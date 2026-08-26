# frozen_string_literal: true

module Publications
  # 建立 Publishable 的發布列（`resource_publications`）。
  #
  # 🔴 **這個服務存在的理由**：`resource_publications` 這張表自 2026-08-14 建立以來，
  # 倉庫裡**沒有任何一行程式碼會建立它的列**（`docs/specs/88` §5 待辦 #2 明文延後）。
  # 缺席的是**寫入端**，所以它的症狀是靜默的：三層 AND 的第二層永遠不成立
  # ⇒ 一旦讀取面打開（`Product.purchasable`），全站商品瞬間全部變成不可購買，
  # 而近千支 spec 仍然全綠——因為沒有任何一支斷言過「新商品必須有發布列」。
  #
  # ## 規則出處：本尊實測，不是我方裁定
  #
  # 全部證據＝`docs/research/82-admin-channels.md` §8（2026-08-26，測試店 chill-love-u5q5mnzq）。
  # 三條直接寫成程式碼的：
  #
  # 1. **建立當下就物化，不是第一次讀取時 lazy 建**（82 §8.4①）：
  #    新增商品表單在存檔前就顯示 `All channels`，存檔後預設變體即有 3 列。
  # 2. **稠密，不是「無列＝繼承父層」**（82 §8.2）：
  #    未被觸碰過的變體回傳 3 列並逐一具名——若是繼承模型應該回 0 列。
  # 3. 🔴 **變體跟的是「全部 auto_publish 的 publication」，不是父商品的集合**（82 §8.4②）：
  #    實測條件刻意做成父子不一致——父商品當時是 Unlisted 且**只發布到 2 個管道**，
  #    在該狀態下新增的兩個變體各自拿到 **3 個管道**，含父商品自己都沒有的 Point of Sale。
  #
  # @see docs/plans/2026-08-26-第12包執行規格.md §2.1
  # @see docs/research/82-admin-channels.md §8.4
  module Materialize
    module_function

    # 對 `publishable` 補齊所有 `auto_publish` 管道的發布列。
    #
    # **冪等**：已存在的列一律不動（不改 `published_at`）。重跑安全，
    # 這也是回填 migration 能與 callback 共用同一支實作的前提。
    #
    # @param publishable [Product, ProductVariant, Collection] 目標資源
    # @param at [Time] 發布時點，預設現在
    # @return [Integer] 本次**新建**的列數（已存在者不計）
    # @note 副作用：對 `resource_publications` 做 INSERT。**不開 transaction**——
    #   本方法設計成在呼叫端的 transaction 內執行（`after_create` 即在建立的 transaction 內），
    #   無任何外部 IO（鐵律 5）。
    def for(publishable, at: Time.current)
      shop_id = publishable.shop_id
      return 0 if shop_id.nil? || publishable.id.nil?

      type = publishable.class.name
      return 0 unless ResourcePublication::PUBLISHABLE_TYPES.include?(type)

      # 🔴 **整段跑在 `without_tenant` 內，而 shop_id 一律取自 `publishable` 本身。**
      #
      # 不是為了繞過隔離，是因為**環境租戶不可靠而記錄本身可靠**：
      #   - `after_create` 會在 seeds、factory、rake、資料 migration 底下被觸發，
      #     那些路徑**沒有 current_tenant** ⇒ 帶 default scope 查 `Publication` 直接
      #     `NoTenantSet`，而它炸的位置在「建立商品」而不是「建立管道」，極難歸因；
      #   - 反過來，若 current_tenant 是**別間店**（測試 setup 常見），
      #     default scope 會把管道過濾成 0 列 ⇒ **一列都不建、而且不拋任何錯**。
      #     那是「回報成功但什麼都沒做」的形態，比直接炸危險得多。
      #
      # 🔴 隔離沒有變弱：`shop_id` 來自 `publishable`，兩邊的查詢與寫入都**逐句明帶
      # `shop_id` 條件**（鐵律 2 配套條款②：豁免的是「表有沒有欄」，不是「查詢帶不帶條件」）。
      #
      # ⚠️ 這正是第 11 包部署事故的同一家族：`20260826058000` 的回填在 CI（空庫）與
      # 開發庫都不執行迴圈本體，只有正式環境炸 `NoTenantSet`。
      # 教訓是**不要讓寫入路徑依賴環境租戶**，不是「記得先設租戶」。
      ActsAsTenant.without_tenant do
        publication_ids = Publication.where(shop_id:, auto_publish: true).order(:id).pluck(:id)
        return 0 if publication_ids.empty?

        existing = ResourcePublication.where(
          shop_id:, publishable_type: type, publishable_id: publishable.id,
          publication_id: publication_ids
        ).pluck(:publication_id).to_set

        (publication_ids - existing.to_a).sum do |publication_id|
          ResourcePublication.create!(
            shop_id:, publication_id:,
            publishable_type: type, publishable_id: publishable.id,
            published_at: at
          )
          1
        end
      end
    end
  end
end
