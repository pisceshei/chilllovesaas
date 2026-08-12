# 56 — 司法管轄區架構（Jurisdiction Pack）

> **緣由**：使用者 2026-08-12 裁定——先前整套規格預設**台灣**法遵，但實際營運主體與主要買家在**香港**（店家 email `.com.hk`、訂單為 HKD／MYR）。裁定逐字：「**基準法域＝香港**，其他市場之後擴充，**目標是全球市場**，所以稅務／會計／法律以香港為主，之後再做擴充。」`CLAUDE.md` 鐵律 10、11 已同步更新。
> **核心原則（本檔的全部價值）**：**不是把台灣換成香港，而是把「司法管轄區」抽成可插拔的一層（jurisdiction pack）**。香港是第一個實作；台灣既有內容降級為 `tw` pack 素材，**一行不刪**。
> **權威順序**（沿用 52／54／55）：官方開發文檔（46a/46b）＞ 官方商家文檔（46c）＞ 實測畫面（44）＞ 我方既有規格。**我方與官方衝突時一律改我方。**
> **法域規則的權威來源不同**：Shopify 不處理任何國家的稅務憑證，46a/46b/46c **不可能**是法域結論的來源。本檔凡法域規則一律標下方 §0.3 的出處等級，**不得偽裝成 Shopify 行為**。
> **金額鐵律**（CLAUDE.md 鐵律 3）：全程 **integer cents**。本檔不新增任何捨入點——16-F5.1 的三個捨入點仍是全部。
> **盤點日**：2026-08-12。**可追溯性**：本檔對既有檔案的改動留 `<!-- 依 … 修正，原文：… -->`，格式沿用 52／54／55。

---

## 0. 決議、原則與出處等級

### 0.1 使用者裁定（2026-08-12）

| 項 | 裁定 |
|---|---|
| 基準法域 | **香港（hk）** |
| 架構要求 | **可插拔的 jurisdiction pack**，因為目標是全球市場 |
| 台灣既有內容 | **降級為 `tw` pack 素材，不刪除**；標「未啟用，待台灣市場開通時實作」 |
| 核心規格 | **不得再直接引用** `統一發票／字軌／折讓／作廢／超商取貨／統編／電支條例`——要引就引 pack 的能力介面 |

### 0.2 三條設計原則

1. **法域是一層，不是一個欄位**。加一個 `country` 欄位再到處 `if country == 'TW'` 是本檔要防的正是那件事——55 號證明了「稅務動作沒跟上金流動作」是最貴的錯誤（55 §0.3），而 `if` 散落各處保證會漏。
2. **未宣告 ≠ none**。缺值時**不得靜默取預設**。`tax_invoice: none` 必須是香港 pack 裡**寫出來的一行**，不能是「沒填所以不開」。理由見 §A.3。
3. **schema 取所有 pack 的聯集，行為取當前 pack**。表可以為未啟用的法域預留（例如 `einvoices` 表在 HK 不會有資料，但 55 §D G-04「不得對 `(shop_id, order_id)` 建唯一索引」的結論仍要保留），**行為**則嚴格按解析出的 pack 走。上線後改不得的 schema 決定不能只按 default pack 做。

### 0.3 出處等級（在檔頭四級 dev／help／live／ours 之外新增兩級）

| 等級 | 意義 |
|---|---|
| `hk-user` | 使用者 2026-08-12 裁定時提供並**聲明已查證**的香港事實（四條，見 §0.4）。可直接引用。 |
| `hk-secondary` | 本檔查得的第二手來源（律師事務所刊物／立法會秘書處研究刊物／業者說明頁）。**可引用但須註明是二手**；法例原文未由本專案覆核。URL 見 §H。 |
| `⚠ 待查證` | 無明確出處。**一律不自補規則**（沿用 52 §附錄 A 的規則）。 |

### 0.4 已查證的香港事實（`hk-user`，四條，本檔直接引用不再重述來源）

| # | 事實 | 影響的能力 |
|---|---|---|
| HK-1 | **香港無增值稅／銷售稅／消費稅** ⇒ 沒有政府強制發票、沒有字軌、沒有折讓單、沒有作廢重開。**收據＝純商業單據**。 | `tax_invoice`、`consumption_tax`、`invoice_document` |
| HK-2 | 禮品卡**不是稅務時點問題，是會計問題**：HKFRS 15 → 售出＝**合約負債（遞延收入）**，兌換時才認列收入；未兌換 breakage 依**預期兌換模式比例**認列，或於**兌換可能性極低**時認列。 | `accounting` |
| HK-3 | 真正的監管約束是 **PSSVFO**（儲值支付工具條例，HKMA 主管）：**單一用途**（只能在發行商自己的店消費）**豁免**；跨多個不相關商戶＝多用途**需牌照**；**有限多場所豁免設 HK$1,000,000 儲值總額上限**。 | `stored_value_regime` |
| HK-4 | 隱私法是 **PDPO**（個人資料（私隱）條例），**不是**台灣個資法；稅號是 **BR number**（商業登記號），**不是**統編。 | `privacy_regime`、`tax_id_format` |

---

## A. 抽象層：jurisdiction pack 的能力介面

### A.0 法域怎麼解析出來（先解決這個，能力介面才有意義）

**一筆交易有兩個法域，不是一個。** 把兩者混成一個 `country` 欄位是本架構最容易犯的錯——跨境單會用錯稅制或宣告錯的消費者權利。

```
seller_jurisdiction  ← 營運主體稅籍所在地   決定：tax_invoice / consumption_tax / stored_value_regime
                                                / tax_id_format / invoice_document
buyer_jurisdiction   ← 收貨地／買家所在地   決定：privacy_regime / pickup_networks / currency_format
                                                / consumer_rights
```

**解析順序**（`limits.jurisdiction.resolution_order`，先命中先用）：

```
order_snapshot  →  market_jurisdiction  →  shop_operating_entity  →  platform_default(hk)
```

**三條硬要求**

1. **訂單成立即快照法域碼**（`orders.seller_jurisdiction` / `buyer_jurisdiction`）。理由與 15-F2「訂單存快照」、55 §B.1 T30「商店調整稅率設定不回溯」**完全同一條**：商家日後改市場，舊單不得跟著改法域。
2. **`jurisdiction` 是 market 的「不可繼承」維度**。29 §1.5 的繼承模型有 8 個 UI 維度，`NULL ⇒ 繼承`；**法域不適用這個語義**——子市場繼承父市場的法域會產生「香港母市場下掛台灣子市場卻套用香港稅制」的錯誤。處置比照 44:866 對 privacy 的既有實測結論（「運送與隱私權不繼承，永遠市場本地」），把 `jurisdiction` 定為**永遠市場本地**。這是 29 §1.5 必須新增的第 9 個維度（見 §D.1）。
3. **`platform_default` 只在「還沒有 market」的階段生效**（註冊流程、系統 job）。任何有訂單脈絡的路徑落到 `platform_default` 都是 bug，要記 warning。

### A.1 九項能力總表

| # | 能力 | 屬 | 值域（enum 或結構） | 核心流程在哪裡呼叫它 |
|---|---|---|---|---|
| C1 | `tax_invoice` | 賣方 | `none` ／ `gui`(TW 統一發票) ／ `lhdn_einvoice`(MY) ／ … | 16-F5.5 稅務事件發射點（開立／折讓／作廢／補開四類事件） |
| C2 | `consumption_tax` | 賣方 | `none` ／ `vat` ／ `gst` ／ `sst` ／ `business_tax`(TW 營業稅) | 15-F2 金額引擎；16-F5.1 X1–X6 退款稅額分攤 |
| C3 | `stored_value_regime` | 賣方 | `none` ／ `svf_pssvfo`(HK) ／ `epayment_act`(TW) ／ `emd`(EU) ／ … | 禮品卡 M27–M32、抵用金 M23–M26、37 清結算架構 |
| C4 | `privacy_regime` | 買方 | `pdpo_hk` ／ `pdpa_tw` ／ `gdpr` ／ `ccpa` ／ … | 38 §3A DSR 雙時鐘、§3C 外洩通報與稽核、日誌保留分層 |
| C5 | `tax_id_format` | 賣方 | 結構（label／regex／checksum／length／揭露義務） | 結帳期驗證（55 T27 原則：格式錯在結帳期擋下）、36 全域搜尋、38 前台合規巡檢 |
| C6 | `pickup_networks` | 買方 | 結構（providers／COD／材積／領件方式／離島規則） | 15-F3.1 結帳 → admin 交接、16-F3.3 取貨點出貨 |
| C7 | `currency_format` | 買方 | 結構（currency／symbol／exponent／position／grouping） | 序列化層 MoneyV2、Liquid `money` filter、原型 `fmt()` |
| C8 | `consumer_rights` | 買方 | 結構（鑑賞期天數／法定管道／適用法規／例外來源） | 16-F7.4(b) 退貨規則 B1–B4、前台退貨政策文案 |
| C9 | `invoice_document` | 賣方 | `tax_document` ／ `commercial_receipt` | 訂單狀態頁、通知信、單據 PDF 產生器 |

> **C1 與 C9 的分工**（最容易混的一對）：`tax_invoice` 是**監管管線**——有沒有政府強制的稅務文件、它的生命週期與編號治理；`invoice_document` 是**買家收到的那張紙**的法律性質。TW 兩者合一（統一發票既是稅務憑證也是買家單據）；**HK 是 `tax_invoice: none` ＋ `invoice_document: commercial_receipt`**——買家仍然收到單據，但它沒有稅務效力。少了 C9，工程師會以為「HK 不用開發票 ⇒ 不用出單據」，那是錯的。

### A.2 逐項能力契約

每一項寫三件事：**核心怎麼呼叫**、**pack 宣告後的行為**、**pack 未宣告時的 fallback**。

---

#### C1 `tax_invoice`

**核心怎麼呼叫**——核心**只發稅務事件，不生產憑證**。事件名稱一律法域中性：

```
TaxEvent = { kind, order_id, occurred_at, amount_cents, tax_cents, jurisdiction, source_write_point }
kind ∈ { sale_recognised, sale_reversed, sale_reduced, sale_increased, sale_uncollected }
#      ↑ 這五個 kind 取代 55 §B 的「開立／作廢／折讓／補開」——後四者是 **TW 的實作**，不是事件本身
```

`Jurisdiction::TaxInvoice.handle(event) -> [DocumentAction]`，`DocumentAction ∈ { issue, void, allowance, reissue, no_document }`。
凡 `no_document` 一律**落一列 `jurisdiction_capability_skips`**（capability、jurisdiction、event kind、reason），不得靜默返回。

