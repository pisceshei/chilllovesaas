# 10. 稅務（Tax Engine / Overrides / Duties）

> 本章依 Shopify 2026 官方文檔（help.shopify.com ＋ shopify.dev）考掘而成，全部規則性斷言附來源（§G），取證 2026-08-14。
> 與我方裁定的差異一律寫在 §F，本文其餘部分描述**本尊原貌**。
> 讀本章前提：`docs/specs/56`（jurisdiction pack C1/C2）、`docs/specs/55` §B（30 條稅務事件點）、`docs/specs/65`（金額單位邊界）。

---

## A. 領域物件模型

### A.1 物件總覽與 cardinality

```
Shop 1 ─── 1  TaxSettings（全域：taxesIncluded / taxShipping / 每市場顯示模式）
Shop 1 ─── N  TaxServiceSelection（每「大區」一個：US、EU、UK、CA、其餘國家）
Shop 1 ─── N  TaxRegistration（每國家或每州/省一筆；US 以州為單位，EU 以「registration 類型＋國」為單位）
Shop 1 ─── N  TaxOverride（product override → 綁 1 個 manual collection；shipping override → 綁 1 個 region）
Shop 0 ─── 1  TaxAppConfiguration（第三方 tax platform app；與內建稅務服務互斥）
Customer 1 ─ 1  taxExempt(Boolean) ＋ 0..N taxExemptions(TaxExemption enum)
CompanyLocation（B2B）1 ─ 1 稅務設定（taxExempt / exemptions / taxRegistrationId）
Order 1 ─── N  TaxLine（掛在 LineItem / ShippingLine / Duty / AdditionalFee 之下，非訂單層平面清單）
LineItem 1 ─ N  Duty（每個 duty 有自己的 taxLines）
Refund 1 ─── N  RefundDuty（refundType: FULL | PROPORTIONAL）
Product/Variant 1 ─ 1  taxable(Boolean)「Charge tax on this product」
Product 1 ─── 0..1 稅務類別（Standard Product Taxonomy category，Shopify Tax 專用）
InventoryItem 1 ─ 0..1 HS code ＋ countryCodeOfOrigin（duties 計算的必要輸入）⚠ API 掛載位置未逐欄取證
State(US) 1 ── 0..1 LiabilityInsight（status: action_required | monitoring）
```

### A.2 TaxLine（GraphQL `TaxLine`，取證 2026-08-14）

| 欄位 | 型別 | 語義（官方描述） |
|---|---|---|
| `title` | `String!` | 稅名（如 "State Tax"、"VAT"） |
| `rate` | `Float` | 稅率小數（0.20） |
| `ratePercentage` | `Float` | 稅率百分比（20.0） |
| `priceSet` | `MoneyBag!` | 稅額，雙幣記。官方原文語義：「after discounts and before returns」——**折扣後、退貨前** |
| `channelLiable` | `Boolean` | 該稅是否由送單 channel 代收代付（marketplace facilitator）；`null`＝責任不明 |
| `source` | `String` | 稅的來源 |
| `price` | `Money!` | deprecated，用 `priceSet` |

TaxLine 出現位置（窮舉，官方 connections 清單）：`AbandonedCheckout`、`AdditionalFee`、`CalculatedDraftOrder`、`CalculatedOrder`、`DraftOrder`、`DraftOrderLineItem`、`Duty`、`LineItem`、`Order`、`SaleAdditionalFee`、`SaleTax`、`ShippingLine`。

Order 層彙總欄位：`totalTaxSet: MoneyBag`、`taxesIncluded: Boolean!`、`currentTotalDutiesSet: MoneyBag`（反映訂單編輯與退款後的現值）、`originalTotalDutiesSet: MoneyBag`（原始值）。

### A.3 Duty（GraphQL `Duty`，取證 2026-08-14）

| 欄位 | 型別 | 語義 |
|---|---|---|
| `id` | `ID!` | GID |
| `countryCodeOfOrigin` | `CountryCode` | 計算該筆關稅所用的原產地國碼（ISO 3166-1 alpha-2） |
| `harmonizedSystemCode` | `String` | 計算所用 HS code |
| `price` | `MoneyBag!` | 關稅金額（雙幣） |
| `taxLines` | `[TaxLine!]!` | **課在關稅上的稅**（import tax 可以對 duty 再課稅，稅上稅結構原生存在） |

出現位置：`LineItem.duties`、`DutySale.duty`、`RefundDuty.originalDuty`。

### A.4 稅務服務（三內建＋一外掛）的值域

| 服務 | 提供地區 | 定位 |
|---|---|---|
| **Shopify Tax** | US、EU、UK、CA | 付費自動稅務：registration-based、產品類別稅率、rooftop accuracy（精確到門牌而非 ZIP）、州費（state fees）、tax holidays、liability insights、B2B/顧客豁免、進階報表、自動申報（US 部分州）、EU/UK VAT invoice 生成 |
| **Basic Tax** | 店址在 Norway、Switzerland、Australia、New Zealand、Singapore；EU/UK/CA 既有店可續用 | 免費 registration-based：**2026-05-13 起新店在 EU/UK/CA 不再可選** |
| **Manual Tax** | 全球 | 商家自填稅率；無自動計算、無 tax holiday、無顧客豁免、shipping 稅不自動 |
| **Tax app**（tax platform） | 依 app | 第三方引擎整包接管計算；與內建稅務服務**互斥**（同店只能擇一） |

⚠ 主 taxes 頁與 choose-tax-service 頁對 Basic Tax 地區表述不一致（前者列 NO/CH/AU/NZ/SG，後者含 EU/UK/CA＋其餘國家）；差異可由「2026-05-13 新店限制」解釋，但邊界（既有店遷移規則）未逐字取證。

