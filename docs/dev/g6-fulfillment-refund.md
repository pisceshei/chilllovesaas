# G6-8（步 5）：履約與退款線

> 研究＝ord-0～ord-4（步 5 交接 §5 資產表＋本包缺口補查）；UI 實測＝
> `docs/research/88-admin-orders-live-teardown.md` §3（分裂鈕）／§4（退款頁）；
> 規格正典＝`docs/specs/16-spec-orders-fulfillment-refunds.md` §F3／§F5。
> 官方取證日 2026-09-01，版本錨＝Admin GraphQL `2026-07`。

---

## §1 這是什麼

訂單線的第三塊：**出貨**（fulfillmentCreate／fulfillmentTrackingInfoUpdate／
fulfillmentCancel）與**退款**（refundCreate＋Order.suggestedRefund）。
四支 mutation ＋ 一個預覽欄位 ＋ admin 詳情頁出貨卡 ＋ 退款頁。

### 模型（M0 表全在，本包補 model 與服務）

| 表 | model | v1 語義 |
|---|---|---|
| `fulfillment_orders` | `FulfillmentOrder` | **每單一張**（單地點；location＝priority 最高）。建單即物化（`CreateFromCheckout#materialize_fulfillment_order!`）＋migration 20260901010000 回填既有單 |
| `fulfillments` | `Fulfillment` | 實際包裹。status＝success/cancelled（官方 4 值去 3PL 專屬）；行項明細在 `line_items_snapshot` json（migration 20260901020000；本尊是 FulfillmentLineItem 子表，v1 json 快照） |
| `refunds` | `Refund` | 業務決議列；金流終態 pending/success/failure（PSP 對映見 §5） |
| `refund_line_items` | `RefundLineItem` | restock_type＝no_restock/cancel/return（官方 enum 去 deprecated 的 LEGacy_RESTOCK——官方逐字「This value is not accepted when creating new refunds.」） |
| `orders` ＋2 欄 | — | `captured_total_cents`／`refunded_total_cents`＝16 §F5.1 條件式 UPDATE 的物化載體（migration 20260901010000 回填） |

## §2 🔴 退款軟上限（16 §F5.1 全契約的落地）

- 上限檢查與累計寫入在**同一條 SQL**（`Refunds::Create.apply_cumulative_cap!`）；
  `affected==0` 重讀**只做分類**：超限 ⇒ `REFUND_EXCEEDS_MAXIMUM_REFUNDABLE`／
  併發 ⇒ `REFUND_CONCURRENT_MODIFIED`（兩碼分開回——limits.refund 正典鍵）。
- 超額路徑**仍是條件式 UPDATE**（上界換 `captured + amount`），需
  `orders.over_refund` 權限（mutation 層驗；`refund_create_permission_spec` 釘）。
- **不做 DB CHECK**（16 §F5.1(e)）。
- ⚠️ **order lock 已把同單退款序列化** ⇒ 條件式 UPDATE 是序列化後的守衛＋
  未持鎖路徑的縱深防禦（併發 spec 檔頭有 gate 版死鎖實錄）。
- 🔴 **入帳路徑必須遞增 captured**：本包補了 `MarkAsPaid`／`MarkPaidFromPsp`
  兩處（步 4 交付時漏掉——沒有它退款上限恆 0；`mark_as_paid_captured_spec` 釘）。

## §3 🔴 金額計算（鐵律 7＋鐵律 3）

`Refunds::Calculator` 是唯一產生處——`Order.suggestedRefund`（預覽）與
`Refunds::Create`（實退）都呼叫它（16 §F5.1「預覽與實退對不上就是 bug」）。

- 分攤＝**最大餘數法**（訂單級 discount/tax 按行 total 分攤；Σ == 原始總額）。
- 多次部分退款＝**per-unit 游標**：行分攤額按單位切（前 remainder 個各多 1 分），
  第 n 次退款取第 [已退量, 已退量+本次量) 個單位的和 ⇒ 全退完 Σ 精確無殘差
  （`calculator_spec` K2 手算釘死）。
- v1 缺項（無資料來源，非遺漏）：restocking fee／換貨扣抵／outstanding。
- 運費：`fullRefund`＝退剩餘可退運費；指定額超過剩餘 ⇒ INVALID。
  ⚠️ 「訂單層級免運折扣 ⇒ 運費完全不可退」（16 §F5.1）v1 無免運折扣概念，
  無從判定——登記缺口，折扣線落地時補。

## §4 出貨與庫存（D43 邊界）

- 出貨＝`committed−`；取消出貨＝`committed+`；restock cancel＝`committed− available+`；
  restock return＝`available+`。全部是**訂單線的字串條件式 UPDATE**
  （`CreateFromCheckout` 同形先例；`Inventory::Adjust` 檔頭明文「committed 由
  訂單線獨佔」）——**不產 ledger 列**（訂單事件的庫存後果不是 adjustment；
  本尊是否為 restock 記 ledger＝未取證，登記）。
- 行項扣減＝條件式 UPDATE（`fulfillable_quantity >= q` 進 WHERE）⇒ 併發超量
  affected 0 整批 rollback。
- `Orders::FulfillmentStatus`＝rollup 唯一推導器（Solidus OrderUpdater 同構）；
  display 值域擴 in_progress/on_hold（SCHEDULED 無寫入入口不出值——enum 檔頭紀律）。

## §5 PSP 退款（Airwallex）

