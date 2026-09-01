# 2026-09-01 Ella 修復 PR-3：window.Shopify＋section 資產聚合＋coverage 批

## 已完成的工作 (Done)

- **window.Shopify bootstrap**（`ThemeEngine::ShopifyGlobal`，`</head>` 前注入）：
  Ella 依賴面 grep 取證逐項供齊——designMode（官方文檔明載的偵測介面）／
  formatMoney／routes.root（帶語言前綴）／currency.active／theme{id,name,role}
  ／CountryProvinceSelector＋setSelectorByValue＋bind＋addListener（地址表單
  國家-省聯動）／getCart/removeItem/onCartUpdate（cart ajax 舊面）／postLink
  ／loadFeatures/PaymentButton/ModelViewerUI（安全 stub）。缺它＝
  「Shopify is not defined」連鎖崩（本地 console 實錘：promotion-popup/
  before-you-leave/predictive-search 全滅）。SG1/MG1 紅證。
- **{% javascript %}/{% stylesheet %} 聚合**（先前整塊吞掉——coverage 軸點名
  商品頁 tabs 等互動 JS 遺失）：SectionAssetTag 收集 → Runtime 聚合桶
  （Set 去重＝同型 section 多實例一份）→ PageRenderer 頁尾輸出。
  SG2/MG2/MG3 紅證（收集斷線與去重退化都殺）。
- coverage 批：color_modify **alpha** 分支（rgba 輸出——overlay 漸層關鍵，
  SG3/MG4 紅證；其餘鍵原樣登記）；time_tag 接 format；item_count_for_variant
  由 cart items 加總（SG4）。
- {% schema %} 的 Swallow 保險網保留（改名波及實錘一次，spec 抓回）。

## 修改的檔案與核心邏輯 (Changes)

- 新：shopify_global.rb、theme_shopify_global_spec.rb（SG1-4）。
- 改：page_renderer（head 注入＋頁尾聚合＋root_prefix_path）、tags
  （SectionAssetTag＋Swallow 並存）、runtime（collect/aggregated）、
  filters（color_modify/time_tag/item_count_for_variant）。

## 尚未完成或需注意的風險 (Pending / TODO)

- window.Shopify 形＝ours（本尊無公開文檔；以 Ella 用法收斂）；formatMoney
  未接店家 money format 模式（v1 千分位＋兩位小數）。
- coverage 軸餘項：pages/images 全域、vendors、video/3D 媒體、
  powered_by_link/current_page/page_image、collection.filters——隨後續包。
- 生產煙測：部署後 console 零「Shopify is not defined」＋預測搜尋/抽屜可動。