### A.5 TaxExemption enum（顧客／公司據點豁免值域，窮舉，取證 2026-08-14）

**加拿大（22 值）**：
`CA_STATUS_CARD_EXEMPTION`、`CA_DIPLOMAT_EXEMPTION`、
BC：`CA_BC_RESELLER_EXEMPTION`、`CA_BC_COMMERCIAL_FISHERY_EXEMPTION`、`CA_BC_CONTRACTOR_EXEMPTION`、`CA_BC_SUB_CONTRACTOR_EXEMPTION`、`CA_BC_PRODUCTION_AND_MACHINERY_EXEMPTION`；
MB：`CA_MB_RESELLER_EXEMPTION`、`CA_MB_FARMER_EXEMPTION`、`CA_MB_COMMERCIAL_FISHERY_EXEMPTION`；
NL：`CA_NL_VPT_RESELLER_EXEMPTION`；NS：`CA_NS_FARMER_EXEMPTION`、`CA_NS_COMMERCIAL_FISHERY_EXEMPTION`；
ON：`CA_ON_PURCHASE_EXEMPTION`；PE：`CA_PE_COMMERCIAL_FISHERY_EXEMPTION`；
SK：`CA_SK_RESELLER_EXEMPTION`、`CA_SK_FARMER_EXEMPTION`、`CA_SK_COMMERCIAL_FISHERY_EXEMPTION`、`CA_SK_CONTRACTOR_EXEMPTION`、`CA_SK_SUB_CONTRACTOR_EXEMPTION`、`CA_SK_PRODUCTION_AND_MACHINERY_EXEMPTION`、`CA_SK_VPT_RESELLER_EXEMPTION`。

**歐盟（1 值）**：`EU_REVERSE_CHARGE_EXEMPTION_RULE`（intra-EU B2B 反向課稅豁免，亦涵蓋 EU→UK）。

**美國（51 值）**：`US_{STATE}_RESELLER_EXEMPTION`，STATE ∈ 50 州＋DC（AK, AL, AR, AZ, CA, CO, CT, DC, DE, FL, GA, HI, IA, ID, IL, IN, KS, KY, LA, MA, MD, ME, MI, MN, MO, MS, MT, NC, ND, NE, NH, NJ, NM, NV, NY, OH, OK, OR, PA, RI, SC, SD, TN, TX, UT, VA, VT, WA, WI, WV, WY）。

合計 74 值。⚠ 抓取工具回報頁面標示總數可能更高（112），逐值清單以上表為準，差額待原頁複核。

顧客層豁免的 admin UI 是三選一 radio：**「Don't collect tax」／「Collect tax unless exemptions apply」（勾選上表豁免類別）／「Collect tax」**。
變更 API：`customerAddTaxExemptions` / （成對的 remove/replace 系列）；B2B 據點：`companyLocationTaxSettingsUpdate(companyLocationId!, taxExempt, exemptionsToAssign, exemptionsToRemove, taxRegistrationId)`，錯誤走 `BusinessCustomerUserError`。

### A.6 稅務設定的 shop 層欄位

- `Shop.taxesIncluded`＝admin「Include sales tax in product price and shipping rate」。
- `Shop.taxShipping`＝admin「Charge tax on shipping rates」（全域設定區）。
- 每市場稅務顯示（Markets → 該市場 → duties and taxes，值域窮舉）：**「Dynamic tax display」／「Show as included」／「Show as line item」**。
- 每市場關稅（值域窮舉）：**「Show as line item」／「Duties included in price」**（後者＝商家吸收，不加價）。
- 每市場設定**覆蓋全域設定**；前置條件＝該市場涵蓋地區已有稅務 registration。子市場預設繼承父市場，多父衝突時取地區合適值。

---

## B. 狀態機

### B.1 Tax app 配置（`TaxAppConfiguration.state`，enum `TaxPartnerState`，取證 2026-08-14）

狀態全集（3）：`PENDING`（"App is not configured."）／`READY`（"App is configured, but not used for tax calculations."）／`ACTIVE`（"App is configured and to be used for tax calculations."）

| 現態 | 觸發 | 前置條件 | 次態 | 副作用 |
|---|---|---|---|---|
| （無） | 商家安裝 tax app | app 具 tax calculations 身分 | PENDING | — |
| PENDING | app 呼叫 `taxAppConfigure(ready: true)` | caller 必須是 tax calculations app＋`write_taxes` scope | READY | admin 顯示可啟用 |
| READY | 商家在 admin 啟用該 app 為稅務服務 | 內建稅務服務讓位（兩者互斥） | ACTIVE | 之後 checkout/draft order 計算送 app |
| ACTIVE | 商家停用／切回內建服務 | — | READY | 計算回到內建 |
| READY/ACTIVE | app 回報未配置 `taxAppConfigure(ready: false)` | 同上 | PENDING | — |
| 任一 | 解除安裝 | — | （終態：移除） | 回內建服務 |

**Runtime 降級（非狀態轉移）**：app 暫時無回應時「admin 內的稅務設定作為備援計算」——商家必須維持內建設定為安全網。**不存在「app 掛了就不收稅」的孤兒態**。

### B.2 每地區收稅狀態（registration/collection）

狀態全集（3）：`not_collecting` → `collecting` → `removed`（可再回 `collecting`）。

