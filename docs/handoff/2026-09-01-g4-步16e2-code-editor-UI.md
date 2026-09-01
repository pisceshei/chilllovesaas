# Handoff：G4 步 16e2 code editor UI（2026-09-01）

## ①我改了什麼

20 步方案步 16 第七包。base＝16e1（#259）之上，分支 `g4/step16e2-code-editor`。
CodeEditorPage＋fileLockVersion 讀面＋StorePage 入口。逐檔＝worklog Changes。

## ②為什麼這樣改

- 唯讀守衛放前端＋後端白名單雙半場：只靠後端拒收，使用者會編輯半天按存
  才炸（官方 UX 是根本不給編輯 templates JSON as file？——本尊 code editor
  其實可編輯 templates/*.json；我方因 Template 覆寫層另管才唯讀，屬架構
  差異，91 §3.72 登記）。
- textarea 先行：monaco/codemirror＝鐵律 1 未討論重依賴，先問再上。

## ③還有什麼沒解決

- 語法高亮／搜尋／Timeline（91 §3.71-72）；16e3 檔案操作；生產煙測待部署。

## ④下一個人要注意什麼

- 開檔讀 body 走 theme.files(filenames:[path])＋fileLockVersion 同 query——
  兩者都吃 OverlaySource（16e1），改 Sources 行為兩頁都要回歸。
- Cmd/Ctrl+S 是 window 級 listener——新增全域快捷鍵注意衝突。
- 本尊 code editor 可編輯 templates JSON；我方唯讀是 Template 覆寫層
  架構差異（91 §3.72）——若日後開放要走 themeTemplateUpsert 通道。
