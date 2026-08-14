# GraphQL schema type 的 namespace。
module Types
  # mutation user error 相關型別的 namespace。
  module Errors
    # `userErrors.code` 的**共用值池**（🔴 這是我方的刻意加嚴，不是本尊慣例）。
    #
    # ## 本尊怎麼做的
    #
    # 本尊是「**一個 UserError object type 對應一個專屬 enum**」——
    # `PageDeleteUserErrorCode` 只有 1 個值、`PageCreateUserErrorCode` 8 值、
    # `PageUpdateUserErrorCode` 9 值，同一個資源的三支 mutation 三個獨立 enum。
    # `/enums/UserErrorCode` 回 **404**，**沒有任何全域 base enum**。
    #
    # 而且本尊各 enum 的值名**並未貫徹**：`SubscriptionDraftErrorCode` 用 `PRESENCE`
    # （「Input value is not present.」）而 `DiscountErrorCode` 用 `PRESENT`
    # （「The input value needs to be blank.」）——**同義不同名，語義甚至相反**；
    # `NOT_FOUND`／`RECORD_NOT_FOUND`／`*_DOES_NOT_EXIST` 三種拼法並存。
    #
    # ## 我方偏離什麼、不偏離什麼
    #
    # - **GraphQL 形狀照抄**：每支 mutation 仍然是一個獨立的 enum type（見 `BaseCodeEnum`）。
    # - **偏離的只有值域紀律**：各 enum 的值必須從下面兩個池 ＋ 該 mutation 專屬碼取。
    #   理由：本尊的分歧是二十年演進的產物、對客戶端是純粹的負擔；我方是新建系統，
    #   沒有相容包袱，而鐵律 4 要求前端能統一處理錯誤分支。
    #
    # @see docs/research/28-api-contract.md §0.3.2、§6
    # @see docs/DECISIONS.md D14 偏離 B
    module CodePools
      # 泛用驗證碼，逐字取自 `docs/research/28` §6 的 `ReturnErrorCode` 全 26 值，
      # **扣掉兩個退貨線專屬碼**（`INCOMPATIBLE_WITH_STANDARD_POLICY`／`NOTIFICATION_FAILED`）。
      #
      # ⚠️ 28 §6 的內文寫「上表中 **20 個**是泛用驗證碼」，但表列 26 值、
      # 標明退貨專屬的只有 2 個 ⇒ **24 才對，20 這個數字與清單對不上**。
      # 本常數以**清單**為準（清單是逐字照抄官方的，數字是我方寫的摘要），
      # 並登記於 `docs/worklog/2026-08-15-mutation寫入地基.md`。
      COMMON = %i[
        ALREADY_EXISTS
        BLANK
        CREATION_FAILED
        EQUAL_TO
        FEATURE_NOT_ENABLED
        GREATER_THAN
        GREATER_THAN_OR_EQUAL_TO
        INCLUSION
        INTERNAL_ERROR
        INVALID
        INVALID_STATE
        LESS_THAN
        LESS_THAN_OR_EQUAL_TO
        MISSING_PERMISSION
        NOT_A_NUMBER
        NOT_EDITABLE
        NOT_FOUND
        PRESENT
        TAKEN
        TOO_BIG
        TOO_LONG
        TOO_MANY_ARGUMENTS
        TOO_SHORT
        WRONG_LENGTH
      ].freeze

      # 併發／樂觀鎖／冪等——🔴 **本輪新開的類別**。
      #
      # 為什麼不能塞進 `COMMON`：那 24 個**全是欄位級輸入驗證**
      # （「這個值太長」「這個值不在清單裡」），而併發衝突講的是
      # 「你看到的狀態已經過期」——它不是輸入錯誤，使用者重送一模一樣的輸入是合理的。
      # 前端對兩者的處置也完全不同：前者標紅欄位，後者要跳「重新載入／覆蓋儲存」。
      #
      # 🔴 **`CONFLICT` 不在這裡，而且永遠不會在**：本尊的 `CONFLICT` 只存在於
      # `DiscountErrorCode`，語義是「折扣屬性選擇互相衝突」的**輸入驗證**，與樂觀鎖無關。
      # `docs/specs/63` §L-3 原本要把它「提升為泛用樂觀鎖碼」，2026-08-15 以**相反方向**結案。
      CONCURRENCY = %i[
        STALE_OBJECT
        CHANGE_FROM_QUANTITY_STALE
        IDEMPOTENCY_CONCURRENT_REQUEST
        IDEMPOTENCY_KEY_PARAMETER_MISMATCH
        IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED
      ].freeze

      # 🔴 這個 token 只准出現在折扣線的 enum 裡（見上方 CONCURRENCY 的說明）。
      # `scripts/check-money-boundary.rb` 之外會另有一條 CI 斷言守住它。
      DISCOUNT_ONLY = %i[CONFLICT].freeze

      # 兩個共用池的聯集，供 `BaseCodeEnum.from_pools` 使用。
      #
      # @return [Array<Symbol>] 去重後的值清單
      # @note 副作用：無。
      def self.shared
        (COMMON + CONCURRENCY).uniq.freeze
      end
    end
  end
end
