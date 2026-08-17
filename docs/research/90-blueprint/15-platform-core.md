# 15. 平台核心（多租戶 / Plans / RBAC / API 平台 / Custom Data）

> 考掘基準：Shopify Admin API **2026-07**（倉庫 28 號釘死的對齊版）＋ help.shopify.com 現行文檔。
> 所有規則性斷言均附來源（G 節），取證日 2026-08-14。官方查不到者標 ⚠ 並列入 openQuestions，不作事實陳述。
> 本章與倉庫既有裁定（specs/85 A 案、CLAUDE.md 鐵律、28 號 API 契約）的差異全部集中在 F 節。

---

## A. 領域物件模型

### A.1 物件總表

| 物件 | 關鍵欄位 | 歸屬與 cardinality |
|---|---|---|
| **Organization**（組織） | id、name、owner（唯一 1 人） | 1 Organization ⊃ N Shop；2026 版所有店都掛在組織下（單店＝單店組織）；Plus 才有跨店集中管理/org 級自訂角色 |
| **Shop**（店＝租戶） | id、`myshopifyDomain`（全平台唯一）、`primaryDomain`、`plan{displayName, partnerDevelopment, shopifyPlus}`、currencyCode、ianaTimezone、billingAddress | 1 Organization : N Shop；一切業務資料的隔離主體 |
| **Domain** | host、sslEnabled、是否 primary | 1 Shop : N Domain；恰 1 個 primary；恰 1 個 myshopify.com（終身綁定，改名限 1 次） |
| **User**（使用者） | email（組織內唯一身分）、狀態、安全登入方式 | 1 Organization : N User；User N:M Shop（透過商店指派）；同一人可在多組織各有身分 |
| **Role**（角色） | name ≤255、description ≤255、category（4 選 1）、permission set | User N:M Role（一人可持多角色，且可跨類別持有）；角色內權限**不得跨類別混合** |
| **Permission** | key、群組、父子依賴、sensitive 旗標 | Role N:M Permission；商店類別共 115 權限／17 群組／3 層（倉庫 81 §1.4 實測窮舉） |
| **User Group**（Plus） | name、roles、members | User N:M Group；Group N:M Role——完整鏈是「使用者↔群組↔角色↔權限」四段 |
| **Collaborator** | partner 帳號、per-store 權限、90 天閒置過期 | 外部 Partner 對單店的存取關係；不佔 staff 名額 |
| **AccessToken / App** | scopes（`read_*/write_*` 成對）、API 版本 | 1 Shop : N app 安裝；rate limit bucket 以 app×shop 為粒度 |
| **WebhookSubscription** | topic、endpoint、filter | 1 Shop : N；metaobject 三 topic 自 2024-07 起**必帶 filter** |
| **BulkOperation** | id、status（7 態）、url、partialDataUrl、objectCount、errorCode | 2026-01+ 每 app 每 shop 同時最多 **5 個 query 型**；舊版每型 1 個 |
| **MetafieldDefinition** | name、namespace、key、type、description、validations、access、capabilities、pinned | 以 (ownerType, namespace, key) 唯一（本尊單店語境；我方＝shop_id 前綴，見 F 節 2026-08-17 更正（PR #52 第 7 輪））；ownerType 值域見 A.3 |
| **Metafield**（值） | namespace、key、type、value（一律字串存取） | 掛在 owner 資源上；(owner, namespace, key) 唯一 |
| **MetaobjectDefinition** | type（`$app:xxx` 或自訂前綴）、fieldDefinitions ≤40、capabilities、access | 1 定義 : ≤1,000,000 entries |
| **Metaobject**（entry） | handle（URL 友善、自動生成可改）、fields、status | 可被 metafield reference 引用；可經 online_store capability 生成前台頁 |

### A.2 身分模型要點（2026 組織層 RBAC）

- 擁有人是**內建角色**：store owner（每店恰 1）與 organization owner（每組織恰 1）**不出現在可管理角色清單**，不可刪、權限不可剝奪。
- Shopify 管理角色 12 個＋predefined roles 7 個＋自訂角色；角色類別 4 種：Organization／Store／POS／Partner。類別可用性受方案限制（org 自訂角色限 Plus；Store 需 Basic 以上；POS 需 POS Pro 地點）。
- 名額計數：只有「一般 staff」計入方案上限；store owner、organization owner、collaborator（無上限）、POS-only（無上限、PIN 登入、需 POS Pro）**皆不計**。

### A.3 MetafieldOwnerType 值域（26 值，窮舉）

`API_PERMISSION, ARTICLE, BLOG, CARTTRANSFORM, COLLECTION, COMPANY, COMPANY_LOCATION, CUSTOMER, DELIVERY_CUSTOMIZATION, DISCOUNT, DRAFTORDER, FULFILLMENT_CONSTRAINT_RULE, GIFT_CARD_TRANSACTION, LOCATION, MARKET, ORDER, ORDER_ROUTING_LOCATION_RULE, PAGE, PAYMENT_CUSTOMIZATION, PRODUCT, PRODUCTVARIANT, SELLING_PLAN, SHOP, TRANSFER, VALIDATION`＋`MEDIA_IMAGE`（deprecated）。〔G-14，取證 2026-08-14〕

