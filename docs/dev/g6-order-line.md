# G6-6 訂單線：讀取契約＋admin 訂單頁＋markAsPaid（步 3＋步 4）

> 對應規格：`docs/research/88`（六層實測）＋28 §4＋90-blueprint/04/05＋specs/16。
> 步 3（#227）＝讀取面；本包（步 4）＝admin 頁＋首支訂單 mutation。

## 1. 這是什麼（三端對接位）

```
買家前台結帳（G6-4）─成單→ Orders::CreateFromCheckout ─┐
                                                        ▼
admin GraphQL：orders / order(id) / orderMarkAsPaid   ← 本線
                                                        ▼
admin SPA：/admin/orders 列表 ＋ /admin/orders/:id 詳情
```

## 2. 具體功能與值域

- **orders query**：keyset ≤250；預設序 processed_at desc（88 §1 實測＝官方
  sortKey 預設雙證）；`query` 語法＝裸詞（單號/email CONTAINS）＋
  `status:`/`financial_status:`/`fulfillment_status:` 白名單（非法值空集）。
- **OrderType**：三狀態軸各自 enum（值域引 model 常數單源——
  `Order::FINANCIAL_STATUSES` 8 值/`FULFILLMENT_STATUSES` v1 3 值/
  `STATUSES` 3 值）；金額五欄 MoneyBag（v1 兩腳同值）；itemCount＝行項數量合計；
  lineItems/transactions＝list；customer 可 null（guest）；
  billingAddress：same_as_shipping ⇒ 回落出貨快照、different ⇒ 剝 billing_ 前綴。
- **orderMarkAsPaid**（首支訂單 mutation）：pending sale 交易翻 success →
  financial_status paid → event＋orders/paid outbox；已取消/已入帳 ⇒
  INVALID_STATE；idempotencyKey 必帶（limits idempotency.required_for）。
- **列表頁**：88 §2 預設欄的資料已備子集（單號/日期/顧客/總計/付款狀態/
  出貨狀態/商品數）；付款八值＋出貨三值篩選下拉（值域窮舉入 FE 測試）；
  搜尋去抖 300ms；列點擊進詳情。
- **詳情頁**：badges＋行項卡＋金額卡（小計/折扣/運費/總計＋交易列）＋右欄
  顧客/收貨/帳單/標籤卡；PENDING∧open 才出「標記為已付款」（確認框＋
  randomUUID 冪等鍵，jsdom/明文後備時間戳）。

## 3. 怎麼做出來的（實作錨）

- 型別：`app/graphql/types/order_type.rb` 等 11 檔；搜尋
  `app/graphql/orders/search_scope.rb`；服務 `app/services/orders/mark_as_paid.rb`；
  頁面 `app/frontend/admin/pages/Orders{Page,DetailPage}.tsx`。
- 與 `MarkPaidFromPsp` 分工：PSP 路徑靜默冪等（雙路徑先到先贏）；admin 路徑
  顯式報錯（UI 藏鈕之外殘留點擊要可解釋）——兩服務檔頭互引。

## 4. 跨功能／前端影響（預先對接）

- 步 5 履約退款：FulfillmentType 掛回 OrderType.fulfillments；refundCreate 的
  金額欄吃同一 MoneyBag；detail 頁行項卡加出貨鈕位。
- 步 7 棄單/步 10 分析/步 18 平台 GMV：讀同一 orders 契約。
- 顧客詳情（步 8）：Customer.lastOrder 已通；訂單頁顧客卡日後連 /admin/customers/:id。
- 🔴 突變輪雙防線記錄：跨店殺手（拔顯式 shop_id）不紅＝acts_as_tenant
  with_tenant 預設 scope 兜底；顯式 shop_id 依鐵律 2 條款②照留（查詢層逐表帶
  shop_id 是規範要求，不因兜底存在而省略）。

## 5. 已知邊界

- sortKey 引數未上（88 §2 十二鍵已錄，隨排序一般化包）；Channel/Delivery
  status/Tags/Fulfill by 欄隨對應資料線；saved views/bulk/欄位選擇器＝列表
  全量包；Timeline/風險卡/Edit/Cancel/Refund UI＝步 5 與後續包。
