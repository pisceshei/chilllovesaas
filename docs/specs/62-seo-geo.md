# 62 — SEO ＋ GEO 深度方案（搜尋最佳化・生成式引擎・多地區）

> **緣由**：使用者 2026-08-12 裁定逐字：「**還有一項很重要的就是 seo 方面還有 geo 方面。你深度去分析 shopify 的文檔。在這一方面進行深度分析和研究，然後寫一個詳細的方案。**」
>
> **GEO 在本檔是兩個完全不同的東西，兩個都做，不可互相取代**：
> - **GEO-G（Generative Engine Optimization，生成式引擎）**＝ 讓 ChatGPT／Gemini／Copilot／Perplexity／Claude 這類生成式介面能檢索、引用、甚至代買我方租戶的商品。見 §H。
> - **GEO-R（Geographic／Region，多地區）**＝ hreflang、多市場網域、地區重導、幣別一致性。與 29 號 Markets 與 P0-02 的父子繼承直接相關。見 §I–§L。
> 兩者在同一份文件是**刻意**的：它們有一個共同的資料底座（同一個 `PriceView` 解析器、同一份 market×locale 矩陣），拆成兩份保證會各自長出一套價格來源——那正是鐵律 7 要防的事故。
>
> **本檔與 30 號的關係**：`docs/research/30-seo-merchant-feeds.md`（查證日 2026-08-11）是**搜尋引擎與 feed 的官方要求全景**，本檔**不重抄**它。本檔寫的是：①30 號沒有的三塊（GEO-G 全部、hreflang 完整矩陣與繼承對應、標題描述樣板化）②30 號有結論但**沒有落到我方資料模型／里程碑／limits 鍵**的部分 ③本輪查證後**與 30 號不一致或需補強**之處（逐條標 `<!-- 依 … 修正 -->`）。讀本檔前請先讀 30 號 §1–§5。
>
> **權威順序**（沿用 52／54／55／56／57／58）：官方開發文檔 ＞ 官方商家文檔 ＞ 實測 ＞ 我方既有規格。**我方與官方衝突時一律改我方。** 但本檔的權威來源分三支，不可混用（見 §0.3）：搜尋引擎側＝Google/Microsoft 官方；平台側＝shopify.dev / help.shopify.com；代理商務協定側＝ucp.dev / developers.openai.com。**Shopify 文檔不能當成 Google 規則的來源**，反之亦然。
>
> **法律紅線（鐵律 9）**：本檔不轉貼 Shopify 文案。凡描述 Shopify 行為者，一律只寫**機制與契約**並在 §附錄 B 標出處 URL。Google／OpenAI／ucp.dev 的**規範性短句**在必要處以引號標示並註明出處，僅用於避免規格失真。
>
> **金額鐵律（鐵律 3／7／10 ＋ 2026-08-12 裁定二）**：JSON-LD 的 `Offer.price`、可見價格、feed、代理端點回應**必須是同一次解析的同一個數**。顯示位數恆兩位（`limits.currency_display.force_minor_unit_digits: 2`），儲存恆 integer cents ×100。§A.4 與 §L 是本檔最容易做錯的兩節。
>
> **法域鐵律（鐵律 11）**：基準法域＝香港，可插拔。本檔**不得**出現寫死的市場清單、語言清單、國別分支。hreflang 矩陣、網域策略、幣別格式一律由 market／jurisdiction 設定推導。任何 `if country == 'TW'`（或 `'HK'`）都是本檔要防的東西。
>
> **盤點與查證日**：2026-08-12。**待查證編號自 V-110 起**（V-37～V-49＝58 號物流；V-50 已結案；**V-50～V-70 為同日 61 號、V-90～V-98 為同日 63 號所佔**——本檔原擬用的 V-60 起與 61 號撞號，已整批下移到 V-110，中間刻意留白給其他 agent）。

---

## 0. 決議、原則與出處等級

### 0.1 使用者裁定拆成可驗收的四條

| # | 裁定要點 | 本檔怎麼回應 | 驗收在哪 |
|---|---|---|---|
| a | 「SEO 方面」 | §A 結構化資料／§B canonical／§C sitemap／§D robots／§E 標題描述／§F alt·h1·handle·301／§G CWV | §O SEO-1～SEO-14 |
| b | 「GEO 方面」之一：生成式引擎 | §H（含 `llms.txt` 的結論與依據、agents.md／UCP／MCP、Catalog 等價物、FAQ 的死與生、與 SEO 的衝突表） | §O GEN-1～GEN-8 |
| c | 「GEO 方面」之二：地理／多地區 | §I hreflang 矩陣＋P0-02 繼承對應／§J 網域策略／§K 地區重導／§L 幣別與 `priceCurrency` | §O REG-1～REG-10 |
| d | 「深度分析 shopify 的文檔」 | 本輪查證 20 個官方頁（§附錄 B），其中 **7 條推翻或補強了我方既有結論**（§0.4） | §附錄 B |

### 0.2 六條設計原則

1. **價格只有一個來源。** 可見價格、`Offer.price`、feed、admin SEO 預覽卡、代理端點回應，五個消費者呼叫**同一個** `resolve_price_view()`。這不是風格問題：Google Merchant Center 以頁面 JSON-LD 即時校正 feed（30 §6.2），兩者不一致＝misrepresentation ⇒ 拒登／停權。§A.3。
2. **SEO 面是平台責任，不是主題責任。** canonical、hreflang、sitemap、robots、Organization/Breadcrumb/Product JSON-LD 由平台注入且**主題不可關閉**；主題只能**擴充**。理由：多租戶 SaaS 的一個壞主題會拖垮該租戶的索引，而租戶不會知道是主題的錯。
3. **未宣告 ≠ 支援。**（承 56 §A.3、58 §0.2 原則 2）代理協定能力（UCP capabilities、MCP tools、直接結帳）一律**顯式宣告**。不支援就寫 `supported: false, reason: …`，**禁止**因為端點存在就讓代理以為能下單。宣告了做不到，代理會在買家面前失敗，那是比 404 貴得多的事故。
4. **凡是進 hreflang 或 sitemap 的 URL，必須對任何客戶端直接回 200。** 不重導、不 401、不 noindex、self-canonical。這一條把 §I、§J、§K、§C 綁成一個可測的不變量（§O REG-6）。
5. **AI 檢索的可信度來自資料完整度，不是來自新檔案。** Google 官方明說 AI 功能不需要新的機器可讀檔案或特殊 schema（§H.1 事實 2）。所以我方在 GEO-G 的投資順序是：**資料完整度 ＞ 代理協定端點 ＞ 文字檔**，不是反過來。
6. **誠實記錄衝突。** SEO 與 GEO-G 有真實的取捨（§H.6），多地區與索引也有（§K）。本檔**不寫「兩邊都好」**。

### 0.3 出處等級（在既有 dev／help／live／ours 之外新增四級）

| 等級 | 意義 | 可否據以寫死實作 |
|---|---|---|
| `google` | `developers.google.com/search` 官方文檔 | ✅ 可 |
| `openai` | `developers.openai.com` 官方文檔 | ✅ 可 |
| `ucp` | `ucp.dev` 規格頁／`shopify.engineering` 工程文 | ✅ 可（但我方是否實作是另一回事，見 §H.3） |
| `press` | 業界二手來源（Search Engine Journal 等）轉述官方人員發言 | ⚠️ 僅供佐證，**一律登記 V 編號** |
| `alt`<br><!-- 2026-08-13 新增。理由見右欄。 --> | **非 Shopify 的第三方商店實測**（本輪＝strawberrynet.com）。它既不是規範來源（不是 Google／不是 Shopify），也不是我方實測 | ⚠️ **僅供「這個形態在真實世界跑得起來」的存在性佐證**，🔴 **不得據以寫死實作、不得當成 SEO 規則**。一律登記 V 編號 |

> 沿用 58 §0.3 的 `-unobtainable` 慣例：**本輪確實取不到者一律寫「未能取得」並登記 V 編號，不得推測補寫。**
>
> 🔴 **`alt` 為什麼要單獨一級而不是併進 `press`**：`press` 是「二手轉述官方」，錯的方式是**轉述失真**；`alt` 是「另一家公司的產品決策」，錯的方式是**他家的取捨不是我家的取捨**（他們可能有我們沒有的約束，也可能單純做錯了）。兩者的誤用形態不同，處置也不同——`press` 要去找一手，`alt` **找到一手也沒用**，因為它從來就不是規範。本輪 §I.2 的 strawberrynet 觀察就是這個等級：它證明「恆帶地區的 URL 前綴」是可運作的形態，**它不證明那是對的**（該站同時被觀察到把 `/zh-TW/` 送到 `en-US`，那正是我方 §0.2 原則 4 要禁的事，見 §I.2-2）。

### 0.4 本輪查證推翻／補強的既有結論（7 條，逐條可追溯）

| # | 既有寫法 | 本輪查證 | 處置 |
|---|---|---|---|
| 1 | 26:523 把 `llms.txt`／`agents.md` 列為 T2 模板類型（只記存在） | shopify.dev changelog **2026-05-28**：`/llms.txt` 與 `/llms-full.txt` **預設就指向 `agents.md` 的內容**；三者各有 `.liquid` 模板可覆寫，fallback 鏈為「專屬模板 → `agents.md` 模板 → 平台預設」 | §H.3 補完整機制；T2 保持不變（不急做），但**路由與 fallback 鏈要一次做對** |
| 2 | 30 §9-4「JSON-LD 注入分工」未涵蓋代理協定 | `agents.md.liquid` 的 Liquid context **只有兩個物件**（`request`、`agents`），且 `agents` 內含 `ucp_discovery_url`／`mcp_endpoint_url`／`ucp_versions`／`sitemap_url`／`currency`／`store_name`／`store_url`；`shop`／`collections` 等全域物件**不可用**（避免快取問題）；該檔**不可在地化**、走裸主網域無 locale 前綴 | §H.3、§H.6 衝突 5（多市場只有一個代理幣別） |
| 3 | 29 §4「hreflang 對每個 market×locale 輸出」未定義**碼的粒度規則** | help.shopify.com/markets/seo ＋ shopify.dev/themes/seo/hreflang：**單國市場 → 區域限定碼（`fr-ca`）；多國市場 → 語言碼（`fr`）**；`x-default` 指主網域；自動 hreflang 可在後台關閉；官方警告自訂與自動並存會產生重複／衝突標註 | §I.2 寫成演算法；§I.3 加**碼衝突解析**（官方未載明 ⇒ V-111） |
| 4 | 30 §2.3「單頁 PDP：canonical URL 不預選變體」 | google 官方 product-variants 頁確認：單頁站**整個 ProductGroup 只能有一個 canonical**，通常是不預選變體的基底 URL；多頁站則每頁自帶完整 self-contained 標記 | ~~§B.2 補「兩種模式二選一，不可混用」＋開關設計~~ ⇒ 🔴 **已於 2026-08-12 兩度修正**：68 §B-6 **廢除模式 B**（開關取消）；**69 §B-6 再修正廢除的理由**——Google **明文建議**每個變體有可識別的獨立 URL，single-page／multi-page **兩種都合規且不表偏好**，Shopify **兩種都做了**（後者鎖 Plus）⇒ 我方廢的是「同一 product 下 variant 各掛 URL」這個**資料模型**，**不是「變體可索引」這個目標**（該目標我方 single-page 模式已達成）。詳見 §B.2 |
| 5 | 我方無 hreflang 語言碼的 script subtag 規則（HK 基準法域是繁中，這是硬缺口） | google 官方 localized-versions 頁：**ISO 639-1 ＋ 可選 ISO 15924 script ＋ 可選 ISO 3166-1 alpha-2**，並明確舉例 `zh-Hant` 為合法值 | §I.4 定案：HK 預設 `zh-Hant-HK`，繁中不得寫成 `zh-TW` 借用 |
| 6 | 30 §2.4「FAQPage 已死（2026-05 完全停顯）——不投資」 | 本輪覆核一致（多家二手來源指向 2026-05 移除）。**但**：Shopify 另有 Knowledge Base（商家 FAQ）供 AI 平台取用，且 Storefront MCP 有 `search_shop_policies_and_faqs` 工具 | §H.5：**FAQ 內容要做，FAQPage JSON-LD 不做**——通路換了，不是需求沒了 |
| 7 | 30 §9-2 robots 預設規則未涵蓋 AI 爬蟲 | OpenAI 官方 bots 文檔：`OAI-SearchBot`（ChatGPT 搜尋收錄，**封鎖＝不出現在 ChatGPT 搜尋答案**）／`GPTBot`（訓練）／`OAI-AdsBot`／`ChatGPT-User`（**使用者觸發，robots.txt 規則可能不適用**）；google 官方：`Google-Extended` **不影響 Google 搜尋收錄與排名** | §D.3 AI 爬蟲策略表＋預設值裁定請求 |
| 🔴 **8**<br>（**2026-08-13 新增，不是本輪查證，是使用者裁定**） | **§I.2「單國市場 → `fr-ca`；多國市場 → `fr`」**（依 §0.4-3 的 `help`／`dev` 查證所寫，忠實對齊 Shopify） | **沒有新查證。** 使用者 2026-08-13 裁定：「不同地區如果同樣有英文，那就在 url 加入識別……避免被 google 等搜索引擎誤判為重複頁面」 | 🔴 **裁定覆蓋 Shopify 行為**：§I.2 改為**恆帶 ISO 3166-1 地區**、禁裸語言碼；`hreflang_code()` 改回傳 Set；明知偏離登記於 **§I.2-1**（比照 §F.3-1 的形態）；動機與其實際 SEO 效果的誠實拆解在 **§I.2-2**（🔴 該節明寫「加地區碼就不會被判重複」**不成立**）。連帶：§I.1 演算法、§I.3(c) `dedupe_codes`、§I.4 值域、§J.1 語言-only 子資料夾、67 §F.1 URL 前綴 |

> 🔴 **第 8 列與第 1–7 列的性質不同，讀的時候不要混**：1–7 是「我方寫錯／不完整，查證後改我方」；**8 是「我方寫對了（對齊本尊），但產品決策換了判準」**。前者若日後發現查錯要改回；**後者只有裁定改變才改回**，任何以「Shopify 不是這樣做」為由的回退一律駁回（§I.2-1 已明列依據）。

---

# SEO

## A. 結構化資料（JSON-LD）

### A.1 三層注入分工（平台層不可關）

```
第 1 層 平台注入（不可關閉，主題無法移除）
  Organization（全站，含 hasMerchantReturnPolicy／hasShippingService 宣告點）
  BreadcrumbList（依 request.page_type 生成）
  Product ＋ Offer ／ ProductGroup ＋ hasVariant（PDP）
  ItemList（collection／search 結果頁）
  WebSite（僅 name/url，**不含 SearchAction**——30 §2.4 已落日）
第 2 層 主題擴充（`structured_data` filter 等價物；只能新增節點，不能改寫第 1 層）
第 3 層 商家資料（metafield：評論、GTIN、規格、尺寸表）——經欄位進入第 1 層，不繞過
```

**為什麼平台層不可關**：對照 30 §9-4 的原始決策，本檔補一條理由——多租戶下「主題把 JSON-LD 註解掉」是無聲事故，商家在 GSC 看到富摘要消失時已經掉了兩週流量。實作上第 1 層由 layout 渲染管線直接 append 到 `</head>` 前，**不經主題模板**；主題的 `structured_data` 輸出走獨立 `<script type="application/ld+json">` 節點，兩者不合併。

### A.2 型別矩陣

| 型別 | 出現頁 | 必填（我方硬要求） | 我方資料來源 | 注意 |
|---|---|---|---|---|
| `Organization` | 全站 layout | `name`、`url`、`logo`(≥112×112) | `shop.brand`（26:109） | 退貨／運費政策在此宣告一次，PDP 不重複（30 §2.2） |
| `BreadcrumbList` | 除首頁外全部 | ≥2 `ListItem`、`position` 自 1 | 路由層生成 | **`name` 用在地化標籤、`item` 用真實 URL**——60 §6 實測系列頁 SEO 卡顯示 `… › 商品系列 › 產品`，該中文標籤來自 breadcrumb，不是 URL 段（URL 段 `collections` 不可譯，29 §2.1） |
| `Product` | PDP（無變體／變體為單一隱含變體） | `name`、`image`、`offers` | 60 §1：商品恆有 ≥1 變體 | 圖片 ≥50,000px²（30 §2.1） |
| `ProductGroup` | PDP（多變體） | `name`、`productGroupID`、`variesBy`、`hasVariant[]` | `product.id` → `productGroupID` | `variesBy` 僅取 Google 支援的六個面向；我方 option name 需映射表，映不到就**不輸出該面向**（不猜） |
| `Offer` | 每變體一個 | `price`、`priceCurrency` | `resolve_price_view()`（§A.3） | 格式規則見 §A.4；`availability` 見 §A.5 |
| `AggregateRating` | PDP（有評論才輸出） | `ratingValue` ＋ `ratingCount`\|`reviewCount` | 評論 metafield（30 §9-4） | **筆數為 0 一律不輸出整個節點**，不得輸出 `ratingCount: 0`；禁自評（30 §2.4） |
| `ItemList` | collection／search | `itemListElement[].position` ＋ `url` | 該頁**當前分頁**的商品 | 只列本頁項目，不列全系列；與 §B.3 分頁 self-canonical 一致 |

**不做清單（連同理由，避免日後有人「補上」）**：`FAQPage`（Google 2026-05 停顯，§H.5 另有出路）、`WebSite`+`SearchAction`（2024-11 落日）、`Review` 自家評分、`AggregateOffer`（merchant listing 要求 `Offer`，30 §2）。

### A.3 數字同源（鐵律 7 在 SEO 面的具體形態）— **本檔最重要的一節**

```ruby
# 唯一的價格入口。五個消費者一律呼叫它，且傳同一個 context。
PriceView = Struct.new(
  :amount_cents,      # integer，presentment 幣別的最小單位 ×100（鐵律 3；58 §G.3 storage_multiplier: 100）
  :currency,          # ISO 4217，= presentment currency（29 §3.1），**不是** shop currency
  :compare_at_cents,  # nil 或 integer
  :availability,      # §A.5 的枚舉
  :valid_until,       # nil（無檔期）或 Date
  :tax_included,      # 依市場 priceInclusions（29 §1.5）
  :resolved_at
)

def resolve_price_view(variant:, context:) # context = RequestContext{market, locale, currency, customer}
  # 解析順序照 29 §1.4：fixed price → base×(1±adj%)×匯率×(1+轉換費率) → rounding
  # fixed price 不換算不湊整（29 §9-6）；gift card 不湊整
end
```

**五個必須同源的消費者**：

| # | 消費者 | 位置 | 若不同源會怎樣 |
|---|---|---|---|
| 1 | 前台可見價格 | `money` filter 輸出 | — |
| 2 | `Offer.price` / `priceCurrency` | 平台 JSON-LD | Google 判結構化資料與頁面不符 → 富摘要消失 |
| 3 | Merchant feed 行 | GMC/Merchant API（30 §9-8） | **misrepresentation → 拒登／停權**（30 §6.2） |
| 4 | Admin SEO 預覽卡的價格列 | 59 §3「搜尋引擎產品資訊」實測含 `HK$1,100.00 HKD`；60 §6 系列頁同款卡 | 商家看到的預覽是假的（49 號 A-8 已列缺口） |
| 5 | 代理／MCP catalog 回應 | §H.4 | 代理報一個價、結帳另一個價 → 代理側直接判定商家不可信 |

**驗收（不可用人工檢查）**：`SeoPriceParityTest` — 對每個 (變體 × active market × locale) 抽樣渲染 PDP，從**渲染後的 HTML** 解析 JSON-LD、從 DOM 的 `data-price-cents` 取可見價、呼叫 feed 生成器取同一列、呼叫 catalog 端點取同一變體，四者的 `amount_cents` 與 `currency` **必須全等**。任何一組不等 ⇒ 紅燈。這條測試在 M2 就要有，因為 feed（M5）上線時再補會來不及。

> ⚠️ **禁止的實作**：在 JSON-LD 模板裡寫 `{{ variant.price | money_without_currency }}` 再自行 `replace(',', '')`。那是第二個價格來源（格式化後再逆向解析），也是本節要防的東西。JSON-LD 一律由**序列化層**從 `PriceView.amount_cents` 直接產生。

### A.4 `Offer.price` 的格式 vs 裁定二（兩位小數）— 真衝突與定案

**三個事實**：

1. **Google**（`google`，merchant listing 頁）：`price` 必須是數值，**不含幣別符號、不含千分位逗號**（例 `39.99`）；`priceCurrency` 為三碼 ISO 4217。
2. **我方裁定二**（`limits.currency_display`）：**所有國家一律顯示兩位小數**，`iso4217_zero_decimal_overridden: [JPY, TWD]`，`storage_scale_unchanged: true`（儲存恆 ×100）。
3. **58 §G.3 的教訓**：`jurisdictions.<code>.currency_format.exponent` 已改為「**顯示位數**」，**不再是 ISO minor unit**。拿它當換算基數，在 zero-decimal 幣別上會產生 100 倍誤差。

**定案（三條，違反即 bug）**：

```
(1) JSON-LD price = amount_cents / 100，一律，**不看幣別**。
    序列化為固定兩位小數的十進位字串，無符號、無千分位、小數點用 "."。
    HK$938.00 → "938.00"；JPY 1000（儲存 100000）→ "1000.00"。
(2) priceCurrency = PriceView.currency（presentment），**不是** shop.currency，
    也不是 jurisdiction 的預設幣別。多市場下這是最常見的錯。
(3) 可見價格的「符號與千分位」由 market locale 決定（鐵律 10），
    JSON-LD **不套用任何 locale 格式化**。兩者共用 amount_cents，不共用格式器。
```

