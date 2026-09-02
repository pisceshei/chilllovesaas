# Handoff：主題無關 conformance（Minimog 6.0.0／Kalles 5.4.2 入倉）＋真店切換實測（2026-09-02）

> 工作包＝分支 `theme/minimog-fixture`（基於 main `3bfaeaf2`）。本檔依鐵律 21 四段。
> 🔴 中斷原因：使用者裁定「fable 5.1 額度消耗太多，先做好 handoff」——本工作包**沒有做完**，
> 斷點與續做入口全部寫在 §③／§④。取代舊檔 `2026-09-02-minimog入倉與conformance首跑.md`
>（5.9.0 已依裁定刪除，該檔未入庫即作廢）。

## ① 我改了什麼

### 1. 裁定與 fixture（D78 改寫，`docs/DECISIONS.md`）
- 使用者三段裁定（原話見 D78）：①最終目標＝import 任何買斷主題即可用（平台契約全覆蓋）；
  ②「你把剛才給你的刪掉，重新研究這個（Minimog 6.0.0）。還有新的 theme Kalles」；
  ③「兩個主題都安裝在 shopify 的，如果需要真店實際跑。你自己 Publish，自己實測抓取」
  ⇒ 真店 pnrjnw-sy 的 **Publish 已獲授權**，其他寫入仍未授權。
- fixture 現況（`test/fixtures/themes/`，全部未 commit、已 `git add` 待提交）：

| 目錄 | 檔數 | 來源 |
| --- | --- | --- |
| `minimog-6.0.0/` | 468 | `minimog-6.0.0.zip`（FoxEcom，theme_version 6.0.0） |
| `minimog-6.0.0-sample-data/` | 681 | 隨 6.0.0 包附帶的 `sample data.zip`，與 5.9.0 那份 md5 相同（`59efc2cf…`） |
| `kalles-5.4.2/` | 642 | `Kalles_v5.4.2.official.zip`（The4，有 `blocks/` 200+ theme blocks） |
| `kalles-5.4.2-template-demo/` | 136 | `Template Demo v5`（模板 JSON 平鋪） |
| `kalles-5.4.2-demo-data/` | 323 | `Demo Data v5` 各 demo 的 config／sections／templates（圖片未入倉） |

  5.9.0 → 6.0.0 檔案級差異：129 檔內容不同、6 檔新增（`assets/contact-bar.css`、
  `assets/store-locator.css`、`sections/contact-bar.liquid`、`sections/store-locator.liquid`、
  `snippets/account-component.liquid`、`snippets/icon-box.liquid`），無刪除。
  `minimog-5.9.0/` 與其 sample-data 目錄已刪（未曾入 main）。

### 2. 引擎 conformance harness 與 spec
- `spec/support/theme_conformance.rb`：新增 `article.*`／`blog.*`／`search.*` 視圖對映
  （Kalles 有這三類替代模板）。
- `spec/liquid/theme_conformance_spec.rb`（取代 `theme_conformance_minimog_spec.rb`）：
  TC-M1（Minimog 6.0.0，≥41 頁）＋ TC-K1（Kalles 5.4.2，≥60 頁）；判準＝每頁 200／404
  正確、零 Liquid error、零例外。**實跑 2 examples, 0 failures（20.23s）**。
- 通用 runner 與分析工具（本輪由 tmp／scratchpad 搬進 `tools/theme-conformance/`，見該目錄 README）：
  `run.rb`（任意主題＋preset 覆蓋層 → JSON 報告，含逐頁 count_miss delta）、
  `engine_surface.rb`（引擎已註冊 tags／filters／globals／Drop 方法 → JSON）、
  `static_scan.py`（主題靜態掃描：未支援 filter／tag、Drop 屬性缺口候選）、
  `settings_preclassify.py`（settings 類 miss key 對 schema 的機械分類）、
  `schema_parse_probe.rb`（三套主題全部 schema 用引擎 `tolerant_json` 解析）、
  `golden_capture.sh`（真店 hoko.vip 全頁 curl 抓取）。

### 3. 首跑結果（全部 0 Liquid error／0 例外）

