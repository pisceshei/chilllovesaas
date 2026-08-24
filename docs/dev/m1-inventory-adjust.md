# m1 — 庫存唯一寫入入口（排程第 17 包）

> 依據：`docs/plans/2026-08-24-庫存ledger形狀總裁定.md`；D41–D43；G28；`docs/research/95` §3–§5。
> 四件事（鐵律 12.4）逐項寫在各檔頭；本文是跨檔的對接圖。

## 1. 這是什麼

```
GraphQL inventoryAdjustQuantities / inventorySetQuantities
   │  idempotencyKey: String!（G28 加嚴）＋ authorize（D42 inventory.edit）
   ▼
Inventory::Adjust.call(mode: "adjust"|"set")     ← 唯一寫入入口（cop 強制）
   │  驗證全收集 → Idempotency::Guard.with（claim/replay）
   ▼
transaction { FOR UPDATE 鎖 levels（ORDER BY id）→ CAS → group＋子行＋現值更新 }
```

## 2. 值域與規則（全部引 limits／95 號，逐條有測試）

| 規則 | 出處 |
|---|---|
| reason ∈ 17 值全集（UI 只露 7 值子集） | 95 §3；`limits.inventory.adjustment_reasons` |
| adjust 可調 name＝available/on_hand/reserved/damaged/safety_stock/quality_control；**committed 與 incoming 不可調** | 95 §2（committed 由訂單線獨佔） |
| set 只收 available/on_hand | 本尊 InventorySetQuantitiesInput 明文 |
| on_hand 寫入＝翻譯成 available 的 delta | 總裁定 §2.3 |
| adjust 邊界 ±2e9；set 邊界 ±1e9（**兩支不同**） | 95 §5 |
| ledgerDocumentUri：available 不得帶／其他必帶／禁 gid://shopify/*／同呼叫必須相同 | 95 §4 四條 |
| 同呼叫重複 (item, location) ⇒ DUPLICATE_INVENTORY_ITEM | V-96.1 fail-closed |
| set 的 CAS 必須表態（compareQuantity 或顯式 ignore） | 本尊 COMPARE_QUANTITY_REQUIRED |
| failed ⇒ 同 key 重試；IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED 永不發 | D41 |

## 3. 三道防漂移機制（各自的突變驗證都做了）

1. **cop `Chilllove/InventoryDirectWrite`**（D43 無豁免口；唯一 Exclude＝入口自己）：
   擋 ledger 列直建與 quantity 欄直寫。突變驗證＝cop_probe 兩個違規都被抓、非庫存放行。
   ⚠️ 已知盲區：`update_all`、`assign_attributes`+`save`、裸 SQL——cop 是第一道不是唯一一道，
   後兩道（DB generated column、nightly 對帳）各補一種形態。
2. **STORED GENERATED**（第 16 包）：on_hand/unavailable 想雙寫也寫不進去。
3. **`Inventory::Reconcile`＋`rake inventory:reconcile`**：七式（六 leaf SUM ＋ changes_count）。
   🔴 前提＝所有變動走過入口；歷史直寫會被如實回報——那是它存在的理由。

## 4. 跨功能影響

- 第 18 包（庫存 UI）：行內調整器的 Set to/Adjust by 直接打這兩支 mutation；
  歷程頁一列＝一 group，Activity 標籤對照＝總裁定 §四b。
- 第 19 包（事件）：本包**刻意不發事件**，outbox 掛載點在 `Inventory::Adjust#apply!` 交易內。
- changes 投影（`InventoryAdjustmentGroupType#changes`）＝本尊語義：調 available 回
  available＋on_hand 兩筆；儲存一列、讀取展開。
- `changeFromQuantity` 的 `required: :nullable` 加嚴**不在本包**（G28 只批了 idempotencyKey）。

## 5. 已知邊界

- Move mutation（跨地點/跨狀態移動）**明文延後**——UI 的行內調整器只用 adjust/set；
  Move 屬轉移線（transfers）落地輪。
- `quantityAfterChange`（running-sum）讀取欄位屬第 18 包歷程頁。
- staff 歸因只記 `staff_member_id`＋`client_source`；app_id 等 M5（V-96.2）。