**衝突點與誠實說明**：`"1000.00"` 與 `1000` 在 JSON 數值語義上相等，Google 側不構成問題（規則只禁符號與逗號，未禁尾隨零）。**真正未查證的是 feed 側**：GMC 的 `price` 是「數值＋空格＋幣別」字串（30 §6.1，例 `15.00 USD`），zero-decimal 幣別是否接受 `1000.00 JPY`、以及富摘要驗證器是否對此告警，**本輪未取得官方明文** ⇒ **V-115**。在 V-115 結案前，feed 生成器對 zero-decimal 幣別的市場**維持兩位小數輸出**（與頁面同源優先於猜測 feed 偏好），並在 GMC 診斷儀表板（30 §9-13）加一條專門的告警規則。

### A.5 `availability` 對映（接 60 §4 的庫存五態）

60 §4 取得官方定義的恆等式：`現有庫存 = 不可用 + 已佔用 + 可用`，`在途` 不在恆等式內。對映表：

| 條件（依序判定，先命中先用） | `schema.org` 值 | 說明 |
|---|---|---|
| 商品／變體未發佈到本市場 catalog | **不輸出 Offer，且該頁 404/410** | 29 §1.3：未發佈＝前台隱藏。輸出 Offer 但頁面買不到＝soft-404（30 §1.1 嚴禁） |
| 購買選項＝預購且未到貨 | `PreOrder` | 需同時給 `availabilityStarts`／GMC `availability_date` |
| `可用 > 0` | `InStock` | **只看「可用」**，不看「現有庫存」——把已佔用算進去＝超賣訊號 |
| `可用 ≤ 0` 且允許無庫存繼續銷售 | `BackOrder` | 59 §2 pill「無庫存時繼續銷售」即此開關 |
| `可用 ≤ 0` 且不允許 | `OutOfStock` | |
| 商品已封存／下架 | 不輸出（頁面 410） | 30 §9-5 的 410 紀律 |

`itemCondition` 預設 `NewCondition`，由商品欄位覆寫（我方需新增欄位，見 §M）。

### A.6 `priceValidUntil` 的處置（本檔新增決策）

Google：`priceValidUntil` 為過去日期時**可能不顯示**。多市場自動匯率一日多次更新（29 §3.2），意味著「價格有效期」在浮動匯率市場根本無法誠實宣告。

**決策**：**只有存在真實結束時點時才輸出**——促銷檔期結束時間、price list 排程結束時間。無檔期時**整個屬性省略**（它是建議屬性，不是必填）。**禁止**「每次渲染都寫 now+90 天」的做法：那是可被抓包的假宣告，且與 §A.3 的同源原則精神相違。

---

## B. Canonical 策略

### B.1 URL 變形矩陣（八種，全部要有明確歸屬）

| # | 變形 | 範例 | canonical 指向 | 額外處置 |
|---|---|---|---|---|
| 1 | 基底 PDP | `/products/{handle}` | 自身 | — |
| 2 | 變體參數 | `/products/{handle}?variant=123` | **`/products/{handle}`**（去參數） | §B.2 唯一模式<!-- 依 68 §B-6 修正，原文：「§B.2 的模式 A；模式 B 另有規則」——模式 B 已廢除 -->；✅ 與 Shopify 實測輸出一致（V-110 結案） |
| 3 | 系列路徑商品 | `/collections/{c}/products/{p}` | `/products/{p}` | 平台仍需可訪（主題會生這種連結） |
| 4 | 系列分頁 | `/collections/{c}?page=2` | **自身**（不指第一頁） | 30 §1.3；`rel=prev/next` 已死 |
| 5 | 篩選／排序 | `?filter.*=`／`?sort_by=` | 基底系列頁 | **同時** robots disallow（canonical 對 facet 不夠力，30 §1.3） |
| 6 | 追蹤參數 | `?utm_*`／`?fbclid`… | 去參數後的 URL | 參數白名單制：**只有白名單內的參數參與 canonical**，其餘一律剝除 |
| 7 | 跨市場 URL | `example.com/fr-ca/products/x`／`example.ca/products/x` | **各自自身**（self-canonical） | 見 §B.4，與 hreflang 綁定 |
| 8 | 平台子網域 | `{shop}.chilllove.app/...` | 商家自訂網域的對應 URL | **301 全量**（30 §9-3；HANDOFF M7） |

**共通規則**：canonical 一律**絕對 URL**、含 scheme 與最終網域、**每頁自引**（30 §1.3 三訊號）。大小寫正規化、尾斜線正規化在 canonical 之前先做（路由層 301），不要靠 canonical 收拾。

### B.2 變體 URL：單頁多變體（唯一模式）＝ Google 官方的 single-page 形態

<!-- 依 google 官方 product-variants 頁補寫；30 §2.3 只寫了模式 A 的一半 -->
<!-- 依 68 號 §B-6 跟隨 Shopify 做法改寫（2026-08-12）：**模式 B 廢除**。
     原文（保留供追溯，🔴 任何人不得改回）：
       「### B.2 變體 URL：兩種模式，選一，不可混用
        | | 模式 A（預設）：單頁多變體 | 模式 B（opt-in）：變體獨立頁 |
        | URL | `/products/{handle}` ＋ `?variant=` 預選 | 每變體一個可索引 URL |
        | canonical | 整個 ProductGroup **只有一個** canonical＝不預選變體的基底 URL | 每頁 self-canonical |
        | JSON-LD | `ProductGroup` ＋ `hasVariant[]`（靜態全量，不隨 DOM 變） | 每頁**完整自足**標記，
                    `inProductGroupWithID` 指回父群組 |
        | 適用 | 顏色/尺寸等純屬性變體 | 變體本身有獨立需求量（不同型號、不同容量）時 |
        | 風險 | 單一 URL 難以針對「紅色 XX」做標題最佳化 | 內容近似頁大量增生，踩 thin content／重複內容 |
        **決策**：預設模式 A。模式 B 做成**商品級開關**（`product.seo.variant_urls_enabled`），
        開啟時平台強制檢查「每個變體頁的標題／描述／主圖至少各自不同」，不通過則拒絕開啟
        （避免商家一鍵生出 500 個近似頁）。」
     ❌ 68 號當時寫的廢除理由（**已被 69 號修正，保留供追溯**）：
       「🔴 **廢除理由不是「風險太高」，是「形態根本不對」**：「同一個商品的變體各自有 URL」正是
          Shopify **刻意不做**的東西。官方要達成同樣目的時，做的是 **Combined Listings**——
          在**資料模型層**就讓它們是不同商品，於是不存在重複內容問題。
          我方原本的「模式 B ＋ 內容差異檢查」是在**用檢查去補一個錯的形態**：
          檢查通過只證明三個欄位不同，不改變「它們是同一個商品」這件事。」

     🔴 **69 號 §B-6 修正了上面這段的定性（2026-08-12，`std` ×2 ＝ Google Search Central）**：
        ① Google **明文建議「讓每個變體能被一個獨立的 URL 識別」**（路徑段或查詢參數皆可）
           ⇒ **「變體可索引」是 Google 官方推薦的目標，不是應該被廢掉的東西。**
        ② Google 定義**兩種都合規**的站台形態：
             single-page：查詢參數切變體 ⇒ 🔴 **官方建議 canonical ＝去掉該參數的基底 URL**；
             multi-page ：各變體自己一頁 ⇒ 🔴 **「單一 canonical」這條要求明文不適用**，各頁對等。
           **Google 對兩種形態不表偏好。**
        ③ ⇒ Shopify 的預設**就是** Google 的 single-page（含官方建議的去參數 canonical），
           Combined Listings **就是** Google 的 multi-page。**Shopify 兩種都做了**，
           只是把 multi-page 鎖在 Plus 方案後面 ⇒ **「Shopify 刻意不做」這個定性是錯的。**

     🔴 **所以廢除的到底是什麼（本次修正的核心，一句話）**：
        廢除的是「**同一個 product 底下的 variant 各掛一個 URL**」這個**資料模型**——
        因為它會讓同一個資源有多個 canonical 候選，而 Google 對 single-page 形態的要求正好是
        「整個 ProductGroup 只能有一個 canonical」⇒ **模式 B 是 single-page 資料模型硬套
        multi-page URL 形態**，兩邊的規則都不滿足。
        **廢除的不是「變體可索引」這個目標**——那個目標是 Google 官方建議的，
        而**我方的 single-page 模式（`?variant=` ＋ 去參數 canonical）已經達成它**，
        且達成方式正是 Google 明文建議的那一種。
        ⚠ **這兩句話在日後回頭看時意義完全不同**：前者是「我們選了另一條合規的路」，
           後者會被讀成「我們放棄了一個 Google 想要的東西」。 -->

**唯一模式：單頁多變體 ＝ Google 官方定義的 single-page 形態。**

| | 規則 |
|---|---|
| URL | `/products/{handle}` ＋ `?variant=` 預選。✅ **每個變體都能被一個獨立 URL 識別**——這正是 Google 官方建議的目標（`std`，69 §B-6），我方以查詢參數達成 |
| canonical | 整個 ProductGroup **只有一個** canonical ＝ **不預選變體的基底 URL**（`?variant=` 去參數）。✅ **這是 Google 對 single-page 形態的明文建議**，不只是我方的取捨 |
| JSON-LD | `ProductGroup` ＋ `hasVariant[]`（靜態全量，不隨 DOM 變）；`variesBy`／`productGroupID` 依 30 §2.3 輸出，每個 variant 的 `offers.url` 指向**能直接預選該變體的 URL** |
| 適用 | 全部情形。顏色／尺寸等純屬性變體如此，不同型號／容量的變體**也如此** |
| 已知代價 | 單一 URL 難以針對「紅色 XX」做標題最佳化。**這是 Shopify 也有的代價，不是我方的缺陷**；官方的出路是把它們建成不同商品（見 §B.2-1） |

**🔴 三條硬規則（依 Google 官方，69 §B-6；違反即 lint 紅燈）**

| # | 規則 | 為什麼 |
|---|---|---|
| 1 | **single-page 模式下，整個 `ProductGroup` 只能有一個 canonical**（＝去參數的基底 URL） | Google 對該形態的明文要求。我方既有實作已符合（V-110 已由實測結案） |
| 2 | 🔴 **禁止用 fragment（`#…`）切換變體** | Google 索引**不使用** fragment ⇒ 用 fragment 等於變體完全不可識別，**連 single-page 的目標都達不到**。主題若這樣做，是主題的 bug，不是選項 |
| 3 | **變體參數一律 `?key=value`，不得用 `?value`** | Google 明文要求的參數格式；`canonical_query_allowlist` 的剝除邏輯也依賴 key 存在才能正確判定 |

> 🔴 **multi-page 形態的對應規則寫在 §B.2-1**（Combined Listings 等價物）：那裡的 canonical 規則**與本節相反**——各頁對等、**禁止** child 指向 parent。兩套規則不得互相搬用；搬錯的方向是「把 multi-page 的 child 全部 canonical 到 parent」，那會把它們從索引裡整批拿掉。

> ✅ **V-110 結案**（2026-08-12，依 68 §B-6(b)／§F-2）：Shopify 自身 `canonical_url` 在 `?variant=` 下的實際輸出**已由一手實測確認＝不含該參數**（`test`，兩店主題不同、輸出形態一致：`thesill.com/products/monstera?variant=…` → `…/products/monstera-deliciosa`；`otherland.com/products/…?variant=…` → 去參數的基底 URL）。
> <!-- 原條目：「⚠️ **V-110**：Shopify 自身 `canonical_url` 在 `?variant=` 下的**實際輸出**
>      （含或不含該參數）本輪只取得主題商／代理商的二手描述（`press`），未取得官方文檔或實測。
>      我方**按 Google 規則實作**（去參數），不按傳聞對齊 Shopify。」 -->
> ⇒ 我方原本「按 Google 規則實作（去參數）、不對齊傳聞」的處置，**現在證實與 Shopify 一致**。出處等級由 `press` 升為 `test`。

#### B.2-1 🔴 缺口登記：Combined Listings ＝ Google 的 multi-page 形態（我方目前沒有等價物）

<!-- 依 69 號 §B-6 補寫定性（2026-08-12）。本節原本把 Combined Listings 描述成
     「Shopify 對這個需求的官方答案」，那是對的但不完整——**它同時是 Google 官方定義的
     兩種合規形態之一**（multi-page），而不是 Shopify 私有的變通做法。
     🔴 這個差別影響的是**我方要不要做**這個判斷本身：
        若它只是「Shopify 的做法」，不做＝與 Shopify 有一個功能差距；
        若它是「Google 定義的兩種合規形態之一」，不做＝**我方只支援兩種合規形態中的一種**。
        後者仍然可以是正確的產品決策（single-page 已達成「變體可索引」的目標），
        但它必須被寫成「我方只做一種形態」，不能被寫成「那種形態不對」。 -->

**Shopify 對「每個變體要有獨立可索引 URL」這個需求的官方答案是 Combined Listings（合併商品）**（`help`）——**它不是「給變體加 URL」，是另一個東西**。
🔴 **而依 Google 官方（`std`，69 §B-6），它正是 multi-page 形態**：各變體頁**地位對等**，「整個 ProductGroup 只有一個 canonical」這條要求**明文不適用**。⇒ **本節登記的是「我方只做了 Google 兩種合規形態中的 single-page 那一種」，不是「Shopify 有個奇怪功能我方沒抄」。**

| 面向 | Combined Listings 的形態 |
|---|---|
| 資料模型 | **把數個真實商品串成一個前台商品列表**。每個子商品保有自己的 title／description／URL／圖片／價格／庫存，在 feed 裡是**獨立項目** |
| 為什麼沒有重複內容問題 | 因為它們**本來就是不同商品**——差異在資料層，不在渲染層。這正是「模式 B」做不到的事 |
| 方案閘門 | **Plus／enterprise**；需 Online Store 通路；免費主題 15.0.0+ 支援，其他主題要改碼 |
| 約束 | 商品必須已存在；**同時只能屬於一個 combined listing** |
| 上限 | 每個 listing ≤ **60** 個商品、**3** 個自訂選項、**2000** 個選項值（`limits.combined_listing.*`，鐵律 6） |
| 我方 canonical 定案 | 🔴 **子商品一律 self-canonical**（與 §B.4「一律 self-canonical」同一條），**不指向 parent**——指向 parent 等於宣告子商品不該被索引，那就失去做這件事的意義。<br>✅ **依據升級（69 §B-6／§V-187）**：這條現在有 **Google 官方**支撐，不只是我方推論——multi-page 形態下「單一 canonical」的要求**明文不適用**，各變體頁地位對等。<br>⚠ **V-187**：Shopify 子商品 canonical 的**實際輸出**仍未一手驗證（69 號查了 dev docs，兩頁對 URL／canonical／SEO **完全沉默**；唯一的第三方說法是**同一作者的兩個網域**，算 1 個 `blog` 來源、無測試數據 ⇒ **不可採信**）⇒ 我方按 Google 官方定案，**不猜 Shopify、不引那兩篇** |
| ⚠ 未答 | **V-203**（69 號新登記）：**parent 商品本身**在 online store 上是什麼——有無可索引 URL、是否進 sitemap、canonical 指向哪裡。官方只說 parent 不可購買、無庫存、無銷售數據，**沒說它在前台是什麼**。我方若做等價物：**parent 不進 sitemap**、若有 URL 則 self-canonical |

🔴 **狀態：已登記的缺口，不是已排程的功能。** 這在架構上是 parent/child 的商品關係（資料模型在 13 號），**不是一個開關**，因此不能靠 §B.2 的一行設定補上。**是否實作、是否照 Shopify 做成方案閘門，待使用者裁定**（68 §H）；`limits.combined_listing.implemented: false` ＋ `pending_user_decision: true`。

🔴 **在裁定前，任何人不得以「補回模式 B」的形式繞過本條。**
<!-- 依 69 §B-6 修正本句的理由（2026-08-12），原文：「——那會把 Shopify 刻意避開的重複內容
     問題重新引進來。」🔴 該理由的前提（「Shopify 刻意避開」）已被 69 號證偽：Shopify 兩種形態
     都做了，只是把 multi-page 鎖在 Plus。正確的理由如下，**它比原理由更硬**，因為它不依賴
     「Shopify 怎麼想」，只依賴 Google 明文的兩套規則彼此互斥。 -->
理由**不是**「Shopify 刻意避開重複內容」（69 號已證偽：本尊兩種形態都做了），而是：**模式 B 會同時違反 Google 兩種形態的規則**——它用 single-page 的資料模型（一個 product、多個 variant）去產出 multi-page 的 URL 形態，於是
- 對 single-page 的規則而言：同一個 `ProductGroup` 出現了**多個 canonical 候選**（§B.2 硬規則 1 違反）；
- 對 multi-page 的規則而言：那些頁**不是各自獨立的商品**，沒有各自的 title／description／庫存／feed 項目，只是同一筆資料的不同渲染 ⇒ 拿不到 multi-page 形態的任何好處，只拿到它的成本。

⇒ **要 multi-page，就要 Combined Listings 等價物那種資料層的分家；沒有中間形態。**

### B.3 分頁

每頁 self-canonical（**不得**全部指向第 1 頁——那會讓第 2 頁以後的商品連結不被發現）。分頁必須有真實的 `<a href>` 互鏈；infinite scroll 一定要有 paginated URL 後備（30 §1.3）。分頁頁的 `<title>` 加「第 N 頁」後綴（§E.2），避免標題完全重複。

### B.4 跨市場：self-canonical，**不跨市場 canonical**

Shopify 記載的行為是每個市場版本 self-canonical ＋ hreflang 互連（`help`）。Google 的多地區文檔則說：同語言的地區重複內容「可挑一個偏好版本用 `rel=canonical` ＋ hreflang」（`google`）。

**這兩者不是同一件事，而且互斥**：被 canonical 指走的 URL 不會被索引，也就無法作為 hreflang 的有效目標。**我方定案：一律 self-canonical**，理由是我們要的是「每個市場各自被索引、各自報自己的幣別與運費」，而不是「合併成一個」。代價是同語言不同地區的頁面會競爭同一批查詢——這是已知代價，用 hreflang ＋ 各市場差異化內容（幣別、運送時效、政策）緩解，不用 canonical 緩解。

> ⚠️ **V-120**：Google 這兩份官方文檔之間的張力（多地區頁建議 canonical vs 在地化頁要求可索引）**未見官方調和說明**，需實測（同語言雙地區站，觀察 GSC 收錄與 hreflang 生效）。在結案前不得改動上述定案。

### B.5 資料模型

```
url_redirects(shop_id, from_path, to_path, status_code, source, created_at)
  unique [shop_id, from_path]；source ∈ {handle_change, manual, domain_move, import}
canonical_overrides(shop_id, resource_type, resource_id, canonical_url)  # 極少用，需審計
```
`from_path` 帶 market/locale 前綴時視為**該 web presence 內**的重導；跨市場重導一律禁止（會打破 §I 的矩陣）。重導鏈長度上限 `limits.seo.redirect_max_chain`（見 §N），超過即 lint 紅燈（Google ≤10 hops，30 §1.1）。

---

## C. Sitemap

沿用 30 §3／§9-1 的分片結構（`/sitemap.xml` index → products／collections／pages／blogs 分片，單檔 ≤50,000 URL）。本節只補**多市場與多語言的切法**，這是 30 號沒有寫死的部分。

| 網域策略 | sitemap 位置 | 內容 |
|---|---|---|
| 主網域子資料夾市場（`example.com/fr-ca`） | 併入主網域 `/sitemap.xml` | 每個資源一列 `<url>`，`loc` 為該市場的 URL；`xhtml:link` 列出**全集含自身**（§I 矩陣） |
| 子網域市場（`ca.example.com`） | **各子網域各自一份** `/sitemap.xml` | 只列本網域 URL；`xhtml:link` 仍列全集（跨網域互指） |
| 獨立網域市場（`example.ca`） | 同上 | 同上 |

**四條硬規則**：
1. **只列 canonical 且回 200 的 URL**。draft market 的 URL（29 §1.1「可瀏覽不可購買」）**不進 sitemap、不進 hreflang、且輸出 `noindex`** ——一個不能結帳的頁面被索引，等於用自然流量把買家送進死路。（⚠ Shopify 對 draft market 的處置本輪未取得 ⇒ **V-112**；我方按上述定案，不等 V-112。）
2. `lastmod` ＝**實質內容更新時間**，不是任何欄位的 `updated_at`（庫存數變動不算內容更新）。灌水會讓 Google 整體不信任該站的 `lastmod`（30 §3）。
3. **不實作 ping endpoint**（Google 2024-01 移除，30 §3）。新鮮度靠 IndexNow（30 §9-9，Google 不參與）＋ sitemap `lastmod`。
4. sitemap 內的 `xhtml:link` 與 `<head>` 的 hreflang **由同一個矩陣函式產生**（§I.1）。兩處各寫一遍必然漂移——這是 §0.2 原則 1 在 hreflang 上的同構。

---

## D. robots.txt

### D.1 可編輯性與模板

Shopify 的機制：平台自動產生預設 `robots.txt`，主題可加 `templates/robots.txt.liquid` 以 `robots` 物件（`default_groups` → `group.user_agent` / `group.rules` / `group.sitemap`）為基礎增刪規則，官方立場是「用 Liquid 物件擴充，不要整份換成純文字」（`dev`）。我方 1:1 復刻此形態（26:220–224 已列 `robots`／`group`／`rule`／`sitemap` 物件，T2）。

**我方加碼三條**（Shopify 沒有、但多租戶 SaaS 需要）：
1. **lint gate**：租戶覆寫後若造成 `Disallow: /` 或移除 `Sitemap:` 行，儲存時**警告＋二次確認**，並在後台 SEO 健康頁常駐紅色橫幅。
2. **平台保底注入**：`Sitemap:` 行與 `/checkout`、`/cart`、`/account` 的 disallow **無論主題怎麼寫都會被平台 append**（第 1 層責任，同 §A.1）。
3. **每租戶一份 IndexNow key 路由**（30 §9-9）。

### D.2 預設 disallow 集合