- 端點 `POST /api/v1/pa/refunds/create`（官方取證 2026-09-01）：`request_id` 必填
  ≤64（＝我方 refund 冪等鍵）、`payment_intent_id`、`amount`（number，與
  payment_intents 同一格式體系）、`reason` ≤128。
- 金額出向唯一路徑：`Money::Storage#to_psp_amount(psp: :airwallex)` →
  `BaseAdapter#to_payload` → `Client#post_json(amount_psp_number:)`（鐵律 3；
  ⚠️ 構造用 `Money::Storage.from_cents`——`new` 是 private，job spec 實抓）。
- 官方 status 4 值對映：RECEIVED＝pending（等後續對帳）／ACCEPTED、SETTLED＝
  success／FAILED＝failure。⚠️ **沒有 SUCCEEDED 值**（缺口研究實查）。
- 流程：`Refunds::Create` 交易內落列（pending）→ 交易外 `ProcessPspRefundJob`
  打 API（鐵律 5）→ 依回應翻終態。
- 🔴 **失敗補償**：FAILED／API 例外 ⇒ `release_cumulative_cap!` 把
  `refunded_total_cents` 減回（錢沒出去、額度必須釋放；Calculator 的行可退量
  同步依 `status=failure` 排除——兩處一致）。
- ⚠️ RECEIVED 停在 pending 的收斂機制（退款 webhook／輪詢）＝未做，登記 §7。

## §6 與本尊的偏離（逐項）

| # | 面向 | 本尊 | 我方 | 依據 |
|---|---|---|---|---|
| 1 | FO 粒度 | 多 FO（per location/group） | **每單一張** | v1 單地點；GraphQL input 照收 pair 陣列（1:1），服務層限恰一組 |
| 2 | `FulfillmentOrderLineItemInput.id` | FulfillmentOrderLineItem GID | **LineItem GID** | v1 無 FO 行子表，FO 行＝訂單行 1:1 |
| 3 | fulfillment 行項 | FulfillmentLineItem 子表 | json 快照 | cancel 回加的依據；升級路徑保留 |
| 4 | tracking 儲存 | numbers/urls 平行陣列 | 物件陣列 `[{number,url}]` | 等價且不會錯位；input 面照官方五欄收 |
| 5 | userErrors | **裸 UserError 無 code**（兩支皆是，取證 2026-09-01） | typed code enum | 鐵律 4 既有加嚴（S5 先例） |
| 6 | tracking update 語義 | **官方未取得**（replace/merge 零命中，兩頁複核） | **整組取代**（ours） | 部分合併無法表達「刪追蹤號」；取得官方語義後複驗 |
| 7 | fulfillmentCancel | 為取消品項建**新** FO | 同一張 FO 翻回 open | v1 單 FO 的等價操作 |
| 8 | RefundInput | 12 欄 | 6 欄子集 | currency/duties/refundMethods/transactions/processedAt/discrepancyReason v1 無資料來源 |
| 9 | 退款冪等 | `@idempotent` directive（2026-04 起強制） | `idempotencyKey` argument 必帶 | 我方冪等慣例（limits required_for 既列） |
| 10 | delivered | FulfillmentEvent（DELIVERED） | `delivered_at` 欄恆 NULL | 物流事件線未做，誠實登記 |

## §7 本包不做的（登記）

1. **FO hold/release mutation**（`fulfillmentOrderHold`／`ReleaseHold`）——
   on_hold 狀態有讀出與擋出貨守衛，但無寫入入口（UI 分裂鈕的 Mark as on hold
   隨後續包）。SCHEDULED 同（需 `fulfill_at` 入口）。
2. **退款 webhook／輪詢收斂**：RECEIVED 停在 pending 靠人工或後續對帳線。
3. **Return/exchange 線**（16 §F7）：獨立步驟。
4. **多地點拆單**（MOVE/SPLIT/MERGE）、3PL request_status 流。
5. **`orders/fulfilled` 對外 webhook topic**：本尊 topic 名未取證 ⇒ 先用內部
   `order.fulfilled`／`order.refunded`（Topics 檔頭登記；webhook 線取證後對位）。
6. **免運折扣 ⇒ 運費不可退**的判定（v1 無免運折扣概念）。
7. **訂單取消（orderCancel）**：另一支（16 §F4），不在本步。

## §8 測試與突變

| 檔 | 守什麼 |
|---|---|
| `spec/services/refunds/calculator_spec.rb` | 分攤手算值、per-unit 游標無殘差、上限、可退量 |
| `spec/graphql/refund_create_spec.rb` | 預覽==實退、軟上限兩碼、冪等重放、restock 兩型、financial 推導 |
| `spec/graphql/refund_create_permission_spec.rb` | over_refund 權限閘（有 edit 無 over_refund 的角色） |
| `spec/graphql/fulfillment_lifecycle_spec.rb` | 出貨全矩陣＋cancel 全反向＋on_hold 守衛 |
| `spec/services/refunds/create_concurrency_spec.rb` | C1 併發（order lock 序列化＋條件式守衛） |
| `spec/services/orders/mark_as_paid_captured_spec.rb` | captured 累計（兩條入帳路徑） |
| `spec/jobs/refunds/process_psp_refund_job_spec.rb` | PSP 終態對映＋失敗補償 |

突變輪結果見 worklog（`docs/worklog/2026-09-01-g6-8-履約退款.md`）。
