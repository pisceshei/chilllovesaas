# 29 — 多語言・多貨幣・多國際市場（Markets 完整機制）

> 目標：CHILL LOVE 具備 Shopify Markets 同級的國際化能力。本文＝官方文檔深研成果（help.shopify.com/manual/markets、shopify.dev markets/localization/currency 全章，查證日 2026-08）＋復刻表結構與行為規格。**優先級 P0/P1/P2 見 §8；與其他文檔的銜接**：hreflang/sitemap 與 30 號 §9 銜接、theme editor 市場 context 與 24 §4.3／27 號銜接、API 面併入 28 號 §13、金額雙記入 06 號資料模型。

## 1. Markets 資料模型

### 1.1 核心概念

- **Market** = 「以特定購買體驗鎖定的一群買家」。新版模型中市場不再只由地理定義，而是由 **conditions（條件）** 決定買家是否命中：地理區域（region）、POS 零售地點（location）、B2B 公司地點（company location）、銷售通路（channel）。
- **MarketType enum**：`REGION`｜`COMPANY_LOCATION`｜`LOCATION`｜`CHANNEL`｜`NONE`。「primary market（主市場）」＝商店主要銷售的國家/地區，**恰含一個國家、不可刪除**，作為預設體驗。
- **MarketStatus enum**：`ACTIVE`｜`DRAFT`。Draft 市場的顧客**可瀏覽但不能完成購買**；停用市場的網域 redirect 回主市場。
- **市場可巢狀（submarkets）**：子市場繼承父市場自訂；同類型自訂「合併」，catalogs 與 web presences 為「累加」，其餘（如貨幣）為「覆寫」。買家同時命中多個市場時，**取最特定者**——完整優先序與繼承語義見 **§1.5**。
- **Backup region**：必設，指向某 active market 內的一個國家。不命中任何 active market 的訪客看到 backup region 的貨幣/語言/主題內容，**可瀏覽、不可結帳**。位於 Settings → General。
- **限制**：wildcard 市場每店上限 100；低階方案實務上限 3 個 active markets、Advanced/Plus 至 50；同一組 regions 只能屬於一個 active market（不可重疊；draft 可）。

### 1.2 每市場可設定項

| 面向 | 內容 |
|---|---|
| 網域策略 | 三選一：主網域子資料夾（`example.com/fr-ca`）／子網域（`ca.example.com`）／獨立網域（`example.ca`）。`MarketWebPresence`：`domain` 與 `subfolderSuffix` **互斥（XOR）**；`defaultLocale`；`alternateLocales[]`；`rootUrls[]`（每 locale 一個根 URL）。**語言-only 子資料夾（`/fr`）僅限 primary market**；次級市場一律 `語言-國家`（`/fr-ca`） |
| 語言 | 每市場一組啟用語言＋自己的 default language。全店最多 **20 種語言**；語言有 published/unpublished 狀態；自市場移除語言 → 該語言 URL 立即 404 |
| 貨幣 | `MarketCurrencySettings { baseCurrency, localCurrencies: Boolean, roundingEnabled: Boolean }`；多國市場可 `localCurrencies=true`（每國當地貨幣自動換匯）；可設手動匯率（僅非主市場） |
| 價格調整 | percentage adjustment ±%（實作於 price list 的 parent.adjustment） |
| 固定價 | price list fixed prices（per variant per currency），覆蓋百分比調整 |
| Duties/稅 | 每市場 DDP/DAP 開關；HS code＋country of origin＋CIF/FOB＋de minimis（P2） |
| B2B | `COMPANY_LOCATION` 型市場＋專屬 catalogs＋付款條件（P2） |
| Theme 內容 | 每市場 contextual template 覆寫（§7.3） |

### 1.3 Catalog / Price List 模型