### A.4 GID 慣例

- 基本：`gid://shopify/{Type}/{id}`；帶參數形態：`gid://shopify/InventoryLevel/123?inventory_item_id=456`（子物件需父 id 才唯一時，用 URL query string）。
- 實作 Relay `Node` 介面者可用 `node(id:)/nodes(ids:)` 取回；物件另有 `legacyResourceId` 對映 REST 數字 id，REST 側對應 `admin_graphql_api_id`。〔G-6〕

---

## B. 狀態機

### B.1 店鋪生命週期（7 態，無孤兒）

狀態全集：`trial`（試用中）→ `trial_expired`（試用到期未選方案，凍結）／`active`（付費營運）／`pause_and_build`（暫停建置）／`frozen`（欠費凍結）／`deactivated`（關閉，資料保留 2 年）／`purged`（逾 2 年，終態）。

| # | From → To | 觸發 | 前置條件 | 副作用 |
|---|---|---|---|---|
| 1 | trial → active | 選方案＋綁付款 | 試用期內或到期後皆可 | 試用內升級**不縮短試用、不提前收費** |
| 2 | trial → trial_expired | 試用到期未選方案 | — | 店被凍結直到選方案；**不會自動扣款** |
| 3 | trial_expired → active | 選方案 | — | 資料原封保留 |
| 4 | active → pause_and_build | owner 在 Settings > Plan 切換 | owner 本人；**已完成試用**；在付費方案上；**Plus 不可** | 全通路 checkout 停用（含 POS）；折扣、棄單挽回、禮品卡、三方通路停用；draft order 可寄 invoice 但**無法完成結帳**；admin 可編輯、前台可瀏覽、基本報表保留；**app 續留且照常收費** |
| 5 | pause_and_build → active | 重選付費方案 | 「舊方案已失效」，必須選**新**方案 | 恢復 checkout |
| 6 | active → frozen | 帳單到期日未付（含多次扣款失敗） | — | **admin 不可進、前台不可見**；僅 owner 與有 finance 權限者可看帳單歷史；所有計費嘗試暫停 |
| 7 | frozen → active | owner 補繳全部欠款（含凍結期 app 費、交易費、運費標籤費） | 距上期帳單 ≥30 天者**須另選新方案**並付下期訂閱 | 解凍生效最多 30 分鐘 |
| 8 | active/pause_and_build → deactivated | owner 主動關店 | owner；Plus 店須走 Plus Support；未償 app 用量費**立即請款** | 全部 app 自動解除安裝；自訂網域斷開；HSTS 政策殘留 90 天；顧客仍可經升級後的 Thank you/Order status 頁查訂單；chargeback 仍可能發生（抗辯需先復店） |
| 9 | deactivated → active | 2 年內登入→選方案→綁卡→Subscribe | 2 年保留期內 | 自訂網域須重新連接；`myshopify.com` 網域沿用原有 |
| 10 | deactivated → purged | 逾 2 年 | — | 資料保證失效（終態）；該 `myshopify.com` 網域**永不可**給新店重用 |

⚠ frozen 店若永不繳費，官方**未載明**自動轉 deactivated 的期限——文檔語義是「無限期凍結直到付款或主動關店」。〔G-16〕
⚠ Pause and Build 月費官方 help 未載明數字（僅稱 reduced fee）；多個第三方一致記載 US$9/月，僅供參考不作事實。

### B.2 使用者邀請／存取（staff 與 collaborator）

**Staff**：`invited`（邀請信，**有效 7 天**）→ `active` ⇄ `suspended`（暫停即無法登入，該人信用卡自動鎖定）→ `removed`（終態；**需輸入操作者自己的密碼**（step-up auth）、不可復原、相關信用卡自動取消）。
- 邀請過期的官方處置＝**移除該使用者重新新增**；官方**沒有**「重寄／取消邀請」獨立操作。〔倉庫 81 §7.7；help staff 邀請頁〕
- 進不去的孤兒態不存在：invited 過期→removed（重加）；suspended 可 reactivate。

**Collaborator**：`code_generated`（owner 產生 4 位數 request code，重新產生即舊碼作廢）→ `requested`（Partner 憑碼送出申請；**必須有碼**）→ owner 於 Users 區 `approved`（指派 role/權限，可限定特定 app 與 channel）或 `rejected` → `active` → **閒置 90 天自動 `expired`** → owner 可 `reactivated`。Collaborator 不可取得 POS 存取、不可被授 Administrator／Store user administrator 角色。〔G-20〕

### B.3 BulkOperation（7 態，官方 enum 窮舉）

`CREATED → RUNNING → COMPLETED | FAILED | CANCELING → CANCELED`；`COMPLETED →（url 逾 1 週）→ EXPIRED`。