| 現態 | 觸發 | 前置條件 | 次態 | 副作用 |
|---|---|---|---|---|
| not_collecting | 「Collect sales tax」＋選州/國＋填稅籍號 | **已向該稅務機關完成登記**（官方前置；稅號欄位 US 可暫留空、事後補填） | collecting | 該地區稅率自動生效（registration-based：「加了 registration，Shopify 自動套用你所登記地區適用的稅率」） |
| collecting | 編輯（換稅號／sourcing） | — | collecting | 不回溯已成立訂單（見 §C.9） |
| collecting | 移除該地區 | — | removed | 該地區不再計稅；歷史訂單快照不變 |
| removed | 重新加入 | 同第一列 | collecting | — |

**Registration-based 的核心語義**：**沒有 registration 的地區＝一律不計稅**（EU 原文：「Shopify 只在適用 registration 涵蓋的國家收 VAT」）。這不是錯誤態，是本尊的預設行為——與我方 C2 fallback 的差異見 §F。

### B.3 美國 liability insight（每州）

狀態全集（3 顯示態＋1 隱含態）：`（無標記）`／`monitoring`／`action_required`／`collecting`（開始收稅後離開 insight 清單）。

| 現態 | 觸發 | 判定 | 次態 |
|---|---|---|---|
| 無標記 | 銷售累積 ≥ 該州門檻 80% | 州法定分析期內 net sales（=sales − refunds − shipping − tax）＋依州法計入的 marketplace 銷售 | monitoring |
| monitoring | 超過門檻 或 檢出 physical nexus（admin 有該州 location） | 同上 | action_required |
| action_required | 商家點「Set up tax collection」→ 填州稅籍號 | 已向州政府登記 | collecting（轉入 B.2） |
| 任一 | 銷售回落／年度重算 | 州分析期滾動 | 可回退 |

州法定分析期值域（窮舉，4 種）：①**前一年或當年曆年**（先看去年，未達再看今年）②**滾動 12 個月**（每月 1 日移出最舊月、加入最新月）③**僅前一曆年**（一年只算一次）④**前四個稅務季度**（每季首日滾動）。
資料延遲：「銷售不會即時反映，可能需數天更新」。⚠ 官方明示 insight 不含 Shopify 之外的通路銷售（Amazon/Etsy 等自行加總）。

### B.4 Duties at checkout（設定流程狀態）

狀態全集（3）：`inactive` → `active` →（可回）`inactive`。
inactive→active 的前置（全部必要）：①承運商支援 DDP label（Canada Post 限美國、DHL Express、DHL Express Canada、DHL eCommerce）②不可使用 Shopify Fulfillment Network ③產品有 HS code＋原產地（Switzerland 另要求重量）④接受條款。
active 的運行時規則：**「產品缺 HS code、描述或類別 ⇒ 該產品不計算 duties」**（靜默不算，不是擋單）⑤同國出貨、EU 境內互寄、abandoned checkout 不收費。
**啟用 duties 的地區 ⇒ 該地區 tax override 失效**（官方明載的互斥）。

---

## C. 業務規則與不變量

### C.1 稅率解析優先序（單一行項的稅率從哪來）

```
1. product.taxable == false            → 不課稅（該行無 tax line）
2. customer/companyLocation 豁免        → 依豁免規則歸零或部分豁免
   🔴 官方原文：「Customer tax exemptions always take precedence over tax overrides.」
3. TaxOverride（collection 命中 ∧ region 命中 ∧ 該 region 正在收稅 ∧ 該 region 未啟用 duties）
   → 覆蓋率直接取代自動稅率（「你輸入的百分比＝要收的稅率，不是豁免的稅率」）
4. 產品稅務類別（Shopify Tax）           → 類別稅率（如食品減稅率）
5. 標準稅率（registration-based 自動 或 manual 手填）
0. 前提閘門：該 destination（或 origin）沒有 registration → 整張不計稅
```

### C.2 計算公式（含稅／不含稅／動態）

**稅基**：行項折扣後金額（TaxLine 語義「after discounts and before returns」；訂單層折扣先攤到行再計稅）。

**不含稅定價（預設）**：`tax = taxable_base × rate`，逐行算、逐行捨入（見 C.3），總稅額＝Σ行稅。
例：$100、15% → 結帳加 $15，總 $115。

**含稅定價（taxesIncluded = true）**：
`Tax = (Tax Rate × Price) / (1 + Tax Rate)`（官方公式原文）
例（官方）：$100 含 10% → 稅 `(0.1×100)/1.1 = $9.09`，品項淨額 $90.91。顯示上「小計與總計相同，但稅額另列一行」。

**動態含稅（dynamic tax-inclusive pricing，per-market）**：以**店址所在地的 home tax rate** 從定價中反推淨額，再按目的市場決定加不加當地稅：
```
base = listed_price / (1 + home_rate)              # $100、home 10% → base $90.91
含稅市場（UK 20%）：顯示 base × (1 + 0.20) = $109.09（含 VAT）
不含稅市場（US）：顯示 $90.91，當地稅結帳時另加
```
限制（官方窮舉）：不改運費；與第三方 post-purchase upsell app 不相容；**tax override 被忽略、一律用標準稅率**；fixed price（固定國際價）不調整；顯示端在非當地幣別＋非 Shopify Payments 情境可能不準。
顯示設定只影響顯示：「稅怎麼計算與收取**不受**這些設定影響」。

**🔴 含稅定價 × 豁免顧客的官方陷阱**：「若顧客免稅但你使用含稅定價，顧客仍按完整標價付款」——豁免不會把含稅價降回淨額。

### C.3 Rounding（取證 2026-08-14）

