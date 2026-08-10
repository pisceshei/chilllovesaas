# 16 — 功能規格：訂單管理、出貨、退款、顧客（生產級）

> 覆蓋功能：訂單列表/詳情、timeline、出貨、取消/封存、退款、匯出、顧客管理。規格對照研究 01/06，基線見 11。

## F1. 訂單列表與詳情（後台）

**生產級做法**：
1. 列表：keyset 分頁（11 §4）、tabs = saved views（`saved_views` 表：staff、resource、filters JSON、sort）、雙狀態 badge（financial/fulfillment 各自推導值）、bulk 動作走 job（>50 筆時背景處理 + 進度回報）。
2. 詳情：資料聚合一支 query 物件（`Orders::DetailQuery`）preload 全關聯，頁面 0 額外查詢；金額區塊全部來自訂單快照欄位（不重算）。
3. 併發編輯保護：訂單詳情操作（fulfill/refund/cancel）都是狀態條件轉移（`WHERE status = ?` 的 UPDATE），兩個 staff 同時操作時後者收到「狀態已變更，請重新整理」。
4. 搜尋：單號精確 + email/姓名 FULLTEXT（13-F4 同技術）。

**⚠️ 坑**：列表的 badge 若即時推導（JOIN transactions/fulfillments 聚合）會拖垮列表——推導結果**物化在 orders 兩欄**，由服務層在每次金流/出貨動作後更新（同 transaction）；bulk 動作要逐筆獨立 transaction（一筆失敗不連坐）並產出結果報告。

## F2. Timeline 與內部備註

**生產級做法**：`events` append-only（actor: system/staff/buyer、verb、payload JSON）；所有服務動作結尾寫事件（建單、付款、出貨、退款、編輯、寄信、備註）；備註是 verb=comment 的事件，僅後台可見；渲染白名單 verb → 文案模板。

**⚠️ 坑**：事件 payload 別塞整包物件（PII 蔓延 + 膨脹）——只存 diff 與 ID；事件不可編輯刪除（稽核價值），備註「刪除」= 追加一筆 redaction 事件。

## F3. 出貨（Fulfillment）

**生產級做法**：
1. 模型照 06：訂單成立時建 `fulfillment_orders`（demo 單地點 1 筆）；fulfill 動作對 FO 的**剩餘數量**驗證（`≤ quantity - fulfilled_quantity`，條件式 UPDATE 累加防超出）。
2. 出貨 = transaction：建 `fulfillments`（tracking number/carrier/url）→ FO 數量累加 → 庫存 committed−/on_hand−（13-F5 的 service）→ 訂單 fulfillment_status 重新物化 → 事件 + outbox（fulfillments/create）→（transaction 外）出貨通知信 job。
3. tracking URL：carrier → URL 模板表（黑貓/7-11/郵局/DHL…），未知 carrier 允許自填 URL（驗證 http(s) 白名單）。
4. 部分出貨天然支援（數量制）；取消出貨（P1）：逆向還原數量與庫存，限「已出貨未送達」窗口。

**⚠️ 坑**：同一 FO 兩個 staff 同時 fulfill 剩餘 3 件各出 3 件 → 沒有條件式累加就變 6 件；tracking 通知信寄出前驗 email 存在（draft order 可能沒 email）；fulfillment_status 的物化更新忘了做 → 列表永遠 unfulfilled（把「物化」寫進 service 的共用 after 步驟 + 測試）。

## F4. 取消與封存

**生產級做法**：
1. Cancel 前置檢查：全部 FO 未出貨（或已先取消出貨）；動作 = 狀態條件轉移 + 庫存 committed 釋放（available+）+ 依選項退款（走 F5）+ 事件 + outbox（orders/cancelled）；cancel_reason 必填 enum。
2. Archive：純標記（closed_at），不影響金流庫存；自動封存規則（付清且已出貨 N 天後）P1 做成 nightly job。
3. 兩者語意分開（研究 01）：cancel 是業務反悔、archive 是收納——UI 文案明確。

**⚠️ 坑**：cancel 不自動等於 refund（要明確勾選）；已部分出貨的單不能整單 cancel（只能對未出貨行退款）——前置檢查要細到行級。

## F5. 退款（Refund）

**生產級做法**：
1. 退款面板：逐行選數量（≤ 已購未退數）、restock 勾選（預設勾）、另退運費欄（≤ 原收運費）、原因、是否通知——完全對齊研究 01 的畫面。
2. 計算：行退款金額 = 行單價×數量 −（該行折扣分攤 × 退貨比例，查 discount_applications，15-F2 坑）；稅同理按比例；**上限鎖**：累計退款 ≤ 實收（transactions 聚合，DB CHECK 級測試）。
3. 執行順序：本地 transaction（建 refund + refund_line_items + transaction 列 pending + restock via Inventory::Adjust 冪等 + 事件）→ **transaction 外**呼叫 Stripe refund → webhook 確認 → transaction 列轉 success → financial_status 重物化 → 通知信。
4. Stripe 失敗處理：pending 退款列 + 告警 + 後台可重試（冪等 key 不變）。

**⚠️ 坑**：restock 冪等（13-F5：refund_line_item_id 唯一）防 webhook 重放重複進貨；「先打 Stripe 再落庫」順序錯誤會在本地失敗時退了錢沒紀錄——**永遠先落 pending 再打金流**；部分退款多次後的殘額計算用資料庫聚合而不是前端傳入。

## F6. 顧客管理

**生產級做法**：
1. 建檔：訂單成立時 email upsert（`(shop_id, email)` 唯一）；統計欄位（amount_spent、orders_count、last_order_at）由訂單事件增量維護 + nightly 重算對帳。
2. 詳情頁：訂單歷史 keyset 分頁、地址簿 CRUD（預設地址單選）、tags（正規化表）、備註（事件）。
3. 合併（P1）：`Customers::Merge` service——訂單/地址/tags 重掛、統計重算、事件記錄雙方 ID；被併者標記 merged_into_id 不硬刪。
4. 匯出 CSV：streaming（13-F6），欄位含 consent 狀態；匯出動作記 audit log（PII 外流點）。
5. 刪除（隱私請求）：檢查無未完成訂單 → 匿名化（email→hash 佔位、姓名地址清空、保留訂單金額統計）而非硬刪（帳務完整性）。

**⚠️ 坑**：guest 重複下單不同大小寫 email → 正規化後 upsert；統計欄位只靠增量會漂移 → nightly 重算是必備對帳；匿名化要連 events payload 與 checkouts 一起處理（PII 清單驅動，11 §7）。

## 本篇驗收（對照 11 §0）

雙 staff 併發 fulfill/refund 不產生超量；退款上限在惡意請求下不可突破（request spec）；restock 重放冪等；cancel 後庫存恆等式仍成立（ledger 對帳）；訂單列表 10 萬筆下 p95 <300ms（keyset 驗證）；匿名化後全文搜尋/匯出查無 PII；每個動作 timeline 都有事件且 audit 可追。
