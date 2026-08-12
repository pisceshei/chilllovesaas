# 57 — 55 號 8 條 P0 在香港基準法域下的落地（G-01 ～ G-08）

> **緣由**：`docs/specs/55` 的 8 條 P0 成文時預設法域是**台灣**。使用者 2026-08-12 裁定**基準法域＝香港**、台灣降級為未啟用 pack（`CLAUDE.md` 鐵律 11、`docs/specs/56`）。本檔**先套用 56 §E 的法域重新分流，再逐條落地**。
> **前置**：56 號的分流結論**不推翻、直接照做**；本檔只補 56 落地不完整或分流有缺口之處（逐條列在 §H，共 8 條）。
> **權威順序**（沿用 52／54／55／56）：官方開發文檔（46a/46b）＞ 官方商家文檔（46c）＞ 實測畫面（44）＞ 我方既有規格。**法域規則的權威來源不同**——Shopify 不處理任何國家的稅務憑證，46a/46b/46c 不可能是法域結論的來源；本檔凡法域結論一律標 56 §0.3 的出處等級（`hk-user`／`hk-secondary`／`⚠ 待查證`）。
> **金額鐵律**（CLAUDE.md 鐵律 3）：全程 **integer cents**。**本檔不新增任何捨入點**——16-F5.1 的三個捨入點（折扣／稅比例分攤走最大餘數法、重新上架費百分比 floor 到分、零小數幣別只在序列化層）仍是全部。本檔新增的金流累計檢查（§G-02）與合約負債分錄（§G-07）**全是加減法，無 floor／ceil**。
> **上限值**（鐵律 6）：一律引 `config/limits.yml` 鍵名，本檔**不寫死任何數字**。
> **台灣內容**：一行未刪（56 §C.3 不刪除聲明）。本輪對台灣內容的改動只有「加標歸屬」與「補上法域條件」，實質規則一字未動。
> **可追溯性**：每一處改動旁留 `<!-- 依 56 §E 分流，原 55 §D 結論：… -->`；推翻既有寫法者另留「🔴 防回退」註記。格式沿用 52／54／55。
> **落地日**：2026-08-12。

---

## 0. 處置狀態總表

| # | 55 §D 原缺口 | 56 §E 分流 | **本輪處置** | 危險等級（56 §E.1） |
|:--|---|---|:--|---|
| **G-01** | 部分出貨開立粒度未定案 ⇒ 擋下轉人工佇列 | **N/A 且處置有害** | ✅ **已做**——擋單規則補上 pack 條件，HK 直接放行並落 skip 列 | **最高**（營運中斷） |
| **G-02** | 折讓累計上限 `Σ 折讓 ≤ 發票金額` | 憑證側 **N/A**；金流側**必須留著** | ✅ **已做**——金流側累計檢查寫成可測式子（SQL／併發／錯誤碼）；憑證側**移入 tw pack** | 高（容易誤刪） |
| **G-03** | 作廢窗已關 ⇒ 降級全額折讓 | **N/A** | ➡️ **移入 tw pack**（router 整體標 tw-only ＋ 明確宣告 no-op） | 中 |
| **G-04** | 一訂單多發票；不得建唯一索引 | 稅務理由 N/A，**結論保留** | ✅ **已做（優先）**——裁決值從未啟用的 pack **提到核心層**並列舉化 | 高（**不可逆**） |
| **G-05** | COD 未取件退回走訂單層作廢 | 憑證面 N/A；**訂單層保留** | ✅ **已做**——事件改法域中性 `TaxEvent(sale_uncollected)`；訂單層 VOIDED 原樣保留 | 中 |
| **G-06** | 禮品卡稅務時點二選一 ＋ 解析器拒絕啟動 | **性質改變**，HK 已有答案 | ➡️ **移入 `jurisdictions.tw.accounting`**（限定 TW）＋ HK 側**明確宣告 `false`** | **最高**（功能永久不可用） |
| **G-07** | 抵用金稅務定位 ＋ 併發安全 | **不消失，只改性質** | ✅ **已做**——HKFRS 15 收入認列寫完整（§G-07）；併發安全那一半（法域無關）補進 28 契約 | 高（容易誤判為已解決） |
| **G-08** | 9 支金流 mutation 未列強制冪等 | **與法域無關，完整適用**（使用者 2026-08-12 裁定；🔴 **56 全檔未分析 G-08**，見 §H-3） | ✅ **已做（優先）**——複核 28 §0.6 已引用；補 mutation 簽名 ＋ 標明平台域 2 支**是 pack-scoped** | —（新發現，見 §H-3） |

**統計**：已做 **6** 條／移入 tw pack **2** 條（G-03、G-06 的解析器旗標）／N-A **0** 條完全消失。
🔴 **沒有任何一條是「刪掉」**——8 條的原始發現一條未推翻，改的只是「它在哪個法域生效、由誰承接」。

---

## G-04 · schema 級：一訂單多發票與唯一索引（**優先，上線後改不得**）

| | |
|---|---|
| **55 原結論** | `38:1346` 逐字 `refund.order.einvoice`（**單數**）暗示 `(shop_id, order_id)` 唯一，與 `16-F5.5`「總額上升 ⇒ 補開一張」直接矛盾。裁決：**一訂單可多發票，不得對 `einvoices(shop_id, order_id)` 建唯一索引**。與 P0-08（`return_line_items` 外鍵）同性質——**schema 級，上線後改不得**。 |
| **56 分流** | 稅務理由在 HK **N/A**（`tax_invoice: none` ⇒ 該表恆空），但 🔴 **結論保留**：`schema_is_union_of_all_packs: true`。「HK 下該表不會有資料，但若日後啟用 tw pack 才發現索引建錯，要停機做 migration」。 |
| **HK 下實際要做什麼** | ① 建表照做（`einvoices` / `einvoice_allowances` **首發就要建**，即使恆空）；② **不得**建該唯一索引；③ 另外兩張表 HK **首發就會寫入**：`jurisdiction_capability_skips`（每次 `documented_no_op`）與 `contract_liability_entries`（HKFRS 15 分錄）。 |

