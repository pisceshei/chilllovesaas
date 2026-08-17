# 11. Markets 國際化（Markets / Catalogs / 幣別 / 翻譯）

> 任務：對 Shopify 2026 官方文檔（shopify.dev Admin GraphQL `latest`＋help.shopify.com）做 Markets 領域考掘，寫成可直接落地的業務邏輯章。取證日 2026-08-14。
> 與倉庫既有研究的關係：`docs/research/29`（Markets 全機制）與 `docs/research/79`（R10 按鈕級 teardown）是底座，本章以**今日官方文檔**逐條複核並補值域／狀態機／公式；`docs/specs/67`（多語言）的裁定不得違反——凡本尊行為與我方裁定不同處，一律在 §F 標明「本尊 vs 我方」。
> 標記約定：`[dev]`＝shopify.dev、`[help]`＝help.shopify.com、`[repo:NN]`＝倉庫既有已查證文檔、⚠️＝官方查不到／證據等級不足，已入 openQuestions。

---

## A. 領域物件模型

### A.1 物件總表與 cardinality

```
Shop 1 ─── N Market ──── 1 MarketConditions ──── 0..1 RegionsCondition / CompanyLocationsCondition
  │                │                              / LocationsCondition / ChannelsCondition（每型至多一個）
  │                ├─── N MarketCatalog（沿 lineage 累加）
  │                ├─── N MarketWebPresence（N:M——一個 web presence 可掛多個 market）
  │                ├─── 0..1 MarketCurrencySettings
  │                ├─── 0..1 MarketPriceInclusions
  │                └─── 1 MarketDeliveryConfigurations
  ├─── N ShopLocale（≤20；恰一個 primary）
  │        └─ N:M MarketWebPresence（defaultLocale 1 個 ＋ alternateLocales N 個）
  ├─── N Catalog（interface：MarketCatalog｜CompanyLocationCatalog｜AppCatalog）
  │        ├─── 0..1 PriceList ─── N PriceListPrice（只存 FIXED 列）
  │        └─── 0..1 Publication ─── N product/collection 發佈列
  └─── 1 backup region（shop 級設定，指向某 active market 內的一個國家）
```

### A.2 Market 物件（[dev] objects/Market，取證 2026-08-14）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `ID!` | GID |
| `name` | `String!` | 市場名（顧客不可見） |
| `handle` | `String!` | 唯一、可由商家改 |
| `status` | `MarketStatus!` | **值域窮舉：`ACTIVE`｜`DRAFT`**（無第三值；79 §1 實測同） |
| `type` | `MarketType!` | **值域窮舉：`REGION`｜`COMPANY_LOCATION`｜`LOCATION`｜`CHANNEL`｜`NONE`**（[dev] enums/MarketType） |
| `conditions` | `MarketConditions` | 命中條件（見 A.3） |
| `currencySettings` | `MarketCurrencySettings` | 見 A.5 |
| `priceInclusions` | `MarketPriceInclusions` | 稅/關稅內含策略（見 A.6） |
| `delivery` | `MarketDeliveryConfigurations!` | 運送設定 |
| `catalogs` / `catalogsCount` | connection / `Count` | 市場目錄（分頁） |
| `discounts` / `discountsCount` | connection | 市場折扣 |
| `webPresences` | connection | SEO/網域策略（分頁） |
| `metafield(s)` | — | 自訂欄位 |
| `assignedCustomization(customizationId)` | `Boolean!` | 該市場是否**自有**某項自訂（＝admin「自訂項目 vs 繼承的設定」分區的資料來源，[repo:29 §1.5(d)]） |

- **已棄用欄位**（新模型不得依賴）：`enabled`、`primary`、`regions`、`webPresence`（單數）、`priceList`（直掛）。⇒ 本尊已把「主市場」「地區集合」從 Market 本體移入 conditions／shop 設定；**Market 物件無 parent/child 欄位**，父子由 conditions 推導（[repo:29 §1.5]）。
- Queries：`market(id)`、`markets(query, type, sortKey=NAME, …)`（query 可搜 `id/market_condition_types/market_type/name/status/wildcard_company_location_with_country_code`）；已棄用：`marketByGeography(countryCode)`、`primaryMarket`。
- Mutations：`marketCreate(input)`、`marketUpdate(id, input)`、`marketDelete`；已棄用：`marketCurrencySettingsUpdate`、`marketRegionsCreate/Delete`、`marketWebPresenceCreate/Update/Delete`（併入 create/update input）。
- 權限：查 `read_markets`、寫 `read_markets`＋`write_markets`。

### A.3 MarketConditions（[dev] objects/MarketConditions＋enums/MarketConditionApplicationType，取證 2026-08-14）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `conditionTypes` | `[MarketConditionType!]!` | 該市場已定義哪幾型條件 |
| `regionsCondition` | `RegionsCondition` | `{ applicationLevel, regions(connection) }` |
| `companyLocationsCondition` | `CompanyLocationsCondition` | B2B 公司地點條件 |
| `locationsCondition` | `LocationsCondition` | POS 零售地點條件 |
| `channelsCondition` | `ChannelsCondition` | 銷售通路條件 |

- **`MarketConditionApplicationType` 值域窮舉：`ALL`｜`SPECIFIED`**——`ALL`＝「符合該型全部記錄」（wildcard，例：所有公司地點）；`SPECIFIED`＝逐一列舉。
- B2B 配對三式（[help] market-types）：全部地點（`ALL`）／指定地區內全部（新地點自動配對）／指定個別地點（`SPECIFIED`）——與 79 §2「B2B 公司地址配對【3】」一致。
- ⚠️ 官方未給每個 condition 的記錄數上限（wildcard 市場每店 100 見 [repo:29 §1.1]，本輪未再取證）。

### A.4 MarketWebPresence（[dev] objects/MarketWebPresence，取證 2026-08-14）

| 欄位 | 型別 | 硬規則 |
|---|---|---|
| `domain` | `Domain` | 與 `subfolderSuffix` **XOR**：「subfolderSuffix 非 null 時本欄必為 null」，反之亦然 |
| `subfolderSuffix` | `String` | 市場尾碼（官方例：`/en-us` 的 `us`） |
| `defaultLocale` | `ShopLocale!` | 該 presence 的預設語言 |
| `alternateLocales` | `[ShopLocale!]!` | 附加語言（决定 Storefront API 對該些國家可用的語言集） |
| `rootUrls` | `[MarketWebPresenceRootUrl!]!` | **每 locale 一條根 URL**；2024-04 起尾端不帶斜線 |
| `markets` | `MarketConnection` | **N:M**——一個 web presence 可服務多個 market（`market` 單數欄已棄用） |