| 轉移 | 觸發／規則 |
|---|---|
| — → CREATED | `bulkOperationRunQuery`（或 RunMutation）受理；驗證失敗走 userErrors 不建立 |
| CREATED → RUNNING | 排程啟動；查詢限制：**最多 5 個 connection**、巢狀 connection **最深 2 層**、connection 必須實作 Node、禁 top-level `node/nodes` |
| RUNNING → COMPLETED | 產出 JSONL 於 `url`（**簽名 URL、1 週後過期**）；每行一個 node 物件，巢狀展平、自動附 `__parentId` 指回父物件 |
| RUNNING → FAILED | `errorCode ∈ {ACCESS_DENIED, INTERNAL_SERVER_ERROR, TIMEOUT}`；**超過 10 天強制停止標記 failed**；可能留 `partialDataUrl` |
| CREATED/RUNNING → CANCELING → CANCELED | `bulkOperationCancel`；取消有延遲窗 |
| COMPLETED → EXPIRED | 結果 URL 逾期（enum 明載此態） |

併發上限：**2026-01 起每 app 每 shop 可同時跑 5 個 query 型 bulk**；更早版本每型（query/mutation）各 1。完成通知：訂閱 `bulk_operations/finish` webhook（官方註明**送達不保證**，仍應輪詢 `bulkOperation(id:)`／舊 `currentBulkOperation` 的 status＋objectCount）。〔G-4、G-5〕

### B.4 API 版本生命週期

`release_candidate →（季度日）→ stable →（12 個月後）→ retired`；另有長期存在的 `unstable`。
- 節奏：**每季一版**（1／4／7／10 月），發版時刻 17:00 UTC；命名 `YYYY-MM`。
- 支援窗：每 stable 版**至少 12 個月**；相鄰版本**至少 9 個月重疊**。
- retired 版被呼叫＝**fall forward**：以「最舊的仍支援 stable 版」回應，回應 header `X-Shopify-API-Version` 標實際服務版本。
- 棄用：欄位在所有支援版同時標 `@deprecated`，於後續版移除，最少 9 個月預告；溝通管道＝API health report、GraphiQL 警告、developer changelog、參考文檔、緊急聯絡信。持續用已棄用資源的公開 app 會被下架＋至少 7 天禁新裝。〔G-1〕

### B.5 Metaobject entry（publishable capability）

具 `publishable` capability 的定義，其 entries 帶 status：`DRAFT ⇄ ACTIVE`（草稿不對 storefront 曝光）。⚠ 官方概覽頁僅列 capability 名稱，DRAFT/ACTIVE 值取自 API schema（`MetaobjectStatus`），本輪未逐頁取證該 enum 頁——列 openQuestions。

### B.6 店鋪轉讓（ownership transfer）

`initiated`（現 owner 於 Settings 發起，**需 re-authenticate**）→ `pending_acceptance`（新 owner 收 email）→ `completed`（新 owner 確認；可選擇併入其既有組織／建新組織／獨立接收）。
- 兩條路：**組織內既有使用者**（Settings > Users > 該使用者 > Change ownership；org owner 與 store owner 分開轉）；**外部新 owner**（Settings > General > Organizations and store transfers）。
- 阻斷條件：**Plus 店不可自助轉讓**（走 Plus Support）；有 **Shopify Capital／Shopify Credit** 未結清不可轉；**Shopify Balance** 須先清空帳戶；組織僅剩一店時轉走該店＝組織消滅。
- 副作用：舊 owner 失去 owner 權限（帳務/付款區不可見）；未達 billing threshold 的未出帳款**由新 owner 承擔**。〔G-19〕

---

## C. 業務規則與不變量

### C.1 租戶與網域

1. `myshopify.com` 網域全平台唯一、與店終身綁定；**改名限 1 次**；店關閉後該網域**永不重用**。〔G-24、G-17〕
2. primary domain 唯一，顧客看到的是它；國際化網域（依 market 的 subfolder／獨立網域）Basic 以上可用。
3. 我方（12 號 spec）：以 `request.host` 解析租戶，禁用任何自報 shop 參數作授權依據；subdomain regex `\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z`＋約 50 個保留字黑名單——這是我方工程規則，本尊無對應公開文檔。

### C.2 Plans 階梯與 feature gating（值域表）

| 維度 | Starter | Basic | Grow | Advanced | Plus | 來源 |
|---|---|---|---|---|---|---|
| 一般 staff 名額 | 0 | **0** | 5 | 15 | 無限 | 倉庫 81 §7.6（help）；Pause and Build＝1 |
| 有效 locations | 2 | 10 | 10 | 10 | **200** | G-25 |
| 三方金流加收費 | — | 2% | 1% | 0.6% | 0.2% | 倉庫 05 §3 |
| 商家自建 metaobject 定義 | — | 128 | 128 | 128 | **256** | G-10 |
| GraphQL restore rate | — | 100 pt/s | 100 pt/s | 200 pt/s | 1000 pt/s（Commerce Components 2000） | G-2 |
| REST bucket／leak | — | 40／2 rps | 40／2 | 40／2 | **400／20** | G-3 |
| 變體建立日限 | （50 萬變體以上大店）10,000/日，**Plus 豁免** | | | | | G-2 |
| org 自訂角色／User Groups | — | — | — | — | Plus 專屬 | 倉庫 81 §7.3/§7.8 |
| Pause and Build 可用性 | — | ✓ | ✓ | ✓ | **✗** | G-15 |

