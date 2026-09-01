# Handoff：Ella 修復 PR-25（2026-09-02）

## ①我改了什麼

.liquid 替代模板（?view=）渲染＋{% layout %} tag 三態真語義（none／
具名／預設）。逐檔＝worklog。

## ②為什麼這樣改

- Ajax 側車是 Ella 核心 UX 的資料源——view 片段拿到整頁＝抽屜壞掉的根因
  之一（另一半是 JS；片段對了 JS 才有得談）。
- layout override 經 registers 掛 carrier：Liquid 5 Registers 的 []= 走
  overlay，外層 hash 讀不回——這是通則陷阱，任何「tag 要回傳資訊給
  renderer」的需求都走預掛 carrier。

## ③還有什麼沒解決

- 老主題基底 .liquid 模板；gift_card 路由；生產 view 片段煙測。
  見 worklog Pending。

## ④下一個人要注意什麼

- 🔴 tag→renderer 回傳一律 carrier hash（registers 預掛），別再試
  `context.registers[:x] =` 然後外層讀——靜默拿到 nil。
- render_named_layout 缺檔回落預設 theme.liquid（fail-open 到「有 layout」
  側）——官方缺檔行為未取證（V），改 fail-closed 前先取證。