`/cart`、`/checkout`、`/account`（及子路徑）、`/search`、facet 參數（`?filter.*`、`?sort_by=`）、內部預覽 URL（`?preview_theme_id=`／`?_ab=`）。**不 disallow** `/collections/*/products/*`（靠 canonical 收）。

### D.3 AI 爬蟲策略（GEO-G 的入口，但實作在 robots）

| User-agent | 歸屬 | 用途（官方定義） | 封鎖的後果 | 我方預設 |
|---|---|---|---|---|
| `OAI-SearchBot` | `openai` | 讓網站出現在 ChatGPT 搜尋 | **不會出現在 ChatGPT 搜尋答案**（官方明文） | **Allow** |
| `GPTBot` | `openai` | 訓練基礎模型 | 內容不進訓練資料 | 需裁定（見下） |
| `OAI-AdsBot` | `openai` | ChatGPT 廣告頁面安全檢查；**不用於訓練** | 無法投 ChatGPT 廣告 | Allow |
| `ChatGPT-User` | `openai` | 使用者即時觸發的取頁 | 官方註明「使用者觸發，robots.txt 規則**可能不適用**」 | 不依賴 robots 控制 |
| `Google-Extended` | `google` | 控制內容是否用於 Gemini 訓練／grounding；**不影響 Google 搜尋收錄與排名** | Gemini 訓練不使用 | 需裁定 |
| `Googlebot` | `google` | 搜尋索引（AI Overviews／AI Mode 的資格來源） | 整站消失 | **Allow，且不可由租戶關閉** |
| `ClaudeBot`／`PerplexityBot` 等 | `press` | 本輪**未逐一取得各家官方 UA 文檔** ⇒ 名稱與語義待覆核 | — | 以**可設定清單**呈現，不寫死 |

**產品形態**：後台不提供「一個 AI 開關」，提供**三組**——① 搜尋／答案型（影響曝光）② 訓練型（影響模型內化）③ 使用者觸發型（不可靠控制，僅說明）。分組理由：把 `OAI-SearchBot` 和 `GPTBot` 綁在一個開關上，商家關掉訓練的同時會無聲關掉 ChatGPT 曝光——那是最貴的誤操作。

> ⚠️ **V-123**：封鎖訓練型爬蟲對「商品被 AI 答案引用」的實際影響**沒有公開對照實驗**。後台文案**不得**宣稱任一方向的效果，只陳述官方定義。
> ⚠️ **V-121/V-122** 見 §H.4。

---

## E. 標題與描述的樣板化

### E.1 欄位與 fallback 鏈

每個可索引資源（product／collection／page／article／blog／首頁／search）有兩個商家欄位：`seo_title`、`seo_description`（並可翻譯——29 §2.1 的 `meta_title`／`meta_description` 已在可翻譯資源清單內）。

```
標題 = seo_title（該 locale） → seo_title（預設語言） → 樣板渲染 → 資源標題
描述 = seo_description（該 locale） → seo_description（預設語言） → 樣板渲染 → 資源內文首段（strip HTML、詞界截斷）
```
**空描述不編造**：若最終為空，**不輸出 `<meta name="description">`**（讓引擎自選片段），不輸出空字串、不輸出商店標語充數。

### E.2 各資源的預設樣板（tokens 化，商家可改）

| 資源 | 預設標題樣板 | 預設描述樣板 |
|---|---|---|
| 首頁 | `{{ shop.name }}{% if shop.slogan %} — {{ shop.slogan }}{% endif %}` | `{{ shop.description }}` |
| 商品 | `{{ product.title }} — {{ shop.name }}` | 商品描述前 N 字（N＝`limits.seo.meta_description_recommended_chars`） |
| 系列 | `{{ collection.title }} — {{ shop.name }}` | 系列描述 → 空則不輸出 |
| 系列第 N 頁 | `{{ collection.title }} — 第 {{ page }} 頁 — {{ shop.name }}` | 同第 1 頁（或不輸出） |
| 頁面／文章 | `{{ title }} — {{ shop.name }}` | 摘要 → 內文首段 |
| 搜尋 | `搜尋：{{ terms }} — {{ shop.name }}` | 不輸出（該頁 `noindex`） |

<!-- 依 68 號 §B-6 刪除「商品（模式 B 變體頁）」一列（原值：`{{ product.title }} {{ variant.title }} — {{ shop.name }}` ／ 描述「同上＋變體屬性」）。
     模式 B 已廢除（§B.2），不存在「變體頁」這個模板。Combined Listings 的子商品**是真實商品**，
     直接套用上面「商品」那一列即可，**不需要第二套樣板**——這正是 Combined Listings 與模式 B 的差別：
     前者不需要為「半個商品」發明任何東西。 -->

**分隔符、順序（店名在前或在後）做成主題設定**，因為這是 Shopify 主題間差異最大的一項（`help` 註明依主題而定）。**上限**：標題 `limits.content.seo_title_max_chars`（70，已存在）並在 60 字提示；描述 `limits.content.seo_meta_description_max_chars`（320，已存在），建議值 160（新增鍵，§N）。截斷一律在**詞界／字界**，多位元組字元不得截半，尾綴 `…`。

### E.3 SEO 預覽卡（admin，59 §3 / 60 §6 實測形態）

必含五列，**順序照實測**：商店名｜麵包屑式 URL｜標題｜截斷描述｜**價格（`HK$938.00 HKD` 形態：符號金額＋空格＋幣別碼）**。價格取自 §A.3 的同一個 `PriceView`（49 號 A-8 缺口在此關閉）。空態文案照 59 §7 的形態：未填標題與描述時顯示引導語而非空白卡。

---

## F. 圖片 alt、`<h1>` 唯一性、handle 與 301

### F.1 圖片 alt

- `media.alt` 為一級欄位（可翻譯，29 §2.1 `MEDIA_IMAGE(alt)`／`COLLECTION_IMAGE(alt)`）。
- **不自動填、但要度量**：後台商品列表與 SEO 健康頁顯示「缺 alt 的媒體數」。若提供 AI 產生 alt，寫入時必須落 `alt_source: ai|human|imported` 稽核欄——理由同 30 §1.2 的 scaled content abuse 防線：無標記的大量自動內容日後無法回溯清理。
- 裝飾性圖片（主題背景）輸出 `alt=""`，**不是**省略屬性。

### F.2 `<h1>` 唯一性

每個模板恰有一個 `<h1>`：PDP＝商品標題、collection＝系列標題、article＝文章標題、首頁＝店名或主標。實作為**主題 lint 規則**（theme-check 自訂規則，31 號主題引擎的 lint 管線內）＋渲染期 dev 模式斷言。多個 `<h1>` 不擋渲染，但在編輯器警示。

### F.3 handle 規則與改名 301

<!-- 🔴 2026-08-12 使用者裁定推翻本節原有的「保留 CJK」定案。裁定逐字：
     「url hand 使用英文標題，**禁止使用中文**。例如 https://chill.deals › products ›
      kerastase-specifique-stimuliste-nutri-energising-daily-anti-hairloss-spray-125ml-4-2oz
      所以你要做多語言。商品所有數據，前台，後台，都要做多語言。」

     本節原文（保留供追溯，**任何人不得改回**）：
       handleize(title, locale):
         1. Unicode NFKC 正規化
         2. 空白與底線 → "-"；連續 "-" 收斂；首尾 "-" 去除
         3. 保留：a-z 0-9 - 以及**非 ASCII 字母**（CJK 等）
         4. 全部大寫 → 小寫（ASCII 範圍）
         5. 結果為空 → fallback "{resource}-{id}"
         6. 唯一性衝突 → 追加 "-2"、"-3"…
       「**為什麼保留 CJK**：基準法域是香港（鐵律 11），商家會用中文標題。強制轉羅馬字要嘛需要
        拼音表（品質差、粵語/國語不一致），要嘛落成 `product-123`（對使用者與 AI 都無語義）。
        URL 層以 percent-encoding 傳輸，`<link rel="canonical">` 與 hreflang 一律輸出
        **percent-encoded 形式**（避免不同客戶端正規化不一致）。」

     原文的推理**在當時是對的，前提被裁定換掉了**：它假設「商家用中文標題 ⇒ handle 只能中文或無語義」。
     裁定同時要求「商品所有數據都要多語言，首發含英文」⇒ **英文標題本來就是必填欄位**，
     handle 從英文標題產生因此是零額外輸入。前提一換，結論就反過來。
     完整推理與 slug 規則見 `docs/specs/67-multilingual.md` §D（含以裁定範例做的可重跑驗證）。 -->

**🔴 handle 一律 ASCII（`[a-z0-9-]`），禁止 CJK 與任何非 ASCII 字元。**（`ruling`，2026-08-12）

```
handleize_url(title):            # 完整九步管線與驗證樣本見 67 §D.1；鍵在 limits.yml §21 handle:
  1. Unicode NFKC 正規化          # 全形 → 半形
  2. 撇號與引號類**刪除**（不是分隔）        Bob's → bobs
  3. 不可分解拉丁字母查表轉寫                ß→ss ø→o ł→l æ→ae …（NFKD 不分解這些）
  4. NFKD → 去除 combining marks             Kérastase → kerastase
  5. 轉小寫（ASCII 範圍）
  6. 其餘非 [a-z0-9] 的連續字元 → 單一 "-"   🔴 含 "." 與 "/"：125ml/4.2oz → 125ml-4-2oz
                                              （刪除 "." 會得到 42oz —— 規格數字被改寫）
  7. 連續 "-" 收斂；首尾 "-" 去除
  8. 超過 limits.handle.max_chars ⇒ 在**分隔符邊界**截斷（不得從字元中間切）
  9. 品質閘門：ASCII 字母數 < 3 ∨ 丟棄字母比例 > 0.5 ⇒ 落確定性 fallback（67 §D.2）
```

**中文標題怎麼辦**（67 §D.2 的完整論證，此處只記結論）：來源優先序 ＝ **商家手填 → `en` 標題的 slug → base 標題 → 確定性 fallback `{resource}-{token8}`**。🔴 **不做拼音**（對粵語圈是錯的、多音字讓確定性不成立、無搜尋價值）、🔴 **不做機器翻譯直接落庫**（URL 是永久身分，生成器必須確定性；且會在寫入路徑引入外部 IO，違反 63 §A.2）。**不擋發布**，改用可觀測的摩擦（自動代碼佔比進 SEO 健康頁）。

**語言維度不在 handle 裡**（67 §D.3）：handle 是 per-shop-per-resource 的單一值，語言由 **URL 路徑前綴**承載（`/en/products/x`），因此 §I.1 的 `absolute_url(resource, wp, loc)` 是純字串拼接，不需對每個 (wp, locale) 查 handle。handle **不可翻譯**（刻意偏離 29 §2.1，登記於 67 §M-2）。

> 🔴 **Liquid `handleize` filter 不適用本節規則**：它產生的是 CSS class／DOM id／JS 鍵（Ella 用 91 處，27 §5），不是 URL。若把 ASCII-only 管線套上它，`{{ '顏色' | handleize }}` 會回空字串 ⇒ 選擇器碰撞 ⇒ 變體選錯而不報錯。兩者**不得共用實作**，見 67 §D.5（`limits.handle.liquid_filter_ascii_only: false`）與 **V-161**。
> <!-- 依 68 號 §F-3 補正事實（2026-08-12）：Shopify 的 filter **保留非 ASCII**
>      （community.shopify.dev/t/unicode-in-handleize-output/1060，2024-10，staff 已復現：
>      `{{ 'Abc 123-D--E 🔪 ŭ' | handleize }}` 的實際輸出**保留 emoji**、`ŭ` 折成 `u`）。
>      ⇒ `{{ '顏色' | handleize }}` 在**本尊會回 `顏色`，不會回空字串**。上面那句「回空字串」
>      講的是「**我方若誤用 URL 管線**會怎樣」（那正是本條要防的事故），不是本尊的行為。
>      🔴 連帶結論：我方 filter 端的 `h-{sha1}` fallback **不得因「結果非 ASCII」觸發**，
>      只在**輸入本身為空或全為分隔符**時觸發（67 §D.5 已據此修正）。 -->

<!-- 依 68 號 §B-1 修正 V-119 的結案敘述（2026-08-12）。
     原文（保留供追溯，🔴 任何人不得改回）：
       「> ✅ **V-119 結案**（2026-08-12）：原問題是「Shopify `handleize` 對 CJK 的實際行為」，
          用途是決定我方要不要對齊。裁定已直接定死我方行為（一律 ASCII），**對齊問題消失**，故結案。
          其**主題相容殘留**（filter 面）改由 **V-161** 承接（67 §L）。」
     🔴 **原文說「對齊問題消失」是錯的。** 68 號把 V-119 的原問題**正面查出來了**：
        Shopify 對非拉丁字集是**原樣保留**，中文標題得到的是中文 handle。
        ⇒ 對齊問題**沒有消失，它有答案，而我方明知答案仍然不照做**。
        這兩件事在日後回頭看時意義完全不同：前者是「不必比了」，後者是「比過了，我方選擇偏離」。
        寫成前者，下一輪稽核只會看到一條已結案的項目；寫成後者，才能在裁定改變時被正確重審。 -->

#### F.3-1 🔴 明知偏離 Shopify 的一條：handle 一律 ASCII（原 V-119 的正確結案形態）

**比照 13 §F1(g)、15 §F4.2、58 §D.2 的既有「刻意偏離」寫法，本條明文登記，避免下一輪稽核當成遺漏重新開單。**

| | 內容 |
|---|---|
| **Shopify 的實際行為** | 🔴 **保留非拉丁字集**。拉丁系變音符號折疊成 ASCII（`mašīna → masina`）；**CJK／西里爾／希伯來／emoji 原樣保留**，URL 以 percent-encoding 呈現。純中文標題得到的 handle 就是**中文本身**——不是 `product-{id}`，也不是空字串。Shopify **沒有 fallback 代碼這回事，因為它不需要**；也**沒有任何 handle 品質閘門**，不擋發布 |
| **出處與等級** | `press` ×4（community 80006／239594／223998、community.shopify.dev 1060 staff 復現）＋ `press` 實例頁面 URL。🔴 **官方文檔完全沒有敘述非拉丁字集的處置規則** ⇒ 描述本尊行為時**只能標 `press`，不得標 `dev`**（68 §I，V-180）。反例 1 則（goodsofdesire.com `8折 → 8`）研判為商家手改 |
| **我方的行為** | handle 一律 `[a-z0-9-]`（`limits.handle.ascii_only: true`）＋ 品質閘門 ＋ 確定性 fallback `{resource}-{token8}`。**不擋發布**（這一半與 Shopify 相同） |
| **偏離的唯一依據** | 🔴 **使用者 2026-08-12 裁定**：「url hand 使用英文標題，**禁止使用中文**」。**裁定 > Shopify**（68 §0 凌駕規則 1）。**不是**技術判斷、**不是** SEO 判斷、**不是**查不到而保守 |
| **連帶物** | 品質閘門（`min_latin_alpha_chars`／`max_dropped_letter_ratio`）與中英混排保留英文片段——**Shopify 無此概念**（它保留 CJK 就不需要）。兩者是「一律英文」裁定的**必然衍生物**，不是獨立設計（68 §C-4／C-5） |
| **裁定若改** | 本條、`limits.handle.ascii_only`、品質閘門三鍵、`fallback_pattern`、以及 67 §D.2／§D.3 **必須連帶重審**。單獨改任何一個都會產生半套狀態 |

> ✅ **V-119 的原問題已由 68 號查明並結案**（答案＝保留 CJK），但**結案理由是「查到了」，不是「不用查了」**。其**主題相容殘留**（Liquid filter 面）改由 **V-161** 承接（67 §L；該條已依 68 §F-3 縮小，見下）。

**改名 301**：handle 變更時，於同一 transaction 插入 `url_redirects(from=舊, to=新, 301, source=handle_change)`。**舊 handle 永不回收**（除非商家手動刪除該重導；唯一性檢查因此要比對 `url_redirects`，67 §D.4(a)）。**多語言補充**：登記與比對一律用**不帶前綴的正規路徑**，路由層命中 404 前先剝 locale 前綴 → 查表 → **命中後把前綴加回去再 301**（`/en/products/舊` → `/en/products/新`，不得丟回 `/products/新`）。下架商品：預設 **410**，可選 301 至最相關頁（30 §9-5）。**禁止 soft-404**。

---

## G. Core Web Vitals 與 Liquid 渲染的關係

門檻沿用 30 §4（LCP ≤2.5s／INP ≤200ms／CLS ≤0.1，CrUX 75 百分位）。本節寫**只有 Liquid 相容引擎才會遇到的四個結構性風險**：

| # | 風險 | 為什麼是 Liquid 特有 | 對策 |
|---|---|---|---|
| 1 | **快取鍵爆炸** | 頁面快取鍵必須含 `(shop, template, market, locale, presentment_currency, customer_state, theme_version)`。多市場×多語言×多幣把同一頁乘成數十份，命中率崩、TTFB 上升 → 直接打 LCP | 分層：**市場無關的片段**（header/footer 靜態部分、商品文案）與**市場相關片段**（價格、運費、政策）拆開快取；價格片段走邊緣可組裝的佔位（ESI 式）；`limits.seo.cwv.*` 定 TTFB 預算 |
| 2 | **主題 N+1 drop** | `{% for product in collection.products %}{{ product.metafields… }}` 在 Liquid 層看不出是 N 次查詢 | drop 層強制批次載入 ＋ 渲染期 query 計數上限（超過即 dev 模式報錯、生產記 `slow_render` 事件） |
| 3 | **`content_for_header` 阻塞** | 平台注入 script（含分析、編輯器橋）在 `<head>`，直接吃 LCP | 平台注入一律 `defer`／`async`；編輯器橋只在編輯 context 注入；第三方 script 走 idle 延載（30 §4） |
| 4 | **section 渲染與 CLS** | Section Rendering API 回填內容改變版面 | 所有圖片強制 `width`/`height`；section 佔位必須有固定高度；主題審核門檻擋不合格主題 |

**LCP 首圖規則**（承 30 §4）：主圖 `preload` ＋ `fetchpriority="high"` ＋ **首屏不 lazy-load**；圖片管線 WebP/AVIF＋srcset。**新增**：多市場下首圖可能因 contextual template（29 §7.3）而不同——preload 的 URL 必須由**同一個 template 解析結果**產生，否則會 preload 錯圖（等於多下載一張大圖，LCP 反而更差）。

---

# GEO-G（生成式引擎）

## H. 讓 AI 檢索與引用我方商品

### H.1 2026-08-12 查證到的事實（每條帶出處，未查證者明標）

| # | 事實 | 出處等級 | 日期 |
|---|---|---|---|
| 1 | Google 官方：出現在 AI Overviews／AI Mode **沒有額外要求，也沒有必要的特殊最佳化**；控制手段是既有的 `nosnippet`／`data-nosnippet`／`max-snippet`／`noindex` | `google` | 查證 2026-08-12 |
| 2 | Google 官方（同頁）：**不需要建立新的機器可讀檔案、AI 文字檔或標記**，也沒有必須新增的 schema.org 結構化資料 | `google` | 同上 |
| 3 | Google 的 John Mueller 談 `llms.txt`：「純屬臆測……這個檔案存在多年，卻沒有任何 AI 系統使用它」 | `press`（Search Engine Journal 轉述，2026-06） ⇒ **V-117** | 同上 |
| 4 | `Google-Extended` **不影響** Google 搜尋收錄，也不是排名訊號；它管的是 Gemini 訓練／grounding | `google` | 同上 |
| 5 | OpenAI 官方：封鎖 `OAI-SearchBot` ⇒ 不會出現在 ChatGPT 搜尋答案；`GPTBot` 管訓練；`ChatGPT-User` 為使用者觸發、robots 規則可能不適用 | `openai` | 同上 |
| 6 | Shopify **2026-05-28** 起支援 `templates/agents.md.liquid`／`llms.txt.liquid`／`llms-full.txt.liquid`；預設 `/llms.txt` 與 `/llms-full.txt` **指向 `agents.md` 的內容** | `dev` | 同上 |
| 7 | `agents.md.liquid` 的 context **只有 `request` 與 `agents`**；`agents` 含 `ucp_discovery_url`／`mcp_endpoint_url`／`ucp_versions`／`sitemap_url`／`currency`／`store_name`／`store_url`；**不可在地化**、走裸主網域 | `dev` | 同上 |
| 8 | UCP（Universal Commerce Protocol）由 Shopify 與 Google 共同發起（Shopify 工程文 2026-01-11），規格站 `ucp.dev` 版本 **2026-04-08**；商家在 `/.well-known/ucp` 公布 profile（version／services／capabilities／payment_handlers／signing_keys），能力集 Cart／Checkout／Order／Identity Linking；MCP 為其可選傳輸；`Cache-Control: public, max-age=60` 為最低要求 | `ucp` | 同上 |
| 9 | Shopify Storefront MCP：`https://{shop}.myshopify.com/api/mcp`（`search_shop_policies_and_faqs`／`get_cart`／`update_cart`）與 `…/api/ucp/mcp`（`search_catalog`／`lookup_catalog`／`get_product`）；**免認證** | `dev` | 同上 |
| 10 | Shopify 代理式（Agentic）銷售管道：ChatGPT／Google AI Mode 與 Gemini（早期存取）／Microsoft Copilot／Meta；後台 `Sales channels > Agentic` 管理；**符合資格的商店預設啟用**；商品經 **Shopify Catalog** 供給；ChatGPT 為導流型（回店完成購買），其餘可在管道內直接結帳 | `help` | 同上 |
| 11 | Shopify Catalog：全球商品目錄，符合條件即**自動納入，不能退出 Catalog 本身**，但可逐一限制 AI 管道存取 | `help` | 同上 |
| 12 | Shopify 對 AI 平台的商品資料建議欄位：標題、描述、圖片、類型／廠商／系列／標籤、條碼（ISBN/UPC/GTIN）、變體（含選項名）、外部商品 URL；並要求政策（如退貨）完整 | `help` | 同上 |
| 13 | ACP（Agentic Commerce Protocol）由 Stripe 與 OpenAI 發起，Apache-2.0，REST 與 MCP 相容 | `openai`/官方站 | 同上 |
| 14 | 學術基準：GEO（KDD 2024，Aggarwal et al.）在 GEO-Bench 上顯示最佳化可提升生成式引擎可見度**最高 40%**，且**效果隨領域差異很大** | 論文 | 同上 |
| 15 | Shopify 自述 Q1 2026 資料：AI 導流 session 年增 8×、訂單近 13×、轉換率較自然搜尋高 50% | 廠商自述 ⇒ **不作為我方規格依據** | 同上 |

