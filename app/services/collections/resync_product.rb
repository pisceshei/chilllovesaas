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

          ids = smart_collection_ids(shop)
          # 🔴 引用其他系列的要**再算一次**（2026-08-26 收斂輪 G4）：exclusion 的
          #   `collection` 型讀被引用系列的**物化成員**，而本迴圈無依賴排序 ⇒
          #   A 排除 B 且 A.id < B.id 時（先建 A、後建 B 再加排除，很常見），
          #   第一趟算 A 時商品還沒進 B ⇒ A 誤留該商品；第二趟在 B 落定後重算 A 修正。
          #   互相引用（A 排除 B、B 排除 A）需要不動點迭代，兩趟不保證收斂——
          #   那一格登記在 dev doc §5（P11-B10），由 rake 兜底。
          (ids + collection_ids_referencing_others(shop, ids)).each do |collection_id|
            outcome = Collection.transaction do
              collection = Collection.lock.find_by(shop_id: shop.id, id: collection_id)
              next :gone if collection.nil?
              next :error if collection.rebuild_status == "ERROR"

              # 商品已刪 / ARCHIVED ⇒ 移出（13 §F4.6-5；UNLISTED **不**移出——
              # 它只是前台不可見，成員資格照舊，§F1.2(f)）。
              should_be_member = product.present? && product.status != "archived" &&
                                 member_by_rules?(shop, collection, product)
              row = CollectionMembership.find_by(shop_id: shop.id, collection_id: collection.id,
                                                 product_id:, variant_id: nil)
              if should_be_member && row.nil?
                CollectionMembership.create!(shop_id: shop.id, collection_id: collection.id,
                                             product_id:, origin: "conditions",
                                             rebuilt_at: Time.current)
                :joined
              elsif !should_be_member && row&.origin == "conditions"
                row.destroy!
                :left
              else
                :noop
              end
            end

            case outcome
            when :joined then joined += 1
            when :left then left += 1
            when :error then skipped += 1
            else next
            end
            next if outcome == :error

            collection = Collection.find_by(shop_id: shop.id, id: collection_id)
            Rebuild.notify_members_changed!(shop, collection) if collection
          end

          Result.new(joined:, left:, skipped_error: skipped)
        end
      end

      private

      # 🔴 工作清單＝**全部智慧系列**，不是「還有 conditions source 的系列」
      #   （2026-08-26 收斂輪 G1）：從 `collection_sources` 導出清單的話，條件被清空的
      #   系列會從所有清理路徑的視野裡消失，物化成員永久殘留。零 source 的智慧系列
      #   在 `member_by_rules?` 下對每個商品都回 false ⇒ 本服務會逐一把殘留列移出，
      #   即「自癒」。
      def smart_collection_ids(shop)
        Collection.where(shop_id: shop.id, collection_type: "smart").pluck(:id)
      end

      # 帶 `collection` 型 exclusion 規則的系列（第二趟重算對象）。
      def collection_ids_referencing_others(shop, ids)
        return [] if ids.empty?

        CollectionSourceRule
          .joins(:source)
          .where(shop_id: shop.id, block: "exclusion", condition_type: "collection")
          .where(collection_sources: { collection_id: ids })
          .distinct.pluck("collection_sources.collection_id")
      end

      # 與 rebuild 同一段 WHERE，加 id 等值——SQL-only 的單商品形。
      def member_by_rules?(shop, collection, product)
        sources = CollectionSource.where(shop_id: shop.id, collection_id: collection.id)
                                  .conditions_type.includes(:rules).order(:position)
        sources.any? do |source|
          where_sql = RuleCompiler.where_sql(source)
          next false if where_sql.nil?

          sql = ActiveRecord::Base.sanitize_sql_array(
            [ "SELECT EXISTS(SELECT 1 FROM products p WHERE p.shop_id = ? AND p.id = ? AND (#{where_sql}))",
              shop.id, product.id ]
          )
          ActiveRecord::Base.connection.select_value(sql).to_i.positive?
        end
      end
    end
  end
end