其他 gating（carrier-calculated shipping、checkout 客製、B2B、關稅 DDP 等）屬各業務域章節，此處不重複。

### C.3 RBAC 不變量（與 81 號實測互證）

1. **單類別約束**：一個 role 的權限不得跨類別混合（官方明文）；但一個 user 可同時持多個不同類別的角色。
2. **依賴圖非樹**：授予子權限⇒**自動勾選全部祖先**；其中兩條**不可取消**（Inventory 任一權限→Products>View；Catalogs 任一→Products>View）；Content/Products/Online store→Files 的自動勾選**可事後取消**；取消被依賴的權限⇒**所有依賴它的權限自動取消**（雙向傳播）。無任何互斥對。
3. 角色表單：name ≤255、description ≤255、**至少一項權限**；建立/變更角色與移除使用者皆觸發 **step-up auth**（重輸密碼）。
4. Sensitive permissions 共 7 條（Customers>Request data、Finance>Edit billing…、Finance>Manage other payment settings、Business entities>View sensitive info、Partner>View financials、Partner>Manage credits and refunds、POS>Manage other payment settings）——help 僅給最小授予建議，無強制授予閘門。
5. Owner 特權不可剝奪；權限真相只在 server（我方 12 號：Pundit `verify_authorized` 全掛）。

### C.4 API 平台計算規則

**GraphQL cost 公式**（逐欄位加總）：
```
cost(scalar)=0; cost(enum)=0; cost(object)=1; cost(mutation)=10（基礎）
cost(interface|union)=max(各可能 selection 的 cost)
cost(connection)=依 first/last 參數比例計（每個 edge 攤入子樹成本）
requestedQueryCost = 預估上限（先預扣）；actualQueryCost = 執行後結算（退還差額）
```
- **單請求上限 1,000 points**（執行前擋下，超過即 `MAX_COST_EXCEEDED`）。
- 節流：桶內 `currentlyAvailable < requestedQueryCost` ⇒ HTTP 200＋`errors[].extensions.code="THROTTLED"`；每個回應附 `extensions.cost{requestedQueryCost, actualQueryCost, throttleStatus{maximumAvailable, currentlyAvailable, restoreRate}}`。
- 等待公式（client 端自救）：`wait_seconds = (requestedQueryCost − currentlyAvailable) / restoreRate`，無 rounding 要求（浮點秒）。
- ⚠ 官方 limits 頁只載 **restore rate**（100/200/1000/2000 pt/s 四級）；bucket 上限（`maximumAvailable`）官方頁未列表——標準店實回 2,000（＝restore×20），其他級距的 bucket 值本輪未逐級取證，列 openQuestions。
- **REST（legacy，2024-10-01 起）**：leaky bucket 40 req/app/store、leak 2 rps；Plus 400／20 rps；header `X-Shopify-Shop-Api-Call-Limit: 32/40`；超限 HTTP 429＋`Retry-After` 秒數。
- 通用：**輸入陣列一律 ≤250 items**；分頁 `first/last` ≤250（倉庫 28 已釘；**具名例外**：connection 側 `customerSegmentMembers` ≤1,000/頁（§08 A.2）與 `product.variants` root connection 單商品一次 2048（§01 A／G1）；輸入陣列側 `productVariantsBulkCreate` ≤2048（§01 A／G7）（2026-08-17 更正，PR #52 第 10 輪；variants 兩例外補列第 11 輪））；連線式分頁越過 **25,000 物件**後 count 回報封頂為「25,001」。
- Storefront API：對買家流量**無 rate limit**；bot 需 Web Bot Auth 簽名否則受限。〔G-2、G-3〕

### C.5 Custom Data 不變量（值域與上限窮舉）

**Metafield 定義上限**〔G-9、G-11，2025-10-20 起〕：

| 項 | 上限 |
|---|---|
| 每 app 每 resource type 定義數 | 256（⚠️ docs 頁 128 vs changelog 256 兩源矛盾未定案；另一判讀＝該 changelog 256 實為商家定義 Plus 檔位值（總綱 §8 矛盾表）——兩判讀並存待 Q-93（2026-08-17 更正，PR #52 第 11 輪）） |
| 商家自建每 resource type 定義數 | 128（Basic/Grow/Advanced）／256（Plus+）——與本章 G-10 正表一致，全 256 為誤植（待 Q-93 （2026-08-17 更正，PR #52 第 9 輪）） |
| Pinned 定義每 resource type | 50 |
| 值大小（多數型別） | 64KB |
| 值大小：`json` | 128KB（2026-04-01 前既有 app 祖父條款 2MB） |
| 值大小：`id`、`url` | 2KB |
| single_line_text 預定義 choices | ≤128 個 |
| list 型別項數 | ≤128（`list.metaobject_reference` 例外 ≤256） |
| Functions 讀取 | 值 >10,000 bytes 時 Functions 收到 null（Admin API 仍可讀） |
| Smart collection 條件可用定義 | 128 |
| Admin 列表篩選可用定義 | 50（Products/Companies/Company Locations/Metaobjects）；**Orders 僅 5** |
| `metafieldsSet` 單次 | ≤25 筆，atomic（倉庫 28 §12） |

