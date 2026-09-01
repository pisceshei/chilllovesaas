# 2026-09-01 G5 步 20b：webhooks admin UI

## 已完成的工作 (Done)

- 設定›通知頁新增 Webhooks 卡（44:447 實測：本尊 webhook 歸通知 IA）：
  訂閱列表（topic/url/status 徽章/failureCount）＋建立表單（topic select＋
  URL）＋刪除；🔴 建立後 secret 一次性顯示條（「只顯示這一次」＋我已保存
  關閉——WH1/MU-1 紅證；讀面無 secret 欄＝20a W1 introspection 釘死）。
- `webhookTopics` 讀面（＝Events::Topics::EXTERNAL——UI select 與後端白名單
  同源，W3/MU-2 紅證：resolver 退化回空即紅）。
- i18n 11 鍵 ×5；突變 2/2 殺。

## 修改的檔案與核心邏輯 (Changes)

- 改：query_type（webhookTopics）、SettingsNotificationsPage（Webhooks 卡＋
  create/delete 流）、SettingsNotificationsPage.test（4→5 例 WH1）、
  webhook_subscriptions_spec（W3 補 topics 斷言）、i18n ×5、admin.css。

## 尚未完成或需注意的風險 (Pending / TODO)

- update（re-enable）UI 未做（mutation 已在 20a；disabled 徽章顯示但無
  重啟鈕）＝91 §3.73 軸補一條；投遞紀錄檢視 UI 同軸。
- ⚠ 本輪事故（未出倉自捕）：測試 splice 用 rfind("});") 錨把第二個 describe
  的**開頭**吃掉（DETAIL 孤兒化）——測試檔插入一律用唯一文字錨，不用
  結構符號 rfind。
- 生產煙測：部署後通知設定頁看 Webhooks 卡＋topics select 有值。
