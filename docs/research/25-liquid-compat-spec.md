# 25 — Liquid 相容層規格：讓第三方 Shopify 主題直接套用

> 目標（使用者需求原文）：「必須做到 shopify 本身的第三方主題可以直接套用使用在本項目中」。本文是達成此目標的完整工程規格：引擎選型、實作範圍、匯入管線、端點相容、測試策略與**授權紅線**。API 面全量 checklist 在 26 號；編輯器與資料模型在 24 號。

## 0. 目標定義與相容性承諾

「直接套用」＝商家把一個 Shopify 主題 zip 上傳到 CHILL LOVE → 通過驗證 → 出現在主題庫 → 發佈後前台以該主題渲染，**佈局、設定、編輯器可用性與互動（cart drawer、變體切換、預測搜尋）都能運作**。

誠實邊界（寫進產品文案與 degradation report）：

- **T0 承諾**：theme-blocks/OS 2.0 世代主題的核心購物路徑（首頁/商品/系列/購物車/搜尋/靜態頁）完整可用。
- **T1 承諾**：blog、顧客帳號、進階 cart、metafields 顯示。
- **T2 不承諾**（degradation report 明列）：訂閱（selling plans）、B2B、多市場進階、app blocks（該 app 不存在於我們平台）、Shopify 專屬整合（Shop Pay banner 等——渲染為空）。
- 結帳一律走我們的 checkout（主題只到 cart 為止把人送進 `/checkout`——這與 Shopify 現制一致：主題不含 checkout 頁）。

## 1. 架構總覽

```
主題 zip ─▶ 匯入管線（驗證/清單/降級報告）─▶ theme_files（DB/S3）
                                                    │
買家請求 ─▶ Storefront Router ─▶ ThemeRuntime ──────┤
              │   1. 解析 route → template JSON      │
              │   2. 組 context（drops）             ▼
              │   3. Liquid render（gem + 平台層） compiled AST cache
              │   4. content_for_header 注入
              └─▶ HTTP 相容面（/cart/*.js、?sections=、/search/suggest.json …）
```

三個相容面，缺一不可（主題＝Liquid 模板 ＋ 依賴平台端點的 JS ＋ 設定 schema）：

1. **語言面**：Liquid 語法＝ **Shopify/liquid gem 5.13.x（MIT）** 原生提供，零實作。
2. **平台面**：Shopify 專屬 objects（138 drops）/ tags（9）/ filters（94）＝我們實作（分層）。
3. **HTTP 面**：主題 JS 硬依賴的端點（§5）＝我們 1:1 實作。

## 2. 引擎：Shopify/liquid gem 能力邊界（已實測驗證）

| 事實 | 內容 |
|---|---|
| 版本/授權 | 5.13.0（2026-06）；**標準 MIT**，無使用限制 → D4 決策的法律基礎 |
| 依賴 | Ruby ≥3.0、strscan ≥3.1.1、bigdecimal（Rails 8 環境相容） |
| 內建 tags（20） | assign/break/capture/case/comment/continue/cycle/decrement/doc/echo/for/if/ifchanged/include/increment/#/raw/render/tablerow/unless（`{% liquid %}` 為語法特例，亦支援） |
| 內建 filters（60） | 通用型：size/upcase/split/join/map/where/reject/find/has/sort/uniq/date/plus/…/sum（完整清單見 26 號） |
| 擴充 API | `Liquid::Environment.build`（5.6+ 新架構；**建獨立 env，不污染全域**）→ `register_tag` / `register_filter` / `file_system=` / `error_mode=` / `exception_renderer=` |
| Drop 協定 | `Liquid::Drop` 子類：公開方法自動可呼叫；`liquid_method_missing` catch-all；`to_liquid` 轉換協定 |
| 模板載入 | `file_system.read_template_file(path)→String`——自實作 DB-backed loader 供 `render/include` 載 snippets；`PartialCache` 單次 render 內自動快取 |
| registers | `template.render(assigns, registers: {…})`——每請求傳入服務物件（cdn host、routes、cart）的正規通道 |
| 資源限制 | `render_length_limit / render_score_limit / assign_score_limit / cumulative_*`——超限 raise `MemoryError`；**租戶隔離的核心保險** |
| Parse 模式 | `:lax`（匯入第三方主題用）/`:strict`；render 期 `strict_variables/strict_filters`（開發模式用） |
| 錯誤 | `Liquid::Error` 16 子類（含 line_number/template_name）；非 bang render 把錯誤收進 `template.errors` 並繼續 |
| 效能 | parse 一次得可重用 AST（**自建 theme_file→AST cache**）；render 線程安全（state 在 Context）；liquid-c 已停維護，**不用** |