**🔴 56 落地不完整之處（本輪修正，見 §H-2）**：56 §0.2 只寫了「schema 取聯集」的**原則**，裁決值 `multiple_invoices_per_order_allowed: true` 留在 `jurisdictions.tw.tax_invoice` 底下——但 **`tw.enabled: false`，建表的人不會去讀一個未啟用的 pack**。原則不可執行，**列舉才可以做成 migration 測試**。已把清單提到核心層 `limits.jurisdiction.schema_union_rules`（三組：`forbidden_unique_indexes` / `required_tables` / `required_columns`）。

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `config/limits.yml` | **49–85**（+37） | 新增 `jurisdiction.schema_union_rules`：1 條禁建索引、4 張必建表、2 組必備欄位（`orders.{seller,buyer}_jurisdiction`、`gift_card_transactions` 複合外鍵） |
| `docs/research/06-data-model.md` | **223–244**（新增 §7.1，+22） | 法域 schema 四表對照表 ＋「`jurisdiction_capability_skips` 為什麼是表不是 log」 |
| `docs/research/06-data-model.md` | **247–249**（+3） | 既有表欄位變更補三條（`orders` 雙法域快照、`gift_card_transactions` 複合外鍵、`gift_cards.redeemable_scope`） |
| `docs/specs/38-platform-trust-modules.md` | **1012–1024**（+11） | §3B 表註路徑改 `limits.jurisdictions.tw.tax_invoice.*`；新增法域分流註釋 ＋ 防回退 |
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | **662–669**（+8） | F5.5(c) 第 5 點路徑更新 ＋ 分流註釋 ＋ 防回退 |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | migration 快照測試 | `einvoices` 上**不存在**任何以 `(shop_id, order_id)` 為完整鍵的唯一索引 |
| T2 | HK 首發 schema 快照 | `einvoices`／`einvoice_allowances`／`jurisdiction_capability_skips`／`contract_liability_entries` **四張表全部存在** |
| T3 | `contract_liability_entries` 唯一鍵 | 同一 `(shop_id, source_type, source_id, direction)` 插第二列 ⇒ 唯一索引拒絕 |
| T4 | `orders` 雙法域欄位 | 訂單成立後 `seller_jurisdiction` / `buyer_jurisdiction` 皆 NOT NULL；商家事後改市場 ⇒ 舊單兩欄**不變**（快照） |
| T5 | 複合外鍵（繞過應用層） | 直接對 DB 插 `gift_card_transactions` 且 `shop_id` 與卡片不符 ⇒ **外鍵拒絕** |
| T6 | 防回退回歸 | 啟用 tw pack 後對同一訂單補開第二張發票 ⇒ 成功，`einvoices` 該訂單 **2 列** |

---

## G-08 · 9 支金流 mutation 強制冪等（**優先，法域無關**）

| | |
|---|---|
| **55 原結論** | `orderCapture` / `orderMarkAsPaid` / `draftOrderComplete` / 4 支 `giftCard*` / 2 支 `storeCreditAccount*` 共 **9 支未列強制冪等**。官方 17 個清單是「Shopify 自己的金流寫入點」，不涵蓋我方自己的。判定標準沿用 NP1-D：**凡金流寫入一律強制冪等**。已補進 `limits.idempotency.required_for`（13→22）＋ 新增 `required_for_platform`（+2）。 |
| **56 分流** | **與法域無關，完整適用**（使用者 2026-08-12 裁定）。<br>🔴 **精確地說：56 全檔 grep `G-08` 命中數 ＝ 0**——§E.1「在 HK 不成立的結論」表沒有 G-08 列，也沒有任何一節提到冪等。「法域無關」是**由缺席推得**的結論，不是 56 寫下的判斷。方向正確，但**因為沒被分析過，平台域那 2 支的例外也就沒人發現**（§H-3）。 |
| **HK 下實際要做什麼** | 9 支一條不減。**驗證引用是否真的落地**（本輪任務指定項）。 |

**引用複核結果**

| 位置 | 狀態 | 說明 |
|---|:--|---|
| `config/limits.yml` `idempotency.required_for` | ✅ **已有** | 22 條（13 + 9），逐條帶對應金流寫入點註解 |
| `config/limits.yml` `idempotency.business_unique_keys` | ✅ **已有** | 5 條第二層業務唯一鍵（TTL 24 小時擋不住永久約束） |
| `docs/research/28` §0.6 | ✅ **已有**（原 35 行） | 逐字列出 9 支 ＋ 平台域 2 支 ＋ 第二層唯一鍵 |
| `docs/specs/15` F4.1(d) | ✅ **已有** | `orderCapture` 的兩層冪等鍵表 ＋ 4 條必測 |
| `docs/research/28` 各 mutation 簽名 | 🔴 **原本缺** | §4 訂單／草稿單、§8 禮品卡的簽名列**沒有 `idempotencyKey`**；`storeCreditAccountCredit/Debit` **整組不存在於任何契約表**。清單有、契約沒有 ⇒ 實作者照契約表寫 resolver 就會漏掉 |

**🔴 56 分流的缺口（本輪新發現，見 §H-3）**：`required_for_platform` 的 2 支（`platformEinvoiceVoid`、`platformEinvoiceAllowanceCreate`）**不是**法域無關的——兩者是台灣統一發票專屬 mutation，HK 為 default 時**根本不存在於 schema**（56 §A.4 CI-3）。若照 `required_for` 的方式做成無條件斷言，**HK 首發的 schema 快照測試會直接紅掉**。已加 `required_for_platform_pack_scope`。

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `config/limits.yml` | **126–129**（+4） | `idempotency.jurisdiction_scope: core_all_packs` ＋ 理由 |
| `config/limits.yml` | **180–185**（+6） | `required_for_platform_pack_scope: jurisdictions.tw.tax_invoice` ＋ CI 斷言方向說明 |
| `docs/research/28-api-contract.md` | **37–43**（+7） | §0.6 補「9 支法域無關／平台 2 支 pack-scoped」＋ 分流註釋 |
| `docs/research/28-api-contract.md` | **107、109** | `orderMarkAsPaid` / `orderCapture` / `draftOrderComplete` 簽名補 `idempotencyKey!` |
| `docs/research/28-api-contract.md` | **208、212–222**（+12） | **新增商店抵用金契約列**（`storeCreditAccountCredit/Debit`）＋ 四條硬要求（冪等／條件式 UPDATE／跨店檢查／到期 job 鍵） |
| `docs/research/28-api-contract.md` | **230、234–243**（+11） | 禮品卡四支簽名補 `idempotencyKey!` ＋ 四條硬要求 |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | schema 快照（法域無關） | `limits.idempotency.required_for` 的 **22 支**，其 resolver **全部**有 `idempotencyKey` 參數 |
| T2 | HK 首發 CI | `required_for_platform` 的 2 支在 schema 中**不存在**（不是「存在且要帶 key」） |
| T3 | tw 啟用後 CI | 同 2 支**存在且帶 `idempotencyKey!`** |
| T4 | 冪等窗過期 | `giftCardDebit` 同一 `(checkout_token, gift_card_id)` 隔 25 小時重放 ⇒ 被**第二層業務唯一鍵**擋下（冪等 key 已失效） |
| T5 | 缺 key | 22 支任一不帶 `idempotencyKey` ⇒ 執行期報錯（非 `userErrors`） |

---

## G-01 · 部分出貨開立粒度：擋單規則必須有法域條件

| | |
|---|---|
| **55 原結論** | ⚠ V-23 未定案；**定案前 `on_fulfillment` ＋ 多次出貨的組合一律擋下並轉人工佇列**，不得靜默選一邊。 |
| **56 分流** | **N/A 且處置有害**（危險等級**最高**，會造成營運中斷）。已落 `jurisdictions.hk.tax_invoice.block_multi_fulfillment_when_undecided: false`。 |
| **HK 下實際要做什麼** | 沒有憑證就沒有粒度問題 ⇒ **照常出貨**。但**不得靜默略過**：每次出貨落一列 `jurisdiction_capability_skips(capability: tax_invoice, event_kind: sale_recognised, reason: 'no_document_regime')`（56 §A.3 `documented_no_op`）。 |

**🔴 驗證結果：旗標原本沒有任何呼叫端（本輪修正，見 §H-1）**

