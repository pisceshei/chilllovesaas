# E8 渲染 1:1 對表（買家前台／live preview vs Shopify 本尊）

> 使用者裁定（2026-09-03）：「你做的都必須要和右邊的 live preview 和買家前台要和 shopify 本尊完全一樣。包括他的 css 和尺寸以及全部的參數」。
> 本包＝把這句話變成可重跑的機器判準：**同一套主題（Ella 7.2.0）＋同一份店資料**，本尊店（hoko.vip，Shopify 真店 pnrjnw-sy）
> 與我方鏡像店逐段比 HTML，差異只允許三類——①平台身分（主機、CDN 路徑、數字 id）②已登記的裁定差異③尚未修的引擎缺口。
> 本檔登記工具、已修缺口、已登記差異與待裁定事項；證據一律附 hoko.vip 2026-09-03 原始位元組或官方逐字。

## §0 範圍與非範圍

- 🔴 本檔的要求自 2026-09-04 起為**鐵律 22**（`CLAUDE.md`；`docs/DECISIONS.md` D82）：預覽與前台渲染必須與本尊完全一樣
  （含尺寸與全部參數），驗收＝逐段 diff 與 computed 量測到零，差異只能修到一致或登記平台差異。
- 範圍：HTML 位元組層（含 CSS 變數、class、屬性、空白形）。首頁（`/`）為第一批；其餘頁（商品／集合／購物車／搜尋／404／頁面／部落格）快照已存，逐頁跑法同 §1。
- 非範圍（另包）：computed CSS 逐元素量測（需瀏覽器同寬並排）、平台注入腳本（Shopify perf-kit／trekkie／shop-js／preloads 屬本尊平台，非主題渲染）、本尊插圖版權圖本體（鐵律 9，我方自繪、只對外框屬性）。

## §1 工具

| 件 | 位置 | 做什麼 |
|---|---|---|
| 正規化 | `app/services/render_parity/normalizer.rb` | 抹掉**只可能是身分**的差異：主機（含埠）、CDN 主題資產路徑與 `?v=`、字型雜湊、`sections--{數字}__`／`template--{數字}__` ⇒ `G`／`T`、block 實例前綴 `A{17}__` ⇒ `B__`、CSRF／reqid、placeholder 插圖本體 ⇒ `[placeholder]`、`Shopify.shop`／theme id／cdnHost；另可抹我方路由前綴（`url_prefix:`，§3 裁定差異）。切段：`shopify-section-*` wrapper 為界，另補 `__head__` 段。 |
| 報告 | `app/services/render_parity/report.rb` | 逐段 token 多重集合 Jaccard 相似度＋首個差異片段（左 40／右 120 字）＋尾端片段＋head 資產集合差，輸出 Markdown。**不做任何「可接受」判斷**。 |
| rake | `lib/tasks/render_parity.rake` | `bin/rails "render_parity:diff[REF,CAND,OUT]"`（URL 或本地檔；`REF_HOST`／`CAND_HOST`／`CAND_PREFIX`，前綴可不帶斜線——Git Bash 會把 `/xxx` 轉成 Windows 路徑）；`render_parity:mirror[SUBDOMAIN,SPEC]` 建鏡像店。 |
| 鏡像店 | `app/services/render_parity/mirror.rb`＋`spec/fixtures/render_parity/hoko.json` | 冪等對齊店名／幣別／來源語言（zh-Hans⇔本尊 zh-CN）／主市場國別（TW）／登入連結旗標／含稅旗標／3 商品／集合 frontpage／聯絡頁／主選單（首頁·目錄·聯絡我們）／主題（名稱鍵 `ella-7.2.0`：`themes/` 第一方目錄（bt3 demo 即此形）或非 production 的 `test/fixtures/themes/`；匯入主題改給 `THEME_CHECKSUM`）。 |
| 規格 | `spec/services/render_parity/render_parity_spec.rb`（RP1–RP6）、`spec/liquid/render_parity_forms_spec.rb`（RF1–RF21） | 工具本身與每個引擎形差各一格；突變輪 `mutate_e8.py`（M55–M90）。 |

跑法（本機）：