- **Registration-based 地區：banker's rounding（四捨六入五成雙），在 line-item 層**。官方原文：「tax amounts are rounded using banker's rounding rules at the line-item level」；halfway 值取偶（$2.5→$2、$3.5→$4）。
- 官方數例：42 件 × $14.99、18% 稅。單件稅 $2.6982 → 捨入 $2.70；42 × $2.70 = **$113.40**。舊 invoice 層算法：42×14.99=629.58×0.18=113.3244 → **$113.32**。兩法相差 $0.08，**line 層捨入是官方現行**。
  🔴 **捨入粒度已定（2026-08-14 補證，原 openQuestion 關閉）＝「單價×率 → banker's rounding → ×量」**。官方對同一數例的分步敘述（轉述）：先把**單件**稅 $2.6982 捨入成 $2.70，再乘以 42 件得到行稅 $113.40。「行小計×率再捨入」（629.58×0.18=113.3244→$113.32）被此分步**排除**。官方措辭「at the line-item level」指「捨入發生在行內、而非 invoice/訂單層」；行內實際粒度＝單件。公式（我方表示法，rate 尺度由 limits 鍵後綴宣告，見 F.2#10）：`line_tax_cents = bankers_round(taxable_unit_cents × tax_rate / SCALE) × quantity`（`*_bp`＝10_000、`*_ppm`＝1_000_000，**禁止混讀**——CA 表因 QST 9.975% 非整數 bp 已升 ppm 2026-08-17 更正（PR #52 第 7 輪））；`taxable_unit_cents`＝行項**分攤折扣後**金額的單件基數（本章 C.2 稅基「行項折扣後」÷ quantity；分攤不整除 ⇒ 依 D-12① 最大餘數法定各件次基數）。官方數例的 $2.6982 即已是折扣後單價情境。 <!-- 2026-08-17 更正（PR #52 第 4 輪）：與總綱 M-11 同步——原式 unit_price_cents 未扣分攤折扣，與本章 C.2 稅基自述矛盾，照抄對折扣品多收稅 -->
  ⚠️ 殘餘未明文：行分攤訂單層折扣後「折後單價」除不盡（如 3 件均攤 $1.00 折扣 → 單件稅基非整數 cents）時，單件稅基如何取值官方未載——官方未明文，待實測（fixture 要求見 F.3#2）。
- 總稅額＝各行（含 shipping line、duty tax line）捨入後求和；**不存在訂單層再捨入**。

### C.4 Shipping 稅

- 自動計 shipping 稅的地區（窮舉，`Charge tax on shipping rates` 設定對其無效）：**Australia、Canada、EU、New Zealand、Norway、Switzerland、UK、US**。其餘地區由 `taxShipping` 開關控制。
- **Proportional shipping tax**（訂單含不可稅品項時，Shopify Tax 才有）：
  - **按數量**：10 件中 4 件不可稅 → shipping 稅收正常額的 60%。
  - **按價格**：$5 可稅＋$10 不可稅 → shipping 稅收 33%。
  - **全免**：全單免稅品 → shipping 不課稅（部分法域）。
  - EU/UK 混合稅率單：shipping 稅率＝**按品項價格加權平均**，會出現非標準稅率。
- Canada：GST/HST 按比例；US 各州 shipping 是否課稅在州設定裡可配置。
- shipping override：per-region 指定 shipping 稅率，取代上述自動值（US 為**州層級、不含地方稅**——官方明示可能因此少收 local tax）。

### C.5 Overrides 的驗證規則與上限（窮舉官方限制）

1. product override 必須綁**手動（manual）collection**；smart/automated collection 不可。
2. override 的地區粒度＝國家／州省；**不可**針對 city、district、sub-state 區域。
3. override 只在**你正在收稅的地區**生效。
4. bundle 商品要對**組成品**設 override，對 bundle 本體設無效。
5. 該地區啟用 duties 收取 ⇒ override 停用。
6. 顧客豁免 > override（見 C.1）。
7. 動態含稅定價下 override 被忽略（見 C.2）。
8. 內建服飾豁免：collection 命名**恰為小寫 `tax:clothing`** 時自動套用州門檻豁免，適用州（窮舉）：NY（單件 <$110 免）、NJ（多數服飾鞋類全免）、MA（<$175 免、超過部分只課超額）、RI（<$250 免）、PA、VT、MN。
⚠ override 數量上限：官方未載明（openQuestion；limits.yml 先留鍵）。

### C.6 Registration 門檻值域（法域 pack 的資料來源）

**US 經濟 nexus**（Shopify 官方 reference 表，取證 2026-08-14）：
- 預設 $100,000/年；AL、MS＝$250,000；CA、NY、TX＝$500,000；多州為「$100,000 **或** 200 單」；NY 特例「$500,000 **且** 100 單」（用季度制）。
- Origin-based 州（窮舉 9）：IL、MS、MO、OH、PA、TN、TX、UT、VA。其餘 28 州 destination-based；**CA、IA 混合制**（CA 州稅 origin、district 稅 destination）。
- 無州銷售稅州（窮舉 5）：AK、DE、MT、NH、OR（可能有地方稅；Shopify Tax 不支援在 no-tax 州收稅、Manual 支援）。
- 州級附加費（state fees，Shopify Tax 才會收）：CO retail delivery fee $0.29/單（逐年通膨調整）、MN $0.50/單（2024-07-01 起、$100 門檻）。
- 3PL 倉庫可構成 physical nexus（官方明示風險）。
- Notice & report 州：不登記則有通知義務（結帳通知＋年度報告）。

