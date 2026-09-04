# E16 頁首區段 fetch 內容的 Section Rendering HTML 段 diff（2026-09-04）

> 規範：鐵律 22（D82／D83）——前台輸出與本尊逐位元組對位；E8 工具契約見 `docs/dev/e8-render-parity.md`（本包＝§2d 第四批）。
> 取證＝`docs/dev/external-facts.md` §G24（hoko.vip curl 2026-09-04）。未取得／範圍外＝`docs/specs/91-pit-register.md` §3.85。

## 概述

Ella 五語言五市場後的頁首不內嵌語言／地區選擇器，而由 `section-fetcher` 打 `?section_id=sections--…__header_default` 取回整段（e8 §2c #66）。
資料面（31 國／5 語言，LC1／LC2）E15 已對齊；本包對這一段做 HTML 逐字 diff，抓到三個引擎缺口：section 形沒有請求頁脈絡、
`{% form 'localization' %}` 的 `return_to` 缺 query、`/localization` 不收 PUT（本尊表單自帶 `_method=put` ⇒ mirror 店真表單提交 404）。

## 這是什麼／具體功能（鐵律 12.4 ①②）

| 控件／行為 | 本尊形（§G24） | 我方（本包後） |
|---|---|---|
| section 形（`?section_id=`／`?sections=`）的 Liquid 脈絡 | 請求頁：`request.path`、`linklists` 的 `current`、paginate parts、tag 連結都以請求頁為準 | `PageRenderer#build_runtime(page_type, assigns, path)` 傳請求路徑（先前 nil） |
| `{% form 'localization' %}`／`currency` 預設 `return_to` | 當前請求的路徑＋原始 query string（順序、編碼逐字；`&` 不轉義）；前綴根 `/en?…` 不帶尾斜線；空 query 不加 `?` | `FormTag#default_return_to`：`registers[:request_path]`（長度 >1 去尾斜線）＋`?`＋`registers[:request_query]`；`"`／`<`／`>` 轉 entity（本尊處置 V） |
| 主題明給 `return_to:` | 官方 "Accepts `back`, relative paths, or routes attributes" | 照舊原樣輸出（`h()` 轉義，`&` ⇒ `&amp;`） |
| 整頁的 `return_to` query | 不可觀測（Ella 整頁不渲染該表單；V） | 進頁快取的整頁只餵**進快取鍵**的 query 對（`CACHE_PARAMS` ∪ `filter.*`，原順序）；`/search`／`/cart`／預覽／section 形餵原始 query |
| `/localization` 的 HTTP method | 表單 `_method=put` ⇒ PUT；PUT 直打 302 | routes `match … via: %i[post put]`（裸＋帶前綴） |
| `/localization` 對 `return_to` 的處置 | 只取路徑＋query：同站絕對 URL 保留、外站 host 丟掉只剩路徑、`back` ⇒ `/back`、含 `?section_id=…` 原樣 302 回 | `LocalizationController#safe_return_to` 改為 URI 解析取 path＋query（先前非 `/` 開頭一律回根——Ella JS 送絕對 URL ⇒ 真店表單每次落回首頁）；`return_path` 剝命中前綴、不剝 query |

## 怎樣做出來（鐵律 12.4 ③）

- `Storefront::PagesController#serve`：section 形／`/cart`／預覽／`/search` 呼叫 `render_page(..., query_string: request.query_string)`；快取分支傳
  `cache_relevant_query_string`（原始 query 對過濾成進鍵者）。`render_page` 把 `query_string.presence` 交給 `ThemeEngine::PageRenderer.new(query_string:)`。
- `ThemeEngine::PageRenderer`：`@query_string` 貫穿 `render_inside_tenant` 與 `build_runtime`；`render_single_section`／`render_sections_json` 把 `path`
  傳進 `build_runtime`。
- `ThemeEngine::Runtime#initialize(query_string:)` ⇒ `base_registers[:request_query]`；`request_path` 仍＝`"#{url_prefix}#{path}"`。
- `ThemeEngine::Tags::FormTag`：`default_return_to(context)`；預設值以 `RawAmp` 值物件標記 ⇒ 輸出時只轉 `"<>`，其餘隱藏欄照舊 `h()`。
- `config/routes.rb`：`match "localization" => "storefront/localization#create", via: %i[post put]`（裸形 `as: :storefront_localization`；
  `:locale_prefix` scope 同形）。
- `Storefront::LocalizationController#safe_return_to`：`URI.parse` 取 `path`＋`query`（解析失敗 ⇒ 手剝 scheme／`//host`），非 `/` 開頭補 `/`，
  多重前導 `/` 壓成一個；open redirect 防線＝永遠只用路徑（`redirect_to … allow_other_host: false` 不變）。
- 其他 `PageRenderer.new` 呼叫端（search／recommendations／cart sections／admin preview）未傳 `query_string` ⇒ `return_to` 只出路徑（既有形）。

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）

- **所有 section 形回應**（Ella 的 header／cart-drawer／recently-viewed／predictive-search fetch、我方編輯器 `draft_section`）現在帶請求頁脈絡：
  `linklists` current／`request.path`／tag 連結／paginate parts 與整頁同值。先前 `request.path` 在 section 形為 nil。
- **`return_to` 帶 query** ⇒ 買家從 fetch 來的頁首切語言／國家後，`/localization` 302 回 `…?section_id=…`（與本尊同形；Ella `localization-form.js` 提交前把 `return_to` 改寫成 `window.location.href`，伺服端預設值只在無 JS 時生效；絕對 URL 形的本尊處置＝V，91 §3.85）。
- **頁快取**：整頁 HTML 仍是快取鍵的純函數（只餵進鍵的 query 對）；section 形本就 `no-store`。
- **routes**：`PUT /localization`／`PUT /{prefix}/localization` 新增；`storefront_i18n_spec` 路由格（L5）釘住。`Rack::Attack` 的前綴剝除不看 method，不受影響。
- **E8／E12 對表**：頁首 SRA 段 differ 只剩新版顧客帳戶三處（e8 §3 平台功能列）；bt3 部署後以 `render_parity:diff` 重跑兩個脈絡（README 指令見 worklog）。

## 測試

`spec/liquid/form_tag_spec.rb` F6b；`spec/requests/storefront_section_rendering_spec.rb` SR6／SR7（fixture 新 `sections/sra-probe.liquid`＋
`templates/collection.sra.json`）；`spec/requests/storefront_i18n_spec.rb` L2b（絕對 URL／外站／`back`／絕對 URL 剝前綴）、L5（`_method=put` 裸／帶前綴／直打 PUT）、SR8（前綴根 `/zh-hant?…`）。
突變（worklog 表）：`build_runtime` 退回 `path: nil`、`default_return_to` 丟 query、`&` 走 `h()`、快取分支餵原始 query、routes 只收 POST、
`safe_return_to` 退回「非 / 開頭回根」⇒ 各自轉紅。

## 已知限制與 TODO

見 `docs/specs/91-pit-register.md` §3.85（`"<>` 處置、整頁 query 形、section 形 `request.path`、絕對 URL 形 `return_to`、新版顧客帳戶連結）。

## 變更記錄

- 2026-09-04 E16 首版（本檔）。
