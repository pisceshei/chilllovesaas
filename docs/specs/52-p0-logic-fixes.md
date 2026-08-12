# 52 — P0 邏輯缺口修正紀錄（15 條）

> **對象**：`docs/specs/50-logic-gap-register.md` §P0（15 條，「照現有規格開發會算錯錢／卡死狀態／遺失資料」）。
> **權威順序**：官方開發文檔（46a/46b）＞ 官方商家文檔（46c）＞ 實測畫面（44）＞ 我方既有規格。**我方與官方衝突時一律改我方。**
> **修正日**：2026-08-12。**新增檔案**：`config/limits.yml`（原本不存在）、本檔。
> **可追溯性**：每一處改動旁都留了 `<!-- 依 46a:行號 修正，原文：… -->` 註釋；**7 條「我方明文寫錯」**額外留了「🔴 此處原本寫錯 … 任何人翻舊版都不要改回去」的防回退註記。

---

## 0. 改動總表

| 檔案 | 行數變化 | 改了什麼 |
|---|---|---|
| `config/limits.yml` | **新增 0 → 379** | 全部官方硬性上限與預設值集中管理（23 個頂層區塊、14 大類，每條帶出處註解與官方層級標記 dev/help/live/ours） |
| `docs/specs/52-p0-logic-fixes.md` | **新增**（本檔） | P0 修正紀錄 |
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | 63 → **540**（+477） | F3.1/F3.2/F3.3、F4.1/F4.2/F4.3、F5.1/F5.2/F5.3、**新增整章 F7**（退貨與換貨） |
| `docs/specs/13-spec-products-inventory-media.md` | 98 → **172**（+74） | F1.1 最終銷售、F5 模型改四欄、**F5.1 庫存五態與子分類** |
| `docs/specs/11-production-baseline.md` | 116 → **179**（+63） | **§2.1 冪等完整規格**（回放語義、TTL、錯誤碼、參數指紋） |
| `docs/specs/17-spec-discounts-engine.md` | 69 → **119**（+50） | F2 求值順序補運費層、**F2.1 訂單級折扣基數**、驗收條目 |
| `docs/specs/15-spec-cart-checkout-payments.md` | 100 → **137**（+37） | F1 `cart_item_limit`、**F3.1 取貨點交接**、F7 棄單門檻 |
| `docs/research/06-data-model.md` | 137 → **208**（+71） | ER 圖退貨外鍵鏈、§4 狀態機總表重寫、§5 恆等式細化、§7 補 15 張表 |
| `docs/research/28-api-contract.md` | 213 → **309**（+96） | §0.6 冪等、§3 庫存 reason、§4 orderCancel、§5 FO 契約、§6 退貨退款、§8 折扣 context、§11 退貨規則＋取貨點 |
| `docs/research/22-admin-button-inventory.md` | 169 → **209**（+40） | Refund／Cancel／Fulfill／棄單／Return 五列改寫、§8 付款四模式＋運送取貨點、§9 修正回退 |
| `docs/specs/50-logic-gap-register.md` | 419 → **424**（+5） | §P0 標題下加結案指標（指向本檔與 `config/limits.yml`），避免重複處理 |

> **未觸碰**：`docs/design/*.html`（本次工作期間有其他工作流在改這三個原型檔，與本次 P0 修正無關）。

---

## 1. 逐條處置

### P0-01 · 退款公式缺「退貨費用扣減」「換貨扣抵」「floor 0」

| | |
|---|---|
| **原本錯在哪** | `16:44` 只有「行退款金額 = 行單價×數量 −（該行折扣分攤 × 退貨比例）；稅同理按比例」。**沒有退貨費用扣減、沒有換貨扣抵、沒有下限鉗制**。有換貨或退貨費的訂單退款金額必錯（可能多退，或算出負數）。 |
| **依據什麼改** | `46a:595–601`（S50，2024-07 起變更，官方標 Action required）逐字：「The refund amount considers **exchange line items and fees on the return**, as well as any **outstanding amount owed by the buyer** on an order.」下限逐字：「the suggested amount cannot be lower than $0 CAD」。文檔範例 $50.99 − $5.00 = $45.99。 |
| **改了哪裡** | `16-F5.1`（16:250–309）新增完整公式；`16-F5.2`（16:310–353）三個算例；`16-F5`（16:236–249）主流程改為「一律走 F5.1」；`22:32` Refund 列改寫；`28 §6`（28:140–158）規則行改寫。 |
| **公式** | `net = returned_value − return_fees − exchange_value − outstanding`；`suggested_refund = max(0, net)`；`balance_to_collect = max(0, −net)`。三個捨入點：折扣/稅比例分攤走**最大餘數法**、重新上架費百分比 `floor` 到分、零小數幣別只在序列化層處理。全程 integer cents。 |
| **怎麼測** | ① 算例 1：`returned_value=5099, fee=500` → `refund=4599`（對齊官方範例）。② 算例 1 變體：`fee=6000` → `refund=0` 且**不產生應收**。③ **算例 3（換貨＋退貨費同時存在）**：退 220000、restocking 10%＝22000、運費 6000、換貨 250000 → `refund=0` ＋ `balance_to_collect=58000`；用舊公式會算出 220000（誤差 NT$2,780/筆）。④ property test：任何中間值出現 float 即失敗。⑤ `returnCalculate` 與 `returnProcess` 同輸入必須同輸出。 |

