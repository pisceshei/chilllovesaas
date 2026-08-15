# Rails 地基與 Admin Shell（M0）

## 概述

M0 建立 CHILL LOVE 多租戶電商 SaaS 的可執行地基：Rails 8.1、MySQL 8、Solid Queue／Solid Cache（不用 Redis）、Vite + React TypeScript Admin SPA、租戶解析、staff 認證、版本化 Admin GraphQL，以及登入後的 CHILL LOVE shell 與商品空狀態。平台名稱集中在 `config/brand.yml`；產品與 API 上限集中在 `config/limits.yml`；Admin 視覺 token 由 `docs/design/23-interaction-css-spec.md` §1 原樣搬入 `app/assets/tokens.css`。

本里程碑的資料地基包含 `docs/research/06-data-model.md` §7 實際具名的 47 張表，另依 `docs/specs/11-production-baseline.md` §2 加入 `idempotency_keys`。後續 M1–M6 可在不改變租戶鍵、金額格式與 API 邊界的前提下逐步補齊業務行為。

## 成果概覽

- Rails 8.1 單體使用 MySQL 8，資料庫字元集／排序規則為 `utf8mb4`／`utf8mb4_0900_ai_ci`。
- development 與 production 都以獨立資料庫承載 primary、Solid Cache、Solid Queue 與 Solid Cable；test 的 Action Cable 使用 `test` adapter。全環境均未引入 Redis。
- `Chilllove::TenantResolver` 僅以 request Host 解析租戶，使用 Solid Cache 快取 5 分鐘，將租戶放入 `Current.shop` 與 `ActsAsTenant.current_tenant`，並在 request 結束或例外時清除 context。
- staff 登入採 bcrypt、可撤銷 DB session、SHA-256 token digest、`reset_session`、host-only `_cl_admin` cookie，以及 IP／帳號雙鍵登入限流。
- Admin server boundary 以 Pundit 驗證；React SPA 的資料請求固定送往版本化 GraphQL 端點。
- 商品頁具備 loading、error、empty、data 與搜尋空結果狀態；M0 預期驗收畫面為 CHILL LOVE shell 與「還沒有商品」空狀態。
- schema 用共用 migration helper 強制租戶表的第一個顯式欄位為 `shop_id`，所有業務索引由 `(shop_id, ...)` 開頭，租戶內關聯使用 composite foreign key。
- 所有 `*_cents` 欄位均為 `bigint`，且帶對應 currency 欄位；migration 不使用 `float` 或 `decimal` 儲存金額。

## 規格出處

| 實作範圍 | 規格來源 |
|---|---|
| Rails 8.1、MySQL 8、Vite/React、Solid Queue/Cache、不用 Redis | `HANDOFF.md` D1、§5 M0；`docs/research/10-implementation-playbook.md`「通用底座」與「M0 開工清單」 |
| 單一品牌來源 | `HANDOFF.md` D3 |
| 多租戶欄位、索引、integer cents 與 47 張具名表 | `docs/research/06-data-model.md` §1–§7；`docs/specs/11-production-baseline.md` §2 |
| Host 解析、租戶 context、staff session、cookie、限流與 Pundit | `docs/specs/12-spec-tenancy-auth-permissions.md` F1–F4；`docs/specs/11-production-baseline.md` §1、§8 |
| Admin 只走 GraphQL、日期版本、GID、cursor、HTTP 200 errors 與 cost | `HANDOFF.md` D5；`docs/research/28-api-contract.md` §0、§1、§18 |
| Admin shell、商品頁與配額 | `docs/research/22-admin-button-inventory.md` §0、§2、§9.4 |
| UI tokens、App frame、元件狀態與 a11y | `docs/design/23-interaction-css-spec.md` §1–§6；`docs/design/chilllove-admin-v2.html` |
| 冪等與 outbox 地基 | `docs/specs/11-production-baseline.md` §2、§8；`docs/research/10-implementation-playbook.md` §08 |

## 架構與資料流

### Request 與租戶邊界

```text
HTTP request Host
  -> Chilllove::TenantResolver
     -> platform／保留 Host：不綁定租戶，繼續交給 Rails
     -> tenant subdomain 或已登記 custom domain
        -> Solid Cache（5 分鐘）
        -> Shop active lookup
        -> Current.shop + ActsAsTenant.current_tenant
     -> 未知／停用 Host：404（no-store）
  -> ApplicationController
  -> ensure：清除 Current 與 ActsAsTenant，避免 thread／connection pool 洩漏
```

