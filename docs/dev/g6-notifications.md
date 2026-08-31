# G6 步 6：通知基座（mailer＋模板）

> 對位正典：`docs/research/89-notifications-teardown.md`（實測＋官方雙源）。
> 消費者：步 7 棄單挽回（abandoned_checkout 模板＋Payloads 已備）、步 8 顧客邀請、
> 步 11 OTP、步 18 dunning——全部走同一 overlay＋Renderer＋DeliverJob 鏈。

## 1. 架構（事件 → 信）

```
orders/create ─┐（outbox）
               ├→ Events::Consumers → Notifications::*Consumer → DeliverJob（Solid Queue）
order.fulfilled┘        │                                            │
                        └ notify=false ⇒ 不入列                        └→ NotificationMailer.notify
                                                                        ├ Renderer（overlay→預設）
                                                                        └ SMTP／test 收件匣
```

- 鐵律 5：寄送全程在交易外（outbox → job → mailer）。
- 冪等誠實登記：at-least-once ⇒ 極端情況同一封信可能寄兩次（DeliverJob 檔頭②；
  郵件業界通行取捨，v1 不建 per-mail 冪等表）。

## 2. 模板層（M0 表採用）

- 🔴 表＝**M0 core schema 既有 `notification_templates`**（key／name／channel／subject／
  body／enabled；uq [shop_id, channel, key]）——步 6 是第一個消費者，不建平行表。
  首版 migration 曾帶 table_exists? 守衛的 create_table（被 M0 表跳過），dead code
  已移除（worklog 記事故）。
- overlay 語義（89 §7.3）：無列＝平台預設（`config/notification_templates/*.liquid`
  ＋ `Notifications::Catalog` 的 default_subject）；revertToDefault ⇒ 刪列。
- v1 三 key：`order_confirmation`／`shipping_confirmation`／`abandoned_checkout`
  （對位本尊 email_templates URL key；89 §3）。

## 3. 渲染契約（89 §5 官方變數）

- 🔴 **order 屬性攤平**（官方逐字：模板內用 `{{ name }}` 不用 `{{ order.name }}`）；
  fulfillment 帶前綴（`fulfillment.tracking_numbers` 等）；棄單恢復連結＝裸 `{{ url }}`。
- 金額值＝integer cents，模板經 `money` filter（ThemeEngine::Filters 同一模組註冊）。
- `order_status_url`＝thank-you 頁（`/checkouts/:token/complete`）——我方尚無獨立
  order status 頁（ours 簡化，89 §7）。

## 4. GraphQL 與 UI

- query `notificationTemplates`（合併視圖＋isDefault）＋`notificationSenderEmail`；
  mutation `notificationTemplateUpdate(key, subject, bodyLiquid, revertToDefault)`
  （Liquid strict parse 儲存閘＝INVALID）＋`notificationSenderEmailUpdate`（空字串清空）。
- admin：`/admin/settings/notifications`（sender email＋三列）＋
  `/admin/settings/notifications/:kind`（兩欄編輯＋Revert，預設態 disabled——89 §1 形）。
- 官方無模板 API（89 §6 陰性搜索）⇒ 本 API 是 ours 加嚴；ML 線對位點＝
  TranslatableResourceType `EMAIL_TEMPLATE`（title/body_html）。

## 5. 寄送環境

- production：`SMTP_ADDRESS`（＋PORT/USER_NAME/PASSWORD）從 /etc/chilllove/env 注入
  ⇒ :smtp；**未設 ⇒ perform_deliveries=false**（demo 紅線「不對外發信」；啟動 log
  一行明文降級）。test env＝:test 收件匣。
- From＝`shops.sender_email`，未設定 ⇒ `no-reply@<base_host>`。

## 6. 測試映射（20.2⑤）

`renderer_spec`（N1 攤平／N3 overlay／N4 money／shipping·abandoned payload 形）＋
`delivery_chain_spec`（D1 registry／D2 notify 閘／D4 端到端收件匣／D5 空 email）＋
`notification_settings_spec`（G3 語法閘／G4 revert／sender email 三態）＋FE 4 例。
突變輪 M1–M7 全紅＋canary（worklog 記逐格）。
