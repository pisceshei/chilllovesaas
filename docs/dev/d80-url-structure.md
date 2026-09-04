# D80 前台語言 URL 前綴、市場選擇與 hreflang 改回本尊形（2026-09-04）

## 概述

使用者 2026-09-04 裁定 D80 **方案 1**（`docs/DECISIONS.md` D80 末段）：前台 URL 只承載**語言**、市場由買家選國的 cookie 承載、hreflang 只列語言碼。
本包把 2026-08-13「恆帶地區、恆有前綴、hreflang 逐國展開、根路徑 302」整組換掉，並把鏡像店（`RenderParity::Mirror`）同步成本尊形。
取證＝`docs/dev/external-facts.md` §G23（hoko.vip curl 2026-09-04＋官方 help／dev 逐字）。

## 規格出處

- `docs/specs/67-multilingual.md` §F.1(b)(c)(d)（前綴規則、身分、餵給 62 的三樣）——本包回寫。
- `docs/specs/62-seo-geo.md` §I.1／§I.2／§I.2-1／§O REG-3／REG-4（碼粒度、x-default、驗收）——本包回寫。
- `config/limits.yml` `i18n.locale_prefix.*`／`seo.hreflang.*`——鍵改名，沿革在鍵旁註釋。
- 官方逐字：help「Use subfolders, such as `example.com/de`」；子資料夾市場「such as `example.com/fr-ca`」；`{% form 'localization' %}`
  "Generates a form for customers to select their preferred country so that they're shown the appropriate language and currency."（§G23）。

## 這是什麼／具體功能（鐵律 12.4 ①②）

| 控件／行為 | 形態與值域 | 本尊實測（§G23） |
|---|---|---|
| 語言前綴 | 共用網域 presence：預設語言 `""`（無前綴）、其他 `/{小寫 BCP-47}`（`/zh-hant`、`/en`、`/fr`、`/ja`、`/pt-br` V）；子資料夾 presence：全部語言 `/{lang}-{suffix}`（`/en-ca`） | `/` 200 lang=zh-CN；`/zh-hans/` 404；`/zh-hant/`、`/en/collections/all` 200 |
| 根路徑／無前綴路徑 | 直接以店預設 (market, locale) 渲染（不 302）；查無頁面 404 | `/` 200；`/en-us` 404 |
| 前綴查無 | 整條路徑當無前綴路徑 ⇒ 通常 404（沒有 `/fr-hk/…` 這個頁面） | `/zh-hans/` 404 |
| 市場 | ①URL 前綴命中的 presence 的市場；②共用主網域上沒有自己 presence 的市場由 `localization` cookie（ISO 3166-1 alpha-2）覆寫；語言不受 cookie 影響 | GET `/` 帶 `localization=US` ⇒ `Shopify.country = "US"`、`locale` 仍 zh-CN |
| `POST /localization` | `country_code`／`language_code`／`return_to`：語言 ⇒ 302 到 `{prefix}{return_to 剝前綴}`；國家屬子資料夾／自有網域市場 ⇒ 302 到該 presence 前綴；國家屬共用市場或 primary ⇒ `Set-Cookie: localization={CC}; path={語言根路徑}; expires=1 年; SameSite=Lax` 並 302 留在同語言 | ①US ⇒ 302 `/collections/all`＋`localization=US; path=/`；②en ⇒ 302 `/en/…`＋`localization=TW; path=/en`；③JP＋ja ⇒ 302 `/ja/…`＋`localization=JP; path=/ja` |
| `Shopify.routes.root`／`routes.root_url` | 預設 `"/"`／`"/"`；其他 `"/zh-hant/"`／`"/zh-hant"` | 同左 |
| `localization.language.root_url` | 預設 `"/"`；其他 `"/zh-hant"` | `window.routes.root_url` 同形（`language.root_url` 本尊值 V） |
| hreflang（`<head>`＋sitemap `xhtml:link`） | 共用網域 presence：每個開放∧已發布語言一條 `{language[-Script]}`；x-default ⇒ primary 預設語言的無前綴 URL；沒有自己 presence 的市場不進矩陣；子資料夾 presence：逐國展開（V） | 每頁六條、零地區碼、零市場段 |
| canonical | 自指＝當前 presence × 語言的 URL（預設語言無前綴） | Ella `<link rel="canonical" href="https://hoko.vip/en/collections/all">` |
| sitemap | index＋單組子表、每 `<url>` 帶全部語言 `xhtml:link`（本尊每語言一組子表＝V） | index 列 `/zh-hant/sitemap_products_1.xml…` |