租戶身分不接受 query param 或自報 header。`acts_as_tenant` 的 `require_tenant` 提供應用層 fail-closed；migration 再以 `(shop_id, id)` tenant identity key 與 `(shop_id, parent_id) -> (shop_id, id)` composite foreign key 擋下跨店關聯。

### Staff 認證

```text
POST /login
  -> TenantResolver 先綁定 Shop
  -> SessionsController 以 tenant scope 查 StaffMember
  -> bcrypt 驗證（未知帳號也跑 dummy hash）
  -> reset_session
  -> Session.issue!
     -> DB 只存 SHA-256 token digest、IP、user agent、有效期
     -> raw opaque token 只放 Rails encrypted `_cl_admin` cookie
  -> redirect /admin
```

後續 request 由 `ApplicationController#resume_admin_session` 驗證未撤銷、未過期且 staff 仍啟用的 DB session；活動時間最多每 5 分鐘寫回一次。`DELETE /logout` 先撤銷 DB session 再清除 Rails session。登入以 Rack::Attack 同時限制每 IP 每分鐘 10 次及每 `shop_id + email` 每 10 分鐘 10 次；同店 subdomain 與 custom domain 因此共用帳號額度，email 進 cache key 前會先雜湊。

### Admin shell 與商品資料

```text
GET /admin/products
  -> Admin::SpaController
  -> authenticate_staff! + Pundit
  -> Rails layout 注入 CSRF 與 config/brand.yml 的品牌名稱
  -> Vite entrypoint 掛載 React Router + AdminShell
  -> ProductsPage
  -> requestAdminGraphQL（同源 cookie + X-CSRF-Token）
  -> POST /admin/api/2026-08/graphql.json
  -> GraphqlController + Pundit + cost guard
  -> Types::QueryType
  -> tenant-scoped Product keyset query
  -> GID／Relay connection／extensions.cost JSON
```

商品列表以 `(created_at, id)` keyset cursor 分頁，不使用深 OFFSET。前端預設頁量取 `app/frontend/admin/api/pagination.ts`（鏡像 `limits.yml api.pagination_default_page_size`＝50），server 端以 `api.pagination_max_page_size` 限制單頁最多 250 筆。空資料時顯示「還沒有商品」與「新增商品」CTA；新增／編輯路由在 M0 仍是 placeholder，CRUD 屬 M1。

## Admin GraphQL API

唯一首版 Admin API 是：

```http
POST /admin/api/2026-08/graphql.json
```

目前 M0 暴露 read-only `products` connection、`node(id:)` 與 `nodes(ids:)`。契約重點如下：

- session-authenticated、同源 CSRF；SPA client 不接受任意 API URL。
- response header 回傳 `X-CL-API-Version: 2026-08`。
- 對外 ID 為 `gid://chilllove/{Type}/{id}`；不直接以 GlobalID 查找跨租戶資料。
- connection 接受 `first/after/last/before`，回傳 `nodes`、`edges` 與完整 `pageInfo`；cursor 為不透明 base64 keyset cursor。
- 每個回應附 `extensions.cost`；單次 requested cost 超過 1,000 時回 `MAX_COST_EXCEEDED`。
- GraphQL syntax／權限／限流／internal error 使用 top-level `errors`，仍回 HTTP 200 並附 `requestId`；未認證或未授權回 `ACCESS_DENIED`。
- 業務 mutation 尚未在 M0 開放。M1 起 mutation payload 必須使用 `{ resource, userErrors: [{ field, message, code }] }`，業務錯誤不可改走 HTTP 4xx。
- Money API 後續以 `MoneyV2`／`MoneyBag` 序列化；資料庫內仍只存 integer cents + currency（**儲存一律 ×100、不看幣別**）。🔴 金額單位邊界契約全文＝`docs/specs/65`（鐵律 3 五小條）：儲存尺度 ≠ 顯示位數 ≠ 對外單位；送 PSP 依該 pack 宣告的 `amount_format` 分流（`Money::Storage#to_psp_amount(psp:)`），ISO 4217 不是換算基數。M1 前須建 `lib/money` 型別骨架與 zero-decimal（JPY/TWD/KRW）CI 測試矩陣，讓 65 §C/§H 的執法點在第一條金額寫路徑出現前就存在。
  <!-- 依 65 號（2026-08-12 裁定二＋69 §V-188）修正，原文：「Money API 後續以 MoneyV2／MoneyBag 序列化；資料庫內仍只存 integer cents + currency。」原文成文早於 65 號契約，缺單位邊界的全部語義。 -->

## 資料表與 migration

### 應用 migration

主要 schema source of truth：

