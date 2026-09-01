# G6 步 7：棄單挽回

> 正典：`docs/research/89-notifications-teardown.md` §6（官方判定與抑制）＋§8
> （admin 面實測）。通知鏈＝步 6（`docs/dev/g6-notifications.md`）。

## 1. 判定與標記

- 官方逐字（89 §6）：棄單＝提供 email 後逾 **10 分鐘**未完成。閾值落
  `config/limits.yml` `checkout.abandoned_after_minutes`（鐵律 6）。
- `Checkouts::MarkAbandonedJob`（recurring 每 5 分鐘）：status=open ∧ email 非空 ∧
  `updated_at` 逾閾值 ∧ 未標 ⇒ 集合式 UPDATE 標 `abandoned_at`。
  「最後活動」以 updated_at 近似（ours；官方內部欄未公開）。

## 2. 挽回連結

- `Notifications::RecoveryUrl`：`https://<host>/checkouts/recover/<recovery_token>`
  （本尊 URL 形不同——89 §8；我方單段 token）。
- 端點 `GET /checkouts/recover/:recovery_token`（🔴 路由必在 `checkouts/:token`
  **之前**，否則 "recover" 被 :token 段吃掉）：未成單 ⇒ 302 回結帳頁（快照還原＝
  checkout 本就落庫）；已成單 ⇒ 302 到 thank-you；查無 ⇒ 404。

## 3. 寄送

- `abandonedCheckoutSendRecovery(id)`：前置＝已標棄單 ∧ email 非空 ∧ 未成單
  （三格都有突變紅證）⇒ `Notifications::DeliverJob`（kind=abandoned_checkout）
  ⇒ 寄出後回填 `checkouts.recovery_email_sent_at`（列表 Email status 唯一寫入者）。
- 自動排程寄送（本尊 Messaging automation 的 Send after）＝⚪ 後置。

## 4. 讀面與 UI

- `abandonedCheckouts` keyset connection（`abandoned_at` desc；KeysetCursor 新登記
  該鍵）；AbandonedCheckoutType 對位官方 `abandonedCheckoutUrl` 命名。
- `/admin/orders/abandoned`（nav 樹既有佔位轉正）：89 §8 七欄＋每列寄送鈕
  （recovered/無 email ⇒ disabled）。詳情頁 ⚪ 後置。
- recovered v1＝orders.checkout_id 存在（不追連結歸因；91 §3.51）。

## 5. 測試映射（20.2⑤）

`mark_abandoned_job_spec`（A1 閾值／A2 email 前置／A3 冪等）＋
`storefront_abandoned_recovery_spec`（R1 路由序／R2 成單分流／R3 404）＋
`abandoned_checkouts_spec`（Q1 欄位形／Q2 判定前置／Q3 成單擋寄／Q4 端到端＋回填）
＋FE 3 例。突變輪 MA1–MA7 全紅＋canary。
