# D81 店級貨幣格式（`shop.money_format`／`shop.money_with_currency_format`）

> 使用者裁定（2026-09-03，`docs/DECISIONS.md` D81）：「貨幣顯示格式樣格跟隨 shopify 本尊。」
> 本檔＝該裁定的實作規範；證據逐字在 `docs/dev/external-facts.md` §G15；範圍外與未取得登記 `docs/specs/91-pit-register.md` §3.77。

## §0 範圍與非範圍

- 範圍：買家前台與 live preview 的所有 `money*` 過濾器輸出、`shop.money_format`／`shop.money_with_currency_format`
  兩個 Liquid 屬性（Ella JS `window.money_format` 的來源）、通知信金額、鏡像店對齊、新店種子、既有店回填。
- 非範圍（登記 §5）：admin 設定 UI（本尊 Settings › General › Change currency formatting 對話框）、Admin GraphQL
  `shop.currencyFormats`、Email 專用兩欄、admin 後台自己的金額顯示（仍走前端 locale 格式器，鐵律 10）。

## §1 這是什麼（本尊形）

- **入口**：Settings › General › Store defaults › 幣別列的「⋯」› **Change currency formatting**。對話框說明逐字：
  "Change how currencies are displayed on your store. {{amount}} and {{amount_no_decimals}} will be replaced with the price of your product."
- **四欄**：HTML with currency／HTML without currency（線上商店）、Email with currency／Email without currency（通知與 order printer）。
- **值域**：任意文字（含 HTML）＋官方八個佔位符（例值 1,134.65）：

  | 佔位符 | 輸出 | 千分位 | 小數 |
  |---|---|---|---|
  | `{{amount}}` | `1,134.65` | `,` | `.` |
  | `{{amount_no_decimals}}` | `1,135` | `,` | 無（rounded） |
  | `{{amount_with_comma_separator}}` | `1.134,65` | `.` | `,` |
  | `{{amount_no_decimals_with_comma_separator}}` | `1.135` | `.` | 無 |
  | `{{amount_with_apostrophe_separator}}` | `1'134.65` | `'` | `.` |
  | `{{amount_no_decimals_with_space_separator}}` | `1 135` | 空白 | 無 |
  | `{{amount_with_space_separator}}` | `1 134,65` | 空白 | `,` |
  | `{{amount_with_period_and_space_separator}}` | `1 134.65` | 空白 | `.` |

- **預設**：官方逐字只公開「BIF、CLP、DJF、GNF、ISK、JPY、KMF、KRW、PYG、RWF、UGX、UYI、VND、VUV、XAF、XOF、XPF 預設
  `amount_no_decimals`」；各幣別符號表未公開。真店 pnrjnw-sy（HKD，店主未改）實讀：HTML with `HK${{amount}} HKD`、
  HTML without `${{amount}}`、Email 兩欄同值。前台印證：商品卡 `$19.99`、購物車抽屜總額 `HK$0.00 HKD`、
  `window.money_format = "${{amount}}"`、商品頁 `og:price:amount` `188.00`。
- **只作用於店基準幣別**（官方逐字 "Currency formatting settings only apply to your store's base currency."）；
  Markets 多幣別顯示另有機制（不在本包）。

## §2 我方實作

| 層 | 落點 | 內容 |
|---|---|---|
| schema | `db/migrate/20260903140000_add_money_formats_to_shops.rb` | `shops.money_format`／`money_with_currency_format`（string 255、NOT NULL、DB 預設 `{{amount}}` 只作安全網）；回填 SQL 與 Ruby 種子表同源 |
| 種子 | `app/models/shop/money_format_defaults.rb` | HKD＝真店四值；官方 no-decimals 17 幣別 ⇒ `CODE {{amount_no_decimals}}`／`{{amount_no_decimals}} CODE`；其餘 `CODE {{amount}}`／`{{amount}} CODE`（V） |
| model | `app/models/shop.rb` | `before_validation :seed_money_formats, on: :create`（呼叫端明給者不覆寫）；presence／length 驗證 |
| 引擎 | `app/liquid/theme_engine/money_format.rb` | `render(cents, pattern)`（佔位符替換、未知佔位符原樣）、`amount_only`（第一個佔位符的分隔風格）、`strip_trailing_zeros`、`coerce`（整數算術，不經 float） |
| registers | `Runtime#base_registers`、`Notifications::Renderer#render_one` | `money_format`／`money_with_currency_format`／`currency` 三鍵；舊 `money_symbol` 與三處 `{ "HKD" => "HK$" }` 表全部移除 |
| filters | `app/liquid/theme_engine/filters.rb` | `money`＝HTML without；`money_with_currency`＝HTML with；`money_without_currency`＝只出數字（沿用第一個佔位符風格）；`money_without_trailing_zeros`＝HTML without 去「分隔符＋00」；nil／空字串 ⇒ 空；registers 缺席 ⇒ 官方例 `${{amount}}`；`unit_price_with_measurement` 走 `money` |
| drops | `ShopDrop#money_format`／`#money_with_currency_format` | 兩欄直出；`permanent_domain`／`domain` 改 `{subdomain}.{base_host}`（先前硬編 `chilllove.example`） |
| 鏡像店 | `RenderParity::Mirror#ensure_shop`、`spec/fixtures/render_parity/hoko.json` | 快照帶兩鍵；缺鍵 ⇒ 該幣別種子 |