- `db/migrate/20260811000000_m0_create_core_schema.rb`：47 張規格具名表 + `idempotency_keys`，以及 tenant-safe indexes／foreign keys。
- `db/schema.rb`：由 MySQL 8.4 clean migration 產生的 primary schema snapshot，包含 48 張 application tables；不可手動編輯。

Solid 元件使用 Rails 產生的獨立 schema 檔：

- `db/cache_schema.rb`：Solid Cache。
- `db/queue_schema.rb`：Solid Queue。
- `db/cable_schema.rb`：development／production 共用的 Solid Cable schema；兩個環境各連到自己的 cable database。

### `docs/research/06` §7 的 47 張具名表

以下名稱按領域分組；合計必須是 47，不能把 `sessions/api_tokens` 誤讀成單一表：

1. 租戶與身分（4）：`shops`、`staff_members`、`roles`、`role_permissions`。
2. 商品與系列（8）：`products`、`product_options`、`option_values`、`product_variants`、`media`、`collections`、`collection_products`、`collection_rules`。
3. 庫存（4）：`inventory_items`、`locations`、`inventory_levels`、`inventory_adjustments`。
4. 顧客（2）：`customers`、`customer_addresses`。
5. 交易、訂單與履約（11）：`checkouts`、`orders`、`line_items`、`order_transactions`、`fulfillment_orders`、`fulfillments`、`refunds`、`refund_line_items`、`events`、`discounts`、`discount_applications`。
6. 主題與內容（8）：`themes`、`templates`、`theme_settings`、`menus`、`menu_items`、`pages`、`files`、`notification_templates`。
7. 運費與稅（4）：`shipping_profiles`、`shipping_zones`、`shipping_rates`、`tax_settings`。
8. 擴充與事件（4）：`metafield_definitions`、`metafields`、`segments`、`event_outbox`。
9. Session 與整合 token（2）：`sessions`、`api_tokens`。

基線額外表（1）：`idempotency_keys`。它不是 `docs/research/06` §7 的第 48 個具名表，而是 `docs/specs/11` §2 要求的寫路徑冪等支援表。因此 M0 application migration 實際建立 48 張應用／業務支援表。

### `shop_id` 與索引規約

- 除 `shops` 外，上述 47 張 tenant tables（46 張規格表 + `idempotency_keys`）都由 `create_tenant_table` 建立，第一個顯式欄位固定為 non-null `shop_id`。
- 每張 tenant table 都有 `(shop_id, id)` unique tenant identity key；所有業務查詢與唯一索引經 `tenant_index` 建立，固定以 `shop_id` 開頭。
- 表間 business foreign key 同時包含 `shop_id`，防止把本店 child 指向外店 parent。
- `*_cents` 一律為 `bigint`；需顯示時才由 API／UI 轉成指定幣別格式，不在資料庫使用浮點數。

### 明確例外

1. `shops` 是 tenant root，本身就是 `shop_id` 指向的對象，因此不再帶自我參照 `shop_id`；其 `subdomain`、`custom_domain` 與 `status` 等索引是平台級查詢，亦不以 `shop_id` 開頭。
2. Rails metadata 表 `schema_migrations`、`ar_internal_metadata` 是 framework bookkeeping，不是業務表。
3. `solid_cache_entries`、`solid_cable_messages` 與 `solid_queue_*`（jobs、executions、processes、semaphores、recurring tasks 等）由官方 Solid schema 管理，承載基建狀態而非租戶業務資料，因此不帶 `shop_id`。業務 job 的 tenant 傳遞規約仍是第一個參數帶 `shop_id`；具體 job 在後續里程碑落地。

## 關鍵取捨與假設

