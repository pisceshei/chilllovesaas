# Handoff：引擎缺口 PR-4——drops 缺屬性＋`/collections/vendors|types`（2026-09-02）

> 工作包＝分支 `engine/drops-gap-4`（自 PR-3 長出，PR-3 squash 後 `git rebase --onto origin/main <PR-3 head>`）。
> 依鐵律 21 四段。配對 worklog：`docs/worklog/2026-09-02-引擎缺口-drops缺屬性與vendors路由.md`。
> 本包是 `docs/handoff/2026-09-02-主題無關conformance與真店切換.md` §④E 排定的第 4 包。

## ① 我改了什麼
- Collection／Blog／Page／Article／Product drops 依官方 objects 頁補屬性（逐字引句在各方法註釋）；
  `/collections/vendors?q=`／`/collections/types?q=` 虛擬系列路由；`url_for_type`＋vendor／type 連結改
  percent-encoding。驗證：G1–G5 綠；五個突變各自轉紅；blog／collections／conformance 回歸綠；rubocop 綠。

## ② 為什麼這樣改
- 三套主題用量（`grep -rhoE "collection\.(featured_image|metafields|image)|page\.metafields|blog\.(next|previous)_article|product\.created_at" test/fixtures/themes/*`）
  集中在 featured_image／metafields／next-previous／created_at，這些在原實作全部計 miss 回 nil。
- 圖欄不存在的屬性（collection.image／article.image）選擇「宣告為 nil」而不是造假圖：主題用
  `{% if article.image %}` 守，nil 走正確分支；假圖會讓每篇文章長出佔位圖。
- 被推翻的假設：「url_for_vendor 用 `+` 編空白即可」——官方例逐字是 `%20`。

## ③ 還有什麼沒解決
- 無 `q` 的 vendors／types 頁官方形、sort_options 名稱的語言表、圖欄缺席、blog 列表頁的 next／previous——見 worklog Pending。
- 真店 Publish／金標本仍待（分頁不可見時截圖逾時；hoko.vip 零商品待裁定）。

## ④ 下一個人要注意什麼
- 下一包＝§④E 第 5 包（Shop 欄位 `money_with_currency_format／description／features`＋font_library 補家族）。
- `VirtualAllCollection` 的位置成員以 `drops.rb` 的 Struct 定義為準（末兩個＝vendor／product_type）；新增呼叫
  一律補齊全部位置參數（漏一個就整組位移）。
- `CollectionDrop` 的 relation helper 依賴 `@publication`；片段／editor 語境（無 publication）一律回空陣列，不要在那裡補 fallback 查全店。