**Metaobject 上限**〔G-10、G-11〕：每定義 **≤40 fields**、**≤1,000,000 entries**（舊制 64k/128k 已廢）；商家定義數 128（Basic/Grow/Advanced）／256（Plus/Enterprise）；app 定義數 docs 頁載 128、changelog（2025-10-20）載 256——**兩源矛盾未定案**；另一判讀＝該 changelog 256 實為**商家定義的 Plus 檔位值**（總綱 §8 矛盾表同條），兩判讀並存待 Q-93（2026-08-17 更正，PR #52 第 11 輪）：原「以較新 changelog 為傾向」與檔位判讀互斥，撤傾向語；標準（standard）定義與 entries 不計入上限。

**型別系統**：基礎＋計量型別共 53 種（boolean/color/date/date_time/json/language/link/money/multi_line_text_field/number_decimal/number_integer/rating/rich_text_field/single_line_text_field/url/id＋37 種帶單位計量型）；reference 12 種（article/collection/company/customer/file/metaobject/mixed/order/page/product/product_taxonomy_value/variant）；`list.` 變體 52 種（**不支援 list 的**：boolean、id、json、language、money、multi_line_text_field、rich_text_field）。單位 enum 逐型窮舉見來源頁〔G-7〕。要點：
- GraphQL 讀寫時 **value 一律是字串**，型別只決定驗證與解析。
- `number_integer` 值域 ±9,007,199,254,740,991；`number_decimal` ±9999999999999.999999999。
- `rating` 必帶 min/max validations；計量型值＝`{value, unit}` JSON。
- 型別建立後**不可改**；namespace/key/ownerType 不可改；name/description/validations/access 可改（validations 受限）。
- 不相容的型別遷移會使既有值失效；任何型別不可遷移為 `id`。

**存取控制 enum**〔G-12、G-13〕：

| 面向 | 值域 | 預設 |
|---|---|---|
| Admin（app-owned） | `MERCHANT_READ` / `MERCHANT_READ_WRITE` | MERCHANT_READ |
| Admin（merchant-owned） | 恆為完整讀寫，不可配置 | — |
| Storefront API | `NONE` / `PUBLIC_READ` | NONE |
| Customer Accounts API | `NONE` / `READ` / `READ_WRITE` | NONE |
| Liquid 模板 | **不受 storefront access 管**：metafield 在 Liquid 永遠可讀 | — |

保留 namespace：`$app`（app 私有，TOML 裡寫 `app`）、`custom`（商家自建預設）、`shopify`（標準定義）。

### C.6 稽核（activity logs）

- **Store activity log**：只顯示**最多 250 筆**、view-only、**不可匯出**、不可點開單筆；記錄例：刪商品、改設定、授權 app、出貨、庫存同步、上架通路、theme 修改、金流設定變更、刪 staff。檢視需 `Home`＋`Store settings > Manage settings` 兩權限。〔G-21〕
- **User management activity log**（Settings > Users > Security）：獨立記錄使用者/角色的建立、編輯、刪除與登入事件，比主 log 詳細。〔G-22〕

### C.7 Sessions 與 2FA

- 2FA 方法值域（4 種）：SMS 一次性碼／authenticator app（TOTP）／實體 security key／裝置內建 authenticator（passkey 類）；另有 recovery codes 與備援方法。
- 強制情境：**Shopify Payments 收款必須開 2FA**；Plus 組織可全組織強制（「所有使用者皆必要」，不適用 POS）；Shopify 對高風險帳號可單方面強制且「適用期間不可關閉」。
- Staff 的 2FA 只能**本人**設定，owner 不能代開。〔G-23〕
- ⚠ admin session 存續時間、裝置管理清單的官方規格未公開——列 openQuestions。

### C.8 資料匯出入（CSV 家族）

- Product CSV：UTF-8＋LF、首行 header；新增必填 `Title`，對既有品加變體必填 `URL handle`；變體＝同 handle 多行、最多 3 個 option；**每品 ≤250 張圖**（公開 https URL，禁 `_thumb/_small/_medium` 後綴，alt ≤512 字元）；「Overwrite products with matching handles」開啟時**空白欄會清掉既有值、省略欄保留**——匯入語義是欄級 merge/overwrite 二擇一。〔G-26〕
- 其他官方 CSV：inventory（多地點）、customers、discounts、users（81 號：使用者匯出入）。⚠ CSV 檔案大小上限（常被引為 15MB）本輪取證頁未載明。

---

## D. 關鍵流程