1. **「約 40 張」採具名清單而非近似數字。** `docs/research/06` §7 實際列出 47 個表名，因此 M0 一次建立完整具名骨架；另加基線要求的 `idempotency_keys`。這避免後續里程碑先補表再重寫 tenant key。
2. **租戶隔離採三層防線。** Host middleware 決定 tenant、`acts_as_tenant` fail-closed、composite FK 在 DB 層兜底；外部 GID lookup 亦顯式附加 `shop_id`。
3. **自訂網域是 M0 簡化。** M0 僅把已通過驗證的 host 寫入 `shops.custom_domain`；獨立 `custom_domains` 表、CNAME 驗證 job、動態 TLS 與舊網域 301 屬 P1／M7。
4. **Admin API 從第一天版本化。** 即使 M0 只有 read-only 商品 query，SPA 仍只依賴正式 GraphQL endpoint；後續不需要從臨時 REST client 遷移。
5. **GraphQL cost 先建立契約邊界。** M0 有 request cost 上限與回應 envelope；完整 per-shop leaky bucket 與前端 THROTTLED 自動退避仍列為後續工作。
6. **品牌與上限不可散落。** `config/brand.yml` 與 `config/limits.yml` 是唯一來源；畫面、controller、GraphQL 不應再硬編碼同一常數。
   - 🔴 **`limits.yml` 的鍵一律必須是字串（2026-08-15 補）**：載入路徑是
     `ActiveSupport::ConfigurationFile.parse(...).deep_symbolize_keys`，而 Psych 走 **YAML 1.1**——
     裸字 `on`/`off`/`yes`/`no`/`true`/`false`（含大小寫變體如 `On`/`YES`）解析成布林、`~`/`null` 成 nil、
     `2026-08-15` 成 Date。**鍵**同樣適用這條規則，而 `deep_symbolize_keys` 對非字串鍵**原樣保留**
     （`true` 不能 `to_sym`）⇒ 載入不會炸，錯誤延到取值端才變成看不出根因的 `KeyError`。
     ⇒ **鍵名是這些字時必須加引號**（`"on":`）。實例：`gift_card_entry_points` 的 M27–M32 曾寫成
     `{ on: ... }`，六個鍵實際是 `true`。機制＝`scripts/check-limits-keys.rb`（見「測試與驗證」）。
     ⚠️ `Limits.fetch`（`app/models/limits.rb`）**缺鍵一律 raise**，這讓錯誤一定會炸而不是靜默拿 nil；
     但它的訊息是「缺少 limits.….M27.on 設定」，讀起來像**設定沒寫**，而檔案裡明明寫著 `on:`
     ⇒ 根因仍看不出來，這正是上述 CI 檢查存在的理由。
     ⚠️ `y`/`n` **不在此列**——YAML 1.1 規格含它們，但 Psych 5.2.2 實測不轉（Ruby 3.4.10，2026-08-15 取證）。
7. **Solid 基建與 business schema 分離。** development／production 都把 primary、cache、queue、cable 分開；test 則使用 deterministic test adapter。durable cache／queue／cable 不需要 Redis，基建表也不混入 business schema。
8. **法律與視覺。** UI 僅用 CHILL LOVE 自有 CSS tokens 與 Lucide；不使用 Polaris、Dawn/Horizon、Shopify CSS、資產或文案。
9. **Production base host fail-fast。** development／test 可用 `lvh.me` 快速驗收，但 production 不允許沿用 fallback；缺少或傳入空白 `CHILLLOVE_BASE_HOST` 時應用會在 boot 階段失敗，避免錯把正式 tenant routing 掛到開發網域。

## 啟動與 seeds

### 開發環境需求

- Ruby 3.4（Rails 8.1）
- MySQL 8
- Node.js 22.17.1（`.node-version` 與 CI 精確 pin；`package.json` 支援範圍為 `>=22.12 <23`）
- pnpm 11.16

建議首次啟動：

```bash
bundle install
pnpm install --frozen-lockfile
bin/setup --skip-server
bin/dev
```

MySQL host／port 在各環境可由 `DB_HOST`、`DB_PORT` 覆寫；development／test 的帳密使用 `DB_USERNAME`、`DB_PASSWORD`（預設 `127.0.0.1:3306` 與 root），production 則使用 `CHILLLOVE_DB_USERNAME`、`CHILLLOVE_DATABASE_PASSWORD`。`bin/dev` 透過 `Procfile.dev` 同時啟動 Rails、標準 Vite wrapper `bin/vite dev` 與 Solid Queue worker。

tenant URL 由 `CHILLLOVE_BASE_HOST` 決定。development／test 未設定時 fallback 為 `lvh.me`，例如 `http://demo.lvh.me:3000/login`；production 必須提供非空值，否則 application boot fail-fast。CI 的 production Vite build 使用 `ci.example.test` 只是 build-time placeholder，不是可部署網域設定。

### Seeds 狀態

`db/seeds.rb` 是可重跑的 M0 最小 seed：只在資料不存在時建立一間 active 示範店與一位 active owner，並刻意不建立商品，讓登入後可驗收商品空狀態。它在所有環境都是 create-only：既有 shop 的名稱、狀態與設定，以及既有 staff 的狀態、owner flag 與密碼，一律保留不覆寫；若找到的 shop 不是 active，會拒絕繼續建立 staff。