**已宣告的行為**

| 值 | 行為 |
|---|---|
| `none` | 全部事件回 `no_document`；**不建 `einvoices` / `einvoice_allowances` 的任何資料列**；`einvoice/*` outbox topic **不註冊**（不是註冊了沒消費者） |
| `gui` | 走 38 §3B 全套（字軌／保留號／作廢／折讓／`RefundRouter` 判定樹） |
| 其他 | pack 自行實作 |

**未宣告的 fallback**：`reject`。結帳與退款一律回 `userErrors{code: JURISDICTION_CAPABILITY_UNDECLARED}`。
**理由（這條最重要）**：`none` 與「沒填」在程式上長得一樣，但風險完全相反——「沒填」代表沒人想過這個市場的稅制，靜默當成 `none` 就是系統性漏開憑證。這正是 55 §D G-03「掛勾寫了卻從不呼叫，比沒寫更糟」的同一種缺陷，換到法域層。

---

#### C2 `consumption_tax`

**核心怎麼呼叫**：15-F2 金額引擎呼叫 `Jurisdiction::ConsumptionTax.compute(line, market)`；16-F5.1 X1–X6 的退款稅額分攤呼叫 `.allocate_refund(...)`。

**已宣告的行為**：`none` 時仍然寫 `tax_cents: 0`，**並帶 `tax_basis: no_consumption_tax_regime`**。
🔴 **不得**用「稅額欄位留空」表示無稅制——報表與 nightly 對帳必須分得出「這個法域沒有消費稅」與「稅算漏了」。這兩者在資料上都是 0，只有 `tax_basis` 分得出來。

**未宣告的 fallback**：`reject`（擋在結帳，不是擋在出貨）。
**🔴 不得 fallback 到 0%**——靜默 0% 稅＝短報，且錯誤會在數月後的申報期才浮現，屆時訂單已不可逆。

---

#### C3 `stored_value_regime`

**核心怎麼呼叫**：`giftCardCreate` / `giftCardCredit` / `giftCardDebit` / `storeCreditAccountCredit` / `storeCreditAccountDebit`（55 §A 的 M23–M32，共 9 條金流寫入點）在**寫入前**呼叫 `Jurisdiction::StoredValue.authorise!(instrument, shop, checkout)`。

**已宣告的行為**：見 §B.3（HK）與 §C.1（TW）。共通結構：
`single_purpose_exempt` / `cross_shop_redemption_allowed` / `float_cap_cents` / `no_fund_pooling` / `platform_wide_instrument_forbidden`。

**未宣告的 fallback**：`reject`——**禁止發行任何儲值工具**（9 支 mutation 全部回 `userErrors`）。
**理由**：儲值是**牌照風險**不是資料風險。不知道當地監管就先發卡，最壞後果是平台無照經營，這不是事後補資料能修的。這是九項能力中唯一「fallback 到完全停用」的一項。

---

#### C4 `privacy_regime`

**核心怎麼呼叫**：38 §3A 的 DSR 雙時鐘取 `statutory_due_at`；§3C 的外洩通報取 `notification_hours` 與主管機關；審計日誌保留分層（38 §12 C1）取 `log_retention_years`。

**未宣告的 fallback**：`manual_queue` ＋ **以「已宣告 pack 中最嚴者」為內部 SLA**，UI 標「法定期限待確認」。
**理由**：這是 38:885／38:1146 的**既有處置**（`regime='pdpa_tw'` 的 `statutory_due_at` 留 `null` ＋ UI 標記），本檔只是把它從「台灣的特例」提升為「所有法域的通則」。**不得無 SLA**——沒有時鐘的 DSR 就是永遠不會處理的 DSR。

---

#### C5 `tax_id_format`

**核心怎麼呼叫**：結帳表單的 B2B 稅號欄位、36 §全域搜尋的「純數字自動判為稅號」、38 §3D 前台合規巡檢的「揭露的稅號 == `shops.tax_id`」。

**未宣告的 fallback**：**欄位隱藏且不得收集**。
**🔴 不是「收了不驗」**——收進來卻無從驗證的稅號是髒資料，會在日後啟用該 pack 時全部變成待清洗記錄，且 B2B 買家會誤以為系統已接受他的稅號。

---

#### C6 `pickup_networks`

**核心怎麼呼叫**：15-F3.1（結帳選門市 → 快照落 `order_pickup_points`）、16-F3.3（admin 側出貨）。

**未宣告的 fallback**：該市場的「取貨點」配送方式**不出現**（`hide_delivery_method`）。
**🔴 不是「出現但選不了」**——買家看到一個永遠灰掉的選項只會去開客服工單。

---

#### C7 `currency_format`

**核心怎麼呼叫**：序列化層 `MoneyV2`／`MoneyBag`（CLAUDE.md 鐵律 3）、Liquid `money` filter、原型 `fmt()`。

**未宣告的 fallback**：**走 CLDR／ICU 的 locale 預設**，並記 warning。
**這是九項中唯一允許 fallback 到通用實作的一項**——因為 CLDR 是可信的通用來源，猜錯了頂多是顯示不合當地習慣，不會產生法律或金額後果。其餘八項的錯誤都不可逆。

---

#### C8 `consumer_rights`

**核心怎麼呼叫**：16-F7.4(b) 的 B1–B4（儲存警示／法定管道／最終銷售例外／預設快照）。

**未宣告的 fallback**：只走**商家自訂退貨規則**，且 UI **不得出現任何「依法…」字樣**，同時登記待查證。

> 🔴 **這一項的 fallback 方向與其他八項相反，必須特別注意**。其他能力的風險是「少做」；`consumer_rights` 的風險是**「多做」**——宣稱一個當地不存在的法定權利，本身就是對買家的不實陳述。香港正是這個情形（§B.5）。

---

#### C9 `invoice_document`

**核心怎麼呼叫**：訂單狀態頁的「單據」區、通知信範本、單據 PDF 產生器。

**已宣告的行為**：`tax_document` ⇒ 走 C1 的憑證管線；`commercial_receipt` ⇒ 由平台自行編號（`numbering_authority: merchant`），修改機制為 `free_form`（直接改開／註記，**沒有**「作廢重開」的法定程序），且**單據上必須明示「本文件非稅務憑證」**（`must_state_not_a_tax_document: true`）。

**未宣告的 fallback**：只產生 `commercial_receipt` 並標「本文件非稅務憑證」。
**理由**：這是唯一「猜保守側」不會出錯的方向——把稅務憑證當商業收據出，買家會來要正式憑證（可修正）；反過來把商業收據當稅務憑證出，就是偽造憑證（不可修正）。

---

### A.3 Fallback 總則：三種合法行為，禁止第四種

| 行為 | 什麼時候用 | 落地要求 |
|---|---|---|
| `reject` | 動作**尚未發生**、可以擋在門口（結帳、發卡、DSR 建立） | 回 `userErrors{code: JURISDICTION_CAPABILITY_UNDECLARED, field, message}`，HTTP 恆 200（鐵律 4） |
| `manual_queue` | 動作**已經發生**且不可逆（金流已成立、退款已生效） | **不得回滾業務**；開工單並在 admin 顯示「本筆待法域覆核」。比照 55 §D G-01「定案前擋下並轉人工佇列」的既有處置 |
| `documented_no_op` | 該法域**確實**沒有對應動作（例如 HK 的憑證動作） | **必須**落一列 `jurisdiction_capability_skips(shop_id, jurisdiction, capability, event_kind, reason, occurred_at)` |

**🔴 禁止的第四種：靜默略過（含靜默取預設值）。**
理由寫在 55 號的兩條 P0 裡，本檔只是換一層：
- G-03——`EinvoiceVoidPolicy.window_open?` 掛勾**寫了但 router 從不呼叫**：「掛勾寫了卻沒接上＝比沒寫更糟（會讓人以為已處理）」。
- G-05——COD 未取件退回走退款 router，**入參語義不成立**，三分支全部落到「折讓 0 元」：一個看起來成功的靜默錯誤。

法域層的等價形態就是：`if jurisdiction_pack.tax_invoice.nil? then return end`。它會**編譯通過、測試通過、上線後靜默漏開所有憑證**。`jurisdiction_capability_skips` 這張表的唯一目的，就是讓「什麼都沒做」變成**看得見的一列資料**。

### A.4 pack 的載入、gate 與 CI 驗收

| 項 | 規則 |
|---|---|
| **必宣告** | `limits.jurisdiction.required_capabilities` 的九項，每個 `enabled: true` 的 pack 都必須有值（`null` 也算「有宣告」，但必須同時有 `verify_*: true`） |
| **啟用 gate** | `jurisdictions.<code>.enable_gate` 列出「未結案前不得啟用」的待查證編號。`tw` 的 gate＝`[V-04, V-05, V-06, V-20, V-21, V-22, V-23, V-24]` 八條——55 號已證明這些未定案項會導致重複開立或漏開，**帶著它們啟用台灣市場等於已知會出錯還上線** |
| **解析器拒絕啟動** | gate 未清空即嘗試啟用 ⇒ `resolver_refuses_start_when_gate_unmet: true`（比照 54 號 V-02 對 shipping 解析器的既有處置） |
| **CI-1** | 每個 enabled pack 的九項能力都有宣告值（缺一即 fail） |
| **CI-2** | `app/` 下不得出現 `統一發票／字軌／折讓／統編／超商取貨／電支條例` 這六個字串的硬編碼分支；只能出現在 `jurisdiction/tw/` 目錄下 |
| **CI-3** | `app/services` 下任何寫入 `einvoice/*` outbox 的類別，都必須在 `jurisdiction/tw/` 命名空間內（HK 為 default 時該路徑不應存在任何呼叫）。這是 55 §G 第 12 條 CI 檢查的法域版改寫 |
| **CI-4** | `limits.yml` 的 `jurisdictions.*` 之外，不得出現 `tw_` / `hk_` 前綴的鍵（防止法域值又漏回核心） |

---

## B. `jurisdiction/hk` pack

### B.1 能力值總表