## 3. 我們要實作的三個清單（差集＝工作量）

以官方機器可讀庫 `Shopify/theme-liquid-docs`（MIT，與 shopify.dev/theme-check 同源）為基準取差集：

| 面 | 總量 | gem 已有 | 我們實作 | T0 最小集 |
|---|---|---|---|---|
| Tags | 30 | 20＋liquid | **9**：content_for/form/javascript/layout/paginate/section/sections/style/stylesheet（＋`{% schema %}` 匯入期剝離） | 全部 9 個 |
| Filters | 154 | 60 | **94**：money×5、media×12（image_url！）、hosted_file×6、color×16、html×8、localization×3（t！）、format×6、string 平台×14、payment×4、customer×5、collection×7、cart×2、tag×3、default_errors/pagination | ~45 個 |
| Objects | 138 | 0 | **138 drops**（product/variant/collection/cart/customer/shop/request/routes/settings/section/block/paginate/forloop…） | ~40 個（＋其餘 nil-stub） |

關鍵工程注意：

- **nil-stub 策略**：Dawn/Horizon 模板會引用大量 T1/T2 屬性；T0 階段所有 138 objects 的屬性都必須「存在且回 nil/空陣列」（用 `liquid_method_missing` 統一兜底＋遙測記錄），否則渲染直接炸。
- **金額慣例**：所有 money 屬性回傳 **cents 整數**，由 money filters 格式化——與我們全站 integer cents 鐵律一致。
- **`content_for_header` 注入**：主題 JS 依賴 `window.Shopify.*` 全域（實查 Dawn/Horizon 用到：`designMode / routes.root / loadFeatures / ModelViewerUI / CountryProvinceSelector / PaymentButton / postLink`）——我們的 header 注入要提供同名 API（自寫實作）。
  <!-- 2026-08-30 live 更正（83 §5）：真店（Ella 7.2.0）實測 window.Shopify 共 32 鍵，
       比本清單多出 legacy 八件：formatMoney / getCart / onCartUpdate / removeItem /
       bind / setSelectorByValue / addListener / postLink（option_selection.js 世代）。
       Ella 相容 stub 集以 83 §5 的 live 清單為準，本行 Dawn/Horizon 集是子集。 -->
- **`routes` drop（19 個 URL 屬性）是第一相容層**：主題 JS 不硬編碼路徑、而是讀 `theme.liquid` 注入的 `window.routes`（cart_add_url…）。但**回應格式**仍是硬依賴（§5）。
- 自動化：clone theme-liquid-docs 的 `data/*.json`（138 objects 全屬性+型別）→ 代碼生成 drop 骨架＋相容性測試表。

## 4. 主題匯入管線

```
上傳 zip（≤50MB）
 → 1. 安全檢查：zip bomb/路徑逃逸（../）/檔案類型白名單/單檔上限
 → 2. 結構驗證：layout/theme.liquid 必在；資料夾白名單；JSON 全部 parse
 → 3. theme-check（@shopify/theme-check-node 3.28+，MIT，Node sidecar）：
      LiquidHTMLSyntaxError / JSONSyntaxError / ValidSchema / MissingTemplate /
      RequiredLayoutThemeObject（content_for_header/layout 必在）/ UnknownFilter /
      UndefinedObject / HardcodedRoutes（偵測硬編碼端點的主題！）…
 → 4. 相容性掃描（我們自建）：抽取全部用到的 objects/tags/filters
      → 對照 26 號清單 → 分級：T0 全綠？T1 缺什麼？T2 引用哪些？
      → 產出 degradation report（商家看得懂的中文清單）
 → 5. 授權聲明 gate（§8：勾選確認有權使用此主題）
 → 6. 入庫：themes + theme_files（原文）；schema/settings 解析進結構化欄位
 → 7. 編譯：Liquid parse（:lax）→ AST cache；settings_schema → 編輯器面板 spec
 → 8. 狀態：未發佈（可預覽）→ 商家發佈
```