| 設定 | development 預設值 | 說明 |
|---|---|---|
| `SEED_SHOP_SUBDOMAIN` | `demo` | 示範店 subdomain |
| `SEED_SHOP_NAME` | `CHILL LOVE Demo` | 示範店名稱 |
| `SEED_ADMIN_EMAIL` | `owner@chilllove.test` | owner staff email |
| `SEED_ADMIN_PASSWORD` | 新建時為 `chill-love-demo` | 只供非 production 的新 owner；production 必填 |
| `SEED_DEMO_SHOP` | 無需設定 | production 必須明確設為 `1` 才允許建立 demo |

建立 development seed：

```bash
bin/rails db:seed
```

在全新 development DB 上，接著開啟 `http://demo.lvh.me:3000/login`，使用 `owner@chilllove.test`／`chill-love-demo`。若資料原已存在，seed 會保留既有密碼，不能假設固定開發密碼仍有效。這組預設帳密只允許本機 demo，不能用於 production。production 必須同時提供 `SEED_DEMO_SHOP=1` 與 `SEED_ADMIN_PASSWORD`，任一缺少都會立即 abort；正式密碼必須透過環境變數注入，不可提交到倉庫。

## 測試與驗證

### 自動驗證

現有測試／檢查覆蓋下列路徑：

- `spec/migrations/m0_core_schema_spec.rb`：47 個具名表＋冪等表＋4 張法域聯集表（含 🔴 einvoices 非唯一索引防回歸斷言）、`shop_id` 第一欄、tenant-prefixed indexes、composite FK（45 條）、integer cents、HK 基準預設值防回退。
- `spec/config/m0_configuration_spec.rb`：品牌單一來源、limits.yml 扁平結構、M0 代碼實際消費的 api／auth 鍵存在且型別正確（2026-08-13 由逐值複製斷言改寫）。
- `scripts/check-limits-keys.rb`（2026-08-15 新增，CI `quality` job）：斷言 `config/limits.yml` **每一層 mapping 的鍵都解析成 String**，擋住上面「關鍵取捨」#6 的 YAML 1.1 鍵陷阱。走 Psych AST 以報出**確切行號**；判定用 `node.to_ruby` 的實際型別（不自寫 YAML 1.1 字表）。**不檢查值的型別**、**偵測到 ERB 即 fail**（loader 會先 render ERB，本腳本讀原始檔，不擋就會 CI 綠燈而 runtime KeyError）——兩項限制寫在腳本檔頭的誠實聲明。
- `scripts/test-limits-key-rules.rb`（2026-08-15 新增，CI `quality` job）：上一支的回歸測試，**17 條 case / 11 個 fixture**（同一 fixture 可有多條斷言：行號一條、型別一條），fixture 在 `spec/fixtures/ci_violations/limits_*`。形態與理由同 `test-money-rules.rb`（65 §K.7 逐字：「**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有」）——判定邏輯被改壞時 `check-limits-keys.rb` 對乾淨倉庫仍會 exit 0，CI 全綠而它已什麼都不擋。

  | fixture | 期望 | 守什麼 |
  |---|---|---|
  | `limits_bool_key` | exit 1 | 裸字 `on` → TrueClass（M27–M32 踩過的原形態） |
  | `limits_false_key` | exit 1 | 🔴 裸字 `no` → FalseClass。**`no` 是挪威的 ISO 3166 代碼**，鐵律 11 的法域 pack 最可能踩到 |
  | `limits_nil_key` | exit 1 | 裸字 `~` → NilClass。**`null:` / `NULL:` 也在同一份 fixture 裡**（原本只有註釋斷言「同理」而沒有實測——與 y/n 那次同型）；實測 Psych 5.2.2 下四種寫法全部 → NilClass |
  | `limits_date_key` | exit 1 | 日期形鍵 → Date（生效日／匯率日結那類表） |
  | `limits_seq_key` | exit 1 | 🔴 布林鍵藏在 **sequence 裡的 mapping**（真實 limits.yml 有 17 處這種結構）；斷言用**帶索引的路徑** `rules.0.on` |
  | `limits_erb` | **exit 2** | ERB fail-closed（輸出型標籤） |
  | `limits_erb_tag` | **exit 2** | ERB fail-closed（**非輸出型**控制流標籤——與上一條是不同寫法） |
  | `limits_missing_target` | **exit 2** | 🔴 **fail-closed：TARGETS 列的檔不存在**。fixture 是一個**只有 README、沒有 `config/limits.yml`** 的目錄——本倉庫的 `config/limits.yml` 一直都在，這個分支在 CI 上永遠走不到，把 `exit` 改成 `next` 完全看不出差別 |
  | `limits_bad_yaml` | **exit 2** | 🔴 **YAML 本身壞掉也是「檢查跑不了」**。沒有 `rescue Psych::SyntaxError` 時，例外直接冒出去、Ruby 以 **exit 1 ＋ backtrace** 結束——而 1 的定義是「檢查跑了，發現違規」⇒ **退出碼會說謊** |
  | `limits_alias_key` | **exit 2** | 🔴 `*nope: 1`（不存在的錨點當**鍵**）。三件事同時繞過「只攔 `Psych::SyntaxError`」的寫法：解析**成功**、炸點在 `walk` 裡的 `to_ruby`（rescue 的外面）、類別是 `Psych::AnchorNotDefined`。⇒ 判準改成語義的：**checker 自己炸了就是沒檢查完，一律 2** |
  | `limits_clean` | exit 0 | 🔴 反向斷言。刻意含 `y`/`n` 鍵，同時守住「不得反過來加禁止裸字 y/n 的字面規則」；**另含一段字串鍵的 sequence**，守 Sequence 遞迴分支的**偽陽性**方向（`limits_seq_key` 只守真陽性） |

  🔴 **退出碼是三分的，不是 0/1**（2026-08-15 第 3 輪；這不是風格問題，是本表能不能守住的關鍵）：

  | 碼 | 意義 |
  |---|---|
  | 0 | 通過 |
  | 1 | **檢查跑了，發現違規**（鍵型別違規） |
  | 2 | **檢查跑不了**：TARGETS 列的檔不存在／檔內含 ERB／讀檔失敗／**YAML 解析或走訪時 checker 自己炸了**（一律 2，不逐一列舉例外類別） |
  | 3 | **檢查根本沒生效**：掃了 0 個檔（canary，無 fixture） |

  原因：`limits_missing_target` 守的 fail-closed 分支與 `scanned.empty?` canary
  **訊息都含 `TARGETS`**。若兩者同碼，把 fail-closed 的 `exit` 改成 `next` 之後，
  控制流會落到 canary，退出碼與關鍵字都一樣 ⇒ 該突變在測試裡是**存活的**（實測確認過）。
  只改斷言字串沒有用——第一句 warn 在 `next` 之前就印出去了。
  ⚠️ **canary 的 3 本身沒有測試在守**（`TARGETS` 是腳本常數，fixture 影響不到），
  把它改回 2 會讓上述突變重新存活。已知且刻意的缺口，見 worklog Pending 9。

  🔴 **`bool`/`false`/`nil`/`date`/`seq` 五個 fixture 各有兩條斷言**：一條斷言 `config/limits.yml:<行號> 鍵 \`…\``、一條斷言型別名。理由是第二輪突變測試（2026-08-15）發現**行號完全沒被守**——把 `start_line + 1` 改成 `start_line`、寫死 `1`、或不印 `rel:line` 前綴，三種改壞法在只斷言型別時全綠，而行號正是這支 checker 的實用價值（真實 limits.yml 一千多行）。
  ⚠️ **行號寫死在 `CASES` 裡 ⇒ 改動任一 fixture 的行數就必須同步改斷言**，這是刻意的耦合。

  🔴 **這張表是被突變測試打出來的**：初版只有 3 條（bool_key／erb／clean），把 checker 改壞成六種形態實測時**三種存活**（只認 TrueClass／刪掉 Sequence 遞迴／ERB 閘門收窄）。補完後 6/6 全抓到。**加新規則到 checker 時，先想「改壞它的哪一種寫法不會被抓」，那個答案就是要補的 fixture。**
