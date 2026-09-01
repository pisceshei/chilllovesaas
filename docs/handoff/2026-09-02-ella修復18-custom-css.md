# Handoff：Ella 修復 PR-18（2026-09-02）

## ①我改了什麼

section 級 Custom CSS：渲染面 scoped style 輸出（CSS 巢狀）＋編輯器面板
底部 textarea（官方位置/500 字上限）。逐檔＝worklog。

## ②為什麼這樣改

- 作用域用 CSS 巢狀而不是自寫 selector 改寫器：@media/偽類全部天然正確，
  唯一邊角（wrapper 標籤自身規則）登記 V——比半吊子 CSS parser 可靠。
- 寫入走 applyOp：undo/改即見/URL 化是既有管線的免費繼承，別另開旁路。

## ③還有什麼沒解決

- theme 級 Custom CSS（settings_data platform_customizations）；儲存型別
  官方未載＝V（渲染已 String/Array 雙收）。見 worklog Pending。

## ④下一個人要注意什麼

- custom_css 的 style 塊在 wrapper **之後**兄弟位——別搬進 wrapper 內
  （tag 可能是 self-styling 元素，內部注入會改 :first-child 之類選擇器語義）。
- 並行 PR 在同一測試檔同錨插入會 rebase 衝突（本包與 PR-17 實撞）——
  多包並行時測試插入錨盡量選各自區域尾部。