| 能力 | 值 | 出處 |
|---|---|---|
| `tax_invoice` | **`none`**；`issues_documents: false`；無 numbering／void／allowance／reissue 機制 | **HK-1**（`hk-user`，已查證） |
| `consumption_tax` | **`none`**；`rate_bp: 0`；`taxes_included_default: false`；`tax_basis_label: no_consumption_tax_regime`；`zero_rated_exports: null`（沒有稅率就沒有零稅率） | **HK-1**（已查證） |
| `stored_value_regime` | **`svf_pssvfo`**；`single_purpose_exempt: true`；`cross_shop_redemption_allowed: false`；`redeemable_scope_enum: [issuing_shop_only]`；`platform_wide_instrument_forbidden: true`；`limited_premises_float_cap_cents: 100_000_000`（HK$1,000,000）；`no_fund_pooling: true` | **HK-3**（已查證）＋ `hk-secondary`：ONC《PSSVFO》說明——Schedule 3 單一用途豁免、Schedule 8 多用途豁免（逐字「HK$1,000,000 or its equivalent」）。**法例原文未由本專案覆核** |
| `accounting` | `framework: hkfrs`；`gift_card_on_sale: contract_liability`；`gift_card_on_redeem: recognise_revenue`；`gift_card_breakage_method: expected_redemption_pattern_or_remote`；`breakage_recognition_when_undecided: defer_all` | **HK-2**（已查證）；breakage 估計方法 **⚠ V-28** |
| `privacy_regime` | **`pdpo_hk`**；DSR 天數／通報時限／通報是否強制／跨境傳輸／日誌保留 **全部 `null`**；`fallback_sla_source: strictest_enabled_pack` | **HK-4**（法規名稱已查證）；細節 **⚠ V-26** |
| `tax_id_format` | `label: BR number`；regex／checksum／length **全部 `null`**；`storefront_disclosure_required: null` | **HK-4**（是 BR number 已查證）；格式 **⚠ V-25** |
| `pickup_networks` | `available: true`；`model: carrier_network_brand`；providers 與**所有合約值 `null`** | `hk-secondary`：順豐（SF Express）聚合的 EF Locker 智能櫃／順豐站／合作便利店（7-Eleven、Circle K、VanGO），逾 1,000 點。**合約值全部 ⚠ V-27** |
| `currency_format` | `HKD`；`symbol: "HK$"`；`exponent: 2`；prefix；grouping `[3]` | `hk-secondary`（ISO 4217）。CLAUDE.md 鐵律 10 的示例 `HK$1,480` 是整數金額的顯示樣態，**不代表 exponent 為 0** |
| `consumer_rights` | `cooling_off_days: null`；`statutory_channel_required: false`；**`statutory_channel_forbidden: true`**；`applicable_laws: [TDO, SGO]` | `hk-secondary`：立法會秘書處《E-consumer protection》ISE08/19-20——香港**無**通訊交易法定鑑賞期，適用 TDO 與 SGO。條文原文 **⚠ V-33** |
| `invoice_document` | **`commercial_receipt`**；`mandatory: false`；`numbering_authority: merchant`；`amendment_mechanism: free_form`；**`must_state_not_a_tax_document: true`** | **HK-1**（收據＝純商業單據，已查證） |

### B.2 `tax_invoice: none` 對 55 號 30 條稅務事件點的影響

#### B.2.1 逐條重分類（30 條）

**四種去向**：
`會計` ＝ 憑證動作消失，但仍是收入或負債的變動，必須記帳
`消失` ＝ 在 HK 完全沒有對應動作（連會計動作都沒有）
`轉移` ＝ 改由另一項能力承接
`不變` ＝ 本來就不是消費稅事件，不受影響

| # | 55 號事件 | TW 的動作 | **HK 的去向** | 說明 |
|---|---|---|---|---|
| T01 | 訂單成立且付款成功 | 開立 | **會計** | HKFRS 15 收入認列（控制權移轉時）；買家收 `commercial_receipt` |
| T02 | 整張訂單出貨完成 | 開立 | **會計** | 同上。TW 的 `issue_timing` 三選一在 HK **消失**，取而代之的是「收入認列時點」——語義相近但**法域效力完全不同**（一個是稅務憑證時點，一個是會計認列時點），**不可沿用同一個設定鍵** |
| T03 | **部分出貨的開立粒度**（G-01 P0） | ⚠ 未定案＋擋單 | **消失** | 🔴 **最重要的一條**：沒有憑證就沒有粒度問題。且 G-01 的處置「定案前擋下並轉人工佇列」若照搬到 HK，會把**所有多次出貨的訂單卡死**。已在 `jurisdictions.hk.tax_invoice.block_multi_fulfillment_when_undecided: false` 明文關閉 |
| T04 | 買家收貨（含 PICKUP_POINT 實際領件） | 開立 | **會計** | 同 T02 |
| T05 | 訂單取消，尚未開立 | no-op | **消失** | 本來就是 no-op |
| T06 | 訂單取消，已開立（全額） | 作廢／窗關⇒折讓 | **會計** | 收入沖銷；無憑證動作 |
| T07 | 全額退款 | 作廢／窗關⇒折讓 | **會計** | 銷貨退回；無憑證動作 |
| T08 | 部分退款 | 折讓 | **會計** | 同上 |
| T09 | 超額退款（G-02） | 沖至歸零＋轉人工 | **會計** | 憑證面消失；**但金流側的 `Σ refunded ≤ maximumRefundable` 軟上限仍在**（那是 55 §A.2 的不變量，不是 §B 的） |
| T10 | 多次部分退款（G-02） | 每次各開一張折讓＋累計上限 | **會計** | 「折讓累計上限」在 HK **N/A**（見 §E.1） |
| T11 | 訂單編輯 commit 總額**下降** | 折讓 | **會計** | 收入沖減 |
| T12 | 訂單編輯 commit 總額**上升** | 補開一張新發票 | **會計** | 追加收入。G-04「一訂單多發票」的**稅務理由** N/A，但**結論保留**（§E.1） |
| T13 | 換貨（等值，`net == 0`） | ⚠ 暫定 no-op | **消失** | 無金額變動、無憑證 |
| T14 | 換貨（買家補差額） | 補開一張 | **會計** | 追加收入 |
| T15 | 換貨（退差額） | 折讓 | **會計** | 收入沖減 |
| T16 | 退貨費用扣抵 | 不另開立；⚠ 費用是否課稅（V-16） | **消失** | 「費用是否課稅」在 HK **直接 N/A**（無消費稅） |
| T17 | COD 未取件退回（G-05） | 訂單層作廢 | **會計** | 憑證面消失；**訂單層 `PENDING → VOIDED` 的金流與庫存處理原樣保留** |
| T18 | 爭議敗訴（V-24） | ⚠ 不自動折讓 | **會計** | 憑證面消失；HKFRS 下的處理 **⚠ V-30**，定案前不自動沖銷、開人工工單 |
| T19 | **禮品卡發行／售出** | ⚠ V-21 開立時點二選一 | **會計** | 🔴 **性質改變**：HKFRS 15 合約負債（已有答案），不是「開立時點」。**V-21 在 HK 不成立** |
| T20 | **禮品卡兌換使用** | ⚠ V-21（與 T19 互斥） | **會計** | 兌換時認列收入。TW 的風險是「兩邊都開＝重複課稅」；**HK 的風險換成「兩邊都認列＝虛增營收」**——風險沒消失，只是換了形態 |
| T21 | 禮品卡到期／停用（餘額未用完） | ⚠ 未定義 | **會計** | **HK 有明確答案**：breakage 依預期兌換模式比例認列，或於兌換可能性極低時認列（HK-2） |
| T22 | 商店抵用金**發放** | ⚠ V-22 暫定不開立 | **會計** | 負債認列；分類 **⚠ V-29**（合約負債 vs 退款負債） |
| T23 | 商店抵用金**用於結帳** | ⚠ V-22「付款方式 vs 折扣」決定發票金額 | **會計** | 🔴 **問題不消失，改性質**：在 TW 決定**發票金額**，在 HK 決定**收入認列金額**。仍待查證（V-29） |
| T24 | 退款分配到禮品卡／抵用金（V-20） | ⚠ 折讓基數是否扣除 | **會計** | 折讓基數問題消失；**合約負債回補**的會計面仍在（退到禮品卡＝負債增加，不是收入沖銷） |
| T25 | 跨境 DDP（含關稅） | M4 刻意不做 | **不變** | 關稅是**進口國**的事，與 HK 有無銷售稅無關。維持 M4 不做（46a:820） |
| T26 | 跨境 DDU／外銷零稅率 | ⚠ 未覆核（G-21） | **消失** | 沒有稅率就沒有零稅率。**但衍生新風險**：賣往有 VAT／GST 的市場時，**買方所在地**的代收註冊義務 ⚠ **V-31** |
| T27 | B2B 統編（三聯式） | 開立時帶 `buyer_tax_id`；8 碼檢核 | **轉移** | 改由 `tax_id_format`（BR number）承接。「三聯式」概念消失；收據上放 BR number 是否有法定義務 ⚠ V-25 |
| T28 | 捐贈發票（愛心碼） | 開立時帶愛心碼 | **消失** | 台灣特有 |
| T29 | 載具（會員／手機條碼／自然人憑證） | 開立時帶 carrier | **消失** | 台灣特有 |
| T30 | 商店調整稅率設定 | 不回溯，取訂單快照 | **消失** | HK 無稅率可調 ⇒ 事件消失。🔴 **但「快照原則」本身是法域無關的核心規則，不得因此刪掉**（未來 VAT pack 需要，且 §A.0 的法域快照就是同一個原則） |

**統計**

| 去向 | 數量 | 條目 |
|---|---|---|
| **會計**（憑證消失、仍需記帳） | **20** | T01, T02, T04, T06–T12, T14, T15, T17–T24 |
| **消失**（完全無對應動作） | **8** | T03, T05, T13, T16, T26, T28, T29, T30 |
| **轉移**（改由其他能力承接） | **1** | T27 |
| **不變** | **1** | T25 |

**55 §B.2「會造成已開立發票需折讓／作廢／重開的 11 個事件」在 HK 全部歸零。**
判定樹（55 §B.2 的 `route(order, refund_cash_cents)`）在 HK **不執行**——但它必須是**明確宣告的 no-op**（`documented_no_op` ＋ 落 skip 列），不是「沒有呼叫端」。這正是 G-03 的教訓。

#### B.2.2 55 §C 交叉矩陣在 HK 的降階

原矩陣 **41 × 6**（開立／折讓／作廢／補開／不涉稅／⚠未定義）。HK 下**前四欄整欄清空**，改為兩個會計欄：

| 矩陣版本 | 尺寸 | 欄位 |
|---|---|---|
| TW（55 §C 原表，保留） | 41 × 6 | 開立｜折讓｜作廢｜補開｜不涉稅｜⚠未定義 |
| **HK（本檔新增）** | **41 × 4** | **收入認列｜合約負債變動｜不涉帳（純資金移動）｜⚠未定義** |

**HK 矩陣的三條讀表結論**（對照 55 §C 的三條）