失敗處理：第 2/3 步紅色錯誤＝拒收（附行號報告）；第 4 步只警告不阻擋（T2 缺失＝黃色降級清單）。

## 5. HTTP 相容面（主題 JS 硬依賴端點——欄位級規格）

全部 locale-aware（支援 `/{locale}` 前綴）。金額一律 cents 整數。

| 端點 | 要點 |
|---|---|
| `GET /cart.js`（**及** `/cart.json`——Dawn 兩個都打；2026-08-30 live 實測**兩端點頂層鍵序完全相同**，且比本列多一鍵 **`discount_codes`**——83 §3.3） | 回 cart object：token/note/attributes/original_total_price/total_price/total_discount/total_weight/item_count/items[]/requires_shipping/currency/items_subtotal_price/cart_level_discount_applications[]。items[] 每項 30+ 欄位（id=variant_id、key=`{line_id}:{hash}`、price/final_price/final_line_price、properties、featured_image{url,alt,width,height,aspect_ratio}、options_with_values、url 含 ?variant=、quantity_rule…） |
| `POST /cart/add.js` | **同時支援** multipart/form-data（Dawn product form 原樣 FormData）與 JSON `{items:[{id,quantity,properties,selling_plan}]}`；支援 Bundled Section Rendering（`sections`≤5＋`sections_url`→回應加 `sections:{id:html}`）；**成功回「被加入的 items」非整車**（Dawn 會再打 /cart.js 取總計）；錯誤 422 `{status,message:"Cart Error",description}` |
| `POST /cart/update.js` | `{updates:{variant_id_or_key:qty}\|[qty…], note, attributes, discount, sections}` → 完整 cart JSON |
| `POST /cart/change.js` | `{id\|line(1 起算), quantity(0=移除), properties(整包覆蓋), selling_plan, sections}` → 完整 cart JSON；`{status:"bad_request"}` 或 422 |
| `POST /cart/clear.js` | → 空 cart（**保留 note/attributes**） |
| `GET /cart/shipping_rates.json` | query shipping_address[zip/country/province] → `{shipping_rates:[{name,price,delivery_date,source}]}` |
| **Section Rendering API** | `?sections=id1,id2`（≤5）→ JSON `{id: "<div id=\"shopify-section-{id}\" class=\"shopify-section\">…</div>", 失敗:null}`；`?section_id=` → 裸 HTML。動態 id 格式 `template--{n}__{name}`、`sections--{n}__{name}`。Dawn 實際用法：cart-drawer、main-cart-items、`/variants/{id}/?section_id=pickup-availability`、predictive-search、related-products |
| `GET /search/suggest.json` | q＋resources[type]（product,page,article,collection,query）＋limit(1-10)＋limit_scope＋options[unavailable_products=show\|hide\|last]＋options[fields]。回 `{resources:{results:{queries[],products[],collections[],pages[],articles[]}}}`（欄位見代理報告；Dawn 同時用 `?section_id=` HTML 版——**兩形都要**） |
| `GET /recommendations/products.json` | product_id＋limit(1-10)＋intent(related\|complementary) → `{intent, products:[…完整商品 JSON]}`；HTML 版 `?section_id=` |
| `POST /localization` | form 欄位：form_type=localization/utf8/_method=put/return_to/country_code＋語言欄位——**Dawn 用 `locale_code`、Horizon 用 `language_code`，兩個名字都要接受**；302 回 return_to 套 locale 前綴 |
| **`?view={suffix}` alternate template 路由** | `{type}.{suffix}.{json\|liquid}` 解析＋`{% layout none %}` 支援——主題把 alternate template 當 **AJAX fragment 端點**用（Ella：`?view=ajax_edit_cart`/`quick_add`/`block_wishlist_card` 等 5 個，見 27 號 §6.6）。**升級 M2**（cart 編輯彈窗依賴） |