**EU**：micro-business 豁免＝對其他 EU 國年銷 **< €10,000** 可用本國稅率；≥ €10,000 必須 destination VAT。OSS 三型（窮舉）：**Union OSS**（EU 店跨國）、**Non-Union OSS**（非 EU 店賣數位商品）、**IOSS**（非 EU 店 ≤ €150 訂單進口代收）。⚠ 官方註記 2026-07-01 起 €150 customs exemption 取消（IOSS 制度變動，需追蹤）。
**UK**：**≤ £135 訂單 POS 代收 VAT、商家申報**；> £135 進口人繳（可選 DDP）。UK VAT 登記門檻 **£90,000/12 個月**（不是舊值 £85,000）。Northern Ireland 雙軌：UK→NI 用 UK VAT，EU→NI 用 EU VAT（用 OSS 不用 IOSS）。
**Canada**：小供應商門檻 **$30,000 CAD/四個連續季度**；GST 5%（AB/BC/MB/NT/NU/QC/SK/YT）、HST 13%（ON）/14%（NS）/15%(NB/NL/PE)；省稅另收：BC PST 7%、MB RST 7%、QC QST 9.975%、SK PST 6%——**BC/MB/QC/SK 需各自獨立登記**，且「發票必須列兩條稅行：GST 一條＋省稅一條」。

**Manual Tax 的省稅合成模式**（值域窮舉，3 種）：**added to**（國稅＋省稅相加：10%+10% → $120）／**instead of**（省稅取代國稅：→ $110）／**compounded on top of**（省稅課在含國稅小計上：$10 國稅＋$110×10%=$11 → $121）。

### C.7 Duties & import taxes

- **De minimis**（低於即免關稅/進口稅，官方例值）：Canada $20 CAD、Mexico $50 USD(duty)/$117 USD(tax)、Australia $1,000 AUD（僅 duty）、EU €150、Japan ¥10,000。🔴 **2025-08-29 起美國進口不再適用 de minimis**（全部訂單都可能有關稅）。
- **CIF vs FOB**：多數國家門檻計算含運費/保險（CIF）；**CA、US、AU、NZ、ZA 不含**（FOB）。
- **DDP**＝賣方承擔全部進口成本（結帳可見全額、不卡關）；**DAP**＝買家貨到自付（有驚喜費用與棄件風險）。
- 計算輸入＝HS code＋原產地＋目的國稅則（含 USMCA 等優惠協定，預設帶入）；**缺 HS code/描述/類別 ⇒ 不計算**。
- 費用：每張「有計算 duties」的訂單收交易費，**算出 0 元也收**；費率 0.85%（Shopify Payments）／1.5%（其他金流）⚠ 另有 0.5% 限時價（文檔標注期限已過，現值需複核）。broker/disbursement 費不在結帳額內（官方建議灌進運費）。
- 退款：`refundCreate(refundDuties: [{dutyId, refundType}])`，`refundType ∈ {FULL, PROPORTIONAL}`（PROPORTIONAL 按退貨數量比例）；已交海關的稅金退還要買家自行找海關。
- Managed Markets（merchant of record 模式）另有 duty **保證**：結帳顯示額與海關實收差額由平台吸收；duties-inclusive pricing 把關稅、跨境費、匯損全部滾進商品價。

### C.8 數位商品 VAT

- EU 規則：**數位商品對 EU 消費者一律按買家所在國 VAT 課稅，無任何門檻**（micro-business 豁免不適用）。
- Shopify 機制：啟用「digital goods VAT tax」→ 自動建一個名為 **Digital Goods VAT Tax** 的 collection，掛進去的產品按**帳單地址**套各 EU 國 VAT 率（可換綁其他 collection）。
- 合規證據：稅務機關可要求**每單兩件位置證據**——Shopify 提供帳單地址＋買家 IP（Fraud Analysis 內）。
- 排除：線上發送的禮品卡明文排除在數位商品外。實體活動票券建議按實體品＋到場自取處理。

### C.9 快照與不回溯（與我方 T30 同源）

商家更改稅務設定**不回溯**已成立訂單；報表與退款一律用訂單當下快照稅率。退款稅額（RefundLineItem 的稅）按原 tax line 比例回沖，**不重算現行稅率**。

### C.10 併發要害與不變量（本尊行為＋我方必測）

1. `Σ(line tax after rounding) == order.totalTax`——恆成立；不得存在訂單層「校正尾差」暗數。
2. 豁免優先序（C.1）是**全序**，同一行不得同時套 override 與豁免各算一次。
3. duties 與 tax override 互斥（B.4）——啟用/停用 duties 的瞬間，未完成 checkout 的稅務快照必須固定在進入 checkout 時的規則集。
4. liability insight 的分析期滾動（月初/季初）與銷售寫入是競態——本尊允許「數天延遲」，同源性只要求 insight 頁與報表用同一 rollup。
5. 稅務服務切換（manual ⇄ Shopify Tax ⇄ app）不得影響已成立訂單的 tax lines（快照）。

---

## D. 關鍵流程

### D.1 開始在某州收稅（US，操作者：商家）

1. 商家在 liability insights 看到 `action_required`（或自行判斷 nexus）。
2. **先向州稅務機關登記**（Shopify 外部動作；官方明示必須先登記才可設收稅）。
3. Settings → Taxes and duties → United States → Collect sales tax → 選州 → 填 sales tax ID（可留空後補）。
4. 系統：該州進入 `collecting`，自動套 registration-based 稅率（Shopify Tax 含 rooftop accuracy／類別稅率／州費／tax holidays）。
5. 失敗分支：未登記就開收＝合規風險（系統不擋，文檔警告）；填錯稅號不影響計算（僅申報用）⚠ 未見格式驗證的官方描述。

### D.2 Checkout 稅計算（操作者：買家；系統：稅引擎）