任務指定「驗證此旗標真的被規格引用，不是只寫在 limits」。複核結論：**原本沒有**。
`block_multi_fulfillment_when_undecided` 在本輪之前只出現在 `config/limits.yml`（hk / tw 各一處）與 `56` 本身；**唯一的呼叫端 `16-F5.5(a)` 的 V-23 擋單註記當時是無條件的**（逐字「一律擋下並轉人工佇列」）。照該規格實作，HK 下 `partial_fulfillment_issue_granularity` 永遠是 `null`、擋單條件**永遠成立** ⇒ 所有多次出貨的訂單全部卡進人工佇列。

> **這正是 55 §D G-03 的病根換到法域層**：G-03 是「`EinvoiceVoidPolicy.window_open?` 掛勾寫了但 router 從不呼叫」；這裡是「旗標寫了但規格從不讀」。56 §A.3 已把「禁止靜默略過」升格為法域層通則，但它自己在 G-01 上正好犯了同一個形態的錯——**值落地了，判斷沒落地**。

**判斷順序（不可顛倒）**

```
pack = Jurisdiction.resolve(order).seller          # 取 orders.seller_jurisdiction 快照，不是即時查市場
if pack.tax_invoice.kind == :none:                 # ← 先問法域
    → 照常出貨 ＋ 落一列 jurisdiction_capability_skips
elif pack.tax_invoice.block_multi_fulfillment_when_undecided
     and pack.tax_invoice.partial_fulfillment_issue_granularity.nil?   # ← 再問未定案
     and order.fulfillments.count > 1:
    → 擋下並轉人工佇列
else:
    → 依 partial_fulfillment_issue_granularity 開立
```

**顛倒順序的後果**：先問未定案再問法域，HK 會先命中 `nil` ⇒ 仍然擋單。**法域必須是第一個判斷**。

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | **577–605**（+29，含法域條件偽碼與防回退註） | V-23 段拆成「待查證」＋「**擋單規則（有法域條件）**」；補判斷順序偽碼、分流註釋、🔴 防回退 |
| `config/limits.yml` | **689–693**（+4） | hk 側補「唯一呼叫端＝16-F5.5(a)」與病根說明 |
| `config/limits.yml` | **902**（+1） | tw 側補呼叫端指標（`block_multi_fulfillment_when_undecided: true` 在 903） |
| `docs/specs/55-money-tax-event-inventory.md` | **350**（G-01 列 +1 欄） | 法域適用性欄 |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | **R3 回歸（56 §F 驗收 9）** | HK 訂單分**三次**出貨 ⇒ **三次全部正常完成**，人工佇列筆數 **0** |
| T2 | 不得靜默 | 同上情境 ⇒ `jurisdiction_capability_skips` **恰增 3 列**，`reason` 可讀。**靜默 return 即測試失敗** |
| T3 | TW 未回退 | 啟用 tw pack ＋ `partial_fulfillment_issue_granularity: null` ＋ 分兩次出貨 ⇒ **擋下並進人工佇列**（原行為不得被削弱） |
| T4 | 判斷順序 | 對 HK 訂單斷言 `partial_fulfillment_issue_granularity` **從未被讀取**（法域分支先短路） |
| T5 | 快照不回溯 | 訂單成立後商家把市場改到 TW ⇒ 該訂單仍走 HK 分支（`orders.seller_jurisdiction` 快照） |

---

## G-02 · 金流側累計檢查（憑證側移入 tw pack，金流側**必須留著**）

| | |
|---|---|
| **55 原結論** | 折讓沒有累計上限檢查——`38:1341` 只看**本次**退款額 ⇒ 兩次各退 60% 開出折讓總額 120%。新增不變量 `Σ allowances ≤ invoice.total_cents`。 |
| **56 分流** | 憑證側在 HK **N/A**（無折讓）⇒ 移入 tw pack。🔴 **但金流側的 `Σ refunded ≤ maximumRefundable` 軟上限仍在**（55 §A.2 M09/M10，法域無關）——「不要連這個一起拿掉」。危險等級：**高（容易誤刪）**。 |
| **HK 下實際要做什麼** | 憑證側整段不執行；**金流側的累計檢查與併發鎖照做**。本輪把它從「一行式子」寫成**可測式子**。 |

**🔴 56 落地不完整之處（本輪補齊，見 §H-4）**：56 §E.1 只說「金流側軟上限仍在」，而 55 §A.2 M09/M10 那一列**只有式子與一句「條件式 UPDATE」**——沒有 SQL 樣式、沒有錯誤碼、沒有併發情境。實作者無從判斷 `affected == 0` 要回哪個錯誤碼，**而那直接決定前端要不要彈超額退款二次確認**。「留著」若沒有可執行的落地物，等於沒留。

### (a) 累計上限式（integer cents，法域無關，**無捨入點**）

```
maximumRefundable_cents = orders.captured_total_cents − orders.refunded_total_cents
不變量（任何時刻）      : Σ refunds.amount_cents ≤ orders.captured_total_cents
                          ⟺ orders.refunded_total_cents ≤ orders.captured_total_cents
```

`refunded_total_cents` 是**物化欄位**（`limits.refund.cumulative_cap_column`），與 `refunds` 明細 nightly 對帳。全是加減法 ⇒ **本節不引入任何 floor／ceil**。

### (b) 條件式 UPDATE 樣式（🔴 禁止先 SELECT 再 INSERT）

```sql
-- 正常路徑：上限檢查與寫入在同一條 SQL，依 affected rows 判定成敗
UPDATE orders
   SET refunded_total_cents = refunded_total_cents + :amount_cents,
       updated_at = :now
 WHERE id = :order_id
   AND shop_id = :shop_id                                    -- 鐵律 2：複合索引以 shop_id 開頭
   AND refunded_total_cents + :amount_cents <= captured_total_cents;
-- affected == 1 ⇒ 同一 transaction 內 INSERT refunds + refund_line_items + outbox
-- affected == 0 ⇒ 見 (c)
```

```sql
-- 超額路徑（46c:223 明載的合法情境）：帶 orders.over_refund 權限 ＋ 二次確認後走這條
-- 🔴 仍然是條件式 UPDATE，只是上界換成「本次核准的超額額度」，不是拿掉 WHERE 條件
UPDATE orders
   SET refunded_total_cents = refunded_total_cents + :amount_cents
 WHERE id = :order_id
   AND shop_id = :shop_id
   AND refunded_total_cents + :amount_cents <= captured_total_cents + :approved_over_refund_cents;
```

### (c) `affected == 0` 的兩種語義必須分開回

| 判別 | 錯誤碼 | 前端行為 | HTTP |
|---|---|---|---|
| 重讀後 `refunded_total + amount > captured_total` | `REFUND_EXCEEDS_MAXIMUM_REFUNDABLE` | 顯示超額退款二次確認；有 `orders.over_refund` 權限才可續行 | 200（鐵律 4） |
| 重讀後上限其實還夠（`updated_at` 已變） | `REFUND_CONCURRENT_MODIFIED` | 退避後**原樣重試**（同一把 `idempotencyKey`） | 200 |

重讀**只用於分類**（決定回哪個錯誤碼），🔴 **不得**用重讀的值去做第二次寫入決策。

### (d) 三個併發情境