## §3 值域與邊界（我方契約；證據欄「官方」＝逐字例、「真店」＝實讀、「V」＝未取得）

| 輸入（cents／格式） | 輸出 | 證據 |
|---|---|---|
| 113465／八佔位符 | 官方例值逐一 | 官方（§G15） |
| 1000／`${{amount}}` | `$10.00` | 官方 filters/money |
| 1000／with `${{amount}} CAD` | `$10.00 CAD` | 官方 |
| 1000／`money_without_currency` | `10.00` | 官方；真店 `188.00` |
| 1000／`money_without_trailing_zeros` | `$10` | 官方 |
| 1999／真店 HTML without | `$19.99` | 真店商品卡 |
| 0／真店 HTML with | `HK$0.00 HKD` | 真店購物車抽屜 |
| nil／`""` | `""` | hoko 佔位商品卡 `<s …> </s>`（E8 RF16）；官方未逐字 |
| `{{ amount }}`（大括號內空白） | 同 `{{amount}}` | 官方 help 頁形 |
| 未知佔位符 `{{amount_x}}` | 原樣保留 | V |
| 148050／`money_without_trailing_zeros` | `€1.480,50`（非全零不去） | V（官方只例 10.00 ⇒ 10） |
| -1050／`${{amount}}` | `$-10.50`（負號在數字前） | V |
| `"1000"`／`1000.4`／`"abc"` | `$10.00`／`$10.00`／`$0.00` | V |
| 113450／`{{amount_no_decimals}}` | `1,135`（半數進位） | V（官方例只證 .65 進位） |

## §4 跨功能／跨頁／前端影響

- **前台所有價格**：商品卡、商品頁、購物車抽屜、結帳前摘要、搜尋結果、集合頁——同一 registers 來源，改店級兩欄即全站生效。
- **Ella JS 動態價格**：`snippets/global-script.liquid` 依 `settings.currency_format_enable` 把 `shop.money_with_currency_format`
  或 `shop.money_format` 塞進 `window.money_format`，前端 `formatMoney` 自己替換佔位符 ⇒ 兩欄字串必須是本尊形（不可預先格式化）。
- **通知信**：`Notifications::Renderer` 走同一 registers；本尊 Email 兩欄我方尚未分欄（§5）。
- **鏡像店／對表**：hoko 快照帶兩鍵；E8 §3「金額格式」差異項自本包起收口，`Report` 不再需要對 `$`／`HK$` 做任何抹除。
- **admin 後台**：不受影響——admin 金額顯示走前端 locale 格式器（鐵律 10），與前台的店級格式是兩件事（本尊亦如此：admin 顯示
  `HK$` 而前台顯示 `$`）。
- **既有店**：migration 回填 ⇒ demo／mirror（HKD）自本包起前台顯示 `$1,480.00`（先前 `HK$1,480.00`）。
- **DECISIONS**：D81 落地；鐵律 10 的 `HK$1,480` 例只約束 admin 顯示與 tabular-nums，不再是前台預設。

## §5 未取得／範圍外（91 §3.77）

1. 各幣別預設符號表（官方未公開）⇒ 非 HKD 新店用通用形，商家可改。
2. `amount_no_decimals` 恰 .50 的捨入模式、負值形、非整數／非數字輸入、`money_without_trailing_zeros` 對非全零小數。
   探針方案＝副本主題 Custom Liquid；本輪因本尊編輯器分頁在背景（`visibilityState=hidden`）側欄不載入而未執行。
3. Email with／without currency 兩欄（我方共用 HTML 兩欄）。
4. 設定 UI（Settings › General 對話框）與 Admin GraphQL `shop.currencyFormats`（ShopType 守則：無消費端不開欄）。
5. Markets 多幣別的顯示格式（官方：本設定只作用於基準幣別）。

## §6 驗收清單

- `spec/liquid/money_format_spec.rb` MF1–MF10（八佔位符、空白容忍、過濾器族官方例、真店形、without_currency 風格、
  輸入強制與大數、種子表、SQL 與 Ruby 集合同源、新店種子、ShopDrop 直出與 permanent_domain）。
- 既有規格改值：`page_renderer_spec` E1／E2、`storefront_seo_spec`、`theme_js_runtime_spec` JS3、`shop_fonts_gap_spec` H1、
  `notifications/renderer_spec` N4、`delivery_chain_spec`。
- 突變（scratchpad `mutate_d81.py`，commit 後跑）：M95 佔位符表少一鍵、M96 `amount_only` 改用整串、M97 種子表 HKD 改回
  `HK${{amount}}`、M98 registers 缺 money_format 時退 `HK$`、M99 migration 清單少一幣別、M100 `permanent_domain` 硬編回 example。

## §7 對表結果

見 worklog `docs/worklog/2026-09-03-店級貨幣格式D81.md` §Done（本機 mirror vs hoko.vip 首頁與公開鏡像店的段數）。