1. 解析目的地（destination 州用收貨地址；origin 州用賣方地點；CA 混合）。
   **無收貨地址時的 fallback（2026-08-14 補證）**：官方明文轉述：檔案中沒有收貨地址時，改以顧客的帳單地址計稅（draft orders 頁）——即 **shipping address → billing address** 兩級鏈。數位商品訂單（checkout 無 shipping step）即走此支，與 C.8「數位商品 VAT 按帳單地址課稅」官方敘述互證同源。POS 通路另軌：官方明文按 POS 裝置所指派的商店 location 計稅（轉述）。
   ⚠️ billing address 也缺席（訂單完全無買家地址）時的第三級 fallback（shop address？0 稅？）官方未明文，待實測——community 有「admin 預設店所在國、API 直接算不出稅」的說法，但非官方文檔，不得引為規則。
2. 閘門：目的地（或 origin 州）有無 registration？無 → 全單 0 稅（不產生 tax lines）。
3. 逐行：`taxable?` → 豁免? → override? → 類別稅率? → 標準稅率（C.1）。
4. 逐行計稅＋banker's rounding（C.3）；shipping line 按 C.4；duties 啟用時算 duty＋duty 的 taxLines。
5. 顯示：按市場設定（included / line item / dynamic）。
6. 買家改地址 → 全量重算（回到 1）。
7. 失敗分支：tax app 無回應 → 降級用 admin 內建設定備援計算（B.1）。

### D.3 DDP 結帳收 duties（系統）

1. 前置檢查（B.4 四條）通過、該市場選「Show as line item」或「Duties included in price」。
2. 逐行以 HS code＋原產地＋目的國稅則計算 duty；缺資料的行靜默跳過。
3. de minimis 判定（目的國、CIF/FOB 口徑）；低於門檻＝0（**仍計入「有計算」→ 仍收平台交易費**）。
4. duties 行＋duty 上的 import tax lines 進訂單；出貨必須購買 DDP label。
5. 退款：suggestedRefund 帶 `refundDuties`（FULL/PROPORTIONAL）→ refundCreate。
6. 失敗分支：估算與海關實收不符 → 非 Managed Markets 由買家補繳（官方明示為估計值）；Managed Markets 平台保證差額。

### D.4 EU VAT invoice 自動生成（Shopify Tax）

1. Settings → Taxes and duties → EU/UK → VAT Invoices → 「Generate and display invoices when orders are placed」。
2. 下單即生成 PDF，掛在 order status page 供買家查看/下載。
3. 客製僅限加 logo；**不支援**加行、註記、公司章。
4. 限制：**不支援寄送到 Portugal 的訂單**。
5. ⚠ 修改/重開發票的生命週期（金額變動後 invoice 是否重出）未在取證頁載明。

### D.5 稅務事件（我方管線，對照用）

本尊沒有「稅務憑證事件」概念（無 GUI/e-invoice 管線）；我方核心只發 5 種 `TaxEvent.kind`（56 §A C1）：`sale_recognised / sale_reversed / sale_reduced / sale_increased / sale_uncollected`，由 jurisdiction pack 決定落不落憑證。本尊的對應物僅是：訂單成立寫 tax lines → 退款回沖 → 報表聚合。

---

## E. 跨模組耦合

| 方向 | 模組 | 耦合點 |
|---|---|---|
| 依賴 → | **Markets（29）** | 每市場稅顯示 3 值域／duties 2 值域；動態含稅靠市場歸屬；含稅市場清單（EU/UK/AU/JP 等）與 29 §3 的幣別顯示同機箱。市場設定覆蓋全域稅設定 |
| 依賴 → | **Products** | `taxable` 開關、稅務類別（Standard Product Taxonomy）、HS code＋原產地（InventoryItem）；`tax:clothing` 命名魔法 collection |
| 依賴 → | **Customers / B2B** | customer.taxExempt＋taxExemptions；companyLocation 稅設定（taxRegistrationId＝B2B 稅號，掛 C5 `tax_id_format` 驗證） |
| 被依賴 ← | **Checkout / Orders** | tax lines 逐行掛載；Order.taxesIncluded/totalTaxSet/currentTotalDutiesSet；draft order 同構 |
| 被依賴 ← | **Refunds（16-F5）** | 退款按原 tax line 比例回沖；refundDuties FULL/PROPORTIONAL；我方 X1–X6 分攤與 55 §B.3 折讓基數 |
| 被依賴 ← | **Reports / Analytics** | US sales tax report（州/郡/jurisdiction 三層＋jurisdiction 明細＋transaction 明細）、Canada report（省層 GST/HST/PST/QST）、Taxes report、Total sales by order CSV、Managed Markets taxes report（限 CA/UK）；net sales 口徑＝sales − refunds − shipping − tax |
| 事件 | **我方 outbox** | 核心發 `TaxEvent`（5 kind）；`jurisdiction_capability_skips` 落 `no_document`；**本尊無 tax 專屬 webhook topic**（orders/create 等 payload 內含 tax_lines）⚠ 需再確認無 tax webhook 的斷言 |
| 外掛 | **Tax platform app** | `taxAppConfigure`、`TaxPartnerState`；app 接管計算但保留：含稅定價、per-country 含稅、product taxable、customer 豁免、duties 收取（duties 啟用時跨境稅一律由 duties 機制收） |
| 收費 | **Billing** | Shopify Tax 免費額度（年度/終身 $100k USD／€100k／£100k／$100k CAD）→ 超過後每單 0.35%/0.25%（US）、0.25%/0.15%（EU/UK/CA，Plus 低檔），**單筆上限 $0.99**、（舊店）每區年上限 $5,000；只對「已開收稅地區」的訂單收費 |

---

## F. 落地對應