### D.1 開店（provision）
1. 註冊 → 建 Organization＋Shop＋owner user＋`myshopifyDomain` → 進入 `trial`。
2. 試用中可完整建店（trial 長度官方稱「依情況而異」，見 shopify.com/free-trial）。
3. 選方案綁卡 → `active`；到期未選 → `trial_expired` 凍結，**不自動扣款**。
失敗分支：subdomain 撞名→重試；我方（12 號）：全程單 transaction＋唯一索引兜底防殭屍店。

### D.2 邀請 staff／collaborator
Staff：owner/使用者管理員發邀請（email＋roles）→ 邀請信 7 天有效 → 受邀者接受→ `active`。失敗分支：過期→移除重加（官方無 resend）；名額不足（Basic 0）→ 要求升級方案。
Collaborator：owner 產碼（4 位數）→ Partner 憑碼申請 → owner 審核（可看 partner 帳齡、活躍協作數、註冊地）→ 核准並指派角色 → `active`；90 天閒置自動過期。

### D.3 店鋪轉讓
見 B.6。操作者＝現 owner；系統動作＝re-auth → 寄確認信 → 移轉 owner 角色與帳務責任；失敗分支＝Capital/Credit/Balance 未清、Plus 店、新 owner 不接受（維持原狀）。

### D.4 欠費凍結與復活
帳單到期未付 → `frozen`（admin＋storefront 全關）→ owner 登入唯一入口＝繳清全部欠款 → ≥30 天者加選新方案 → 30 分鐘內解凍。

### D.5 關店（deactivate）
前置：處理未結 gift card／訂閱訂單、關 Shopify 網域自動續費或轉出三方網域、盤點 app 外部扣款。執行：owner 確認 → app 全解除安裝＋未償費用立即請款 → `deactivated`。之後：2 年內可復店；HSTS 殘留 90 天；chargeback 仍可能來。

### D.6 Bulk 匯出
`bulkOperationRunQuery(query)` → CREATED/RUNNING → 訂 `bulk_operations/finish`＋輪詢兜底 → COMPLETED 取 `url`（1 週失效）→ 逐行讀 JSONL、用 `__parentId` 重建父子。失敗分支：FAILED（10 天超時／ACCESS_DENIED／INTERNAL_SERVER_ERROR）→ 讀 `partialDataUrl` 決定重跑範圍；同時 >5 個 query 型 → userErrors 拒收。

### D.7 Metafield 定義與寫值
`metafieldDefinitionCreate(ownerType, namespace, key, type, validations, access)` →（唯一性：**shop_id**+ownerType+namespace+key——本尊單店語境隱含 per-shop，我方多租戶必須顯式，2026-08-17 更正（PR #52 第 7 輪））→ `metafieldsSet`（≤25 筆 atomic，支援 `compareDigest` 樂觀鎖）→ 值驗證按 type＋validations。失敗分支：超定義上限 256／值超型別大小上限／validations 不符 → userErrors；型別遷移不相容 → 既有值 invalidated。

### D.8 API 版本升級（商家側 app／我方 SDK）
每季 diff 新版 schema → 檢查 API health report 的棄用清單 → 9 個月窗內完成遷移；retired 版呼叫被 fall-forward，以 `X-Shopify-API-Version` 回報實際版本（監控此 header 是升級失察的最後警報）。

---

## E. 跨模組耦合

### E.1 發出的事件（webhook topics，平台核心相關）
- `shop/update`（店設定變更）、`app/uninstalled`、`domains/create|update|destroy`、`bulk_operations/finish`、`metaobjects/create|update|delete`（**2024-07 起必帶 filter 指定 type，不再用 sub-topic**）。
- 隱私三件套（GDPR 級，所有 app 必須處理）：`customers/data_request`、`customers/redact`、`shop/redact`。
- 完整值域見 `WebhookSubscriptionTopic` enum〔G-27、G-28〕。

### E.2 依賴方向
- **一切業務域依賴租戶解析**（shop 上下文）；平台核心不依賴任何業務域。
- Plans gating 橫切所有域（staff 名額、locations、rate limit、metaobject 上限、功能開關）——gating 判斷集中於 plan 層，業務域只查 capability，不自查方案名。
- Custom Data 被 themes（Liquid 恆可讀）、Storefront API（僅 PUBLIC_READ）、admin 列表篩選、smart collections、Flow、Functions（>10KB 得 null）消費。
- Rate limiter 前置於整個 Admin API 面；bulk 與 webhook 是它的兩個洩壓閥（官方建議超量讀寫走 bulk）。
- 稽核 log 消費所有域的變更事件（append-only）。

### E.3 我方事件對應（outbox）
訂單成立／退款／庫存調整必帶 `idempotencyKey` 且走 outbox（CLAUDE.md 鐵律 5）；平台核心自身要進 outbox 的事件：shop 建立/方案變更/凍結/關店、staff 邀請/停用/移除、角色與權限變更、metafield definition 變更、bulk 完成。

---

## F. 落地對應

### F.1 倉庫既有文檔對應