> 這張表直接併入 09 號 API 地圖與 M2 驗收：**先讓 Dawn 的 cart drawer 對著我們的端點動起來，再談其他**。

## 6. 渲染服務設計（Rails 落地）

```ruby
# 一次性（boot）：
LIQUID_ENV = Liquid::Environment.build do |e|
  e.error_mode = :lax
  ChillLove::Liquid::TAGS.each    { |n, k| e.register_tag(n, k) }      # 9 個
  ChillLove::Liquid::FILTERS.each { |m| e.register_filter(m) }          # 94 個（分模組）
  e.default_resource_limits = { render_length_limit: 2.megabytes,
                                render_score_limit: 200_000,
                                assign_score_limit: 100_000 }
end

# 每請求：
class ThemeRuntime
  def render(shop, theme, route)
    template  = resolve_template(theme, route)          # JSON template + overrides merge
    ast       = AstCache.fetch(theme_file) { Liquid::Template.parse(src, environment: LIQUID_ENV) }
    context   = build_drops(shop, route)                # product/collection/cart/shop/routes/settings…
    ast.render(context,
      registers: { shop:, theme:, file_system: DbFileSystem.new(theme), cdn: })
  end
end
```

規則：

1. **Drops 包 AR models，禁 N+1**：drop 初始化時接 preloaded scope；`forloop`/`paginate` 由平台 tags 供給。
2. **AST cache**：`theme_files.updated_at` 為 key（Solid Cache）；發佈新版本＝整主題 cache bust。
3. **安全**：Liquid 本身無任意代碼執行；風險在 drops 暴露面（**只暴露白名單屬性**）與輸出（section settings 的 html/liquid 型值已是商家自傷範圍，與 Shopify 同標）＋ resource limits 防 DoS；`{{ … }}` 預設不轉義與 Shopify 一致，XSS 防線在「我們的 drops 不回傳未清洗的買家輸入」。
4. **錯誤策略**：production＝lax＋`exception_renderer` 把錯誤變 HTML 註解＋上報；theme 開發模式＝strict_variables 警告面板。
5. **快取分層**（對齊 14 號 spec）：整頁 cache（匿名買家、cart 為空時）→ section cache → AST cache；cart 相關 section 永不整頁快取。

## 7. 相容性分層與測試策略

- **T0/T1/T2 定義與逐項清單**：見 26 號 §6（tier 統計）。
- **Golden-file 測試**：以（合法取得的）真實主題結構為 fixture——**測試 fixture 用我們自寫的迷你主題**（複製 Dawn 結構模式、不複製其代碼），對每個 T0 object/tag/filter 寫「模板片段 → 期望 HTML」對照表；theme-liquid-docs 的 JSON 自動生成屬性存在性測試（138 objects × 屬性 → 至少 nil 不炸）。
- **端點契約測試**：§5 每個端點一組 request/response JSON schema 測試；再用 headless 瀏覽器跑「cart drawer 加購→數量改→移除」E2E。
- **相容性回報**：runtime 記錄 `liquid_method_missing` 命中（哪個主題引用了我們未實作的屬性）→ 儀表板排 T1/T2 優先級。

## 8. 授權紅線（本功能的法律面——必讀）

研究代理查證的事實（2026-08 現況）：