## 怎樣做出來（鐵律 12.4 ③）

- `Markets::UrlPrefix.for(presence, locale)`：`suffix.present? ⇒ "/{tag}-{suffix}"`；`tag == presence.default_shop_locale ⇒ ""`；否則 `"/{tag.downcase}"`。
  `SEGMENT = /[a-z]{2,3}(-[a-z]{4})?(-[a-z]{2})?/`（地區段可選）、`FORMAT` 容許空字串；保留段檢查只對非空前綴。不再看市場 regions（`MissingRegionSource`
  保留類別、不再拋出）。
- `Markets::PrefixIndex`：`resolve` 不變（比對非空前綴）；`Hit` 加 `country_code`＋`effective_country_code`；新增 `with_buyer_country(hit, shop:, domain:,
  country_code:)`（共用網域 hit ∧ 該國屬「無自己 presence」的 active region 市場 ⇒ 換市場；屬 primary 自己 ⇒ 只記國碼；子資料夾 hit 原樣）、
  `shared_market_for_country`、`prefix_segments(shop:)`（URL 重導驗證用的真實前綴集合）。
- `Storefront::BaseController`：`buyer_country_code`（cookie `localization`，`MarketRegion::COUNTRY_CODE_FORMAT` 過濾）；`locale_hit`／`default_hit` 皆套
  `apply_buyer_country`。`PagesController#root` 直接 `serve(default_hit, "/")`；`#show`：第一段像前綴才查 `locale_hit`，查無 ⇒ 整條路徑＋`default_hit`；
  `render_page` 帶 `market:`／`country_code:`；301 引擎前綴拼接容許空字串。
- `Storefront::LocalizationController`：`effective_hit` 的 presence 為基底；`market_for_country`（primary 優先）；有自己 presence ⇒ 302 該前綴；否則
  `resolve_language(presence, current:)`（請求語言 > 當前語言〔POST 前綴／`return_to` 命中前綴〕> presence 預設）、寫 cookie、302。`return_path` 只剝
  **命中**的前綴（`return_prefix_hit`），不剝「像前綴」的段。
- `ThemeEngine::PageRenderer`／`Runtime`：新增 `market:`／`country_code:`；`Shopify.country` 讀 `@country_code`；`Storefront::LocalizationContext.drop`
  收 `market:`／`country_code:`（`localization.country`／`market` 跟買家走，語言集合仍是 presence 的；`root_url_for` 把空前綴轉 `"/"`）。
- `Markets::HreflangCodes.for_presence(presence, locale)`：`suffix.present? ⇒ for(market, locale)`（逐國）；否則 `Set[language_code(locale)]`。
  `Seo::HreflangMatrix.entries` 改呼叫 `for_presence`；`x_default_url` 不變（預設語言前綴為空 ⇒ 無前綴 URL）。
- `config/routes.rb` scope constraint `/[a-z]{2,3}(-[a-z]{4})?(-[a-z]{2})?/`；`config/initializers/rack_attack.rb` 前綴剝除同形。
- `UrlRedirects::Normalize#prefixed?`：形狀粗篩後以 `PrefixIndex.prefix_segments(ActsAsTenant.current_tenant)` 判定；無租戶 ⇒ 形狀（fail-closed 偏拒絕）。
- `Storefront::CartController#strip_locale_prefix`／`CommentsController`／`SearchController`／`RecommendationsController`：前綴一律來自 `effective_hit`
  （`locale_hit` 查無 ⇒ 店預設 `""`），不再從 `params[:locale_prefix]` 直接拼。