1. **「必然伴隨會計事件」的 7 條不變**（M09／M10／M13／M15／M16／M17／M20），只是右邊接的東西從「憑證動作」換成「收入／負債分錄」。**成對出現的要求完全不變**——這證明 55 號的盤點方法是對的，錯的只是它把 TW 的實作當成了事件本身。
2. **「不涉稅」的 13 條在 HK 變成「不涉帳」的 13 條**，仍需明文標註。理由沿用 54 §P1-06：「不標註的『沒做』下一輪稽核會重新開單」。
   ⚠ 例外：M38／M39（平台自己的帳單發票）**不受本 pack 影響**——那是平台向租戶收費，走平台營運主體的法域（見 §E.3 風險 6）。
3. **⚠ 未定義的格從 15 降到 8**：
   - **消失 7 格**：換貨與部分出貨（M07／M08／M12／M20，4 格，因為 T03／T13 在 HK 消失）＋退貨費用是否課稅（M11，1 格）＋禮品卡的 T19／T21 兩格（HKFRS 15 已有答案）
   - **保留 8 格**：禮品卡 M27／M29／M30／M32 的 breakage 與負債回補細節（⚠ V-28）、抵用金 M23／M24／M26（⚠ V-29）、爭議敗訴 M35（⚠ V-30）

### B.3 禮品卡與商店抵用金：HKFRS 15 會計 ＋ SVF 單一用途硬限制

這兩件事必須分開看：**會計決定「帳怎麼記」，SVF 決定「產品能不能這樣設計」**。後者是硬限制，前者是待落地的分錄。

#### B.3.1 會計（HKFRS 15，HK-2 已查證）

| 時點 | 分錄方向 | 對應 55 號金流寫入點 |
|---|---|---|
| 售出／發卡 | **合約負債（遞延收入）↑**，**不認列收入** | M27（後台發卡）、M28（禮品卡商品售出） |
| 儲值 | 合約負債 ↑ | M29 |
| 兌換（結帳扣抵） | 合約負債 ↓、**認列收入** | M30 |
| 退款回補至卡片 | 合約負債 ↑（**不是**收入沖銷） | M32 |
| 到期／停用（餘額未用完） | **breakage**：依預期兌換模式比例認列，或於兌換可能性極低時認列 | M31 |

**落地缺口（新增，登記不實作）**

| # | 缺口 | 處置 |
|---|---|---|
| **J-01（P1）** | 專案內**沒有任何合約負債的分錄落點**——`gift_card_transactions` 只有餘額變動，沒有「這筆變動對應哪個會計方向」 | 📌 建議表 `contract_liability_entries(shop_id, source_type, source_id, direction, amount_cents, recognised_at, basis)`，唯一鍵 `(source_type, source_id, direction)`。與 55 §D G-16 的 `refund_transaction_allocations` 同性質——都是「純函式的輸出沒落庫，導致無法對帳」 |
| **J-02（P1）** | **breakage 需要「預期兌換模式」的估計**，而估計需要歷史兌換率統計；專案內無此 rollup | 📌 需新增兌換率 rollup。⚠ **V-28**：估計方法未覆核；**首年無歷史資料時保守側錯——不認列 breakage**（`breakage_recognition_when_undecided: defer_all`），不得為了帳面好看提前認列 |
| **J-03（P2）** | 商店抵用金是**合約負債**還是**退款負債（refund liability）**未定——兩者的收入認列時點與金額都不同 | ⚠ **V-29**（＝55 號 V-22 的 HK 版）。`store_credit_on_issue` / `on_use` 皆 `null` ＋ verify 旗標 |

#### B.3.2 SVF 單一用途硬限制怎麼在資料模型與 UI 上強制

**分歧點（HK-3 已查證）**

```
每個租戶的禮品卡只能在該租戶自己店內使用   ⇒ 單一用途 ⇒ **豁免**，無需牌照
CHILL LOVE 發行跨租戶通用禮品卡           ⇒ 多用途   ⇒ **平台自己可能需要 SVF 牌照**
```

⇒ **產品級硬限制：CHILL LOVE 不發行跨租戶通用的儲值工具。**

**五層強制（缺一層都擋不住）**

| 層 | 做法 | 為什麼這一層不能省 |
|---|---|---|
| **1. 列舉** | `gift_cards.redeemable_scope` 的**列舉本身只有 `issuing_shop_only` 一個值**，`platform_wide` **不存在於列舉中** | 若做成「有值但預設關」，日後有人為了行銷需求把它打開，code review 看不出那是牌照風險。**讓錯誤選項根本不存在**是唯一可靠的做法 |
| **2. schema** | `gift_cards.shop_id NOT NULL`；`gift_card_transactions` 以**複合外鍵 `(shop_id, gift_card_id)`** 綁回卡片，**不是**單欄 `gift_card_id` | 單欄外鍵在應用層漏檢時完全擋不住跨店扣抵。複合外鍵讓 DB 成為最後一道防線。鐵律 2 已要求全表帶 `shop_id`，但那是**租戶隔離**；這裡是**業務語義**——兩個理由碰巧同一個欄位，不要以為做了前者就等於做了後者 |
| **3. mutation** | `giftCardDebit` / `storeCreditAccountDebit` 在條件式 UPDATE **之前**先驗 `instrument.shop_id == checkout.shop_id`，不符回 `userErrors{code: CROSS_SHOP_REDEMPTION_FORBIDDEN}` | 55 §A.2 已要求這兩支走條件式 UPDATE（防超額扣抵）；本檔在同一個位置加一道**跨店檢查**。兩者是不同的失敗模式，錯誤碼要分開 |
| **4. 平台層** | `Platform::` namespace **不得**存在任何跨租戶發卡／跨租戶扣抵的 mutation | 寫法比照 37:895 的既有做法——55 §A.1 的 M41 明文標註「它不是金流寫入點」，就是為了「任何人日後想加一支發起撥款的 mutation，本表就是擋下它的依據」。本節對跨租戶儲值起同樣作用 |
| **5. UI** | 後台發卡頁顯示「本卡僅限本商店使用」且**不可設定**（不是可設定但預設關）；平台後台**無**「發行通用卡」入口 | 一個「可以按但按了會壞」的按鈕遲早會被按 |

**替代設計（回答「那平台想做全站行銷活動怎麼辦」）**

平台想發放「全平台通用的抵用」⇒ **只能做成平台補貼的折扣碼**（17 號折扣引擎），由平台承擔成本、結算時補貼租戶。
差別在法律定性：**折扣是價格減讓，不是儲值**——買家從未把錢交給平台保管，因此完全不落入 PSSVFO。這是唯一合規的替代路徑，也是本節唯一的產品建議。
⚠ **V-32**：有限多場所豁免的 HK$1,000,000 上限適用主體是租戶還是平台、以及單一用途豁免下是否仍有 HKMA 申報義務——未覆核。我們走單一用途路線，這條是備援。

#### B.3.3 「不得資金池」在 HK 的法源更換（重要，容易搞錯方向）

37:895 的 TW-9 鐵律（不代收代付、不保管資金、租戶貨款直接進租戶自持商戶號、後台不得出現「平台錢包／提現」字樣）法源是**台灣《電子支付機構管理條例》**。

🔴 **不得因為「香港沒有電支條例」就放寬這條。** 在 HK，平台若代收代付貨款可能落入 PSSVFO 或其他金融監管範疇（⚠ 未覆核）。
**法源換了，結論不變**——既有的「租戶自持商戶號、平台不碰錢」架構在 HK 同樣安全，而且是更保守的做法。已在 `jurisdictions.hk.stored_value_regime.no_fund_pooling: true` ＋ `verify_hk_money_service_rules: true` 落地。

### B.4 HK 取貨網路與 TW 超商取貨的差異

**HK 側業者（`hk-secondary`，URL 見 §H）**：順豐（SF Express）聚合的自取網絡——**EF Locker** 智能櫃（24 小時）／**順豐站**（Service Centre）／**合作便利店**（7-Eleven、Circle K、VanGO），逾 1,000 點。

**六項結構差異**

| # | 面向 | TW（已查證，42:521–540 ECPay 合約） | HK | 狀態 |
|---|---|---|---|---|
| 1 | **模型層數** | **兩層**：carrier == brand（ECPay 直接對應 7-ELEVEN／全家／萊爾富／OK 四大超商） | **三層**：carrier（順豐）→ network（EF Locker／順豐站／合作便利店）→ brand（7-Eleven／Circle K／VanGO） | ✅ 已在 `model: carrier_network_brand` 表達。⚠ 是否另有非順豐的 HK 業者 **待查證** |
| 2 | **標準化枚舉** | 有 `LogisticsSubType`（8 種，ECPay 合約定義） | ⚠ 是否有等價枚舉 **待查證** | ⚠ V-27 |
| 3 | **COD** | 超商取貨**內建代收**，上限 NT$20,000 | ⚠ 是否支援、上限多少 **待查證** | ⚠ V-27 |
| 4 | **領件身分** | **手機號＋證件**（42:537 逐字） | ⚠ 待查證（智能櫃通常用取件碼／QR，但**未經證實，不寫入**） | ⚠ V-27 |
| 5 | **材積／重量** | 三邊和 ≤105cm、≤5kg（業界慣例，非官方文檔） | ⚠ 待查證 | ⚠ V-27 |
| 6 | **離島** | 外島門市常排除（`CVSOutSide=1`） | ⚠ 香港離島（長洲／南丫／大嶼山部分）是否有等價限制 **待查證** | ⚠ V-27 |

> 🔴 **不得把台灣的 NT$20,000／105cm／5kg 換算成 HKD／HK 規格充當 HK 值。** 這些是台灣物流商的合約值與業界慣例，與香港沒有任何關係。`jurisdictions.hk.pickup_networks` 的五個合約值鍵**全部保持 `null` ＋ `verify_hk_pickup_contract_values: true`**，pack 未宣告時該市場的取貨點配送方式**不出現**（§A.2 C6 的 fallback）。

### B.5 HK 消費者權利：不是少做一件事，是多做會出事

**已查證（`hk-secondary`，立法會秘書處《E-consumer protection》ISE08/19-20）**：香港**沒有**適用於網購／遠距交易的法定鑑賞期或解約權；適用的是 TDO（《商品說明條例》，禁止不公平營商手法）與 SGO（《貨品售賣條例》，貨品須有令人滿意的品質、符合說明）。該刊物逐字：「there is currently no specific legislation regulating online retail business in Hong Kong」。

**對 16-F7.4(b) 四條規則的影響**