### P0-02 · 退貨費用模型完全缺失

| | |
|---|---|
| **原本錯在哪** | 16 號完全無退貨費用欄位；22:61 只寫「restocking fee 與退貨運費按規則帶入」。**無欄位可存 → 退款金額錯、無法對帳。** |
| **依據什麼改** | `46a:526`＋`46a:608`：`RestockingFeeInput{percentage: Float!}`——**百分比、必填、per line item**，「Supports partial returns with **different fees per item**」。`46a:528`＋`46a:610`：`ReturnShippingFeeInput{amount: MoneyInput!}`——**固定金額、必填、per return、且必須是 presentment 幣別**。46a 明言此**不對稱設計是刻意的，必須照抄**。 |
| **改了哪裡** | `16-F5.3`（16:354–374）四個欄位定義＋覆寫兩層語義；`06 §7`（06:187–208）補 `returns` / `return_line_items` 表；`28 §6` 補契約；`22:78` Return 建立列改寫；`config/limits.yml` 的 `return.*`。 |
| **怎麼測** | ① 同一張退貨兩個品項給不同 `restocking_fee_bp`（15% / 8%），各自 floor 後加總正確。② `returns.return_shipping_fee_currency != orders.presentment_currency` → 寫入失敗。③ `restocking_fee_cents` 物化值與重算值必須相等（對帳測試）。④ 不對稱性回歸：試圖把 return shipping fee 做成百分比 → 與 `returnCalculate` 對不上，測試需捕捉。 |

### P0-03 · 訂單級多個百分比折扣的基數寫反 🔴（7 條「我方明文寫錯」之一）

| | |
|---|---|
| **原本錯在哪** | `17:42` 明文：「百分比疊加不是相加（20%+10% = **72 折**不是 7 折）——pipeline 序列計算天然正確」。這與官方**三方一致**的結論**直接相反**，且與我方自己的 `22:105` 自相矛盾。 |
| **依據什麼改** | `46b:284` 逐字：「both percentages are calculated on the **original subtotal**」（10% + 20% = 30%，非複利 28%）。`46c:720`（H28 zh-TW）逐字：「各折扣的百分比皆以**原始小計**計算」。 |
| **改了哪裡** | `17-F2.1`（17:46–81）新增基數定義、公式、算例表與五條必測性質；`17:84–85` 坑清單改寫；`17-F2`（17:18–23）補「運費折扣在配送選項生成之後」與「運費不可疊運費」；`17:113–119` 驗收條目。 |
| **關鍵區分** | **跨級仍序列**（product → order → shipping，order 級基數＝product 折後小計）；**同級不串接**（order 級的 N 個折扣共用同一個 `S₀`）。兩件事不要混。 |
| **怎麼測** | ① `S₀=100000`、10%＋20% → 折 **30000**（舊做法會得 28000）。② **可交換律 property test**：任意排列 order 級折扣結果相同。③ 鉗制：60%＋60% → `min(120000, 100000)` → 付 0，行金額不為負。④ 逐筆 floor 後加總（不是先加總 bp）——`Σbp > 10000` 時仍有鉗制點。 |

### P0-04 · `fulfillmentOrderCancel` 替代單／部分 hold-move 剩餘單未寫

| | |
|---|---|
| **原本錯在哪** | 完全未寫。`28 §5` 只列 `fulfillmentOrderMove/Hold/ReleaseHold/Split` 四個名稱。**取消或部分保留後，剩餘品項憑空消失**（資料遺失），訂單永遠卡在 partially_fulfilled。 |
| **依據什麼改** | `46a:236`／`46a:354` 逐字：`fulfillmentOrderCancel` ＝「Cancels order and **creates replacement for remaining work**」。`46a:358–360`／`46a:366`：`fulfillmentOrderHold` 與 `fulfillmentOrderMove` 回傳 **`remainingFulfillmentOrder`**（自動拆出新單承接未處理品項）。46a §2⑦-9 明列這是「最容易漏、漏了會導致品項憑空消失的地方」。 |
| **改了哪裡** | `16-F3.2`（16:131–148）三個操作的回傳欄位表＋實作規格；`06 §2`（06:38、06:58–62）ER 自參照關聯與要點；`28 §5`（28:98–116）契約補完。 |
| **怎麼測** | **拆單不變量 property test**：對一張多品項 FO 隨機執行 cancel/hold/move/split 序列後，`Σ 所有 FO（含替代單）的 line item quantity == order line item 可履行數量`。另測：① cancel 有剩餘 → `replacementFulfillmentOrder` 非 null 且繼承 shop/order/location；② cancel 無剩餘（全出貨）→ 回 null；③ 只 hold 部分品項 → 未 hold 品項落在 `remainingFulfillmentOrder` 且可正常出貨；④ 建替代單與取消原單在同一 transaction（中途 raise 後兩者皆未生效）。 |

### P0-05 · FulfillmentOrder 狀態機完全不存在

