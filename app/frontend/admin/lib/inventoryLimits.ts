/**
 * 前端鏡射的庫存值域（鐵律 6 的前端側）。
 *
 * 🔴 **這是鏡射，不是第二個真相**：正典是 `config/limits.yml` 的
 * `inventory.adjustment_reasons_manual_ui`（UI 手動下拉的 7 值子集，順序即 UI 順序、
 * 第一項為預設）。改 limits 必須同步改這裡——與 `api/pagination.ts` 同一個已知形態。
 *
 * 為什麼不從伺服器拿：這七個值是**編譯期常量級**的 UI 值域，為它多打一次網路
 * （或塞進每個查詢的 payload）換來的只是「理論上不會漂移」；而漂移的實際防線是
 * 後端 `InventoryAdjustmentGroup::REASONS` 的 inclusion 驗證——
 * 前端送了不在清單裡的值，伺服器會回 `INVALID_REASON`，不會靜默寫入。
 *
 * 值域出處：`docs/research/95` §3（API 17 值 vs UI 7 值兩個投影）
 * ＋ 實機 `docs/research/94` §2.4（下拉逐項）。
 */
export const ADJUSTMENT_REASONS_MANUAL_UI = [
  "correction",
  "cycle_count_available",
  "received",
  "restock",
  "damaged",
  "shrinkage",
  "promotion",
] as const;

/**
 * reason 識別字 → Activity 顯示標籤的 i18n key 前綴。
 *
 * 歷程頁的 Activity 欄不是 reason 識別字而是標籤（對照表＝總裁定 §四b）；
 * 標籤在 `messages/*.json` 的 `inventory.activity.<reason>`，
 * 下拉選項在 `inventory.reason.<reason>`——**兩組刻意分開**：
 * 下拉是動詞式的短標（「已收件」），歷程是事件式的敘述（「Inventory received」）。
 */
export const ACTIVITY_KEY_PREFIX = "inventory.activity." as const;

/**
 * 調整記錄的保留天數（顯示用）。
 *
 * 🔴 正典＝`config/limits.yml` 的 `inventory.adjustment_history_retention_days`
 * （後端 `Inventory::HistoryQuery` 用它裁窗）。這裡鏡射它**只為了畫那句說明文案**——
 * 原本 180 這個數字被寫死在五份語言包裡，改 limits 時五個檔案都不會跟著動，
 * 而畫面會理直氣壯地寫著一個與實際窗口不符的天數。
 */
export const ADJUSTMENT_HISTORY_RETENTION_DAYS = 180;