| 規則 | TW | **HK** |
|---|---|---|
| B1 適用市場含 TW 且 `window_days < 7` 時儲存出警示 | 有效 | **不適用**（無警示） |
| B2 **法定管道恆存在**（配送日+7 天內一律提供「依消保法申請解約」入口） | 有效，且「這條才是真正的合規保證」 | 🔴 **禁止提供** |
| B3 B2 的入口對 `is_final_sale` 品項仍出現 | 有效 | **不適用** |
| B4 未設規則時 TW 市場預設 `window_days = 7` | 有效 | **不適用**（無法定預設） |

> 🔴 **B2 是本檔發現的最反直覺的一條。** 在香港提供「依法申請解約」入口，等於對買家宣稱一個**不存在的法定權利**——這本身可能構成 TDO 的不實陳述／誤導性遺漏。也就是說：在 HK，把 TW 的合規機制「順手也做上」**不是多一層保護，而是製造一個新的違法風險**。
> 這條已落地為 `jurisdictions.hk.consumer_rights.statutory_channel_forbidden: true`——注意它是**獨立的一個布林值**，不是 `statutory_channel_required: false` 的反面。「不要求」與「禁止」在程式上必須是兩個不同的判斷，否則實作者會把「不要求」讀成「做了也無妨」。

**HK 下平台該做什麼**：確保「商家公告的退貨政策被履行」（TDO 對不公平營商手法的規範）。⚠ **V-33**：具體條文與平台責任邊界未覆核。
**追蹤項**：消費者委員會 2018 年報告倡議對**特定行業**強制 7 天冷靜期，**尚未立法**（`pending_legislation_watch`）。立法後需回頭改本節。

### B.6 HK pack 的 ⚠ 待查證彙總

見 §E.2（V-25 ～ V-33，共 9 條）。

---

## C. `jurisdiction/tw` pack（既有內容歸位）

> **本節不產生新內容，只做歸屬標記與交叉引用。既有規格的實質內容留在原處，一行未刪。**
> **狀態：`enabled: false`——未啟用，待台灣市場開通時實作。**

### C.1 歸位對照表

| tw pack 能力 | 既有內容在哪裡（一律保留原處） | limits 新路徑 |
|---|---|---|
| `tax_invoice: gui` | `38 §3B`（38:964–1014 五張表）、`38 §6-3`（38:1256–1402 字軌監控／取號／`RefundRouter`）、`16-F5.5`(a)(b)(c)(d)（16:462–552 掛鉤點／判定樹／不變量）、`55 §B`（30 條事件點）、`42 §12.1`（42:518–526 結帳發票資訊區） | `jurisdictions.tw.tax_invoice`（原 `limits.einvoice` 40 鍵**整段搬入，內容一字未改**） |
| `consumption_tax: business_tax` | `16-F5.1` X1（含稅定價台灣預設）、`16-F5.2` 算例 2（TW 5% 內含）、`15:28`（含稅模式行級反推） | `jurisdictions.tw.consumption_tax`（稅率沿用 `tax_invoice.business_tax_rate_bp: 500`，不另立第二處真相） |
| `stored_value_regime: epayment_act` | `37 §3`／`37:479–491`／`37:895`（TW-9 無資金池鐵律）、`22:192`、`43:90`／`43:125`（渠道與連鎖的同一條紅線） | `jurisdictions.tw.stored_value_regime` |
| `privacy_regime: pdpa_tw` | `38 §3A`（DSR 雙時鐘）、`38 §3C`（`pdpa_incidents` 72 小時）、`38:1146`（`when "pdpa_tw" then nil`）、`38 §12 C1`（5 年 vs 12 個月保留期衝突）、`36:1152` | `jurisdictions.tw.privacy_regime` |
| `tax_id_format: 統一編號` | `42:520`（檢核演算法）、`36:26`／`36:397`／`36:415`／`36:457`／`36:1646`（搜尋與 schema）、`38:1400`／`38:1444`（前台揭露巡檢）、`39:552`（PII regex） | `jurisdictions.tw.tax_id_format` |
| `pickup_networks: 超商取貨` | `42 §12.2`（42:528–538 ECPay 電子地圖全流程）、`15-F3.1`（15:225–246）、`16-F3.3`（16:149–151）、`28 §11`、`22:199–202`、`44:322`／`44:335` | `jurisdictions.tw.pickup_networks`（原 `limits.pickup_point.carriers` 等五鍵搬入） |
| `cod`（台灣慣例值） | `42 §12.3`（42:542）、`15-F2.3`（COD 手續費行項）、`16-F4.4`（對帳回寫） | `jurisdictions.tw.cod`（原 `limits.cod.fee_cents_default_range` / `fee_taxable` 搬入） |
| `currency_format: TWD` | `42:508`（zh-Hant + TWD，NT$ 千分位無小數） | `jurisdictions.tw.currency_format` |
| `consumer_rights: 消保法七日` | `16-F7.4(b)` B1–B4（16:705–724）、`54 §P1-31`（處方更正的完整理由） | `jurisdictions.tw.consumer_rights`（原 `limits.return.tw_*` 五鍵搬入） |
| `invoice_document: tax_document` | 同 `tax_invoice`（TW 兩者合一） | `jurisdictions.tw.invoice_document` |
| `accounting`（禮券／購物金稅務時點） | `55 §B.1` T19–T23、`55 §F` V-21／V-22 | `jurisdictions.tw.accounting`（原 `limits.gift_card.tax_event_*`／`store_credit.tax_event_*`／`dispute.tax_event_on_lost` 搬入） |

### C.2 啟用 gate

```
jurisdictions.tw.enable_gate: [V-04, V-05, V-06, V-20, V-21, V-22, V-23, V-24]
```

**八條全部結案前，`tw` pack 不得啟用。** 理由：55 號已經逐條證明這些未定案項的後果是**重複開立／漏開／折讓總額超過發票金額**——帶著它們啟用台灣市場，等於已知會出錯還上線。
`resolver_refuses_start_when_gate_unmet: true`（比照 54 號 V-02 的既有處置）。

### C.3 不刪除聲明

<!-- 依使用者 2026-08-12 裁定「既有台灣內容不刪，降級為 jurisdiction/tw pack 的素材」歸位。
     本輪對台灣內容的**唯一**實質改動是 `config/limits.yml` 的區塊搬移（鍵名與值一字未改，只改路徑與縮排）；
     所有 .md 規格檔的台灣內容**一行未動**，只在本檔 §C.1 建立歸屬索引。
     🔴 任何人日後看到 38 §3B、16-F5.5、42 §12 仍然滿是台灣內容，那是**刻意保留**，不是漏改。
     去法域化的改動計畫在 §D.1，那是另一批工作，尚未執行。 -->

---

## D. 遷移計畫

> **這是計畫不是執行。** 除 §D.2 的 `limits.yml` 區塊搬移已於本輪完成，其餘**只列不改**。
> 「預估影響行數」＝新增 ＋ 改寫的合計，不含純標記行。

### D.1 核心規格去法域化（P0/P1/P2 逐檔）

| # | 檔案 | 現況 | 要改成什麼 | P | 預估行數 |
|---|---|---|---|:-:|---:|
| 1 | `docs/specs/16-spec-orders-fulfillment-refunds.md`（860 行／41 處） | F5.5 直接寫「開立／作廢／折讓／補開」；F3.3 寫「超商取貨」；F7.4(b) 寫台灣七日鑑賞期 | F5.5 改為**稅務事件發射器**（發 §A.2 C1 的五個法域中性 `kind`，由 pack 決定落地）；F3.3 改呼叫 `pickup_networks`；F7.4(b) 整段標為 tw pack 素材並新增「HK：`statutory_channel_forbidden`」對照；F4.4 COD 退回列的 `einvoice/void_requested` 改為 `TaxEvent(sale_uncollected)` | **P0** | ~120 |
| 2 | `docs/specs/38-platform-trust-modules.md`（2790 行／73 處） | §3B 電子發票是核心模組；§6-3 `RefundRouter` 無法域條件；§3C 寫死 `pdpa_tw` | §3B ＋ §6-3 整體標為 `jurisdiction/tw` 專屬實作（**不刪**），入口改為 pack dispatch；§3C 改為 `privacy_regime` 能力驅動；§3D 前台合規巡檢六項改為 pack 提供的規則集（HK 的六項內容 ⚠ V-33 待查證） | **P0**（它是 C1 的唯一實作） | ~150 |
| 3 | `docs/specs/55-money-tax-event-inventory.md`（482 行／68 處） | §B 30 條、§C 矩陣、§D 缺口全部以 TW 為前提 | §B.1 加「HK 去向」欄（素材＝本檔 §B.2.1，機械套用）；§C 加 HK 版 41×4 矩陣；§D 的 G-01/02/03/04/05/06/07/09 加「法域適用性」欄；§G 驗收 5–11 標「TW only」 | **P0** | ~80 |
| 4 | `config/limits.yml` | 見 §D.2 | 見 §D.2 | **P0** | ✅ **本輪已做**（+350） |
| 5 | `docs/research/06-data-model.md`（208 行／1 處） | 無 jurisdiction 概念 | 新增三張表：`jurisdiction_capability_skips`、`contract_liability_entries`（J-01）、`order_jurisdiction_snapshots`（或併入 `orders` 兩欄）；`gift_cards` 加 `redeemable_scope`；`gift_card_transactions` 改為**複合外鍵 `(shop_id, gift_card_id)`** | **P0**（schema 級，上線後改不得） | ~25 |
| 6 | `docs/research/29-markets-i18n.md`（§1.5） | 8 個可繼承維度，`NULL ⇒ 繼承` | 新增**第 9 個維度 `jurisdiction`，且明文「不可繼承，永遠市場本地」**（理由同 44:866 對 privacy 的實測結論）；否則子市場會繼承錯誤法域 | **P0** | ~20 |
| 7 | `docs/specs/36-platform-ops-modules.md`（2495 行／13 處） | `t.string :tax_id, limit: 8`（36:457、36:1646）；「輸入 8 位純數字自動判為統編」 | 🔴 **`limit: 8` 是寫死的台灣假設**，HK BR number 放不進去 ⇒ 放寬並加 `tax_id_jurisdiction` 欄；搜尋判定改由 `tax_id_format.regex` 驅動 | **P0**（schema 級） | ~25 |
| 8 | `docs/specs/15-spec-cart-checkout-payments.md`（385 行／6 處） | F2 稅計算假設含稅；F3.1 超商取貨；F2.3 COD 手續費 NT$ | F2 改呼叫 `consumption_tax`；F3.1 改呼叫 `pickup_networks`；F2.3 的 NT$30–60 標為 tw pack 值 | **P0** | ~40 |
| 9 | `docs/specs/18-spec-messaging-events-webhooks.md`（97 行／4 處） | 三個內部 topic `einvoice/*` 恆註冊 | 改為 pack-scoped：`jurisdiction.tw.einvoice/*`，且**pack 啟用時才註冊**（HK 下不存在這三個 topic） | P1 | ~10 |
| 10 | `docs/research/28-api-contract.md`（404 行／4 處） | §0.6 冪等、§11 pickup point、§15 topic 清單 | 同步 #9；`pickupPointProviders` 契約改為 pack 驅動；新增 `JURISDICTION_CAPABILITY_UNDECLARED` 與 `CROSS_SHOP_REDEMPTION_FORBIDDEN` 兩個錯誤碼 | P1 | ~20 |
| 11 | `docs/specs/37-platform-money-modules.md`（1431 行／1 處） | TW-9 電支條例鐵律 | 改為 `stored_value_regime.no_fund_pooling`，HK 值同樣 `true` 但**法源不同**（§B.3.3）。🔴 註明「不得因為 HK 沒有電支條例就放寬」 | P1 | ~15 |
| 12 | `docs/specs/49/50/53/54`（四份稽核登記表／共 29 處） | 條目未標法域 | 每條加「法域歸屬」欄（core／tw-only／hk-only）。**目的是防止下輪稽核把 tw-only 條目當成 HK 缺口重新開單**——這是 54 §P1-06 的既有教訓 | P1 | ~20 |
| 13 | `docs/research/42-storefront-full-inventory.md`（12 處） | §12「台灣在地補充」是前台三件套的規格來源 | 整章加標「本章為 `jurisdiction/tw` pack 素材，未啟用」；§11 的「台灣預設 zh-Hant + TWD」改為 market-driven | P1 | ~10 |
| 14 | `docs/specs/17-spec-discounts-engine.md`（3 處） | 17:35／17:114／17:117 的「**折讓**」指的是**折扣金額**，不是稅務折讓單 | 🔴 **命名衝突**：38／16／55 的「折讓」＝稅務折讓證明單（HK 下消失），17 的「折讓」＝折扣金額（法域無關，永遠存在）。改名為「折抵金額」以免實作者混淆 | P1 | ~5 |
| 15 | `docs/specs/11-production-baseline.md` §0 | 七維度的「合規」維度無定義 | 「合規」＝該市場所屬 pack 的九項能力全部已宣告且 gate 已清空 | P1 | ~8 |
| 16 | `docs/specs/39-platform-engineering-modules.md`（2965 行／15 處） | `einvoice` 佇列、feature flag `einvoice_auto`、PII regex `\b\d{8}\b`（統編） | 佇列與 flag 改為 pack 啟用時才註冊；PII regex 改由 `tax_id_format.regex` 提供 | P2 | ~20 |
| 17 | `docs/research/22`／`43`／`44`／`docs/design/33`／`40`（共 20 處） | 散落的台灣描述 | 加交叉引用到本檔，不改實質內容 | P2 | ~10 |