### F.1 對應倉庫既有文檔

| 本章節 | 倉庫對應 |
|---|---|
| C.1–C.3 計算管線 | `docs/specs/15`-F2 金額引擎；`docs/specs/65`（單位邊界） |
| D.5 稅務事件 | `docs/specs/56` §A C1/C2（能力介面）、`docs/specs/55` §B（30 事件點 T01–T30） |
| C.9 快照不回溯 | 55 §B.1 **T30** 同一條 |
| C.7 duties | 55 §B.1 **T25**（M4 刻意不做，schema 預留 `refund_duties`）；29 §5（duties 為 P2） |
| C.4 shipping 稅 | 15 Shipping／29 §5 zone-market guard |
| A.5 豁免 | 56 §A C5（tax_id_format）、B2B（29 §10） |
| E 報表 | 鐵律 7 數字同源；`docs/research/80` §3 |

### F.2 本尊 vs 我方裁定（逐條）

| # | 本尊 | 我方裁定 | 出處 |
|---|---|---|---|
| 1 | 金額/稅額 API 為 decimal `MoneyBag`，內部捨入到貨幣 exponent | **全程 integer cents ×100**，序列化層才轉 MoneyV2/MoneyBag；zero-decimal 幣別（JPY/TWD/KRW）必進稅額測試矩陣 | 鐵律 3、65 §H |
| 2 | 無政府稅務憑證概念（無統一發票/e-invoice 管線；EU VAT invoice 只是商業 PDF） | 稅務憑證＝jurisdiction pack 能力 C1（HK `none`＋commercial_receipt、TW `gui`、MY `lhdn_einvoice`）；核心只發 5 種 TaxEvent | 鐵律 11、56 §A |
| 3 | 未 registration 的地區＝**靜默不計稅**（合法預設） | C2 未宣告＝**reject**（結帳擋下）；宣告 `none` 才是 0 稅且必帶 `tax_basis: no_consumption_tax_regime`。**不得把本尊的靜默 0 照搬**——本尊面向商家自負合規，我方 pack 未宣告＝沒人想過該市場 | 56 §A.2 C2 |
| 4 | 正向計稅捨入＝**banker's rounding、單價粒度（unit→round→×qty，C.3 2026-08-14 已補證定案）** | 我方 55 §B.3 只定了**折讓拆分**（floor 未稅＋差額法）；正向計稅採本尊規則，寫成 `limits.tax.rounding: bankers_unit_then_quantity` 可配置鍵（粒度已定，鍵保留作未來法域差異開關，不得改回 `bankers_line_level` 這種粒度含混的命名），且與折讓拆分的 floor 不是同一件事，不得混用 | 55 §B.3；本章 C.3 |
| 5 | Shopify Tax 按 GMV 門檻＋每單費率向商家收費 | 平台計費模型未裁定——不復刻收費，先做功能面 ⚠ 需使用者決策 | — |
| 6 | Duties at checkout（DDP）＋Managed Markets 保證 | **M4 不做**（T25）；schema 預留 refund_duties；de minimis／HS code 表留 pack 介面 | 55 T25 |
| 7 | US liability insights（80% monitoring／action required／四種分析期） | 作為 `jurisdiction/us` pack 能力（economic nexus 是美國特有概念），核心只提供 rollup 查詢介面；HK 基準法域無此物 | 鐵律 11 |
| 8 | 顧客豁免 74+ 值 enum（US/CA/EU 硬編碼於平台） | 豁免值域應由 jurisdiction pack 宣告（HK pack：無銷售稅 ⇒ 豁免清單空）；enum 命名沿用本尊格式利於 1:1 | 56 §A |
| 9 | 含稅顯示雙模式＋動態含稅（home rate 反推） | 對齊實作；但 HK 無銷售稅 ⇒ 基準法域下 `taxesIncluded` 無感；顯示位數走 58 §G.3（顯示≠儲存≠對外） | 鐵律 3/10 |
| 10 | 稅率 float（rate 0.20） | 稅率內部用**整數**，尺度由鍵後綴宣告（`*_bp` /10_000 或 `*_ppm` /1_000_000——QST 9.975% 在 bp 尺度非整數，該類率一律 ppm 2026-08-17 更正（PR #52 第 7 輪））；序列化層才轉 Float | 55 §B.3（該檔更新屬 ⚪ 範圍外） |
| 11 | 本尊 tax app 降級＝fallback 到 admin 設定 | 我方無第三方 tax app（M 階段）；若做，降級行為要落 `jurisdiction_capability_skips` 等可觀測表，不得靜默 | 56 §A.3 |
| 12 | `tax:clothing` 魔法 collection 命名觸發州豁免 | 魔法命名是隱式行為，與我方「靜默規則禁止」原則衝突——若復刻必須在 admin UI 顯式標示該 collection 已啟用豁免 ⚠ 待裁定 | 56 §A.3 精神 |

### F.3 開發驗收要點（新增於本章）

