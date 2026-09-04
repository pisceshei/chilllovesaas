# E13 主題編輯器 live preview 的 computed-CSS 對表（鐵律 22.1「兩者皆是」，2026-09-04）

> 規範：鐵律 22（D82／D83）——編輯器預覽與買家前台**兩者**都必須與本尊逐屬性相同；憑證在倉庫（22.4）。
> 工具契約與買家前台結果見 `docs/dev/e12-computed-parity.md`；本檔＝編輯器預覽這一半：量法、抓到的三個引擎缺口、結果、
> 主題自己定義的設計模式差異、與尚未取得的本尊編輯器擷取。

## §0 量法：預覽在 staff 閘後，工具加 `--cookie`

- 我方編輯器預覽 iframe＝`/admin/store/preview/{theme_id}{path}?editor=1`（`Admin::StorefrontPreviewController#show`，`design_mode: true`），
  在 `authenticate_staff!` 之後。`scripts/computed-parity.mjs` 的 `capture`／`inspect`／`evaljs` 自本包起接受
  `--cookie "name=value; name2=value2"`：導航前以 CDP `Network.setCookie` 設到目標 URL；JSON 只記 cookie **name**（`cookies` 欄），值不落檔。
- 本機取 staff session cookie **不經登入表單、不碰密碼**：`rails runner` 建 `UserStoreAssignment`（staff→店）＋
  `Session.issue!`（短效）＋以 `ActionDispatch::Request#cookie_jar.encrypted[Rails.application.config.session_options[:key]]`
  產生 `_cl_admin` 加密值，再 `Rack::Utils.escape`（瀏覽器持有的是 Set-Cookie 的 escape 形——未 escape 的 `+` 會被 Rack 讀成空格、
  簽名失效、每個請求都是新 session ⇒ 302 /login，本包首輪即此）。腳本＝scratchpad `issue_local_session.rb`（倉庫外；產物是憑證）。
- 兩邊同寬同高、同 `--open-details 1`、同 `--wait 3000`；ref＝本機店面 `http://mirror.lvh.me:3000/zh-hans-tw{path}`（同一引擎、同一資料、
  同一 Chrome）與 hoko.vip live 兩組基準各一份報告。

## §1 抓到的引擎缺口（三項，全部修於本包）

| # | 現象（computed 對表） | 根因 | 修法 | 規格 |
|---|---|---|---|---|
| 1 | 預覽首輪 21 段 0 段全同、元素 1494 vs 1247；診斷 http≥400＝22、`Uncaught (in promise) Event` | 預覽的每個主題 `.js` 資產回 **422**：Rails cross-origin JavaScript 防護（`verify_same_origin_request`：GET、回應 media type 為 text/javascript、非 XHR ⇒ raise）——`ApplicationController` 的 `protect_from_forgery` 使 `Admin::StorefrontPreviewController#asset` 也受檢，iframe 的 `<script src>` 全中；dev log 逐字 "Security warning: an embedded <script> tag on another site requested protected JavaScript."（external-facts §G19）。公開店面的 `Storefront::AssetsController` 早已 `skip_forgery_protection`（S10），預覽端點漏了 | `skip_forgery_protection only: :asset`（只限資產；draft_page／draft_section 仍受 CSRF） | PV1／PV1b |
| 2 | 預覽 `<html lang="">`、`Shopify.locale = ""`、`Shopify.country = ""`；skip link `body>a` 寬 134 vs 219（平台字串英文回退） | 預覽 renderer 不帶 `locale`／`web_presence`（公開店面由 `locale_hit` 帶） | 預覽以店的預設 (market, locale) 渲染＝`Markets::PrefixIndex.default_hit`（primary market × 第一個 presence × 其預設語言；本尊編輯器市場選擇器預設 "Store default"，`docs/research/100` §中 2）；`show` 與 `draft_section` 同一真相 | PV2／PV2b／PV3、DH1–DH3 |
| 3 | 商品頁 `product_recommendations` 79 差異：卡片按鈕 74／99px vs 32／80px（英文 "Sold out"／"Add to cart" vs zh-CN） | 預覽內主題 JS 打的是 **無前綴** URL（Ella `data-url="/recommendations/products?limit=5"`、`Shopify.routes.root = "/"`）；無前綴的 SRA 端點 `locale_hit` 為 nil ⇒ 英文。本尊主市場預設語言**無前綴**，同一 URL 就是預設語言 | 無前綴的三支 SRA 端點（recommendations／search suggest／cart sections）退回 `default_hit`（`BaseController#effective_hit`）——與根路徑 302 的目標同一落點；帶前綴者仍只由前綴決定，不是 GeoIP／cookie 推市場 | SF-9b |