**小計**：P0 **8 檔**（~460 行，其中 limits.yml 已完成）／P1 **7 檔**（~88 行）／P2 **2 組**（~30 行）。

### D.2 `limits.yml` 重組（✅ 本輪執行）

| 動作 | 內容 |
|---|---|
| **新增 §0 `jurisdiction`**（契約） | `default: hk`／`resolution_order`／`snapshot_on_order`／`seller_capabilities`／`buyer_capabilities`／`required_capabilities`（九項）／`undeclared_capability_action: reject`／`allowed_fallback_actions`／`silent_skip_forbidden: true`／`resolver_refuses_start_when_gate_unmet`／`schema_is_union_of_all_packs`／**`_moved_keys`（17 條舊→新路徑對照）** |
| **新增 §14b `jurisdictions`**（packs） | `hk`（九能力 ＋ `accounting`，全部帶出處等級標記）／`tw`（`enabled: false` ＋ `enable_gate` 八條） |
| **整段搬移** | 頂層 `einvoice:`（40 鍵）→ `jurisdictions.tw.tax_invoice`。**鍵名與值一字未改**，只改路徑與縮排 |
| **拆分搬移** | `pickup_point.{carriers,cod_max_amount_twd,max_dimension_sum_cm,max_weight_kg}` → `jurisdictions.tw.pickup_networks`；`cod.{fee_cents_default_range,fee_taxable}` → `jurisdictions.tw.cod`；`return.tw_*`（5 鍵）→ `jurisdictions.tw.consumer_rights`；`gift_card.tax_event_*`（3 鍵）＋ `store_credit.tax_event_*`（2 鍵）＋ `dispute.tax_event_on_lost` → `jurisdictions.<code>.accounting` |
| **核心保留** | `api`／`idempotency`／`order`／`fulfillment*`／`return`（除 tw_*）／`refund`／`capture`／`inventory`／`product`／`collection`／`media`／`discount`／`cart`／`abandoned_checkout`／`checkout`／`location`／`shipping`／`pickup_point`（只剩機制鍵）／`cod`（只剩機制鍵）／`store_credit`／`gift_card`（併發與面額仍是核心）／`customer_account`／`content`／`notification`／`dispute`／`market`／`b2b`／`functions` |
| **新增硬限制鍵** | `gift_card.redeemable_scope: issuing_shop_only` ＋ `cross_shop_redemption_error_code`；`store_credit.redeemable_scope`（§B.3.2 第 1 層） |
| **行數** | **726 → 1,076（+350）**；YAML 解析通過，31 個頂層鍵 |

**遺留（列入 §D.1 #1/#2/#3 的 P0）**：`limits.einvoice.*` 的 **19 處**舊路徑引用仍散在 `16`／`38`／`55` 三檔中，需隨規格去法域化一併改為 `limits.jurisdictions.tw.tax_invoice.*`。`_moved_keys` 就是這批改動的對照表。目前無任何程式讀 `limits.yml`（專案仍在規格階段），因此搬移不會造成執行期斷裂。

### D.3 原型文案 market-driven（**不硬改成 HK**）

> **掛載點**：47 號量到、29 §1.5 收斂的**市場父子繼承模型**——加上 §D.1 #6 的第 9 個維度 `jurisdiction`（不可繼承）。原型 `chilllove-admin-v2.html:3153` 的 `MARKETS` 常數就是現成的掛載處。

| 檔案 | 現況 | 要改成什麼 | P | 預估行數 |
|---|---|---|---|---:|
| `docs/design/chilllove-storefront-v2.html` | `NT$` **47 處**；台灣詞 **28 處**。`fmt()`（S:1306）硬編 `"NT$"+…toLocaleString("en-US")`；結帳「發票資訊」區（S:2533–2563 四類型／三載具／統編／捐贈碼）；超商取貨 rate（S:2282／2404／2447） | `fmt()` 改讀 `MARKET.currency_format`（symbol／exponent／grouping）；發票資訊區改為 `MARKET.tax_invoice === 'gui' ? 發票區 : 收據說明區`；取貨方式改讀 `MARKET.pickup_networks`；FAQ／footer 文案改 market-driven | **P0** | ~120 |
| `docs/design/chilllove-admin-v2.html` | `NT$` **141 處**；台灣詞 **11 處**。`MARKETS`（A:3153）目前只有一個「台灣（預設）」 | 金額 formatter 集中化並讀 market；`MARKETS` 加香港市場（示範父子與法域不繼承）；顧客／訂單假資料改為 HK＋TW 混合（呼應真實營運：HKD／MYR） | P1 | ~180 |
| `docs/design/chilllove-platform-admin.html` | `NT$` **23 處**；台灣詞 **23 處**。`einvoice`／`shopinvoice` 兩張卡片、`frontscan` 四項達成率、統編欄 | 兩張發票卡片改為「**僅在租戶所屬法域 pack 提供 `tax_invoice` 時顯示**」（HK 租戶看不到，且**空狀態要說明原因**，不是靜默隱藏）；`frontscan` 六項改由 pack 提供；統編欄改 `tax_id_format.label` | P1 | ~80 |

**三條硬要求**
1. **不要硬改成 HK**——要做成 market-driven。把 `NT$` 換成 `HK$` 只是把同一個錯誤搬到另一個國家。
2. 改動後**必跑** `python3 scripts/lint-prototype.py`（ERROR 必須為 0，CLAUDE.md 工作方式）。特別注意「同檔頂層函式不得重名」——`fmt()` 集中化很容易踩到這條，那次事故是整頁功能靜默消失。
3. 三個原型的金額 formatter 必須**同源**（鐵律 7 數字同源的延伸）。

### D.4 P0 匯總

| P0 項 | 檔案 | 預估行數 | 狀態 |
|---|---|---:|---|
| P0-1 `limits.yml` 法域重組 | `config/limits.yml` | +350 | ✅ **本輪完成** |
| P0-2 16 號 F5.5 改稅務事件發射器 ＋ F3.3／F4.4／F7.4(b) | `docs/specs/16` | ~120 | 待做 |
| P0-3 38 號 §3B/§6-3 標為 tw 專屬 ＋ §3C 改能力驅動 | `docs/specs/38` | ~150 | 待做 |
| P0-4 55 號加 HK 去向欄／HK 矩陣／缺口法域適用性 | `docs/specs/55` | ~80 | 待做 |
| P0-5 06 號三張新表 ＋ `gift_cards.redeemable_scope` ＋ 複合外鍵 | `docs/research/06` | ~25 | 待做（**schema 級，上線後改不得**） |
| P0-6 29 §1.5 新增 `jurisdiction` 不可繼承維度 | `docs/research/29` | ~20 | 待做 |
| P0-7 36 號 `tax_id VARCHAR(8)` 放寬 | `docs/specs/36` | ~25 | 待做（**schema 級**） |
| P0-8 15 號 F2／F3.1／F2.3 改呼叫 pack | `docs/specs/15` | ~40 | 待做 |
| P0-9 storefront 原型 market-driven | `docs/design/chilllove-storefront-v2.html` | ~120 | 待做 |
| **合計** | 9 項 | **~930 行** | 1/9 完成 |

**建議順序**：P0-5／P0-6／P0-7（schema 與模型，改不得的先定）→ P0-2／P0-3／P0-8（規格）→ P0-4（55 號套用）→ P0-9（原型）。

---

## E. 風險與待查證

### E.1 已寫進 55 號、但在 HK **不成立**的結論

> **處置原則：不是「修掉」，是「移到 tw pack 且在 HK 標 N/A」。** 這些結論在台灣是對的，55 號沒有錯——錯的是它們被寫成了核心規則。

