# frozen_string_literal: true

module Types
  module Errors
    # 庫存兩支 mutation 共用的錯誤碼（排程第 17 包；值域出處＝docs/research/95 §4）。
    #
    # 🔴 與本尊的兩處刻意差異：
    #   ① `IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED` **存在於 enum（共用池帶入）但兩線皆永不發出**
    #      （D41：failed＝同 key 重試）。走「池＋註記」而不是逐 enum 剔除——
    #      剔除要改池機制，且 D41 的影響段本就允許註記路線。
    #   ② 兩支共用一個 enum（本尊 Adjust/Set 各一支、值域大量重疊）——我方 admin SPA
    #      是唯一客戶端，共用讓前端錯誤分支只寫一份；per-mutation 特有碼並存於同一 enum
    #      （INVALID_QUANTITY_NAME＝adjust 側、INVALID_NAME＝set 側，觸發條件互斥）。
    class InventoryAdjustUserErrorCode < BaseCodeEnum
      graphql_name "InventoryAdjustUserErrorCode"
      description "inventoryAdjustQuantities／inventorySetQuantities 可能回傳的錯誤碼。"

      # 共用池已含 CHANGE_FROM_QUANTITY_STALE 與 IDEMPOTENCY_*。
      # 🔴 D41 註記：池裡的 IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED **商品線／庫存線皆不發**
      # （failed＝同 key 重試）；它經池進入 enum 是共用池機制，不是庫存線會觸發它。
      from_pools
      own_value :INVALID_REASON, "reason 不在 limits.inventory.adjustment_reasons 的 17 值全集內。"
      own_value :INVALID_QUANTITY_NAME, "adjust 的 name 不可調（committed／incoming 或未知值）。"
      own_value :INVALID_NAME, "set 的 name 只接受 available 或 on_hand。"
      own_value :INVALID_QUANTITY_TOO_HIGH, "數量超過上限（adjust 2e9／set 1e9，兩支不同）。"
      own_value :INVALID_QUANTITY_TOO_LOW, "數量低於下限。"
      own_value :COMPARE_QUANTITY_REQUIRED, "set 必須帶 compareQuantity 或顯式 ignoreCompareQuantity。"
      own_value :COMPARE_QUANTITY_STALE, "set 的 CAS 比對失敗：現值已被他人改動。"
      own_value :INVALID_AVAILABLE_DOCUMENT, "調整 available 時不得帶 ledgerDocumentUri。"
      own_value :INVALID_QUANTITY_DOCUMENT, "調整 available 以外的 name 必須帶 ledgerDocumentUri。"
      own_value :MAX_ONE_LEDGER_DOCUMENT, "同一呼叫的所有 ledgerDocumentUri 必須相同。"
      own_value :IDEMPOTENCY_KEY_ALREADY_USED,
        "此 key 曾在超過保留期（24h）前成功使用過；請換新 key（D44：不靜默 replay 舊結果）。"
      own_value :DUPLICATE_INVENTORY_ITEM, "同一呼叫對同一 (item, location) 出現兩筆 change（V-96.1 fail-closed）。"
    end
  end
end