```bash
bin/rails "render_parity:mirror[mirror]"
CHILLLOVE_BASE_HOST=localhost bin/rails server -p 3000 -b 127.0.0.1
curl -s -o /tmp/mirror-home.html --resolve mirror.localhost:3000:127.0.0.1 -L http://mirror.localhost:3000/
REF_HOST=hoko.vip CAND_HOST=mirror.localhost CAND_PREFIX=zh-hans-tw bin/rails "render_parity:diff[/tmp/hoko-home.html,/tmp/mirror-home.html,tmp/render-parity.md]"
```

🔴 dev 模式改 `drops.rb`／`numeric_lookup.rb`／`nil_empty.rb` 後**必須重啟伺服器**（`config/initializers/theme_engine.rb` 把 drops.rb 排除於 autoload；重載後 `ThemeEngine::Runtime::ClosestDrop` NameError 即此症狀）。

## §2 已修引擎形差（首頁首批；每格對應 RF 規格與突變）

| # | 形差 | 本尊證據（hoko.vip 2026-09-03 原始位元組／官方逐字） | 修法 | 規格 |
|---|---|---|---|---|
| 1 | Liquid 空白控制保留首位元組 | 首頁 14,762 個孤立 `\r`；`column;\r--gap:`＝gap-style `{% enddoc %}\r\n\r\n{%- liquid` 的首位元組（liquid 5.13.0 `whitespace_handler` bug-compat 分支） | `Runtime::PARSE_OPTIONS` 加 `bug_compatible_whitespace_trimming: true` | RF1 |
| 2 | `{% style %}` | 官方："Generates an HTML `<style>` tag with an attribute of `data-shopify`." | `StyleTag` 輸出 `<style data-shopify>` | RF2 |
| 3 | `section.index`／`index0`／`location` | 官方："The 1-based index of the current section within its location."／nil in static sections, online store editor, Section Rendering API；slideshow `data-index="1"`、before-you-leave `data-section-fetch="false"` | template／group 迴圈給 1-based（只數實際渲染者）、location＝template／群組 type／static；SRA 與設計模式 nil | RF3／RF6 |
| 4 | 缺群組檔輸出；群組 BEGIN／END 換行 | `sections 'toolbar-mobile'` 無檔 ⇒ 零輸出；`<!-- BEGIN sections: x -->\n…\n<!-- END sections: x -->`，wrapper 之間無分隔 | `render_section_group` | RF4 |
| 5 | `inline_asset_content` 照檔輸出 | `</svg>\r\n</span>`（account-drawer `{{- … -}}` 兩側有 `-`，`\r\n` 只能來自資產檔尾）；同日曾誤判為修尾——toolbar 的 `</svg>\r</span>` 來自 `block.settings.icon` 字串 | 撤回 rstrip | RF1 |
| 6 | `shop.customer_accounts_enabled` | 官方："Returns true if the store shows a login link."；本尊新店渲染 Drawer-Account | `shops.customer_accounts_enabled`（預設 true） | RF7 |
| 7 | 語言碼 zh-Hans⇔zh-CN | `<html lang="zh-CN">`、`Shopify.locale = "zh-CN"`、Ella `locales/zh-CN.json`；官方 locale 檔命名規則逐字（language-region） | `ThemeEngine::LocaleTags`：輸出碼與主題檔候選用本尊碼，內部 tag 不變；語言切換表單反查 | RF8 |
| 8 | `{% schema %}` 前後空白 | color-swatches `{%- endstyle -%}\r\n\r\n{% schema %}…{% endschema %}\r\n` ⇒ `</style>\r\n</div>` | 載入期只抽 JSON、tag 留位（`SCHEMA_RE` 三組） | RF9 |
| 9 | form tag 隱藏欄位 | customer／product／contact／customer_login 四形：`<form …><input …form_type… /><input …utf8… />`緊接、無分隔 | `FormTag` | RF10；F3／F8 更正（09-02 的「各一行」來自 DevTools 排版） |
| 10 | block 實例 id | `group-block--AWlFwNUZ5UVVuRmp6e__group_announcement_bar_PeTpTw`…首頁 105 個相異前綴、同 block 各處一致、同 key 跨 section 不同；重複渲染尾綴 `-1`／`-2`（`card_product_information_4wqAip`／`-1`／`-2` 共前綴） | `BlockIds`（`A`＋SHA-256 base64 17 碼，seed＝section id＋block 路徑；**值為 ours**）＋每 section 內重複渲染計數尾綴；`data-shopify-editor-block` 仍裸 key | RF11／RF20 |
| 11 | color 設定與字串相等 | Ella color-swatches `color_2 == 'rgba(0,0,0,0)'` 在本尊為真 ⇒ `background: #1199bb` | `ColorDrop#==`／`to_str` | RF12 |
| 12 | placeholder 外框逐名 | hero-apparel-1＝`xMaxYMid slice` 1300×730、-2＝`xMidYMin slice` 1300×731、-3＝`xMaxYMid slice` 1297×729（無 class 參數 ⇒ 無 class 屬性，官方範例同）、product-apparel-1＝448×448、-2／-3＝449×448 | `PlaceholderSvg::FRAMES`；插圖自繪 scale 貼合 | RF13；PS1 更正 |
| 13 | Liquid 錯誤訊息路徑名 | `Liquid error (snippets/section line 43): divided by 0` | partial 命名 `snippets/{name}`（`registers[:template_factory]`）；section／block／layout 依同規則 `sections/x`…（本尊未實測，V） | RF14 |
| 14 | `window.Shopify` bootstrap 頭段 | `var Shopify = Shopify \|\| {};` → shop → locale → currency（JSON）→ country → theme（name／id／schema_name／schema_version／theme_store_id／role）→ theme.handle="null" → theme.style → cdnHost → routes.root | `ShopifyGlobal.script`（shop＝我方子網域、cdnHost 路徑＝ours） | RF15；SG1 更正 |
| 15 | 字串取屬性 | 無集合的 product-grid 靜態卡 `card_product = block.settings.product`（動態來源解成非商品 ⇒ blank 空字串）：`card--media`、`"id": ,`、`media | json` ⇒ `""`；同卡子 block 以整數 `closest.product` 取 `featured_media` 走**佔位**分支 ⇒ 整數仍 nil | `NumericLookup`（String ⇒ ""；Numeric／nil 不變；同日曾誤納整數，報告抓回） | RF16 |
| 16 | `nil == empty` | lookbook 點位查無商品走 `{% else %}No product selected for this dot` | `NilEmpty` | RF17 |
| 17 | 資源型 setting | 官方："blank if no selection has been made, the selection isn't visible, or the selection no longer exists"；實測未選（含缺鍵、動態來源解成非資源純量）⇒ 空字串（`card--media`）、已選但查無 ⇒ nil（`"media": null`）；直接輸出回 handle | `SettingsDrop#coerce` product／collection／page／blog／*_list（drop 透傳、缺鍵仍走資源規則）；資源 drop `to_s`＝handle；靜態 block 先合併 `closest` 覆寫再求值動態來源 | RF18／RF21 |
| 18 | 每個 block 渲染尾接 LF | 36 個 wrapper `</div>` 後全是 `\n`、緊貼形零個 | `render_block` 回傳尾接 `\n` | RF19 |
| 19 | json 過濾器 `\/` | `window.shopUrl = "https:\/\/hoko.vip"` | `JsonSerializer.dump(script_safe: true)` | — |
| 20 | `stylesheet_tag: preload: true` | 官方："a resource hint is sent as a Link header"；本尊 tag 無 preload 屬性 | 不輸出屬性（Link header 未實作，登記） | — |
| 21 | `font_face` src 兩行 | `url(…woff2) format("woff2"),\n       url(…woff) format("woff");` | 補 woff 備援行（我方 woff 檔未提供，現代瀏覽器不會請求） | F1 更正 |
| 22 | `color_modify: 'alpha', 0` | `rgba(0, 0, 0, 0)`（整數不帶 `.0`） | `css_alpha` | — |
| 23 | `link.handle`／`link.current` | `id="HeaderMenu-首頁"`、首頁 `aria-current="page"`；官方 current 逐字 | `LinkDrop#handle`（Unicode 保留）／`current`／`child_current`；`handleize` 同規則 | LL 規格 |
| 24 | `linklists[缺 handle]` | footer 選單區塊輸出空 `<ul>` ⇒ `{% if menu %}` 為真 | 回空 `LinkListDrop`（EmptyMenu；本尊物件形＝未取得，V） | — |
| 25 | `cart.taxes_included` | 稅注「已含税。优惠和运费将在结账时一起计算。」 | `shops.taxes_included`（預設 false） | — |
| 26 | `money` 空值 | `<s class="price-item price-item--regular"> </s>` | 空輸入 ⇒ 空字串 | RF16 |
| 27 | `{% render <block>, k: v %}` | Ella `_lookbook.liquid` 變數形帶參數（原 SyntaxError ⇒ 整塊「缺 block」） | `RenderTag` 參數進 block 變數 | — |