| | |
|---|---|
| **原本錯在哪** | `06 §4` 無 FulfillmentOrder 列；`16-F3` 只寫「建 `fulfillment_orders`、對剩餘數量條件累加」。`requestStatus` 在全部 specs 中 grep 命中數 = 0。**履約線的按鈕 guard 無依據 → 狀態卡死、非法轉移**；`fulfillmentOrderClose → INCOMPLETE`（不是 CLOSED）會做反。 |
| **依據什麼改** | `46a:213–241`（7 個 status ＋轉移圖）、`46a:243–256`（8 個 requestStatus，含「自營履行單恆為 `UNSUBMITTED`」不變量）、`46a:258–275`（12 個 supportedActions 及對應 mutation）、`46a:277–290`（8 個 hold reason）、`46a:383–392`（Fulfillment 6 值）。`46a:240` 逐字：「Marks in-progress order as incomplete」。 |
| **改了哪裡** | `16-F3.1`（16:33–130）完整表：(a) 7 狀態 (b) **16 條合法轉移**含前置條件與副作用 (c) **8 條非法轉移** (d) 8 個 requestStatus ＋不變量＋轉移 (e) 12 個 supportedActions ＋出現條件 (f) 8 個 hold reason (g) Fulfillment 6 值；`06 §4`（06:111–143）補 FulfillmentOrder 三列＋FulfillmentHold＋Fulfillment；`28 §5` 補全部 mutation 與回傳。 |
| **怎麼測** | ① 16 條合法轉移全綠。② 8 條非法轉移全部回 `INVALID_STATE`（特別是 `CLOSED→*`、`CANCELLED→*`、`ON_HOLD→fulfillmentCreate`）。③ **`fulfillmentOrderClose` 的結果必須是 `INCOMPLETE` 不是 `CLOSED`**。④ 不變量：`assigned_fulfillment_service_id IS NULL ⟹ request_status='UNSUBMITTED'`（DB CHECK ＋ 測試）。⑤ 第 11 個 active hold → userError。⑥ `supportedActions` 與按鈕啟用一致性測試：伺服器不回某 action 時，前端該按鈕必為 disabled（防前後端 guard 漂移）。 |

### P0-06 · Return 狀態機採 help 的 4 態 🔴（我方明文寫錯）