- 修法 2／3 的單一真相：`Markets::PrefixIndex.default_hit(shop:)`；`Storefront::PagesController#default_prefix`（根路徑 302）改用它，
  三個消費者（根路徑重導／編輯器預覽／無前綴 SRA）不再各抄一份。

| # | 現象（A′ 對表，E14 追加） | 根因 | 修法 | 規格 |
|---|---|---|---|---|
| 4 | cart_drawer 368 vs 130 元素：本尊多 238 個 `<option>`（Ella `snippets/cart-shipping-calculator.liquid` L28 `{{ all_country_option_tags }}`）；我方 select 空 | 我方全域 `all_country_option_tags` 做成「market ∩ 有費率 zone」的國碼 option——那是 `country_option_tags` 的語義（官方兩物件頁逐字見 external-facts §G20），格式也不是本尊形；店面對表看不到（非設計模式的 cart drawer 內容互動時才取） | 新 `ThemeEngine::CountryOptionTags`＋平台字典 `config/country_option_tags.json`（本尊 zh-CN 渲染輸出整理：237 國、1128 子區域；ISO 3166 對不上本尊集合）；`all`＝`---`＋全部（依該語言的本尊觀察序）、`only`＝運送區域內國家同形；cart `estimate_rates` 收國名或國碼。E14b：字典 v2 五語言（zh-CN／zh-TW／en／fr／ja）在地名與觀察序（external-facts §G21） | W4／W4b／W4c／R5 |

## §2 結果（本機 dev server，Chrome 152 headless，1280×900；首頁另 768×1024／390×844；全部 `--open-details 1`）

| 頁 | 寬 | ref | 段落全同 | 非全同段 |
|---|---|---|---|---|
| / | 1280 | 本機店面 | 15/21 | 五個 popup-group 段（§3）、`__root__`（§3） |
| / | 1280 | hoko.vip live | 15/21 | 同上 |
| / | 768／390 | 本機店面／hoko | 15/21 各 | 同上 |
| /collections/all | 1280 | 本機店面／hoko | 9/15 各 | 同上 |
| /collections/frontpage | 1280 | 本機店面／hoko | 9/15 各 | 同上 |
| /products/acme-tee | 1280 | 本機店面／hoko | 8/15 各 | 同上＋`main`（countdown 秒數文字寬，時間性，同 91 §3.79） |
| /pages/contact | 1280 | 本機店面／hoko | 10/16 各 | 同上 |
| /search | 1280 | 本機店面／hoko | 6/12 各 | 同上 |
| /cart | 1280 | 本機店面 | 8/15 | 同上＋`cart-section`（cart countdown 文字寬 47.5 vs 46.5，時間性） |
| /cart | 1280 | hoko.vip live | 9/15 | 同上 |
| /nope（404） | 1280 | 本機店面／hoko | 6/12 各 | 同上 |

| / | 1280／768／390 | **本尊編輯器設計模式渲染 A′**（E14） | 20/21 各 | `__root__`（我方橋 13 元素；本尊兩個 JS 建立的 video popup 抽屜；`#Drawer-Search` 內容 auto margin 報告值 920 vs 0 而幾何同）——五個 popup-group 段與 A′ **全同** |
| /products/acme-tee | 1280 | A′（E14） | 8/15 | recommendations／product_tabs／footer 為被擋執行期的 fetch 副作用（§4 量測限制）；`main`＝countdown＋本尊 payment button |

- 讀法：每頁「非全同段」恰＝五個 popup-group 段＋`__root__`（＋時間性 countdown）；**其餘所有段——模板段、header、footer、
  announcement bar——編輯器預覽與店面／本尊逐屬性全同**。修法前的首頁是 0/21（缺口 1）、修法 1 後 15/21 但 skip link 與語言錯（缺口 2）、
  商品頁 6/15（缺口 3）。