| 55 號條目 | 原結論 | 在 HK | 處置 | 危險等級 |
|---|---|---|---|---|
| **G-01** 部分出貨開立粒度 | ⚠ V-23 未定案；**定案前該組合擋下並轉人工佇列** | **N/A，且處置有害** | 🔴 照搬會把**所有多次出貨的訂單卡進人工佇列**。已在 `jurisdictions.hk.tax_invoice.block_multi_fulfillment_when_undecided: false` 明文關閉；擋單規則只在 `tax_invoice != none` 時生效 | **最高**（會造成營運中斷） |
| **G-02** 折讓累計上限 `Σ 折讓 ≤ 發票金額` | 硬不變量＋條件式 UPDATE | **N/A**（無折讓） | 移入 tw pack。🔴 **但金流側的 `Σ refunded ≤ maximumRefundable` 軟上限仍在**（55 §A.2，法域無關）——不要連這個一起拿掉 | 高（容易誤刪） |
| **G-03** 作廢窗已關 ⇒ 降級為全額折讓 | router fallback | **N/A** | 移入 tw pack | 中 |
| **G-04** 一訂單多發票；**不得**對 `einvoices(shop_id, order_id)` 建唯一索引 | schema 級裁決 | 稅務理由 N/A | 🔴 **結論保留**：schema 取所有 pack 的聯集（`schema_is_union_of_all_packs: true`）。HK 下該表不會有資料，但**若日後啟用 tw pack 才發現索引建錯，要停機做 migration** | 高（不可逆） |
| **G-05** COD 未取件退回走**訂單層**作廢，不走退款 router | 規格對接修正 | 憑證面 N/A | 訂單層 `PENDING → VOIDED` 的**金流與庫存處理原樣保留**，只是不再發 `einvoice/void_requested` | 中 |
| **G-06** 禮品卡 V-21「開立時點二選一」＋ `resolver_refuses_start_when_undecided: true` | 未定案時解析器拒絕啟動 | **問題性質改變** | 🔴 HK 是 HKFRS 15 合約負債（**已有答案**），不是開立時點。`resolver_refuses_start_when_undecided` 若照搬到 HK，因為 `tax_event_on_*` 永遠是 `null`，會讓**禮品卡在香港永遠無法啟用**。已移入 `jurisdictions.tw.accounting` 並限定 TW | **最高**（會造成功能永久不可用） |
| **G-07** 抵用金 V-22「付款方式 vs 折扣」 | 直接決定發票金額 | **不消失，改性質** | TW＝決定**發票金額**；HK＝決定**收入認列金額**（V-29）。**問題還在，答案不通用** | 高（容易誤判為已解決） |
| **G-09** 換貨三態的稅務事件 | 補差⇒補開／退差⇒折讓／等值⇒no-op | **N/A** | 移入 tw pack；HK 全部走會計 | 低 |
| **G-21 / T26** 外銷零稅率規則未覆核 | ⚠ 待查證 | **N/A**（沒有稅率就沒有零稅率） | 移入 tw pack。**但衍生 V-31**：賣往有 VAT／GST 市場的代收註冊義務——這是「目標全球市場」的真正稅務風險 | 高（新風險） |
| **T16 / V-16** 退貨費用是否課稅 | ⚠ 暫定不課稅 | **N/A** | 移入 tw pack（`jurisdictions.tw.cod.fee_taxable`） | 低 |
| **T27／T28／T29** 統編三聯／捐贈／載具 | 開立時帶對應欄位 | T28／T29 **完全消失**；T27 **轉移**至 `tax_id_format` | 移入 tw pack | 低 |
| **§B.3** 折讓基數公式（含 `business_tax_rate_bp: 500` 的含稅反推） | 收斂公式 ＋ floor 未稅 ＋ 差額法 | **N/A** | 移入 tw pack。🔴 **但「含稅／未稅雙模式」的結構保留**——未來任何 VAT／GST pack 都需要它 | 中 |
| **§E.2** `einvoice` 32 鍵 | 頂層區塊 | HK 下**完全不載入** | 已搬入 `jurisdictions.tw.tax_invoice` | — |
| **§G** 驗收 5–11（七條稅務驗收） | 折讓上限／作廢窗／在途／多發票／COD／稅額拆分／未定案擋下 | **全部 N/A** | 標「TW only」；HK 另立會計驗收（§F） | 中 |
| **§G** 驗收 12（交叉矩陣做成 CI 檢查） | `einvoice/*` 的呼叫端必須在矩陣有 ●／○ | **需改寫** | 改為 CI-3：非 tw pack 啟用時，`app/services` 下**不得存在**任何 `einvoice/*` 呼叫路徑 | 中 |

**一句話總結**：55 號的**方法**完全正確（由資料表反推、三個入口都掃、交叉矩陣防呆），錯的只是它把「台灣的憑證實作」寫成了「稅務事件本身」。本檔沒有推翻 55 號的任何一條發現，只是在它上面加了一層 dispatch。

### E.2 新增 ⚠ 待查證（V-25 ～ V-33，共 9 條）

> V-01 ～ V-14 見 `52 §附錄 A`；V-15 ～ V-20 見 `54 §3`；V-21 ～ V-24 見 `55 §F`。**規則不變：一律不自補。**

| # | 項目 | 為何不能自行決定 | 就地標記位置 |
|---|---|---|---|
| **V-25** | **HK BR number 的格式**（長度、分支碼、是否有檢核碼），以及**收據上是否有揭露義務** | `hk-user` 只確認「是 BR number，不是統編」，未給格式。🔴 `36:457`／`36:1646` 的 `tax_id VARCHAR(8)` 是寫死的台灣假設，HK 值可能放不進去——這是 **schema 級** 風險 | `jurisdictions.hk.tax_id_format.*` 全 `null` ＋ `verify_br_number_format: true`；本檔 §B.1、§D.1 #7 |
| **V-26** | **PDPO 細節**：DSR 法定回覆天數、資料外洩通報是否強制與時限、跨境傳輸條文的生效狀態、日誌保留年限 | `hk-user` 只確認法規名稱。38:885／38:1146 對台灣的等價問題已標「待定，需使用者確認」，香港同樣未覆核 | `jurisdictions.hk.privacy_regime.*` 全 `null` ＋ `fallback_sla_source: strictest_enabled_pack` |
| **V-27** | **HK 取貨網路的業者清單與合約值**：COD 支援與上限、材積／重量、離島限制、領件身分驗證方式、API 與回拋契約；以及**是否有非順豐的業者** | 唯一來源是第三方 app 供應商說明頁（`hk-secondary`），無合約值。🔴 **不得**把台灣的 NT$20,000／105cm／5kg 換算過來 | `jurisdictions.hk.pickup_networks.*` 五個合約值鍵全 `null`；本檔 §B.4 |
| **V-28** | **HKFRS 15 breakage 的估計方法**，以及**首年無歷史兌換資料時的處置** | `hk-user` 給了原則（依預期兌換模式比例／兌換可能性極低時），未給估計方法。無歷史資料時「預期兌換模式」無從估計 | `jurisdictions.hk.accounting.breakage_recognition_when_undecided: defer_all`（保守側錯，不提前認列）；本檔 §B.3.1 J-02 |
| **V-29** | **商店抵用金在 HKFRS 下是合約負債還是退款負債（refund liability）** | ＝55 號 V-22 的 HK 版。影響**收入認列金額**（若為折扣則收入較低，若為付款方式則收入＝商品總額），差額等於抵用金全額 | `jurisdictions.hk.accounting.store_credit_on_issue`／`on_use` 皆 `null`；本檔 §B.2.1 T22/T23、§B.3.1 J-03 |
| **V-30** | **chargeback lost 在 HKFRS 下的會計處理** | ＝55 號 V-24 的 HK 版。資金被扣回但商品未退回、買賣關係未解除——是壞帳、退款、還是收入沖銷，性質不同 | `jurisdictions.hk.accounting.chargeback_lost_treatment: null`；定案前不自動沖銷、開人工工單 |
| **V-31** | **跨境銷售時買方所在地的 VAT／GST 代收與註冊義務**（EU IOSS／UK／AU／SG 低價值貨物等） | 🔴 **這是「目標全球市場」的真正稅務風險，不是 HK 本地問題**。HK 賣方沒有本地銷售稅，但賣往有 VAT／GST 的市場時，義務落在**買方所在地**。55 號的 T26「外銷零稅率」完全沒有涵蓋這個方向 | `jurisdictions.hk.consumption_tax.verify_outbound_vat_obligations: true`；本檔 §B.2.1 T26 |
| **V-32** | **有限多場所豁免 HK$1,000,000 上限的適用主體**（租戶還是平台）；**單一用途豁免下是否仍有 HKMA 申報義務** | `hk-user` 給了數字與適用情境，未給主體歸屬。我們走單一用途路線，這條是備援，但若日後有跨店需求會立刻踩到 | `jurisdictions.hk.stored_value_regime.verify_svf_exemption_scope: true`；本檔 §B.3.2 |
| **V-33** | **TDO／SGO 對「商家公告退貨政策未履行」的具體條文與平台責任**；以及 HK 版的**前台合規巡檢六項**該檢什麼 | 立法會研究刊物（`hk-secondary`）只給了「有哪些法」，沒給條文與平台責任邊界。38 §3D 的前台合規巡檢六項是台灣專屬，HK 的等價清單完全空白 | `jurisdictions.hk.consumer_rights.verify_hk_consumer_law_details: true`；本檔 §B.5、§D.1 #2 |

**另外三條 `verify_*` 旗標**（未給 V 編號，因為屬於機制性確認而非法律結論）：
`jurisdictions.hk.stored_value_regime.verify_hk_money_service_rules`（平台若代收代付是否落入其他 HK 金融監管）、
`jurisdictions.hk.currency_format.verify_hkd_display_convention`（HKD 顯示是否隱藏 `.00`）、
`jurisdictions.hk.invoice_document.verify_hk_receipt_requirements`（商業收據的法定必載欄位與保存年限）。

### E.3 產品級風險（不是待查證，是需要決策或已決策）

