# Handoff — G6-6a 訂單 API 讀取面（2026-09-01）

## ① 我改了什麼

- 輸入：使用者指令「20 步全流程執行——每步深研官方文檔＋親自點擊實測＋全取證」；
  PayPal（步 1）使用者明示暫停。base＝main（#226 之後）。本包＝步 3。
- 研究輪（四並行）：官方 shopify.dev 訂單/履約/退款 enum 與 mutation 逐字取證
  （2026-07 版）＋倉庫正典盤點（76/22/90-blueprint/16/實作錨）＋OSS 參考
  （BSD/MIT 限定）——結果存 session scratchpad ord-0~3，正典結論併入 88 號。
- 實測輪：測試店訂單線親點（列表七組篩選 enum 逐項展開/排序/欄集/Export/
  詳情雙狀態/退款頁/退貨頁/草稿/棄單）→ `docs/research/88` 入庫。
- 實作：OrderType 家族＋MoneyBag 首發＋orders/order query＋SearchScope＋
  OrderPolicy＋processed_at cursor 鍵＋Customer.lastOrder。
- 驗證：contract spec 6 例綠；突變五格紅（含一格改打——見③）；全套閘門於
  凍結樹重跑（rspec 背景單獨回收退出碼）。

## ② 為什麼這樣改

- 預設序 processed_at desc＝雙證（88 §1 本尊 URL 實測 ∧ 官方 sortKey 預設
  PROCESSED_AT）；enum 值域一律引 model 常數（值域正典單一來源）；
  MoneyBag 兩腳 v1 同值＝契約形先行，markets 幣別包接手時 API 消費端零改。
- 被推翻的假設：①「單號搜尋要剝 # 前綴」——突變證實不承重（單號欄含 #，
  contains 天然涵蓋），已刪；②篩選層 Payment status 10 值≠API enum 8 值
  （Due/Unpaid 是查詢糖）——分層各自為真，88 §2 登記。

## ③ 還有什麼沒解決

- sortKey 引數（12 鍵值域已錄 88 §2）；fulfillment 模型與 FulfillmentType（步 5）；
  displayFulfillmentStatus 擴值；lineItems connection 化；88 V-88-1~6。
- MUT-O4 首發殺不紅的完整記錄在 worklog Pending（20.4 反向複驗附命令）。

## ④ 下一個人要注意什麼

- 步 4（admin 訂單頁）直接吃本包：CUSTOMERS_QUERY 同款三件套抄
  `orders` query；篩選 chips 組 query 字串走 SearchScope 白名單
  （status:/financial_status:/fulfillment_status:）；欄集/排序面照 88 §2。
- 新增金額欄一律 MoneyBagType（resolver 給 {cents:, currency:,
  presentment_cents:, presentment_currency:}）；不得再造。
- 三處同批鐵則（schema 檔頭警告）：RESOLVABLE_TYPES＋resolve_type＋
  implements Node。
- 突變輪的 `git checkout --` 會把「突變前的未提交修改」一起洗掉——本包實踩
  （刪 delete_prefix 的清理被洗、靠 grep 自查抓回）；先 commit 再突變，或
  突變後逐檔 diff 自查。
