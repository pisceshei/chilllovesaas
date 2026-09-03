# Handoff：主題編輯器 E10 Announcement bar 逐控件對照（2026-09-03）

配對 worklog：`docs/worklog/2026-09-03-主題編輯器E10-Announcement-bar.md`。規範：`docs/dev/e10-theme-editor-announcement-bar.md`。

## ① 我改了什麼

- 目標：使用者要求編輯器與本尊逐控件一模一樣，從 Announcement bar 起。輸入 ref：main `0f553370`（D81 合併後）；分支 `editor/e10-announcement-bar`。
- 做了：本尊四層控件實測與逐字（§G16）；七項差異修法（引用形解析、preset 分類、select 分段規則、單列形、Remove block 標籤、樹列截斷、
  預覽圖示工具列＋選中 chip）；規格 E13b／S4–S6／ED8／ED44b／B1／B1b；文檔四份。
- 遇到的問題：①本尊編輯器分頁在背景時側欄停在骨架（`visibilityState=hidden`），Chrome MCP 無法切分頁 ⇒ 請使用者點到前景後才能操作
  （91 §3.77 已登記）；②分段規則以「放得進容器」為條件但官方未給量法 ⇒ 以真店六例校準估寬；③ED8／ED44 fixture 的短選項 select 依規則
  變分段 ⇒ 測試改點分段鈕並改標籤避免撞名。
- 驗證：vitest 三檔全綠、bootstrap spec 27 例綠、typecheck 綠；全閘門與突變見 worklog「閘門」。

## ② 為什麼這樣改

- 引用形解析放後端而非前端 `blockDef`：後端 `block_defs_for` 已把本地定義補 name（退 type），前端無法分辨「引用」與「本地定義」；
  後端拿得到原始 schema（`bdef["name"].nil? && bdef["settings"].nil?`）才是正確判準，且樹／面板／picker 三個消費端一次收斂。
- 分段規則用估寬而非 canvas 實量：真店六例中 Top／Center／Bottom 在實量下貼近門檻（借字型差異可能翻轉），估寬對六例全部吻合且跨環境
  （jsdom）確定；登記 V。
- 被推翻的假設：本尊分段規則不是「選項數 ≤3」（Font 3 項卻是下拉），也不是字元數（Direction 18 字元卻分段）；官方三條件＋寬度才解釋得通。
- 未採：Theme Settings 收合區的靜態擴掃（section＋巢狀 block＋snippet 引用）——會列出 Instagram／YouTube 等本尊不列的項，先不動。

## ③ 還有什麼沒解決

- 91 §3.78 全部項（Theme Settings 規則、Ask for changes、Duplicate 灰化、URL 前綴、字級量測、Text 小圖示、「…」section 級）。
- 未在本機看過改後的實際畫面（demo admin 登入需憑證）⇒ 合併部署後用使用者 Chrome 在 demo 店並排複驗；CSS 單列形的視覺比例可能需微調。
- 下一輪：Announcement bar 的行為面（隱藏／拖曳／Undo／Save／預覽更新）與 Header section。

## ④ 下一個人要注意什麼

- 本尊編輯器只能在 Chrome **前景**分頁操作；分頁若被關掉要重開 `…/themes/143506604135/editor` 並請使用者點到前景。
- 對照方法：同一分頁切換本尊與 demo（`https://demo.chilling.com.hk/admin/themes/1/editor`），用 `?section=…&block=…` 直達同一 block。
- 改分段規則要同時改 `segmentFits` 與 §G16 的六例校準表；改單列型別要同步 `INLINE_TYPES`、CSS 與 e4 doc §E10。
- 不得把 Sidekick「Ask for changes」做進來（平台 AI，⚪）。