- 報告與擷取 JSON 在 scratchpad `computed/report-editor-vs-{storefront,hoko}-{page}-{width}.md`／`local-editor-*.json`；重跑法見 §5。
- 旁證：本尊 `?preview_theme_id=143506604135`（編輯器所編輯的副本主題）以 headless 擷取與 hoko.vip live 首頁比＝20/21，唯一差異
  `__root__` 的 `body>div:3`（0→68px、固定底部＝本尊預覽列）⇒ 副本主題渲染＝live（E1 的隱藏／還原無殘留）。

## §3 主題自己定義的設計模式差異（本尊編輯器同樣如此；不是引擎缺口）

1. **五個 popup-group 段的 wrapper**（before_you_leave／cart_drawer／toolbar_mobile／multitasking_bar／promotion_popup）：
   `position: fixed; inset: 0; z-index: 99; width: 0; min-width: 0; min-height: 0`（店面 static、z-index auto／19）。來源＝Ella `assets/base.css`
   L57–L64：`.shopify-design-mode .shopify-section-group-popup-group { position: fixed; }`＋`… { z-index: 99; }`（`inspect` 命中規則證實，
   external-facts §G19）；`html.shopify-design-mode` 由 Ella `layout/theme.liquid` L11 在 `request.design_mode` 時輸出——本尊編輯器與我方預覽
   同一 class ⇒ 同一形。連帶 `body` 的 `grid-template-rows` 少五列（fixed 元素不佔 grid）、`body>side-drawer:6` z-index 19→99。
2. **before_you_leave、cart_drawer 與 header_mobile 的內容在編輯器整段渲染**（before_you_leave 27→322 標籤、cart_drawer 149→293；
   header_mobile 的側抽屜選單 45 個元素在 `body>side-drawer>…>header-mobile-tabs` 下，落在 `__root__`）：Ella `sections/before-you-leave.liquid`
   L1–L6、`sections/cart-drawer.liquid`、`sections/header_mobile.liquid` L10–L12／L44–L49：`if section.index == nil ⇒ section_fetch = true ⇒
   內容以 {% content_for 'block' %} 直出`，否則留空由 `<section-fetcher data-activate="interaction">` 互動時再取。官方（2026-09-04 逐字）：`section.index` "returns nil … While rendering in
   the online store editor" ⇒ 本尊編輯器同樣 nil、同樣直出；我方 `Runtime#render_section` 的 `index: @design_mode ? nil : index` 即此
   （external-facts §G1／§G19）。
3. **`group-block-content--design-mode` class**（promotion_popup 等 group block）：Ella `snippets/group.liquid` L187／`group-hover.liquid` L92
   在 `request.design_mode` 加 class；`snippets/product-grid.liquid` L136 `{% unless request.design_mode %}` 才輸出一段 script；
   `featured-product`／`main-product`／`_group-announcement` 在設計模式多載 `theme-editor.js`。這些是標記面，computed 未見差異。
4. **`__root__`**（首頁 1280：多 58 個元素＋`body` grid 列數＋`side-drawer` z-index）：13 個＝我方編輯器橋在 `body` 末尾注入的覆疊層
   （`.cl-ov-box`／`.cl-ov-chip`／`.cl-ov-insert`×2／`.cl-ov-bar`＋3 鈕＋svg，全部 `display:none` 初始）；45 個＝第 2 項的 header_mobile
   側抽屜內容；`body>side-drawer:6` z-index 19→99 與 grid 列數＝第 1 項的連帶。本尊編輯器對預覽 iframe 注入什麼**未取得**（§4）。
   複驗：`grep -c "(missing) |"` 報告的 `__root__` 段＝58，其中含 `header-mobile-tabs` 者 45。
   E14（A′ 取得後）：本尊設計模式頁的 popup-group 五段、before_you_leave 直出、header_mobile 抽屜內容與我方**逐屬性全同**（三寬 20/21）；
   本尊編輯器對 iframe 的注入＝`storefront-modules`／`visual-preview-modules` 執行期（量測時擋掉，其覆疊層因此未量到，V），
   `__root__` 餘差見 §2 A′ 列與 91 §3.81。

## §4 本尊編輯器預覽的 computed 擷取（A′）——2026-09-04 取得（E14）；原「未取得」段落的更正