| 主題／preset | 頁數 | count_miss 鍵 |
| --- | --- | --- |
| Minimog 6.0.0 基底 | 41 | 77 |
| Minimog 6.0.0 ＋ BFCM／Barber／Bedding | 41 各 | 90／86／82 |
| Kalles 5.4.2 基底 | 60 | 215 |
| Kalles ＋ Template Demo v5 | 138 | 300 |
| Kalles ＋ Home Fashion 01／Cosmetic／Digital／Barber | 60 各 | 218／210／214／209 |

  preset 相對基底新增的非 settings 鍵只有：Minimog `pages.product-compare`、`font_library.helvetica`、
  `blogs.`、`linklists.faqs-menu`；Kalles `linklists.`、`ShopDrop.metaobjects`、`images.`。
  引擎面：tags 30／標準 filters 61／引擎 filters 74／globals 29／Drop 類 52
  （`tools/theme-conformance/evidence/engine_surface.json`）。
  schema 解析：三套主題 711 個 section／block schema 用引擎 `tolerant_json` **0 失敗**
  （Kalles 有 194 檔帶尾逗號＝非嚴格 JSON，這是 Shopify 接受的形態；Python 嚴格 `json.loads`
  會全部炸，見 §④ 坑 6）。

### 4. 研究（三個 Workflow ＋ 機械分類）——結果都在倉庫 `tools/theme-conformance/research/`
- **契約矩陣**（`liquid-platform-contract-matrix`，run `wf_dbf03b00-620`）：466 列
  ＝ implemented 141／partial 161／missing 119／stub 33／stubbed 1／not-applicable 11；
  295 個 agent 完成 123、其餘撞額度上限；**synthesis 為 null**。列表含官方逐字引句、我方
  file:line 與 fix 草案。missing 的 object 大宗＝B2B（company*）、selling_plan*、metaobject*、
  order／transaction／fulfillment、gift_card／recipient、robots／sitemap、user／user_agent、
  video／video_source、model／model_source、brand*、store_availability／location 等。
- **hoko.vip 對位稽核**（`hoko-parity-audit`，run `wf_d508d98a-372`）：72 條候選 finding，
  **0 條經過對抗驗證**（224 agent 只完成 4）。候選清單以「rejected」欄名存放，那是 pipeline
  對未驗證項的預設值，不代表被駁回。要點：theme block 預設 `<div id="shopify-block-…">` 未輸出；
  `{% render var, k: v %}` parse 致命；`section.index` 恆 nil（Ella `section_fetch` 門反轉）；
  `shop.customer_accounts_enabled` 寫死 false；`rgba()`／`#RRGGBBAA` 色值不解析；
  section wrapper 無實例前綴 id／無 `shopify-section-group-*` class／無 BEGIN/END 註解；
  `{% form %}` 丟變數 `id:`；`shop.url` 用合成 host；`asset_url` 無 `?v=`；`{% style %}` 少
  `data-shopify`；`json` filter 不跳脫 `/`；`placeholder_svg_tag` 形態；缺群組時把引擎註解漏進
  HTML；`page_title` 在 collection／cart 頁用店名；`routes.root_url` 帶 locale 時無尾斜線；
  section 本地 blocks（無 `blocks/*.liquid`）被靜默丟棄；空字串 `color_scheme` 不退回 schema
  預設；`form.posted_successfully?` 寫死 true；themes 管理頁 UI 差異十餘條。
- **6.0.0＋Kalles 缺口 triage**（`theme-gap-triage-m6-kalles`，run `wf_10441674-058`）：70 鍵
  ＝ engine-gap 31（**18 條通過對抗驗證**、13 條未驗證）、theme-quirk 17、data-absent 11、
  already-implemented 3、settings-default 8。
  已驗證 18：`FormDrop.email／body／password_needed／first_name／last_name`、
  `CollectionDrop.all_tags／featured_image／metafields`、`BlogDrop.next_article／previous_article`、
  `PageDrop.metafields`、`ProductDrop.created_at`、`PlaceholderImageDrop.presentation`、
  `ShopDrop.features`、filters `link_to_add_tag／link_to_remove_tag／url_for_type／sort_by`。
  未驗證 13：filters `default_pagination／color_to_hsl／md5／format_code`、
  `link.handle／current／levels／object／child_current`（LinkDrop 無 `liquid_method_missing`）、
  `font_library.libre_baskerville`、theme-block 三項（`block-wrapper-id-class`、
  `disabled-blocks-skipped`、`content_for-blocks-closest-param`）。
  已確認**不是**缺口：巢狀 theme blocks、`content_for "block"` 靜態區塊、`{% doc %}`＋靜態區塊參數
  （already-implemented）；`FormDrop.templates.contact.form.*`／`FormDrop.` 空鍵／`pages.` 空 handle
  等為主題本身的動態鍵（theme-quirk）。