| # | 情境 | 期望 |
|:--|---|---|
| C1 | 已收 100000、已退 0，兩分頁同時退 60000 | 恰 1 筆成功；另一筆 `REFUND_EXCEEDS_MAXIMUM_REFUNDABLE`；`refunded_total_cents == 60000` |
| C2 | 已收 100000，100 執行緒各退 1000 | 恰 100 筆成功、`refunded_total_cents == 100000`；第 101 筆失敗。**成功數 ＋ 失敗數 ＝ 請求數** |
| C3 | 退款與 `orderCapture` 併發 | 不得出現 `refunded_total > captured_total` 的中間態；兩者對同一列競爭，後到者重試後成功 |

### (e) 為什麼不做成 DB CHECK

`CHECK (refunded_total_cents <= captured_total_cents)` 會擋掉 46c:223 明載的**合法**超額退款（先前發過商店抵用金者可對原付款方式 over-refund）。**軟上限＝應用層條件式 UPDATE；硬約束只有 `refunded_total_cents >= 0`。**

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | **348–412**（+65） | F5.1「退款上限」段新增 (a)–(e)：上限式／兩段 SQL／兩個錯誤碼表／三個併發情境／不做 DB CHECK 的理由 ＋ 分流註釋 ＋ 🔴 防回退 |
| `config/limits.yml` | **283–296**（+14） | `refund` 補 6 鍵：`cumulative_cap_formula` / `cumulative_cap_enforcement` / `cumulative_cap_column` / `cap_exceeded_error_code` / `concurrent_conflict_error_code` / `over_refund_uses_same_conditional_update` |
| `docs/specs/38-platform-trust-modules.md` | **1376–1385**（+10） | `RefundRouter` 標為 tw-only ＋ 明確宣告 no-op ＋ 🔴「清理本 router 時不得連帶清掉 16-F5.1 的金流側」 |
| `docs/specs/55-money-tax-event-inventory.md` | **107–111**（+5） | §A.2 開頭補「11 條全部法域無關，一條都不得削弱」 |
| `docs/specs/55-money-tax-event-inventory.md` | **116** | M09/M10 列指向 `16-F5.1(a)–(e)` |
| `docs/specs/55-money-tax-event-inventory.md` | **492–504**（+13） | §G 驗收 5–11 標「TW only」＋ 兩條在 HK 仍須通過的例外 |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | C1／C2／C3 三個併發情境 | 如上表 |
| T2 | 錯誤碼分離 | 超額 ⇒ `REFUND_EXCEEDS_MAXIMUM_REFUNDABLE`；併發競爭 ⇒ `REFUND_CONCURRENT_MODIFIED`。**兩者不得合成一個碼** |
| T3 | 超額路徑仍有併發保護 | 兩個 staff 同時做**已核准**的超額退款 ⇒ 總額不得突破 `captured + approved_over_refund` |
| T4 | 無 DB CHECK | 合法超額退款（先發過商店抵用金）⇒ **成功**，不被 DB 層擋下 |
| T5 | 物化欄位對帳 | nightly：`orders.refunded_total_cents == Σ refunds.amount_cents`（全域） |
| T6 | **防回退**（56 §F 驗收 21） | 55 §A.2 的 **11 條**金流累計上限測試在 HK pack 下**全部仍須通過** |
| T7 | integer cents | 任一中間值出現 float 即失敗 |

---

## G-03 · 作廢窗 fallback（**移入 tw pack**）

| | |
|---|---|
| **55 原結論** | `EinvoiceVoidPolicy.window_open?` 掛勾存在但 router **從不呼叫** ⇒ 跨期別全額退款嘗試作廢被拒、該筆銷售永遠無沖銷憑證。已修：`window_open? == false` ⇒ **降級為全額折讓**。 |
| **56 分流** | **N/A**（HK 無作廢機制 ⇒ 無作廢窗）。移入 tw pack。 |
| **HK 下實際要做什麼** | 整條規則不執行。🔴 **但必須是明確宣告的 no-op**：呼叫端改為 `Jurisdiction::TaxInvoice.handle(TaxEvent)`，HK pack 回 `no_document` ＋ 落 skip 列。**不得**做成「這個類別在 HK 沒有呼叫端」。 |

> **G-03 的教訓在 HK 不但沒消失，還升格了。** 55 對 G-03 的判語是「掛勾寫了卻沒接上＝比沒寫更糟（會讓人以為已處理）」——56 §A.3 已把它抽象成法域層的**禁止第四種行為**（靜默略過），`jurisdiction_capability_skips` 這張表的唯一目的就是讓「什麼都沒做」變成看得見的一列資料。
> 諷刺的是，**56 自己在 G-01 上犯了同一形態的錯**（旗標寫了沒人讀，見 §G-01／§H-1）——這說明這類缺陷不是「知道就不會犯」，必須靠 CI 檢查。

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `docs/specs/38-platform-trust-modules.md` | **1376–1385**（與 G-02 同一處註釋） | router 整體標 tw-only ＋ 明確 no-op 要求 ＋ 禁止「無呼叫端」寫法 |
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | **535–550**（+16） | F5.5 節標題與導言：三層分工表（掛鉤點／事件 kind 法域無關；憑證動作 TW only）＋ 不刪除聲明 |
| `docs/specs/55-money-tax-event-inventory.md` | **352**（G-03 列 +1 欄） | 法域適用性欄 |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | HK 明確 no-op（56 §F 驗收 6） | HK 訂單發生全額退款 ⇒ `jurisdiction_capability_skips` **恰增一列**，`reason` 可讀。**靜默 return 即失敗** |
| T2 | CI-3 | HK 為 default 時，`app/services` 下**不存在**任何寫入 `einvoice/*` outbox 的呼叫路徑；三個內部 topic 也不註冊 |
| T3 | TW 未回退 | 啟用 tw pack ＋ `window_open? == false` 的全額退款 ⇒ 產生**全額折讓**而非失敗（原行為不得被削弱） |

---

## G-05 · COD 未取件退回（憑證面 N/A，**訂單層 VOIDED 保留**）

| | |
|---|---|
| **55 原結論** | 退款金額為 0（款項從未收到），router 三分支全部落到「折讓 0 元」⇒ 一筆從未成立的銷售留著全額發票。已修：走**訂單層** `einvoice/void_requested`，不走退款 router。 |
| **56 分流** | 憑證面 N/A；**訂單層 `PENDING → VOIDED` 的金流與庫存處理原樣保留**，只是不再發 `einvoice/void_requested`。 |
| **HK 下實際要做什麼** | 訂單層流程一字不動（狀態轉移、`restock` 回補、對帳）。事件改為**法域中性**的 `TaxEvent(kind: sale_uncollected)`（56 §A.2 C1 五個 kind 之一），由 pack dispatch：TW ⇒ `einvoice/void_requested`；HK ⇒ `no_document` ＋ skip 列。 |