- 網域三策略（[help] customizations/domains-and-languages）：subfolder `store.com/fr/`（推薦、零成本）／subdomain `fr.store.com`／頂級網域 `store.fr`。
- **語言解析優先序（3 層，值域窮舉）**：①顧客明確要求的語言 ②顧客目前使用中的語言 ③網域設定的預設語言。（79 §2 另有多父層決勝 4 階：同主機同語言＞同主機異語言＞異主機同語言＞字母序，`live` 級。）
- **停用市場的 URL 後果分岔**：「用 subfolder 的市場停用後，subfolder URL 停止運作」，需自行設手動 redirect；頂級網域/子網域自動導回主市場（後半句為 [repo:79 §5]，本輪 help 只正面取證 subfolder 一支）。
- hreflang 自動生成（[help] 同頁）。
- ⚠️ 每市場 web presence 數上限：官方頁無數字。

### A.5 MarketCurrencySettings（[dev]，取證 2026-08-14）

**值域窮舉（本物件僅 3 欄）**：

| 欄位 | 型別 | 語義 |
|---|---|---|
| `baseCurrency` | `CurrencySetting!` | `localCurrencies=false` 時顧客**必須**用的幣別 |
| `localCurrencies` | `Boolean!` | true＝按顧客地區轉當地幣；false＝全市場只見 base currency |
| `roundingEnabled` | `Boolean!` | 多幣價格是否套 rounding |

- 多國市場 `localCurrencies` **預設開啟**（[help] customizations/local-currencies）；單國市場自動設當地幣（[help] market-types）。
- 手動匯率：商家自行負責更新；轉換費**不加到顯示價**，改從 payout 扣（[help] local-currencies）。限制：「手動匯率不可用於 primary market」；Managed Markets 下適用範圍＝單國市場或關掉 localCurrencies 的多國市場（[help] exchange-rates）。
- 多幣**收款**前置：primary gateway 必須是 Shopify Payments 或 Adyen，其他閘道一律以商店預設幣別結帳（[help] local-currencies；79 §5 同）。

### A.6 MarketPriceInclusions（[dev]，取證 2026-08-14）

| 欄位 | 型別 |
|---|---|
| `adaptivePricingEnabled` | `Boolean!`（僅 Managed Markets 適用，否則忽略） |
| `inclusiveTaxPricingStrategy` | `InclusiveTaxPricingStrategy!` |
| `inclusiveDutiesPricingStrategy` | `InclusiveDutiesPricingStrategy!` |

- **`InclusiveTaxPricingStrategy` 值域窮舉：`ADD_TAXES_AT_CHECKOUT`｜`INCLUDES_TAXES_IN_PRICE`｜`INCLUDES_TAXES_IN_PRICE_BASED_ON_COUNTRY`**——與 admin「稅額顯示【3】：顯示為獨立項目／顯示為內含／動態稅額顯示」逐一對應（[help] customizations/duties-and-taxes＋79 §2）。
- ⚠️ `InclusiveDutiesPricingStrategy` 值域本輪未取到 enum 頁；admin 面值域【2】＝「顯示為獨立項目／價格已包含關稅（商家吸收）」（[help] 同頁）。

### A.7 Catalog／PriceList／Publication（[dev]，取證 2026-08-14）

