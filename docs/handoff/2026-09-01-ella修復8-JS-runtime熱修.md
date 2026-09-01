# Handoff：Ella 修復 PR-8（2026-09-01）

## ①我改了什麼

對表艦隊 js-runtime 軸五格。分支 `ella/js-runtime-hotfix`（base=main #270 後）。
逐檔＝worklog Changes。

## ②為什麼這樣改

- 全域 settings 缺 defaults 是「整站 no-js」的單點根因——與 section/block
  同款三層是本尊語義（schema_defaults 已有現成函式）。
- heredoc 內 JS 正則一律四反斜線；驗證看「輸出 HTML 裡是單反斜線」。

## ③還有什麼沒解決

- PR-9 srcset／PR-10 password+layout／PR-11 編輯器 live 五格（艦隊 findings
  全存 wf_4fdcbcc5-7ba journal）。

## ④下一個人要注意什麼

- 反斜線類突變用程式化構造 needle（repr 打印核對），字面錨層數必錯。
- header 高 0 非 bug＝Ella 透明頁首（header-component absolute 疊 hero）。
