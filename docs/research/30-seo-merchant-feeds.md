# 30 — SEO・Merchant Center・社媒 Feed・Simprosys 對接（官方要求全景）

> 目標：平台生成的每個租戶店面**預設即合規**——Google Search / Bing / IndexNow / Google & Microsoft Merchant Center / Meta・TikTok・Pinterest catalog。本文＝官方文檔深研成果（developers.google.com/search、support.google.com/merchants、Bing/IndexNow、simprosysapis.com OpenAPI spec，查證日 2026-08-11）＋平台落地清單。SEO 渲染面在 M2 隨 storefront 落地；feed 生成器排 M5+。

## 1. Google Search Essentials 與電商必做

### 1.1 技術門檻
Googlebot 可抓（robots.txt ≤500KiB、4xx=無限制、5xx=12h 暫停）、頁面回 200、SSR 完整 HTML。狀態碼語義：301/308 強訊號、302/307 弱訊號、redirect ≤10 hops；**404 與 410 等同**（移出索引）；429 → 減速抓取；**soft-404 嚴禁**（下架商品絕不可回 200 空殼頁）。

### 1.2 Spam policies（產品層要防租戶觸犯）
cloaking、doorway、hidden text/links、keyword stuffing、link spam、**scaled content abuse**（AI 大量低質頁）、scraping、sneaky redirects、thin affiliation 等 15 條。

### 1.3 電商必做清單

| 主題 | 規則 | 平台實作 |
|---|---|---|
| Canonical 三訊號 | redirect > rel=canonical > sitemap；**絕對 URL、每頁自引** | 全頁 self-canonical 引擎 |
| **變體 URL** | 官方：以 query 標識變體時，**canonical=省略該參數的 URL** | `?variant=` → canonical 至 `/products/{handle}`＋ProductGroup 標記 |
| Faceted navigation | 預設不讓 facet URL 被抓；空結果組合回 404 | robots.txt 預設 disallow `?sort_by=`/`?filter.*`；過濾頁 canonical 至基底 |
| Pagination | rel=prev/next 已死；`?page=n` 各頁 **self-canonical（勿指向第一頁）**＋`<a href>` 互鏈；infinite scroll 必須有 paginated URL 後備 | collection 分頁規則寫進主題要求 |
| 404 紀律 | 下架→410 或 301 至最相關頁 | 商品 unpublish 預設 410，可選 301 |
| Site move | 全量 301 ≥1 年＋GSC Change of Address | 換域名精靈 |

## 2. 結構化資料（JSON-LD）欄位表

Google 兩套體驗：**Merchant listing**（可購買 PDP；較嚴：offers 必須 `Offer` 非 AggregateOffer、price>0、priceCurrency/image 必填）vs **Product snippet**（name＋review/rating/offers 三擇一）。兩份 GSC 報告分開監控。

### 2.1 Product（merchant listing）
必填：`name`、`image`（≥50,000px²，建議 16:9/4:3/1:1 三比例）、`offers(Offer)`。建議：`description/sku/gtin/mpn/brand.name/color/material/pattern/size/audience/aggregateRating/review/inProductGroupWithID`。

### 2.2 Offer
必填：`price`+`priceCurrency`（ISO 4217）。建議：`availability`（InStock/OutOfStock/PreOrder/BackOrder…9 枚舉）、`itemCondition`（New/Refurbished/Used）、`priceValidUntil`（**過期→不顯示**）、促銷用 `priceSpecification.priceType: StrikethroughPrice`（原價）＋offers.price（現價）、**`shippingDetails`（OfferShippingDetails：shippingRate/shippingDestination/deliveryTime{handlingTime,transitTime}）**、**`hasMerchantReturnPolicy`（applicableCountry/returnPolicyCategory/merchantReturnDays/returnMethod/returnFees）——可在 Organization 層全站宣告一次**。

### 2.3 ProductGroup（變體）
`name`＋`productGroupID`（=item_group_id）＋`variesBy`（color/size/material/pattern/suggestedAge/suggestedGender）＋`hasVariant[]`（每變體唯一 SKU/GTIN）。**單頁 PDP：canonical URL 不預選變體；各變體可經獨立 URL 直接預選**。