### H.2 `llms.txt` 到底做不做——結論與依據

<!-- 依 68 號 §C-1 跟隨 Shopify 做法修正（2026-08-12）。
     原文：「**結論：做，但只做成「與 `agents.md` 同源的別名端點」，且 `llms-full.txt` 預設關閉。
             不投入任何內容策展與人力。**」
     原結論的**前半（別名端點、不做內容策展）是對的，保留**；**後半（預設關閉）是錯的**，
     錯因是把 Shopify 的 `llms-full.txt` 誤讀成「整站 markdown 打包」——它不是，它是第三個別名。
     🔴 這是**我方誤讀本尊實作造成的分歧，不是價值觀分歧**（68 §C-1 逐字結論）。
     🔴 **防回退**：不要因為「llms-full 聽起來就是整站傾印」而把預設改回關閉。
        真正的整站傾印只會在商家自訂 `templates/llms-full.txt.liquid` 之後出現，
        那個情境由 `limits.agents.llms_full_txt_max_bytes` 承接，不是由預設值承接。 -->

**結論：做，但只做成「與 `agents.md` 同源的別名端點」；三條路徑（`/agents.md`／`/llms.txt`／`/llms-full.txt`）預設全開且內容相同。不投入任何內容策展與人力。**

**依據（三條，全部可追溯）**：

1. **反面證據是硬的**：Google 官方明文說 AI 功能不需要新的機器可讀檔案（事實 2），Google 代表更直接說沒有任何 AI 系統在用（事實 3，`press` ⇒ V-117）。OpenAI 的 bots 文檔通篇講 robots.txt 與 UA，**完全沒有提到 `llms.txt`**（事實 5）。也就是說：**沒有任何一家引擎的官方文檔宣稱消費它。**
2. **但成本可以壓到接近零**：Shopify 已經把 `/llms.txt` 做成 `agents.md` 的別名（事實 6）。我方照抄這個形態，等於**多兩條路由指向同一個生成器**，沒有第二份內容、沒有第二套快取、沒有商家要維護的東西。反過來，**不做的成本反而存在**：從 Shopify 搬過來的商家，舊站這兩個 URL 有東西、新站 404——59 號的裁定精神（「肌肉記憶不能斷」）在 URL 面同樣成立。
3. **`llms-full.txt` 在 Shopify 不是打包，是別名 ⇒ 與 `/llms.txt` 同等待遇，預設開**（`dev`，2026-05-28 changelog；68 §C-1）。

   <!-- 依 68 號 §C-1 跟隨 Shopify 做法整段改寫（2026-08-12）。原文（保留供追溯，🔴 任何人不得改回）：
        「3. **`llms-full.txt` 是另一回事，要拒絕**：它的語義是「把整站內容打包成 markdown」。
            ①沒有引擎宣稱消費它；②它等於把商家全站內容做成一鍵可抓的封包，與內容授權、頻寬成本、
            競品比價全部衝突；③生成成本隨商品數線性成長，大租戶會把它變成一個昂貴的無人使用端點。
            **預設 `false`，商家可開，開啟時強制套大小上限與快取**。」
        🔴 **原文的三條理由本身沒有錯，錯的是它們針對的對象。** ①②③ 針對的是 `llms-full.txt` 的
           **原始語義**（整站 markdown 打包）；而 Shopify 的實作**根本不是打包**——`/llms.txt` 與
           `/llms-full.txt` 預設都指向同一份 `agents.md` 內容（本節事實 6）。前提換掉之後：
             ② 沒有第二份內容 ⇒ 不存在「全站封包」這件事；
             ③ 沒有第二套生成 ⇒ 成本不隨商品數成長；
             ① 對 `/llms.txt` 同樣成立，而我方已經接受了 ⇒ 不能拿它單獨否決第三條路徑。
        🔴 **這是誤讀本尊實作造成的分歧，不是價值觀分歧**——記下這個區別，是為了讓日後回頭看的人
           知道「當時的推理沒壞，只是餵給它的事實是錯的」，而不是把整段推理一起丟掉。 -->

   - **預設值**：`limits.agents.llms_full_txt_enabled: true`（原 `false`）。三條路徑預設全開、內容相同、共用同一個生成器與同一份快取。
   - **`llms_full_txt_max_bytes: 5242880` 保留**：別名形態下用不到，但商家一旦自訂 `templates/llms-full.txt.liquid`，**原始語義（整站打包）就回來了**——那時這個護欄是必要的。**護欄跟著「商家可以寫任意 Liquid」這件事走，不跟著預設值走。**
   - **①（無引擎官方宣稱消費）仍然成立**（V-117 不因本次改動結案）：它的結論是「不投入內容策展」，不是「不提供路徑」。

**反過來說，真正該投資的是什麼**：事實 8/9/10/11/12 指向同一個方向——2026 的生成式通路吃的是**結構化的商務能力與商品資料**（Catalog、MCP 工具、UCP 能力宣告），不是一個文字檔。我方的投資順序因此是：**§H.4 資料完整度 ＞ §H.3 代理端點 ＞ `llms.txt`**。

> ⚠️ **V-118**：`agents.md`／`llms.txt` 這組端點**是否真的被代理抓取**，本輪未取得任何一手伺服器日誌證據。上線後我方應**自己量**（§H.7 的 AI 流量儀表板），用自家資料結案，不靠業界文章。

### H.3 `agents.md` / `llms.txt` / UCP / MCP：我方要做什麼

**（a）三個端點與 fallback 鏈**（形態對齊事實 6/7）

```
/agents.md      ← templates/agents.md.liquid      → 平台預設生成器
/llms.txt       ← templates/llms.txt.liquid       → agents.md 模板 → 平台預設生成器
/llms-full.txt  ← templates/llms-full.txt.liquid  → agents.md 模板 → 平台預設生成器
```
<!-- 依 68 號 §C-1 修正，原文該行尾為「（預設關閉）」。三條路徑**預設全開且內容相同**（dev，2026-05-28）。 -->
🔴 **三條路徑預設全開**（`limits.agents.llms_paths_default_alias_of_agents_md: true`）。沒有「哪一條預設關」這回事——關掉其中一條就會讓從 Shopify 搬來的商家在那條 URL 上從有內容變成 404。
Liquid context **只給兩個物件**（`request`、`agents`），全域物件不可用——理由與 Shopify 相同且我方更需要：這三個端點走**裸主網域、無 locale 前綴、不可在地化**，若讓模板取用 `collections`／`shop`，快取鍵會被市場與語言污染，而這個檔案根本沒有市場維度。

`agents` drop 的欄位（我方等價物，命名對齊以利主題移植）：`store_name`、`store_url`、`sitemap_url`、`currency`、`ucp_discovery_url`、`mcp_endpoint_url`、`ucp_versions`。

**（b）能力宣告的鐵律**（承 §0.2 原則 3）

`ucp_discovery_url` 與 `mcp_endpoint_url` **只有在我方真的提供該端點時才輸出**。在 M6 之前我方不提供 UCP，因此：

```yaml
agents:
  ucp:
    provider_enabled: false        # 未實作前恆 false
    declare_when_disabled: false   # 🔴 未實作就**不輸出該欄位**，不得輸出空字串或佔位 URL
    enable_gate: [V-113, V-114]      # 兩條未結案前不得 enable
```
輸出一個指向 404 的 `ucp_discovery_url`，代理會在買家面前失敗；那比沒有這個欄位糟糕得多。

**（c）UCP 我方做不做**

**做，但排在 M7 之後，且分兩階段**：
- **階段 1（唯讀，M6 可評估）**：`/.well-known/ucp` 只宣告 **Catalog 查詢**能力（對應 §H.4 的商品端點），不宣告 Cart／Checkout。價值：讓代理能正確報價與導流回店，風險低。
- **階段 2（可交易，M7+）**：Cart／Checkout／Order 能力，牽涉簽章金鑰管理（JWK）、webhook 簽章（UCP 要求商家→平台 webhook **必須簽章**）、冪等（鐵律 5 已有底座）、以及**代理下單的法域與稅務快照**（56 §0.2：訂單成立即快照法域碼——代理下單同樣適用，不得例外）。

> ⚠️ **V-113**：`/.well-known/ucp` 是否對所有 Shopify 商店自動提供、其內容與快取策略、`ucp_versions` 的值域——本輪只由 `agents` drop 的欄位存在**反推**其存在，未取得該端點的官方規格頁。
> ⚠️ **V-114**：UCP／MCP 如何攜帶**買家國別與幣別**以取得 per-market 價格。`agents.md` 只暴露單一 primary currency 且不可在地化（事實 7），若協定層沒有市場參數，多市場商家會被代理報錯幣別。**這是我方多市場架構與代理通路之間最大的未知**。

### H.4 AI 代理／agentic 通路要什麼資料（我方 Catalog 等價物）

實站側欄有「代理式（Agentic）」銷售管道（21 §1、47 §B、49 號 A 項），我方原型也有一個 toast 佔位。本節把它變成規格。

**（a）資料契約＝GMC 規格的超集，不另立一套**

30 §8 的結論是「以 GMC 規格為 canonical schema ＋ per-channel 轉換層」。代理通路**沿用同一個生成器**，只加三個 AI 特有欄位：

| 欄位 | 來源 | 為什麼 AI 需要 |
|---|---|---|
| 既有 GMC 全集（30 §6.1） | feed 生成器 | 代理與購物平台共用同一份事實 |
| `policy_refs`（退貨／運送／保固） | shop policies（可翻譯，29 §2.1 `SHOP_POLICY`） | 事實 12：政策完整度被明列；代理答不出退貨政策就不會推薦 |
| `qa_entries`（結構化問答） | §H.5 的 `knowledge_entries` | 對應 `search_shop_policies_and_faqs` 這類工具 |
| `option_semantics`（選項名與值的語義標註） | 商品選項 ＋ 分類法（59 §3-4：類別驅動稅率與中繼欄位） | 事實 12 明列「變體（含選項名）」；`容量 230ml` 要能被理解成 volume=230ml 才進得了「找 200ml 以上的精華」這種查詢 |

**（b）查詢端點**（我方等價物，命名對齊 Shopify 以利生態移植）

```
POST /api/agents/catalog/search    ≈ search_catalog
POST /api/agents/catalog/lookup    ≈ lookup_catalog
GET  /api/agents/catalog/product   ≈ get_product
POST /api/agents/faq/search        ≈ search_shop_policies_and_faqs
```
**四條硬要求**：①回應的價格／供貨**必走 §A.3 的 `resolve_price_view()`**（第 5 個消費者）；②必須接受 `country`／`language` 參數並據以解析市場（沒有參數時用 primary market 並在回應中**明示**用了哪個市場，不要靜默）；③未發佈到該市場 catalog 的商品**不得出現**（29 §1.3）；④免認證的公開端點必須有成本型限流（28 §0），且**不得**洩漏庫存精確數（回 `InStock`/`OutOfStock` 級別即可，避免競品即時掃庫存）。

**（c）商家控制面**：逐通路開關（對齊事實 10/11 的形態：能限制個別 AI 通路），但**平台層的目錄可見性不可退出**——理由與 Shopify 相同：那是平台的分發底座；商家真正想關的是「哪個通路能拿」。

> ⚠️ **V-121**：Shopify Catalog 的商品「符合資格」條件具體清單，help 頁未列出。
> ⚠️ **V-122**：各 AI 通路（ChatGPT／Copilot／Gemini／Meta）對商品欄位的硬性要求與拒登原因碼，官方未公開逐欄規格。**我方在取得前，商品資料完整度的門檻一律以 GMC 規格為準**（超集策略的好處：不必猜）。

### H.5 內容結構化、FAQ、問答式標題

**（a）FAQ：內容要做，`FAQPage` JSON-LD 不做**

Google 已於 2026-05 移除 FAQ 富摘要（30 §2.4 ＋ 本輪覆核）。但代理側明確要吃政策與 FAQ（事實 9 的 `search_shop_policies_and_faqs`、事實 12 的政策完整度）。**通路換了，需求沒有消失。** 因此：

```
knowledge_entries(shop_id, kind, question, answer, locale, market_id NULL=全域,
                  source_type, source_id, position, published, updated_at)
  kind ∈ {policy, shipping, returns, sizing, care, product_qa, store_qa}
  index [shop_id, kind, locale]
```
一份資料**三個出口**：①前台可展開區塊（人看）②`/api/agents/faq/search`（代理看）③商品頁的規格區（結構化欄位）。**不出 `FAQPage` JSON-LD**（可留一個預設關閉的開關，若 Google 日後恢復再開）。

**（b）問答式標題（H2/H3 寫成問句）**

學術面只有 GEO 論文（事實 14）給出「引用來源、統計數字、引述可提升可見度，最高 40%，且領域差異大」的結論；**「問答式標題提升 AI 引用率」本輪沒有找到可靠的一手證據** ⇒ **V-125**。因此我方的處置是：

- **平台不強制、不自動改寫標題**。
- 主題預設模板在**適合的位置**（配送與退貨、尺寸、材質保養）用問句 H3，因為那本來就是使用者的問法，對人也好讀——**理由寫成「可讀性」，不寫成「AI 排名」**。
- 後台文案**不得**宣稱問答式標題會提升 AI 曝光（V-125 未結案前，那是行銷話術不是規格）。

**（c）真正有依據的內容結構化三條**（對齊事實 1/2/12 與 GEO 論文）

1. **事實密度**：規格、材質、尺寸、產地、保養、相容性做成**結構化欄位**（metafield 定義），而不是塞進描述的自由文字。理由：欄位能同時餵富摘要、feed、代理端點三條路；自由文字只餵一條。
2. **可歸因的敘述**：可驗證的數字（容量、成分濃度、認證編號）優於形容詞。GEO 論文支持「統計與引用」方向，且對人也有效。
3. **政策完整**（退貨天數、運費門檻、配送時效）——代理答不出來就不推薦；同時這些也是 `Offer.hasMerchantReturnPolicy` / `shippingDetails` 的來源（30 §2.2），**同一份資料兩個用途**。

### H.6 GEO-G 與傳統 SEO 的衝突與重疊（誠實表）

| # | 議題 | 重疊（兩邊都好） | 衝突（必須取捨） | 我方處置 |
|---|---|---|---|---|
| 1 | 內容完整度 | 結構化欄位、政策、規格：SEO 富摘要與代理端點共用 | **大量 AI 生成的商品文案**：對 AI 通路是「內容完整」，對 Google 是 **scaled content abuse**（30 §1.2，可能整站受罰） | AI 產文一律落 `content_source` 稽核欄；後台對「一次生成 >N 篇」加摩擦與警告 |
| 2 | `llms.txt` 類檔案 | — | Google 明說不需要（事實 2/3）；業界又在推 | §H.2：零成本別名做，內容策展不做；<!-- 依 68 §C-1 修正，原文：「`llms-full.txt` 預設關」 -->**三條路徑預設全開**（Shopify 的 `llms-full.txt` 是別名不是打包） |
| 3 | 訓練型爬蟲 | — | 封鎖保護內容，但可能減少品牌在模型中的內化；**效果無公開實驗**（V-123） | 分成三組開關（§D.3），文案只陳述官方定義，不宣稱效果 |
| 4 | 代理內直接結帳 | 轉換路徑短、成交快 | **買家不再進站**：分析、再行銷、CWV 樣本、A/B 測試全部失去該次 session；歸因模型要改 | 代理訂單必須帶 `channel=agentic` 與代理識別；分析頁把代理成交**單獨一軸**，不混進自然搜尋 |
| 5 | 即時價格／庫存開放 | 代理報價準確＝更可能被推薦 | 等於對競品開放即時比價與庫存掃描 | §H.4(b)④：供貨只回級別不回數量；限流；可設定的延遲/快取 |
| 6 | FAQ 區塊 | 對人有用、對代理有用 | 對 Google **不再有富摘要回報**，卻仍吃頁面重量與 CLS 風險 | 做內容、不做 `FAQPage`；區塊預設收合並鎖定高度（§G 風險 4） |
| 7 | 多市場 | 傳統 SEO 用 hreflang 精準分流 | **代理側沒有 hreflang 這回事**：`agents.md` 不可在地化、只有一個 currency（事實 7）→ 多市場商家在代理通路可能被報錯幣別 | V-114；在結案前，代理端點**強制要求 `country` 參數**並在回應明示解析到的市場（§H.4(b)②） |
| 8 | 結構化資料 | Google 富摘要要它，代理也吃它 | Google 官方說「沒有為 AI 而生的特殊 schema」（事實 2）——**不要為了 AI 去發明自訂 schema 型別** | 只用 schema.org 標準型別；擴充走 metafield 與 §H.4 的欄位，不發明 JSON-LD 型別 |

### H.7 可觀測（不做這個，上面全是信仰）

- **AI 流量分軸**：以 UA（`OAI-SearchBot`／`GPTBot`／`ChatGPT-User`／`Google-Extended`／`PerplexityBot`…）與 referrer（`chat.openai.com` 等）切出「AI 抓取」與「AI 導流」兩條線，**分開看**。抓取多而導流零，代表被讀但沒被引用。
- **端點命中率**：`/agents.md`、`/llms.txt`、`/.well-known/ucp`、代理 catalog 端點各自的請求數與 UA 分布 ⇒ 這是 **V-118 的結案資料**。
- **代理成交**：`channel=agentic` 的訂單數／AOV／退款率，與自然搜尋分開比較。
- 全部進 M8 的指標 dashboard（HANDOFF §5）。

---

# GEO-R（地理／多市場）

## I. hreflang 完整矩陣

### I.1 生成演算法（唯一實作，sitemap 與 `<head>` 共用）

<!-- 依 2026-08-13 locale 碼裁定修正第 4–5 行（§I.2）。原文（保留供追溯，🔴 不得改回）：
       entries = presences.flat_map { |wp|
           wp.locales.map { |loc| Entry(code: hreflang_code(wp.market, loc),
                                        url:  absolute_url(resource, wp, loc)) } }
     🔴 改動有二，且**第二條才是會咬人的那個**：
        ① `hreflang_code`（單數）改成 `hreflang_codes`（複數，回傳 Set）——多國市場逐國展開；
        ② `wp.locales` 改成 `open_locales(wp)`——per-market 語言白名單（67 §A.5）。
           原文的 `wp.locales` 讀起來像「這個 presence 上掛的全部語言」，
           在白名單引進後那是**商店啟用集**而不是**該市場對買家開放集**；
           照原文寫會把沒開放的語言也放進 hreflang，而那些 URL 依 67 §F.1(c) 是 **404**
           ⇒ 直接違反下面不變量 4（矩陣內每個 URL 必須回 200）。 -->
```
def hreflang_set(resource, shop):
  presences = active_markets(shop)                      # 排除 draft market（§C 規則 1）
      .flat_map { |m| resolved_web_presences(m) }       # 🔴 resolved = 沿 lineage 累加（§I.3）
  entries = presences.flat_map { |wp|
      open_locales(wp).flat_map { |loc|                 # 🔴 白名單 ∩ published（67 §A.5／§C.8）
        hreflang_codes(wp.market, loc).map { |code|     # 🔴 複數：多國市場逐國展開（§I.2）
          Entry(code: code, url: absolute_url(resource, wp, loc)) } } }
  entries = entries.reject { |e| !resource.published_in?(e.market) }   # 未發佈到該市場 catalog ⇒ 不列
  entries = dedupe_codes(entries)                        # §I.3(c) 碼衝突解析
  entries + [Entry(code: 'x-default', url: x_default_url(shop))]
```

**四條硬性不變量**（§O REG-6 逐條測）：
1. **自指**：集合必含當前頁自己的條目。
2. **雙向**：集合內任兩個 URL 互相列出彼此（Google 明文：不雙向可能被忽略）。實作上因為是同一個函式產生同一個集合，天然雙向——**因此禁止任何「按頁客製」的 hreflang 例外**。
3. **絕對 URL**、含最終網域與 scheme、percent-encoded。
4. **每個 URL 對任何客戶端回 200 且 self-canonical**（§0.2 原則 4）。

### I.2 碼的粒度規則 —— 🔴 **一律「語言＋地區」，永不輸出裸語言碼**（2026-08-13 裁定覆蓋 Shopify 行為）

<!-- 🔴 2026-08-13 使用者裁定推翻本節原有的碼粒度規則。裁定逐字（重點句）：
     「不同地區如果同樣有英文，那就在 url 加入識別，香港就是 en-HK，如果加拿大，那就是 en-CA；
       共用繁體中文，那香港就是 zh-Hant-HK，台灣就是 zh-Hant-TW，以此類推。
       這是考慮到之後 SEO，和進行區分，避免被 google 等搜索引擎誤判為重複頁面。」
     （原文「如果加拿大，那就是 ca-HK」研判為筆誤——同句前半已給 en-HK，且 ca-HK 不是合法 BCP-47
       語言碼組合；本檔採 en-CA，並在 §I.2-1「裁定若改」欄註記此研判。）

     本節原文（保留供追溯，🔴 **任何人不得改回**）：
       ### I.2 碼的粒度規則（對齊實測到的 Shopify 行為）
       hreflang_code(market, locale):
         base = locale.language                       # ISO 639-1
         base += "-" + locale.script if locale.script # ISO 15924，例 Hant（google 明確支援 zh-Hant）
         return base + "-" + market.single_country if market.regions.size == 1   # ISO 3166-1 alpha-2
         return base                                  # 多國市場 ⇒ 語言碼
       「- **單國市場 → 區域限定**（`fr-ca`）；**多國市場 → 語言碼**（`fr`）。
          此形態取自 `help`／`dev` 對 Shopify 行為的描述。」

     🔴 **原規則沒有錯，它只是不再是我方的規則。** 它忠實描述了 Shopify 的行為（`help`／`dev`，
        62 §0.4-3 登記的查證結果），我方當時的判斷是「對齊本尊」。2026-08-13 裁定把判準換成
        「地區必須可從 URL 與標註碼區分」⇒ 「多國市場退回裸語言碼」這一半**與裁定直接衝突**，
        因為它正是「同樣有英文卻不加識別」的那個情形。
     🔴 **這是使用者裁定覆蓋 Shopify 行為，不是我方發現 Shopify 寫錯。** 比照 §F.3-1 的既有寫法，
        明知偏離登記在下面的 §I.2-1，避免下一輪稽核當成遺漏重新開單。 -->

