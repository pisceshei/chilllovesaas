# 85 — 運送設定與 Checkout 實測 teardown（結帳線第二包取證輪）

> 取證：**2026-08-31**，測試店 `chill-love-u5q5mnzq`（Plus dev，全權寫入授權）；
> 工具＝本地 Chrome；原生 select 一律 DOM 收割。探針資產（S9-Probe-Ship profile）
> 已於取證後**刪除**、購物車已清空、split shipping 開關已復位——店面零殘留。
> 網路查證同日（官方頁逐字引句見本檔 §6；完整表在研究艦隊輸出，工作區存檔）。

## §1 Settings→Shipping and delivery 索引

- **Shipping profiles**：Store default＝**General profile**（`All products`；建第二檔後
  措辭變 **`All other products`**——補集語義的 UI 直證）·1 of 1 location·2 zones；
  「Add custom profile」。第二檔存在時多出 **`Manage split shipping [On]`** 列
  （單檔時隱藏）。
- Estimated delivery dates＝Automated dates ⌄；Shipping labels（Calculate rates）；
  **Packages＝1 box**（店預設包裹）；Carrier accounts＝None。
- **Additional delivery methods 三列**：Local delivery／Pickup in store／Pickup points
  ——皆 Off（三分法與 15 §F3.1(a) 對齊）。
- Documents：Sender name／Templates（Packing slip, Invoice, Pick list）。
- **Delivery customizations**：「Customizations control how delivery options appear to
  buyers at checkout. You can hide, reorder, and rename delivery options.」（app 掛載層）。

## §2 General profile 詳情（/settings/shipping/profiles/115610419435）

- Products：「All products not in other profiles」＋「New products are added by default」。
- Fulfillment location：Shop location·United States。
- **Zones**：**Domestic**（US）：rates **Express** $15.00（1–2 business days）／**Standard**
  $8.00（`Free $70.00 and up · 3–5 business days`——條件免運與費率同列顯示）；
  **International**（27 國）＋🔴 警示橫幅逐字「**To start selling to 27 countries/regions
  in this zone, include them in a market**」＝zone≠market 正向 guard 的 2026 現形
  （F2.2；44:524 舊測的現值複驗）。
- Carrier rates（僅 International zone 掛）：**DHL Express**（1 service·Supports prepaid
  duties·Calculated transit time·Worldwide）／**USPS**（3 services：First Class Package
  International／Priority Mail Express International／Priority Mail International）——
  徽章 **Calculated**。

## §3 費率編輯器（Edit/Add shipping option；2026 形態）

- 欄位：Name＋「Add delivery details」；**Rate type**（原生 select **恰四值**，DOM 逐字）：
  `flat_rate`＝Flat（預設）／`carrier`＝Carrier or app calculated／`order_amount`＝
  Order amount／`weight`＝Package weight。**條件費率已升格為 rate type**（不再是
  flat＋附加條件的形）。
- **Transit time**（select 恰五值）：1 to 2／3 to 5／5 to 8 business days（value＝
  base64 JSON `{"min":86400,"max":172800}` 等——**秒制區間**）／Custom／None。
  🔴 **必填**：空值提交＝紅框＋逐字「Transit time is required」（None 是顯式選項）。
- `order_amount` 型＝**分級列**：Minimum／Maximum（空＝「No limit」）／Price／Transit
  time＋⊕（加一級）＋🗑——分級費率＝多列 [min,max)→price。
- ☑ **Offer free shipping** → Minimum order amount（General Standard＝$70.00 USD）。
- 🔴 **費率自帶幣別**：General profile 顯示「Amounts set in US dollars (USD). Change
  currency」；新建 profile 的費率預設 **HK$**（店幣）⇒ rate 有 currency 維度。
- 探針 rate：S9-Probe-Ship／zone Probe-US／`Standard` HK$5.00／transit None（取證後全刪）。

## §4 Zone 建立對話（Create new shipping zone）

- Zone name（「Customers won't see this」）＋搜尋＋國家樹：**候選只列 market 內國家**
  （本店＝North America→United States），底部連結逐字「**Add more countries/regions
  in Markets**」⇒ **zone 建立面被 Markets 界定**（F2.2 的另一半：新 zone ⊆ market；
  §2 的 27 國警示＝歷史資料可違反＋警示）。US 可展開至 **62 states** 州級勾選。
- 零費率 zone 警示逐字：「Add a shipping option to let customers check out for orders
  shipping to this zone」＝`Rates(p)=∅ ⇒ 擋結帳` 的 admin 面。

## §5 Checkout 實測（chill.deals；帳號未登入、無 PSP ⇒ 不可能產生費用）

### §5.1 One-page 結構（URL 形＝`/checkouts/cn/<token>/en-us?...`——token＋locale 段）

區塊序（單頁）：**Contact**（Email＋Sign in＋「Email me with news and offers」勾選）→
**Delivery**（Country/Region ⌄→First/Last name→Address（autocomplete 放大鏡）→
Apartment (optional)→City/State ⌄/ZIP→Phone (optional)❓→「Save this information for
next time」）→ **Shipping method**（地址完整前逐字「Enter your shipping address to view
available shipping methods.」）→ **Payment**（「All transactions are secure and
encrypted.」；本店無 PSP＝「This store can't accept payments right now.」）→ Pay now。
右欄摘要：行項＋Subtotal＋Shipping（「Enter shipping address」→金額）＋Total（**HKD** 前綴）。

- 🔴 **admin 設定 ↔ 前台欄位端到端對應**：contact method=Email ⇒ 只有 Email 欄；
  Full name=Require first and last ⇒ 兩欄；Address line 2=Optional ⇒ 「(optional)」；
  Phone=Optional 同。**Country 下拉只有 United States**＝官方句「active market ∩
  shipping zone with rates」的實測面。State 62 值（50 州＋領地＋軍郵 AA/AE/AP）。