**🔴 56 對本條的描述漏了根因（本輪補上，見 §H-5）**：56 §E.1 把 G-05 讀成「憑證面的事」。但 G-05 的根因是**「router 的入參語義不成立」**，那與有沒有稅制無關——HK 下若照舊把 COD 退回丟進退款路徑，症狀會從「開一張 0 元折讓」變成**「落一列金額 0 的假退款」**，一樣是髒資料，而且因為 HK 沒有折讓可看，**更難被發現**。

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | **247**（改寫） | F4.4 第 5 列：事件改 `TaxEvent(sale_uncollected)` ＋ 兩個法域的落地寫明 |
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | **254–262**（+9） | 分流註釋：憑證面 N/A、訂單層保留、**根因在 HK 完全不變**、🔴 防回退 |
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | **568**（改寫） | F5.5(a) COD 列同步 |
| `docs/specs/55-money-tax-event-inventory.md` | **354**（G-05 列 +1 欄） | 法域適用性欄 |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | HK COD 未取件退回 | 訂單 `PENDING → VOIDED`；庫存依 `restock` 回補；**`refunds` 表零新增列**（不得產生金額 0 的假退款） |
| T2 | 明確 no-op | 同上 ⇒ `jurisdiction_capability_skips` 增一列（`event_kind: sale_uncollected`） |
| T3 | TW 未回退 | 啟用 tw pack ⇒ 產生 `einvoice/void_requested`（**不是** 0 元折讓） |
| T4 | 不走 router | 兩個法域下皆斷言 `RefundRouter.route` **未被呼叫** |

---

## G-06 · 禮品卡：從「稅務時點」到「會計分類」（**移入 tw pack ＋ HK 明確宣告 false**）

| | |
|---|---|
| **55 原結論** | 禮品卡稅務處理完全未定義（T19/T20/T21）。⚠ V-21 兩制互斥；已建 `limits.gift_card` 區塊含 `tax_event_on_issue/on_redeem` 皆 `null` ＋ **解析器在未定案時拒絕啟動**（比照 V-02）。 |
| **56 分流** | **問題性質改變**：HK 是 HKFRS 15 合約負債（**已有答案**），不是開立時點。`resolver_refuses_start_when_undecided` 照搬到 HK ⇒ 因為 `tax_event_*` 永遠是 `null`，**禮品卡在香港永遠無法啟用**。已移入 `jurisdictions.tw.accounting` 限定 TW。危險等級：**最高**（功能永久不可用）。 |
| **HK 下實際要做什麼** | ① 禮品卡**可以正常啟用**；② 稅務時點問題消失，換成 HKFRS 15 分錄（見 §G-07）；③ ⚠ 只剩 breakage 估計方法未定（**V-28**），定案前 `defer_all`——**不認列 breakage ≠ 不能發卡**。 |

**🔴 56 落地不完整之處（本輪補上，見 §H-6）**：56 把旗標**移走**了，但 HK 側**沒有寫出對應的 `false`**。這違反 56 自己的**原則 2「未宣告 ≠ none」**——「tw 有、hk 沒有」在程式上長得像「hk 忘了填」，實作者讀到 `nil` 時若沿用預設 `true`，就會踩回同一個坑。**移走不等於關閉，關閉必須寫出來。**

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `config/limits.yml` | **767–772**（+6） | `jurisdictions.hk.accounting.gift_card_resolver_refuses_start: false` ＋「明確宣告的 false，不是沒填」理由 |
| `docs/research/28-api-contract.md` | **234–244**（與 G-08 同一處） | 禮品卡四支硬要求 ＋ 🔴「原旗標已移入 tw 並限定 TW，照搬會讓禮品卡永遠無法啟用」 |
| `docs/specs/55-money-tax-event-inventory.md` | **355**（G-06 列 +1 欄） | 法域適用性欄 |
| `docs/specs/55-money-tax-event-inventory.md` | **448** | §E.3 `gift_card` 列補「後四鍵已移入 `jurisdictions.tw.accounting` 限定 TW，前五鍵留核心」 |
| `docs/specs/55-money-tax-event-inventory.md` | **468–480**（+13） | §F 新增「V-20 ～ V-24 的法域歸屬」對照表（三條在 HK 是**同題不同答**，不是消失） |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | **R4 回歸（56 §F 驗收 10）** | HK 商店建立禮品卡 ⇒ **成功**。`resolver_refuses_start_when_undecided` 不得在 HK 生效 |
| T2 | 兌換可用 | HK 禮品卡結帳扣抵 ⇒ 成功，餘額正確扣減 |
| T3 | breakage 保守側 | 首年無歷史兌換資料 ⇒ breakage **不認列**（`defer_all`），負債留著。**但發卡與兌換不受影響** |
| T4 | TW 未回退 | 啟用 tw pack ＋ `tax_event_on_*` 為 `null` ⇒ 禮品卡稅務解析器**拒絕啟動**（原處置不得被削弱） |
| T5 | 未宣告 ≠ false | 建一個 `gift_card_resolver_refuses_start` 缺值的假 pack ⇒ 依 `undeclared_capability_action: reject` 處理，**不得**靜默當 false 也不得靜默當 true |

---

## G-07 · 儲值工具的 HKFRS 15 收入認列（**不消失，只改性質**）

| | |
|---|---|
| **55 原結論** | 抵用金的**稅務定位**（付款方式 vs 折扣，直接決定發票金額）與**併發安全**（無冪等、無條件式 UPDATE ⇒ 超額扣抵）皆未定義。⚠ V-22。 |
| **56 分流** | **不消失，改性質**：TW＝決定**發票金額**；HK＝決定**收入認列金額**（V-29）。「問題還在，答案不通用」。危險等級：**高（容易誤判為已解決）**。 |
| **HK 下實際要做什麼** | 見下方 (a)–(e)。 |

**🔴 56 分流只涵蓋了 G-07 的一半（本輪補上，見 §H-7）**：G-07 原文有**兩個**缺口——①稅務定位 ②**併發安全**。56 §E.1 只處理了 ①（改性質為會計），②完全沒提。但②**法域無關**：兩分頁同時結帳超額扣抵，與賣方在哪個法域毫無關係。把 G-07 整條讀成「移到會計層了」會把②一起弄丟。

### (a) 分錄方向（HKFRS 15，出處 `hk-user` HK-2，已查證）

**方向是唯一真相，不是科目名稱。** 科目名稱各家帳務系統不同，方向錯了帳就反了。

| 時點 | 55 金流寫入點 | 合約負債 | 收入 | 說明 |
|---|---|---|---|---|
| 後台發卡 | M27 | **↑** | 0 | 收到現金（或無償發放，見 §待查證）⇒ 遞延收入 |
| 禮品卡商品售出 | M28 | **↑** | 0 | 同上 |
| 儲值 | M29 | **↑** | 0 | |
| 兌換（結帳扣抵） | M30 | **↓** | **認列** | 履約義務完成 ⇒ 收入認列 |
| **退款回補至卡片** | M32 | **↑** | 0 | 🔴 **不是**收入沖銷 |
| 到期／停用（餘額未用完） | M31 | **↓**（breakage） | 見 (c) | |

> 🔴 **M32 是最容易做反的一條。** 退款回補到卡片是**負債增加**，做成「收入沖銷」會**同時少計負債與少計收入**——兩邊都錯，而且 nightly 恆等式抓不到（兩個錯誤互相抵銷）。56 §F 驗收 20 已把「方向錯即失敗」列為獨立一條，理由就在這裡。

### (b) 落庫（56 §B.3.1 J-01 的實作）

表 `contract_liability_entries(shop_id, source_type, source_id, direction, amount_cents, recognised_at, basis)`，唯一鍵 `(shop_id, source_type, source_id, direction)` ⇒ **同一筆金流只能落一次分錄**。與 55 §D G-16 的 `refund_transaction_allocations` 同性質——都是「純函式的輸出沒落庫，導致無法對帳」。

