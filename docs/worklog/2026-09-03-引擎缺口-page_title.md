# 2026-09-03 引擎缺口 PR-8：`page_title` 各頁型

分支 `engine/page-title-8`（自 PR-7 分支長出，PR-7 合併後 rebase 到 main）。配對 handoff：
`docs/handoff/2026-09-03-引擎缺口-page_title.md`。收口 hoko 稽核候選「`page_title` 在 collection／cart 頁用店名」。

## 已完成的工作 (Done)
- 證據（2026-09-03 逐字，兩店主題 layout 皆 `{{ page_title }} &ndash; {{ shop.name }}` 形）：
  英文店 kyliecosmetics.com——`/cart`＝Your Shopping Cart、`/search`＝Search、`/search?q=tee`＝
  `Search: 0 results found for "tee"`、404＝404 Not Found、`/collections`＝Collections、`/collections/all`＝Products、
  `/blogs/news`＝部落格標題；中文店 hoko.vip——首頁＝店名（不接 &ndash;）、`/cart`＝您的購物車、`/search`＝搜索、
  `/search?q=tee`＝搜尋：找到「tee」的結果，共 0 筆、404＝404 找不到、`/collections`＝产品系列（繁體店逐字出簡體字）、
  `/collections/all`＝商品、系列／商品／vendors／types 頁＝資源標題或 q。allbirds.com 為自訂 layout（Search - Allbirds），不採。
- `ThemeEngine::PageTitles`（新檔）：en／zh 字串表＋`for(page_type:, assigns:, status:, shop:, locale:)`；
  `PageRenderer#render_inside_tenant` 逐頁 assign `page_title`；虛擬 all／vendors／types 系列標題依語言（Products／商品）。
- spec `spec/requests/storefront_page_title_spec.rb` PT1–PT5（PT5 以 `locale: "zh-Hant"` 直打 PageRenderer）。
- 突變輪：M1 恆店名 ⇒ PT1／PT2／PT3／PT4／PT5 紅；M2 搜尋計數寫死 0 ⇒ PT3／PT5 紅；M3 拔 zh 表 ⇒ PT5 紅；
  M4 虛擬 all 標題寫死 Products ⇒ PT5 紅。
- 回歸：`bundle exec rspec spec/requests/storefront_page_title_spec.rb spec/liquid/page_renderer_spec.rb
  spec/requests/storefront_search_spec.rb spec/requests/storefront_collections_spec.rb
  spec/requests/storefront_drops_gap_spec.rb spec/liquid/theme_conformance_spec.rb` 綠。

## 修改的檔案與核心邏輯 (Changes)
- `app/liquid/theme_engine/page_titles.rb`：新檔（STRINGS 表、`strings`、`products_title`、`for`）。
- `app/liquid/theme_engine/page_renderer.rb`：`render_inside_tenant` assign `page_title`；`/collections/all` 與
  vendors／types 虛擬系列的標題改 `PageTitles.products_title(@locale)`。
- `spec/requests/storefront_page_title_spec.rb`：新檔。

## 尚未完成或需注意的風險 (Pending / TODO)
- 字串表只有 en／zh（zh 取自繁體店 hoko；zh-Hans 店的形＝未取得，同用 zh 表）；其他語言退英文（未取得）。
- 搜尋計數用 `search.results_count`（全類型合計）；本尊計數口徑（是否含 article／page）＝未逐字取得，
  兩店例皆 0／1 筆無法分辨。
- `page_description` 未動（官方＝資源 meta description；另包）。
- SRA／片段渲染路徑不 assign page_title（片段不出 `<title>`）。