| | |
|---|---|
| **原本錯在哪** | `06:96` 寫 `requested → in_progress → inspection_complete → returned`（help 的 4 態展示狀態）。**缺 `DECLINED` / `CANCELED` 兩個終態、缺 `OPEN` / `CLOSED` 的 API 語義、缺 6 條不可逆 guard** → 已拒絕的退貨可被重新核准、`REQUESTED` 可被直接取消 → 狀態卡死與帳務錯亂。 |
| **依據什麼改** | `46a:438–482`：`ReturnStatus` **5 值**（`REQUESTED`/`OPEN`/`DECLINED`/`CLOSED`/**`CANCELED` 單 L**）＋完整轉移圖＋不可逆聲明（「Approving a return is a permanent action」「cannot revert to REQUESTED」「Cannot be canceled directly」）。`46c:1021–1033`（C-07）判定：採 dev 5 值，help 的「檢查完成」降為 `OPEN` 底下的子進度。 |
| **改了哪裡** | `16-F7.1`（16:390–448）：(a) 5 狀態 (b) **9 條合法轉移**含前置與副作用 (c) **7 條非法轉移** (d) `returnCancel` 四條硬前置 (e)–(i) decline reason／return reason／逆向履行三態／disposition 四值／訂單層 `OrderReturnStatus` 6 值；`06 §4`（06:121–131）改寫該列。 |
| **怎麼測** | ① `REQUESTED → CANCELED` **必須失敗**（只能 approve/decline）。② `DECLINED` 之後任何 mutation 皆回 `INVALID_STATE`。③ `returnApproveRequest` / `returnDeclineRequest` 之後無法回退。④ `returnCancel` 在「已有 refund／已有 disposition／有 Shopify Shipping 標籤」任一情況下失敗；**手動上傳標籤時成功**。⑤ 移除最後一個 return line item → 自動 `CLOSED`。⑥ 拼寫回歸：`ReturnStatus.CANCELED`（單 L）與 `FulfillmentOrderStatus.CANCELLED`（雙 L）不得被「統一」。 |

### P0-07 · 「訂單有 active return → 不可取消」互鎖未寫

| | |
|---|---|
| **原本錯在哪** | `16:38` 只有 help 側一條「已部分出貨的單不能整單 cancel」。dev 的四條全缺，尤其**「有進行中的退貨不可取消」完全沒有** → 退貨進行中仍可取消訂單 → **雙重退款 ＋ 庫存重複回補**。 |
| **依據什麼改** | `46a:832–838` 逐字四條不可取消條件：已取消／有待處理付款授權／**Contain active returns**／有無法履行的未結出貨。`46c` C-01 判定「取聯集」。 |
| **改了哪裡** | `16-F4.1`（16:180–196）五條聯集 guard 表（G1–G5，各附判定式與錯誤碼）＋反向互鎖；`16-F4`（16:168–179）主流程；`28 §4`（28:123–135）；`22:40` Cancel 列。 |
| **怎麼測** | ① 存在 `REQUESTED` 或 `OPEN` 的 return 時 `orderCancel` 必失敗（`INVALID_STATE`）。② `DECLINED`/`CLOSED`/`CANCELED` 的 return **不阻擋**取消。③ **反向**：訂單已 `cancelled_at` 時建立 return 必失敗。④ 併發：同時發起 `orderCancel` 與 `returnCreate`，只能有一個成功（條件式 UPDATE ＋ 唯一性測試）。⑤ G1/G2/G4 各自的獨立案例。 |

### P0-08 · `return_line_items` 外鍵指錯（schema 級）

| | |
|---|---|
| **原本錯在哪** | `06:37` 只有 `ORDER ||--o{ RETURN`，退貨掛在**訂單層**。**上線後改不得**，且會允許退未出貨品項。 |
| **依據什麼改** | `46a:519` 逐字：`ReturnLineItemInput.fulfillmentLineItemId: ID!` ——「The ID of the **fulfillment line item** to be returned」。`46a:627`／`46a:648`：`returnableFulfillments` 前提逐字「A returnable fulfillment is an order that **has been delivered**」。46a §4⑦-16 明言「這決定了 schema，改不得」。 |
| **改了哪裡** | `16-F7.2`（16:449–471）外鍵鏈圖 ＋ 四條規則；`06 §2` ER（06:35–43、06:63–65）新增 `FULFILLMENT_LINE_ITEM ||--o{ RETURN_LINE_ITEM`；`06 §7` 補 `fulfillment_line_items` / `return_line_items` 表；`22:78` Return 建立列註明來源；`28 §6` 補 `returnableFulfillments`。 |
| **怎麼測** | ① `return_line_items.fulfillment_line_item_id` 為 NOT NULL FK（migration 測試）。② 對**未出貨**品項建立退貨 → 失敗。③ 對**已出貨未送達**品項建立退貨 → 失敗（`delivered_at IS NULL`）。④ 可退數量 = `fulfillment_line_items.quantity − 已退數量`，超過即失敗。⑤ `PICKUP_POINT` 訂單以**實際領件時間**作為 delivered 判定。 |

### P0-09 · 換貨未產生 `ON_HOLD` ＋ `AWAITING_RETURN_ITEMS` 的 FulfillmentOrder

| | |
|---|---|
| **原本錯在哪** | `22:61` 只寫「Exchange 加購（算差額；不能自訂品項）」。**換貨品在收到退貨前就出貨 → 直接資損。** |
| **依據什麼改** | `46a:552–556` 逐字：換貨在 `returnCreate` 以 `exchangeLineItems` 指定，系統建立 fulfillment order，狀態 **`ON_HOLD`**、hold reason **`AWAITING_RETURN_ITEMS`**，換貨品項的銷售紀錄自動建立。`46c:299`／`46c:351–358`：庫存不保留、訂單層折扣禁止、差價三情境。 |
| **改了哪裡** | `16-F7.3`（16:472–490）八條規則表；`16-F3.1(f)` 標註 `AWAITING_RETURN_ITEMS` 為換貨專用；`06 §7` 補 `exchange_line_items` 表；`22:78` Return 建立列。 |
| **怎麼測** | ① 建立帶 `exchangeLineItems` 的 return → 必產生一張 `status=ON_HOLD` ＋ hold `reason=AWAITING_RETURN_ITEMS` 的 FO。② 對該 FO 呼叫 `fulfillmentCreate` → 必失敗。③ `returnProcess` 完成 disposition → 自動 release hold → FO 轉 `OPEN` → 可出貨。④ `returnCancel` **不影響**已釋出的換貨品項。⑤ 換貨品項套訂單層折扣 → 失敗；套商品折扣 → 成功。⑥ 含 duties 的訂單建立換貨 → 失敗。⑦ 建立換貨期間 `committed` **不變**（見下方 V-03 待查證）。 |

### P0-10 · 退貨與取消規則「綁購買時點快照」未進任何 spec

| | |
|---|---|
| **原本錯在哪** | `44:437` 有結論（`order_line_items.return_policy_snapshot_id`）但**未進任何 spec**；16／13／28 全無。商家改規則會**追溯既往**，舊訂單的退貨期限/費用全部跟著變 → 費用算錯、顧客權益爭議。 |
| **依據什麼改** | **三方一致**：`46c:422–426` H14 en 逐字「Changes to your return rules apply only to future orders. Changes don't apply to previous orders」；H13 zh-TW 逐字同義；`44:437` 後台頁尾逐字「退貨與取消規則適用於在啟用或更新規則後所購買的品項」。 |
| **改了哪裡** | `16-F7.4`（16:491–509）八條規則；`13-F1.1`（13:23–36）最終銷售品項的商品側掛載；`28 §11`（28:226、28:233–245）`returnRules` / `returnPolicySnapshot` 契約與說明；`06 §7` 補 `return_rules` / `return_policy_snapshots` / `return_rule_final_sale_targets` 三表；`22:79` Return rules 列改寫；`config/limits.yml` 的 `return.window_*`。 |
| **怎麼測** | ① **回歸測試（核心）**：建立訂單 → 改退貨規則（縮短期限、調高費用）→ 對舊訂單跑 `returnCalculate`，結果**必須完全不變**。② `order_line_items.return_policy_snapshot_id` NOT NULL。③ `returnRuleUpdate` 後 `return_policy_snapshots` 必定 +1 筆，舊筆 `updated_at` 不變。④ 最終銷售品項在**前台入口層**即不出現申請按鈕（不是提交後被拒）。⑤ bundle 設為最終銷售 → userError。⑥ 同一訂單「已履行品項可退貨、未出貨品項可取消」兩個按鈕逐 line item 各自判斷。 |

### P0-11 · 冪等語義三處錯/缺 🔴（我方明文寫錯）

| | |
|---|---|
| **原本錯在哪** | ① `11:45–48` 的 `with_idempotency` 存 `response_body` 並**原樣回放**——與官方語義**相反**；② 無 TTL 24h；③ 無 `IDEMPOTENCY_CONCURRENT_REQUEST` / `IDEMPOTENCY_KEY_PARAMETER_MISMATCH` 兩碼與參數指紋正規化。退款重試會**重複退款**或誤判 mismatch 而卡死。 |
| **依據什麼改** | `46a:791`／`46a:1009` 逐字：「Successfully cached responses are **constructed from current database state**」。`46a:789`／`46a:1006` 逐字：「The retention window is **24 hours** … retries are treated as separate operations」。`46a:763–764`／`46a:1010–1011` 兩個錯誤碼。`46a:793`／`46a:816` 逐字：「Ensure consistent ordering of input fields to avoid fingerprinting mismatches」。`46a:781–787`：2026-04 起 17 個 mutation 強制 `@idempotent(key:)`，缺 key **執行期報錯**。 |
| **改了哪裡** | `11 §2.1`（11:41–96）完整規格：(a) 表結構改存 `result_ref` 指標 (b) 五種 state 的回放行為表 (c) 兩個錯誤碼 (d) canonical_json 指紋正規化 (e) 適用範圍與 key 產生；`11:100–111` 代碼範例重寫並附「為什麼」註釋；`11:36` 索引行；`28 §0.6`（28:33–48）契約表；`config/limits.yml` 的 `idempotency.*`（含 `required_for` 13 條）。 |
| **怎麼測** | ① 同 key 重送 → 回應由**當前狀態重建**（測法：第一次成功後直接改 DB 中該物件的欄位，重送同 key，回應必須反映**新值**）。② 25 小時後同 key 重送 → **視為新操作**（產生第二筆退款）。③ 同 key 兩個併發請求 → 後到者收 `IDEMPOTENCY_CONCURRENT_REQUEST`。④ 同 key 不同參數 → `IDEMPOTENCY_KEY_PARAMETER_MISMATCH`。⑤ **欄位順序不同、內容相同的 input → 指紋相同、不得誤判 mismatch**。⑥ 缺 key 呼叫 `required_for` 清單內的 mutation → 執行期報錯。⑦ bulk 100 行共用一把 key → 拒絕。 |

### P0-12 · 請款模式數量寫錯 🔴（我方明文寫錯，且「修正」本身是錯的）

| | |
|---|---|
| **原本錯在哪** | `22:147` 寫「**請款三模式**：結帳自動/全單出貨後自動/手動」，`22:157` 更明文寫「**修正：舊文件寫四模式，官方現行三模式**（第四種是訂單處理的自動出貨開關）」。**這條「修正」本身是錯的。** 後果：多次出貨的訂單**請款行為錯誤**（該逐次請款卻整單請款）。 |
| **依據什麼改** | `46c:508–514`（help.shopify.com H33 zh-TW，2026-08 實抓）的表格明列**四種**：結帳時自動請款（預設，全方案）／履行時自動請款（全方案）／**每次履行時自動請款（🔴 僅 Shopify Plus）**／手動請款（全方案）。50 號表 3 T-10 判定採 help 四模式。 |
| **改了哪裡** | `22:172`（§8 付款列）改為四模式並標 Plus 專屬；`22:174–178` 防回退註記；`22:180` 授權效期表與 1.75% 附加費；`22:193–196` §9 第 1 條**整條劃線作廢並寫明理由**；`config/limits.yml` 的 `capture.modes`（四值）＋ `plus_only_modes` ＋ `authorization_days_*` ＋ `late_capture_surcharge_rate`。 |
| **怎麼測** | ① 設定 `automatic_per_fulfillment` 的商店，一張訂單分三次出貨 → **產生三筆 capture**（金額各自對應該次出貨）。② 設定 `automatic_after_fulfilled` → 分三次出貨，只有**最後一次**觸發 capture（全額）。③ 非 Plus 方案選 `automatic_per_fulfillment` → 設定被拒。④ 授權效期依卡別與方案取值（Visa Plus = 30 天）。⑤ 逾期請款 → 帳單多一筆 1.75% 附加費行項。 |

### P0-13 · 超商取貨（pickup points）在 admin/API 側完全無規格

| | |
|---|---|
| **原本錯在哪** | 42 §12.2 只有前台流程；`15`／`16`／`22 §8`／`28 §11` **全部空白**。前台選了門市**後台無處存、無法出貨** → 台灣最主要配送方式不可用。 |
| **依據什麼改** | `44:322` 實測：後台「其他配送方式」三列＝`當地配送`／`到店取貨`／**`取貨點`**，44 逐字結論「這正是台灣超商取貨的對應概念；我們 42 號前台的超商取貨流程在 admin 側要對應此設定」。`46b:551–552`：`purchase.checkout.pickup-point-list.*` 與 `pickup-location-list.*` 是**兩組不同**的結帳擴充點 → pickup point 是獨立的第三種配送方式。 |
| **改了哪裡** | `16-F3.3`（16:149–167）資料模型兩張新表、`delivery_method_type` 三分法、出貨流程差異、`READY_FOR_PICKUP` 事件；`15-F3.1`（15:60–82）結帳→admin 交接契約與四條硬驗證；`28 §11`（28:224–225、28:246–253）API 契約與說明；`22:176`（§8 運送列）補第三種配送方式；`config/limits.yml` 的 `pickup_point.*`。 |
| **怎麼測** | ① `delivery_method_type=PICKUP_POINT` 但未選門市 → 結帳提交被擋。② 門市資訊以**快照**落庫（刪除 `pickup_point_providers` 的通路後，既有訂單的門市資訊仍完整）。③ COD 金額 > NT$20,000 → COD 選項不出現且提交被擋。④ 超材積商品在**購物車階段**即擋。⑤ `PICKUP_POINT` 的 FO 出貨畫面不顯示收件地址、顯示門市卡。⑥ `READY_FOR_PICKUP` → 實際領件才寫 `delivered_at`，退貨資格以此判定。 |

### P0-14 · `orderCancel` 契約錯誤 🔴（我方明文寫錯）

| | |
|---|---|
| **原本錯在哪** | `28:69` 簽名 `orderCancel(reason, refund: Boolean, restock: Boolean, notifyCustomer)`：**多出官方不存在的 `refund: Boolean`**、缺 `staffNote`/`refundMethod`、`restock` 未標 non-null、缺**非同步 job 回傳**、缺「停用地點＋已付款＋restock:true 會失敗」。同步執行跨聚合操作會逾時中斷 → **半取消狀態卡死**。 |
| **依據什麼改** | `46a:842–851`（參數表：`reason` 與 `restock` 皆 non-null；`staffNote` ≤255 買家不可見；`refundMethod` 可退原路或 store credit）、`46a:865`／`46a:877`（逐字「responses include a **job object** for tracking completion」）、`46a:853`（停用地點行為逐字）、`46a:830`（6 個 cancel reason）。 |
| **改了哪裡** | `16-F4.2`（16:197–224）參數表（含 `refund` 標為「官方不存在，刪除」）＋回傳＋非同步三條＋停用地點行為；`28 §4`（28:93、28:117–135）簽名改寫＋契約說明；`22:40` Cancel 列。 |
| **怎麼測** | ① GraphQL schema 中**不存在** `orderCancel.refund` 參數（schema 快照測試）。② 不傳 `restock` → 驗證錯誤（non-null）。③ `staffNote` 256 字 → 失敗；且該欄不出現在任何買家可見輸出。④ 回傳 `job{id, done:false}`，輪詢至 `done:true` 後訂單才為 cancelled。⑤ **停用地點 ＋ 已付款 ＋ `restock:true`** → 整個 mutation 失敗且**無任何部分副作用**；未付款同條件 → 成功但庫存不回補。⑥ 同一訂單重複觸發取消 job → 只執行一次（冪等）。 |

### P0-15 · 庫存資料模型只有 `available/committed` 兩欄

| | |
|---|---|
| **原本錯在哪** | `13:59` 寫「`inventory_levels`（available/committed **兩欄起步**）」，但 `06:111` 恆等式與 `44:150` 實測都需要 `unavailable`（含子分類）＋`incoming`。草稿單保留庫存、待收退貨**無處可存** → **恆等式恆不成立、nightly 對帳永遠告警、且會超賣**。 |
| **依據什麼改** | `46c:891–907`（H18 zh-TW 五態逐字定義）、`46c:925–927`（unavailable 四子分類）、`46c:546–549`／`46c:895`（**訂單草稿保留進 Unavailable，不是 Committed**）、`46c:296`／`46c:330`（建立退貨當下庫存不變、標記「待收退貨品項」）、`46c:594–595`（編輯連動規則）、`46c:608–617`（調整原因七項）。 |
| **改了哪裡** | `13-F5`（13:73–77）模型改為四欄＋子分類表，附防回退註記；`13-F5.1`（13:104–159）五態表、恆等式、六個子分類、11 條狀態間移動、編輯連動、七原因、事件型別；`06 §5`（06:149–167）恆等式細化；`06 §7` 補 `inventory_unavailable_buckets`；`28 §3`（28:78–87）`name` 四個量測面＋七原因（**移除官方沒有的 `sold`**）；`config/limits.yml` 的 `inventory.*`。 |
| **怎麼測** | ① 恆等式斷言：`on_hand == available + committed + unavailable` 且 `Σ buckets.quantity == unavailable`（nightly job ＋ 單元測試）。② 草稿單保留庫存 → `unavailable[draft_reserved]` +n、`committed` **不變**。③ 草稿轉正式單 → `unavailable[draft_reserved]` −n、`committed` +n。④ 保留到期 → 回 `available`。⑤ 建立退貨 → 所有數量**皆不變**，只寫一筆 delta=0 的標記事件。⑥ 編輯 on_hand → available 等量變動。⑦ 後台嘗試直接改 `committed` → 無入口且 API 拒絕。⑧ `incoming` 不計入 `on_hand`（收貨後才轉 `available`）。 |

---

## 2. 「我方明文寫錯」7 條的處置（50 號表 2）

每一條都**改正 ＋ 在原處留防回退註記**（`🔴 此處原本寫錯 … 任何人翻舊版都不要改回去`）。

| # | 條目 | 原本寫錯的位置 | 現在寫在哪 | 防回退註記 |
|---|---|---|---|---|
| H-03 | 冪等回放原始快照（官方是由當前狀態重建） | `11:45–48`、`28 §0.6` | `11 §2.1`(b)、`28 §0.6` | ✅ 11:42–50、28:44–47 |
| H-12 | `orderCancel` 簽名多 `refund`、少 `staffNote`/`refundMethod`、`restock` 非 non-null | `28:69` | `16-F4.2`、`28 §4` | ✅ 16:199–204、28:119–122 |
| H-38 | `returnRefund` 已 deprecated 仍列為現行 mutation | `28:91` | `16-F7.6`、`28 §6` | ✅ 16:514–518、28:148–151 |
| H-40 | 訂單級多個百分比折扣基數（P0-03） | `17:42` | `17-F2.1` | ✅ 17:48–54 |
| H-48 | `customerSelection` 已 deprecated（2025-10），應改 `context{customerSegments\|markets}` ＋ XOR | `28:113` | `28 §8` | ✅ 28:180–182 |
| H-95 | 請款模式（P0-12）；且「修正為三模式」這條修正本身是錯的 | `22:147`、`22:157` | `22 §8`、`22 §9-1` | ✅ 22:174–178、22:193–196 |
| H-107/108 | 棄單門檻三處不一致（15:94「1 小時」vs 22:60/24:228「10 分鐘」）；`cart_item_limit`（總件數 50）與「每行 999／行數 100」概念混淆 | `15:9`、`15:94` | `15-F1`、`15-F7`、`22:73` | ✅ 15:14–18、15:132–136、22:75–77 |

> H-38 / H-48 / H-107-108 屬 P1，但因為是「明文寫錯」（會誤導開發者照錯的寫），一併在本次改掉。

---

## 3. 附錄 A · ⚠ 待查證（來源未載明）集中清單

> **規則：這些項目一律不自補規則。** 已在對應規格處以 `⚠ 待查證（來源未載明）` 就地標記，並集中列於此。
> 標記為 `verify: true` 的條目在 `config/limits.yml` 中也有對應旗標。

| # | 項目 | 為何不能自行決定 | 就地標記位置 |
|---|---|---|---|
| **V-01** | `RestockType` 的真實列舉值 | 三方互斥：`46a:747` 為 `RESTOCK`/`NO_RESTOCK`/`LEGACY_RESTOCK`；`28:90` 原寫 `RETURN`/`CANCEL`/`NO_RESTOCK`；實務另有第三套 → **GraphQL introspection 定案，實作前不得二選一** | `28 §6` |
| **V-02** | 市場的 `shipping` 到底繼不繼承 | `46b:659–661` 逐字「Null means the market inherits shipping from its parent」vs `44:866` 逐字「運送與隱私權不繼承」→ 直接矛盾 | （29 號 Markets，本次未動） |
| **V-03** | 換貨品項的 `ON_HOLD` FO 是否佔用 `committed` 庫存 | `46a`（會建 FO）與 `46c:299`（不保留庫存）表面衝突，**兩份文檔皆未載明**。本專案暫採 help（不佔 committed） | `16-F7.3` 表後 |
| **V-04** | 台灣統編檢核演算法的現行規則（是否含「可被 5 整除」） | `42:520` 只有舊規則，財政部原文須覆核 | （42 號，本次未動） |
| **V-05** | 電子發票期別格式與雙月制規則 | `38:986` 已標「待定，需使用者確認」 | （38 號，本次未動） |
| **V-06** | 發票作廢的期別限制、「48 小時上傳」期限 | `38:885` 明言來源是媒體整理，須以財政部原文覆核 | （38 號，本次未動） |
| **V-07** | 個資外洩 72 小時起算點、PDPA 的 DSR 法定回覆天數 | `38:885` 已標未載明 | （38 號，本次未動） |
| **V-08** | `purchase.checkout.block.render` 的 14 個 placement 字串 | `46b:997` 標為「四個版本頁面皆未列出」 | （P2，本次未動） |
| **V-09** | `maximumRefundable` 公式／退款稅額分攤規則／`RefundShippingInput` 同時給 `amount` 與 `fullRefund` 的行為／`RestockingFeeInput.percentage` 最大值／`FulfillmentOrderHoldUserErrorCode`、`SplitUserErrorCode`、`OrderCancelUserErrorCode` 具體值／`fulfillmentOrderSplit` 最大拆分數／tracking number 數量上限 | `46a:1049–1067` 逐條標「文檔未載明」共 15 項 | `16-F5.1`（軟上限段）、`16-F5.3`、`28 §5`、`28 §6`、`limits.yml`（`verify_*` 旗標） |
| **V-10** | 每店 markets 總數上限／market 巢狀層數／`MarketUserErrorCode`／單一折扣可綁 markets 數／Function 執行失敗 fallback | `46b:993–1010` 逐條標未載明（社群的「50 markets」說法**未經官方證實，勿引用**） | `28 §8` |
| **V-11**（新增） | **取貨點（pickup point）在 Shopify admin 側是否有對應 GraphQL 型別**；台灣各物流商的 COD 上限與材積限制合約值 | 三方文檔（46a/46b/46c）皆未載明；`28 §11` 的 `pickupPointProviders` / `checkoutPickupPointSet` 為**本專案自定契約**；COD NT$20,000 與三邊和 105cm／5kg 是**業界慣例值，非官方文檔** | `16-F3.3`、`15-F3.1`、`28 §11`、`limits.pickup_point.verify_tw_carrier_limits` |
| **V-12**（新增） | **純退貨費用超過退貨品項價值時，是否應產生「應收」**（無換貨、無欠款的情況） | `46a:601` 只說「建議金額不得低於 $0」，**未說**會產生應收；`46c:351–358` 的「payment needs to be collected」在上下文中同時涵蓋 fees 與 exchange items → 語義邊界不明。本專案暫定：不自動產生應收 | `16-F5.1`「負值的兩種語義」 |
| **V-13**（新增） | **重新上架費的百分比基數是否含稅** | `46a §4④` 只說「按 line item subtotal 計算」，subtotal 是否含稅未載明。本專案暫定：基數＝該行**折後未稅**小計 | `16-F5.1` 公式註解 |
| **V-14**（新增） | **冪等 key 的長度／字元格式硬性限制** | `46a §6⑤` 只建議 UUID v4/v5/v7，未給硬性格式限制 | `28 §0.6` |

---

## 4. 本次修正過程中發現、50 號**漏列**的新 P0 候選

> 這幾條符合 P0 定義（照現有規格開發會算錯錢／卡死／遺失資料），但 50 號未列或只列為 P1。**本次已一併修掉的標 ✅；需另行決策的標 ⚠**。

| # | 缺口 | 錯誤後果 | 為何是 P0 | 處置 |
|---|---|---|---|---|
| **NP0-A** | **退款上限做成 DB CHECK 硬擋**（`16:44`「累計退款 ≤ 實收（DB CHECK 級測試）」） | 擋掉 `46c:223` 明載的合法超額退款情境；**DB CHECK 是 migration，上線後移除要停機** | 50 號放在 P1（T-03），但這是**schema 級不可逆決定**，與 P0-08 同性質 | ✅ 已改為軟上限＋權限＋二次確認（`16-F5.1`、`22:32`） |
| **NP0-B** | **`fulfillmentCreate` 未限制「同 order 同 location」** | 跨地點混批出貨 → 庫存從錯誤地點扣減、`on_hand` 恆等式破裂、對帳永遠告警 | 與 P0-15 同一條恆等式；且是**資料錯誤不是 UI 問題** | ✅ 已補（`16-F3`第 5 點、`28 §5`） |
| **NP0-C** | **`orderEditAddVariant.allowDuplicates` 與 `orderEditSetQuantity.restock` 的預設值未寫** | `46a:924`/`46a:929` 兩者官方預設皆為 `false`；預設值選錯 → **庫存錯亂**（自動 restock 了不該 restock 的品項） | 50 號列在 H-29（P2），但這是**靜默的庫存錯誤**，無錯誤訊息、只有對帳時才發現 | ✅ 已寫入 `limits.order.edit_*_default`；訂單編輯完整規格仍待 M4（H-33 屬 P1） |
| **NP0-D** | **`REQUESTED`/`OPEN` 的 return 存在時，反向未擋「已取消訂單上建立 return」** | P0-07 只寫了單向（return 擋 cancel）。反向未擋 → 已取消訂單上仍可建 return → **重複退款** | 互鎖必須雙向才成立；單向互鎖等於沒有互鎖 | ✅ 已補（`16-F4.1` 末段反向互鎖） |
| **NP0-E** | **`inventory` 調整原因枚舉含官方沒有的 `sold`**（`28:63`） | `sold` 與 fulfillment 事件語義重疊 → 同一次出貨可能被記兩筆 ledger（一筆 fulfillment、一筆 `sold`）→ **恆等式重複扣減** | 50 號列在 H-103（P1，只說「兩處清單不同」），但未指出 `sold` 會造成**重複扣減** | ✅ 已移除 `sold` 並統一為官方七項（`28 §3`、`13-F5.1(f)`、`limits.inventory.adjustment_reasons`） |
| **NP0-F** | **合併運費「以費率名稱為合併鍵」未寫**（`46c:869–876`） | 名稱相同→相加、名稱全不同→取最便宜相加。不寫合併鍵 → **跨設定檔購物車的運費直接算錯** | 這是金額公式錯誤（與 P0-01/P0-03 同類），50 號列在 P1（H-111） | ⚠ **本次僅在 `22 §8` 運送列補上規則描述**；完整公式與算例應進 15-F2 金額引擎，建議升為 P0 另案處理 |
| **NP0-G** | **`supportedActions` 的權威歸屬未定，前端自建 guard**（`22:38`） | 前後端兩套 guard 必然漂移 → 前端顯示可點、後端拒絕（或更糟：前端擋住合法操作，商家以為系統壞了） | 50 號列在 S-07（表 1），未進 P0；但這是**狀態機能否正確落地的前提**，與 P0-05 綁定 | ✅ 已在 `16-F3.1(e)` 定為鐵律（伺服器計算、前端不得另寫），`22:47` 同步 |

**建議**：NP0-F（合併運費費率名稱合併鍵）應正式升為 P0-16 並排入 M3/M4 前修——它與 P0-01/P0-03 同屬「金額直接算錯」，只是缺口在運費側而非折扣/退款側。
