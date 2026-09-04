# E12 computed-CSS 對表：鐵律 22.1「精確到 CSS 級別」的量測工具與首輪結果（2026-09-04）

> 規範：鐵律 22（D82／D83）——「一樣」＝每個元素的 computed style 逐屬性相等；憑證在倉庫（22.4）。
> 本檔＝工具契約、量測方法、已知例外與首輪結果；HTML 段 diff 見 `docs/dev/e8-render-parity.md`。

## §0 工具：`scripts/computed-parity.mjs`

- **零新依賴**（鐵律 1）：Node ≥ 22 內建 `WebSocket`／`fetch`；本機 Chrome（`--chrome <path>` 或 `CHROME_PATH`，預設 Windows 安裝路徑）以
  `--headless=new --disable-extensions --user-data-dir=<暫存乾淨 profile>` 啟動，經 CDP 操作。乾淨 profile ⇒ 沒有使用者擴充功能的
  `font-weight:500 !important` 注入（memory `measurement-env-contamination`；鐵律 22.4 量測環境消融）。
- 子命令：
  - `capture <url> <out.json> [--width 1280] [--height 900] [--wait 1500] [--open-details 1] [--cookie "n=v; n2=v2"]`：（E13：`--cookie` 導航前以
    `Network.setCookie` 設到目標 URL，量登入牆後的編輯器預覽；JSON 只記 cookie name；E14：`--block "pat1,pat2"` 導航前
    `Network.setBlockedURLs`，擋本尊編輯器執行期才量得到設計模式頁，JSON 記 `blocked`）`Page.navigate` → `loadEventFired` →
    `document.fonts.ready` → settle → 逐元素收集（見 §1）；另記診斷（頁內例外、console error／warn、載入失敗、4xx／5xx）。
  - `diff <ref.json> <cand.json> [--out report.md] [--limit 60]`：逐段（section wrapper）→ 逐元素（鍵）→ 逐屬性；輸出段落表＋差異明細。
  - `inspect <url> <selector> [--props a,b] [--all 1]`：`CSS.getMatchedStylesForNode` 列命中規則（來源樣式表、selector、宣告）。
  - `evaljs <url> <js|--file path>`：頁面載入後執行 JS 印 JSON——取證用（鐵律 14／19）。
  - `selftest`：同形全同／屬性差／幾何差／缺元素／身分差抹除／score 定義各一格。
- 元素鍵＝所屬 `shopify-section-*` wrapper id 正規化（`template--{id}__`⇒`template--T__`、`sections--{id}__`⇒`sections--G__`、
  theme block 實例前綴 `A{17}__`⇒`B__`；同 `RenderParity::Normalizer` 的身分規則）＋自 section 根起的 `tag[:nth-of-type]` 路徑。
- 比對屬性：89 個 computed 屬性（盒模型／定位／字型／顏色／背景／flex／grid／transform／陰影等，清單在檔內 `PROPS`）＋
  `getBoundingClientRect` 四值。px 值容差 0.5（次像素文字量測噪音；rect 同）；其餘字串精確比對。
- 值正規化只抹身分差：主機、`/cdn/shop/t/{n}/assets/`⇒`/theme-assets/`、`?v=`、`data:` 內容。
- score＝段內「逐屬性全同的元素數 ／ max(ref 元素數, cand 元素數)」；段落「全同」＝零差異（含元素集合相同）。

## §1 量測方法與已知例外

1. **內嵌 `<svg>` 只比自身的盒，不進入子節點**：佔位插圖本體是鐵律 22.3 唯一例外（HTML 對表以 `[placeholder]` 抹本體；Ella 的
   `image_url` 佔位 svg 沒有 `placeholder-svg` class），圖示 path 幾何由 svg 盒＋viewBox 決定、標記差由 HTML 對表負責。
   首輪未跳過時，marquee／media_gallery／collection_list 的差異全部落在佔位 `svg>g>path`（本尊插圖 vs 我方自繪）。
2. **`--open-details 1`**：Ella 把搜尋 modal／選單放在 `<details>`；關閉狀態下該子樹兩邊都有 layout，但報告值可能不同——
   首輪 header 的搜尋圖示 `svg` 我方 25px、本尊 18px **只出現在關閉的 details 內**（同頁 inline 搜尋兩邊皆 18px；
   `inspect` 顯示命中規則完全相同、`el.style.setProperty('width','1.8rem','important')` 亦不改變、改 `flex` 才改變）。開啟後
   header 段 87/87 全同。判定：關閉 details 子樹的差異不是使用者看得到的形，一律以開啟狀態量；根因未取得（V，91 §3.79）。