### 2.4 其他
- AggregateRating（ratingValue＋ratingCount|reviewCount）/Review（author<100 字元、reviewRating）；禁自評自家。
- BreadcrumbList（≥2 ListItem、position 自 1、末項可省 item）。
- Organization（logo ≥112×112；**hasMerchantReturnPolicy/hasShippingService 全站宣告點**）。
- **WebSite+SearchAction（sitelinks searchbox）已落日（2024-11）——不實作**；**FAQPage 已死（2026-05 完全停顯）——不投資**；VideoObject（name/thumbnailUrl/uploadDate 必填）。

## 3. Sitemap

單檔 ≤50,000 URL/50MB → index 分片；`lastmod` 僅在「持續可驗證準確」時被信任（=實質更新時間，勿灌水）；**priority/changefreq 一律忽略**；image 擴充（每 URL ≤1,000 圖）；hreflang 擴充（xhtml:link 全集互指含自身）；**Google ping endpoint 已移除（2024-01）——不要實作 ping**；只列 canonical、只列 200。

**平台策略**：`/sitemap.xml`（index）→ `sitemap_products_{n}.xml` / `sitemap_collections_{n}.xml` / `sitemap_pages_{n}.xml` / `sitemap_blogs_{n}.xml`；動態生成＋edge cache（商品變更事件失效）；robots.txt 注入 `Sitemap:` 行。

## 4. Core Web Vitals

| 指標 | Good | 量測 |
|---|---|---|
| LCP | ≤2.5s | CrUX 75 百分位 |
| INP | ≤200ms | 同上 |
| CLS | ≤0.1 | 同上 |

SSR 達標要點：edge cache TTFB、LCP 主圖 preload＋fetchpriority=high＋**不 lazy-load 首屏**、全圖 width/height（CLS）、字體 swap+preload、第三方 script idle 延載、主題編輯器警示注入 script 的 CWV 影響。

## 5. Bing 與 IndexNow

- Bing 排名因子官方列名：relevance、quality/credibility、**user engagement**、freshness、location、page load time；支援 `crawl-delay`、OpenGraph；BWT 驗證可自 GSC 一鍵匯入。
- **IndexNow 協議**：key 8–128 字元 → `/{key}.txt`；批量 `POST api.indexnow.org/indexnow`（host/key/urlList，**≤10,000/次**）；回應 200/202/400/403/422/429(Retry-After)；提交一處自動分享 **Bing/Amazon/Naver/Seznam/Yandex/Yep**；**Google 不參與**（走 sitemap）；同 URL 變更間隔 ≥5 分鐘。

## 6. Google Merchant Center

### 6.1 產品資料規格（分級）
- **一律必填**：`id`（≤50，建後不可變）、`title`（≤150）、`description`（≤5,000）、`link`（已 claim 網域）、`image_link`（**最低 500×500 於 2027-01-31 強制；建議 ≥1500×1500**；禁浮水印/促銷字）、`availability`（in_stock/out_of_stock/preorder/backorder）、`price`（`15.00 USD`；US/CA 不含稅、其他含稅）。
- **條件必填**：`availability_date`（preorder 時）、`brand`（新品）、`gtin`（有即必填）、`mpn`+brand（無 GTIN）、`identifier_exists:no`（都無）、`condition`、`adult`、**`item_group_id`（有變體即必填=父 SKU）**、服飾類 `age_group/color/gender/size`、`shipping`（29+ 國強制運費資訊）、EU 能效 `certification`。
- **選填重點**：`additional_image_link`（≤10）、`sale_price`(+effective_date)、`google_product_category`（數字 ID）、`product_type`、`custom_label_0-4`、`short_title`、`product_highlight`、`unit_pricing_measure`、`shipping_weight`、`video_link`、`canonical_link`。