| 標的 | 事實 | 對我們的約束 |
|---|---|---|
| liquid gem / theme-check(TS) / theme-liquid-docs | 標準 MIT | ✅ 自由使用（引擎與驗證器無虞） |
| **Theme Store 主題**（含付費） | Shopify ToS §9.6：授權**單一商店**（"licensed to use it for a single Store only"…"not permitted to transfer or sell…elsewhere"）；IP 屬第三方設計師（各有 EULA） | ⚠️ 商家把主題搬來我們平台＝條款文字未授權的使用。**產品義務**：匯入流程強制授權聲明 gate（「我確認我有權在本平台使用此主題」勾選＋說明文案）；我們不提供、不轉售、不預載任何 Theme Store 主題 |
| **Ella 7.2.0（本專案 golden theme）** | ThemeForest/Envato 通路商業主題；**使用者已購買授權**（單店使用、不得再散布） | ✅ **使用者自用面已解決**：作為測試 fixture 入私有倉庫（`test/fixtures/themes/ella-7.2.0`＋LICENSE-NOTE）、跑相容測試、用於使用者自有商店——皆在其授權內。❌ 平台面不變：不得預載/散布給**其他**商家（每商家自購或談 Halothemes 平台合作）；第一方主題仍從零自寫 |
| **Dawn** | **不是純 MIT**——LICENSE.md 是加了使用領域限制的修改版 MIT：「僅可用於開發與 Shopify 軟體/服務整合互通的主題…**所有其他用途一律禁止**」（2021 年首 commit 即如此） | ❌ 平台端禁止使用/衍生 Dawn 代碼（與既有紅線一致，現在有了確切條款依據） |
| **Horizon** | 同款 interop 限制且更嚴：禁止經「**任何站外渠道**」散布衍生主題；Shopify 有權單方認定何為衍生 | ❌ 同上 |
| **訴訟先例** | Shopify v. SHOPLINE（2024 起訴：其 Seed 主題抄 Dawn；**2026-06 和解**：賠款＋停止散布） | 🔴 Shopify 對「非 Shopify 平台重用其主題資產」**積極執法**。我們的第一方主題必須從零自寫（結構模式可學、代碼不可抄）；平台自身絕不散布 Dawn/Horizon 衍生物 |
| 先例專案 | vfonic/solidify（Solidus 上渲染 Shopify 主題，MIT，2023 archive、未完成）——唯一公開嘗試 | 佐證工作量在 drops/端點面；可讀其架構參考（MIT），不依賴其代碼 |

**產品面落地**：(1) 匯入 UI 的授權聲明 gate＋幫助文案（Theme Store 主題授權限單店，請向主題開發商確認）；(2) 我們的預設主題＝自寫（M2 的 CHILL LOVE 品牌主題，遵守 23 號 tokens）；(3) 行銷文案永遠說「相容 Shopify 主題格式」，不說「提供 Shopify 主題」。

## 9. 里程碑整合（修訂 M2/M6）

