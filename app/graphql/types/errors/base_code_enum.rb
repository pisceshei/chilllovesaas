# GraphQL schema type 的 namespace。
module Types
  # mutation user error 相關型別的 namespace。
  module Errors
    # 各 mutation 專屬 `userErrors.code` enum 的基底。
    #
    # 🔴 **GraphQL 形狀照抄本尊**：每支 mutation 一個**獨立的 enum type**
    # （本尊 `PageCreateUserErrorCode` / `PageUpdateUserErrorCode` / `PageDeleteUserErrorCode`
    # 是三個不同的 type，值數還不一樣）。本類別**不是**共用 enum，它只是產生器。
    #
    # 用法：
    #
    #     class Types::Errors::ProductCreateUserErrorCode < Types::Errors::BaseCodeEnum
    #       graphql_name "ProductCreateUserErrorCode"
    #       from_pools                      # 共用池（COMMON ＋ CONCURRENCY）
    #       own_value :HANDLE_TAKEN, "handle 已被同店其他商品使用"
    #     end
    #
    # @see docs/research/28-api-contract.md §0.3.2
    # @see docs/DECISIONS.md D14 偏離 B
    class BaseCodeEnum < GraphQL::Schema::Enum
      # 值的中文說明。缺說明的值一律 raise——**schema 是給人讀的**，
      # 一個沒有 description 的錯誤碼，前端只能猜它是什麼意思。
      DESCRIPTIONS = {
        ALREADY_EXISTS: "已存在",
        BLANK: "不得為空白",
        CREATION_FAILED: "建立失敗",
        EQUAL_TO: "必須等於指定值",
        FEATURE_NOT_ENABLED: "功能未啟用",
        GREATER_THAN: "必須大於指定值",
        GREATER_THAN_OR_EQUAL_TO: "必須大於或等於指定值",
        INCLUSION: "不在允許的值域內",
        INTERNAL_ERROR: "內部錯誤",
        INVALID: "無效",
        INVALID_STATE: "狀態不符——狀態機違規的統一碼（28 §6，全專案沿用）",
        LESS_THAN: "必須小於指定值",
        LESS_THAN_OR_EQUAL_TO: "必須小於或等於指定值",
        MISSING_PERMISSION: "缺少權限",
        NOT_A_NUMBER: "不是數字",
        NOT_EDITABLE: "不可編輯",
        NOT_FOUND: "找不到",
        PRESENT: "必須為空",
        TAKEN: "已被佔用",
        TOO_BIG: "值過大",
        TOO_LONG: "過長",
        TOO_MANY_ARGUMENTS: "參數過多",
        TOO_SHORT: "過短",
        WRONG_LENGTH: "長度錯誤",
        STALE_OBJECT: "你看到的版本已過期——他人已修改此資源（樂觀鎖，63 §A.4）",
        CHANGE_FROM_QUANTITY_STALE: "庫存的比較基準值已過期（CAS 不符，63 §E.5）",
        IDEMPOTENCY_CONCURRENT_REQUEST: "同一把冪等鍵有另一個請求正在處理中",
        IDEMPOTENCY_KEY_PARAMETER_MISMATCH: "同一把冪等鍵被用於不同的參數",
        IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED: "同一把冪等鍵的前一次嘗試已失敗",
        CONFLICT: "折扣屬性選擇互相衝突（🔴 折扣線專屬，不是樂觀鎖碼）"
      }.freeze

      class << self
        # 從共用值池宣告全部值。
        #
        # @param pools [Array<Symbol>] 要納入的池，預設兩個共用池
        # @return [void]
        # @raise [KeyError] 池裡有值缺 `DESCRIPTIONS` 條目時拋出
        # @note 副作用：在本 enum 類別上定義 GraphQL 值。
        def from_pools(pools = Types::Errors::CodePools.shared)
          pools.each { |token| declare(token) }
        end

        # 宣告一個本 mutation 專屬的碼。
        #
        # @param token [Symbol] 大寫底線的碼
        # @param description [String] 中文說明
        # @return [void]
        # @note 副作用：在本 enum 類別上定義一個 GraphQL 值。
        def own_value(token, description)
          value token.to_s, description, value: token.to_s
        end

        private

        def declare(token)
          value token.to_s, DESCRIPTIONS.fetch(token), value: token.to_s
        end
      end
    end
  end
end