**寫入時機**：與餘額變動**同一個 transaction**（否則 crash 後餘額與分錄不一致，且無從補）。

**恆等式（property test，integer cents，無捨入點）**：
```
Σ liability_increase − Σ liability_decrease − Σ breakage_recognised == Σ outstanding_balance_cents
```

### (c) breakage（⚠ **V-28，保留待查證，不自補**）

已查證（HK-2，`hk-user`）：**依預期兌換模式比例認列，或於兌換可能性極低時認列**。

⚠ **待查證 V-28（不得自行決定）**：**估計方法**本身、以及**首年無歷史兌換資料時的處置**。`hk-user` 給了原則，沒給方法。

**定案前的處置**：`breakage_recognition_when_undecided: defer_all`——**不認列 breakage**，負債留著。保守側錯，**不得為了帳面好看提前認列**。
🔴 **但 `defer_all` 是行為不是藉口**：仍要建**兌換率 rollup** 並持續累積資料（`breakage_requires_redemption_rate_rollup: true`），否則永遠湊不出估計基礎，V-28 也就永遠結不了案。`breakage_rollup_min_history_months: null` ⚠ 同屬 V-28，不得自訂。

### (d) 商店抵用金（⚠ **V-29 ＝ 55 V-22 的 HK 版**）

⚠ **待查證**：抵用金在 HKFRS 下是**合約負債**還是**退款負債（refund liability）**。兩者的收入認列時點與金額都不同，差額等於抵用金全額。

🔴 **定案前的處置（本輪新訂，見 §H-8）**：`store_credit_when_undecided: record_with_undetermined_basis`——**不阻擋發放與使用**，金流照走，但每一筆落一列 `contract_liability_entries` 且 `basis: 'undetermined_v29'` ＋ 開人工覆核工單。
**理由**：`store_credit_on_issue/on_use` 兩鍵皆 `null`，若比照 tw 的 `resolver_refuses_start_when_undecided`，抵用金在香港會**永遠無法啟用**——**與 G-06 完全相同的病根**。56 §B.3.1 J-03 只登記了「兩個鍵皆 null ＋ verify 旗標」，**沒有寫定案前的行為**，等於把這個坑留在原地。已落 `store_credit_resolver_refuses_start: false`。

### (e) 併發安全（**法域無關的那一半**）

| 要求 | 內容 |
|---|---|
| 冪等 | `storeCreditAccountCredit/Debit`、`giftCardCreate/Credit/Debit/Deactivate` 皆 `idempotencyKey!` 必填（§G-08） |
| 第二層業務唯一鍵 | `giftCardDebit: (checkout_token, gift_card_id)`；`storeCreditAccountDebit: (checkout_token, store_credit_account_id)` |
| 條件式 UPDATE | `UPDATE … SET balance_cents = balance_cents − ? WHERE id = ? AND shop_id = ? AND balance_cents >= ?`；🔴 **禁止先讀後寫** |
| 累計上限 | `balance_cents` 恆 `>= 0`；抵用金另有 `max_balance_usd` 上限，**併發下同樣靠條件式 UPDATE**，不是靠寫入前 SELECT |
| 跨店檢查 | 條件式 UPDATE **之前**驗 `instrument.shop_id == checkout.shop_id`，不符回 `CROSS_SHOP_REDEMPTION_FORBIDDEN`。與餘額不足是**兩個失敗模式**，錯誤碼不得合併 |
| 到期 job | 冪等鍵 `UUID v5(scexpire, (store_credit_account_id, expiry_date))`（55 §A.3） |

> **關於跨店檢查的法源**（56 附錄 Z 已降級）：`redeemable_scope: issuing_shop_only` 自 2026-08-12 起從「SVF 法遵硬限制」降級為**設計預設**，複合外鍵與跨店檢查的理由改為**多租戶資料隔離**（CLAUDE.md 鐵律 2）。**技術動作完全不變，只是理由換了**——任何人日後看到「PSSVFO 不需考慮」，不得據此拿掉這些檢查。

**改了哪些檔案哪些行**

| 檔案 | 行 | 改了什麼 |
|---|---|---|
| `config/limits.yml` | **751–766**（+16） | `hk.accounting` 新增 `gift_card_entry_points`（M27–M32 六個時點的方向）／`refund_to_instrument_is_liability_increase`／`invariant`（恆等式） |
| `config/limits.yml` | **776–779**（+4） | `breakage_requires_redemption_rate_rollup: true` ＋ `breakage_rollup_min_history_months: null`（⚠ V-28） |
| `config/limits.yml` | **787–792**（+6） | 抵用金定案前處置：`store_credit_when_undecided` ＋ `store_credit_resolver_refuses_start: false` ＋ TW/HK 答案不可互套的說明 |
| `docs/research/06-data-model.md` | **223–245** | §7.1 `contract_liability_entries` 表定義與唯一鍵（與 G-04 同一處） |
| `docs/research/28-api-contract.md` | **208、212–222、234–243** | 抵用金契約列（原本整組不存在）＋ 兩組硬要求（與 G-08 同一處） |
| `docs/specs/55-money-tax-event-inventory.md` | **356**（G-07 列 +1 欄） | 法域適用性欄，明寫「併發安全那一半法域無關，不得漏掉」 |

**測試案例**

| # | 測試 | 斷言 |
|:--|---|---|
| T1 | 售出 ⇒ 兌換（56 §F 驗收 18） | 售出：合約負債 **+N**、收入 **+0**；兌換：合約負債 **−N**、收入 **+N** |
| T2 | 恆等式 property test | `Σ 合約負債變動 + Σ 已認列收入 == Σ 售出面額`，1 ～ 1,000,000 cents 全域成立，integer cents |
| T3 | **M32 方向**（56 §F 驗收 20） | 退款回補至禮品卡 ⇒ `contract_liability_entries.direction == liability_increase`。**做成收入沖銷即失敗** |
| T4 | breakage 保守側（56 §F 驗收 19） | 首年無歷史資料 ⇒ breakage **不認列**，負債留著 |
| T5 | 分錄不重複 | 同一筆 `giftCardDebit` 冪等重放 ⇒ `contract_liability_entries` **不增列**（唯一鍵擋下） |
| T6 | 分錄與餘額同 transaction | 寫入分錄後 raise ⇒ 餘額與分錄**皆未生效** |
| T7 | 抵用金未定案不擋 | HK 商店發放並使用抵用金 ⇒ **成功**；分錄 `basis == 'undetermined_v29'` 且開出人工覆核工單 |
| T8 | 併發扣抵 | 同一張禮品卡在兩個 checkout 同時扣抵全額 ⇒ 恰 1 筆成功，`balance_cents` 不為負 |
| T9 | 抵用金累計上限併發 | 併發入帳至 `max_balance_usd` 邊界 ⇒ **不得突破** |
| T10 | 跨店 | A 店禮品卡在 B 店結帳扣抵 ⇒ `CROSS_SHOP_REDEMPTION_FORBIDDEN`，**餘額不變**；與餘額不足回不同碼 |

---

## H. 對 56 號分流的意見（8 條，**不靜默照做**）

