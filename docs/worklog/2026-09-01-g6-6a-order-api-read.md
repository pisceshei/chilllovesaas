# 2026-09-01 G6-6a：訂單 API 讀取面（88 號六層實測＋官方逐字取證 → OrderType 家族）

## 已完成的工作 (Done)

- **88 號 teardown 入庫**（`docs/research/88-admin-orders-live-teardown.md`）：測試店
  訂單線親點實測（列表 24 篩選維度＋7 組 enum 逐項展開／排序 12 鍵／欄集 15 欄／
  Export modal／More actions／詳情頁雙狀態／退款頁／Return and exchange 頁／
  草稿與棄單列表結構／CSS 真值 450/550 消融），與官方 shopify.dev（2026-07 版，
  取證 2026-09-01）enum 對表；篩選層 vs API enum 的層差（10 值 vs 8 值）明文登記。
- **GraphQL 訂單讀取面**：`OrderType`（三狀態軸 enum／MoneyBag 五金額欄／行項／
  交易／customer／地址快照雙欄）＋`LineItemType`（快照語義）＋
  `OrderTransactionType`（append-only）＋`OrderAddressType`（zone→province 對映）＋
  🔴 **`MoneyBagType` 首發**（shopMoney/presentmentMoney；v1 單幣同值——markets
  幣別包接手時消費端零改動）＋四個 enum（financial 8／fulfillment v1 3／
  transaction kind 5／status 6——值域一律引 model 常數，兩處同源）。
- **`orders` query**＋`order(id)`：keyset 分頁（預設序 processed_at desc＝88 §1
  URL 實測＝官方 sortKey 預設）＋`Orders::SearchScope`（裸詞→單號/email CONTAINS；
  status:/financial_status:/fulfillment_status: 白名單、非法值空集）＋
  `OrderPolicy`（orders.view 獨立權限格）＋schema 白名單雙處＋KeysetCursor 增
  processed_at 鍵＋五語 locale。
- **Customer.lastOrder** 關聯欄（顧客詳情「最近訂單」卡的資料口）＋
  `Order belongs_to :customer` 補齊（G6-7 只加了反向）。
- **測試**：`orders_contract_spec` 6 例（O-G1~O-G6＋分頁＋lastOrder）；突變輪
  O1 跨店/O2 裸 cents/O3 掉序鍵/O4b 非法 enum 放行/O6 帳單不回落全紅。

## 修改的檔案與核心邏輯 (Changes)

- `docs/research/88-admin-orders-live-teardown.md`：新增。
- `app/graphql/types/`：order_type／line_item_type／order_transaction_type／
  order_address_type／money_bag_type／order_connection_type／order_edge_type／
  order_display_financial_status_enum／order_display_fulfillment_status_enum／
  order_transaction_kind_enum／order_transaction_status_enum 新增；
  customer_type 增 lastOrder；query_type 增 orders/order＋authorize_orders!。
- `app/graphql/orders/search_scope.rb`：新增。
- `app/graphql/products/keyset_cursor.rb`：ORDER_KEYS 增 processed_at。
- `app/graphql/chilllove_schema.rb`：Order 白名單雙處。
- `app/models/order.rb`：belongs_to :customer；`order_policy.rb` 新增。
- `config/locales/*.yml` ×5：errors.orders.access_denied。
- `spec/graphql/orders_contract_spec.rb`：新增。

## 尚未完成或需注意的風險 (Pending / TODO)

- 🔴 **20.4 反向複驗記錄**：SearchScope 首版含「單號剝 # 前綴」代碼，突變輪
  MUT-O4（拔掉剝前綴）**殺不紅**——單號欄本身存 # 前綴，contains 比對下該代碼
  不承重 ⇒ 已刪除，殺手改打「非法 enum 值放行」（MUT-O4b 實紅）。複驗：
  `bundle exec rspec spec/graphql/orders_contract_spec.rb -e "O-G4"`。
- `sortKey` 引數未上（88 §2 十二鍵值域已錄）——與 products 同姿勢登記 V，
  隨列表排序一般化包。
- displayFulfillmentStatus v1 三值子集（SCHEDULED/ON_HOLD/IN_PROGRESS 擴值隨
  步 5 履約線落庫時同批）；lineItems v1＝list 非 connection（量級上來換）。
- fulfillments 欄未出（Fulfillment model 未建——步 5 建模時補 FulfillmentType）。
- 步 4（admin 訂單列表/詳情頁）吃本包 query，下一包接。
- 88 號 V-88-1~6 照登記（數值型篩選 UI 形/badge pill 精確色/Edit 頁/標籤頁深入/
  saved view 流/persisted query 不可觀測）。