- **前一輪 Minimog 5.9.0 triage**（run `wf_9c61a6d9-6df`，已完成）12 條確認：
  `CollectionDrop.sort_options／current_vendor／current_type`、`ShopDrop.money_with_currency_format／
  description`、`font_library.roboto_condensed`（＋family 名推導 bug）、color_scheme 無預設應退回
  第一組（settings＋section 各層）、checkbox 無預設應為 false。
- **settings 類鍵機械分類**（`settings_preclassify.py`）：Minimog 27 settings-default／10 ENGINE-GAP?
  （9 color_scheme＋1 checkbox，與上列裁定同型）／16 theme-quirk；Kalles 81／10（7 checkbox、
  2 color_scheme）／88 theme-quirk＋2 條 `select` 無預設待查官方語義
  （`section(recently-products).sort_by`、`.availability`）。

### 5. 真店（pnrjnw-sy ＝ hoko.vip）
- 主題庫實測（截圖）：`kalles-v5-4-2-official`（Added 1:45 pm）、`minimog-6-0-0`（Added 1:27 pm）、
  `Horizon`（9:39 am），現行發布＝`ella-7-2-0-theme-source`（id 143469576295）。
  兩套新主題的 **theme id 未取得**（列表在跨域 iframe 內，連結 href 讀不到）。
- 已抓 Ella 基線：`tools/theme-conformance/golden/ella-7.2.0-baseline/`（index 1,013,293 bytes、
  20 個 section；`/products.json` 回 `{"products":[]}`＝**店內零商品**；`/collections.json` 134 bytes）。
- **Publish 尚未成功**（斷點，見 §③）。

## ② 為什麼這樣改

- 驗收單位改成「平台契約條目」而非「某主題用到什麼」（D78）；每套主題只是探針。Kalles 之所以
  重要，是因為它是 theme-blocks 架構（`blocks/`＋`@theme`／`@app`＋巢狀），Ella／Minimog 踩不到。
- conformance 第一階只擋「炸頁」（Liquid error／例外／狀態碼），count_miss 只登記——因為 miss
  鍵七成以上是主題讀了自己沒宣告的 setting（theme-quirk）或資料未種（data-absent），直接擋會
  把假警報變成閘門。
- 真店金標本的價值＝**同一套主題原始碼**在本尊引擎的輸出（hoko.vip 對 Ella 已證明可逐頁 diff）；
  這也是使用者授權 Publish 的原因。Preview（`?preview_theme_id=`）本可免發布，但仍需 theme id，
  而 id 只能從 iframe 內的連結或發布後的 `Shopify.theme` 取得。
- 被推翻的假設：①「Kalles 141 個 setting 不在 schema」——是我的 Python 嚴格 JSON 解析炸掉，
  引擎沒事；②「claude-in-chrome 點座標可靠」——在跨域 iframe 上不可靠（§④ 坑 1）；
  ③「sample data 是 5.9.0 專屬」——6.0.0 包附同一份，故保留並改名。

## ③ 還有什麼沒解決（斷點在這裡）

1. 🔴 **本分支尚未 commit／push**（截至本檔寫成時）。§④ 第 1 步就是提交。
2. 🔴 **真店 Publish 未完成**：兩次座標點擊都沒打到 Publish（一次誤開了 Ella 編輯器），
   後改用 JS 操作頂層文件的捲動容器（可行，見 §④ 步驟 A），捲到 `scrollTop=1050` 後截圖時
   Chrome renderer 卡死（`Page.captureScreenshot` 30s 逾時）。**沒有任何主題被發布、沒有任何
   設定被改**；頂層頁面的 iframe 高度被我用 JS 臨時改成 3200px（重新整理即消失）。