> 任務要求「若發現 56 號的分流有遺漏或判斷錯誤，不要靜默照做——列出來並說明理由」。
> **結論先講：56 對 G-01 ～ G-07 的分流判斷沒有一條是錯的**，方向全部正確（G-08 則是**全檔未分析**，見 H-3）。問題集中在**落地不完整**——值寫進 `limits.yml` 了，但規格檔沒有對應的判斷；或者「要保留」的東西沒有可執行的落地物。以下 8 條本輪已全部修掉。
> **這三種缺口的共同點是「測試抓不到」**——它們都編譯通過、現有測試通過、review 時看起來已經處理好了。這正是 55 §D G-03 判語「掛勾寫了卻沒接上＝比沒寫更糟（**會讓人以為已處理**）」所描述的同一類危險。

| # | 條目 | 性質 | 問題 | 為什麼要緊 | 本輪處置 |
|:--|---|---|---|---|---|
| **H-1** | **G-01** | 🔴 **落地缺口（最嚴重）** | `block_multi_fulfillment_when_undecided: false` 只寫在 `limits.yml`，**唯一的呼叫端 16-F5.5(a) 的擋單規則當時完全沒有法域條件**（逐字「一律擋下」） | 照規格實作，HK 仍然卡死所有多次出貨的訂單——**56 想防的事情原封不動還在**。這與 G-03「掛勾寫了卻沒接上」是**同一個形態的缺陷**，只是 56 這次是自己犯 | 16-F5.5(a) 補判斷順序偽碼 ＋ 兩處 limits 補呼叫端指標 |
| **H-2** | **G-04** | 🔴 **落地缺口（不可逆）** | schema 裁決值 `multiple_invoices_per_order_allowed` 留在 `jurisdictions.tw.tax_invoice`，而 **`tw.enabled: false`**。56 §0.2 只寫了「schema 取聯集」的**原則**，沒有列舉 | 建表的人不會去讀一個未啟用的 pack。原則不可執行、列舉才能做成 migration 測試。錯了要**停機 migration** | 新增核心層 `limits.jurisdiction.schema_union_rules`（禁建索引／必建表／必備欄位三組）＋ `06 §7.1` |
| **H-3** | **G-08** | ⚠ **完全未分析** | 🔴 **56 全檔 grep `G-08` 命中數 ＝ 0**。「與法域無關」的結論方向正確（租戶那 9 支確實如此），但它是**由 §E.1 的缺席推得**的，不是被分析過的。因此 `required_for_platform` 的 **2 支是台灣統一發票專屬、HK 下不存在於 schema** 這個例外沒人發現 | CI 若照 `required_for` 做成無條件斷言，**HK 首發的 schema 快照測試會直接紅掉**。這一點掉在 56 §E.1 的 G-08 列與 §A.4 CI-3 之間的縫裡 | 新增 `required_for_platform_pack_scope`，CI 斷言方向隨 pack 反轉 |
| **H-4** | **G-02** | ⚠ **「保留」沒有落地物** | 56 說金流側軟上限「仍在、不要拿掉」，但 55 §A.2 那一列**只有式子與一句『條件式 UPDATE』**——沒有 SQL 樣式、沒有錯誤碼、沒有併發情境 | 實作者無從判斷 `affected == 0` 要回哪個錯誤碼，**而那直接決定前端要不要彈超額退款二次確認**。「留著」若沒有可執行的落地物，等於沒留 | 16-F5.1 補 (a)–(e) 完整可測式子 ＋ limits 補 6 鍵 |
| **H-5** | **G-05** | ⚠ **根因被讀窄了** | 56 §E.1 把 G-05 讀成「憑證面的事」（憑證面 N/A、訂單層保留） | G-05 的根因是**「router 入參語義不成立」**，與稅制無關。HK 下若照舊走 router，症狀從「0 元折讓」變成**「金額 0 的假退款列」**，一樣髒，而且因為 HK 沒有折讓可看，**更難被發現** | 16-F4.4 註釋補根因說明 ＋ 測試 T1 斷言「`refunds` 表零新增列」 |
| **H-6** | **G-06** | ⚠ **違反 56 自己的原則 2** | 旗標**移走**了（`gift_card` → `jurisdictions.tw.accounting`），但 HK 側**沒有寫出對應的 `false`** | 56 §0.2 原則 2 逐字「**未宣告 ≠ none**，缺值時不得靜默取預設」。「tw 有、hk 沒有」在程式上長得像「hk 忘了填」，讀到 `nil` 沿用預設 `true` 就會踩回同一個坑。**移走不等於關閉，關閉必須寫出來** | `hk.accounting.gift_card_resolver_refuses_start: false` ＋ 理由 |
| **H-7** | **G-07** | ⚠ **只涵蓋了一半** | G-07 原文有**兩個**缺口：①稅務定位 ②**併發安全**（無冪等、無條件式 UPDATE ⇒ 超額扣抵）。56 §E.1 只處理了①，②完全沒提 | ②**法域無關**——兩分頁同時結帳超額扣抵與賣方法域毫無關係。把 G-07 整條讀成「移到會計層了」會把②一起弄丟，而那是**顧客資損** | 28 §7 新增抵用金契約列（原本整組不存在）＋ 兩組硬要求 |
| **H-8** | **G-07(d)** | ⚠ **未定案缺處置** | 56 §B.3.1 J-03 對 V-29 只登記「兩鍵皆 `null` ＋ verify 旗標」，**沒寫定案前的行為** | 與 G-06 **完全相同的病根**：兩鍵 `null` ＋ 若沿用 tw 的「未定案拒絕啟動」⇒ 抵用金在香港永遠無法啟用。56 剛在 G-06 上發現這個坑，卻在 J-03 上留了同一個 | `store_credit_when_undecided: record_with_undetermined_basis` ＋ `store_credit_resolver_refuses_start: false` |

**一句話總結**：56 的**判斷**沒問題，**落地**有三種系統性缺口——①值進了 limits 但規格沒讀（H-1）②裁決埋在未啟用的 pack 裡（H-2）③「要保留」但沒有可執行的落地物（H-4、H-8）。這三種缺口的共同點是**測試抓不到**，因為它們都「編譯通過、現有測試通過」。

---

## I. 新增 ⚠ 待查證（V-34 ～ V-36）

> V-01 ～ V-14 見 `52 §附錄 A`；V-15 ～ V-20 見 `54 §3`；V-21 ～ V-24 見 `55 §F`；V-25 ～ V-33 見 `56 §E.2`。
> **規則不變：一律不自補規則。**