| # | 風險 | 狀態 |
|---|---|---|
| **R1** | **跨租戶通用禮品卡 ⇒ 平台自己可能需要 SVF 牌照** | ✅ 已裁決為**產品級禁止**（§B.3.2 五層強制）。替代設計＝平台補貼的折扣碼 |
| **R2** | **在 HK 提供「依法申請解約」入口，本身可能構成 TDO 不實陳述** | ✅ 已落地 `statutory_channel_forbidden: true`。🔴 這是「多做會出事」的一條，與其他七項能力的風險方向相反 |
| **R3** | **G-01 的擋單處置若不加法域條件，會在 HK 卡死所有多次出貨的訂單** | ✅ 已落地 `block_multi_fulfillment_when_undecided: false` |
| **R4** | **G-06 的 `resolver_refuses_start_when_undecided` 若不加法域條件，會讓禮品卡在 HK 永遠無法啟用** | ✅ 已移入 `jurisdictions.tw.accounting` 並限定 TW |
| **R5** | **`shops.tax_id VARCHAR(8)` 是寫死的台灣假設** | 📌 登記為 P0-7（schema 級） |
| **R6** | **命名衝突「折讓」**：17 號＝折扣金額（法域無關，永遠存在）；38／16／55＝稅務折讓證明單（HK 下消失）。HK 上線後兩者只剩一個，翻舊文件的人會混淆 | 📌 登記為 P1（§D.1 #14），17 號改名為「折抵金額」 |
| **R7** | **命名衝突「發票」**：M38／M39 的平台帳單發票 vs 租戶的稅務發票（55 §C 讀表結論 2 已標為「命名衝突的高風險點」）。HK 下租戶側消失，但**平台帳單仍在**，且若平台向 TW 租戶收費可能觸發台灣的境外電商課稅義務 | 📌 併入 V-31 一併查證；平台帳單走**平台營運主體**的法域，不是租戶的 |
| **R8** | **HKD exponent 2 vs TWD exponent 0** 的顯示差異會讓「同一個 integer cents 值在兩個市場顯示不同位數」 | ✅ 架構已支援（`currency_format.exponent`）；⚠ 原型 `fmt()` 尚未 market-driven（P0-9） |

---

## F. 本篇驗收（對照 11 §0 七維度）

**架構正確性**
1. 九項能力在每個 `enabled: true` 的 pack 中**全部有宣告值**（CI-1）；缺一即 build fail。
2. `app/` 下 grep `統一發票|字軌|折讓|統編|超商取貨|電支條例` 六個字串，**命中數必須為 0**（`jurisdiction/tw/` 目錄除外）（CI-2）。
3. 預設法域為 `hk` 時，`app/services` 下**不存在**任何寫入 `einvoice/*` outbox 的呼叫路徑（CI-3）；三個內部 topic 也不註冊。
4. `limits.yml` 的 `jurisdictions.*` 之外**不存在** `tw_` / `hk_` 前綴的鍵（CI-4）。

**Fallback 正確性（§A.3 的核心）**
5. 建一個只宣告八項能力的假 pack ⇒ 結帳回 `JURISDICTION_CAPABILITY_UNDECLARED`，**不得成立訂單**。
6. HK 下發生任一「憑證動作消失」的事件（T06／T07／T08…）⇒ `jurisdiction_capability_skips` **恰增一列**，且 `reason` 可讀。**靜默 return 即測試失敗**。
7. 未宣告 `stored_value_regime` 的 pack ⇒ 九支儲值 mutation **全部**回 `userErrors`，一張卡都發不出來。
8. 未宣告 `consumer_rights` 的 pack ⇒ 前台退貨頁**不出現任何「依法」字樣**（字串掃描）。

**HK 行為正確性**
9. HK 訂單分三次出貨 ⇒ **三次全部正常完成**，不進人工佇列（R3 回歸測試）。
10. HK 商店建立禮品卡 ⇒ **成功**（R4 回歸測試：`resolver_refuses_start_when_undecided` 不得在 HK 生效）。
11. HK 訂單的 `tax_cents == 0` **且** `tax_basis == 'no_consumption_tax_regime'`；只有 0 而沒有 basis 即失敗。
12. HK 市場的退貨頁**不出現**「依消保法申請解約」入口；TW 市場出現（B2 回歸）。
13. HK 訂單單據上出現「本文件非稅務憑證」字樣。

**SVF 硬限制（§B.3.2 五層各一測）**
14. `redeemable_scope` 的列舉中**不存在** `platform_wide`（schema 快照測試）。
15. A 店的禮品卡在 B 店結帳扣抵 ⇒ 回 `CROSS_SHOP_REDEMPTION_FORBIDDEN`，**餘額不變**。
16. 直接對 DB 插入 `gift_card_transactions` 且 `shop_id` 與卡片不符 ⇒ **複合外鍵拒絕**（繞過應用層也擋得住）。
17. `Platform::` GraphQL schema 中**不存在**任何跨租戶發卡／扣抵的 mutation（schema 快照測試）。

**會計正確性**
18. 禮品卡售出 ⇒ 合約負債 +N、**收入 +0**；兌換 ⇒ 合約負債 −N、收入 +N；`Σ 合約負債變動 + Σ 已認列收入 == Σ 售出面額`（property test，integer cents）。
19. 首年無歷史兌換資料 ⇒ breakage **不認列**（`defer_all`），負債留著。
20. 退款回補至禮品卡 ⇒ **合約負債增加**，不是收入沖銷（方向錯即失敗）。

**防回退**
21. 55 §A.2 的 11 條金流累計上限測試**全部仍須通過**——法域改動**不得**削弱任何一條金流不變量（E.1 G-02 的「容易誤刪」風險）。
22. `jurisdiction` 維度在 29 §1.5 的繼承解析中**永遠不繼承**：父市場 HK、子市場 TW ⇒ 子市場解析出 `tw`，不是 `hk`。

---

## G. 本輪實際改動清單

| 檔案 | 行數變化 | 改了什麼 |
|---|---|---|
| `config/limits.yml` | 726 → **1,076**（+350） | 新增 §0 `jurisdiction` 契約（含 `_moved_keys` 17 條）與 §14b `jurisdictions` packs（`hk` 十區塊 ／ `tw` 十一區塊）；頂層 `einvoice`（40 鍵）**整段搬入** `jurisdictions.tw.tax_invoice`（值一字未改）；`pickup_point`／`cod`／`return`／`gift_card`／`store_credit`／`dispute` 六個區塊的法域鍵拆出並留 `*_ref` 指標；新增 `gift_card.redeemable_scope` ＋ `cross_shop_redemption_error_code` 兩條 SVF 硬限制鍵 |
| `docs/specs/56-jurisdiction-architecture.md` | **新增** | 本檔 |

> **未觸碰**（全部列入 §D 計畫，本輪只列不改）：`docs/specs/15`／`16`／`36`／`37`／`38`／`39`／`55`、`docs/research/06`／`22`／`28`／`29`／`42`／`43`／`44`、`docs/specs/49`／`50`／`53`／`54`、`docs/design/*.html`。
> **CLAUDE.md** 鐵律 10／11 已由使用者於本次決議時更新，本檔不再改。

---

## H. 香港來源清單（`hk-secondary`）

> 以下為本檔查得的**第二手**來源。法例與官方原文**未由本專案覆核**，凡引用一律標 `hk-secondary`，且不得升格為「已查證」。

| 用於 | 來源 |
|---|---|
| PSSVFO 單一用途豁免（Schedule 3）與多用途豁免（Schedule 8，含 HK$1,000,000 上限） | ONC（香港律師事務所）《Payment Systems and Stored Value Facilities Ordinance》：https://www.onc.hk/uploads/publications/11236/en/pdf/Payment_Systems_and_Stored_Value_Facilities_Ordinance.pdf |
| SVF 監管制度總覽（主管機關為 HKMA） | 香港金融管理局：https://www.hkma.gov.hk/eng/key-functions/international-financial-centre/stored-value-facilities-and-retail-payment-systems/regulatory-regime-for-stored-value-facilities/ |
| 香港無法定鑑賞期；適用 TDO 與 SGO | 立法會秘書處《E-consumer protection》ISE08/19-20：https://www.legco.gov.hk/research-publications/english/essentials-1920ise08-e-consumer-protection.htm |
| 消委會倡議特定行業強制 7 天冷靜期（尚未立法，追蹤項） | 消費者委員會：https://www.consumer.org.hk/en/advocacy/study-report/cooling-off |
| HK 取貨網路（EF Locker／順豐站／合作便利店 7-Eleven、Circle K、VanGO，逾 1,000 點） | Wave Commerce（Shopify app 供應商）說明頁：https://www.wavecommerce.hk/blog/hk-pickup-options-sf-express-shopify ／ 順豐 EF Locker：https://htm.sf-express.com/hk/en/dynamic_function/S.F.Network/EF-Locker/ ／ 7-Eleven HK 順豐取件：https://www.7-eleven.com.hk/en/pick-up-services/SFExpress |

---

## 附錄 Z — 2026-08-12 使用者裁定：SVF 降級（本文件 §B.3 的修正）

**裁定原文**：「支付系統及儲值支付工具條例不需要考慮。我們不做自己的支付系統，是整合 airwallex、stripe、paypal 等等電子支付工具。」

**處置**：`stored_value_regime` 從**法遵閘門**降級為**設計預設**。

| 項目 | 原（§B.3） | 改後 |
|---|---|---|
| `platform_wide_instrument_forbidden` | `true`（五層強制、啟動阻擋） | **`false`** |
| `verify_svf_exemption_scope` | 待查證項 | **移除**（不再以 SVF 豁免作為合規主張） |
| `redeemable_scope: issuing_shop_only` | 🔴 硬限制 | **設計預設**，仍為預設值 |
| 新增 `cross_tenant_requires_licensing_review` | — | `true`（要做跨租戶時先走一次評估） |

**必須留下的判斷依據**（避免日後被讀成「已豁免所以怎樣都行」）：

PSP 整合解決的是**支付處理**——刷卡授權、請款、結算由 Airwallex / Stripe / PayPal 這些持牌業者承擔，這部分確實與我們無關。但**禮品卡與商店抵用金是「預先收款、之後兌換」**，性質上與誰處理刷卡無關；funding 那筆錢是 Stripe 收的，不改變「之後這張卡還欠顧客一筆價值」這件事。

真正讓 PSSVFO 不構成風險的是**現行設計本身**：
1. 禮品卡由**租戶發行**、僅限**自家店**兌換 ⇒ 單一用途
2. 平台僅提供軟體，**非發行人**

⇒ 所以結論（不必處理）成立，但成立的原因是設計，不是 PSP 整合。**這兩條前提任一改變，結論就不再成立**——特別是若日後要做「跨租戶通用儲值／平台級會員錢包」，那不是改一個列舉值，而是要重新評估發行人身分與牌照。屆時的替代設計仍建議走**平台補貼的折扣碼**（折扣是價格減讓，不涉預先收款）。

**對 §D 遷移計畫的影響**：P0-5（`gift_cards.redeemable_scope` 與複合外鍵）**仍然要做**——理由從「法遵強制」改為「多租戶資料隔離」（CLAUDE.md 鐵律 2：全表帶 `shop_id`）。技術動作不變，只是理由換了。