- `spec/lib/chilllove/tenant_resolver_spec.rb`：subdomain／custom domain、未知 Host 404、5 分鐘 cache、ensure cleanup。
- `spec/requests/staff_authentication_spec.rb`：登入、統一錯誤、cookie、digest-only DB session、撤銷與第 11 次嘗試 429。
- `spec/models/staff_member_spec.rb`、`spec/models/session_spec.rb`：password／狀態、session 有效性與同租戶限制。
- `spec/graphql/products_contract_spec.rb`：HTTP 200 error、版本 header、GID、keyset cursor、跨店隔離、page limit 與 session 撤銷。
- `spec/system/m0_admin_shell_spec.rb`：staff 登入後看見 CHILL LOVE shell、商品空狀態與新增商品 CTA；可透過 `M0_SCREENSHOT_PATH` 選擇性輸出截圖。
- `app/frontend/admin/pages/ProductsPage.test.tsx`：商品頁載入、錯誤、空狀態與資料狀態。
- `.github/workflows/ci.yml`：MySQL 8.4 service、RSpec、frontend test/typecheck/build，以及 Ruby lint／security audit。

#### 已完成實測（2026-08-11）

| 驗證 | 結果 |
|---|---|
| MySQL 8.4 clean lifecycle：`db:drop` → `db:create` → `db:migrate` → `db:prepare` | 通過 |
| test DB：`db:rollback` → `db:migrate` | 通過；migration 可逆後可重新套用 |
| 實體表數 | primary 50（48 application + 2 Rails metadata）、cache 3、queue 13、cable 3；development／production runtime 都使用獨立 Solid Cable DB，test 使用 `test` adapter |
| tenant schema introspection | 47 張 tenant tables 的 `shop_id` 都是 ordinal 2（`id` 後第一個顯式欄位）；tenant tables 中非 `shop_id` 起首的業務索引為 0 |
| foreign keys | 90 條：47 條 tenant → `shops` FK + 43 條 tenant-safe composite FK |
| money schema | 30 個 `*_cents` 欄位全為 `bigint`；11 張 money tables 全有 currency 欄位 |
| generated unique sentinel probes | 重複 insert 均由 MySQL 拒絕，錯誤碼 `ERROR 1062` |
| cross-tenant composite FK probe | 跨租戶 parent link 由 MySQL 拒絕，錯誤碼 `ERROR 1452` |
| `db:seed` 重跑兩次 | 維持 `shops=1`、`staff_members=1`、`products=0`；符合 idempotent 與商品空狀態要求 |
| `bundle exec rspec` | 通過，49 examples／0 failures |
| M0 system spec | 通過，1/1；以真實 headless Chrome 完成 staff 登入、CHILL LOVE shell 與商品空狀態驗收 |
| system screenshot | 產生 `tmp/m0-admin-shell.png`，並已人工檢視驗收畫面 |
| `pnpm typecheck` | 通過 |
| `pnpm test` | 通過，Vitest 3/3 cases（空狀態、錯誤重試、資料表與搜尋空結果） |
| test／production frontend build | 兩個環境皆通過 |
| `RAILS_ENV=test bin/rails zeitwerk:check` | 通過，`All is good!` |
| `bin/rubocop` | 通過，70 files／0 offenses；machine-generated schema 與 M0 runtime 未載入的 Phase 1 PoC 明確排除 |
| `bin/brakeman --no-pager --exit-on-warn --exit-on-error` | 通過；掃描 5 controllers、12 models、5 templates，0 warnings |
| `bin/bundler-audit` | 通過；RubySec database 1,232 advisories，0 vulnerabilities |
| `pnpm audit` | 通過，0 vulnerabilities |