### 6.2 遞交與品質
- Feed 格式：TSV/XML RSS 2.0/Sheets；≤4GB；URL scheduled fetch/SFTP。**API：Content API for Shopping 2026-08-18 落日——一律直接實作 Merchant API（2025 GA；子 API：Accounts/Products/DataSources/Inventories/Promotions/Reports/Batch）**。
- **品質硬規則**：feed 與 landing page 價格/庫存必須一致（misrepresentation→拒登/停權）；**automatic item updates 以頁面 JSON-LD 即時校正**——JSON-LD 與 feed 必須同一資料源生成。
- 驗證與 claim：HTML tag/檔案/GTM/GA/GSC 關聯；一 URL 一帳號 claim；**平台申請 MCA（advanced account）代管租戶子帳號**。

## 7. Microsoft Merchant Center

屬性名與 Google 同名同義（Google 規格為超集）；**MMC 內建「Import from Google Merchant Center」**或共用同一份 feed 檔；免費刊登（Bing Shopping tab）上傳即參加；UET tag（dynamic remarketing 需事件帶 `prodid`+`pagetype` 對上 feed id）；網域驗證走 BWT。

## 8. 社媒 Catalog 對映（以 GMC 為 canonical schema）

| 欄位 | Meta | TikTok | Pinterest |
|---|---|---|---|
| id/title/description/availability/price/link/image_link | 必填（availability 枚舉帶空格 `in stock`） | 必填（id→`sku_id`） | 必填 |
| brand | 必填 | 必填 | 選填 |
| google_product_category | 支援 | **必填** | 支援 |
| item_group_id | 變體必用 | 選填 | 變體必填 |
| feed 格式 | CSV/TSV/XML(g: namespace)/API | CSV/API/排程抓取 | TSV/CSV/XML；每日抓取 |

**結論：單一 GMC 規格生成器＋per-channel 轉換層**（欄名改寫、枚舉映射、欄位裁剪）覆蓋四平台。

## 9. 平台落地清單（必實作）

| # | 功能 | 規格 |
|---|---|---|
| 1 | sitemap 端點 | index+四類分片；lastmod=實質更新；products 片含 image 擴充；multi-market 含 xhtml:link 全集 |
| 2 | robots.txt.liquid | 預設 disallow /cart /checkout /account /search、facet 參數；自動 Sitemap: 行；租戶可覆寫但 lint |
| 3 | Canonical 引擎 | 全頁 self-canonical；?variant=/追蹤參數→基底；分頁 self-canonical；平台子網域 301 至自訂網域 |
| 4 | JSON-LD 注入分工 | 平台層不可關閉：Organization（含全站退貨/運費宣告）+BreadcrumbList+Product/Offer/ProductGroup；評論經 metafield 供給；主題 structured_data filter 可擴充；平台驗證輸出。不做 FAQPage/SearchAction |
| 5 | 404/410 紀律 | 下架預設 410；空 facet 404；禁 soft-404 |
| 6 | Site move 精靈 | 全量 301＋雙 sitemap＋GSC 指引 |
| 7 | CWV 預算 | 主題審核門檻 LCP≤2.5/INP≤200/CLS≤0.1；圖片管線 WebP/AVIF+srcset+尺寸屬性 |
| 8 | **Feed 生成器** | 欄位對映（我方模型→GMC）：variant.sku→id、title+變體屬性→title（≤150）、compare_at 存在時 price=compare_at+sale_price=售價、vendor→brand、barcode→gtin（GS1 校驗）、product.id→item_group_id、平台分類→GPC ID 映射表、tags 規則引擎→custom_label_0-4；輸出 `/feeds/google/{market}.xml`(RSS)+`.tsv` 供 GMC scheduled fetch/MMC 共用/社媒轉換層；**Merchant API 即時推送**（增量：改價/庫存事件） |
| 9 | IndexNow | 每 shop 產 key＋`/{key}.txt` 路由；觸發：publish/改價/庫存狀態變/unpublish/URL 變更；批量 ≤10,000；去抖 ≥5 分鐘；429 退避 |
| 10 | 站長驗證支援 | meta tag 槽（google-site-verification/msvalidate.01）、檔案路由、DNS 指引；GMC claim 衝突偵測 |
| 11 | 追蹤注入槽 | UET/GA4/Meta Pixel ID 欄位化設定（content_id=feed id）；idle 延載 |
| 12 | hreflang×Markets | 銜接 29 號：代碼僅 ISO 639-1(+3166-1)白名單（**es-419 不支援**）；GMC 每 target country/language 分 feed |
| 13 | 監控 | GSC API（兩份商品報告/CWV/sitemap）、GMC Reports 拒登率、IndexNow 回應碼儀表板 |