| 里程碑 | 原內容 | 修訂後 |
|---|---|---|
| M2 前台線 | Storefront SSR＋theme JSON 渲染＋cart drawer | **Liquid 引擎接入**（gem＋T0 tags/filters/drops ~40 objects）＋ 自寫預設主題（theme-blocks 世代結構）＋ §5 端點的 cart 家族＋SRA ⇒ 驗收：預設主題全站可逛＋cart drawer 走 /cart/*.js |
| M6 編輯器 | 三欄主題編輯器 | 主題編輯器（24 號 §3 六原子操作）＋ **匯入管線（§4）**＋ T1 補完＋predictive search/recommendations 端點 ⇒ 驗收：一個外部 OS 2.0 主題匯入→degradation report→發佈→可逛可加購 |
| M6+（P2） | — | T2 長尾、市場覆寫、AI 生成 block |

工作量現實（給排期）：94 filters 中 money/media/url 三族最重（image_url 的 width/height/crop/format 參數矩陣）；138 drops 靠代碼生成骨架＋逐個接資料；端點面約 10 支控制器但欄位密度高。T0 全綠估 3-4 週全職。

## 10. 坑清單（本模組專屬）

1. **cart/add.js 的雙格式**：只實作 JSON 會讓所有主題的加購表單壞掉（Dawn 送 FormData）。
2. **回應形狀差異**：add.js 回 items 不回整車；change/update 回整車——搞反了 drawer 數字全錯。
3. **section_id 的兩種形態**：`?sections=`（JSON、含 wrapper div）vs `?section_id=`（裸 HTML）；wrapper 的 `id="shopify-section-{id}"` 缺了會讓主題 JS 找不到節點。
4. **localization 欄位名分裂**：locale_code（Dawn）vs language_code（Horizon）——都收。
5. **nil-stub 不做就是白屏**：主題模板到處引用 selling_plan/localization 屬性；缺屬性＝Liquid 炸整頁（lax 下輸出空但 drop method missing 要兜住）。
6. **settings 值型別**：image_picker 回 image drop 不是 URL 字串；richtext 回包 `<p>` 的 HTML；color 回 color 物件（有 .red/.alpha 方法）——filters（image_url、color_modify）吃的是物件。
7. **`{% schema %}` 忘了剝**：把 schema 當內容渲染會直接把 JSON 印在頁面上（匯入期剝離存表）。
8. **資源限制不設**：一個惡意 for 迴圈主題能吃爆 worker——resource limits＋timeout 是多租戶的底線。
9. **liquid-c 誘惑**：已停維護，別為 3x parse 速度引入。
10. **授權 gate 跳過**：§8 的聲明勾選不是 nice-to-have，是上線前置條件。
11. **寬容解析缺失**：第三方原始碼包的 schema/settings JSON 常帶註解與尾逗號（官方後台會清、原始碼不會）——匯入管線必須 tolerant parse＋規範化，否則 Ella 這類主題第一步就掛。
12. **缺 group 檔要寬容**：Ella 的 theme.liquid 引用不存在的 `toolbar-mobile` group——渲染空＋警告，不可炸。
    <!-- 2026-08-30 live 證實（83 §9）：真店跑同一份主題，該群組引用靜默空渲染、頁面照常
         （warning 面未取得）。「渲染空」由推定升格為實證；同名 sections/toolbar-mobile.liquid
         是 popup 群組的成員 section，與群組引用是兩回事。 -->
13. **`Shopify.*` no-op stubs 不做**：主題 JS 引用 ShopifyXR/PaymentButton/loadFeatures/CountryProvinceSelector——沒有 stub 就是 console 炸裂＋功能連鎖失效。
14. **（PoC 實測）`blank` 語義依賴 ActiveSupport**：gem 的 `x == blank` 走 `MethodLiteral(:blank?)`，裸 Ruby 無 `Object#blank?` → `undefined == blank` 恆 false——主題「`if x == blank` → assign」慣用法全滅（實測 Ella 全部標題消失）。Rails 環境自帶 ActiveSupport 即修復；**引擎啟動自檢必須驗證 blank?/present? 已載**。
15. **（PoC 實測）strscan 版本鏈**：liquid 5.6+ 需 strscan ≥3.1.1（`peek_byte`）；Ruby 3.3 內建 3.0.x 直接炸——Gemfile 明鎖 `gem "strscan", ">= 3.1.1"`。

## 11. 編輯器運行時契約（Ella 驗證版——完整規格見 27 號 §6）

「編輯器與 Shopify 完全一樣」的硬邊界＝主題 JS 實際監聽的介面：

1. **八個 DOM 事件**：`shopify:section:load/unload/select/deselect/reorder`、`shopify:block:select/deselect`、`shopify:inspector:activate/deactivate`——bubbles、detail 含 `sectionId/blockId/load`；target＝section wrapper 或帶 `data-shopify-editor-block` 的元素。
2. **標記**：wrapper `id="shopify-section-{fullId}"`＋design mode 的 `data-shopify-editor-section`；`{{ block.shopify_attributes }}` → `data-shopify-editor-block='{"id","type"}'`（僅 design mode）。
3. **旗標**：`window.Shopify.designMode` ↔ `{{ request.design_mode }}`。
4. **重渲染語義**：draft-render 私有端點（公開 SRA 不能帶未儲存設定）→ `unload` → outerHTML 替換（**script 不自動執行**，主題自己在 load 時重跑）→ `load` → 選中態補發 `select(load:true)`；排序只動 DOM＋`reorder`；color/text 有即時 patch 快通道（CSS var/文字節點）。
5. **ID 規則**：生成 `{type 底線化}_{6 碼 base62}`；讀入兼容 timestamp+hex 與 UUID 舊世代；fullId `template--{n}__{key}`；block id 唯一範圍＝section。
6. **picker 規則**：section＝有 presets 才可加（category 分組/name 排序/enabled_on 過濾）；block＝顯式白名單（可含 `_` 私有）∪ `@theme`（排除私有），顯式者 recommended；靜態 block 不可拖/刪。
7. **golden theme**：Ella 7.2.0——M6 驗收＝27 號 §8 十條全綠。