以上是整合端實際取得的結果；PR 的「自測結果」仍應保留 command 與 exit status，不能只引用本篇摘要。

### 手動驗收

成功 migration 與 seed 後：

1. 執行 `bin/rails db:seed` 與 `bin/dev`。
2. 開啟示範店 URL（例如 `http://demo.lvh.me:3000/login`）。
3. 以 `owner@chilllove.test`／`chill-love-demo` 登入，確認成功導向 `/admin`，且網址最終為 `/admin/products`。
4. 確認畫面顯示 CHILL LOVE topbar、sidebar 導覽、商品頁標題與「還沒有商品」空狀態。
5. 在 browser network 面板確認商品資料只由 `POST /admin/api/2026-08/graphql.json` 載入，帶同源 cookie 與 CSRF header，沒有 Admin REST 請求。
6. 確認 GraphQL response 為 HTTP 200，帶 `X-CL-API-Version: 2026-08` 與 `extensions.cost`。
7. 登出後重新存取 `/admin/products`，確認回登入頁；已撤銷 session 不可再使用。
8. 以未知 tenant Host 存取，確認回 404「找不到這間商店。」且不洩漏其他店資料。

## 已知限制與 TODO

- M0 seed 僅提供一間空的 demo 店與 owner；服飾商品、顧客、訂單與分析曲線等內容型示範資料不在本里程碑建立。
- M0 GraphQL 只有商品 read path；新增、編輯、刪除、bulk、media、variant diff 與 mutation `userErrors` 在 M1 實作。
- shell 中除商品外的頁面，以及「新增商品」／商品詳情路由，目前是後續里程碑 placeholder。
- 完整 cost leaky bucket、THROTTLED retry、API token 認證與 scopes 尚未實作；M0 只有 session-authenticated endpoint 與 request cost guard。
- `event_outbox` 與 `idempotency_keys` 已有 schema，但 dispatcher、webhook delivery 與可重用 idempotency service 尚待各寫路徑里程碑實作。
- staff invitation、password reset、2FA、owner transfer 與 audit log 不在 M0 實作範圍；其中 audit 能力需在對應里程碑補表與驗證。
- 自訂網域在 M0 以 `shops.custom_domain` 簡化；正式驗證、動態 TLS 與 redirect lifecycle 待後續里程碑。
- M0 browser system spec 已以真 Chrome 通過並人工檢視單張驗收截圖；尚未建立跨 viewport 的自動視覺回歸 baseline。
- `docs/specs/11` §5 的完整結構化日誌、錯誤上報、dashboard 與合成巡檢屬 M8；M0 僅保留 request／tenant context 與安全參數過濾地基。
- production 的備份、online DDL 演練、Kamal、TLS 與部署 runbook 屬 M7–M9，不因 skeleton 可在本機啟動而視為已完成。