3. **本尊 CDN 對主題 CSS 做過處理**：hoko `base.css` 399,482 bytes（壓縮、`-webkit-appearance` 前綴、巢狀攤平成
   `.field__button>.svg-wrapper{…}`），我方直出原檔 461,215 bytes（含 CSS nesting `.field__button { > .svg-wrapper {…} }`）。
   Chrome 152 對原檔巢狀語法的 computed 結果與攤平版相同（本輪全部段落證據）；處理管線本身官方未逐字（V）。
4. **本尊平台注入不比**（22.3）：`body>div>iframe`（shop-pay hop）、`shop-cart-sync`、與其造成的 `body` `grid-template-rows` 多一列 0px。
5. 診斷不是對表結果：首輪兩邊都只有 `favicon.ico` 404；本尊另有 `shop.app/pay/hop` 403（平台）。

## §1b 由 computed 對表抓到的引擎缺口（本包修法）

| # | 形差 | 本尊證據 | 我方修法 | 規格 |
|---|---|---|---|---|
| 1 | `image_url` 對 nil | hoko 商品頁 `<div class="sticky-atc__media">Liquid error (blocks/_sticky-add-to-cart line 96): invalid url input</div>`；同頁 `data-product-variant-media=""` 是同錯誤在 `{% assign %}` 裡被吞（Liquid 5.13 本機探針同形） | nil ⇒ `raise Liquid::ArgumentError, "invalid url input"`（先前回空字串 ⇒ image_tag 退佔位 ⇒ sticky-atc 多 800px 圖）；**更正 e8 #52** | PP14 |
| 2 | Section Rendering API 只在三個端點 | 官方 "this parameter can be used to render a section in the context of any page"；hoko recently-viewed JS 打 `/search?section_id=…&q=` 拿段 HTML（3.7KB），我方回整頁（324KB）⇒ 警告區塊可見 | `PagesController#show` 對任何路徑處理 `section_id`／`sections`（no-store、404／400、JSON） | SR1–SR4 |
| 4 | SRA 端點的語言 | hoko 商品頁「Related products」卡片按鈕「售罄」（32px）／「加入购物车」（80px）；我方「Sold out」／「Add to cart」（74／99px）——三支 SRA renderer 一律 `locale: nil` | `BaseController#locale_hit`（前綴 ⇒ 市場／語言／presence），recommendations／search suggest／cart sections 三支帶 locale；PagesController 的 SRA 本就經 `render_page` | SF-9 |
| 5 | 外部影片 `preview_image` | 官方 objects/media "A preview image of the media."；`image_url` 對 nil＝錯誤（#1）⇒ 真 Ella 商品圖庫（EG1）與 Minimog 分享連結（TC-M1）對無縮圖／無圖資料印錯誤 | `ExternalVideoMediaDrop#preview_image`：YouTube 供應商縮圖 `ExternalPreviewImageDrop`（`image_url` 直出 URL）；Vimeo 未做（V）；一致性 fixture 商品給圖 | PP21、EG1、TC-M1 |
| 3 | recommendations 共同系列不足 | hoko acme-tee 只在「首頁」系列，`/recommendations/products?section_id=…` 回 bolt-mug、cosy-lamp（皆不在該系列）；我方回空 ⇒ skeleton 不換 | 共同系列成員之後以其他可見商品依建立序補到 limit（規則 V） | R4 |

## §2 首輪結果（open-details；本機 Chrome 152 headless；ref＝hoko.vip live；2026-09-04；報告在 scratchpad `computed/report-*.md`，重跑即得）

| 頁面 | 寬 | cand | 段落逐屬性全同／總數 | 未全同的段落與原因 |
|---|---|---|---|---|
| / | 1280 | mirror.chilling.com.hk（E8b 部署 7e20cc5e） | 20/21 | `__root__`：本尊平台 iframe／`shop-cart-sync`（§1-4） |
| / | 768 | 同上 | 20/21 | 同上 |
| / | 390 | 同上 | 20/21 | 同上 |
| /collections/all | 1280 | 同上 | 14/15 | `__root__` |
| /collections/frontpage | 1280 | 同上 | 14/15 | `__root__` |
| /pages/contact | 1280 | 同上 | 15/16 | `__root__` |
| /search | 1280 | 同上 | 11/12 | `__root__` |
| /cart | 1280 | 同上 | 14/15 | `__root__` |
| /nope（404） | 1280 | 同上 | 11/12 | `__root__` |
| /products/acme-tee | 1280 | 同上（本包修法前） | 10/15 | recently_viewed（SRA 回整頁）、product_recommendations（無補位 ⇒ skeleton）、footer（上方高度差連動）、main（sticky-atc 多 800px 佔位圖＋countdown＋payment button）、`__root__` |
| /products/acme-tee | 1280 | 本機 dev（本包修法後，mirror.lvh.me:3000） | 13/15 | `main`：countdown 秒數文字（時間性）＋本尊 `shopify-accelerated-checkout`（平台結帳，91 ⚪）；`__root__` |