```
Catalog   = { context(市場/公司地點/app), priceList, publication(可售商品集合) }
PriceList = { currency（必須=市場貨幣）, parent: { adjustment: {type: PERCENTAGE_INCREASE|DECREASE, value},
              settings: {compareAtMode} }, prices: [{variant, price, compareAtPrice, originType: FIXED|RELATIVE}] }
```
- 未設固定價的 variant → base price × (1±adjustment%) 自動計算（RELATIVE）；固定價覆蓋（FIXED）。
- `priceListFixedPricesAdd` 單次上限 250 筆。
- 商品未發佈到市場 catalog → 前台隱藏、搜尋不出現、不可加車。

### 1.4 復刻表結構（全帶 shop_id，摘要）

`shop_locales`（locale/primary/published，unique [shop_id, locale]）、`markets`（name/handle/status/market_type/primary/**`derived_parent_market_id`（推導快取，見 §1.5，不是權威欄位）**）、`market_regions`（country_code，unique [market_id, country_code]＋應用層驗證 active 不重疊）、**`market_settings`（market_id, key, value JSON **NULL＝繼承**，unique [market_id, key]）**、`market_web_presences`（domain_id XOR subfolder_suffix、default_shop_locale，check constraint）、`market_web_presence_locales`（alternateLocales＋position）、`market_currency_settings`（base_currency/local_currencies/rounding_enabled/manual_exchange_rate）、`catalogs`（context_type）＋`catalog_markets`＋`catalog_publications`、`price_lists`（currency/adjustment_type/adjustment_value/compare_at_mode）、`price_list_prices`（只存 FIXED；unique [price_list_id, variant_id]）、`currency_exchange_rates`（base/quote/rate/fetched_at）、shops 增 `backup_region_country_code`。

**價格解析順序**：fixed price → base×(1±adj%)×匯率(手動優先)×(1+轉換費率) → rounding（若啟用）。

### 1.5 父子關係與繼承模型（P1-32／T-05，本輪重寫）

> <!-- 依 46b:632–664、46b:690–717、46b:777–793 修正，原文逐字：
>      「A market can have **one or more parent markets**. If a market does not define a customization, it will inherit the customization from its parents, or the store defaults if no customization is defined on any parent.」
>      「**關鍵：parent 不是手動指定的，是自動推導的（lineage inference）**：子市場的 region 是父市場 condition 的**嚴格子集** → 成立父子；子市場的 location 落在父市場的 region 內 → 成立父子；**具體地點列舉不參與 lineage 計算**」
>      「**用 null 表達繼承**…**沒有 `inherited: Boolean` 這種顯式旗標，也沒有 `parentMarketId` 欄位**（Market 物件無 parent/child 欄位）」
>      🔴 此處原本寫錯：§1.4 原本把 `parent_market_id` 列為 `markets` 的**權威欄位**（來源是 44:869 從 UI「上層市場：🏪 商店預設」區塊推論），
>      與官方「由 conditions 自動推導」直接衝突——後果：商家改了 regions，父子關係不會跟著變，繼承解析出錯。
>      任何人翻舊版看到權威的 `parent_market_id` 都不要改回去。 -->

**(a) 父子＝推導，不是欄位**

```
is_parent(P, C) ⟸  C.conditions.regions ⊊ P.conditions.regions            # 嚴格子集
              ∨  C.type ∈ {LOCATION, COMPANY_LOCATION}
                 ∧ C 的地點座落於 P.conditions.regions 之內
# 具體地點列舉不參與推導（「Companies A,B」vs「Companies A,B,C」不成立父子）
```
- `markets.derived_parent_market_id` 是**物化快取**：任一 market 的 conditions 變更即重算受影響子樹（同 transaction），nightly job 全量重算對帳。
- **API 不暴露 parent/child 欄位**（照抄官方 `Market` schema，28 §13）；admin UI 的「上層市場」區塊讀快取。
- 根為 **Store Default**（商店預設），永遠是所有 market 的最終上游。

**(b) 命中優先序（buyer 同時命中多市場時）**：`Company Location > Retail Location > Region > Store Default`（46b:641–648）。多個父市場時，繼承解析同樣依此序取最特定者。

**(c) 繼承語義：`NULL` ＝ 繼承**

| 維度 | 官方語義 | 落地 |
|---|---|---|
| `catalogs` | **累加（additive）** | 子市場的 catalog 集合 ＝ 自身 ∪ 沿 lineage 上溯的全部 |
| `webPresences` | **累加（additive）** | 同上 |
| `currencySettings` | **覆寫（override）** | `market_settings['currency'] IS NULL` ⇒ 取最近一個非 NULL 的祖先 |
| `priceInclusions` | **覆寫（override）** | 同上 |
| `delivery.shipping` | 46b 說「null ⇒ 繼承」；44 說「永遠市場本地」 | **⚠ 待查證（V-02），不得二選一寫死**——見 (e) |
| 折扣／主題／結帳設定檔／退貨規則 | **官方公開 API 未載明繼承語義**（46b:788 逐字「admin UI 已上線、公開 API 未跟上」） | **本專案自定：一律 override，`NULL ⇒ 繼承`**，並在 UI 標「本專案決策」 |

> 44:862 實測 admin 有 **8 個**可繼承維度（幣別／目錄／折扣／主題／結帳設定檔／網域+語言／稅與關稅／退貨規則）；
> 公開 API 只對其中 **4＋1** 個有官方語義。處置：**UI 做 8 個、資料模型統一走 `market_settings(key, value NULL=繼承)`**，
> 其中 4 個標官方語義、4 個（折扣／主題／結帳設定檔／退貨規則）標「Shopify 公開 API 未載明，本專案決策」（對應 50 號 T-06／T-07）。

**(d) 「繼承 vs 已覆寫」徽章的資料來源**：`Market.assignedCustomization(customizationId:)`（28 §13）——`value IS NULL` ⇒ 分到「繼承的設定」區並顯示解析後的**生效值**；非 NULL ⇒ 分到「自訂項目」區。

**(e) ⚠ 待查證（來源未載明／三方衝突）**：
- **V-02 市場的 `shipping` 到底繼不繼承**：`46b:659–661` 逐字「Null means the market inherits shipping from its parent」vs `44:866` 逐字「運送與隱私權**不繼承**，永遠市場本地」。**直接矛盾，須 GraphQL introspection ＋ dev store 實測覆核**。在覆核前，`market_settings['shipping']` 的欄位先建、解析器留兩套策略開關（`limits.market.shipping_inherits: null` ＝ 未定案），**不得預設任一邊**。
- **V-10 每店 markets 總數上限、巢狀層數上限、`MarketUserErrorCode`**：46b:993–1010 逐條標未載明（社群「50 markets」說法**未經官方證實，勿引用**）。

## 2. 翻譯層

### 2.1 可翻譯資源類型（30 種，TranslatableResourceType）

PRODUCT（title/body_html/handle/product_type/meta_title/meta_description）、PRODUCT_OPTION（name）、PRODUCT_OPTION_VALUE（name）、COLLECTION（title/body_html/handle/meta_*）、COLLECTION_IMAGE（alt）、ARTICLE（title/body_html/summary_html/handle/meta_*）、ARTICLE_IMAGE、BLOG、PAGE、MENU（title）、LINK（title）、FILTER（label）、METAFIELD（value）、METAOBJECT（依 type）、MEDIA_IMAGE（alt）、SELLING_PLAN(_GROUP)、SHOP（meta_*）、SHOP_POLICY（body）、EMAIL_TEMPLATE（title/body_html）、PACKING_SLIP_TEMPLATE、PAYMENT_GATEWAY（name/message/instructions）、DELIVERY_METHOD_DEFINITION（name/description）、ONLINE_STORE_THEME ＋ THEME_LOCALE_CONTENT ＋ THEME_JSON_TEMPLATE ＋ THEME_SECTION_GROUP ＋ THEME_SETTINGS_CATEGORY ＋ THEME_SETTINGS_DATA_SECTIONS ＋ THEME_APP_EMBED（皆動態 keys）。

**不可翻譯**：tags；URL 固定資源段（`products`/`collections` 不可譯，只有 handle 可譯）。

### 2.2 儲存模型（digest 綁版本）

```ruby
create_table :translations do |t|
  t.references :shop
  t.string  :resource_type; t.bigint :resource_id
  t.string  :locale; t.references :market, null: true   # null=全域；非 null=per-market 覆寫（Adapt）
  t.string  :key; t.text :value
  t.string  :source_digest, null: false                  # SHA-256(原文)；原文改 → outdated
  t.boolean :outdated, default: false
  t.index [:shop_id, :resource_type, :resource_id, :locale, :market_id, :key], unique: true
end
```
- **digest 機制**：註冊翻譯必附原文 hash；原文改動 → 全 locale 譯文批次標 outdated（翻譯後台「需更新」的來源）。
- 讀取 fallback：`(locale, market)` → `(locale, 全域)` → 預設語言原文。
- Shopify 原型 API：`translatableResources` / `translationsRegister(resourceId, [{locale, key, value, translatableContentDigest, marketId?}])` / `marketLocalizationsRegister`。

### 2.3 Theme 靜態字串 vs 動態內容分工

- **Theme locale files**（`locales/*.json`）管 theme UI 字串：`en.default.json` 必有；區域型 `fr-CA.json`；`*.schema.json` 管編輯器字串。上限每檔 3,400 條、每條 1,000 字元；`{{ 'templates.cart.title' | t }}` 取用。**theme locale 檔內容本身也可被商家覆寫**（THEME_LOCALE_CONTENT 資源型）。
- **動態內容**（商品/頁面/blog/theme JSON 設定文字）走 §2.2 translations。

### 2.4 Translate & Adapt 行為（我們的翻譯後台規格）

側欄資源樹（Products/Collections/Pages/Blog/Metaobjects/Theme/Notifications/Policies/Menus）→ 上方語言/市場 tab → 主體**逐 key 雙欄表格**（左原文唯讀、右譯文編輯，富文本帶編輯器）；「Auto-translate」機翻（**限 2 種語言**，仿官方限額）；同語言選其他市場＝**Adapt 模式**（per-market 覆寫）；outdated 列標示；CSV 匯入/匯出。

### 2.5 URL locale 前綴路由

- 主網域＋primary 預設語言 → **無前綴**；primary 其他語言 → `/{lang}`；次級市場 subfolder → `/{lang}-{suffix}`；獨立網域市場：defaultLocale 在根、alternate 在 `/{lang}`。
- 每個 `web presence × locale` 一個 root URL；`routes` drop 與 `window.Shopify.routes.root` 都要吐帶前綴的值（Liquid 相容層銜接點！）。

## 3. 多貨幣機制

### 3.1 三種貨幣角色與雙記

shop currency（底價/記帳）、presentment currency（顧客看見並支付）、payout currency。**API 慣例：金額一律 `MoneyBag { shopMoney, presentmentMoney }` 雙記**——orders/refunds/transactions 存兩組 amount+currency＋成交時匯率。

### 3.2 匯率與換算

- 自動匯率一日多次更新；手動匯率固定（僅非主市場）。**轉換發生在交易當下**（capture/refund/chargeback 各用當時匯率）；訂閱續扣沿用首單匯率。
- 換算式：`顧客價 = 底價 × 匯率 × (1 + 轉換費率)`；轉換費率 1.5%（美/英/EEA）或 2%（其他）。

### 3.3 Rounding 與零小數貨幣

- 每市場開關；形式「Round up to the nearest {value}」，每貨幣 target 固定預設（EUR→x.95、JPY→¥100、USD 整數…）。復刻：`currency_rounding_rules(currency, target)` 表。**fixed price 不換算不湊整；gift card 不湊整**。
- 零小數貨幣（exponent=0）：JPY/KRW/VND/CLP/ISK/BIF/DJF/GNF/KMF/PYG/RWF/UGX/VUV/XAF/XOF/XPF——顯示與收款一律整數；money filter 格式化不得出現小數。

### 3.4 退款匯率（反直覺規則）

退款給顧客＝原幣原額；商家端換匯用**退款當下匯率**（非下單時）→ FX 損益由商家承擔（官方例：€85 單當時 $100，數週後退款花 $110）。復刻：orders 存 `exchange_rate_at_order`、refunds 存 `exchange_rate_at_refund`，報表揭露 FX gain/loss。

### 3.5 Liquid 端

money filter 按商店貨幣格式模板輸出**當前 presentment 貨幣**；`cart.currency` ≠ `shop.currency`；structured data 的 priceCurrency 用 `cart.currency.iso_code`。

## 4. 前台行為

- **市場判定鏈**：URL（網域/子資料夾）優先 → GeoIP 建議 → 不命中則 backup region。
- **Automatic redirection** 可選；共用主網域模式就地切換（不改 URL，該內容不被索引）。**爬蟲永不 redirect**（官方明載）；EU ccTLD 不自動跳轉。復刻：GeoIP → 「建議切換」banner ＋ cookie 記住選擇，bot 一律直出所請 URL。
- **localization form**：`{% form 'localization' %}` + country_code/language_code（兩個欄位名都收，25 號坑 #4）；切國家時語言不被支援 → 落到市場預設語言。
- **hreflang**：對每個有獨立 URL 的 market×locale 組合輸出 `<link rel="alternate" hreflang>`（經 content_for_header 注入）＋ `x-default` 指主網域；**每市場化 URL self-canonical**；sitemap 收全部市場 URL（子資料夾併主網域 sitemap，獨立網域各自有）。

## 5. 結帳與市場

結帳鎖定進入時的 presentment currency（結帳頁不能換幣）；draft 市場結帳前即擋；付款方式=顧客國家×幣別×金流商支援的交集；shipping zones 與市場國家對齊，未涵蓋國家=不可結帳；duties 開啟（DDP）→ 結帳加 duties 行項（P2）。

**zone ≠ market：兩個方向都要有 guard（P1-24／H-112）**
<!-- 依 44:524、44:622 補寫，原文：運送 zone 頁黃色警示橫幅逐字「⚠ 若要在此區域開始銷售至 27 個國家/地區，請將這些國家/地區加入市場」；
     44 行動項 38 逐字「**zone ≠ market**：建了運送區域不代表能賣，必須同時加進 Markets。這是一條跨模組硬約束，我們 29 號 Markets 與 15 號 Shipping 都沒寫」。
     複核更正：本節上一句「shipping zones 與市場國家對齊，未涵蓋國家=不可結帳」其實已寫了**反方向**，
     50 號「29 與 15 都沒有」不完全成立；真正缺的是①正方向（有 zone、不在 market → 不可販售）②admin 警示橫幅 ③15 側 RateResolver 的 guard。 -->

| 方向 | 判定 | 行為 |
|---|---|---|
| **有 zone、國家不在任何 active market**（本輪新增） | `country ∈ shipping_zone.countries` 且 `country ∉ ⋃ active_market.regions` | **不可販售**：該國訪客落到 backup region（可看不可買）；**運送 zone 頁出黃色警示橫幅**「若要在此區域開始銷售至 N 個國家/地區，請將這些國家/地區加入市場」＋直達 Markets 連結 |
| 在 market、無任何 zone 涵蓋（原有） | `country ∈ active_market.regions` 且無可用費率 | 可瀏覽，結帳到運送階段被擋（15-F2.1(b) 的 `Rates(p) = ∅` 分支） |

`limits.shipping.zone_requires_market: true`。**兩個方向的差集數量必須在 admin 兩邊都可見**（Markets 頁顯示「有 zone 但未開賣的國家 N 個」、Shipping 頁顯示「已開賣但無費率的國家 M 個」）——只做單邊警示，商家仍會在客訴時才發現。15 側規格見 **15-F2.2**。

## 6. Admin UI 結構

- **Settings → Markets**：清單頁（名稱/狀態/國家、Add market）；單市場詳情分區：①狀態（Active/Draft）②Domains and languages（三選一＋語言管理＋Set as default）③Currency and pricing（base currency/local currencies/手動匯率/adjustment %/rounding）④Duties ⑤Catalogs ⑥Shipping/Checkout ⑦Theme content（跳 theme editor 市場 context）。
- 刪市場：國家移轉自動摘除、市場空了自動刪；backup region 在 Settings → General。
- 翻譯後台 UI 見 §2.4。

## 7. API 面（併入 28 號 §13）

### 7.1 Admin GraphQL 操作表

| 類別 | Queries | Mutations |
|---|---|---|
| Markets | `markets`, `market(id)` | `marketCreate/Update/Delete` |
| Web presence | market.webPresences | `webPresenceCreate/Update/Delete` |
| 貨幣 | market.currencySettings | `marketCurrencySettingsUpdate` |
| Catalogs | `catalogs` | `catalogCreate/Update/Delete`, `catalogContextUpdate`, `publicationUpdate` |
| Price lists | `priceLists` | `priceListCreate/Update/Delete`, `priceListFixedPricesAdd/Update/Delete/ByProductUpdate` |
| 翻譯 | `translatableResources(ByIds)` | `translationsRegister/Remove` |
| 市場在地化 | `marketLocalizableResources` | `marketLocalizationsRegister/Remove` |
| 語言 | `shopLocales` | `shopLocaleEnable/Disable/Update` |

### 7.2 Storefront context

`@inContext(country: CA, language: FR)` → 價格/可售性/翻譯按市場 context 回傳；`buyer`（B2B）；cart 以 `cartBuyerIdentityUpdate(countryCode)` 對齊。我們的等價物：SSR 渲染管線的 `RequestContext{market, locale, currency}` 中介層＋所有 drops 讀 context。

### 7.3 Theme contextual templates

`templates/{template}.context.{market-handle}.json`：`{"context": {"market": "handle"} | {"b2b": true}, "parent": "index.json", "sections": {僅差異}}`——editor 市場切換時自動生成；**可覆寫** section 內容/blocks/settings，**不可覆寫**全域 theme settings 與 Liquid。與 24 §4.3 的 `template_overrides` 表一致。

## 8. 實作優先級

- **P0（M2 隨行）**：shop_locales＋translations（含 digest）＋匯率表；`/{locale}` 路由＋t filter＋locale files；翻譯後台（資源樹+雙欄+機翻 2 語言）；多幣「顯示」（GeoIP/selector→presentment、換算式、零小數）；結帳仍 shop currency 收款；hreflang（locale 維度）。
- **P1（M5-M6）**：markets 全表＋市場解析中介層＋backup region；per-market adjustment＋rounding 表＋手動匯率；訂單雙幣記帳＋兩時點匯率；localization form 雙 selector＋GeoIP banner；hreflang 全組合＋x-default＋分網域 sitemap；translations.market_id（Adapt）；contextual templates；Settings→Markets UI。
- **P2**：price lists/catalogs 限售、duties（HS code/CIF/FOB/de minimis）、B2B、submarkets、真多幣收款（Stripe presentment currency）。

## 9. 復刻最易踩的規格點

1. active markets 國家不重疊（應用層驗證）。2. digest 綁版本，原文改 → 批次標 outdated。3. 退款當下匯率 vs 訂閱鎖首單匯率（兩條相反規則同進 money service）。4. 爬蟲永不 redirect＋self-canonical＋hreflang 互聯＝國際 SEO 全部骨架。5. 語言-only 前綴僅限主市場（路由 constraint 寫死）。6. fixed price 不套匯率不套 rounding。7. backup region 可看不可買（miss 不 500、不放行結帳）。

> 來源：help.shopify.com/manual/markets 全章、shopify.dev Market/MarketWebPresence/MarketCurrencySettings/PriceList/TranslatableResourceType/translationsRegister/@inContext、themes/architecture/locales、international/pricing（exchange-rates/rounding/refunds）、automatic-redirection、markets/seo。查證日 2026-08-11。


## 10. B2B（Company／CompanyLocation）——掛載層級與資料模型（P1-33／H-64～H-68）

> 本節為新增。50 號 H-64 逐字：「44 行動項 71 說『我們 B2B 規格原本掛在 company 上——要改』，但**實際上不存在該規格**」。
> 本輪複核確認：`docs/specs` 下無任何 B2B 規格檔，僅 admin 原型（`chilllove-admin-v2.html`）有註釋。B2B 落在 29 號是因為 **`COMPANY_LOCATION` 是 MarketType 的五個值之一**（§1.1），與 Markets 的 conditions 模型同源。
> **API 契約見 28 §13b（權威）**；本節只寫資料模型與掛載鐵律。

**(a) 三表 ＋ 兩張關聯表**（全帶 `shop_id`）
`companies`（name / external_id / note / default_role_id / main_contact_id）、
`company_locations`（company_id / name / locale / currency / billing+shipping address / `buyer_experience_configuration` JSON / tax_settings）、
`company_contacts`（company_id / **`customer_id` 外鍵 → 復用 `customers` 表**）；
關聯：`company_contact_role_assignments`（contact × **location** × role）、`company_location_catalogs`。

**(b) 掛載鐵律（H-64，最重要的一條，migration 檔頭要寫上）**
<!-- 依 46b:817–830、46b:936 補寫，原文逐字：「Catalogs attach exclusively to company locations, not companies.」
     「some information, such as tax IDs and exemptions, is location-specific and must be updated from the location page」
     「`Company.defaultRole`：The role proposed by default for a contact at the company.」
     46b §5⑥-2 逐字：「**Admin UI 提供『從 company 頁批次套到所有 location』的便利操作，但資料仍寫進每個 location**——這正是 Shopify 的作法，能避免『company 值 vs location 值誰贏』的繼承地獄。」 -->
> **catalog／payment terms／tax（tax ID・exemptions）／checkout 設定／currency／locale／地址 —— 一律掛 `company_locations`。**
> **`companies` 只有 `name` / `note` / `default_role` / `main_contact` 四個欄位是自己的。**
> **不得**在 `companies` 上加 catalog/tax/currency 欄位再做「location 沒設就用 company 的」——那正是 Shopify 刻意避開的繼承地獄，也是 44 行動項 71 要我們改掉的東西。

**(c) 另外四條**
- **H-68**：`company_contacts` **不是獨立帳號**，掛在 retail customer 上（`customers` 表要能同時扮演 B2C 顧客與 B2B 聯絡人）。角色（`ordering_only` / `location_admin`）是 **contact × location** 的指派，不是 contact 的全域屬性。
- **H-66**：同一 location 命中多個含相同商品的 catalog → **取最低價**（`MIN(price)`）；且商品**必須至少發佈到一個 applicable publication 才可見**。
- **H-67**：**不得建 `company_locations.market_id` 正向外鍵**（`CompanyLocation.market` 官方已 deprecated）；改由 `COMPANY_LOCATION` 型 market 的 `companyLocationsCondition` 反查——與 §1.5 的推導模型一致。
- **S-27 審核流**：`buyer_experience_configuration.checkout_to_draft = true` ⇒ 結帳建 draft order 而非 order；付款結果**三態**（無 terms → 立即付款／NET → `payment_pending`／NET＋deposit → `partially_paid`）。

**(d) 上限**：一律引用 `limits.b2b.*`（10,000 locations/company、10,000 contacts/company、**50 contacts/location**、25 catalogs/location、250 prices/request、**1 company/customer**；B2B 為 Plus 專屬功能）。
**(e) ⚠ 待查證（來源未載明）**：NET 7/15/30/45/60/90 的內建清單（46b:892）、`CheckoutProfile` 是否有 company/location 欄位（46b:828）——見 54 號 §附錄 A 的 V-19。
**(f) 優先級**：整組屬 **P1（M5）**，與 §8 的 markets 全表同批；資料模型（(a)(b)）必須在 M5 動工前定案，因為 `customers` 表的 B2B 相容性是 M1 的 schema 決定。