- 網路層：checkout 走 `POST /checkouts/internal/graphql/persisted?operationName=Proposal`
  （每次欄位變更／費率選擇各一發）——persisted query，**query 全文不可觀測**（鐵律
  14.3）；response body 本輪工具未暴露＝未取得。

### §5.2 費率計算與幣別（單 profile 期）

地址填畢即出：**Standard $62.73**（Fri, Sep 4–Wed, Sep 9；預設選最便宜）／**Express
$117.62**（Wed, Sep 2–Thu, Sep 3）；Shipping 入 Total。
- 換匯實證：rate 設定 $8／$15 **USD** ⇒ 前台 presentment **HKD** 62.73／117.62（×~7.84）。
- 🔴 **免運門檻以費率自身幣別比較**：subtotal HK$266.50（≈34 USD）＜ $70 USD ⇒
  Standard **收費**。若門檻按 presentment 數字面比（266.50 ≥ 70）早該免運——被否證。
- transit 區間 ⇒ 前台顯示**日期範圍**；transit=None 的探針費率顯示「Ships next business
  day」（來源疑＝processing/Automated dates，登記）。

### §5.3 Split shipping（雙 profile 期；2026 現行形）

加入第二件（POLA·General 檔）後：
- 逐字「🚚 **Your order will arrive in 2 shipments**」；選中卡「**Lowest price** $5.00」
  內列 per-shipment 明細：「📦 1 item · Standard／Fri, Sep 4–Wed, Sep 9／**FREE**」
  （POLA 行 $1,119≈143 USD ≥ $70 ⇒ General Standard 免運觸發）＋「📦 1 item ·
  Standard／Ships next business day／$5.00」（Davidoff 行·探針檔）。
- 「**More shipping options**」modal＝**Shipment 1**（radio：Standard FREE✓／Express
  $117.62）＋**Shipment 2**（Standard $5.00 唯一）＋Save ⇒ **per-shipment 獨立選擇**。
- 換 profile 歸屬後重進 checkout 出警示逐字：「The shipping options have changed for
  your order. Review your selection.」
- **Split 開關**（admin `Manage split shipping`）對話逐字：「**Show split shipping in
  checkout**／Shipping is split when products in an order are fulfilled from different
  locations or belong to separate shipping profiles. Customers will be able to select
  the shipping method for each shipment separately.」
- ⚠ **split 切 Off 對行中 checkout 未生效**（Off 存檔成功＋兩次重載仍 split 形）⇒
  Off 模式的合併形（46c／官方 combined-rates 規則）**本輪未觀測到**，生效範圍未取得
  （V；官方 combined-rates 頁 2026-08-31 仍載同名相加／異名取最便宜相加＋顯示名
  `Shipping`——見 §6）。
- ⚠ 金額條件（免運/order_amount 級距）的**基數**（整車 vs per-participant）本輪
  **未判別**（兩 shipment 各自條件不交叉；官方句「Price-based shipping rates apply
  to the total price of the cart」與 spec 15 F2.1(b) per-participant 相衝，登記 V）。

### §5.4 Profile 刪除語義

Delete profile 確認逐字：「Are you sure you want to delete S9-Probe-Ship? **All
products from this profile will show rates from your general profile at checkout.**」
⇒ 商品回落 General（fallback＝補集回收）。

## §6 官方網路查證錨（2026-08-31；逐字表全文在研究輸出）

- combined-rates 現行正典 `help.shopify.com/en/manual/fulfillment/setup/shipping-profiles/combined-shipping-rates`：
  「Shipping rates with the same name are added together…」「If all of your rates have
  different names, then the cheapest options are added together… with the name
  `Shipping`.」「…a single flat rate is charged.」（location group 只收一次）
- zones×market：`…/international/shipping/shipping-zones`：「Customers can select a
  country at checkout only when it's included in both an active market and a shipping
  zone with available shipping rates.」
- 欄位三態官方字面＝**Don't include／Optional／Required**（checkout-form-options）；
  contact method 恰兩值；「要求登入 ⇒ 只能 email」＋「購物車隱藏加速結帳鈕」。
- checkout 不可主題化：checkout.liquid Plus-only 且對三步已 unsupported；Thank you／
  Order status 2025-08-28 sunset；現行客製＝checkout editor＋UI extensions＋branding API。
- checkouts 狀態 enum：90 藍圖 03 §B.2＝**open/completed/deleted 三值**（無 active；
  abandoned＝時戳旗標）——我方 `Checkout` model 第一包誤用 "active"，本包更正。

## §7 證據五件套彙總（鐵律 14.4）

| 格 | URL（去 token）| 步驟 | 形狀 | 取證日 |
|---|---|---|---|---|
| Rate type 四值／Transit 五值 | admin…/settings/shipping/profiles/115610419435 | Edit option→DOM 收割 | §3 逐字 | 2026-08-31 |
| zone 候選⊆market | 同上（Create zone 對話） | Add zone | §4 | 2026-08-31 |
| checkout 全形 | chill.deals/checkouts/cn/<token>/en-us | cart/add.js→/checkout | §5.1 | 2026-08-31 |
| 免運幣別基準 | 同上 | US 地址→費率 | §5.2（$62.73 非 FREE） | 2026-08-31 |
| split 兩層形 | 同上 | 加第二件→More options | §5.3 | 2026-08-31 |
| persisted GraphQL | …/checkouts/internal/graphql/persisted?operationName=Proposal | 切費率→network | op name only（14.3） | 2026-08-31 |
| profile 刪除 fallback | admin…/profiles/116831551723 | Actions→Delete | §5.4 逐字 | 2026-08-31 |