| 本章節 | 倉庫對應 |
|---|---|
| A.2/C.3（RBAC） | `docs/research/81` §1/§7（115 權限窮舉、依賴圖、step-up auth）；`docs/specs/12` F3 |
| A.2（組織層身分） | `docs/specs/85`（**A 案已裁**：身分表升組織層＋`user_store_assignments`＋fail-closed helper） |
| B.1（店鋪狀態機） | `docs/specs/12` F1（provision）；方案/凍結/關店流程為**本章新補**，M1 後建 `shops.status` 時引用 |
| B.3/C.4（API 平台） | `docs/research/28` §0.1–0.6（版本、cost、bulk、冪等——28 為準，本章補官方值域） |
| C.5（Custom Data） | `docs/research/28` §12；`docs/research/05` §1f |
| C.2（Plans） | `docs/research/05` §3；`docs/research/81` §7.6/§7.13 |
| C.6–C.8 | `docs/specs/12` F2/F3（session、稽核）；`docs/research/81` §1.7/§3 |
| 上限值落地 | 一律進 `config/limits.yml`（鐵律 6），本章所有數字不得硬編碼 |

### F.2 本尊 vs 我方裁定（逐條）

| # | 本尊原貌 | 我方裁定 | 依據 |
|---|---|---|---|
| 1 | 金額以 decimal string（MoneyV2.amount）流通 | 內部全程 **integer cents ×100**，序列化層才轉 MoneyV2/MoneyBag；PSP 依 pack 宣告格式 | 鐵律 3、specs/65 |
| 2 | 稅務憑證（發票等）內建於結帳/訂單 | **jurisdiction pack**（基準法域 HK＝無憑證；tw pack 承載統一發票） | 鐵律 11 |
| 3 | `gid://shopify/{Type}/{id}` | `gid://chilllove/{Type}/{id}`，其餘 GID 慣例照抄（含 legacyResourceId） | 28 §0.3 |
| 4 | 季度版本＋12/9 個月窗、fall-forward | demo 期**單版本**（`2026-08`），窗口制度規格佔位；`X-CL-API-Version` header 先行 | 28 §0.1 |
| 5 | rate limit 按方案分級（100–2000 pt/s） | demo 全店統一 **bucket 2,000／restore 100 pt/s**（＝本尊標準級） | 28 §0.4 |
| 6 | REST Admin API（legacy）並存 | **不做 REST**，admin SPA 只打 GraphQL（API-first） | 鐵律 4 |
| 7 | bulk 為真非同步（JSONL、簽名 URL） | demo **同步分批**實作、契約不變（狀態機/JSONL/`__parentId` 照抄） | 28 §0.5 |
| 8 | 冪等：官方 17 支強制清單 | 加嚴：另強制 9 支金流 mutation＋回放由 DB 重建（不存快照）、TTL 24h | 28 §0.6 |
| 9 | userErrors.code 部分 mutation 才有 | 加嚴：**全部 mutation 一開始就上 typed code enum** | 28 §0.3.2 |
| 10 | 身分：組織層 users，email 全平台單帳號 | **A 案對齊本尊方向**；但業務資料表保留 `(shop_id,id)` 複合鍵與複合外鍵，身分層失去的 DB 隔離以 `Current.accessible_shop_ids` fail-closed helper＋CI 檢查補償 | specs/85 |
| 11 | 邀請 7 天過期、無 resend | 我方傾向做 resend（重寄＝舊 token 作廢）——**R12-V8 未結案**，若做即為超集 | 81 §7.7、12 F3 |
| 12 | 權限樹：help 扁平 19 群 vs 實測巢狀 17 群 | **UI 採實測 17 群樹、語義採 help 描述**（R12-DOC1） | 81 §7.1 |
| 13 | metafield type 全量 53＋12 ref＋52 list | 首發 **15 種**（28 §12），schema 設計預留全量擴充 | 28 §12 |
| 14 | 多幣顯示依市場 locale | 同（`HK$1,480`、tabular-nums、不硬編符號） | 鐵律 10 |
| 15 | Plans 商業模式（月費×費率互鎖） | 我方 plan 表先建 gating 骨架（staff 名額/locations/上限），定價不抄 | 05 §3 |
| 16 | subdomain 命名規則未公開 | 自訂 regex＋約 50 保留字黑名單＋改名 301 | 12 F1 |

### F.3 開發驗收要點

1. **店鋪狀態機**：B.1 的 10 條轉移各有測試；不得出現「凍結店可打 API」「pause 店可完成 checkout」；`trial_expired` 與 `frozen` 的差異（前者無欠款）要分開建模。
2. **RBAC**：權限依賴圖（含 2 條不可取消邊）做成資料而非 if-else；勾子補祖先／撤父連鎖撤子各有單元測試；role 單類別約束在 DB constraint＋validation 雙層；step-up auth 覆蓋角色 CUD 與使用者移除。
3. **限流**：cost 計算對 object/scalar/connection/mutation 各有測試；THROTTLED 回應含完整 `extensions.cost`；單請求 1,000 上限先於執行。
4. **Custom Data**：C.5 每個上限進 `config/limits.yml`；值驗證按 type 矩陣測（含 64KB/128KB/2KB 邊界、list 128/256、choices 128）；**(shop_id, ownerType, namespace, key)** 唯一索引（值＝(shop_id, owner_id, namespace, key)；無 shop_id 前綴＝跨租戶全域唯一＋違反鐵律 2，2026-08-17 更正（PR #52 第 7 輪））；type 不可變更以 migration 級測試鎖住。
5. **雙店隔離**：85 號 A 案落地後，身分表的跨店測試改斷言「A 店 session 不能解析出 B 店資源」，業務表仍走 12 F4 的 404 斷言。
6. **稽核**：250 筆顯示上限是**本尊 UI 行為**，我方 append-only 表不設保留上限（法遵留存），僅列表分頁模仿。