## §3 已登記差異（正規化抹掉或報告中保留、不算引擎缺口）

| 類 | 內容 | 落點 |
|---|---|---|
| 平台身分 | 主機／永久網域（`Shopify.shop`、canonical、JSON-LD url、`window.shopUrl`）、CDN 路徑（`/cdn/shop/t/2/assets` vs `/theme-assets`）、字型雜湊、`sections--{數字}`、theme 數字 id、block 實例前綴**值**（演算法不可觀測） | Normalizer |
| 裁定差異 | 我方路由前綴恆帶地區（67 §F.1(b)，2026-08-13）：本尊主市場預設語言**無前綴**（`href="/collections/all"`） | `CAND_PREFIX` 抹掉；**待裁定**（§4） |
| 平台功能 | 本尊新版顧客帳戶登入連結 `/customer_authentication/redirect?locale=…`／`https://shopify.com/{id}/account`；我方 `/account/login`／`/account/register` | 報告保留 |
| 版權 | placeholder 插圖本體（本尊版權圖 vs 我方自繪；外框屬性已對齊） | Normalizer `[placeholder]` |
| 平台注入 | `content_for_header` 內容（本尊 perf-kit／trekkie／shop-js／digital-wallet／preloads；我方 canonical＋hreflang＋JSON-LD） | head 資產集合差列出、不擋 |
| 金額格式 | 本尊 hoko（HKD）顯示 `$19.99`，我方原 `HK$19.99`（鐵律 10 範例）；本尊 shop 級 `money_format` 我方原未建 | **已收口**（D81 包 2026-09-03：`shops.money_format`／`money_with_currency_format`，`docs/dev/d81-shop-money-format.md`） |
| dev 環境 | canonical-url／hreflang 主機在本機（`mirror.chilllove.example`／`mirror.lvh.me`）與頁面主機不一致——config 層，production 同一網域 | 報告保留 |