**🔴 `hreflang_code()` 的回傳型別從「一個碼」改成「一組碼」。這是本次修改最容易漏的一件事。**

```
hreflang_codes(market, locale) -> Set<String>      # 🔴 複數。原函式名 hreflang_code 已停用
  base = locale.language                           # ISO 639-1
  base += "-" + locale.script if locale.script     # ISO 15924，例 Hant（google 明確支援 zh-Hant）
  countries = market.regions                       # ISO 3166-1 alpha-2，>=1 個
  🔴 assert countries.size >= 1                    # 空集合 ⇒ raise，不得退回裸語言碼
  return countries.map { |c| base + "-" + c }      # 單國 ⇒ 1 個；多國 ⇒ N 個，全部指向同一 URL
```

| 情形 | 舊規則（Shopify 行為） | 🔴 新規則（裁定） |
|---|---|---|
| 單國市場 HK ＋ `en` | `en-hk` | `en-HK`（**不變**） |
| 單國市場 CA ＋ `en` | `en-ca` | `en-CA`（**不變**） |
| 單國市場 HK ＋ `zh-Hant` | `zh-Hant-HK` | `zh-Hant-HK`（**不變**） |
| 單國市場 TW ＋ `zh-Hant` | `zh-Hant-TW` | `zh-Hant-TW`（**不變**） |
| **多國市場 EU（FR/DE/BE）＋ `en`** | **`en`**（一個碼） | 🔴 **`en-FR`／`en-DE`／`en-BE`（三個碼，同一個 URL）** |
| **多國市場 APAC（SG/MY）＋ `en`** | **`en`**（一個碼） | 🔴 **`en-SG`／`en-MY`（兩個碼，同一個 URL）** |

- 🔴 **裸語言碼一律禁止**（`limits.seo.hreflang.bare_language_code_forbidden: true`）：任何輸出中出現不帶 ISO 3166-1 地區後綴的 hreflang 值（`en`、`zh-Hant`、`fr`）即 **CI 紅燈**。唯一例外是 **`x-default`**，它本來就不是語言碼。
- **`x-default`**：指**主網域上、primary market 的預設語言**對應的資源 URL。🔴 **在本次修改後它不再指「無前綴的根路徑」**——因為根路徑已不再是內容頁（67 §F.1(b)：`/` 一律重導到預設 (market, locale) 前綴）。x-default 必須指向那個**帶前綴且回 200** 的 URL，否則 §0.2 原則 4 破裂。
- 大小寫：輸出小寫語言、Title case script、**大寫地區**（`zh-Hant-HK`）——Google 不區分大小寫，但一致性讓 diff 測試可行。🔴 **URL 前綴的大小寫規則不同**（全小寫，`/zh-hant-hk`），兩者**不得互相借用**，理由見 67 §F.1(a)。

#### I.2-1 🔴 明知偏離 Shopify 的一條：hreflang 碼恆帶地區（比照 §F.3-1 的登記形態）

| | 內容 |
|---|---|
| **Shopify 的實際行為** | **單國市場 → 語言-國家碼；多國市場 → 裸語言碼。** 出處：`help.shopify.com/manual/markets/seo` ＋ `shopify.dev/docs/storefronts/themes/seo/hreflang`（`help`／`dev`，查證日 2026-08-12，登記於 §0.4-3）。本尊在多國市場下**就是**輸出 `fr`／`en` 這類裸碼 |
| **我方的行為** | **恆帶 ISO 3166-1 地區**（`limits.seo.hreflang.always_region_qualified: true`）。多國市場**逐國展開**成 N 個碼，全部指向同一個 URL |
| **偏離的唯一依據** | 🔴 **使用者 2026-08-13 裁定**：「不同地區如果同樣有英文，那就在 url 加入識別……這是考慮到之後 SEO，和進行區分，避免被 google 等搜索引擎誤判為重複頁面。」**裁定 > Shopify**（沿用 68 §0 凌駕規則 1）。**不是**技術判斷、**不是** Google 規則要求、**不是**查不到而保守 |
| **合法性** | ✅ **碼本身合法**：Google 的 localized-versions 頁定義 hreflang 值＝ISO 639-1 (+ 可選 ISO 15924) (+ 可選 ISO 3166-1 alpha-2)（`google`，§0.4-5）⇒ `en-BE`、`zh-Hant-TW` 都在值域內。**偏離的是「什麼時候加地區」的產品選擇，不是碼的合法性** |
| **代價（誠實記錄，不寫「兩邊都好」）** | ① 多國市場的條目數從 1 變成 N（EU 27 國市場 ⇒ 27 條指向同一 URL），矩陣體積與 `<head>` 大小按國家數放大 ⇒ 受 `limits.seo.hreflang.max_expanded_countries_per_market: 40` 約束，超限的處置見 §I.3(c)；② **`x-default` 的定義被連帶改掉**（不再是根路徑）；③ 與 Shopify 匯入／匯出的 hreflang 對照不再逐字相同，遷移比對工具要知道這件事 |
| **裁定若改** | 本條、`limits.seo.hreflang.always_region_qualified`／`bare_language_code_forbidden`、`limits.i18n.locale_prefix.*` 整組、以及 67 §F.1 **必須連帶重審**。單獨改任何一個都會產生半套狀態（例如 URL 帶地區但 hreflang 不帶 ⇒ 自指不變量破裂）。<br>⚠ **另含一個研判**：裁定原文的 `ca-HK` 我方研判為 `en-CA` 的筆誤（**V-222**）。若研判錯誤，受影響的只有「加拿大那一列的字面值」，**不影響本條的規則本身** |

#### I.2-2 這對 Google 的重複內容判定是好是壞 —— 🔴 **使用者的動機正是這個，所以要寫清楚**

裁定的理由句是「**避免被 google 等搜索引擎誤判為重複頁面**」。這個動機**部分成立、部分不成立**，兩半都要寫，否則下一個人會拿「SEO 需要」去推導出本節沒有支持的結論。

**先把兩個事實分開（事實 vs 推論，分開標）**

| | 內容 | 等級 |
|---|---|---|
| 事實 1 | hreflang 的作用是**告訴搜尋引擎「同一內容的其他在地化版本在哪」，讓它把對的版本送給對的使用者**；它是**服務（serving）訊號** | `google`（localized-versions，§附錄 B 已引） |
| 事實 2 | Google 對多地區網站的重複內容處置：**同一內容的不同國別版本一般不會因此受罰**，處理方式是重複內容的既有機制（canonical／群集），不是懲罰 | `google`（managing-multi-regional-sites，§附錄 B 已引） |
| 事實 3 | 我方既有定案：**跨市場一律 self-canonical，不跨市場 canonical**（§B.4，V-120） | `ours` |
| 🔵 推論 A | 碼變細**不會**改變 Google 是否把兩個 URL 視為重複——那由 URL 與內容決定，**不由標註碼決定** | 推論（我方） |
| 🔵 推論 B | 碼變細**會**改善「送錯版本」的機率：`en` 對 EU 27 國是一個籠統宣告，`en-BE` 是明確宣告 | 推論（我方） |
| 🔵 推論 C | 碼變細**不會**讓「同一個 URL」變成兩個頁面。`inherit_primary` 之下 HK 與 SG 市場共用同一條 URL（§J.2），此時 `en-HK` 與 `en-SG` 指向**逐位元組相同的一條 URL** ⇒ 這不是「兩個重複頁面」，它**根本只有一個頁面** | 推論（我方） |

**⇒ 結論（三句，任何人要引用本節請整組引用）**

1. 🔴 **「加了地區碼就不會被判重複」是不成立的。** 判重複與否看的是 URL 與內容；hreflang 是服務訊號不是去重訊號。**本節不背書這個因果。**
2. ✅ **但裁定的方向仍然對，只是機制不同**：真正降低「被誤判／被誤送」風險的是「**每個 (市場, 語言) 有一條專屬且穩定的 URL，並被一個明確的碼指到**」。恆帶地區把**碼**這一半做到了；**URL** 那一半由 67 §F.1 的前綴規則做到（前綴 ≡ (market, locale) 身分）。**兩半合起來才是裁定要的東西，只做一半沒有意義。**
3. 🔴 **真正會被判成重複的形態，本次修改沒有動到它，而且它更嚴重**：兩個市場共用同一條 URL 時（`inherit_primary` 常態，§J.2）內容是同一份；以及**根路徑與預設語言頁並存**（`/` 與 `/en-hk/` 內容相同）。後者是我方自己會製造的重複，處置見 67 §F.1(b)——`/` 不是內容頁，一律重導。**這一條的實際 SEO 收益比碼粒度大得多。**

⚠ **未查證**：Google 是否會因 hreflang 碼粒度變細而改變其重複內容群集或 canonical 選擇 ⇒ **V-220**。結案前一律按上面三句實作，**後台文案不得宣稱「加地區碼可避免重複頁面判定」**（同 §H.6-3／§D.3 的既有紀律：只陳述機制，不宣稱效果）。

### I.3 與 Markets 父子繼承（P0-02）的對應——**本節是使用者點名要的**

29 §1.5 的繼承語義：`catalogs` 與 `webPresences` 是**累加（additive）**，其餘是**覆寫**。落到 hreflang：

**(a) 用「解析後」的 web presence 集合，不是市場自己那一列。**
子市場的 web presence 集合 ＝ 自身 ∪ 沿 lineage 上溯的全部（`limits.market.inheritance_additive` 已含 `web_presences`）。因此 `hreflang_set` 第二行必須呼叫 `resolved_web_presences(m)`，**不是** `m.web_presences`。

<!-- 依 68 號 §C-2 補（2026-08-12）：新市場預設 `inherit_primary` 之後，本條的**常態**變了。 -->
🔴 **新市場預設 `inherit_primary`（§J.2）讓「繼承來的 web presence」從邊緣情形變成常態**，實作上要接住兩件事：**①** 一個沒有自己網域／子資料夾的市場**不產生新 URL**，它只是讓同一個 URL 多掛一個 hreflang 碼——**同一 URL 對多碼是合法的**；**②** `dedupe_codes`（§I.3(c)）處理的是**同碼多 URL**，**不得**把 ① 也當成衝突去刪，否則繼承市場的條目會被誤刪、雙向性隨即破裂。若寫成後者，子市場的頁面會漏掉繼承自父市場的語言版本，hreflang 集合不完整 ⇒ 雙向性破裂 ⇒ 整組標註可能被忽略。**這是 P0-02 的繼承模型在 SEO 面最直接、也最容易漏的後果。**

**(b) 父子關係是推導的，所以 hreflang 是「market conditions 的函式」。**
`markets.derived_parent_market_id` 是物化快取（29 §1.5(a)）。任一 market 的 conditions 變更 ⇒ 受影響子樹重算 ⇒ **hreflang 矩陣與 sitemap 必須同步失效**。實作：market conditions 變更事件 → 失效 `hreflang_matrix:{shop_id}` 快取 → 觸發 sitemap 重生 ＋ IndexNow 批次（30 §9-9，去抖 ≥5 分鐘）。**漏掉這個掛鉤，商家改了市場範圍，hreflang 會停在舊值好幾天**——與 55 §D G-03「掛勾寫了沒接上」同一類病根。

**(c) 碼衝突解析（官方未載明 ⇒ V-111，我方定案）**

<!-- 🔴 依 2026-08-13 locale 碼裁定改寫（§I.2）。原文（保留供追溯，**任何人不得改回**）：
       「兩個多國市場都以英文為預設（例：EU 多國市場與 APAC 多國市場）會各自產生 `hreflang="en"`，
         同一個集合裡出現兩個同碼條目＝無效標註。
         dedupe_codes: 若同一 code 出現 >1 次：
           1. 嘗試「展開」——把該碼的每個市場展開成 語言-國家 逐國條目
              （市場國家數 ≤ limits.seo.hreflang.max_expanded_countries_per_market）
           2. 展開後仍衝突（同一國家屬於兩個 active market —— 29 §1.1 已禁止重疊，理論上不會發生）
              ⇒ 取 specificity_stack 較高者，另一者丟棄
           3. 任一次進入 (1) 或 (2) ⇒ 落一列 seo_lint_findings 並在後台 Markets 頁顯示警示」

     🔴 **恆帶地區之後，原文步驟 1 描述的那個衝突源頭消失了，但演算法不能刪——原因很反直覺，
        寫在下面「殘留衝突源」一段。** 最大的陷阱是：**原文的步驟 2 從「理論上不會發生」
        變成「唯一還會被走到的分支」**，而它的動作是「丟棄一個條目」。若沒有人注意到這個
        重心轉移，一條原本寫來當保險絲的分支會在正常運作中默默丟掉 hreflang 條目。 -->

**🔴 恆帶地區把「同碼多 URL」這個問題**大幅**縮小了，但沒有消滅它。四種情形要分清楚：**

| # | 情形 | 舊規則 | 🔴 新規則（§I.2） |
|---|---|---|---|
| 1 | 兩個多國市場都以英文為預設（EU ＋ APAC） | 兩個 `en` ⇒ **同碼多 URL，衝突** | ✅ **消失**：展開成 `en-FR/en-DE/…` 與 `en-SG/en-MY/…`，逐國碼互不相同（29 §1.1 已禁止 active market 的國家重疊） |
| 2 | 一個市場、一個 locale、多個**繼承來的** web presence（自身有子資料夾 ＋ 沿 lineage 上溯到父市場的 presence，§I.3(a) 的 resolved 集合是**聯集**） | 同碼多 URL，衝突 | 🔴 **不變，仍然衝突**——碼由 (market, locale) 決定，**與 presence 無關**，所以展開對它無效 |
| 3 | 同一 URL 掛多個碼（`inherit_primary` 常態，§J.2） | 合法 | ✅ **仍然合法，而且變成常態的常態**（多國市場現在也走這條） |
| 4 | 多國市場的國家數 > `max_expanded_countries_per_market` | 展開被上限擋下 ⇒ 落回步驟 2 | 🔴 **不能落回步驟 2**——步驟 2 會丟碼，而現在「不展開」不再是合法輸出（裸碼被禁）。處置見下 |

```
dedupe_codes: 若同一 code 出現 >1 次：
  0. 🔴 **前置斷言**：任一 entry 的 code 不含 ISO 3166-1 地區後綴 ⇒ raise
     （裸碼在恆帶地區規則下是**上游 bug**，不是本函式該吸收的輸入）
  1. ~~嘗試「展開」~~ ⇒ 🔴 **已在 hreflang_codes() 上游完成**（§I.2）。
     本步驟保留為 **no-op ＋ 斷言**：進到 dedupe 的條目**必然已是逐國碼**，
     所以「展開」對殘留衝突（上表情形 2）**永遠無效**——不得再嘗試，否則會是無限迴圈的形狀
  2. 🔴 **本步驟現在是唯一會被走到的分支，且它會丟棄條目 ⇒ 判準必須收緊**：
     殘留衝突只有一種來源＝**同一 (market, locale) 對應多個 web presence**（resolved 是聯集）。
     ⇒ 不用 specificity_stack（那是拿來比**市場**的，這裡兩邊是同一個市場，比不出東西）。
     ⇒ 改用 **canonical presence 規則**：取該市場的 `own presence`（自身那一列）；
        若該市場沒有自己的 presence（inherit_primary），取 lineage 上**最近**的祖先 presence。
        `limits.seo.hreflang.multi_presence_resolution: nearest_own_then_ancestor`
     🔴 被丟棄的那條 URL **不是垃圾**——它照樣可達、照樣 self-canonical（§B.4），
        只是**不作為該碼的 hreflang 目標**。不得因為它沒進矩陣就把它 noindex 或 404
  3. 國家數超過 max_expanded_countries_per_market ⇒ 🔴 **不得截斷、不得退回裸碼**：
     落 seo_lint_findings（severity: blocking）＋ 後台 Markets 頁顯示「此市場國家數超出 hreflang 展開上限」，
     並**照樣輸出上限數量的條目**（部分標註優於無效標註）。
     `limits.seo.hreflang.over_limit_action: emit_partial_and_lint`
  4. 任一次進入 (2) 或 (3) ⇒ 落一列 seo_lint_findings 並在後台 Markets 頁顯示警示
```
**不得靜默丟棄**（同 56 §A.3 的 `silent_skip_forbidden` 精神）。

🔴 **雙向性（§I.1 不變量 2）在本次修改後仍然成立，理由與原本相同但必須重新確認一次**：所有條目由**同一個** `hreflang_set()` 產生同一個集合，所以任兩個 URL 互指是天然的。**恆帶地區沒有破壞這一點**，因為展開發生在**碼**這一維，集合的成員（URL）不變。🔴 **會破壞它的是步驟 2**——它丟的是 (code, URL) 條目：若 A 頁面丟了指向 B 的條目、B 頁面沒丟指向 A 的條目，雙向性就破了。因此步驟 2 的 `nearest_own_then_ancestor` **必須是純函式（只看 market lineage，不看「當前是哪一頁」）**，這樣每一頁算出來的丟棄決定完全相同。`limits.seo.hreflang.dedupe_must_be_page_independent: true`，驗收見 §O REG-2b。

**(d) 繼承徽章與 SEO 的關係**：Markets 詳情頁的「繼承／已覆寫」分區（29 §1.5(d)）在網域與語言維度上，要**同時顯示該市場最終產生的 hreflang 碼**。
<!-- 依 2026-08-13 裁定（§I.2）改寫理由。原文：「理由：商家看得懂『繼承自上層』，但看不懂那會讓自己的頁面掛上 `en` 而不是 `en-sg`。」
     🔴 原文舉的那個例子在恆帶地區之後**不可能發生了**（永遠不會掛 `en`）——但這一節的必要性
        不但沒有降低，反而升高：多國市場現在會一次掛上 N 個碼，而商家在 UI 上只看到「繼承自上層」四個字。 -->
🔴 **理由在恆帶地區之後換了，需求更強**：商家不再需要擔心「掛上 `en` 而不是 `en-sg`」（那個形態已被 §I.2 消滅），但**多國市場現在一次產生 N 個碼**（EU 市場 27 國 ⇒ 27 條），而 UI 上只寫「繼承自上層」。⇒ 該分區必須顯示 **①最終碼的完整清單（可摺疊）②條目總數 ③是否觸及 `max_expanded_countries_per_market`**。**條目數是商家唯一能看懂的「這個決定有多大」的指標**，缺了它，商家把一個 27 國市場開起來時完全不知道自己的每一頁 `<head>` 多了 27 行。

**(e) 🔴 per-market 語言白名單接進本節的方式（2026-08-13 新增）**：67 §A.5 引進「某市場對買家開放哪些語言」之後，(a) 的 `resolved_web_presences(m)` **不變**，變的是 §I.1 第 4 行——`wp.locales` 改成 `open_locales(wp)`。
- **白名單沿 lineage 累加**，與 `web_presences` 同一條語義（`limits.market.inheritance_additive` 已含 `web_presences`，白名單掛在 presence 上 ⇒ 自動繼承同一條規則）。🔴 **子市場不得「減掉」父市場開放的語言**，理由與後果見 67 §A.5(d)——一句話版本：**減法會讓 `resolved_*` 從聯集變成「聯集減去某些例外」，而例外集合是 per-market 的 ⇒ 雙向性再也無法用「同一個函式同一個集合」來保證**。
- **白名單變更 ⇒ 走 (b) 的同一條失效管線**（去抖 5 分鐘），觸發條件表要加上 `market_web_presence_locales`（67 §M-6 已登記）。

### I.4 語言碼白名單與 HK 基準

- 白名單：ISO 639-1 **＋ 可選 ISO 15924 script ＋ 🔴 必要 ISO 3166-1 alpha-2**。**`es-419` 等非標準地區碼不支援**（30 §9-12）；`EU`／`UK` 一類非 ISO 3166 地區碼一律拒（Google 明列為常見錯誤）。
  <!-- 依 2026-08-13 裁定（§I.2）把「可選 ISO 3166-1 alpha-2」改為「必要」。
       原文：「白名單：ISO 639-1（+ 可選 ISO 15924 script + 可選 ISO 3166-1 alpha-2）。」
       🔴 改的是**我方輸出的值域**，**不是 Google 的值域**——Google 那一邊地區碼仍然是可選的
          （`google`，localized-versions），我方只是永遠不用那個選項。
          兩者不要混寫成一句，否則下一輪會有人以為 Google 規則變了。 -->