3. **Minimog／Kalles 在本尊的金標本一頁都還沒抓**；且 hoko.vip 零商品 ⇒ 即使發布，商品頁／
   系列頁在真店也抓不到可比內容（需使用者裁定：在 pnrjnw-sy 建幾個商品／匯入 sample data，
   或改用測試店 chill-love-u5q5mnzq 另裝主題——後者需使用者上傳主題 zip）。
4. 三個 Workflow 都因額度中斷：契約矩陣缺 172 個 verify＋synthesis；hoko 稽核缺 220 個
   verify＋synthesis（72 條候選全未驗證）；triage 缺 13 個 verify＋synthesis。
   續跑指令在 §④ 步驟 D。
5. 未實作的引擎缺口（上面 §①4 全部）一條都還沒修；PR 包順序建議在 §④ 步驟 E。
6. `settings_preclassify.py` 對 `kalles-5.4.2/sections/header-inline-blocks.liquid` 的 schema
   仍解析失敗（引擎 tolerant_json 能解）——分類器要補同款寬容規則或改呼叫引擎。
7. 未取得：Kalles／Minimog 在 pnrjnw-sy 的 theme id；Shopify 對 `select`／`radio` 無 default 時
   的官方語義（settings_preclassify 標 VERIFY-OFFICIAL 的 2 鍵）。

## ④ 下一個人要注意什麼

### 步驟 0：環境
- 真倉庫＝`C:\Users\pisce\Documents\ChatGPT\CHILL LOVE SYSTEM\worktrees\p2-claim-index-r6`
  （cwd 是舊資料夾，每個命令先 cd）。分支 `theme/minimog-fixture`。`gh` 2.97 可用。
- Rails 腳本：`RAILS_ENV=test bundle exec rails runner <script>`；Python 用 `python`＋
  `PYTHONIOENCODING=utf-8`。

### 步驟 1：提交本工作包
```bash
cd "/c/Users/pisce/Documents/ChatGPT/CHILL LOVE SYSTEM/worktrees/p2-claim-index-r6" && git status --short | head
```
若還沒 commit：`git add -A && git commit`（訊息：Minimog 6.0.0＋Kalles 5.4.2 入倉、conformance
harness／TC-M1／TC-K1、D78、tools/theme-conformance）→ push → `gh pr create` → CI `quality`＋`test`
綠 → `gh pr merge --squash --match-head-commit <sha>` → 部署 bt3（`ssh bt3-wan "cd /www/wwwroot/chilllove/app && bash scripts/deploy.sh origin/main"`）。
合併前 `git fetch origin main`（記憶 fetch-before-branch）。

### 步驟 A：真店 Publish（唯一可靠路徑＝JS 捲頂層容器＋座標點擊＋截圖驗證）
1. 用使用者的 Chrome（claude-in-chrome）**前景分頁**開 `https://admin.shopify.com/store/pnrjnw-sy/themes`，
   等 ≥15s（載入紀律：空白＝未載完，不是沒內容）。
2. `javascript_tool`（只能回傳數字／純文字，含 query string 的字串會被工具擋掉）：
   `const s=document.querySelector('.Polaris-Scroll'); s.scrollTop=1000; s.scrollTop`
   —— iframe 在頂層的 `.Polaris-Scroll` 容器裡；主題庫列在 scrollTop≈900–1300 之間
   （1300 已看到 Discover themes 網格，所以往回一點）。
3. 截圖確認 `minimog-6-0-0` 列可見，**同一輪**內立刻用截圖座標點該列的 `Publish`，再截圖：
   應出現確認 modal（「Publish minimog-6-0-0?」）→ 點 modal 的 Publish → 截圖確認列變成
   current theme。若截圖與點擊之間頁面重載（resize／導航都會讓 iframe 重載並捲回頂端），
   座標會打到別的按鈕（本輪誤開 Ella 編輯器的原因）。
4. `bash tools/theme-conformance/golden_capture.sh minimog-6.0.0`（curl hoko.vip 全頁，輸出到
   `tools/theme-conformance/golden/minimog-6.0.0/`，並印出 `Shopify.theme` ⇒ 得到 theme id）。