**Catalog（interface；實作型：MarketCatalog／CompanyLocationCatalog／AppCatalog）**：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` / `title` | `ID!` / `String!` | |
| `status` | `CatalogStatus!` | **值域窮舉：`ACTIVE`｜`DRAFT`｜`ARCHIVED`** |
| `priceList` | `PriceList` | 0..1 |
| `publication` | `Publication` | 0..1；**無 publication 時可售性回落到 sales channel 決定** |
| `operations` | `[ResourceOperation!]!` | 最近批次作業 |

**PriceList**：`currency: CurrencyCode!`（固定價幣別）、`fixedPricesCount: Int!`、`name: String!`、`parent: PriceListParent`（`adjustment{type,value}`＋`settings{compareAtMode}`）、`prices`（connection）、`quantityRules`（connection，B2B 量購規則）、`catalog`。
- **`PriceListAdjustmentType` 值域窮舉：`PERCENTAGE_INCREASE`｜`PERCENTAGE_DECREASE`**；`value: Float!`。⚠️ 官方未載 value 上下限。
- **`PriceListCompareAtMode` 值域窮舉：`ADJUSTED`（compare-at 跟著百分比調整）｜`NULLIFY`（除非有固定價明設，compare-at 一律清成 null）**。
- **`PriceListPriceOriginType` 值域：`FIXED`｜`RELATIVE`**。
- `priceListFixedPricesAdd(priceListId, prices)`：**同 variant 重複送＝整筆取代**；已載錯誤碼 `PRICE_LIST_CURRENCY_MISMATCH`（幣別與 price list 不符）。⚠️ 每次 250 筆上限在今日頁面未見（[repo:29 §1.3] 有此值，降級為 repo 級）。

**Publication**：`autoPublish: Boolean!`（新品自動發佈）、`supportsFuturePublishing: Boolean!`（排程發佈）、`products`／`collections`／`includedProducts`（connections）、`productPublicationsV3`、`hasCollection(id)`、`catalog`。已棄用：`name`、`app`。
- 上限：`publicationUpdate` 每次最多 **50** 個項目；`includedProductsCount` 預設封頂 **10,000**。

### A.8 語言與翻譯模型（[dev]，取證 2026-08-14）

**ShopLocale**：`locale`（ISO 碼）、`name`、`primary: Boolean`、`published: Boolean`（顧客可否存取）、`marketWebPresences`。Mutations：`shopLocaleEnable(locale, marketWebPresenceIds?)`（**加入即為未發佈態**）、`shopLocaleUpdate`、`shopLocaleDisable`。
- 全店語言上限 **20**（Lite 除外，[help] markets/languages）。

**翻譯讀寫契約**：
- `translatableResources(resourceType, 分頁)` → `TranslatableResource { resourceId, translatableContent[{key, value, digest, locale}], translations(locale, marketId?) }`——**`digest` 是註冊翻譯的必要輸入**（樂觀鎖）。
- `translationsRegister(resourceId, translations[{locale, key, value, translatableContentDigest, marketId?}])`；`translationsRemove`。權限 `write_translations`。
- `marketLocalizationsRegister(resourceId, marketLocalizations[{key, value, marketId, marketLocalizableContentDigest}])`＝同語言跨市場的內容覆寫（Translate & Adapt 的「Adapt」）。
- **`TranslatableResourceType` 值域窮舉（latest 版 31 值）**：ARTICLE、ARTICLE_IMAGE、BLOG、COLLECTION、COLLECTION_IMAGE、DELIVERY_METHOD_DEFINITION、EMAIL_TEMPLATE、FILTER、LINK、MEDIA_IMAGE、MENU、METAFIELD、METAOBJECT、ONLINE_STORE_THEME、ONLINE_STORE_THEME_APP_EMBED、ONLINE_STORE_THEME_JSON_TEMPLATE、ONLINE_STORE_THEME_LOCALE_CONTENT、ONLINE_STORE_THEME_SECTION_GROUP、ONLINE_STORE_THEME_SETTINGS_CATEGORY、ONLINE_STORE_THEME_SETTINGS_DATA_SECTIONS、PACKING_SLIP_TEMPLATE、PAGE、PAYMENT_GATEWAY、PRODUCT、PRODUCT_OPTION、PRODUCT_OPTION_VALUE、SELLING_PLAN、SELLING_PLAN_GROUP、SHOP、SHOP_POLICY（另 PACKING_SLIP_TEMPLATE 的欄位＝body；PAYMENT_GATEWAY＝name/message/before_payment_instructions；**PRODUCT 含 handle**——本尊 handle 可翻譯，我方裁定不可，見 §F）。
- **`TranslationErrorCode` 值域窮舉（18 值）**：BLANK／FAILS_RESOURCE_VALIDATION／INVALID／INVALID_CODE／INVALID_FORMAT／INVALID_KEY_FOR_MODEL／INVALID_LOCALE_FOR_SHOP／INVALID_MARKET_LOCALIZABLE_CONTENT／INVALID_TRANSLATABLE_CONTENT（＝digest 與現行原文不符的形態）／INVALID_VALUE_FOR_HANDLE_TRANSLATION（handle 已被占用）／MARKET_CUSTOM_CONTENT_NOT_ALLOWED／MARKET_DOES_NOT_EXIST／MARKET_LOCALE_CREATION_FAILED／RESOURCE_NOT_FOUND／RESOURCE_NOT_MARKET_CUSTOMIZABLE／RESOURCE_NOT_TRANSLATABLE／TOO_MANY_KEYS_FOR_RESOURCE／INVALID_LOCALE_FOR_MARKET（已棄用）。

### A.9 Storefront 端 context（[dev] storefront queries/localization，取證 2026-08-14）

`localization` query → `Localization { availableCountries（各國含幣別/單位制/可用語言）, availableLanguages（隨當前國家變）, country, language, market（已棄用） }`；用 `@inContext(country, language)` 切換 context ⇒ 價格按該國幣別、內容按該語言回傳。⇒ 我方等價物＝SSR `RequestContext{market, locale, currency, jurisdiction}`（[repo:67 §A.3]）。

---

## B. 狀態機

### B.1 Market.status

**狀態全集：`DRAFT`、`ACTIVE`（＋終態「已刪除」）。無其他值；無孤兒態（兩態互通、皆可達終態）。**

| 轉移 | 觸發 | 前置條件 | 副作用 |
|---|---|---|---|
| ∅ → DRAFT/ACTIVE | `marketCreate`／admin 建立式（狀態選擇器可直選「有效」） | 名稱；conditions 至少一型；Advanced 超過 3 個 active 需加購（⚠️ 費額見 openQuestions） | webhook `MARKETS_CREATE` |
| DRAFT → ACTIVE | 啟用 | **結帳可用雙條件**：國家屬該市場 ＋ 位於有可用費率的運送區域（[help]／79 §5：先加國家→建 zone 設費率→才啟用） | 買家可完成購買；webhook `MARKETS_UPDATE` |
| ACTIVE → DRAFT | 停用 | 若 backup region 落在此市場 ⇒ 必須先改指其他 active market 的國家（[help] backup-region） | 設定**保留**；draft 可瀏覽不可購買；**subfolder URL 立即失效（需手動 redirect）**；頂級網域/子網域導回主市場（[repo:79 §5]）；webhook `MARKETS_UPDATE` |
| DRAFT/ACTIVE → 刪除 | `marketDelete`／「刪除市場」 | **主市場不可刪**；不可復原 | 子市場失去繼承來源（79 §1）；webhook `MARKETS_DELETE` |

主市場（primary）硬限制（[repo:79 §1]，`live`＋help）：恰含一國、由商店幣別決定、不可刪；「設為主要市場」僅 active 可設；設 subfolder 的市場、多地區市場不可設為主要。

### B.2 CatalogStatus

**狀態全集：`DRAFT`、`ACTIVE`、`ARCHIVED`。** 三態經 `catalogCreate/catalogUpdate` 互轉（官方未載不可逆邊；⚠️ ARCHIVED→ACTIVE 是否允許未明文，建模時按可逆處理並留開關）。只有 ACTIVE catalog 參與價格/可售性解析。

### B.3 ShopLocale（語言生命週期）

**狀態全集：未啟用 → enabled+unpublished → enabled+published；終態＝disabled（移除）。**

| 轉移 | 觸發 | 前置 | 副作用 |
|---|---|---|---|
| 未啟用 → unpublished | `shopLocaleEnable` | 總數 ≤20 | 譯文可先行匯入；webhook `LOCALES_CREATE` |
| unpublished → published | `shopLocaleUpdate(published:true)` | — | 顧客可存取；webhook `LOCALES_UPDATE` |
| published → unpublished | 反向 | 不可對 primary 做（primary 恆 published；⚠️ 官方頁未逐字載，屬結構必然） | **該語言 URL 停止服務**；譯文保留、再發佈免重譯（[help] languages） |
| → disabled | `shopLocaleDisable` | 非 primary | 自市場移除語言 ⇒ 該語言 slug 的所有 URL 404，官方建議設 redirect；webhook `LOCALES_DESTROY` |

另一維度：**語言 × 市場**的開放狀態（把已啟用語言加入某市場的 web presence／自市場移除）不改 ShopLocale 本體，只改 `marketWebPresences` 關聯。

### B.4 Translation（單條譯文 × digest）

**狀態全集：無譯文 → 已註冊(fresh) → 過期(outdated) →（重註冊）fresh；終態＝removed。無孤兒態。**

| 轉移 | 觸發 | 前置 | 副作用 |
|---|---|---|---|
| 無 → fresh | `translationsRegister` | 送入的 `translatableContentDigest` ＝ 當前原文 digest，否則 `INVALID_TRANSLATABLE_CONTENT` | — |
| fresh → outdated | **原文變更**（商家改 title 等） | — | Translate & Adapt 標「out of sync」；下次 auto-translate 會覆蓋**未經人工編輯**的機翻，人工譯文不動（[help] translate-adapt-app） |
| outdated → fresh | 重新註冊（帶新 digest） | 同上 | — |
| any → removed | `translationsRemove` | — | 讀取回落 fallback 鏈 |

### B.5 商品 × 市場可售性（publication 維度）

**狀態全集：included（發佈於該市場 catalog 的 publication）／excluded。** 預設**全商品全市場可售**（「所有商品預設以預設價在每個市場可售」）；排除方式＝catalog 編輯器「Exclude from catalog」或 CSV `Published=FALSE`。excluded 的對外行為：搜尋/列表不可見；**直連商品 URL → redirect 回首頁**（不是 404）——[help] publishing-products-with-markets，取證 2026-08-14。

---

## C. 業務規則與不變量

### C.1 價格解析公式（單一 variant 在市場 M、幣別 c 下的顯示價）

```
resolve_price(variant, M, c):
  1. 收集 applicable catalogs＝沿市場 lineage 累加的全部 ACTIVE catalogs（B.5 可售性先擋）
  2. 每個 catalog 產生候選價：
       有 FIXED price（該幣別）→ 用固定價（originType=FIXED）
       否則 → base_price × (1 ± adjustment%)（originType=RELATIVE），再走匯率鏈
  3. 多 catalog 衝突：更「specific」的 catalog 價勝出（B2B＞retail＞region）；
     同 specificity ⇒ 取最低價（[help] catalogs：「更特定者優先；無更特定者則顯示較低價」）
  4. RELATIVE 且需換幣：converted = round_currency( price × fx_rate × (1 + conversion_fee) )   # round_currency 定義見下
  5. roundingEnabled ⇒ 對步驟 4 結果套 rounding（C.4 charm rounding）；FIXED 價不換匯、不套 rounding