1. **計稅測試矩陣**：`{不含稅, 含稅, 動態含稅} × {豁免, override, 類別稅率, 標準} × {HKD, JPY, TWD}`——JPY/TWD 行的 banker's rounding 在 exponent=0 下必須整數（65 §H 同源）。
2. 官方 rounding 例（42×$14.99@18%）入 fixture 必須斷言**三個值**：單件稅捨入後＝270 cents、行稅＝11340 cents、且明確斷言行小計法結果 11332 **≠** 行稅（防粒度回歸）；再加 halfway 案例驗 round-half-to-even（$2.5→$2、$3.5→$4）；再加「折後單價除不盡」案例——⚠️ 期望值官方未明文，先實測本尊取值後鎖入 fixture，不得腦補。
3. `Σ 行稅 == totalTax` 恆等式做 property test（含 shipping line 與 duty tax line）。
4. 豁免 > override 的優先序測試（同一行同時命中兩者）。
5. duties ⇄ override 互斥的狀態切換測試（B.4 第 3 條併發要害）。
6. registration 移除後歷史訂單 tax lines 不變（T30 快照）。
7. `tax_basis` 欄位：HK（無稅制）訂單 tax_cents=0 且 tax_basis=no_consumption_tax_regime，與「稅算漏了」可區分（56 §A.2）。
8. 含稅定價＋豁免顧客＝仍收全價（C.2 陷阱）要有明確測試與 UI 提示，不得讓商家以為會退稅。
9. 數位商品訂單（無 shipping address）計稅測試：destination＝billing address（D.2 fallback 鏈，官方明文）；「billing 也缺」案例先標 pending，待實測本尊行為定案，不得先寫死 shop-address fallback。

---

## G. 來源（全部取證 2026-08-14）

| 主題 | URL |
|---|---|
| Taxes 總覽/責任聲明 | https://help.shopify.com/en/manual/taxes |
| 稅務服務比較（全功能表） | https://help.shopify.com/en/manual/taxes/shopify-tax/choose-tax-service |
| Shopify Tax | https://help.shopify.com/en/manual/taxes/shopify-tax |
| Shopify Tax 計費 | https://help.shopify.com/en/manual/taxes/shopify-tax/pricing |
| Basic Tax（registration-based） | https://help.shopify.com/en/manual/taxes/registration |
| Registration-based 管理＋banker's rounding | https://help.shopify.com/en/manual/taxes/registration/manage |
| Manual tax settings（added to/instead of/compounded） | https://help.shopify.com/en/manual/taxes/manual-tax-settings |
| 含稅定價（公式） | https://help.shopify.com/en/manual/taxes/include-exclude-taxes |
| 動態含稅定價 | https://help.shopify.com/en/manual/international/pricing/dynamic-tax-inclusive-pricing |
| 稅收取對顯示價的影響 | https://help.shopify.com/en/manual/taxes/tax-collection-impact-on-pricing |
| Overrides & exemptions | https://help.shopify.com/en/manual/taxes/tax-overrides |
| Shipping 稅（proportional） | https://help.shopify.com/en/manual/taxes/shipping-tax |
| 數位商品 VAT | https://help.shopify.com/en/manual/taxes/tax-on-digital-products |
| US 稅 reference（origin/destination/nexus 門檻/州特例） | https://help.shopify.com/en/manual/taxes/us/us-tax-reference |
| US 稅管理 | https://help.shopify.com/en/manual/taxes/us/us-tax-manage |
| US liability insights | https://help.shopify.com/en/manual/taxes/us/us-tax-liability |
| 稅務法規理解（marketplace 計入） | https://help.shopify.com/en/manual/taxes/us/navigating-us-tax-regulations |
| EU 稅 | https://help.shopify.com/en/manual/taxes/eu ＋ /eu/eu-tax-reference |
| UK 稅 reference（£135/£90k/NI） | https://help.shopify.com/en/manual/taxes/uk/uk-tax-reference |
| Canada 稅 reference（GST/HST/PST/QST） | https://help.shopify.com/en/manual/taxes/canada/canada-tax-reference |
| Duties & import taxes（CIF/FOB/de minimis/DDP/DAP） | https://help.shopify.com/en/manual/international/duties-and-import-taxes |
| 結帳收 duties（前置/費率/互斥） | https://help.shopify.com/en/manual/international/duties-and-import-taxes/charging-duties |
| 每市場 duties/taxes 設定 | https://help.shopify.com/en/manual/markets/customizations/duties-and-taxes |
| VAT invoices（EU/UK） | https://help.shopify.com/en/manual/taxes/shopify-tax/vat-invoices |
| 稅報表 | https://help.shopify.com/en/manual/taxes/tax-reports |
| Draft orders 稅計算（shipping→billing fallback 原文） | https://help.shopify.com/en/manual/fulfillment/managing-orders/create-orders/create-draft |
| POS 稅（依裝置指派 location） | https://help.shopify.com/en/manual/taxes/set-adjust-pos-taxes |
| Tax apps（fallback 行為） | https://help.shopify.com/en/manual/taxes/tax-apps |
| GraphQL TaxLine | https://shopify.dev/docs/api/admin-graphql/latest/objects/TaxLine |
| GraphQL TaxExemption enum | https://shopify.dev/docs/api/admin-graphql/latest/enums/TaxExemption |
| GraphQL Duty | https://shopify.dev/docs/api/admin-graphql/latest/objects/Duty |
| GraphQL taxAppConfigure | https://shopify.dev/docs/api/admin-graphql/latest/mutations/taxAppConfigure |
| GraphQL TaxPartnerState | https://shopify.dev/docs/api/admin-graphql/latest/enums/TaxPartnerState |
| GraphQL companyLocationTaxSettingsUpdate | https://shopify.dev/docs/api/admin-graphql/latest/mutations/companylocationtaxsettingsupdate |
| Refund duties（FULL/PROPORTIONAL） | https://shopify.dev/docs/apps/build/orders-fulfillment/returns-apps/view-and-refund-duties |
| GraphQL Order（totalTaxSet/currentTotalDutiesSet） | https://shopify.dev/docs/api/admin-graphql/latest/objects/Order |
| Managed Markets duties-inclusive pricing | https://changelog.shopify.com/posts/drive-international-conversion-with-automated-duties-inclusive-pricing-from-shopify-managed-markets |
