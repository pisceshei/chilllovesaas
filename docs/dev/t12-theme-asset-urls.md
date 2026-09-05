# T12 主題資產 URL 本尊形——`asset_url`／`asset_img_url`／`file_url`／`file_img_url`／`shopify_asset_url`／`global_asset_url`／`font_url`

> 路線圖 T12（`docs/plans/2026-09-05-全對齊路線圖.md` §2）。取證全文＝`docs/dev/external-facts.md` §G28（官方 filters 頁＋hoko.vip 2026-09-05）；
> 未取得／範圍外＝`docs/specs/91-pit-register.md` §3.89。worklog／handoff＝`docs/worklog/2026-09-05-主題資產URL本尊形T12.md`、
> `docs/handoff/2026-09-05-主題資產URL本尊形T12.md`。前置＝E19a（`compiled_assets` 已走本尊路徑形）。

## 1. 這是什麼（本尊行為）

七個資產 URL 濾鏡都回 **店主機**（hoko.vip；官方例＝myshopify 永久網域）的協定相對 CDN 路徑：

| 濾鏡 | 本尊形（官方例／hoko 實測） | 我方（本包後） |
|---|---|---|
| `asset_url` | `//host/cdn/shop/t/{theme_id}/assets/{file}?v={28–30 位}` | 同形；`?v=`＝每檔摘要（≤20 位）＋主題版本秒 |
| `asset_img_url: size` | `…/assets/{stem}_{size}{ext}?v=…`（size 預設 `small`） | 同形；供給端回原檔（不縮放，V） |
| `file_url` | `//host/cdn/shop/files/{name}?v={19 位}` | 同形；`StoredFile` 以 filename 查；缺檔仍出 URL、無 `?v=`（V） |
| `file_img_url: size` | `…/files/{stem}_{size}{ext}?v=…` | 同形；供給端以官方 `img_url` 尺寸表選 width |
| `shopify_asset_url` | `//host/cdn/shopifycloud/storefront/assets/themes_support/{stem}-{8hex}{ext}` | 同形（8hex＝路徑 SHA-1 前 8 位）；本體未提供 ⇒ 404（V） |
| `global_asset_url` | `//host/cdn/s/global/{file}` | 同形；本體未提供 ⇒ 404（V） |
| `font_url[: 'woff']` | `//host/cdn/fonts/{family}/{handle}.{sha1}.woff2`（woff 另一雜湊） | 同形；sha1＝`public/fonts` 檔 SHA-1；woff 同雜湊、供給端 404（⚪ 97 §1.3） |

hoko 商品頁：89 個 `asset_url`（全部 `//hoko.vip/cdn/shop/t/2/assets/…?v=`）、`?v=` 28／29／30 位各 2／39／48 個；同主題所有資產的 `?v=` 後 10 位相同
（`1788313528`＝unix 秒），`compiled_assets` 另一時間戳（`1788313593`）⇒ **前段＝每檔摘要、後段＝該檔產生時的主題版本時間**。
供給端（curl 2026-09-05）：資產 `cache-control: public, max-age=31557600`＋`access-control-allow-origin: *`，錯 `?v=`／無 `?v=` 皆 200，
缺檔 404 `public, max-age=60`，**未發布主題以 id 亦 200**（`/cdn/shop/t/1/assets/base.css`）；字型 `public, max-age=31536000, immutable`＋CORS。

## 2. 具體功能與值域

- **主機**＝請求主機含埠（`request.host_with_port`；正式環境＝host）。本尊為店主機而非 CDN 網域（hoko 兩形並存：主題資產走店主機、平台資產部分走 cdn.shopify.com，Normalizer 對映）。
- **主題 id**＝該次渲染的主題（已發布或預覽釘選／編輯器草稿）；供給端接受租戶內**任一**主題 id（本尊同）。
- **`?v=`**：`{digest64}{updated_at.to_i}`——digest64＝MD5 前 8 位元組的無號 64 位整數（1–20 位）；主題檔寫入必 `theme.touch`（theme_file_upsert／delete 既有）⇒ 值旋轉。
  缺檔 ⇒ 無 `?v=`。`compiled_assets` 的 `?v=` 同式（E19a 原只出時間戳 10 位，本包改 29 位形）。
- **尺寸後綴**：`_{pico|icon|thumb|small|compact|medium|large|grande|original|master}` 或 `_{w}x{h}`；官方 `img_url` 表 pico 16／icon 32／thumb 50／small 100／
  compact 160／medium 240／large 480／grande 600／original＝master 1024（deprecated 頁）。
