# Handoff：Ella 修復 PR-19（2026-09-02）

## ①我改了什麼

theme 級 Custom CSS（platform_customizations 對位＋head style＋佈景面板
輸入）＋picker 搜尋框。逐檔＝worklog。

## ②為什麼這樣改

- platform_customizations 收在 ThemeSetting.settings 內但初始化即抽離：
  零 schema 變更拿到官方「settings_data 兄弟物件」語義，代價是「這個鍵
  永遠不是 setting id」的不變量——TCC1 釘死。
- 前端寫入走 setThemeSetting：dirty/儲存/改即見全繼承，零新管線。

## ③還有什麼沒解決

- picker 分類與 tabs／hover 預覽；後端長度驗證；見 worklog Pending。

## ④下一個人要注意什麼

- 🔴 佈景設定 schema 若日後出現 id 恰為 `platform_customizations` 的
  setting（不應該，但主題是第三方輸入）——值會被抽走。加主題匯入驗證時
  把這個鍵列保留字。
- theme 級 style 在 head 尾、section 級在各 wrapper 後——兩個 data- 屬性
  名不同（-theme 尾碼），測試選擇器別混用。
