# Handoff：引擎缺口 PR-8——`page_title` 各頁型（2026-09-03）

> 工作包＝分支 `engine/page-title-8`（自 PR-7 長出，PR-7 squash 後 `git rebase --onto origin/main <PR-7 head>`）。
> 依鐵律 21 四段。配對 worklog：`docs/worklog/2026-09-03-引擎缺口-page_title.md`。
> 本包是 `docs/handoff/2026-09-03-引擎缺口-filters.md` §④ 排定的下一批第 2 包。

## ① 我改了什麼
- `PageTitles` 字串表（en／zh）＋ PageRenderer 逐頁 assign；虛擬系列標題依語言。驗證：PT1–PT5 綠；四個突變各自轉紅；
  page_renderer／search／collections／drops_gap／conformance 回歸綠；rubocop 綠。

## ② 為什麼這樣改
- 官方只給 "The page title of the current page."，值形靠真店：先找到一家**英文**且用標準 layout 形的 Shopify 店
  （kyliecosmetics.com，`Shopify.theme` 可證）補齊英文字串，與 hoko.vip 中文形逐項對得上；allbirds 是自訂 layout，排除。
- 字串表放引擎（不放主題 locale）：這些是本尊平台字串，主題不宣告。

## ③ 還有什麼沒解決
- 其他語言／zh-Hans 未取得；搜尋計數口徑未逐字；`page_description` 另包——見 worklog Pending。

## ④ 下一個人要注意什麼
- 下一包＝系列 tag 路徑路由 `/collections/{handle}/{tag1+tag2}`（PR-6 的 link_to_*tag 已能生成連結、點進去仍 404）；
  真店可直接驗：hoko.vip 三個產品目前無 tag，要先在真店產品頁把 Tags 填上（本輪 Tags 欄輸入未成功——
  「Add tags」是 combobox，需先點 chip 再點展開的輸入框，或改用 find ref 後 `type`＋選 `Add "x"` 選項）。
- 新增頁型時在 `PageTitles.for` 補分支，否則退「資源標題／店名」。