## §4 使用者裁定（2026-09-03 已裁定，實作待開包）

1. **路由前綴**：D80——跟隨本尊市場／語言設定（主市場預設語言無前綴、額外語言 `/{lang}`、子資料夾市場 `/{lang}-{country}`）；
   67 §F.1(b)「恆有前綴」作廢。實作前 `CAND_PREFIX` 抹除只是過渡。
2. **貨幣顯示格式**：D81——店級 `money_format`／`money_with_currency_format` 跟隨本尊；鐵律 10 `HK$` 只是範例。
   **已落地**（2026-09-03，`docs/dev/d81-shop-money-format.md`）：hoko 快照帶兩鍵、鏡像店對齊後商品卡／購物車抽屜／頁首三段收斂。

## §5 首頁對表結果（2026-09-03，本機 mirror vs hoko.vip 快照）

見 worklog `docs/worklog/2026-09-03-渲染對表E8.md` §Done 的最終數字；21 段（含 `__head__`）中 16 段位元組相同（正規化後），其餘差異全部落在 §3。

## §6 下一步

- 逐頁：products／collections／cart／search／404／pages／blogs 快照已在 scratchpad（`parity/hoko-*.html`），鏡像店同頁跑 §1 流程。**第一項已知缺口**：`product.featured_media`／`featured_image` 無圖時本尊回 nil（/collections/all 三張真商品卡 `card--text`），我方回佔位 drop（91 §3.75）。
- computed CSS：同寬並排（本機 Chrome＋同源 iframe，見 memory three-width-measurement）逐元素比 `getComputedStyle`。
- bt3：demo 的 Ella 是名稱鍵主題（`themes/ella-7.2.0`，checksum 無）⇒ 直接 `bin/rails "render_parity:mirror[mirror]"` 建線上鏡像店，再用 URL 形跑 diff。
- §4 兩項裁定後回收對應正規化規則。