- 🔴 **值域收窄的方向只有一個：我方輸出恆帶地區（§I.2），但驗證器仍必須「能認得」不帶地區的碼**——因為 hreflang 驗證器同時用於**巡檢外部輸入**（商家自訂標註、匯入的主題、遷移自 Shopify 的既有頁面）。認得 ≠ 允許輸出：巡檢到裸碼一律報 `seo_lint_findings`，我方自己產生裸碼一律 CI 紅燈。**兩個檢查點，兩種嚴重度，不得合併成一個布林。**
- **香港基準（鐵律 11）**：繁體中文＝`zh-Hant`，HK 市場＝**`zh-Hant-HK`**。**不得**借用 `zh-TW` 表示繁體（那是台灣地區碼，不是字體），也不得寫死任何台灣條目——TW 若日後啟用，是 `zh-Hant-TW`，由 market 設定推導。**裁定 2026-08-13 逐字給的 `zh-Hant-HK`／`zh-Hant-TW` 與本條既有定案完全一致**（裁定是確認，不是變更）。
- 🔴 **`zh-Hant` 這個標籤本身仍然存在，而且必須存在**——它是 `platform_locales.tag`（**語言**的身分，67 §C.1）。恆帶地區改的是**輸出的碼**（hreflang 值、URL 前綴），**不是語言註冊表**。把 `zh-Hant-HK` 存進 `platform_locales` 是本次修改最容易犯的錯，理由與後果見 67 §C.1 規則 1。
- 語言從市場移除 ⇒ 該語言 URL 立即 404（29 §1.2）⇒ **必須同時從 hreflang 與 sitemap 移除**（否則指向 404 = 不變量 4 破裂）。這條掛鉤與 (b) 同一個失效管線。**per-market 語言白名單（67 §A.5）走的是同一條路徑**：把某語言從某市場的白名單移除 ＝ 從該市場移除語言，兩者不是兩套機制。

---

## J. 多市場網域策略

### J.1 三選一的 SEO 後果（Google 官方 pros/cons ＋ Shopify 描述）

| 策略 | Google 記載的取捨 | Shopify 描述的 SEO 後果 | 我方額外的營運成本 |
|---|---|---|---|
| **子資料夾** `example.com/fr-ca` | 易建置、維護成本低；但單一伺服器位置、站點區隔困難 | 與主網域**共享網域權重** | 最低：一張憑證、一組 DNS |
| **子網域** `ca.example.com` | 易建置、伺服器位置靈活；使用者不易從 URL 認出地理定位 | **部分搜尋引擎視為獨立站點**，需自行累積權重 | 萬用憑證即可；但需獨立 sitemap 與 GSC 資源 |
| **獨立網域** `example.ca` | 地理定位訊號最明確、伺服器位置無關；但昂貴、基礎設施較多 | 提供**最強的在地 SEO 訊號** | 最高：逐域註冊/續約、憑證、GSC、可能的在地法遵 |
| URL 參數 `?loc=de` | **官方不建議** | — | **我方不提供** |

Shopify 模型的硬約束（29 §1.2）：`MarketWebPresence` 的 `domain` 與 `subfolderSuffix` **互斥（XOR）**；**語言-only 子資料夾（`/fr`）僅限 primary market**，次級市場一律 `語言-國家`（`/fr-ca`）。~~我方 1:1 復刻，並在路由 constraint 層寫死這條規則（29 §9-5）。~~

<!-- 依 2026-08-13 locale 碼裁定修正末句（§I.2 ＋ 67 §F.1(b)）。
     原末句（保留供追溯，🔴 不得改回）：「我方 1:1 復刻，並在路由 constraint 層寫死這條規則（29 §9-5）。」
     🔴 **「1:1 復刻」在裁定之後是錯的**：裁定禁止裸語言前綴，而本尊的規則裡
        「語言-only 子資料夾僅限 primary market」**明文允許** primary market 用 `/fr`。
        ⇒ 我方復刻的是 **XOR** 那一半，**不是** 語言-only 那一半。 -->
🔴 **我方的處置（2026-08-13 裁定後）：XOR 照抄，語言-only 子資料夾整條廢除。**

| 本尊的約束 | 我方 | 依據 |
|---|---|---|
| `domain` 與 `subfolderSuffix` **XOR** | ✅ **1:1 復刻**，路由 constraint 層寫死（29 §9-5） | `dev`／29 §1.2 |
| 語言-only 子資料夾（`/fr`）僅限 primary market | 🔴 **廢除——我方沒有語言-only 子資料夾這個形態**，primary market 也一樣。所有前綴恆為 `語言[-字體]-地區`（`/en-hk`、`/zh-hant-tw`） | **裁定**（§I.2-1、67 §F.1(b)） |
| 次級市場一律 `語言-國家`（`/fr-ca`） | ✅ **一致**——只是在我方這是**唯一**形態，不是「次級市場的特例」 | 裁定 ＋ `dev` 恰好同向 |

⇒ **路由 constraint 從「兩條規則（primary 可用語言-only／次級必須語言-國家）」簡化成一條**：`url_prefix` 必須匹配 `^[a-z]{2,3}(-[a-z]{4})?-[a-z]{2}$`。**這是恆帶地區少數幾個讓實作變簡單的地方**，其餘多半是變複雜（§I.2-1 代價欄）。

### J.2 我方預設與選擇準則（不寫死國別）

<!-- 依 68 號 §C-2 跟隨 Shopify 做法修正（2026-08-12）。
     原文（保留供追溯，🔴 任何人不得改回）：
       「**預設＝子資料夾。** 理由：新租戶沒有網域權重可分，共享主網域是最快進索引的路徑，
         且成本最低。」
     🔴 **原文把「預設值」與「建議值」壓成了一個值——Shopify 刻意把它們拆開，我方照做。**
        Shopify 的兩個事實方向相反、但不矛盾：
          建議值（help，managing-international-domains）：首次設定國際銷售**建議**子資料夾；
          預設值（changelog.shopify.com/posts/subfolders-are-no-longer-created-by-default-for-new-markets，
                  **2023-05-23**）：在此之前新的單國市場會**自動建立**語言／國家子資料夾；
                  此後**新市場預設沿用 primary market 的 URL 結構**，子資料夾改為商家自行設定。
        原文的理由（共享權重、成本最低）**只支持「建議子資料夾」，不支持「自動配子資料夾」**——
        它沒有回答「商家還沒想清楚要不要多一份站點時，平台該不該替他生」。 -->

**預設值與建議值是兩件事，分開寫（跟隨 Shopify 的做法）：**

| | 值 | 出處 | 說明 |
|---|---|---|---|
| **新建市場的預設** | **繼承 primary web presence 的網域與 URL 結構**（`limits.market.web_presence.default_for_new_market: inherit_primary`） | `dev`（2023-05-23 changelog） | 🔴 **不自動配子資料夾。** 平台不替商家新增任何 URL |
| **UI 建議值** | **子資料夾**（`limits.market.web_presence.ui_recommended_strategy: subfolder`） | `help` | 商家點「設定網域」時的預選項與推薦文案；理由仍是原文那兩條（共享權重、成本最低） |

**為什麼這條不是雞毛蒜皮**：自動配子資料夾 ＝ 一次新增**一批可索引 URL ＋ 一批 hreflang 條目 ＋ 一批 sitemap 列**。Shopify 在 2023 專門為此發了一則 changelog 把它關掉，方向很明確——**多市場的 URL 增生必須是商家的明示動作**。我方若沿用「預設子資料夾」，商家每開一個市場就靜默多一份站點，而他可能只是想針對該國調個價。

**與 §I 的接縫（`inherit_primary` 的直接後果，實作時最容易漏）**：繼承 primary web presence 的市場**不產生新的 URL**，它只是讓**同一個 URL 多掛一個 hreflang 碼**。因此：

- **同一 URL 對應多個 hreflang 碼 ＝ 合法且是本預設下的常態**（`en-hk` 與 `en-sg` 同指 `example.com/products/x`）。
- **同一個碼對應多個 URL ＝ 非法**，那才是 §I.3(c) `dedupe_codes` 要處理的東西。**兩者不要搞混**：把前者也拿去 dedupe，會把繼承市場的條目誤刪，hreflang 的雙向性隨即破裂。
- 商家之後**手動**改成子資料夾時，那批 URL 才第一次出現 ⇒ 走 §J.3 的遷移路徑（新增而非搬遷，不需 301，但要進 sitemap 與矩陣並觸發失效）。

**選擇準則做成後台的決策提示，而不是硬性建議**：

```
建議獨立網域，當且僅當：該市場有在地法人/法遵要求（jurisdiction pack 宣告 requires_local_domain）
                        或 該市場的支付/物流要求在地網域
                        或 商家已擁有該 ccTLD 且有在地品牌
建議子網域：需要獨立的伺服器/CDN 拓撲或獨立團隊營運
其餘：子資料夾
```
`requires_local_domain` 是**法域能力**（56 號的 capability contract），不是 SEO 層的 if-else。**SEO 層不得出現任何國別清單**（鐵律 11）。

🔴 **上面這座階梯是「商家來問的時候給的建議」，不是「商家沒動作時系統做的事」。** 商家沒有明示選擇時，一律 `inherit_primary`——`其餘：子資料夾` 這一行講的是**推薦哪一個選項**，不是**預設幫他建哪一個**。

### J.3 遷移路徑（策略改變時）

子資料夾 → 獨立網域是一次 site move：全量 301 ≥1 年 ＋ 雙 sitemap ＋ GSC Change of Address（30 §9-6）。**平台必須擋住「直接改設定就切換」**：改網域策略要走精靈，產生重導表、保留舊 URL、並在 90 天內於 SEO 健康頁常駐監控 404/流量落差。

<!-- 依 68 號 §C-2 新增下面這一條（2026-08-12）：新市場預設 `inherit_primary` 之後，
     最常見的「策略改變」不再是子資料夾 → 獨立網域，而是 **inherit → 子資料夾**，
     而原節完全沒有涵蓋它。 -->
🔴 **`inherit_primary` → 子資料夾／子網域／獨立網域是「新增」不是「搬遷」，兩者的處置完全不同**：繼承狀態下該市場**沒有自己的 URL**（§J.2），所以沒有舊 URL 要 301，**不得**套用上面的 site move 流程（產生一批 `from == to` 的重導列是製造垃圾與重導鏈風險）。要做的是：**新 URL 進 sitemap ＋ 進 hreflang 矩陣 ＋ 觸發 §I.3(b) 的失效管線**，並在 SEO 健康頁提示「本市場新增了 N 個可索引 URL」。反向（子資料夾 → 回到 inherit）**才**是搬遷：那些 URL 已被索引，必須 301 回主網域對應頁，走上面的精靈。

---

## K. 地區重導與 SEO 的衝突

### K.1 事實

- **Google**：建議**避免**依語言自動重導；這類重導「可能讓使用者（與搜尋引擎）看不到你網站的其他版本」，且 IP 定位判斷不可靠、可能導致 Google 無法正確抓取各版本（`google`）。**這條事實沒有被推翻，本節下面的定案是在明知它成立的前提下做的。**
- **Shopify**：自動重導**只作用於顧客，搜尋引擎爬蟲被排除**（`help`）。
- 🔴 **Shopify 的預設值**（`help`，`/manual/markets/getting-started/localization`，68 §C-3 取得）：**新店預設「啟用」地區自動重導**，預設「**停用**」自動語言偵測。**兩個預設值方向相反。**
- **判斷依據**：瀏覽器語言 ＋ 地理位置；`geoip` 已被併入自動重導（`dev` changelog）。
- 🔴 **EU 例外（法遵，不是偏好）**（`help`，`/international/automatic-redirection`）：使用 **EU ccTLD** 的在地化體驗，**EU 客戶不會在 EU 內被自動重導**；官方要商家改用第三方 app 提供「**建議**」而不是重導。市場用非國別網域（`.com`／`.shop`）時，EU 客戶照常重導。
- **Shopify 自己沒有內建 recommendation banner**——「建議」這個形態官方是推給第三方 app 的。
- 29 §4 我方既有結論：「爬蟲永不 redirect；GeoIP → 建議切換 banner ＋ cookie 記住選擇」。**前半跟隨後仍然成立且升格為不變量；後半從「預設行為」降為「關閉自動重導時的行為」＋「EU ccTLD 下的唯一合法行為」。**

### K.2 我方規格

<!-- 依 68 號 §C-3 跟隨 Shopify 做法整節翻面（2026-08-12）。
     原文（保留供追溯，🔴 任何人不得改回）：
       「| 預設 | **關閉自動重導**。預設行為＝顯示「建議切換到 {市場}」橫幅 ＋ cookie 記住選擇
                ＋ 常駐的語言/地區切換器 |
        | 若商家開啟 | ①一律 302 ②對已驗證的搜尋引擎爬蟲不套用 ③只重導一次 ④EU ccTLD 不自動跳轉 |」
     🔴 **這一條是「跟隨 Shopify」與「外部權威（Google）」的直接衝突，不是與使用者裁定衝突**
        （68 §G 逐條分類如此）。使用者裁定「全部跟隨 Shopify」⇒ 預設開。
     🔴 **代價必須明寫，不得只翻布林值**：Shopify 之所以敢預設開，靠的是
        「爬蟲不重導 ＋ hreflang 完整」把 Google 的疑慮擋掉。⇒ 我方一旦預設開，
        原本「開啟時的選配護欄」三條就**升格為不可關閉的不變量**（下表 🔒 標記）。
        少了它們，預設開就是真的傷索引，而且傷的是**每一個新租戶**，不是有意開啟的那些。 -->

| 項 | 規則 |
|---|---|
| **預設** | 🔴 **啟用**地區自動重導（`limits.seo.redirect_geo.enabled_default: true`，原 `false`）。跟隨 Shopify 的預設值 |
| **語言自動偵測** | ✅ **維持停用**（`limits.i18n.storefront.auto_redirect_on_language: false`）——**這一半本來就與 Shopify 一致**（本尊亦預設停用），我方之前沒意識到自己已經對齊了。🔴 不要因為地區那一半翻成 true 就把這一半一起翻 |
| 重導形態 | 一律 **302**（不是 301——地區偏好不是永久事實） |
| 🔒 **不變量 1** | **對已驗證的搜尋引擎爬蟲不套用**（`exclude_verified_crawlers`）。**不可關閉**：不提供後台開關、API 欄位或環境變數；試圖關閉一律 reject |
| 🔒 **不變量 2** | **出現在 hreflang／sitemap 的 URL 對任何客戶端直接回 200**（`hreflang_urls_must_return_200`，§0.2 原則 4）。**不可關閉**。這是本節與 §I 的接縫，也是最容易做壞的地方 |
| 🔒 **不變量 3** | **只重導一次**（`once_per_visitor`，cookie 標記），使用者手動切回後不再攔截。**不可關閉**：無限重導＝使用者永遠回不到他想看的版本，那比不重導糟得多 |
| 爬蟲判定 | UA 比對 ＋ **反向 DNS 驗證**（Googlebot/Bingbot 官方驗證法）。未通過驗證的自稱爬蟲**當一般使用者處理**（否則變成偽裝繞過的漏洞） |
| **EU 例外** | 🔴 **法遵，不是偏好**：EU ccTLD 的在地化體驗 ＋ EU 來源客戶 ⇒ **不重導**，改顯示建議橫幅。判定**不得**寫成 SEO 層的國別 if-else（鐵律 11）——由 jurisdiction pack 宣告 `forbids_geo_auto_redirect`，SEO 層只讀該能力（`limits.seo.redirect_geo.eu_exception_source: jurisdiction_pack_capability`；掛載點見 56 號 capability contract） |
| 建議橫幅 | 自動重導**關閉時**、以及 **EU ccTLD 情境下**的行為：顯示「建議切換到 {市場}」橫幅 ＋ cookie 記住選擇。⚠ **Shopify 自己沒有內建這個**（官方推給第三方 app）⇒ 這是我方**超出本尊**的一條，標 `ours`；是否升為正式產品能力待裁定（68 §H） |
| 切換器 | 無論是否開啟自動重導，切換器必須是**真實連結**（`<a href>` 指向目標市場 URL），不能是純 JS。理由：那是爬蟲發現其他市場版本的路徑之一 |
| 商家可關 | 自動重導本身**可由商家關閉**（那是 Shopify 也有的開關）；🔒 三條不變量**不隨之可關**——關掉自動重導時它們自然不生效，但不存在「開著重導卻關掉護欄」的組合 |
| 🔴 **與快取的接縫** | **重導判定的輸入含瀏覽器語言與地理位置**（`help`：geoip 已併入自動重導）⇒ 它**依請求而異**。因此：①**重導判定必須在快取之前、且判定結果本身不得進頁面快取**（否則一份被快取的 302 會把所有人送去同一個市場，或一份被快取的 200 讓該重導的人不被重導）；②頁面快取鍵**不因此新增 `Accept-Language` 維度**——67 §G.2 的降維與 `i18n.storefront.emit_vary_accept_language: false` **維持不變**，因為**被重導的請求根本沒有進到頁面渲染**；③**重導只發生在導覽層，不改變任何 URL 的回應主體**——這是不變量 2 的另一面 |

<!-- 依 68 號 §C-3 補（2026-08-12）：上面「與快取的接縫」一列是**預設值翻面後才出現的新問題**，
     原節不需要它（預設關閉時沒有任何請求會被重導）。
     🔴 它同時是 67 §K.1 SF-1（「同一 URL 送三種 Accept-Language，回應主體逐位元組相同」）
        的邊界：SF-1 斷言的是**回應主體**，在自動重導開啟後，**狀態碼可能不同**（302 vs 200）。
        SF-1 不需要改（它測的是語言維度、且主體確實相同），但**測試實作必須跟隨最終 URL 後再比對主體**，
        否則會把「地區重導預設開」誤判成「語言污染」。 -->

> 🔴 **V-116 重寫**（依 68 §C-3；原條目的處置前提已消失）
> **原處置**：「『排除爬蟲是否被 Google 視為可接受』未取得官方表態 ⇒ **預設維持關閉**。」
> **前提消失**：預設值已依裁定翻成啟用，「維持關閉」這個處置沒有東西可以依附。
> **新處置**：**預設開；三條護欄不可關；風險登記在此。** 未知本身沒有變——Google 官方文檔至今只說「避免自動重導」，**未對「排除爬蟲」表態**（既不認可也不否定）。我方的緩解不變且加碼：對 bot 與人**回傳完全相同的頁面內容**，唯一差異是「人可能被建議／重導到另一個 URL」，而該 URL 對 bot 同樣直接回 200（不變量 2）。**這不是 cloaking 的形態**（cloaking 是給 bot 看不同內容），但**我方無法代替 Google 宣稱它可接受**。
> **若 Google 日後表態不可接受**：要改的是 `enabled_default`（翻回 false），**不是**拆掉三條護欄。

---

## L. 貨幣顯示與 `priceCurrency` 一致性

### L.1 三個數字、一個來源（承 §A.3）

| 面 | 值 | 格式 | 來源 |
|---|---|---|---|
| 可見價格 | `PriceView.amount_cents` | market locale 決定符號與千分位；**小數位恆 2**（裁定二） | `money` filter |
| `Offer.price` | 同上 | **無符號、無千分位、恆兩位小數字串** | 序列化層 |
| `Offer.priceCurrency` | `PriceView.currency` | ISO 4217 三碼 | presentment 幣別 |
| feed `price` | 同上 | `"938.00 HKD"` 形態（30 §6.1） | 同一生成器 |

**最常見的三個錯，逐條寫明防呆**：

1. **用 shop currency 當 `priceCurrency`。** 多市場下顧客看 HKD、JSON-LD 寫 USD ⇒ 結構化資料與頁面不符。防呆：序列化層**不接受**傳入 currency 參數，只接受 `PriceView`。
2. **用 `currency_format.exponent` 換算。** 該欄在 2026-08-12 之後語義是**顯示位數**（58 §G.3 的警告）；拿去除以 10^exponent 會在 JPY/TWD 上算出 100 倍誤差。防呆：換算常數只有一個 —— `limits.seo.jsonld.amount_divisor: 100`，並在註解直接引 58 §G.3。
3. **在 JSON-LD 裡套 locale 格式化。** `HK$938.00` 或 `938,00` 進 `price` 都是無效值。防呆：序列化層用固定的 `format("%.2f", cents / 100.0)` 等價實作（**但輸入是 integer，除法只在格式化那一步發生，中途不得出現 Float**——鐵律 3）。

### L.2 rounding、fixed price、匯率與 JSON-LD 的先後

`Offer.price` 必須是**最終呈現價**：`fixed price → base×(1±adj%)×匯率×(1+轉換費率) → rounding`（29 §1.4／§3.3）。**fixed price 不換算不湊整；gift card 不湊整。** 若 JSON-LD 取的是 rounding 前的值，就會出現「頁面 ¥1,000、結構化資料 ¥987.34」的典型不符。防呆：`PriceView` 由解析器**在 rounding 之後**建構，解析器不回傳中間值。

### L.3 `compare_at` 與促銷

原價走 `offers.priceSpecification.priceType: StrikethroughPrice`，現價走 `offers.price`（30 §2.2）。**`compare_at ≤ price` 時不輸出 StrikethroughPrice**（不是輸出相等值）——輸出一個沒有折扣的劃線價是誤導性標記。

### L.4 零小數幣別的三個面（一張表講完）

| 面 | JPY 的值 | 依據 |
|---|---|---|
| 儲存 | `100000`（cents，×100 不看幣別） | `currency_display.storage_scale_unchanged` ＋ 58 §G.3 |
| 顯示 | `¥1,000.00`（兩位小數） | 裁定二 `force_minor_unit_digits: 2` |
| `Offer.price` | `"1000.00"` | §A.4 定案（數值等價，Google 只禁符號與逗號） |
| feed `price` | `"1000.00 JPY"` | ⚠️ **V-115 未結案**：GMC 對 zero-decimal 幣別是否接受兩位小數未取得明文 |

### L.5 exponent=3 幣別（KWD／BHD／JOD）在 SEO 面的處置

<!-- 依 68 號 §D-3 跟隨 Shopify 做法新增（2026-08-12）。本節是 D-3 在**本檔**（序列化與顯示面）的落點；
     幣別清單本身的裁定落在 `limits.catalog_flow.exponent3_*`，金額邊界仍歸 65 號。 -->

**Shopify 的實際做法**：幣別代碼**支援**（`CurrencyCode` enum 含 KWD／BHD／JOD／OMR／TND，`dev`）；金額**四捨五入到 2 位**（`press`：以 API 送 `3.004` 存成 `3.00`）；顯示不一致（BHD 首頁 3 位、商品頁 2 位，`press`）⇒ 官方沒有把 3 位小數做通；Shopify Payments **不支援**該三國開店（`press`）。

