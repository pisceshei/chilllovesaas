# Handoff：G5 步 20b webhooks UI（2026-09-01）

## ①我改了什麼

步 20 第二件。base＝main `84a8847`，分支 `g5/step20b-webhooks-ui`。
通知設定頁 Webhooks 卡＋webhookTopics 讀面。逐檔＝worklog Changes。

## ②為什麼這樣改

- topics select 走 server 讀面而非前端硬編：EXTERNAL 集合變動 UI 自動跟隨
  （與 20a fanout 掛載縫同一設計軸）。
- secret 一次性條放頁內不放 toast：toast 會自動消失，密鑰抄寫需要停留。

## ③還有什麼沒解決

- re-enable 鈕／投遞紀錄檢視（91 §3.73 軸）；生產煙測待部署。

## ④下一個人要注意什麼

- WH1 的列表斷言鎖 data-testid="webhook-list"（topic 字串在 select option
  同時出現——getByText 會撞多元素）。
- 測試檔插入用唯一文字錨；rfind 結構符號會吃掉相鄰 describe 的邊界
  （本輪實錘，worklog ⚠）。