```

**`round_currency` 定義（換匯落位捨入）**——與 C.4 的 charm rounding 是**兩件事**：本步驟**無條件**執行（每次換匯必落到可收款的價位），C.4 只在 `roundingEnabled=true` 時再對本步驟結果疊檔位湊整：

- **管線位置（官方明文）**：「價格＝乘上匯率、加上轉換費、**再套該幣別的 rounding 規則（如適用）**」（[help] exchange-rates「Automatic exchange rate conversions」，取證 2026-08-14）。
- **捨入模式候選＝`ROUND_HALF_UP`（Q-11 未裁（2026-08-17 更正，PR #52 第 12 輪））**：官方唯一明文的模式句——「小數 50 以上進位、未滿 50 捨去」（[help] currency-formatting「Considerations」，取證 2026-08-14）；官方換算例 `$10.00 × 0.867519 × 1.015 = 8.8053…` → **€8.81** 與 half-up 一致（truncate 會得 €8.80，**排除**）。⚠️ 該明文句的脈絡是顯示格式（rounded currency formats），換算步驟本身的模式官方未逐字宣告（bankers rounding 與官方例值亦相容，但無任何官方文句支持），待實測（＝Q-11，未裁前 fixture 期望不得釘死）；實作候選 `HALF_UP`，模式落 `markets.currency_rounding_conversion_mode` 配置（鍵名同總綱 §8 草圖（2026-08-17 更正，PR #52 第 12 輪）：原 `currency_rounding_rules.conversion_mode` 為同旋鈕異拼；預設 `half_up`，不硬編）。
- **捨入量子（我方裁定；本尊未刊量子表 ⚠️）**：落到該幣別的**定價量子（pricing quantum）**——per-currency 配置、預設以 ISO 4217 exponent 為**底表**、可逐幣別覆蓋：JPY/KRW quantum＝1 主單位；**TWD 雖 ISO exponent=2 但收款按整元 ⇒ quantum＝1 主單位**（與 65 §H.1 T19 的 Stripe「整除 100」約束對齊）。結果一律回 `Money::Storage`（×100 cents 尺度：JPY 換出 ¥1,480 ⇒ 存 `148000`，且必整除 100）。**定價量子是第四個旋鈕**，與儲存尺度（恆 ×100）、顯示位數（58 §G.3 `currency_format.exponent`）、PSP 單位（65 §D pack 宣告）互相獨立、**禁止互相代用**（鐵律 3：display exponent 不得當換算基數，PSP 單位不得反推定價）。
- **零小數幣別的顯示端**：本尊 17 個幣別預設顯示格式 `amount_no_decimals`（BIF、CLP、DJF、GNF、ISK、JPY、KMF、KRW、PYG、RWF、UGX、UYI、VND、VUV、XAF、XOF、XPF，[help] currency-formatting，取證 2026-08-14）——只影響顯示、不影響本步驟；我方對應物＝jurisdiction pack 的顯示位數。
- **型別鏈**：`Money::Storage ×(decimal fx_rate) → 高精度 decimal 中間值（不落庫、不外流）→ round_currency → Money::Storage`；中間值禁止以 float 承載（鐵律 3）。F.3-2 的 JPY/TWD/KRW 矩陣即測本步驟。

- **固定價 > 百分比調整**（官方例：catalog 設 −10% 但手動定價 $2.00 ⇒ 顧客付 $2.00）。
- **固定價 > 手動匯率**（「International fixed prices override manual rates」，[help] exchange-rates）。
- compare-at：`ADJUSTED` 模式下 compare-at 跟著調整；`NULLIFY` 模式下除固定價明設者一律 null。
- 換算公式官方例：`($10.00 USD × 0.867519) × (1 + 0.015) = €8.81`。

### C.2 轉換費（conversion fee，[help] pricing/fees，取證 2026-08-14）

| 情境 | 費率 |
|---|---|
| Shopify Payments，商店在美國 | **1.5%** |
| Shopify Payments，商店在法國 | **2%** |
| Shopify Payments，其他所有地區 | **2%** |
| PayPal Wallet for Shopify Payments（US／FR） | **3%**（其他地區不可用） |

- 收取時點＝**capture 非本幣付款時**；**退款/chargeback 不再收一次，但已收的不退**。
- 手動匯率模式下轉換費不進顯示價、從 payout 扣。
- （[repo:29 §3.2] 舊記「1.5% 美/英/EEA」與今日取證不符 ⇒ 以本表為準。）

### C.3 匯率規則（[help] exchange-rates／refunds，取證 2026-08-14）

1. **轉換發生在交易當下**：capture、refund、chargeback 各用**當時**匯率——授權與請款相隔期間匯率可能移動（手動 capture 的風險官方明文）。
2. **退款反直覺規則**：顧客一律收**原 presentment 幣別原額**；商家端用**退款當下匯率**換算 ⇒ FX 損益全由商家承擔。官方例：€85 訂單當時＝$100，數週後退款需 $110，商家虧 $10。
3. 自動匯率：「價格隨市場匯率自動變動」；⚠️ 更新頻率與匯率來源官方未載（[repo:29 §3.2]「一日多次」無官方背書，降級 ⚠️）。
4. **Managed Markets 另一套**（[help] managed-markets）：匯率**穩定化**——通常每 **7 天**更新；波動 >**5%** 時可能更頻繁；每筆訂單匯率**保證 30 天**；30 天內退款沿用**訂單建立日匯率**（與 2. 的一般規則相反，兩條要分開實作，[repo:79 §4] 同）。
5. 手動匯率：不可用於 primary market；商家自行維護。

### C.4 Rounding（[help] pricing/rounding＋customizations/local-currencies，取證 2026-08-14）

- 目的＝匯率變動下保持價尾穩定；形式＝「Round up to the nearest {value}」，**每幣別預設值固定、不可自訂**（「無法把 rounding 規則自訂成與預設不同」）。
- 適用：商品價 ✔、運費 ✔；**gift card ✘**；稅 ⚠️ 未載。
- 只作用於**換算後**價格；固定價不套。
- 官方例：$14.27→$14.00、€9.73→€10.00。⚠️ 全幣別 target 對照表現行文檔未刊（[repo:29 §3.3] 的 EUR→x.95/JPY→¥100 清單無今日佐證，保留為 repo 級）。
- 前置：Shopify Payments 且所在國支援。

### C.5 市場命中與衝突不變量

1. **命中優先序（值域窮舉）**：`COMPANY_LOCATION` ＞ `LOCATION`（Retail Location）＞ `REGION` ＞ Store Default——此四層＝官方「Market Precedence Stack」**逐字全集**（[dev] apps/build/markets/new-markets/market-inheritance，取證 2026-08-14；[help] market-types 同向：「B2B 比 retail 特定；retail 比 country/region 特定」）。**A.2 五值 MarketType 中另兩值的席位如下，不是遺漏**：
   - **`CHANNEL` 刻意不在 stack 內**：官方 precedence stack 四層無 channel ⇒ 通路市場**不參與「買家屬於哪個市場」的裁決**，它是按「銷售通路 × 已命中地理市場」生效的**疊加維度**——「顧客在屬於某 channel market 的通路購物時，該市場的 catalog 與命中的 country/region market 的 catalog **合併**」；通路市場「預設繼承父 country/region market 的 catalog 與幣別」（[help] market-types，取證 2026-08-14）。⇒ **CHANNEL 與 REGION 同時命中＝不裁決、兩者並用**：catalog 取聯集；幣別/定價通路市場**自有者勝、未自有者繼承**地理市場（同型合併、異型更特定者覆寫的通則，[help] market-types「Submarkets across market types」）。
   - **`NONE`＝「不適用於任何訪客」**（[dev] enums/MarketType 原文語義：market does not apply to any visitor）⇒ 無 conditions 的市場，**恆不參與命中**，優先序無其席位是正確的。
   - ⚠️ **CHANNEL × LOCATION／CHANNEL × COMPANY_LOCATION 同時命中**（例：POS 通路本身又被納入某 channel market；B2B 買家經特定通路下單）：官方未明文，待實測。我方驗證器暫按「命中 LOCATION／COMPANY_LOCATION 時忽略 channel 疊加（stack 勝者已含通路語義）」建模並留開關。
   - **目錄層另有一條 catalog 解析優先序**（[dev] apps/build/markets/new-markets/catalogs，取證 2026-08-14）：company location **直連** catalog ＞ company-location market catalog（`SPECIFIED`＞`ALL`）＞ region market catalog（`SPECIFIED`＞`ALL`）＞ App Catalog（如 Online Store）；「只考慮最高 precedence 層的 catalogs，該層無 catalog 才落到次層」「同層平手取最低價」。⚠️ 此表未列 channel-market catalog 一層，與上句 help 的「合併」規則兩頁互不引用，關係待實測；我方按「channel catalog 併入其父地理市場所在層」建模並留開關。
2. **catalogs 跨市場累加**：「所有適用市場的 catalogs 合併，顧客可及全部」——同型父市場自訂**合併**、異型**覆寫**（[repo:79 §0.3]）。
3. 子地區（州/省）市場：**僅運送可自訂**，幣別/目錄/主題/網域一律繼承父市場（[help] market-types）。
4. 通路市場：預設繼承父市場設定，可各自定價/可售性/幣別；**命中語義＝疊加非裁決**（不進 precedence stack），詳見本節第 1 條 CHANNEL 分項。
5. ⚠️ **同一國家可否同時屬於兩個 active REGION 市場**：舊規則「不可重疊」（[repo:29 §9-1]），今日 help 明文「無 overlap 限制聲明」且巢狀（嚴格子集）合法——非子集式重疊的行為未載，入 openQuestions；我方驗證器暫维持「非子集重疊 reject」並留開關。
6. **backup region 不變量**：必指向某 active market 內的國家；建店時自動＝商店所在國；含它的市場要停用前必須先改指。命中失敗的訪客拿 backup region 的幣別/語言/主題，**可瀏覽不可結帳**。
7. **zone ≠ market 雙向 guard**：有 zone 不在 market ⇒ 不可販售；在 market 無 zone 費率 ⇒ 結帳運送段被擋（[repo:29 §5]，M1 已有規格）。

### C.6 上限值總表（落 `config/limits.yml`，出處逐條）

| 鍵 | 值 | 出處 |
|---|---|---|
| `markets.max_languages_per_shop` | 20 | [help] languages，2026-08-14 |
| `markets.auto_translate_max_languages` | 2 | [help] translate-adapt-app，2026-08-14 |
| `markets.included_active_markets` / `max` | 3 ／ 50（Advanced 超額每市場 $59/月；Plus 50） | ⚠️ 社群/第三方級，官方 help 未刊——**不得寫死，配置化** |
| `markets.b2b_active_catalogs_non_plus` | 3（Plus 無限） | [help] market-types，2026-08-14 |
| `markets.publication_update_batch` | 50 | [dev] Publication，2026-08-14 |
| `markets.publication_included_products_cap` | 10,000（預設） | [dev] Publication，2026-08-14 |
| `markets.price_list_fixed_prices_per_request` | 250 | [repo:29 §1.3]（今日頁未載）⚠️ |
| `markets.theme_locale_file_lines` / `chars` | 3,400 條/檔、1,000 字/條 | [repo:29 §2.3] |
| `markets.translation_keys_per_resource` | 有上限（`TOO_MANY_KEYS_FOR_RESOURCE`）⚠️ 數值未載 | [dev] TranslationErrorCode，2026-08-14 |

### C.7 併發要害

1. **翻譯 digest＝CAS**：register 必帶原文 digest，原文被並發修改 ⇒ `INVALID_TRANSLATABLE_CONTENT` reject——我方 `translations.source_digest` 沿用此語義；批次匯入必須逐列 CAS，不得整批最後寫。
2. **adjustment% 變更 vs 進行中結帳**：結帳鎖定進入時 presentment 價（[repo:29 §5]）；price list 改動只影響新 session。
3. **fixed price 覆寫競態**：`priceListFixedPricesAdd` 對同 variant 是「取代」語義 ⇒ 兩個並發批次後寫者勝，需 UI 顯示 `fixedPricesCount` 供對帳。
4. **匯率快照**：訂單建立、capture、refund 三個時點各存匯率（`exchange_rate_at_*`）；Managed-Markets 型（30 天保證）與一般型（交易當下）是**兩條策略**，pack 化。

---

## D. 關鍵流程

### D.1 建立並啟用市場

| 步 | 操作者 | 系統動作 | 失敗分支 |
|---|---|---|---|
| 1 | 商家 | `marketCreate`（name＋conditions；狀態可直選 ACTIVE） | 名稱>255／conditions 空 ⇒ userErrors；超過 plan 配額 ⇒ 擋（Advanced 提示加購） |
| 2 | 系統 | 依 conditions 推導 lineage、生成「繼承的設定」六項（幣別/目錄/折扣/主題/結帳/網域語言，全 NULL＝繼承）；發 `MARKETS_CREATE` | — |
| 3 | 商家 | 逐項 ⊕ 覆寫（幣別→`currencySettings`；目錄→掛 catalog；網域語言→web presence） | subfolder 市場設為主要 ⇒ reject |
| 4 | 商家 | 啟用前置：市場國家納入運送 zone 並有費率 | 無費率 ⇒ 結帳不可選該國（雙條件不成立） |
| 5 | 商家 | DRAFT→ACTIVE；發 `MARKETS_UPDATE` | backup region 衝突見 B.1 |

### D.2 前台市場/語言判定（每請求）

```
① URL 決定 web presence（獨立網域→該 presence；subfolder 前綴→該 presence；無前綴→primary）
② 由 presence.markets ∩ GeoIP 推薦 market；同時命中多型 ⇒ 按 C.5-1 precedence stack 裁決
   （COMPANY_LOCATION＞LOCATION＞REGION；CHANNEL/NONE 不參與裁決）；
   未命中任何 active market ⇒ backup region 體驗（可看不可買）