⇒ **本尊的實質做法是「幣別代碼開放、金額當 2 位處理、精度損失不處理」，不是「擋掉這些幣別」** ⇒ 我方跟隨：**不擋幣別**（`limits.catalog_flow.unsupported_currency_exponents: []`，原 `[3]`）。

| 面 | KWD 的值 | 說明 |
|---|---|---|
| 儲存 | `290`（＝KWD 2.90 的 cents，×100 不看幣別） | 🔴 **`2.905` 存不進來，會落成 `2.90`**——精度損失是**跟隨的結果**，Shopify 也是這樣（四捨五入），但**必須明文記錄，不能靠沉默** |
| 顯示 | `KD 2.90`（兩位小數） | 與裁定二**天然吻合**，不需要例外邏輯 |
| `Offer.price` | `"2.90"` | §A.4 的 `amount_cents / 100` 一律適用、**不看幣別** ⇒ 本節**不需要**在序列化層新增任何分支 |
| feed `price` | `"2.90 KWD"` | 同一生成器 |
| **收款** | 🔴 **PSP pack 未明文宣告 `amount_format` 與該格式參數 ⇒ reject**（A0；`minor_units` 另需逐幣別 minor unit＝A1；`decimal_string` 位數 >2 ⇒ A6 使 pack 不得 enable） | 鐵律 3 ／ 65 §D **原封不動**<!-- 依 65 §J M-9（69 §V-188）修正（2026-08-13），原文：「PSP pack 未明文宣告 minor unit ⇒ reject｜鐵律 3／65 §R5 原封不動」——宣告的維度多了 amount_format 一層，R5 不再是唯一對外表示法。 --> |

> 🔴🔴 **不得把本節讀成「鐵律 3 放寬了」。** 跟隨 Shopify 改的是**幣別清單**，不是**金額邊界**。KWD 的 milli-unit 問題**依然無解**：ISO 4217 的 KWD exponent=3，若某 `minor_units` pack 宣告 3，`Money::PspMinor` 的基數就是 1000，而我方儲存是 ×100 ⇒ **儲存尺度與 PSP 單位在此幣別下不同源**。跟隨 Shopify **不解決這個問題，只是允許幣別存在**。⇒ **幣別可選、收款要等 PSP pack 明文宣告，且該 pack 必須同時宣告如何處理儲存精度不足。** `money_boundary.max_supported_iso_exponent: 2` 一個字都不動——它是 **`minor_units` 分支唯一的執法點**；`decimal_string` 分支的對應執法點是 **A6**（宣告位數 >2 ⇒ pack 不得 enable，65 明言 A6 與 A2 是同一條規則在另一種格式下的形態）。
> <!-- 依 65 §J M-9（69 §V-188）修正（2026-08-13），原文：「它從『兩個執法點之一』變成唯一的執法點」——
>      成文於 minor-units-only 世界觀；A6 出現後「唯一」對 decimal_string pack（如 KWD 走 Airwallex 型）不成立。 -->
>
> ✅ **交叉引用待修清單（原三項）已全數結案（2026-08-13 核）**：`63 §G.4` 的「market 建立時擋、回 `INCLUSION`」已依 68 §D-3 改寫（執法點移到 A2／A6 轉換點）；`65 §A2／T11` 與 `55` 的金額測試矩陣**經逐檔 grep 已無** INCLUSION／market-建立時擋的殘留（65 T11 早在其自身輪次已附註修正——本清單成文時點的判斷對 65/55 已過時）。⚠ 68 §I **V-188** 的登記（Shopify 對 exponent=3 無官方立場）保留。
> <!-- 原文：「🔴 交叉引用待修（本輪不得改那三份檔案）：63 §G.4、65 §A2／T11、55 的金額測試矩陣目前仍寫著
>      『exponent=3 於 market 建立時擋下、回 INCLUSION』——那個執法點已被本次跟隨移除。實作前必須以
>      limits.catalog_flow.exponent3_* 為準並回頭修那三處…」。63 已於 2026-08-13 修（M-8 結案輪）；65/55 查無殘留。 -->

---

## M. 落地：里程碑對應

| # | 項目 | 里程碑 | 需要的 schema／欄位 | 驗收 |
|---|---|---|---|---|
| S1 | `url_redirects` 表＋handle 變更掛鉤＋410 紀律 | **M0**（表）/ **M1**（掛鉤） | §B.5 | 改 handle 後舊 URL 301；下架回 410；鏈長 ≤ `limits.seo.redirect_max_chain` |
| S2 | 商品／系列／頁面／文章的 `seo_title`／`seo_description`（**可翻譯**）＋ `handle`（🔴 **不可翻譯**，全站單一值、語言走 URL 前綴，67 §D.3） | **M1** | 29 §2.1 對應 key；handle 見 `limits.handle` | 翻譯後台可見；digest 機制生效；handle 不出現在可翻欄位清單 |
| S3 | media `alt` 一級欄位＋`alt_source` 稽核＋缺 alt 計數 | **M1** | `media.alt`, `media.alt_source` | 商品列表顯示缺 alt 數 |
| S4 | Admin SEO 預覽卡（五列，含價格） | **M1** | 讀 `PriceView` | 與前台渲染價格逐位相同（§O SEO-2） |
| S5 | `resolve_price_view()` ＋ `SeoPriceParityTest` | **M2**（feed 消費者在 M5 接入） | §A.3 | 四方全等；任一不等紅燈 |
| S6 | canonical 引擎（八種變形） | **M2** | `canonical_overrides` | §B.1 逐列測 |
| S7 | 平台 JSON-LD 注入（Organization/Breadcrumb/Product/ProductGroup/Offer/ItemList） | **M2** | §A.2 | Rich Results 測試通過（HANDOFF M2 驗收已列） |
| S8 | 標題／描述樣板引擎＋截斷 | **M2** | 主題設定 | 多位元組不截半；空描述不輸出 tag |
| S9 | sitemap 四分片＋`lastmod` 語義＋market 切法 | **M2**（單市場）/ **M5**（多市場全量） | §C | 只含 200＋canonical；draft market 不入 |
| S10 | `robots.txt.liquid` ＋平台保底注入＋lint | **M2** | 26:220–224 物件 | 覆寫後仍有 `Sitemap:` 行 |
| S11 | hreflang（locale 維度，單市場多語言）<br>🔴 **含恆帶地區的碼規則與 `hreflang_codes()` 的 Set 回傳型別**（§I.2）<!-- 依 2026-08-13 裁定補。🔴 **不得排到 S16**：碼粒度不是「多市場才需要」的東西——單市場單語言的第一個頁面就要輸出 `en-HK` 而不是 `en`，而型別（Set vs String）一旦以單數形態實作出去，S16 要改的是每一個呼叫點。 --> | **M2**（P0） | §I.1／§I.2 | 自指＋雙向；🔴 **輸出中無裸語言碼**（REG-4） |
| **S11b** | 🔴 **per-market 語言白名單**（`market_web_presence_locales` 補三欄 ＋ admin UI ＋ 切換器只列開放語言 ＋ 未開放前綴 404）<!-- 依 2026-08-13 裁定新增。 --> | **M2**（與 67 L7 URL 前綴路由同一批做——**前綴 ≡ (market, locale) 身分，兩者拆開做會先做出一個沒有身分的前綴表**） | 67 §A.5／§C.8 ＋ 29 §1.4 既有表 | REG-11 四條 |
| S12 | `<h1>` 唯一性 lint＋CWV 預算與圖片管線 | **M2** | — | LCP/INP/CLS 門檻；lint 0 error |
| S13 | `/agents.md`＋`/llms.txt`＋**`/llms-full.txt`** 三條別名端點＋`agents` drop<!-- 依 68 §C-1 修正：原文只列兩條端點（`llms-full.txt` 當時預設關），現三條預設全開 --> | **M2**（低成本，隨路由層一起做） | 模板類型 ＋ `agents` drop 7 欄 | 三條路由 fallback 鏈正確；**三條預設皆回 200 且內容相同**（GEN-1／GEN-4）；`ucp_*` 欄位在未實作時**不輸出** |
| S14 | AI 爬蟲三組開關＋預設值 | **M2** | shop settings | robots 輸出符合分組；`Googlebot` 不可關 |
| S15 | `knowledge_entries` ＋前台區塊 | **M5** | §H.5(a) | 一份資料三出口；不出 `FAQPage` |
| S16 | hreflang 全量矩陣（market×locale）＋x-default＋碼衝突解析<br>🔴 **多國市場的逐國展開與 `over_limit_action` 在這裡才會被觸發**（單市場測不到） | **M5** | §I.1–I.3 | REG-1～REG-8 ＋ **REG-2b**／**REG-11** 全綠 |
| S17 | 多市場 sitemap（分網域）＋market 變更失效掛鉤 | **M5** | §C ＋ §I.3(b) | 改 market conditions 後矩陣 5 分鐘內更新 |
| S18 | feed 生成器接入 `PriceView`＋IndexNow | **M5** | 30 §9-8/9-9 | GMC 測試 feed 零錯誤（HANDOFF M5 驗收已列） |
| S19 | 代理通路：catalog／faq 端點＋逐通路開關＋限流 | **M5**（唯讀）/ **M6**（管道 UI） | §H.4 | 端點回應價格與 PDP 全等；未發佈商品不出現 |
| S20 | 主題側 `structured_data` 等價 filter ＋ 編輯器 SEO 面 | **M6** | 26:410 | 主題只能新增節點 |
| S21 | 網域策略（自訂網域、per-market 網域、平台子網域 301）＋site move 精靈<br>🔴 **含新市場預設 `inherit_primary`**（`limits.market.web_presence.*`，§J.2）<!-- 依 68 §C-2 補 --> | **M7**（**但 `inherit_primary` 的預設值必須在「能建市場」的那個里程碑就正確**，不能等 M7） | HANDOFF M7 已列 ＋ `market.web_presence.*` | 雙網域皆可逛；301 全量；**建立新市場時不自動產生任何子資料夾 URL**（測：建市場後 sitemap 與 hreflang 條目數不變） |
| S22 | UCP 階段 1（唯讀 Catalog 能力宣告） | **M7+**，`enable_gate: [V-113, V-114]` | `/.well-known/ucp` | 未結案不得 enable |
| S23 | SEO/GEO 可觀測（GSC API、AI 流量分軸、hreflang 完整性巡檢、富摘要驗證 job） | **M8** | §H.7 | 巡檢可觸發告警 |

---

## N. `config/limits.yml` 新增鍵（本輪已落鍵）

新增兩個頂層區塊：**`seo:`**（§18）與 **`agents:`**（§19）。**既有鍵一律沿用不重複定義**——特別是：

| 既有鍵 | 用途 | 本檔引用處 |
|---|---|---|
| `content.seo_title_max_chars: 70` | 標題上限 | §E.2 |
| `content.seo_meta_description_max_chars: 320` | 描述上限 | §E.2 |
| `currency_display.force_minor_unit_digits: 2` | 顯示兩位小數 | §A.4／§L |
| `currency_display.storage_scale_unchanged: true` | 儲存 ×100 | §L.4 |
| `market.inheritance_additive: [catalogs, web_presences]` | hreflang 用 resolved 集合 | §I.3(a) |
| `market.specificity_stack` | 碼衝突解析第 2 步 | §I.3(c) |
| `carrier.money.storage_multiplier: 100` | 換算尺度的前例與警告 | §L.1 防呆 2 |

新增鍵清單見 `config/limits.yml` 的 §18／§19 兩節（每鍵帶出處註解）。

**2026-08-12 依 68 號「全部跟隨 Shopify」裁定的鍵變更**（本檔範圍內，逐鍵可追溯；每鍵在 `limits.yml` 內都有 `依 68 號 §X … 原值：…` 的追溯註釋）：

| 鍵 | 原值 → 新值 | 依據 | 本檔落點 |
|---|---|---|---|
| `agents.llms_full_txt_enabled` | `false` → **`true`** | 68 §C-1（`dev` changelog：三路徑預設全開、內容相同） | §H.2、§H.3(a)、§H.6-2、§O GEN-4 |
| `agents.llms_paths_default_alias_of_agents_md` | 新增 `true` | 同上 | §H.3(a) |
| `seo.redirect_geo.enabled_default` | `false` → **`true`** | 68 §C-3（`help`：新店預設啟用） | §K.1／§K.2、§O REG-9、V-116 |
| `seo.redirect_geo.non_disableable_invariants` | 新增（三條護欄升格） | 68 §C-3 | §K.2 🔒 三列 |
| `seo.redirect_geo.eu_cctld_no_redirect` / `eu_exception_source` | 新增 | 68 §C-3（`help`，法遵） | §K.2 |
| `market.web_presence.*` | 新增（`default_for_new_market: inherit_primary` 等） | 68 §C-2（`dev` 2023-05-23 changelog） | §J.2 |
| `seo.variant_url_mode_b_requires_unique_content` | **刪除** → `variant_independent_urls_supported: false`（**值不變**，🔴 **理由已於同日換掉**） | 68 §B-6（模式 B 廢除）→ 🔴 **69 §B-6 修正定性**（`std` ×2）：廢除的是**資料模型**，不是「變體可索引」這個目標；後者是 Google 官方建議，我方 single-page 模式**已達成** | §B.2（含三條 Google 硬規則）、§B.2-1 |
| 🔴 `seo.variant_url_fragment_forbidden` / `variant_param_must_be_key_value` | **69 新增** | 69 §B-6（`std`：Google 索引不使用 fragment；參數須 `?key=value`） | §B.2 硬規則 2／3 |
| `combined_listing.*`（§22 新區塊） | 新增（`implemented: false`、60／3／2000） | 68 §B-6(c)（`help`） | §B.2-1 |
| `catalog_flow.unsupported_currency_exponents` | `[3]` → **`[]`** ＋ `exponent3_*` 四鍵 | 68 §D-3（`dev` enum ＋ `press` 四捨五入） | §L.5 |
| `handle.collision_strategy_generated` | `numeric_suffix_from_2` → **`numeric_suffix_from_1`** | 68 §C-4（`dev` `potion`/`potion-1` ＋ `test`） | 67 §D.4(b)（本檔 §F.3 引用） |
| `handle.liquid_filter_fallback_trigger` | 新增 `empty_or_all_separator_input_only` | 68 §F-3（staff 復現：filter 保留非 ASCII） | §F.3 註 ＋ 67 §D.5 |
| 🔴 `i18n.import.blank_means_unchanged` | `true` → 68 改 **`false`** → **69 改回 `true`**（二次修正）；缺席語義三鍵與預覽四鍵**全數保留**，另加 overwrite 旗標四鍵 | 68 §B-3（Matrixify，`press`）→ 🔴 **69 §V-182 推翻其前提**（本尊原生 CSV 在 Settings → Languages，`help`：**8 欄 ＋ Status 三值 ＋ 覆寫勾選框**，**沒有把空白解讀成刪除**） | 67 §E.6（沿革全文）、67 §0.4-0、67 §M-9 |

**2026-08-13 依 locale 碼裁定（§I.2）的鍵變更**——🔴 **這一組的依據是「使用者裁定」，不是查證，也不是跟隨 Shopify。恰恰相反：它是本檔第二處明知偏離本尊的地方（第一處＝§F.3-1 handle）。**

| 鍵 | 原值 → 新值 | 依據 | 本檔落點 |
|---|---|---|---|
| 🔴 `seo.hreflang.region_qualified_when_single_country_market` | `true` → **刪除**，改為 `always_region_qualified: true` | 裁定（§I.2）。原鍵名把「單國市場」寫進鍵名裡，**留著它會讓人以為多國市場還有另一種行為** | §I.2 |
| 🔴 `seo.hreflang.bare_language_code_forbidden` | **新增 `true`** | 裁定。輸出中出現裸碼 ⇒ CI 紅燈 | §I.2、§O REG-4 |
| `seo.hreflang.multi_country_market_expands_per_country` | **新增 `true`** | 裁定。多國市場逐國展開成 N 碼、同一 URL | §I.2、§I.3(c) 情形 1 |
| `seo.hreflang.multi_presence_resolution` | **新增 `nearest_own_then_ancestor`** | 🔴 **殘留衝突源換人了**（§I.3(c) 情形 2）：原 `specificity_stack` 比的是市場，殘留衝突兩邊是同一個市場 ⇒ 比不出東西 | §I.3(c) 步驟 2 |
| `seo.hreflang.dedupe_must_be_page_independent` | **新增 `true`** | 🔴 步驟 2 現在是唯一會走到的丟棄分支 ⇒ 丟棄決定必須逐頁相同，否則雙向性破裂 | §I.3(c)、§O REG-2b |
| `seo.hreflang.over_limit_action` | **新增 `emit_partial_and_lint`** | 超出 `max_expanded_countries_per_market` 時**不得退回裸碼**（裸碼已被禁）⇒ 部分標註 ＋ blocking lint | §I.3(c) 步驟 3 |
| `seo.hreflang.validator_accepts_bare_code_for_audit_only` | **新增 `true`** | 🔴 **認得 ≠ 允許輸出**：巡檢外部標註要能認裸碼並報 lint；我方自己產生裸碼是 CI 紅燈。兩個檢查點兩種嚴重度 | §I.4 |
| `seo.hreflang.x_default_target` | **新增 `default_market_locale_prefixed_url`** | 🔴 根路徑不再是內容頁（67 §F.1(b)）⇒ x-default 不得再指 `/` | §I.2、§O REG-3 |
| `i18n.locale_prefix.*`（新子區塊） | **新增** | URL 前綴恆帶地區、禁裸語言前綴、前綴 ≡ (market, locale) 身分、未知前綴 404、根路徑重導 | 67 §F.1(b)(c) |
| `i18n.market_locales.*`（新子區塊） | **新增** | per-market 語言白名單（strawberrynet 模型）；🔴 **實體沿用既有 `market_web_presence_locales`，不新建表** | 67 §A.5、§C.8、本檔 §I.3(e) |
| `naming_contract.*`（新頂層 §23） | **新增** | 鐵律 9 的界線：**可以對齊命名契約，不可以複製樣式表內容**（67 §H.5） | 67 §H.5 |

🔴 **`money_boundary.*` 在 68 那一輪一個鍵都沒動**（鐵律 3／65 號）。D-3 改的是幣別清單，不是金額模型；`max_supported_iso_exponent: 2` 的**註釋**有更新（說明它已成為唯一執法點），**值不變**。
⚠ **但 69 §V-188 那一輪動了 `money_boundary`**——新增 `psp_amount_formats`／`psp_divisibility_*` 等鍵（PSP 的金額**格式**是一個原本不存在的維度：Airwallex 用十進位主單位字串）。🔴 **那同樣不是放寬**：`psp_undeclared_currency_action: reject` 與 `max_supported_iso_exponent: 2` 一個字都沒動，全文見 **65 §A R6／§D**。

---

## O. 驗收清單

### SEO

| # | 條目 | 判準 |
|---|---|---|
| SEO-1 | 平台 JSON-LD 不可被主題移除 | 用一個把 head 清空的測試主題渲染，第 1 層節點仍在 |
| SEO-2 | **四方價格全等** | `SeoPriceParityTest`（DOM／JSON-LD／feed／catalog 端點）＋ admin 預覽卡 |
| SEO-3 | `Offer.price` 格式 | 正則 `^\d+\.\d{2}$`；無符號無逗號；`priceCurrency` 為三碼 |
| SEO-4 | availability 對映 | 已佔用不得計入 InStock；未發佈市場不得輸出 Offer |
| SEO-5 | canonical 八變形 | §B.1 逐列 request → 斷言 canonical |
| **SEO-5b** | 🔴 **變體 URL 的三條 Google 硬規則**（依 69 §B-6 新增） | ①同一 `ProductGroup` 的所有變體 URL，canonical **全部指向同一個去參數基底 URL**（single-page 只能有一個 canonical）；②全站渲染輸出中**不得出現以 fragment 切變體的連結**（`#variant`／`#color=` 之類，Google 索引不使用 fragment）；③變體參數一律 `?key=value` 形態，掃到 `?value` 即紅燈 |
| SEO-6 | 分頁 self-canonical | 第 2 頁 canonical ≠ 第 1 頁 |
| SEO-7 | sitemap 純淨度 | 抽樣全部回 200 且 self-canonical；無 draft market URL |
| SEO-8 | robots 保底 | 主題覆寫後 `Sitemap:` 行與 checkout/cart/account disallow 仍在 |
| SEO-9 | 標題描述 | 上限內；多位元組不截半；空描述不輸出 meta tag |
| SEO-10 | h1 唯一 | 每模板恰 1 個 |
| SEO-11 | handle 改名 301 | 舊 URL 301；鏈長超限報錯 |
| SEO-12 | 410 紀律 | 下架商品回 410，非 200 空殼 |
| SEO-13 | CWV | LCP ≤2.5s／INP ≤200ms／CLS ≤0.1（實驗室＋CrUX） |
| SEO-14 | 不做清單 | 全站輸出中不得出現 `FAQPage`、`SearchAction`、`AggregateOffer` |

### GEO-G

| # | 條目 | 判準 |
|---|---|---|
| GEN-1 | 三端點 fallback 鏈 | 移除 `llms.txt.liquid` 後 `/llms.txt` 落到 `agents.md` 模板；再移除落到平台預設 |
| GEN-2 | `agents` drop 受限 context | 模板內存取 `collections` 應為 nil，不得拋錯也不得洩漏 |
| GEN-3 | **未實作能力不得宣告** | `limits.agents.ucp.provider_enabled: false` 時，`/agents.md` 輸出中**不含** `ucp_discovery_url` 與 `ucp_versions`（不是輸出空字串） |
| GEN-4 | **`llms-full.txt` 預設開且＝`agents.md` 別名** | 未安裝任何模板時 `/llms-full.txt` 回 **200 且內容與 `/agents.md` 逐位元組相同**（**不是 404**）；自訂 `llms-full.txt.liquid` 後受 `limits.agents.llms_full_txt_max_bytes` 上限<br><!-- 依 68 §C-1 反轉，原文：「`llms-full.txt` 預設關 \| 預設回 404；開啟後受大小上限」。🔴 不反轉這條，CI 會把**正確行為**判成失敗。 --> |
| GEN-5 | AI 爬蟲分組 | 關訓練組不影響搜尋組；`Googlebot` 無法被租戶關閉 |
| GEN-6 | 代理端點價格同源 | 與 SEO-2 同一套斷言 |
| GEN-7 | 代理端點市場明示 | 無 `country` 參數時回應必含解析到的 market handle |
| GEN-8 | 庫存不外洩 | 端點回應不含精確可用數 |