- **裸 registers**（無 theme／主機，單元 harness）⇒ 退回 `/theme-assets/{file}`（舊形，路由仍在）。

## 3. 怎樣做出來（實作落點）

| 檔 | 內容 |
|---|---|
| `app/liquid/theme_engine/asset_urls.rb` | 七種形＋`version`（Rails.cache 以 `[theme.id, updated_at, file]` 鍵）＋`digest64`＋`split_size`／`sized_name`＋尺寸表 |
| `app/liquid/theme_engine/font_files.rb` | `public/fonts/*/*.woff2` 啟動時讀成常量（SHA-1＋本體；Brakeman：不以參數組路徑） |
| `app/liquid/theme_engine/filters.rb` | 七濾鏡改走 AssetUrls；`font_face` 的兩行 src 走 `font_url`；helper `asset_host`／`stored_file_named`（private） |
| `runtime.rb`／`page_renderer.rb` | `asset_host:` kwarg；registers 加 `asset_host`／`theme`／`source`；ContentForHeader 收 `asset_host` |
| `content_for_header.rb` | `compiled_version(name)`（摘要＋版本秒，快取）；compiled src 主機改 asset_host |
| `controllers/storefront/{pages,recommendations,search,cart}_controller.rb`、`admin/storefront_preview_controller.rb` | `asset_host: request.host_with_port` |
| `controllers/storefront/assets_controller.rb` | `cdn`（任一主題 id、尺寸形回原檔、hoko 標頭）／`font`（雜湊比對）／`themes_support`／`global_asset`（404）；`THEME_ASSET_MAX_AGE` |
| `controllers/storefront/media_controller.rb` | `by_filename`（完整檔名 → 尺寸形拆解 → 尺寸表 width）；`serve` 抽出 |
| `config/routes.rb` | `cdn/shop/t/:theme_id/assets/*file`、`cdn/fonts/:family/:file`、`cdn/shop/files/:filename`、`…/themes_support/*file`、`cdn/s/global/*file` |
| `spec/requests/storefront_theme_asset_urls_spec.rb` | TA1–TA10；fixture `sections/t12-asset-probe.liquid`＋`templates/product.t12.json`；`font_pipeline_spec` F1／F3、C7 校準 |

## 4. 跨功能／跨頁／前端影響

- **整頁與片段渲染**（pages／search／recommendations／cart sections／admin 預覽）全部改出本尊形；舊 `/theme-assets/*` 路由與 `/admin/store/preview/{id}/assets/*` 路由留作相容（已快取 HTML）。
- **Normalizer**（`RenderParity`）：`CDN_ASSET_RE`／`CDN_FONT_RE`／`ASSET_VERSION_RE` 既已把兩形收斂到 `/theme-assets/`／`/fonts/`，本包不改規則；主題 id 抹除見 RP8（E19a 收尾）。
- **快取**：資產 URL 隨 `theme.updated_at` 旋轉 ⇒ 供給端可 1 年；頁級快取鍵已含 `theme.updated_at`（page_cache）。`Rails.cache` 存摘要（每主題版本每檔一次）。
- **主題編輯器預覽**（design_mode）：同形（草稿主題 id）；平台 host 上沒有 storefront `cdn/*` 路由（TenantResolver 邊界）——預覽只在租戶 host 成立（V）。
- **T5／T8／T9**：其他主題（Kalles／Minimog）的 `asset_url`／`file_url` 使用同一路徑；`shopify_asset_url` 本體（option_selection／currencies／qrcode）＝後續包自寫。

## 5. 驗證

rspec：`spec/requests/storefront_theme_asset_urls_spec.rb` TA1–TA10 綠；`font_pipeline_spec`／`shop_fonts_gap_spec`／`storefront_content_for_header_spec`／`storefront_pages_spec`／
`storefront_theme_preview_spec`／`render_parity_spec`／`e17_fetch_parity_spec` 回歸綠；閘門表見 worklog。

本機 mirror（Ella 7.2.0，`mirror.lvh.me:3000`，`Rails.cache.clear` 後 `/products/acme-tee`）：89 個 `//mirror.lvh.me:3000/cdn/shop/t/2/assets/…?v=`（hoko 同頁 89）、
`?v=` 28／29／30 位各 2／47／40（hoko 2／39／48；摘要值分布差＝演算法不同，V）、`/theme-assets/` 0 處；抽查資產／字型 woff2／compiled 皆 200，回應標頭
`cache-control: max-age=31557600, public`＋`access-control-allow-origin: *`（Rails 指令順序與 hoko 相反，語義同；91 記）；`.woff` 404（⚪ 97 §1.3）。
bt3 部署後複驗＝收尾 PR。