- 取得法：本尊編輯器＝admin 頁內的嵌入 app iframe `online-store-web.shopifyapps.com/themes/{id}/editor`，預覽 iframe 再巢狀於其中（跨域）；
  分頁層 network 工具、無障礙樹、`chrome://`、預覽內右鍵（編輯器自己的選單）都到不了它——**由使用者在編輯器分頁 DevTools › Network 篩 Doc 貼出**。
  預覽文件＝`https://pnrjnw-sy.myshopify.com/?oseid=<編輯器工作階段 id>`（不是 hoko.vip；`?preview_theme_id=…&_ab=0&_fd=0&_sc=1` 只是一般店面，
  無設計模式）；`&source=visualPreviewInitialLoad` 那份是零 section 的殼（編輯器再串流填入），不帶 source 的那份是完整設計模式渲染。
- 量法：headless 載入完整版時 Shopify 的 `storefront-modules` 執行期（`OnlineStoreEditorData`／`oseid` LocationBehavior，external-facts §G20）
  會把導航改寫到一般店面（live 主題 143469576295、無設計模式）⇒ 工具加 `--block "visual-preview-modules,storefront-modules"`
  （CDP `Network.setBlockedURLs`）後 `designMode true`、theme 143506604135、20 段、`data-shopify-editor-*`。live 店面本來不載這兩支，擋掉只移除
  編輯器管線；代價＝依賴其 XHR 攔截器補 `oseid` 的 fetch（recommendations／recently-viewed）會 abort ⇒ 商品頁 A′ 的該段是骨架（量測限制，V）。
- 結果：首頁三寬 A′ vs 我方編輯器預覽 20/21（§2）；A′ vs hoko live＝五個 popup-group 段＋`__root__` 差——證實 §3 的「主題自定義設計模式差異，
  本尊同形」。缺口 #4（§1）由此抓到並修。
- 憑證：`oseid`／app frame 的 `id_token`／`session` 是短效票證，只存 scratchpad、不入倉不進 PR；重跑要重新從 DevTools 取。

## §5 重跑

```
# 1) 本機 dev server：CHILLLOVE_BASE_HOST=lvh.me bundle exec rails server -p 3000 -b 127.0.0.1
# 2) staff cookie（本機 dev DB；不經登入表單）：COOKIE_OUT=<file> bundle exec rails runner <issue_local_session.rb>
# 3) 擷取與 diff
node scripts/computed-parity.mjs capture "http://mirror.lvh.me:3000/admin/store/preview/2/?editor=1" e.json --wait 3000 --open-details 1 --cookie "$(cat <file>)"
node scripts/computed-parity.mjs capture "http://mirror.lvh.me:3000/zh-hans-tw/" s.json --wait 3000 --open-details 1
node scripts/computed-parity.mjs diff s.json e.json --out report.md
node scripts/computed-parity.mjs inspect "http://mirror.lvh.me:3000/admin/store/preview/2/?editor=1" '[id$="__cart_drawer_PFLQy3"]' --props position,z-index --cookie "$(cat <file>)"
# 4) A′（E14）：oseid 由使用者從編輯器 DevTools 取；擋掉本尊編輯器執行期
node scripts/computed-parity.mjs capture "https://pnrjnw-sy.myshopify.com/?oseid=<id>" a.json --wait 3000 --open-details 1 --block "visual-preview-modules,storefront-modules"
node scripts/computed-parity.mjs diff a.json e.json --out report.md
```

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）

- `Storefront::PagesController#default_prefix`、`RecommendationsController#url_prefix`、`SearchController#url_prefix` 改讀 `Markets::PrefixIndex.default_hit`
  （行為不變：同一條規則，單一真相）。
- 無前綴的 `/recommendations/products`、`/search/suggest`、`/cart/add`（含 `sections`）現以店預設語言渲染（先前英文）；帶前綴者不變。
  買家前台頁面自身恆帶前綴（D80 未裁），故只影響直接打無前綴端點的呼叫者（編輯器預覽、外部腳本）。
  <!-- 2026-09-04 D80 方案 1 更正：買家前台的預設語言頁自此**無前綴**（根路徑直接服務），無前綴端點的語言真相與買家前台同一落點；預覽仍 `url_prefix ""`。 -->
- 編輯器預覽：主題 JS 現在真的會跑（資產 200）——依賴 `Shopify.designMode` 的主題行為（Ella before-you-leave／cart-drawer 的
  `shopify:section:select` 開啟、promotion popup 選中即彈）自本包起在預覽內生效；預覽語言＝店預設語言（`Shopify.locale`／`country`、`<html lang>`）。
- `docs/dev/e6-theme-editor-preview.md` §E13 同步；`docs/dev/e12-computed-parity.md` §0 加 `--cookie`。
