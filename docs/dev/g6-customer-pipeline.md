# G6-7 顧客線地基：checkout 資料契約＋customers query＋顧客列表頁

> 對應規格：`docs/specs/16` §F6.1（建檔）／`docs/research/90-blueprint/08-customers.md`
> §B.2、§C.1、§C.4、§E.2（身分/同意/依賴方向）／`docs/research/74` §1（列表五欄）／
> `docs/research/28` §7＋§0.3（API 面）。使用者指令（2026-08-31）：「結帳頁所有欄位
> 獲取的資料。你要做好接口。等後端所有功能模塊開發過程中可以完美對接。以及前端
> 客戶管理頁面的對接。」

## 1. 資料鏈路（這是什麼／怎麼做）

```
結帳頁欄位（87 §3）
  email / buyer_accepts_marketing / shipping_address{first,last,addr1,addr2,
  city,zone,postal_code,phone,country_code} / billing_address{mode,billing_*}
        │ /checkouts/:token/submit（G6-4）落 checkouts 表
        ▼
Orders::CreateFromCheckout（訂單成立交易內）
  ├ Order 快照欄：email＋buyer_accepts_marketing（本包新增傳導）＋兩地址 JSON
  └ Customers::UpsertFromCheckout（本包新增；同交易純 DB——鐵律 5）
      ① email 正規化（lowercase+strip；唯一定義點 Customer.normalize_email）
         → (shop_id, email) find_or_create；撞 uq_customers_email ⇒ 重讀贏家
      ② 識別欄只補空（姓名/電話——訂單快照 ≠ 主檔編輯權）
      ③ consent 只升不降：勾選 ⇒ email_marketing_consent=true＋
         (updated_at, source="checkout")；已訂閱不重寫時間戳；未勾不退訂
      ④ 地址簿只在簿空時補（06 §2：訂單面是快照）；zone→province 鍵名對映
      ⑤ 統計三欄原子增量：orders_count+1／total_spent_cents+=total／
         last_order_at（🔴 鐵律 7：這是三欄唯一寫入端；列表/詳情 KPI/報表同源直讀）
      ⑥ 回寫 order.customer_id＋checkout.customer_id
```

manual 與 PSP 兩條付款路共用同一建單服務 ⇒ 管線對兩者一體生效。

## 2. 對外接口（後續模塊的對接點）

- **GraphQL**（`/admin/api/2026-08/graphql.json`；鐵律 4）：
  - `customers(first, after, last, before, query)`：keyset cursor（≤250）、預設序
    updated_at desc（74 §1 本尊預設鍵）、`query`＝姓名/email/電話 CONTAINS 多詞 AND
    （`Customers::SearchScope`；LIKE 萬用字元跳脫）。
  - `customer(id)`：GID `gid://chilllove/Customer/{id}`；跨店/不存在回 null。
  - `Customer` 型別：身分欄＋consent 欄（boolean＋updated_at/source）＋統計三欄＋
    `defaultAddress`；**`amountSpent`＝`MoneyV2 { amount, currencyCode }`**——
    `Types::MoneyV2Type` 隨本包首發（鐵律 3 的 GraphQL 序列化落點；G6-6 Order 線
    金額欄一律共用它，不得另造）。
  - 授權：`customers.view`（`CustomerPolicy`；PII 獨立權限格，不沿用商品/檔案鍵）。
  - node/nodes：`RESOLVABLE_TYPES`＋`resolve_type` 已補 Customer 分支（兩處同批）。
- **模型層**：`Customer`／`CustomerAddress`（表 M0 就在，本包首個消費者）；
  `Customer.normalize_email` 是 email 正規化唯一定義點——任何新寫入路徑
  （customerCreate、匯入）必須走它。

## 3. 前端客戶管理頁

`/admin/customers`（App.tsx IMPLEMENTED 註冊；側欄既有 nav 直達）＝
`CustomersPage.tsx`：74 §1 預設五欄（顧客名稱／電子郵件訂閱 chip／地點／訂單／
消費金額）、伺服器搜尋（300ms 去抖）、cursor 載入更多、三態（骨架/錯誤+重試/
空態二形）。i18n 18 鍵×五語包。

## 4. 跨功能影響（預先對接）

- **G6-6 訂單 API**：OrderType 的金額欄用 `MoneyV2Type`；`Order.customer_id` 已有值
  ⇒ `order.customer` 關聯與顧客詳情「最近訂單」卡可直接接。
- **棄單挽回線**：`checkouts.customer_id` 已回寫 ⇒ 棄單列表可歸戶。
- **行銷/分群線**：consent 讀 `email_marketing_consent*` 三欄；升級到六值狀態機＋
  append-only 事件表（08 §B.2/§C.4）時本包欄位轉為快取層，來源語義不變。
- **報表線（19 rollup）**：nightly 對帳 job 重算三統計欄時，**寫入端仍以本服務的
  增量為準**、對帳只修漂移（16 §F6.1）。

## 5. 已知邊界（誠實登記）

- consent＝boolean＋中繼兩欄，**不是** 08 §B.2 六值狀態機（PENDING/REDACTED/
  INVALID 表達不了）；SMS/WhatsApp 通道未接。
- phone 唯一索引未補（08 §C.1 要求 unique，現況非 unique——動既有資料面另包裁定）。
- 顧客詳情頁、customerCreate/Update/合併/匿名化 mutation、匯入匯出、RFM/分群、
  排序鍵 7×2 全值域、欄位選擇器 18 欄＝顧客模組全量包。
- 測試訂單剔除（08 §E.2 rollup 規則）：目前無測試訂單概念，全量計入。