### GEO-R

| # | 條目 | 判準 |
|---|---|---|
| REG-1 | 自指 | 每頁 hreflang 集合含自身 |
| REG-2 | 雙向 | 集合內任兩 URL 互指 |
| **REG-2b** | 🔴 **dedupe 的頁面無關性**（依 2026-08-13 裁定新增） | 造出「同一 (market, locale) 對應兩個 resolved web presence」的情形（子市場自身有子資料夾 ＋ 繼承父市場 presence），然後**從集合內每一個 URL 各抓一次 hreflang 集合**：🔴 **N 個集合必須逐位元組相同**。若某頁保留了自己那條、別頁丟掉它，REG-2 會在這個情形下靜默失效（§I.3(c) 步驟 2） |
| REG-3 | x-default | 恰一個，指主網域 primary 預設語言**的帶前綴 URL**；🔴 **不得指向根路徑 `/`**（根已是重導，非 200 ⇒ 會破 REG-6）<!-- 依 2026-08-13 裁定修正，原判準：「恰一個，指主網域 primary 預設語言」——當時根路徑就是預設語言頁 --> |
| REG-4 | 碼合法性 ＋ 🔴 **恆帶地區** | ISO 639-1(+15924)**(+3166-1 必要)**；拒 `EU`/`UK`/`es-419`；🔴 **全站輸出中不得出現任何不帶地區後綴的 hreflang 值**（掃描 `<head>` 與 sitemap，正則 `hreflang="[a-z]{2,3}(-[A-Za-z]{4})?"` 命中即紅燈；`x-default` 除外）<!-- 依 2026-08-13 裁定擴充，原判準：「ISO 639-1(+15924)(+3166-1)；拒 EU/UK/es-419」——原判準允許裸碼 --> |
| REG-5 | **繼承正確性** | 子市場頁面的集合 ＝ 自身 ∪ 祖先 web presences（改父市場後重測） |
| REG-6 | **可達性不變量** | hreflang／sitemap 內所有 URL 對任何客戶端直接 200、self-canonical、非 noindex |
| REG-7 | 失效掛鉤 | 改 market conditions／移除語言／**改 per-market 語言白名單**後，矩陣與 sitemap 在去抖窗內更新 |
| REG-8 | 碼衝突 | ~~造出兩個同語言多國市場 → 展開為逐國碼 ＋ 落 lint 記錄~~ ⇒ 🔴 **判準改了**：造出兩個同語言多國市場後，**兩邊本來就已是逐國碼、不應發生任何衝突**（§I.3(c) 情形 1 已消滅）——本條改測**殘留衝突**：造出情形 2（多 presence）⇒ 走 `nearest_own_then_ancestor` ＋ 落 lint，**不得靜默丟棄**；另測情形 3（國家數 > 上限）⇒ **部分輸出 ＋ blocking lint，且輸出中無裸碼** |
| **REG-11** | 🔴 **per-market 語言白名單**（依 2026-08-13 裁定新增） | ①切換器只列該市場開放的語言，且每個項目都是回 200 的真實 `<a href>`；②以直接 URL 存取**該 shop 不存在的 (market, locale) 前綴** ⇒ **404**（不得 302 到別的語言）；③以直接 URL 存取**別的市場的**合法前綴 ⇒ **200**（可能被地區重導攔一次，測試須跟隨重導；🔴 **回 404 即紅燈**——那會直接打破 REG-6）；④hreflang 集合 ⊆ 白名單 ∩ published，逐項回 200 |
| REG-9 | **重導（預設開）** | <!-- 依 68 §C-3 反轉，原文：「預設不自動重導；開啟後 302、對已驗證爬蟲不套用、只攔一次」 -->新店預設**啟用**地區重導；302；🔒 已驗證爬蟲不套用、🔒 只攔一次、🔒 hreflang／sitemap URL 對任何客戶端回 200 —— **三條護欄無法由任何設定關閉**（測試：嘗試以 API／設定關閉任一條 ⇒ reject）；EU ccTLD ＋ EU 來源 ⇒ 不重導改顯示建議；**語言自動偵測維持關閉** |
| REG-10 | 幣別一致 | 每市場的可見價格／`priceCurrency`／feed 幣別三者相同 |

---

## 附錄 A · 待查證登記（V-110 起）

| # | 未取得的是什麼 | 取得途徑 | 在結案前的處置 | 影響章節 |
|---|---|---|---|---|
| **V-110** | Shopify `canonical_url` 在 `?variant=` 下的實際輸出（含／不含參數） | dev store 實測；或 shopify.dev 明文 | **按 Google 規則實作（去參數）**，不對齊傳聞 | §B.2 |
| **V-111** | 兩個多國市場產生相同 hreflang 語言碼時，Shopify 的去重／解析規則 | 實測（建兩個同語言多國市場） | 用我方 `dedupe_codes`（展開為逐國碼＋lint），**不得靜默丟棄** | §I.3(c) |
| **V-112** | Shopify 對 **draft market** 的 URL：是否進 hreflang／sitemap／是否 noindex | 實測 | 我方定案：**不進、且 noindex**（可瀏覽不可買的頁面不該被索引） | §C |
| **V-113** | `/.well-known/ucp` 是否對所有 Shopify 商店自動提供；其內容、快取策略與 `ucp_versions` 值域 | shopify.dev `/docs/agents` 子頁；或實測任一商店 | `agents.ucp.provider_enabled: false`，**不輸出** `ucp_discovery_url` | §H.3 |
| **V-114** | UCP／MCP 如何攜帶買家國別與幣別以取得 per-market 價格 | ucp.dev capability schema 逐項；Shopify Catalog MCP 參數表 | 我方代理端點**強制 `country` 參數**並回應明示市場 | §H.3、§H.6-7 |
| **V-115** | GMC／Merchant API 對 zero-decimal 幣別的 `price` 是否接受兩位小數（`1000.00 JPY`）；富摘要驗證器是否告警 | support.google.com/merchants 產品資料規格逐欄；Merchant API schema | feed 維持兩位小數（與頁面同源優先），並加 GMC 診斷告警規則 | §A.4、§L.4 |
| **V-116**<br>🔴 **處置已重寫** | 「對爬蟲不套用地區自動重導」是否被 Google 視為可接受（非 cloaking）——**未知本身未變**：Google 官方至今只說「避免自動重導」，未對「排除爬蟲」表態 | Google Search Central 官方明文或官方人員表態 | <!-- 依 68 §C-3 重寫，原處置：「**自動重導預設關閉**；開啟時 bot 與人取得相同頁面內容」——該處置的前提（預設關閉）已隨裁定消失 -->**預設啟用**（跟隨 Shopify）；bot 與人取得相同頁面內容；🔒 排除爬蟲／hreflang 回 200／只攔一次**三條升格為不可關閉的不變量**；風險登記於 §K.2。若 Google 日後表態不可接受 ⇒ 翻回 `enabled_default: false`，**不得改為拆護欄** | §K |
| **V-117** | 是否有**任何** AI 供應商官方文檔宣稱消費 `llms.txt`（本輪只查到 Google 明確否定 ＋ OpenAI 文檔未提及） | 各家開發者文檔逐一覆核（Anthropic／Perplexity／Microsoft） | `llms.txt` 僅做零成本別名；不投入內容策展 | §H.2 |
| **V-118** | `agents.md`／`llms.txt`／`.well-known/ucp` **是否真被代理抓取**（伺服器日誌級證據） | **我方自己量**（§H.7 端點命中率儀表板） | 端點照做，但不據此宣稱效果 | §H.2、§H.7 |
| ~~**V-119**~~ | ~~Shopify `handleize` 對 CJK 標題的實際行為（保留／轉寫／落 id）~~ | 68 號查證（`press` ×4） | ✅ **2026-08-12 結案，答案＝保留 CJK**（不是「問題消失」）<br><!-- 依 68 §B-1 改寫，原處置：「✅ **2026-08-12 結案**：使用者裁定「url hand 使用英文標題，禁止使用中文」⇒ 我方一律 ASCII，**不再需要對齊 Shopify**，原問題失去用途。」🔴 原敘述把「裁定覆蓋 Shopify」寫成「對齊問題消失」——前者是明知偏離、後者是不必比較，日後重審的意義完全不同。 -->Shopify 對非拉丁字集**原樣保留**，中文標題得到中文 handle，從不落代碼、也不擋發布。我方一律 ASCII 是**明知偏離**，唯一依據＝使用者裁定（**裁定 > Shopify**），登記於 §F.3-1。⚠ 官方**從未文件化**此行為 ⇒ 描述本尊時只能標 `press`（68 V-180）。主題相容殘留改由 **V-161** 承接（67 §L，已縮小） | §F.3-1 |
| **V-120** | Google 兩份官方文檔的張力：多地區重複內容建議 canonical 到偏好版本 vs 在地化頁需可索引才能被 hreflang 服務 | 實測（同語言雙地區，觀察 GSC 收錄） | **一律 self-canonical**，不跨市場 canonical | §B.4 |
| **V-121** | Shopify Catalog 的商品「符合資格」條件具體清單 | help.shopify.com Catalog 子頁逐頁；或 dev store 觀察拒登原因 | 我方以 GMC 規格為完整度門檻（超集策略） | §H.4 |
| **V-122** | 各 AI 通路（ChatGPT／Copilot／Gemini／Meta）對商品欄位的硬性要求與拒登原因碼 | 各通路官方文檔；或代理管道後台的錯誤清單 | 同上 | §H.4 |
| **V-123** | 封鎖訓練型爬蟲（GPTBot／Google-Extended／ClaudeBot）對商品被 AI 引用的實際影響 | 無公開對照實驗；只能自建 A/B（成本高、雜訊大） | 後台文案**只陳述官方定義，不宣稱效果** | §D.3、§H.6-3 |
| **V-124** | Shopify `structured_data` filter 在多變體商品輸出 `ProductGroup` 的**具體欄位集** | 實測（渲染有變體商品的主題）；changelog 只說改用 ProductGroup | 我方按 Google product-variants 規則自行決定欄位集 | §A.2 |
| **V-125** | 「問答式標題提升 AI 引用率」是否有可靠一手證據（本輪只找到 GEO 論文的引用/統計/引述三項，且領域差異大） | 學術檢索；或自建量測 | 主題模板可用問句，但**理由寫可讀性**，後台不得宣稱 AI 效果 | §H.5(b) |
| **V-126** | `ClaudeBot`／`PerplexityBot` 等非 Google/OpenAI 爬蟲的官方 UA 字串與語義 | 各家官方文檔 | AI 爬蟲清單做成**可設定資料**，不寫死 | §D.3 |
| 🔴 **V-220**<br>（2026-08-13 新增） | **Google 是否會因 hreflang 碼粒度變細（`en` → `en-FR`/`en-DE`/…）而改變其重複內容群集、canonical 選擇或索引結果。** 🔴 這是使用者裁定的**動機句**（「避免被 google 等搜索引擎誤判為重複頁面」）所依賴的因果，而**我方沒有任何一手證據支持該因果** | Google Search Central 官方明文；或自建 A/B（同一內容兩組碼粒度，觀察 GSC 收錄與國別流量）——後者雜訊大、週期長 | 🔴 **按 §I.2-2 的三句實作，不按動機句實作**：碼恆帶地區（裁定，照做）＋ **後台文案與任何對外說明一律不得宣稱「加地區碼可避免重複頁面判定」**（同 §D.3／§H.6-3「只陳述機制、不宣稱效果」的既有紀律）。🔴 **即使日後查出「沒有效果」，也不得據以翻回裸碼**——碼粒度是裁定，效果是另一回事 | §I.2、§I.2-2 |
| 🔴 **V-221**<br>（2026-08-13 新增） | **根路徑 `/`（無 locale 前綴）在恆帶地區之後應該是什麼**：裁定只說「url 加入識別」，**沒有說根路徑要不要一起帶前綴**。三種可能：①`/` 重導到預設 (market, locale)（我方推導的採用值）②`/` 就是預設語言頁、與 `/en-hk/` 內容相同（🔴 那是我方自己製造的重複，正是動機句要避免的）③`/` 是一個獨立的語言選擇著陸頁 | **使用者裁定**（這是產品決策，查 Shopify 沒有用——本尊的模型是「primary 預設語言在根」，與裁定的前提不同）；`alt` 佐證：strawberrynet 觀察到**沒有裸根內容頁**，所有觀察到的頁面都帶 `{lang}-{REGION}` 前綴 | 我方採 **①**（`limits.i18n.locale_prefix.root_path_behavior: redirect_to_default_prefix`，302 非 301——預設市場可能改變）。理由：它消滅系統內**最大的一組真重複**（`/` 與 `/en-hk/` 逐位元組相同），而那比碼粒度的收益大得多（§I.2-2 結論 3）。🔴 **連帶**：x-default 必須改指帶前綴的 URL（`seo.hreflang.x_default_target`），根路徑**不得**進 sitemap 或 hreflang | §I.2、67 §F.1(b) |
| **V-222**<br>（2026-08-13 新增，低風險） | 裁定原文「如果加拿大，那就是 **ca-HK**」——我方研判為 **`en-CA`** 的筆誤（同句前半已給 `en-HK`，且 `ca-HK` 不是合法的「語言-地區」組合：`ca` 是加泰隆尼亞語的 ISO 639-1 碼，`HK` 是香港） | 使用者一句話確認 | 我方採 `en-CA`。🔴 **即使研判錯誤，受影響的也只有加拿大那一列的字面值，不影響 §I.2 的規則本身**——所以本條**不阻擋實作** | §I.2、§I.2-1 |
| **V-223**<br>（2026-08-13 新增） | **strawberrynet 的完整語言／地區矩陣**（本輪 `alt` 級觀察只確認到 `en-HK`／`en-CA`／`en-US` 三個前綴；`/zh-TW/` 與 `/zh-HK/` 兩次請求都被送到 `en-US` 的內容，未能取得繁中版本） | 以帶 `Accept-Language: zh-Hant` 與 HK 出口 IP 重取；或直接開該站的地區選單 | 🔴 **不需要結案**：`alt` 級來源本來就不能據以寫死實作（§0.3）。本條登記的用途是**誠實記錄「我方引用的對照樣本只看到三個前綴」**，避免日後有人把 §I.2 講成「業界都這樣做」。<br>🔴 **另記一條反例，它比正例有用**：該站 `/zh-TW/` 回應的 canonical 是 `https://www.strawberrynet.com/en-US` ⇒ **同一條 URL 對不同客戶端回不同語言的內容**，那正是我方 §0.2 原則 4 與 67 §F.2 明文禁止的形態。**這個對照樣本在「URL 形態」上可借鑑，在「重導行為」上是反面教材，兩者不得一起抄** | §I.2-2、67 §A.5 |

---

## 附錄 B · 本輪查證的來源（查證日 2026-08-12）

**Google（`google`）**
`developers.google.com/search/docs/appearance/ai-features`（AI 功能無額外要求、無需新檔案／schema；nosnippet 系列控制）｜`/docs/appearance/structured-data/merchant-listing`（必填屬性、price 數值格式、ISO 4217、availability 枚舉、priceValidUntil 過期不顯示）｜`/docs/appearance/structured-data/product-variants`（ProductGroup／productGroupID／variesBy／hasVariant／inProductGroupWithID；單頁站唯一 canonical 規則）｜`/docs/appearance/structured-data/product`（兩種產品體驗的入口）｜`/docs/specialty/international/localized-versions`（hreflang 碼格式含 ISO 15924 `zh-Hant`、雙向性、x-default、三種實作法、常見錯誤）｜`/docs/specialty/international/managing-multi-regional-sites`（四種 URL 結構取捨、避免自動重導、IP 判斷不可靠、重複內容處置）｜`/docs/crawling-indexing/google-common-crawlers`（Google-Extended 定義與「不影響搜尋收錄與排名」）

**OpenAI（`openai`）**
`developers.openai.com/api/docs/bots`（`OAI-SearchBot`／`GPTBot`／`OAI-AdsBot`／`ChatGPT-User` 的用途、UA 字串、封鎖後果、robots 規則對使用者觸發可能不適用）

**Shopify 開發文檔（`dev`）**
`shopify.dev/changelog/customize-llmstxt-llms-fulltxt-and-agentsmd`（2026-05-28；三個模板與 fallback 鏈）｜`shopify.dev/docs/storefronts/themes/architecture/templates/agents-md-liquid`（受限 context、`agents` 物件七欄、不可在地化、裸主網域）｜`shopify.dev/docs/storefronts/themes/seo`（三個子題）｜`/themes/seo/metadata`（`page_title`／`page_description`／`canonical_url` 模式）｜`/themes/seo/hreflang`（自動經 `content_for_header`、單國 vs 多國的碼粒度、可在後台關閉、自訂與自動並存的風險）｜`/themes/architecture/templates/robots-txt-liquid`（`robots` 物件與擴充建議）｜`shopify.dev/changelog/liquid-structured_data-filter-supports-productgroup`（2024-07-16 改用 ProductGroup）｜`shopify.dev/docs/apps/build/storefront-mcp/servers/storefront`（`/api/mcp` 與 `/api/ucp/mcp` 的工具清單、免認證）｜`shopify.dev/docs/agents`（UCP 實作面：profile、Catalog／Cart／Checkout／Order MCP、訂單 webhook）

**Shopify 商家文檔（`help`）**
`help.shopify.com/zh-TW/manual/promoting-marketing/seo`（該區 11 個子題，含 Shopify Catalog 與「為 AI 最佳化」）｜`/seo/adding-keywords`（標題 70 字元上限、建議 60、描述建議 160、留空時主題以店名＋內容標題組合）｜`/seo/hide-a-page-from-search-engines`（`<meta name="robots" content="noindex">` 條件注入、`seo.hidden` metafield、Unlisted 狀態、仍可被站內搜尋找到）｜`/seo/find-site-map`（`sitemap.xml` ＋ 子 sitemap、國際網域各自產生、多語言自動加入）｜`/seo/optimizing-store-for-ai`（PDP 資訊完整度建議、Knowledge Base 產生 FAQ）｜`/seo/shopify-catalog`＋`/shopify-catalog/optimizing-products`（自動納入不可退出、可逐通路限制；被考慮的商品欄位清單）｜`/manual/markets/seo`（自動 hreflang、各市場 self-canonical、三種網域結構的 SEO 後果、sitemap 自動更新、**爬蟲排除於自動重導之外**）｜`/manual/online-sales-channels/agentic-storefronts`（四個 AI 通路、`Sales channels > Agentic`、符合資格預設啟用、ChatGPT 為導流型）

**代理商務協定（`ucp`）**
`ucp.dev/2026-04-08/specification/overview/`（`/.well-known/ucp` profile 結構、Cart／Checkout／Order／Identity Linking、MCP 傳輸、反向網域命名、簽章與 `Cache-Control` 要求）｜`shopify.engineering/UCP`（2026-01-11，與 Google 共同發起）｜`agenticcommerce.dev`（ACP：Stripe＋OpenAI、Apache-2.0、REST 與 MCP 相容）

**學術**
`arxiv.org/abs/2311.09735`（GEO: Generative Engine Optimization，KDD 2024；GEO-Bench；可見度最高 +40%；領域差異大）

**第三方商店對照（`alt`，一律登記 V；🔴 存在性佐證，不是規範來源）**（觀察日 **2026-08-13**，工具＝WebFetch，⇒ **V-223**）
`www.strawberrynet.com/en-HK`（canonical 逐字 `https://www.strawberrynet.com/en-HK`）｜`/en-CA/`（canonical 逐字 `https://www.strawberrynet.com/en-CA`）⇒ **URL 前綴形態恆為 `{lang}-{REGION}`，未觀察到任何裸語言前綴，也未觀察到裸根內容頁**（V-221 的 `alt` 佐證）｜header 只有**一個**合併的「Country / Region」控件（`lang-icon.svg`），**不是**語言與地區兩個切換器｜🔴 **反面觀察**：`/zh-TW/` 與 `/zh-HK/` 兩次請求取得的內容其 canonical 均為 `https://www.strawberrynet.com/en-US` ⇒ 同一 URL 對不同客戶端回不同語言，**違反我方 §0.2 原則 4／67 §F.2**｜`/robots.txt` **無 `Sitemap:` 行**、以 `/*/` 萬用字元涵蓋所有 locale ⇒ 與我方 §D.1「平台保底注入 `Sitemap:` 行」相反｜`<head>` 中**未觀察到 hreflang 標註**
> 🔴 **這一段的用法只有一種**：證明「恆帶地區的前綴」在真實世界跑得起來（§I.2-1、67 §F.1(b)）。**其餘四項觀察全部是我方明文禁止的做法**，列在這裡是為了讓下一個人知道**我們看過、而且刻意不抄**——不是漏看。

**二手（`press`，一律登記 V）**
Search Engine Journal「Google 說 llms.txt 目前純屬臆測」（2026-06，轉述 John Mueller）⇒ V-117｜多家報導 Google 於 2026-05 移除 FAQ 富摘要（與 30 §2.4 一致）｜Shopify 企業部落格自述 Q1 2026 AI 導流數據（廠商自述，不作規格依據）

> **時效警報**（承 30 號檔尾）：①Content API for Shopping **2026-08-18 落日**（六天後）——feed 一律直接走 Merchant API；②GMC 圖片 500×500 於 2027-01-31 強制；③UCP 規格版本以日期命名（`2026-04-08`），**版本會滾動**，任何 UCP 相關實作都要把版本當變數而不是常數。