| # | 項目 | 為何不能自行決定 | 就地標記位置 |
|:--|---|---|---|
| **V-34** | **合約負債的計量幣別與匯率**：使用者實際訂單為 **HKD／MYR**（56 檔頭）。禮品卡以 MYR 售出、帳以 HKD 記時，合約負債用**發卡日匯率**還是**兌換日匯率**計量？兩者的差額（匯兌損益）落在哪個科目？ | HKFRS 21 的貨幣性／非貨幣性項目分類直接決定是否重評價，**未由本專案覆核**。56 §B.3.1 的五列分錄表隱含「單一幣別」，多幣別情境完全沒涵蓋。🔴 這不是理論問題——`currency_format.exponent` 在 HKD 是 2、TWD 是 0，跨幣別的 integer cents 換算本身就是本專案的既有風險點（56 §E.3 R8） | `jurisdictions.hk.accounting.contract_liability_measurement_currency`（待建，`null` ＋ `verify_*`）；本檔 §G-07(a) |
| **V-35** | **超額退款在 HKFRS 下的分錄方向**：`Σ refunded > 已認列收入` 時（46c:223 明載為合法情境），差額是**收入沖銷**（可能使該筆訂單收入為負）還是**認列為費用／顧客賠償**？ | 55 §B.1 T09 在 HK 的去向只標「會計」，56 §B.2.1 沒有展開。方向不同會讓損益表的「營收」與「營業費用」兩行都不一樣，且超額退款是**有權限就能做**的日常操作，不是罕見情境 | `jurisdictions.hk.accounting.over_refund_treatment`（待建，`null` ＋ `verify_*`）；本檔 §G-02 |
| **V-36** | **`jurisdiction_capability_skips` 的保留年限**：它是**稽核證據**（證明「沒開憑證是因為該法域無此制度」，不是漏開）。保留期該對齊哪一條——PDPO 的日誌保留（⚠ V-26，目前 `null`）？商業收據保存年限（⚠ `verify_hk_receipt_requirements`，目前 `null`）？ | 兩個參照對象**本身都還沒定案**，且該表在 HK 是高頻寫入（20 條稅務事件全走這裡，56 §B.2.1）——保留期定太短會在稽核時拿不出證據，定太長是儲存成本與 PDPO 最小化原則的衝突 | `jurisdiction.capability_skips_retention_years`（待建，`null` ＋ `verify_*`）；`06 §7.1` |

---

## J. 本輪改動清單

| 檔案 | 行數變化 | 改了什麼 | 對應 |
|---|---:|---|---|
| `config/limits.yml` | 1,086 → **1,185**（+99） | `jurisdiction.schema_union_rules`（+37）；`idempotency.jurisdiction_scope` ＋ `required_for_platform_pack_scope`（+10）；`refund` 金流累計上限 6 鍵（+14）；`hk.accounting` 分錄方向／恆等式／breakage rollup／抵用金未定案處置／禮品卡解析器明確 false（+33）；G-01 兩處呼叫端指標（+5） | G-01/02/04/06/07/08 |
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | 860 → **985**（+125） | F5.1 金流側累計檢查 (a)–(e)（+66）；F5.5(a) 擋單規則加法域條件（+29）；F5.5 節導言三層分工表（+16）；F4.4 COD 列改法域中性事件（+10）；F5.5(c) 第 5 點路徑與 schema 註（+8） | G-01/02/03/04/05 |
| `docs/specs/55-money-tax-event-inventory.md` | 481 → **515**（+34） | §D.1 P0 表新增「法域適用性」第 7 欄（8 列）；§A.2 開頭「11 條全部法域無關」；M09/M10 指向 16-F5.1；§E.3 `gift_card` 列標移動；§F 新增 V-20～V-24 法域歸屬表；§G 驗收 5–11 標 TW only ＋ 兩條例外 | 全 8 條 |
| `docs/research/28-api-contract.md` | 404 → **435**（+31） | §0.6 法域範圍（+7）；訂單／草稿單／禮品卡簽名補 `idempotencyKey!`；**新增商店抵用金契約列**與四條硬要求（+13）；禮品卡四條硬要求（+11） | G-06/07/08 |
| `docs/research/06-data-model.md` | 229 → **255**（+26） | **新增 §7.1 法域 schema**（四表對照 ＋ 為什麼是表不是 log）；既有表欄位變更補三條 | G-04/07 |
| `docs/specs/38-platform-trust-modules.md` | 2,790 → **2,810**（+20） | §3B 表註路徑更新 ＋ schema 聯集分流註釋（+11）；§6-3 `RefundRouter` 標 tw-only ＋ 明確 no-op ＋ 禁止「無呼叫端」寫法（+10） | G-02/03/04 |
| `docs/specs/57-p0-hk-baseline-fixes.md` | **新增** | 本檔 | — |

> **未觸碰**：`docs/design/*.html`（另一路人馬正在改，本輪一行未動——包含 56 §D.3／P0-9 的原型 market-driven 工作）、`docs/specs/15`／`36`／`37`／`39`、`docs/research/29`／`42`／`43`／`44`、`docs/specs/49`／`50`／`53`／`54`。這些是 56 §D 遷移計畫的其餘項目，**不在本輪 8 條 P0 的範圍內**。
> **台灣內容一行未刪**（56 §C.3）：38 §3B、16-F5.5、55 §B 仍然滿是統一發票內容是**刻意保留**，不是漏改。

---

## K. 本篇驗收（對照 11 §0 七維度）

**法域正確性**
1. HK 訂單分三次出貨 ⇒ 三次全部正常完成，人工佇列 **0** 筆（G-01 T1）。
2. HK 商店建立並兌換禮品卡 ⇒ 成功（G-06 T1/T2）。
3. HK 商店發放並使用商店抵用金 ⇒ 成功，分錄 `basis == 'undetermined_v29'`（G-07 T7）。
4. HK 下每一次「憑證動作消失」的事件 ⇒ `jurisdiction_capability_skips` 恰增一列。**靜默 return 即失敗**（G-01 T2、G-03 T1、G-05 T2）。

**schema 正確性（不可逆，優先）**
5. `einvoices` 無 `(shop_id, order_id)` 唯一索引（G-04 T1）。
6. 四張法域表在 HK 首發即存在（G-04 T2）。
7. `orders` 雙法域欄位 NOT NULL 且不回溯（G-04 T4）。
8. `gift_card_transactions` 複合外鍵擋得住繞過應用層的跨店寫入（G-04 T5）。

**金額與併發正確性（法域無關，防回退）**
9. 55 §A.2 的 **11 條**金流累計上限測試在 HK pack 下**全部仍須通過**（G-02 T6）。
10. 三個併發情境 C1/C2/C3 全綠；兩個錯誤碼分離（G-02 T1/T2）。
11. 合法超額退款不被 DB 層擋下（G-02 T4）。
12. `limits.idempotency.required_for` 的 22 支 resolver 全部有 `idempotencyKey`（G-08 T1）。

**會計正確性**
13. 售出 ⇒ 負債 +N／收入 +0；兌換 ⇒ 負債 −N／收入 +N（G-07 T1）。
14. 恆等式 property test 全域成立，integer cents（G-07 T2）。
15. **M32 退款回補至卡片 ⇒ 負債增加**，方向錯即失敗（G-07 T3）。
16. 首年無歷史資料 ⇒ breakage 不認列，但**發卡與兌換不受影響**（G-07 T4）。

**TW 防回退（未啟用不等於可以壞掉）**
17. 啟用 tw pack 後，G-01 T3／G-03 T3／G-05 T3／G-06 T4 四條原行為**全部仍須通過**——本輪對台灣的改動只有「加法域條件」與「加標歸屬」，**實質規則一字未動**。
18. `limits.jurisdiction._moved_keys` 的 17 條舊→新路徑對照，在 `16`／`38`／`55` 三檔中的引用逐條可解析（本輪已修其中 3 處，其餘列入 56 §D.1 的 P0-2／P0-3／P0-4）。

**可觀測**
19. `jurisdiction_capability_skips` 的寫入率有 metric；HK 下該值為 0 反而是**告警條件**（代表 dispatch 沒接上）。
20. `contract_liability_entries` 與 `gift_card_transactions` 的 nightly 對帳斷言（恆等式，§G-07(b)）。