②′ 通路疊加：請求所屬 sales channel ∈ 某 ACTIVE CHANNEL 市場 ⇒ 該市場 catalog 與 ② 結果**聯集**、
   幣別/定價自有者覆寫、未自有者沿用 ②（C.5-1；⚠️ ② 勝者為 LOCATION/COMPANY_LOCATION 時暫不疊加）
③ 語言：顧客明確要求 > 目前使用 > presence.defaultLocale
④ 幣別：market.currencySettings（localCurrencies ? 顧客國當地幣 : baseCurrency）＋②′ 通路覆寫
⑤ 爬蟲一律不 redirect；自動跳轉為可選功能（[repo:29 §4]）
```

### D.3 收款與退款（多幣）

1. 結帳鎖定 presentment currency → capture 時以**當下匯率**換算入帳，收 1.5%/2% 轉換費 → 訂單雙記 `shopMoney`＋`presentmentMoney`。
2. 退款：顧客收原幣原額 → 商家端按**退款當下匯率**換算（Managed Markets 30 天內＝訂單日匯率）→ 不另收轉換費、原費不退 → FX 損益入報表。
3. 失敗分支：非 Shopify Payments/Adyen 閘道 ⇒ 全程商店預設幣別，無此流程。

### D.4 翻譯生產迴圈（Translate & Adapt 對齊）

1. `translatableResources(PRODUCT…)` 拉原文＋digest → 2. 人工／auto-translate（**上限 2 語言**；政策文件不可機翻）→ 3. `translationsRegister` 帶 digest（stale ⇒ reject、重拉）→ 4. 原文變更 ⇒ 譯文標 out-of-sync → 5. 下次 auto-translate 覆蓋**未經人工編輯**的機翻、人工譯文保留 → 6. CSV 匯出/匯入僅限次語言。
   Adapt（同語言跨市場）走 `marketLocalizationsRegister`（**我方 G13 裁定不做**，見 §F）。

### D.5 停用/刪除市場

停用：ACTIVE→DRAFT，設定保留；subfolder URL 失效（商家自設 redirect）、獨立網域/子網域自動回主市場；`MARKETS_UPDATE`。
刪除：不可復原；主市場禁刪；子市場失去繼承；`MARKETS_DELETE`。國家移出市場＝改 conditions（`MARKETS_UPDATE`），市場清空不自動刪（[repo:29 §6] 記「市場空了自動刪」⚠️ 與現行模型待複核）。

---

## E. 跨模組耦合

### E.1 Webhook topics（[dev] WebhookSubscriptionTopic，取證 2026-08-14，值域窮舉本領域相關者）

| Topic | 觸發 | scope |
|---|---|---|
| `MARKETS_CREATE` / `MARKETS_UPDATE` / `MARKETS_DELETE` | 市場建/改/刪 | `read_markets` |
| `MARKETS_BACKUP_REGION_UPDATE` | backup region 變更 | `read_markets` |
| `LOCALES_CREATE` / `LOCALES_UPDATE` / `LOCALES_DESTROY` | 語言啟用/發佈狀態變更/移除 | `read_locales` |
| `DOMAINS_CREATE` / `DOMAINS_UPDATE` / `DOMAINS_DESTROY` | 網域變更 | — |
| `PRODUCT_PUBLICATIONS_CREATE/UPDATE/DELETE`、`COLLECTION_PUBLICATIONS_*` | 發佈列變更 | `read_publications` |

⇒ 我方 outbox 事件名對映：`market.created/updated/deleted`、`market.backup_region_updated`、`shop_locale.created/updated/destroyed`、`publication.entry_changed`。

### E.2 依賴方向

| 對方模組 | 方向 | 耦合點 |
|---|---|---|
| Shipping（15 號） | 互相 | zone≠market 雙向 guard；啟用前置「有費率」；order routing 規則「Stay within the destination market」（規則鏈由上而下過濾：minimize split → stay in market → closest，[help] order-routing，取證 2026-08-14） |
| Checkout／Payments | Markets → | presentment currency 鎖定；local payment methods 按市場國家自動亮出（例：市場含 BE ⇒ Bancontact；含 BE+NL ⇒ Bancontact＋iDEAL）；多幣收款僅 Shopify Payments/Adyen |
| Tax／Duties | Markets → | `priceInclusions` 三值稅顯示＋兩值關稅收取；HS code＋origin 缺 ⇒ 關稅算不出；US 自 2025-08-29 無 de minimis |
| Theme／編輯器（24/27 號） | Markets → | contextual templates `templates/*.context.{market}.json`；佈景主題覆寫 4 型（79 §0.3） |
| SEO（30/62 號） | Markets → | hreflang 自動生成、rootUrls per locale、self-canonical |
| 分析（80 號） | Markets → | 訂單 MoneyBag 雙記＋三時點匯率快照 ⇒ FX 損益報表 |
| B2B（28 §13b） | ← Markets | `COMPANY_LOCATION` 市場、company_location 掛 catalog、3 active catalogs 非 Plus 上限 |
| 商品（63 號） | 互相 | publication 可售性；excluded 直連 ⇒ 首頁 redirect；新品 `autoPublish` |
| 翻譯後台（67 號） | ← Markets | digest CAS、outdated 迴圈、auto-translate 2 語言額度 |

---

## F. 落地對應

### F.1 對應倉庫文檔

| 本章節 | 落地處 |
|---|---|
| A（物件模型） | `docs/research/29 §1`（表結構已定）；API 面併 `docs/research/28 §13` |
| B（狀態機） | 29 §1.1/§6；79 §1；67 §B.3（ShopLocale） |
| C.1–C.4（價格/匯率/rounding） | `docs/specs/65`（單位邊界）＋29 §3；新增測試矩陣項見 F.3 |
| C.6（上限） | `config/limits.yml`（本表為出處） |
| D.2（判定鏈） | 29 §4＋67 §F；62 §I/J/K |
| E.1（事件） | outbox 契約（28 號） |

### F.2 本尊 vs 我方裁定（逐條）

| # | 本尊行為（今日取證） | 我方裁定 | 依據 |
|---|---|---|---|
| 1 | 金額全程 decimal（`MoneyV2.amount` 十進位字串）；價格公式含 Float 乘法 | **內部 integer cents（×100 不看幣別）**，序列化層才轉 MoneyV2；換算鏈每步走 `Money::*` 型別；PSP 單位逐 pack 宣告 | 鐵律 3／specs/65 |
| 2 | `PRODUCT.handle` 可翻譯（TranslatableResourceType 明列；有 `INVALID_VALUE_FOR_HANDLE_TRANSLATION` 錯誤碼） | **handle 不可翻譯、一律 ASCII**；語言維度由 URL 前綴承載 | 67 §D（2026-08-12 裁定） |
| 3 | `marketLocalizationsRegister`＝同語言 per-market 內容覆寫（Adapt） | **不做市場級內容覆寫**（`translations.market_id` 已刪；HK 英文＝CA 英文）；日後要做走主題區段覆寫 | 67 §0.4-7（裁定 10）＋79 §6（G13） |
| 4 | primary market 可用語言-only subfolder（`/fr`） | **URL 前綴恆為 `語言[-字體]-地區`**（`en-HK`），永不出現裸語言碼 | 67 §0.4-5（2026-08-13 裁定） |
| 5 | 稅/關稅顯示三值＋兩值是市場設定；憑證能力全球一套 | 顯示值照抄；**稅務憑證走 jurisdiction pack**（HK 無銷售稅；核心只發稅務事件） | 鐵律 11 |
| 6 | 轉換費 1.5%（US）/2%（其他）由 Shopify 收 | 我方費率是**平台商業參數**，不硬編；`limits.yml`＋billing 設定化 | 鐵律 6 |
| 7 | rounding 預設值固定不可自訂 | 我方做 `currency_rounding_rules` 表（可調），預設值先比照本尊已知值、缺值 ⚠️ 待補 | 29 §3.3 |
| 8 | plan 分層（逐市場主題/結帳自訂＝Advanced+；商業實體/Checkout Blocks＝Plus；3 active B2B catalogs 非 Plus） | 我方是否複刻方案閘門＝**79 §7 V4 未決**，實作先不設閘、留 feature flag | 79 §3 |
| 9 | excluded 商品直連 ⇒ **redirect 回首頁** | 29 §1.3 原記「前台隱藏」未載直連行為 ⇒ **採本尊行為**（redirect 首頁，非 404），入前台路由規格 | 本章 B.5（新事實） |
| 10 | 匯率：一般型交易當下、Managed 型 30 天保證 | 兩條策略並存、pack 化；訂單/退款各存匯率快照 | 29 §3.4＋79 §4 |
| 11 | 錯誤碼：`TranslationErrorCode` 等 typed enum、泛用 UserError 無 code | 我方**全 mutation 一律帶 code**（刻意加嚴） | 鐵律 4 |
| 12 | 市場級語言集掛 web presence（defaultLocale＋alternateLocales） | 同構：`market_web_presence_locales`＝**對買家的白名單**（strawberrynet 模型） | 67 §A.5／C.8 |

### F.3 開發驗收要點（可直接抄進驗收清單）

1. **價格解析順序測試**：FIXED > RELATIVE；FIXED 不換匯不 rounding；`NULLIFY` 下 compare-at 清空；多 catalog「更特定勝、同級取低」各一案。
2. **零小數幣別矩陣**（65 §H）：JPY/TWD/KRW 過整條換算鏈＋rounding——含 `round_currency` 落位斷言：模式＝配置值（候選 `HALF_UP`，Q-11 未裁；fixture 只釘官方例 €8.8053→€8.81——該例排除 truncate 但**不區分** half-up 與 banker's（非 half-tie）（2026-08-17 更正，PR #52 第 11 輪））、JPY/TWD 結果存值必整除 100（quantum＝1 主單位）、中間值無 float；新增「多段乘法＋末端 ±2.5% 進位」案（79 §4）。
3. **退款匯率雙時點測試**：一般型退款用當下匯率（商家 FX 損益成立）；Managed 型 30 天內用訂單日匯率——兩案數字對到官方例（€85/$100/$110）。
4. **digest CAS**：並發改原文後 register 舊 digest ⇒ 必 reject（對映 `INVALID_TRANSLATABLE_CONTENT`）；原文變更 ⇒ 全 locale 譯文批次 outdated。
5. **市場狀態機**：backup region 所在市場停用 ⇒ 先改指否則 reject；subfolder 市場停用 ⇒ 該前綴 404＋提示建 redirect；主市場禁刪。
6. **命中優先序**：同請求命中 B2B＋region ⇒ B2B 自訂生效且 catalogs 取聯集；命中 CHANNEL＋REGION ⇒ **不裁決**：catalog 聯集、通路自有幣別覆寫、未自有沿用 region；`NONE` 型市場任何請求不得命中。
7. **excluded 商品直連 ⇒ 302 回首頁**（非 404）；`autoPublish` 新品預設全市場可售。
8. **語言**：第 21 個語言 enable ⇒ reject；移除語言 ⇒ 該語言 URL 404＋redirect 建議；auto-translate 第 3 個語言 ⇒ reject。
9. **zone≠market 雙向 guard**（15-F2.2）兩邊差集數字可見。
10. **事件**：B.1–B.5 每條轉移發對應 outbox 事件（E.1 對映表），消費端冪等。

---

## G. 來源

全部取證 2026-08-14（另註明者除外）：

- https://shopify.dev/docs/api/admin-graphql/latest/objects/Market
- https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketWebPresence
- https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketCurrencySettings
- https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketConditions
- https://shopify.dev/docs/api/admin-graphql/latest/objects/RegionsCondition
- https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketPriceInclusions
- https://shopify.dev/docs/api/admin-graphql/latest/enums/MarketType
- https://shopify.dev/docs/api/admin-graphql/latest/enums/MarketConditionApplicationType
- https://shopify.dev/docs/api/admin-graphql/latest/enums/InclusiveTaxPricingStrategy
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CatalogStatus
- https://shopify.dev/docs/api/admin-graphql/latest/enums/PriceListAdjustmentType
- https://shopify.dev/docs/api/admin-graphql/latest/enums/PriceListCompareAtMode
- https://shopify.dev/docs/api/admin-graphql/latest/enums/TranslatableResourceType
- https://shopify.dev/docs/api/admin-graphql/latest/enums/TranslationErrorCode
- https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic
- https://shopify.dev/docs/api/admin-graphql/latest/interfaces/Catalog
- https://shopify.dev/docs/api/admin-graphql/latest/objects/PriceList
- https://shopify.dev/docs/api/admin-graphql/latest/objects/Publication
- https://shopify.dev/docs/api/admin-graphql/latest/objects/ShopLocale
- https://shopify.dev/docs/api/admin-graphql/latest/input-objects/PriceListAdjustmentInput
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/marketCreate
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/priceListFixedPricesAdd
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/translationsRegister
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/marketLocalizationsRegister
- https://shopify.dev/docs/api/admin-graphql/latest/queries/translatableResources
- https://shopify.dev/docs/api/storefront/latest/queries/localization
- https://shopify.dev/docs/apps/build/markets/new-markets/market-inheritance （Market Precedence Stack 四層逐字＝C.5-1）
- https://shopify.dev/docs/apps/build/markets/new-markets/catalogs （catalog 解析層級＋「最高層優先、平手取低價」）
- https://help.shopify.com/en/manual/markets （overview）
- https://help.shopify.com/en/manual/markets/getting-started/market-types
- https://help.shopify.com/en/manual/markets/customizations/catalogs
- https://help.shopify.com/en/manual/markets/customizations/local-currencies
- https://help.shopify.com/en/manual/markets/customizations/domains-and-languages
- https://help.shopify.com/en/manual/markets/customizations/duties-and-taxes
- https://help.shopify.com/en/manual/markets/languages
- https://help.shopify.com/en/manual/markets/backup-region
- https://help.shopify.com/en/manual/markets/publishing-products-with-markets
- https://help.shopify.com/en/manual/international/pricing/exchange-rates
- https://help.shopify.com/en/manual/international/pricing/currency-formatting （half-up 明文＋17 幣別 amount_no_decimals 清單＝C.1 round_currency）
- https://help.shopify.com/en/manual/international/pricing/rounding
- https://help.shopify.com/en/manual/international/pricing/refunds
- https://help.shopify.com/en/manual/international/pricing/fees
- https://help.shopify.com/en/manual/international/duties-and-import-taxes
- https://help.shopify.com/en/manual/international/translate-adapt-app
- https://help.shopify.com/en/manual/fulfillment/setup/order-routing/understanding-order-routing
- https://help.shopify.com/en/manual/payments/shopify-payments/local-payment-methods （經 WebSearch 摘要取證）
- https://help.shopify.com/en/manual/international/managed-markets/shopify-payments （經 WebSearch 摘要取證：7 天/5%/30 天保證）
- ⚠️ 社群級（不得據以寫死）：https://community.shopify.dev/t/included-markets-per-plan/15121 （3 included/50 max/$59）
- 倉庫底座：`docs/research/29-markets-i18n.md`（查證 2026-08-11）、`docs/research/79-admin-markets.md`（實測 2026-08-13）、`docs/specs/67-multilingual.md`（裁定 2026-08-12/13）
