# m2 — 主題引擎生產化（包 30／D77）

> 消費入口：`ThemeEngine::PageRenderer`（整頁）／`ThemeEngine::Runtime`（section 級）。
> 沿革：`poc/liquid-engine/`（Ella 三渲染目標實證）→ 本包移植；PoC 保留不動作歷史對照。

## §1 這是什麼（12.4 ①）

Liquid 相容前台引擎的生產骨架：`liquid` gem 5.13（MIT）＋自實作平台層
（tags 11 支／filters ~70 支／drops ~25 類）＋五個資料模型（Theme／Template／
ThemeSetting／Page／Menu＋MenuItem，表為 M0 既建）＋登入後預覽端點＋
`/admin/store` 主題清單頁＋`CacheStampBumper` 消費者。

## §2 具體功能（12.4 ②）

- **檔案來源**：`themes` 列不存 Liquid 檔（M0 表註「主題是資料」）。
  `ThemeEngine::Sources.resolve(theme)`：`Rails.root/themes/<key>`（第一方）→
  `test/fixtures/themes/<key>`（🔴 僅 dev/test；Ella 授權邊界＝鐵律 9）。
  key＝`name.parameterize-version`（ella-7.2.0）。解析不到＝nil，發布被
  `SOURCE_MISSING` 擋（fail-closed）。
- **DB 覆寫讀取序**：templates row → `templates/<key>.json`；theme_settings row →
  `config/settings_data.json.current`。編輯器（後續包）寫 DB 側。
- **單一發布**：`themes.published_slot` 產生欄＋唯一索引（DB 保證）；
  `Theme#publish!` 先降現任再升目標（順序＝fail-closed 選擇，見模型註）。
- **預覽**：`GET /admin/store/preview/:theme_id(/*path)`——staff session＋
  `X-Robots-Tag: noindex, nofollow`；可見性走 `Storefront::Lookup`
  （🔴 與本尊預覽站「商家視角」刻意不同：我方預覽所見＝買家將見）。
- **路由值域（v1）**：`/`＝index；`/products/:handle`；`/collections/:handle`；
  `/pages/:handle`；其餘＝404 template。
- **GraphQL**：`themes` query（published 前）＋`themePublish`（本尊逐字
  `Publishes a theme.`；錯誤碼 NOT_FOUND／SOURCE_MISSING=ours）。
- **快取失效**：內部 topic `product.updated`／`product.variant.updated`
  （SaveProduct 同交易發）→ `Catalog::CacheStampBumper` → 所在系列
  `products_updated_at`。成員變動 bump 的主人仍是 `Collections::Rebuild`。

## §3 怎樣做出來的（12.4 ③）

- Environment 常數化（tags/filters 註冊一次；resource limits 引
  `limits.theme_engine.*` 三鍵）。
- AST cache＝process 級 mutex hash，鍵=[source key, rel]，上限 1000 清空。
  🔴 偏離 25 §6「Solid Cache」：`Liquid::Template` AST 非可靠序列化物。
- 🔴 **第四個反例（本包新抓）**：assigns 必須走 `Liquid::Context.build(static_environments:)`
  ——`{% render %}` 隔離子 context 只帶 static env＋registers，普通 assigns 在
  snippet 內消失（實測 `{{ shop }}` 輸出空）。PoC 用普通 assigns。
- 單檔 SyntaxError → `@errors`＋跳過該 section，不炸整頁（Ella 實測
  `{% render block %}` 動態名＝本尊平台擴充、gem 不收）。
- Zeitwerk 例外：drops.rb 多類單檔 ⇒ initializer ignore＋to_prepare require。

## §4 跨功能影響（12.4 ④）

- **前置消費**：`Storefront::Lookup`（S9/#195）、`Product.purchasable`（第 12 包）、
  `collection_memberships`（第 11 包）、`CacheStamps`（第 3 包）。
- **下游**：包 32（markets → LocalizationDrop 真值）、包 33（帶前綴路由＝
  RoutesDrop prefix 參數的真值來源；頁級快取）、包 34（locale 鏈＋money 格式）、
  M2 編輯器（templates／theme_settings 的寫入端）。
- **事件**：topics.rb ③的兩個留位結清；`event_deliveries` 出現新 consumer 名
  `catalog.cache_stamp_bumper`（改名＝重放，鐵律同 relay 契約）。

## §5 測試錨

`spec/liquid/page_renderer_spec.rb`（E1–E9 含 Ella 冒煙）／
`spec/requests/theme_preview_spec.rb`（P1–P4）／
`spec/services/catalog/cache_stamp_bumper_spec.rb`（B1–B3）／
`StorePage.test.tsx`（T1–T3）。突變 M1–M6＋M4b 全部實跑轉紅（worklog 有表）。
