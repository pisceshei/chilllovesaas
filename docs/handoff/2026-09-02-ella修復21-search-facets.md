# Handoff：Ella 修復 PR-21（2026-09-02）

## ①我改了什麼

搜尋頁 facets：SearchDrop 接同一 Facets、filter 啟用時非商品結果全濾除
（官方逐字）、`_facets_qs` 保 q/type。逐檔＝worklog。

## ②為什麼這樣改

- 不寫第二份 faceting：PR-20 handoff 的紅線——base relation 換成搜尋商品
  集合即可，counts/URL/多值全繼承。
- types 交集做在 SearchResultsDrop 構造：分頁偏移計算全鏈（products→
  pages→articles 串接）自動正確，比在 drops 渲染層擋乾淨。

## ③還有什麼沒解決

- 與 PR-20 同批的 V／配置面。見 worklog Pending。

## ④下一個人要注意什麼

- 🔴 fixture main-search paginate by 2——混型斷言記得 page=2（本包首輪
  紅過）。
- `_facets_qs` 的保留鍵集合現在是 sort_by/q/type＋filter.*——再擴鍵前想
  一下 collection 頁快取 key 空間（q/type 不出現在 collection ⇒ 本次零
  影響，新鍵未必）。
