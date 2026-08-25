# frozen_string_literal: true

module Collections
  # 單一商品的智慧系列增量重算（第 11 包；13 §F4.6-2）。
  #
  # ①這是什麼：對一個商品，逐一檢查全店有 conditions source 的系列「它現在該不該在裡面」，
  #   diff 物化列（進／出）。觸發鏈＝商品建立/更新/庫存調整的 **outbox 事件** →
  #   `Events::Consumers` 路由 → `Collections::ResyncConsumer` → 本服務。
  #
  # ②🔴 觸發機制的裁定（研究 P11-U17，ours——官方時機未取得 P11-U3）：
  #   走**既有的 outbox 消費者管線**（PRODUCTS_CREATE／PRODUCTS_UPDATE／INVENTORY_ADJUSTED），
  #   不在商品儲存 transaction 內同步重算（鐵律 5：txn 內只寫 outbox 列；且 5000 個
  #   智慧系列的求值不該掛在寫路徑的鎖持有時間上）。代價＝最終一致窗（秒級，
  #   Relay 的輪詢節奏）；本尊自己的 help 也承認 "delay products displaying in
  #   collections on your storefront"（僅搜尋摘要旁證，P11-U3 直取未複驗）。
  #   消費者契約＝冪等（at-least-once 重叫收斂：本服務天生收斂——算的是「現值該不該在」）。
  #
  # ③求值與 rebuild **同一段 SQL**（13 §F4.9）：`RuleCompiler.where_sql` 加 `p.id = ?`
  #   的 EXISTS——不存在 Ruby 端第二套判定。
  #
  # ④併發（研究 §5）：逐系列短 transaction＋`Collection.lock`（與 Rebuild／規則編輯
  #   同一序列化點）⇒ 讀到的規則必然最新已提交；與 Rebuild 交錯無害（同鎖下都收斂）。
  #   ERROR 系列跳過（規則編不了＝rebuild 已標 ERROR，增量不該對著壞規則亂算）。
  class ResyncProduct
    Result = Data.define(:joined, :left, :skipped_error)

    class << self
      # @param shop [Shop]
      # @param product_id [Integer] 商品 id（可能已被刪——刪除＝從所有系列移出）
      # @return [Result]
      # @note 副作用：寫 memberships；變動的系列 bump cache stamp＋發 collections/update。
      def call(shop:, product_id:)
        ActsAsTenant.with_tenant(shop) do
          product = Product.find_by(shop_id: shop.id, id: product_id)
          joined = 0
          left = 0
          skipped = 0

          # 🔴 **拓樸序**（2026-08-26 收斂輪 J3）：exclusion 的 `collection` 型讀被引用
          #   系列的**物化成員** ⇒ 被引用方必須先落定。沿革與兩次錯誤修法：
          #   ①初版無序（G4 發現：A 排除 B 且 A.id < B.id ⇒ A 誤留商品）；
          #   ②第二版 `ids + referencing`（**追加**，H5 發現：A 仍在第一趟先提交一筆
          #     錯誤成員、bump 快取、發事件，第二趟才刪掉再發一則＝雙倍事件＋前台窗口）；
          #   ③第三版 `(ids - referencing) + referencing`（**改序**，J3 發現：修掉了翻轉，
          #     但把「第二次求值機會」也一起拿掉 ⇒ **鏈式**單向引用 A→B→C 時 A 與 B
          #     同落尾段、順序由 pluck 決定，A 讀到完全沒被重算過的 B ⇒ 錯且不自癒）。
          #   ⇒ 正解是**依引用關係做拓樸排序**：被引用的先算。環（A⇄B）無拓樸序，
          #   以穩定順序打破並登記 P11-B10（由 rake 兜底）——環是唯一不保證收斂的形態。
          #   🔴 排序實作在 `Collections::ReferenceGraph`（第六輪 K2）：**三條求值路徑
          #   共用同一份**。第五輪只改了這裡，兜底 rake 仍照 id 序 ⇒ 同一份規則兩支
          #   引擎給不同答案，H4 的根因被重新打開。
          ReferenceGraph.topological(shop, smart_collection_ids(shop, product_id)).each do |collection_id|
            outcome = Collection.transaction do
              collection = Collection.lock.find_by(shop_id: shop.id, id: collection_id)
              next :gone if collection.nil?
              next :error if collection.rebuild_status == "ERROR"

              current = collection

              # 商品已刪 ⇒ 移出（查無主＝從所有系列移出）。ARCHIVED 的排除**下沉到 SQL**
              # （`RuleCompiler::PRODUCT_ELIGIBLE_SQL`，與 Rebuild 同一份字面）——
              # 初版在這裡用 Ruby 擋，而 Rebuild 沒擋，兩支引擎因此對封存商品給出
              # 相反答案（2026-08-26 收斂輪 H4）。UNLISTED **不**移出（前台不可見≠
              # 非成員，13 §F1.2(f)）。
              should_be_member = product.present? && member_by_rules?(shop, collection, product)
              row = CollectionMembership.find_by(shop_id: shop.id, collection_id: collection.id,
                                                 product_id:, variant_id: nil)
              if should_be_member && row.nil?
                CollectionMembership.create!(shop_id: shop.id, collection_id: collection.id,
                                             product_id:, origin: "conditions",
                                             rebuilt_at: Time.current)
                # 🔴 對外面與成員寫入同一個 txn（第八輪 M5，理由見 `Rebuild#rebuild!`）：
                #   放在 txn 外時只要失敗一次就永久遺失——本服務的變更判定是
                #   「這一輪有沒有 diff」，重跑會得到 :noop。
                Rebuild.notify_members_changed!(shop, collection)
                :joined
              elsif !should_be_member && row&.origin == "conditions"
                row.destroy!
                Rebuild.notify_members_changed!(shop, collection)
                :left
              else
                :noop
              end
            rescue RuleCompiler::Unsupported => e
              # 🔴 三條求值路徑必須共用同一份「遇 unknown ⇒ 整系列 ERROR」契約
              #   （2026-08-26 第八輪 M4）：`Rebuild` 的 `compile_all!` 有這道守衛，
              #   本服務沒有 ⇒ 例外直接穿出整個逐系列迴圈，**拓樸序中排在它後面、
              #   與該壞系列毫無關係的系列整批漏算**，且每次重試都在同一點再炸
              #   （事件退避到 dead-letter）⇒ 那些系列的成員永久停在錯值、無自癒。
              #   處置與 Rebuild 一致：標 ERROR、記錄、跳過這一個，其他照算。
              Rebuild.mark_error_for(shop, current, e.message) if current
              :error
            end

            case outcome
            when :joined then joined += 1
            when :left then left += 1
            when :error then skipped += 1
            else next
            end
          end

          Result.new(joined:, left:, skipped_error: skipped)
        end
      end

      private

      # 🔴 工作清單的兩個必要條件（G1 ∧ J7）：
      #   ①**不得**只取「還有 conditions source 的系列」——條件被清空的系列會從所有
      #     清理路徑消失、物化成員永久殘留（G1）；
      #   ②也**不必**每則事件都掃全店每一個智慧系列——那會對零 source 且與本商品
      #     無關的系列白付一次列鎖與求值，而 H3 把庫存事件接活之後這條放大鏈才真正
      #     通電（`max_smart_collections_per_shop` × 每商品的變體×地點事件數，J7）。
      #   ⇒ 取聯集：**有 conditions source 的**（可能要加入）∪ **本商品已有物化列的**
      #     （可能要移出——這一半就是 G1 的自癒面，且用主鍵索引，代價極小）。
      #     兩者都不在 ⇒ 該系列對這個商品構造上不可能有任何變化，跳過是**正確**的，
      #     不是抄捷徑。
      def smart_collection_ids(shop, product_id)
        with_sources = CollectionSource.where(shop_id: shop.id).conditions_type
                                       .joins(:collection).where(collections: { collection_type: "smart" })
                                       .distinct.pluck(:collection_id)
        with_rows = CollectionMembership.where(shop_id: shop.id, product_id:, origin: "conditions")
                                        .distinct.pluck(:collection_id)
        (with_sources | with_rows)
      end

      # 與 rebuild 同一段 WHERE，加 id 等值——SQL-only 的單商品形。
      def member_by_rules?(shop, collection, product)
        sources = CollectionSource.where(shop_id: shop.id, collection_id: collection.id)
                                  .conditions_type.includes(:rules).order(:position)
        sources.any? do |source|
          where_sql = RuleCompiler.where_sql(source)
          next false if where_sql.nil?

          # 🔴 與 `Rebuild#upsert_batch` 同一條紀律（收斂輪 H1／H2）：`where_sql`
          #   **在 sanitize 之後才代入**，商家值裡的 `?` 與內部空白都不得被再解析一次。
          #   資格謂詞也拼同一份字面（H4）⇒ 兩支引擎構造上同一段 WHERE。
          template = "SELECT EXISTS(SELECT 1 FROM products p WHERE p.shop_id = ? AND p.id = ? " \
                     "AND #{RuleCompiler::PRODUCT_ELIGIBLE_SQL} AND (#{Rebuild::WHERE_SLOT}))"
          sql = ActiveRecord::Base.sanitize_sql_array([ template, shop.id, product.id ])
                                  .sub(Rebuild::WHERE_SLOT) { where_sql }
          ActiveRecord::Base.connection.select_value(sql).to_i.positive?
        end
      end
    end
  end
end