---

## G. 來源（全部取證 2026-08-14）

| # | URL | 用途 |
|---|---|---|
| G-1 | https://shopify.dev/docs/api/usage/versioning | 季度版本、12/9 個月窗、fall-forward、棄用政策 |
| G-2 | https://shopify.dev/docs/api/usage/limits | GraphQL cost 公式、restore rate 四級、1,000 上限、輸入陣列 250、25,000 分頁封頂、變體日限 |
| G-3 | https://shopify.dev/docs/api/admin-rest/usage/rate-limits | REST 40/2、Plus 400/20、429/Retry-After、legacy 起始日 |
| G-4 | https://shopify.dev/docs/api/usage/bulk-operations/queries | bulk 限制、JSONL、`__parentId`、URL 1 週、10 天超時、5 併發 |
| G-5 | https://shopify.dev/docs/api/admin-graphql/latest/enums/BulkOperationStatus | 7 態 enum 窮舉 |
| G-6 | https://shopify.dev/docs/api/usage/gids | GID 格式、參數化 GID、legacyResourceId |
| G-7 | https://shopify.dev/docs/apps/build/custom-data/metafields/list-of-data-types | 型別全量與單位 enum、值域 |
| G-8 | https://shopify.dev/docs/apps/build/custom-data/metafields/definitions | 定義構成、保留 namespace、可改欄位表 |
| G-9 | https://shopify.dev/docs/apps/build/metafields/metafield-limits | 定義 256、pinned 50、值大小、list、capability 上限 |
| G-10 | https://shopify.dev/docs/apps/build/metaobjects/metaobject-limits | metaobject 40 fields/1M entries/方案定義數 |
| G-11 | https://shopify.dev/changelog/increased-limits-for-metafields-and-metaobjects | 2025-10-20 上限調升（256/256/1M） |
| G-12 | https://shopify.dev/docs/apps/build/custom-data | 三情境 access enum、擁有權三分 |
| G-13 | https://shopify.dev/docs/apps/build/custom-data/permissions | access enum 與預設、Liquid 恆可讀 |
| G-14 | https://shopify.dev/docs/api/admin-graphql/latest/enums/MetafieldOwnerType | ownerType 26 值窮舉 |
| G-15 | https://help.shopify.com/en/manual/your-account/manage-orgs-and-stores/manage-pricing-plan/pause-store | Pause and Build 資格與停用面 |
| G-16 | https://help.shopify.com/en/manual/your-account/manage-billing/billing-charges/frozen-store | 凍結觸發、封鎖面、解凍條件、30 天規則 |
| G-17 | https://help.shopify.com/en/manual/your-account/manage-orgs-and-stores/manage-pricing-plan/deactivate-store | 關店前置、2 年保留、HSTS 90 天、網域不可重用 |
| G-18 | https://help.shopify.com/en/manual/intro-to-shopify/pricing-plans/free-trial ＋ /FAQ | 試用長度「varies」、到期凍結不扣款 |
| G-19 | https://help.shopify.com/en/manual/your-account/manage-orgs-and-stores/change-transfer-ownership | 轉讓兩路徑、阻斷條件、副作用 |
| G-20 | https://help.shopify.com/en/manual/your-account/staff-accounts/collaborator-accounts | 4 位數碼必要、審核流、90 天過期、不佔名額 |
| G-21 | https://help.shopify.com/en/manual/shopify-admin/activity-logs | 250 筆、view-only、不可匯出、所需權限 |
| G-22 | https://help.shopify.com/en/manual/your-account/users/security/user-management-activity-log | 使用者管理獨立 log |
| G-23 | https://help.shopify.com/en/manual/your-account/account-security/two-step-authentication | 2FA 4 方法、強制情境 |
| G-24 | https://help.shopify.com/en/manual/domains | myshopify 改名限 1 次、primary domain |
| G-25 | https://help.shopify.com/en/manual/fulfillment/setup/locations | locations 2/10/200 |
| G-26 | https://help.shopify.com/en/manual/products/import-export/using-csv | CSV 格式、250 圖、overwrite 語義 |
| G-27 | https://shopify.dev/changelog/new-webhook-topics-added-for-metaobject-events | metaobject topics 需 filter（2024-07） |
| G-28 | https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic | topic 全量值域入口 |

倉庫內部引用：`docs/research/05`、`docs/research/28`、`docs/research/81`、`docs/specs/11`、`docs/specs/12`、`docs/specs/85`、`CLAUDE.md`。
