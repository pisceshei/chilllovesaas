# 2026-09-02 Ella 修復 PR-21：search facets（搜尋頁篩選器）

## 已完成的工作 (Done)

- 91 §3.61 的搜尋面收口——**同一 Facets 服務**（PR-20 handoff ④ 預告形）：
  - SearchDrop#filters：performed ∧ 有 publication ∧ 有 `_facets_qs` 語境
    ⇒ Facets（base＝`Storefront::SearchQuery.products` 商品結果集合，
    path＝/search）；其餘照舊 []。
  - SearchResultsDrop：product_relation 套 facets；🔴 filter 啟用時
    **非商品結果全濾除**（官方 support-storefront-filtering 逐字
    "all non-product results are filtered out"，取證 2026-09-02）——
    types 交集到 product。
  - `_facets_qs` 保留鍵擴 `q`/`type`（搜尋 URL 重建不丟語境；collection
    頁不受影響——該兩鍵不出現）。
- fixture main-search 加 facets 斷言塊。
- 測試 FS1（商品被過濾／非商品濾除官方語義／URL 保 q）；突變 1/1 殺
  （拔 types 交集 ⇒ page 結果在 filter 下殘留）。
- 🔴 測試坑：fixture paginate by 2 ⇒ 混型結果在第 2 頁——未過濾斷言
  帶 page=2 取（首輪紅的原因，不是實作錯）。

## 修改的檔案與核心邏輯 (Changes)

- `drops.rb`：SearchDrop facets／SearchResultsDrop facets＋types 交集。
- `pages_controller.rb`：facets_query_string 保留鍵擴 q/type。
- fixture main-search.liquid＋storefront_facets_spec（FS1）。

## 尚未完成或需注意的風險 (Pending / TODO)

- 搜尋頁不進頁快取（12b 既有）⇒ 本包無快取鍵新風險；`_facets_qs` 對
  搜尋只作參數傳遞通道。
- 配置面／5000·1000 上限／param V＝與 PR-20 同批登記，未變。
