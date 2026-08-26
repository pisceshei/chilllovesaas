# frozen_string_literal: true

module Publications
  # 建立 Publishable 的發布列（`resource_publications`）。
  #
  # 🔴 **這個服務存在的理由**：`resource_publications` 這張表自 2026-08-14 建立以來，
  # 倉庫裡**沒有任何一行程式碼會建立它的列**（`docs/specs/88` §5 待辦 #2 明文延後）。
  # 缺席的是**寫入端**，所以它的症狀是靜默的：三層 AND 的第二層永遠不成立
  # ⇒ 一旦讀取面打開（`Product.purchasable`），全站商品瞬間全部變成不可購買，
  # 而近千支 spec 仍然全綠——因為沒有任何一支斷言過「新商品必須有發布列」。
  # （線上實測 2026-08-26：正式環境 `resource_publications` 共 **0** 列。）
  #
  # ## 規則出處：本尊實測，不是我方裁定
  #
  # 全部證據＝`docs/research/82-admin-channels.md` §8（2026-08-26，測試店 chill-love-u5q5mnzq）。
  # 三條直接寫成程式碼的：
  #
  # 1. **建立後即在全部 auto_publish 管道上「已發布」**（82 §8.4①）：
  #    新增商品表單在存檔前就顯示 `All channels`，存檔後預設變體 `channelPublicationCount = 3`。
  #    ⚠️ **2026-08-26 更正**：這一條**只斷言可觀測的那一半**。原本寫成
  #    「本尊在建立當下就**寫列**」——那是把不可觀測的推論當成本尊事實。
  #    從 admin UI 與 Admin API **都分不出**「建立時寫列」與「讀取時以 auto_publish 展開」
  #    （兩者的 `resourcePublications` 回應完全一樣）。
  #    🔴 ⇒ **稠密物化是我方裁定（ours）**，見下方「為什麼我方選稠密物化」。
  # 2. **變體有自己的、與父商品不同的發布集合**（82 §8.2）：
  #    未被觸碰過的變體回傳 3 個管道並逐一具名，且商品層取消發布後變體層原封不動（82 §8.4③）
  #    ⇒ 變體不是「繼承父層」，它是獨立的一層。
  # 3. **變體跟的是「全部 auto_publish 的 publication」，不是父商品的集合**（82 §8.4②）。
  #    ⚠️ 這一條也是**我方裁定（ours）**，證據三方拉扯，全文見 `docs/dev/m2-publication-model.md` §4。
  #
  # ## 🔴 為什麼我方選稠密物化（ours，不是照抄）
  #
  # 本尊的**儲存形態未取得**（上面第 1 條），所以這是我方的選擇，理由是後果不是權威：
  #   ①**讀取端簡單且可索引**：`Product.published_on` 的兩個 EXISTS 走
  #     `uq_res_pub_target` 複合索引；若改成「讀取時展開 auto_publish」，
  #     「這個商品在這個管道發布了嗎」就變成「有沒有明確的**取消**列」的反向查詢，
  #     而那是對可空謂詞取反——第 11 包在三值邏輯上踩過三次的形態。
  #   ②**每一層的意圖都保留得住**：商品層開開關關不會損失變體層的設定（82 §8.4③ 的本尊行為）。
  #   ③v1 每店只有一個 publication，列數＝資源數，成本可忽略。
  # ⚠️ **代價**：寫入是 O(publishable × publication)。管道數長到 5 以上時
  #    `after_create` 的成本會變成主導項（實測數字見 `docs/specs/91-pit-register.md` §3.18）。
  #
  # ## 兩條寫入路徑，**規則只有一份**
  #
  # `.for`（逐筆、走 validation）與 `.backfill_all!`（批量、`insert_all`）是**兩種寫入機制**；
  # 但「哪些管道要建」與「還缺哪些配對」這兩條**規則**由 `auto_publish_publication_ids`
  # 與 `missing_pairs` **各自唯一產生**，兩條路徑共用（鐵律 7）。
  #
  # 🔴 **2026-08-26 修正（對抗審查）**：原本回填邏輯是**抄一份**寫在 migration 裡，
  # 而 migration 的 spec 又抄了第三份 ⇒ **規則有三份實作，而測試守的是它自己那一份**。
  # 兩位審查員以不同方法各自實測證明了危害：把 migration 的 `where(shop_id:)` 刪掉一個
  # token，回填就寫出跨租戶的列（`insert_all` 繞過 validation、多型欄位又無外鍵，兩層都不擋），
  # 而 spec 仍然 38 examples 0 failures；把 `auto_publish: true` 拿掉同樣全綠。
  # ⇒ 收斂成一份，且 spec 改成**載入並執行真的 migration 類別**。
  module Materialize
    # 回填時每批取幾個 publishable。單次 `insert_all` 的列數＝本值 × 該店管道數。
    # （伺服器實測 2026-08-26：MySQL 8.4.9 `max_allowed_packet = 67108864`，
    #  每列 SQL 約 120 bytes ⇒ 單店要約 550 個管道才逼近上限。）
    BACKFILL_BATCH = 1_000

    module_function

    # 對 `publishable` 補齊所有 `auto_publish` 管道的發布列。
    #
    # **冪等**：已存在的列一律不動（不改 `published_at`）。
    #
    # @param publishable [Product, ProductVariant, Collection] 目標資源
    # @param at [Time] 發布時點，預設現在
    # @return [Integer] 本次**新建**的列數（已存在者不計）
    # @raise [ArgumentError] `publishable` 的類別不在 `ResourcePublication::PUBLISHABLE_TYPES` 內
    # @note 副作用：對 `resource_publications` 做 INSERT。**不開 transaction**——
    #   本方法設計成在呼叫端的 transaction 內執行（`after_create` 即在建立的 transaction 內），
    #   無任何外部 IO（鐵律 5）。
    def for(publishable, at: Time.current)
      type = publishable.class.name

      # 🔴 **未知型別一律 raise，不得靜默回 0**（2026-08-26 對抗審查）。
      #   `ResourcePublication` 本身有 `validates :publishable_type, inclusion:`，
      #   也就是型別不對時**本來就會炸**；在這裡先 `return 0` 等於把一個 fail-closed
      #   的驗證降級成靜默成功。
      #   具體危害：日後某包新增第四個 Publishable（例如 `Page`），照抄
      #   `after_create :materialize_publications` 但忘了把 `"Page"` 加進
      #   `PUBLISHABLE_TYPES` ⇒ 每個 Page 都建不出發布列、前台全部看不到、
      #   **不拋任何錯、沒有任何 spec 會紅**（三個 caller 都不看回傳值）。
      #   本方法的三個 caller 全是 model callback，callback 的契約是
      #   「出錯要炸掉整個 create 交易」，不是「回一個沒人看的 0」。
      unless ResourcePublication::PUBLISHABLE_TYPES.include?(type)
        raise ArgumentError,
          "#{type} 不是 Publishable（合法值：#{ResourcePublication::PUBLISHABLE_TYPES.join('／')}）"
      end

      shop_id = publishable.shop_id
      return 0 if shop_id.nil? || publishable.id.nil?

      publication_ids = auto_publish_publication_ids(shop_id)
      pairs = missing_pairs(shop_id:, type:, publishable_ids: [ publishable.id ], publication_ids:)
      return 0 if pairs.empty?

      # 🔴 逐筆 `create!` 而非 `insert_all`：這條路徑處理的是**外部輸入建立的資源**，
      #   必須經過 `ResourcePublication` 的全部 validation（尤其
      #   `publishable_belongs_to_same_shop`——多型關聯拿不到 DB 外鍵，那是唯一的防線）。
      #   回填路徑的不對稱與其理由見 `.backfill_all!`。
      ActsAsTenant.without_tenant do
        pairs.each do |publishable_id, publication_id|
          ResourcePublication.create!(
            shop_id:, publication_id:,
            publishable_type: type, publishable_id:, published_at: at
          )
        end

        bump_publications_stamp!(shop_id:, type:, publishable:, at:)
      end

      pairs.size
    end

    # 補齊**既有**的 Product／ProductVariant／Collection（回填用）。
    #
    # 🔴 **callback 修未來、本方法修歷史，兩半缺一等於沒修**——與 `88` §5 #1
    # （建店預設 publication）是同一條教訓，那次也是兩半。
    #
    # **冪等**：重跑只補缺的列。
    #
    # @param at [Time] 發布時點
    # @return [Integer] 本次新建的列數
    # @note 副作用：對 `resource_publications` 做批量 INSERT。
    #   唯一呼叫端＝`db/migrate/20260826060000_backfill_resource_publications.rb`。
    def backfill_all!(at: Time.current)
      created = 0

      # 🔴 **`without_tenant` 在這裡是承重的，不是防禦性寫法。**
      #   下面每一個查詢都走**帶 default scope** 的關聯（刻意不寫 `.unscoped`），
      #   而 `config/initializers/acts_as_tenant.rb` 設 `require_tenant = true`
      #   ⇒ 沒有 current_tenant 時 default scope 直接 raise `NoTenantSet`。
      #   migration 跑在 `bin/rails db:migrate`，那裡**沒有** current_tenant。
      #
      #   ⚠️ **2026-08-26 更正（對抗審查證偽）**：本檔與 migration 的前一版註釋宣稱
      #   「拿掉 `without_tenant` ⇒ 正式環境只要有既有商品就 `NoTenantSet`」，
      #   當時是**錯的**——前一版的讀取全走 `.unscoped`（`unscoped` 連 default scope 的
      #   raise 一起拿掉）、寫入全走 `insert_all`（不經 model），所以拿掉 `without_tenant`
      #   照樣跑完。那句因果是從第 11 包 `20260826058000` 誤植過來的，該包成立、本支不成立。
      #   ⇒ 本版**刻意移除 `.unscoped`**，讓 `without_tenant` 真正承重，
      #   並由 `spec/migrations/p12_backfill_publications_spec.rb` 的行為測試（跑真 migration）
      #   守住——不再依賴掃字串的 source-guard（那種守衛可以被一行註釋騙過，實測已證）。
      ActsAsTenant.without_tenant do
        # 逐店處理：`auto_publish` 的管道集合是**每店各自**的。
        Publication.where(auto_publish: true).order(:shop_id, :id)
                   .pluck(:shop_id, :id).group_by(&:first).each do |shop_id, rows|
          publication_ids = rows.map(&:last)

          publishable_scopes.each do |type, klass|
            # 🔴 `where(shop_id:)` 不可省——它是這條路徑的**唯一**租戶防線。
            #   `insert_all` 繞過 validation（含 `publishable_belongs_to_same_shop`），
            #   而 MySQL 對多型欄位無法建外鍵 ⇒ 少了這個條件就會寫出
            #   「shop_id 是 A、publishable 屬於 B」的列，沒有任何一層會擋。
            #   對抗審查實測過該突變：`mismatched=2`，而舊 spec 仍然全綠。
            klass.where(shop_id:).select(:id).find_in_batches(batch_size: BACKFILL_BATCH) do |batch|
              pairs = missing_pairs(shop_id:, type:, publishable_ids: batch.map(&:id), publication_ids:)
              next if pairs.empty?

              now = Time.current
              rows_to_insert = pairs.map do |publishable_id, publication_id|
                {
                  shop_id:, publication_id:,
                  publishable_type: type, publishable_id:,
                  published_at: at, created_at: now, updated_at: now
                }
              end

              # 🔴 這裡用 `insert_all` 而 `.for` 用 `create!`，是**刻意的不對稱**：
              #   `insert_all` 繞過 validation，在一般寫入路徑上那是漏洞——但這裡的
              #   `publishable_id` 是**從同一個 shop_id 的表裡查出來的**（上一行的
              #   `where(shop_id:)`），租戶歸屬由查詢本身保證，不依賴 validation。
              #   換來的是既有資料量下可接受的回填時間。
              #   ⚠️ 任何人把這段複製到**非回填**的路徑，那個保證就不存在了。
              ResourcePublication.insert_all(rows_to_insert)
              created += rows_to_insert.size
            end
          end
        end
      end

      created
    end

    # 把 `products.publications_updated_at` 推到 `at`（cache stamp）。
    #
    # 🔴 **這個欄位的寫入者由 `db/schema.rb` 的欄位註釋逐字指名「隨第 12 包」**，
    # 且 `config/limits.yml` 的 `cache_stamp_sources` 已把它列為正典
    # ⇒ 正典宣告與實作不符就是鐵律 19 要防的形態。第 12 包初版沒交付（理由是零讀取者），
    # 第二輪對抗審查指出：**正典已經宣告了，就不能用「還沒有人讀」當理由不寫**。
    #
    # **哪些變動要 bump**：
    #   - `Product` 自己的發布列變動 ⇒ bump 它自己
    #   - `ProductVariant` 的發布列變動 ⇒ bump **父商品**（變體發布狀態會改變商品的
    #     有效可購買性，見 `Product.published_on` 的第二個 EXISTS）
    #   - `Collection` ⇒ **不 bump**：`collections` 表沒有這個欄位，
    #     系列自己的成員集合戳是 `products_updated_at`（第 3 包），語義不同，不得挪用。
    #
    # 🔴 實際的 UPDATE 在 `Product.bump_publications_stamp!`——那裡有一段
    # **不得動 `lock_version`** 的說明，理由是實測踩到的：`update_all` 的 hash 形式
    # 會替啟用樂觀鎖的 model 自動遞增鎖版本，於是「建立發布列」會把商家手上開著的
    # 商品編輯表單直接作廢（`StaleObjectError`），而商家什麼都沒做。
    #
    # @return [void]
    # @note 副作用：對 `products` 做一次 UPDATE（Collection 時為 no-op）。
    def bump_publications_stamp!(shop_id:, type:, publishable:, at:)
      product_id =
        case type
        when "Product" then publishable.id
        when "ProductVariant" then publishable.product_id
        end
      return if product_id.nil?

      Product.bump_publications_stamp!(shop_id:, id: product_id, at:)
    end

    # 該店所有「新資源要自動納入」的管道。**規則的唯一產生處**（鐵律 7）。
    #
    # 🔴 本尊 `Publication.autoPublish` 的官方語義逐字（shopify.dev，取證 2026-08-26）：
    #   "Whether new products are automatically published to this publication."
    #
    # @param shop_id [Integer]
    # @return [Array<Integer>] publication id，依 id 排序（讓兩條寫入路徑順序一致）
    def auto_publish_publication_ids(shop_id)
      ActsAsTenant.without_tenant do
        Publication.where(shop_id:, auto_publish: true).order(:id).pluck(:id)
      end
    end

    # 這批 publishable × 這批管道之中，**還沒有列**的配對。**規則的唯一產生處**。
    #
    # @return [Array<Array(Integer, Integer)>] `[publishable_id, publication_id]`
    def missing_pairs(shop_id:, type:, publishable_ids:, publication_ids:)
      return [] if publishable_ids.empty? || publication_ids.empty?

      existing = ActsAsTenant.without_tenant do
        ResourcePublication.where(
          shop_id:, publishable_type: type,
          publishable_id: publishable_ids, publication_id: publication_ids
        ).pluck(:publishable_id, :publication_id)
      end.to_set

      publishable_ids.flat_map do |publishable_id|
        publication_ids.filter_map do |publication_id|
          pair = [ publishable_id, publication_id ]
          pair unless existing.include?(pair)
        end
      end
    end

    # 回填要掃的三張表。鍵＝`publishable_type` 的字面值。
    #
    # 🔴 由 `ResourcePublication::PUBLISHABLE_TYPES` 導出，**不另寫一份清單**——
    #   兩份會在新增第四個 Publishable 時分岔，而分岔的症狀是「回填漏掉一種型別」，
    #   同樣不拋錯。
    def publishable_scopes
      ResourcePublication::PUBLISHABLE_TYPES.to_h { |type| [ type, type.constantize ] }
    end
  end
end