## 10. Simprosys 對接契約（simprosysapis.com 實證研究）

### 10.1 核心發現
1. **SimprosysAPIs 官方定位就是給「非 Shopify 自建平台」的 feed 管理通道**（"Feed Management for Self-Hosted E-Commerce Stores"）——**不需要偽裝成 Shopify**。
2. 模型＝**純資料倒入（push-ingestion）**：我們推 products/variants/locations/local-inventory/orders → feed 生成優化與提交 **Google/Microsoft/Meta/Klaviyo** 在其後台完成。
3. OpenAPI 3.1 spec 實證（`developers.simprosysapis.com/api/v1/openapi.json`，34 端點）；**無 webhooks、無 feed 設定端點、無 pixel 端點**（狀態靠 Task Status 輪詢）；**無「拉取我們 feed URL」模式**——不要規劃。
4. 認證：`POST /api/v1/token/`（client_id+client_secret→Bearer access+refresh）；憑證綁 IP/domain 白名單（error 1105）。
5. 現階段免費、商業條款未定（風險）；**SHOPLINE 先例**：Simprosys 曾為同類 SaaS 上架專屬 app——平台級合作可談。

### 10.2 端點與限制摘要
- Products/Variants/Locations/Local-Inventory/Orders 各有單筆＋bulk 端點（`POST/PUT/DELETE /api/v1/(bulk-)products/` 等）；`GET /api/v1/status/{shop_id}/{task_id}` 輪詢。
- 限流：單筆 **500 req/60s**、批次 **20 req/60s**（429）；批量上限 **500 products/批、200 variants/product、2000 variants/批**。
- 變體模型欄位≈GMC 屬性集全集（§6.1）＋`offer_id`（必填）＋`pause`＋`cogs`＋return_policy_label。
- Orders 模型供 Google **Delivery Speed Estimates**（shipment/carrier/shipped_time/delivery promise/postal codes）。

### 10.3 整合方案（雙軌決策）
- **主案＝自建 feed 底座**（§9-8：GMC 規格生成器＋Merchant API＋per-channel 轉換）——電商 SaaS 基本盤，不可外包，避免單一 vendor 依賴。
- **加值案＝SimprosysAPIs connector**：我們平台需具備——①商品欄位完整度（缺口：gtin/google_product_category/gender/age_group/custom_label →「行銷屬性」欄位組＋metafields）；②變更事件管線（自家 webhooks：products/update、inventory_levels/update、orders/create → queue → 差異同步）；③限流整形（bulk 20 req/min＝每分鐘至多 1 萬商品/憑證，多租戶共用出口需全域排程）；④每商家一組 store 憑證（加密保管＋refresh 輪換＋固定出口 IP）；⑤訂單餵送（可選 feature：Delivery Speed Estimates）。
- **放棄**：偽裝 Shopify 讓其 Shopify app 直接安裝（數人年、vendor 不配合）。長期若建 app 生態，循 SHOPLINE 先例洽談專屬 app。
- **商務洽談項**：partner 級多租戶開通與計價、白牌、webhook 回呼、TikTok/Pinterest roadmap（其 API 產品現不含）。

> 來源：developers.google.com/search（essentials/spam/ecommerce/structured-data/sitemaps/robots/hreflang）、web.dev/vitals、support.google.com/merchants/answer/{7052112,9199328,3246284,176793}、developers.google.com/merchant/api、bing.com/webmasters、indexnow.org/documentation、learn.microsoft.com UET、developers.facebook.com commerce catalog、help.pinterest.com catalogs、simprosysapis.com＋developers.simprosysapis.com OpenAPI spec＋apps.shopify.com/google-shopping-feed＋SHOPLINE app store。查證日 2026-08-11。
> **時效警報**：①Content API for Shopping **2026-08-18 落日**（一週後！）——feed 服務直接以 Merchant API 實作；②GMC 圖片 500×500 於 2027-01-31 強制；③FAQPage/sitelinks searchbox 已移除，不投入。
