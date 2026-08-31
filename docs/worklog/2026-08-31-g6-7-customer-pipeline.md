# 2026-08-31 G6-7：checkout 資料契約＋顧客線地基＋客戶管理頁對接

## 已完成的工作 (Done)

- **checkout→order→customer 資料鏈路接通**（使用者指令：結帳頁欄位資料做好接口、
  後端模塊可完美對接）：
  - `Customers::UpsertFromCheckout`（訂單成立交易內；16 §F6.1 email upsert）：
    正規化去重／識別欄只補空／consent 只升不降（source=checkout＋時間戳）／
    地址簿簿空補預設（zone→province 對映）／統計三欄原子增量（鐵律 7 唯一寫入端）／
    order.customer_id＋checkout.customer_id 回寫。manual 與 PSP 同鏈生效。
  - `orders.buyer_accepts_marketing` 傳導（g6-4 worklog Pending 收口）。
  - migration：customers.last_order_at＋email consent 中繼兩欄＋orders 勾選快照欄。
- **Customer／CustomerAddress model 首發**（表 M0 就在、此前零消費者）＋
  `CustomerPolicy`（customers.view/edit 獨立權限格）。
- **GraphQL 契約**：`customers` query（keyset ≤250、預設序 updated_at desc、
  自由文字搜尋）＋`customer(id)`＋`CustomerType`/`CustomerAddressType`/
  Connection/Edge＋🔴 **`MoneyV2Type` 首發**（鐵律 3 序列化層的 GraphQL 落點，
  G6-6 Order 線共用）＋RESOLVABLE_TYPES/resolve_type 雙處同批補 Customer＋
  KeysetCursor 增 `updated_at` 排序鍵＋Rails locale 五語補 customers.access_denied。
- **客戶管理頁對接**：`/admin/customers` 由佔位頁轉真頁（App.tsx IMPLEMENTED）；
  `CustomersPage.tsx`＝74 §1 預設五欄＋伺服器搜尋＋cursor 載入更多＋三態；
  i18n 18 鍵×五語包；colocated 測試 4 例。
- **測試**：`storefront_order_customer_spec`（K1–K6）＋`customers_contract_spec`
  （G1–G5＋分頁契約）共 9 例；FE 4 例；突變輪八格全紅
  （K1b 正規化/K2 統計/K3 降級/K4 回寫/K6 覆寫/G2 裸 cents/G3 跳脫/G4 預設序）。
  🔴 突變輪兩個修正記錄：K1「恆建新列」殺不紅＝DB 唯一鍵第二道防線接住（防線
  load-bearing 的正面證據，改殺正規化層）；G3/G4 首輪殺不紅＝**測資選錯**
  （無含 0 資料／兩排序鍵同向），已加反向 fixture 並在 spec 內註記。

## 修改的檔案與核心邏輯 (Changes)

- `db/migrate/20260831310000_add_customer_stats_and_consent_metadata.rb`＋schema。
- `app/models/{customer,customer_address,customer_policy}.rb`：新增。
- `app/services/customers/upsert_from_checkout.rb`：新增（管線本體）。
- `app/services/orders/create_from_checkout.rb`：掛管線＋buyer_accepts_marketing 傳導。
- `app/graphql/types/{money_v2,customer,customer_address,customer_connection,customer_edge}_type.rb`：新增。
- `app/graphql/customers/search_scope.rb`：新增；`products/keyset_cursor.rb` 增 updated_at 鍵。
- `app/graphql/types/query_type.rb`：customers/customer field＋authorize_customers!。
- `app/graphql/chilllove_schema.rb`：Customer 白名單雙處。
- `config/locales/*.yml` ×5：errors.customers.access_denied。
- `app/frontend/admin/{App.tsx,pages/CustomersPage.tsx,pages/CustomersPage.test.tsx}`＋
  `i18n/messages/*.json` ×5。
- spec：`storefront_order_customer_spec.rb`＋`graphql/customers_contract_spec.rb` 新增。
- `docs/dev/g6-customer-pipeline.md`：接口文檔（跨功能對接點）。

## 尚未完成或需注意的風險 (Pending / TODO)

- consent＝boolean＋中繼欄（六值狀態機＋append-only 事件表＝08 §B.2/§C.4 全量包）；
  SMS/WhatsApp 通道未接。
- phone 唯一索引未補（08 §C.1 要求；動資料面另包裁定）。
- 顧客詳情頁／customer* mutation／合併/匿名化/匯入匯出/RFM 分群/排序鍵全值域/
  18 欄選擇器＝顧客模組全量包；nightly 統計對帳 job 未建（增量在，漂移對帳待排程包）。
- 既有生產訂單（#1001 等）不回填 customer——管線只對新訂單生效；回填屬資料
  遷移裁定（避免未經裁定改歷史資料）。
- 測試訂單剔除（08 §E.2）未實作（無測試訂單概念）。
- F5 併發壓測（50 執行緒同 checkout）欠帳掛 G6-6——顧客統計增量已用原子 SQL，
  該壓測屆時必須涵蓋 orders_count/total_spent 不漂。