- `RenderParity::Mirror#align_markets`：`markets[].suffix` 缺 ⇒ 不建 presence，並拆掉既有 presence（E15 期的 subfolder；`removed=N` 入 log）；
  `spec/fixtures/render_parity/hoko.json` 四個市場移除 `suffix`。
- 頁快取：key 已含 `market`（`Storefront::PageCache.key_for`），cookie 覆寫後的市場自然分 key（`storefront_i18n` L3b 釘住）。

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）

- **所有店面 URL 變形**：既有 `/en-hk/…`、`/zh-hant-hk/…` 一律 404（本尊同形）；預設語言頁在根；主題 `routes.*`、`link.url`、canonical、sitemap、
  hreflang、301 引擎、`/localization`、cart／search／recommendations 帶前綴路由全部跟隨。既有外部連結／書籤若指向舊形需商家自建 301（未做）。
- **市場由 cookie 決定** ⇒ 同一 URL 對不同買家可能是不同市場（`Shopify.country`、`localization.country`／`market`）；我方市場無獨立幣別／價格，
  故金額不變（Markets 幣別／價格差異落地時，頁快取 key 已含 market，不會互汙；`Vary` 未加 cookie，CDN 快取若上線要先處理——登記 91 §3.84）。
- **E8／E12 對表**：mirror 店根路徑就是本尊形 ⇒ `CAND_PREFIX` 不再需要（Normalizer 的 `url_prefix:` 保留為工具能力）；e8 §3 裁定差異列①②收口。
- **主題編輯器預覽**（e13）：預覽仍以 `default_hit` 渲染、`url_prefix ""`——與買家前台預設語言頁現在**同 URL 形**。
- **Admin**：`SettingsRedirectsPage` 文案例子改 `/zh-hant/…`；重導路徑驗證只擋本店真實前綴。
- **未動**：67 §F.2 語言不自動重導、`Accept-Language` 不影響輸出（SF-1／SF-3／SF-10 仍釘）；62 §K.2 地區重導未實作。

## 測試

`spec/services/markets/url_prefix_spec.rb`（U1–U8）、`hreflang_codes_spec.rb`（H1–H5）、`prefix_index_spec.rb`（DH1–3／DR1／BC1／BC2）、
`spec/services/markets/provision_defaults_spec.rb` P5、`spec/models/markets_data_layer_spec.rb` M9、`spec/services/render_parity/mirror_spec.rb`
MR1–MR4、`spec/services/storefront/localization_context_spec.rb` LC5、`spec/requests/storefront_i18n_spec.rb`（SF-*／SW1／L1–L4／L3b）、
`storefront_pages_spec.rb` S1／S2／S4／S8、`storefront_seo_spec.rb` SEO2／SEO6、`url_redirect_engine_spec.rb` E1–E3／G2、
`theme_editor_preview_parity_spec.rb` PV2b、`theme_shopify_global_spec.rb` SG1；其餘 request spec 的 `/en-hk/…` 一律改 `/…`、`/zh-hant-hk/…` 改 `/zh-hant/…`。
突變（本包 worklog 表）：預設語言加回前綴、共用網域碼加回地區、根路徑改 302、cookie 也改語言、子資料夾市場被 cookie 拉走 ⇒ 各自轉紅。

## 已知限制與 TODO

見 `docs/specs/91-pit-register.md` §3.84（子資料夾／自有網域 hreflang 本尊形、每語言一組 sitemap 子表、country-only 提交的語言處置、
`language.root_url` 本尊值、cookie 與 CDN `Vary`、`/en-us` 類舊形無 301）。

## 變更記錄

- 2026-09-04 D80 方案 1 首版（本檔）。