| /products/acme-tee | 1280 | mirror.chilling.com.hk（E12 部署 83e85398 後） | 13/15 | template--T__main、__root__（main＝countdown 時間性＋本尊 payment button；`__root__`＝平台注入） |
| /collections/all | 768 | mirror.chilling.com.hk（83e85398） | 14/15 | __root__ |
| /collections/frontpage | 768 | mirror.chilling.com.hk（83e85398） | 14/15 | __root__ |
| /products/acme-tee | 768 | mirror.chilling.com.hk（83e85398） | 13/15 | template--T__main、__root__ |
| /pages/contact | 768 | mirror.chilling.com.hk（83e85398） | 15/16 | __root__ |
| /search | 768 | mirror.chilling.com.hk（83e85398） | 11/12 | __root__ |
| /cart | 768 | mirror.chilling.com.hk（83e85398） | 14/15 | __root__ |
| /nope（404） | 768 | mirror.chilling.com.hk（83e85398） | 11/12 | __root__ |
| /collections/all | 390 | mirror.chilling.com.hk（83e85398） | 14/15 | __root__ |
| /collections/frontpage | 390 | mirror.chilling.com.hk（83e85398） | 14/15 | __root__ |
| /products/acme-tee | 390 | mirror.chilling.com.hk（83e85398） | 13/15 | template--T__main、__root__ |
| /pages/contact | 390 | mirror.chilling.com.hk（83e85398） | 15/16 | __root__ |
| /search | 390 | mirror.chilling.com.hk（83e85398） | 11/12 | __root__ |
| /cart | 390 | mirror.chilling.com.hk（83e85398） | 14/15 | __root__ |
| /nope（404） | 390 | mirror.chilling.com.hk（83e85398） | 11/12 | __root__ |

（2026-09-05 部署 83e85398 後追加：上表後半。）

### §2b E15（2026-09-04；真店改為五語言五市場後，鏡像店同步＋`localization.available_countries`；本機 dev `mirror.lvh.me:3000` vs hoko live）

| 頁面 | 1280 | 768 | 390 | 非全同段 |
|---|---|---|---|---|
| / | 20/21 | 20/21 | 19/21 | `__root__`；390 promotion_popup（擷取時序，見下） |
| /collections/all | 12/15 | 14/15 | 14/15 | `__root__`；1280 promotion_popup＋multitasking_bar（時序） |
| /collections/frontpage | 14/15 | 14/15 | 14/15 | `__root__` |
| /products/acme-tee | 11/15 | 13/15 | 12/15 | `__root__`、`template--T__main`（countdown＋payment button）；1280／390 promotion_popup（時序） |
| /pages/contact | 15/16 | 15/16 | 15/16 | `__root__` |
| /search | 11/12 | 11/12 | 11/12 | `__root__` |
| /cart | 14/15 | 13/15 | 14/15 | `__root__`；768 promotion_popup（時序） |
| /nope（404） | 11/12 | 11/12 | 11/12 | `__root__` |

- 與 §2 基線逐頁逐寬相同；頁首 `header_default` 段在五語言五市場下三寬全同（語言鈕＋section-fetcher 形，e8 §2c #66）。
- **promotion_popup／multitasking_bar 為擷取時序項**：Ella `<promotion-popup data-delay="10000">` 自 connectedCallback 起 10 秒開啟並給 `body.overflow-hidden`；
  本機 dev server 資產慢送使 `loadEventFired` 晚於 10 秒，擷取點落在開啟後（diff＝`visibility hidden→visible`、`body overflow-y visible→clip`、
  multitasking bar x 位移 1px）；同頁另一寬度資產已暖即全同；bt3（nginx）在 §2 同頁無此差。部署後 bt3 重跑結果見 E15 handoff／後續追加。

## §3 未取得／範圍外（登記 91 §3.79）

- 關閉 `<details>` 子樹的報告值差根因；Shopify CDN 的 CSS 處理管線（壓縮／autoprefixer／nesting 攤平的確切規則）。
- 768／390 兩寬（鐵律 13 三裝置）：首頁三寬皆 20/21；其餘七頁只跑 1280，兩寬待補。
- recommendations 補位規則、關閉 details 子樹報告值差、CDN CSS 管線、countdown 時間性內容：見 91 §3.79。
- 編輯器預覽這一半（鐵律 22.1「兩者皆是」）：E13 已做——`docs/dev/e13-theme-editor-preview-parity.md`（`--cookie` 量法、三項預覽缺口、
  主題自定義的設計模式差異、本尊編輯器擷取未取得 91 §3.80）。