5. 對 `kalles-v5-4-2-official` 重複 3–4，標籤 `kalles-5.4.2`。
6. **結束時把 `ella-7-2-0-theme-source` 重新 Publish 回去**（回復原狀）。
7. 有 theme id 之後，之後的抓取可改用 `https://hoko.vip/?preview_theme_id=<id>` 免發布。

### 步驟 B：金標本 vs 我方輸出的逐頁 diff
- 我方：`RAILS_ENV=test bundle exec rails runner tools/theme-conformance/run.rb test/fixtures/themes/minimog-6.0.0 Minimog 6.0.0 -`
  只給狀態與 miss；要 HTML 用 `ThemeEngine::PageRenderer`（範例在 run.rb 內）。
- 對位方法沿用 hoko 稽核：先比 `<head>`、section 包裝（id／class／BEGIN-END 註解）、
  `window.Shopify` 形狀，再比 section 內容；商品頁在真店零商品下不可比（§③3）。

### 步驟 C：settings 分類器
- `python tools/theme-conformance/settings_preclassify.py test/fixtures/themes`（讀 tmp 的
  conformance JSON；先跑 run.rb 產生）。theme-quirk 判定前務必看「schema parse errors」行。

### 步驟 D：續跑三個 Workflow（Ultracode 已關；需使用者再開或明說「run a workflow」）
- 契約矩陣：`Workflow({scriptPath: "C:\Users\pisce\.claude\projects\C--Users-pisce-Downloads-shopifysystem\d5af83e2-8736-4797-b1ab-84bec82b9230\workflows\scripts\liquid-platform-contract-matrix-wf_dbf03b00-620.js", resumeFromRunId: "wf_dbf03b00-620"})`
- hoko 稽核：同目錄 `hoko-parity-audit-wf_d508d98a-372.js`，resume `wf_d508d98a-372`
- triage：同目錄 `theme-gap-triage-m6-kalles-wf_10441674-058.js`，resume `wf_10441674-058`
- 已完成的 agent 走快取不重跑；**每次 resume 都可能再撞額度**（本輪三次撞上），先估 agent 數。
  若不想再燒額度：矩陣 466 列與 triage 70 列已足夠排 PR，只有 hoko 的 72 條需要人工挑驗。

### 步驟 E：引擎缺口 PR 包建議順序（每包附官方引句＋red-proof 突變＋真主題 spec）
1. **FormDrop 型別化**（依 `{% form %}` type 宣告屬性；`password_needed`＝true；
   email／body／first_name／last_name）——Kalles／Ella 登入表單現在**不渲染密碼欄**，最高影響。
2. **theme block 包裝與 disabled**（hoko 高分項＋triage 未驗證三項）：預設 `<div id="shopify-block-{id}" class="shopify-block …">`、`tag: null` 才不包、block `disabled: true` 跳過、
   section 本地 blocks 不得丟、`{% render var, k: v %}` 支援。
3. **settings 預設語義**：checkbox 無 default ⇒ false；color_scheme 無 default／空字串 ⇒ 第一組；
   select／radio 無 default 先查官方（未取得）。
4. **Collection／Search／Blog／Page／Product drops**：`sort_options`、`current_vendor／current_type`
   ＋ `/collections/vendors|types` 路由、`all_tags`、`featured_image`、`metafields`（collection／page）、
   `next_article／previous_article`、`created_at`。
5. **Shop／字型**：`money_with_currency_format`、`description`（需 shops 欄位）、`features`；
   font_library 補 Roboto Condensed／Libre Baskerville／Helvetica＋family 名推導。
6. **filters**：`link_to_add_tag／link_to_remove_tag／url_for_type／sort_by`（已驗證）、
   `default_pagination／color_to_hsl／md5`（待驗證；`format_code` 疑非官方 filter，先查）。
7. 之後才是矩陣的 119 個 missing object（B2B／selling plan／metaobject／order 等大件）。

