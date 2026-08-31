# 2026-09-01 G6-6b（步 4）：admin 訂單列表/詳情頁＋orderMarkAsPaid

## 已完成的工作 (Done)

- **列表頁** `/admin/orders`（88 §2 預設欄資料已備子集：單號/日期/顧客/總計/
  付款狀態/出貨狀態/商品數）：付款八值＋出貨三值篩選（值域窮舉入測試）、
  搜尋（單號/email）、cursor 載入更多、三態、列點擊進詳情。
- **詳情頁** `/admin/orders/:orderId`（88 §3 骨架資料已備子集）：badges＋
  行項卡＋金額卡（小計/折扣/運費/總計＋交易列）＋右欄顧客/收貨/帳單/標籤卡；
  「標記為已付款」（PENDING∧open 條件顯示＋確認框＋冪等鍵）。
- **orderMarkAsPaid mutation**（首支訂單 mutation；三件套 error enum/type＋
  limits idempotency.required_for 登記）＋`Orders::MarkAsPaid` 服務（pending
  sale 翻 success→paid→orders/paid outbox；與 MarkPaidFromPsp 分工檔頭互引）。
- **OrderType.itemCount**（列表 Items 欄）；admin.css 補訂單詳情類；
  i18n 66 鍵×5 語包；docs/dev/g6-order-line.md（補 #227 步 3 的 dev 文檔義務）。
- 測試：後端 12 例（含 M1–M5 殺手）＋前端 5 例（端點契約/$after 文件/列渲染/
  篩選值域窮舉/標記付款流）；突變 M1/M2/M4 紅。

## 修改的檔案與核心邏輯 (Changes)

- `app/graphql/mutations/order_mark_as_paid.rb`＋`types/errors/order_mark_as_paid_*`
  ＋`app/services/orders/mark_as_paid.rb`＋mutation_type 掛載＋limits 登記。
- `app/graphql/types/order_type.rb`：itemCount。
- `app/frontend/admin/pages/Orders{Page,DetailPage}{,.test}.tsx`＋App.tsx 路由×2
  ＋`app/assets/stylesheets/admin.css` 訂單詳情類＋五語包 orders.* 66 鍵。
- `spec/graphql/order_mark_as_paid_spec.rb` 新增。
- `docs/dev/g6-order-line.md` 新增（步 3＋4 合篇）。

## 尚未完成或需注意的風險 (Pending / TODO)

- 🔴 突變輪記錄二則：①MUT-M5（拔顯式 shop_id）不紅＝acts_as_tenant
  with_tenant 預設 scope 第二道防線接住；顯式 shop_id 依鐵律 2 條款②照留。
  複驗：`bundle exec rspec spec/graphql/order_mark_as_paid_spec.rb -e "M5"`。
  ②FE 狀態字樣斷言首版被篩選 option 同字樣撞紅——改 getAllByText（測資教訓）。
- 步 5 接續：fulfillmentCreate/refundCreate/orderCancel＋詳情頁出貨/退款 UI；
  Timeline 卡（events 查詢面未建）；訂單頁顧客卡連顧客詳情頁（步 8）。
- 列表 Channel/Delivery status/Tags 欄、saved views、bulk、欄位選擇器、
  sortKey＝列表全量包；Export＝後續。
- 日期顯示用瀏覽器 locale（toLocaleString）——店時區顯示隨 shop.timezone
  接線包（Shop query 已有時區欄）。