## 變更記錄

- 2026-08-11（PR 待建立）：建立 M0 Rails／MySQL 地基、47 張規格表 + `idempotency_keys`、租戶與 staff 認證、版本化 Admin GraphQL、React shell 與本篇接手文檔。
- 2026-08-11（PR 待建立）：記錄 MySQL schema／constraint probes、idempotent seeds 與 frontend test、typecheck、build 實測結果；其餘驗證維持待跑。
- 2026-08-11（PR 待建立）：完整 RSpec 49/49 通過，含真 Chrome M0 system spec 1/1 與人工截圖驗收。
- 2026-08-11（PR 待建立）：RuboCop、Brakeman、RubySec 與 pnpm audit 全綠；production tenant base host 改為必填 fail-fast。
- **2026-08-13（移植輪，`m0/rails-foundation` 分支）**：骨架自舊平行歷史（`m0/rails-skeleton` @920ca7b）移植到現行 main，依 2026-08-12 之後的裁定改造——
  ① **HK 基準**（鐵律 11）：`shops.store_currency`／14 個 currency 欄位預設 TWD→HKD、timezone Asia/Taipei→Asia/Hong_Kong（migration＋schema＋seeds＋factory 同輪）；
  ② **法域聯集表**（06 §7.1，晚於骨架的規則）：新建 `einvoices`（🔴 不得對 (shop_id, order_id) 建唯一索引——全案唯一 schema 級上線後改不得的決定）、`einvoice_allowances`、`jurisdiction_capability_skips`、`contract_liability_entries`；`orders` 補 `seller_jurisdiction`／`buyer_jurisdiction` 雙法域快照欄（無 default）；tenant 表 47→51、composite FK 43→45；
  ③ **limits.yml 正典化**（鐵律 6/7）：廢棄骨架自帶的 58 行環境分層版，改用 main 的 41 區塊扁平版（`application.rb` 改扁平載入）；`GraphqlLimits` 鍵名對齊 `api:` 區塊正典名；`api:` 補 4 鍵（default page size＋cost 權重）、新增 `auth:` 登入限流區塊；rack_attack 與前端 first:50 硬編碼外移；
  ④ **文檔快照不回流**：骨架內嵌的舊版 CLAUDE.md／HANDOFF.md／AGENTS.md／docs/**（缺鐵律 3 五小條、鐵律 11、specs 65/58）一律以 main 現行版為準，僅本篇隨遷並修訂金額敘述改引 65 號；
  ⑤ **CI 強化**：`db:prepare` 改 `db:create db:migrate`＋`git diff --exit-code db/schema.rb`（schema.rb 係於無本機 MySQL 環境手工同步，此步為其機械驗證）；
  ⑥ ⚠ **2026-08-11 的實測結果表對移植後版本尚未重跑**——本輪環境無 MySQL，全部驗證以 CI 為準，綠了才可合併。`spec/config/m0_configuration_spec.rb` 已改寫為「代碼消費契約」斷言（原逐值複製斷言在 limits.yml 正典化後＝第二份資料副本）。
- **2026-08-15（`m1/limits-yaml-key-types` 分支，PR #33）**：修 `limits.yml` 的 YAML 1.1 布林**鍵**陷阱——
  `jurisdictions.hk.accounting.gift_card_entry_points.M27..M32` 的裸字 `on` 鍵實際是 `true`（全檔非 String 鍵剛好 6 個），
  加引號改為 `"on":`；新增 `scripts/check-limits-keys.rb` 並掛進 CI `quality` job。
  本篇同輪更新兩處：「關鍵取捨與假設」#6 補鍵契約、「自動驗證」補該腳本。
  ⚠️ 初稿把 `y`/`n` 也寫成會轉布林，經兩個驗收方各自指出並複驗（Ruby 3.4.10／Psych 5.2.2）後更正——
  Psych 5 不轉 `y`/`n`，該說法只對 YAML 1.1 **規格**成立。