### 坑（本輪實證，不要再踩）
1. **claude-in-chrome 對 Shopify admin**：themes 頁與編輯器本體都在 `online-store-web.shopifyapps.com`
   跨域 iframe（直接開該 URL 回 `HMAC validation failed`）；`find`／`read_page` 看不到 iframe 內容；
   `scroll` 滾輪對 iframe 幾乎無效；`resize_window` 回報成功但 viewport 仍 1573×485；
   `ctrl+minus` 縮放不支援；`wait` 上限 10s；背景分頁渲染懶惰、截圖會是舊畫面；
   **javascript_tool 回傳值含 query string／cookie 會整段被擋**（只回數字或切掉 `?` 後的字串）。
   可行組合＝前景分頁＋JS 捲 `.Polaris-Scroll`＋截圖後同輪點擊。
2. **Bash 工具的 heredoc 會吃掉反斜線**：`\\1`、`\s` 這類內容寫進檔案後變形（本輪把 `r"\1"`
   寫成 `r""`，把整個分類器的結論翻成 141 個假 theme-quirk）。含反斜線的腳本一律用 Write／Edit 工具。
3. **Python `json.loads` 對主題 schema 不可用**：Kalles 194 檔尾逗號；要先剝 `/* */` 與
   `,(\s*[}\]])`，或直接呼叫引擎 `ThemeEngine::Runtime.tolerant_json`。
4. **conformance 的「miss」不是缺口**：先過 `settings_preclassify.py`＋data-absent 判斷，再進
   官方契約比對；已分類清單在 §①4，不要重新 triage。
5. **真店零商品**：hoko.vip 商品／系列頁沒有可比內容；別把空頁 diff 當成引擎缺口。
6. **Workflow 的 `rejected` 欄**在 hoko 稽核裡＝「未驗證」，不是「被駁回」（verify 沒跑就落進去）。
7. 三套主題 fixture 只供測試、不隨產品出貨（D78／鐵律 9）；`kalles-5.4.2-demo-data` 已刻意排除圖片。
8. 測試 DB 若有殘留 shop（runner 中途失敗會留下 `tc-xxxxxx`／`mc-xxxxxx` subdomain 的 shop），
   concurrency spec 的 `Shop.delete_all` 會撞 FK——先清：`Shop.where("subdomain LIKE 'tc-%' OR subdomain LIKE 'mc-%'").destroy_all`（with `ActsAsTenant.without_tenant`）。
9. **主題 zip 內可能夾帶廠商金鑰**：Kalles 的 `templates/page.store-locator.json`（主題本體與
   Template Demo v5 各一份）`access_token` 帶廠商的 Mapbox token（`pk.eyJ…`，GitHub 判為
   「Mapbox Secret Access Token」），push protection 直接拒收（GH013）。本輪已把兩處改成
   `REDACTED-MAPBOX-TOKEN` 後才推得上去；新主題入倉前先跑
   `grep -rE "sk[.]eyJ|pk[.]eyJ|AIza[0-9A-Za-z_-]{35}|shpat_|sk_live_"`，不要點 GitHub 的
   「allow the secret」。Kalles 另含 8 處 Google Maps 瀏覽器金鑰（`AIza…`），push protection
   未攔，照原樣保留。這也代表 Kalles store-locator 頁在我方渲染時 Mapbox 呼叫必然失敗
   （設定值是假的），該頁的 JS 錯不是引擎缺口。

### 證據索引
- 研究輸出（倉庫內複本）：`tools/theme-conformance/research/{contract-matrix,hoko-parity-audit,gap-triage-m6-kalles,gap-triage-m59}.json`
  （原檔＝`%LOCALAPPDATA%\Temp\claude\C--Users-pisce-Downloads-shopifysystem\d5af83e2-8736-4797-b1ab-84bec82b9230\tasks\{w4nw7ecxi,w7my60gvo,wauyobcoy,wlarspz03}.output`；
  逐 agent journal 在 `~/.claude/projects/C--Users-pisce-Downloads-shopifysystem/d5af83e2-…/subagents/workflows/<run id>/journal.jsonl`）。
- conformance／分類 JSON：`tools/theme-conformance/evidence/`（`conformance-*.json`、`preclassify-*.json`、`engine_surface.json`、`theme_static_scan.json`）。
- 真店截圖只在對話中；主題庫三列的文字已抄錄於 §①5。
