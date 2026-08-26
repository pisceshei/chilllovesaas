# 28 — 全項目 API 契約（服務端 ↔ 商家端 ↔ 前台）

> **D5 決策落地文件**：整個項目 API 化——admin React SPA 與服務端之間**只走 GraphQL Admin API**（1:1 仿 Shopify 慣例）；買家前台走 **Liquid SSR＋Ajax/Section Rendering HTTP 面**（25 §5）；事件出口走 **Webhooks**。本文＝三個面的完整契約：§0 慣例（照抄 Shopify 工程慣例，經官方文檔查證）→ §1–14 逐模組操作表 → §15 webhooks → §16 前台面 → §17 三端對接矩陣。欄位級細節在 specs 12–19 與 22 號按鈕表；本文是「有哪些介面、輸入輸出什麼、遵守什麼規則」的單一真相。

## 0. API 慣例（1:1 仿 Shopify，來源：shopify.dev 版本/認證/GID/分頁/限流/bulk/webhooks 章）

### 0.1 端點與版本
- Admin GraphQL：`POST /admin/api/{version}/graphql.json`，version＝日期制 `YYYY-MM`（首版 `2026-08`）。回應 header `X-CL-API-Version` 標實際服務版本（fall-forward 語義佔位）。schema 演進用 `@deprecated(reason:)`。

> 🔴 **對齊基準版＝Shopify Admin API `2026-07`**（2026-08-15 釘死）。
> 「2026 春季版」＝ Spring '26 Edition，官方發布日 **2026-06-17**，其 API 面落地版本是
> **2026-07（＝目前 latest）**，**不是 2026-04**——兩者確有實質差異
> （例：ShopifyQL 的 `returns*` 系列 2026-04 仍在、2026-07 已移除）。
> 本文的 **enum 值清單**與**冪等白名單**是**版本綁定**的，升版時必須逐項 diff。
>
> 🔴 **查證方法的陷阱（踩過一次，寫下來）**：shopify.dev **只保留最近四個 stable 版**的
> schema 文檔，而 `/2024-01/`、`/2025-01/` 這類舊路徑會**靜默回傳 latest 內容且不報錯**
> （實證：`/2024-01/mutations/productCreate` 自報 `api_version 2026-07`，
> 並顯示 2024-10 才引入的 `product: ProductCreateInput`）。
> ⇒ 任何「2022-01／2024-01／2025-01 逐字相同 ⇒ 跨版本一致」的結論**都是假證據**，
> 一律降級為「查不到」。可查證窗口目前是 **2025-10／2026-01／2026-04／2026-07／unstable**。
> 另：官方自 **2025-04 起停發 API release notes**（最後一份是 2025-01），
> 版本差異只能靠 schema 頁逐項比對。
- demo 期單版本；版本窗口目標（12 個月支援、9 個月重疊）寫入規格待商業化執行。

### 0.2 認證與授權
- **Admin SPA**：登入 → session cookie＋CSRF（同源 BFF 模式）；**API token**（機器整合）：`clat_` 前綴長效 token，header `X-CL-Access-Token`。（Session-token JWT 交換為 v2。）
- **Scopes**：`read_{resource}/write_{resource}` 成對蛇形複數，逗號字串。首發 10 對：products, orders, customers, inventory, fulfillments, discounts, themes, content, markets, translations（＋`read_analytics`、`read/write_settings`）。staff 角色（12 號 spec）映射為 scope 集合。
- 受保護資源（60 天訂單窗口、payment methods）：規格佔位，demo 不啟用。

### 0.3 GraphQL 核心慣例（全部照抄）
- **GID**：`gid://chilllove/{Type}/{id}`；主要物件實作 `Node`，支援 `node(id:)/nodes(ids:)`；物件帶 `legacyResourceId`。
- **分頁**：connection `first/after/last/before`＋`pageInfo{hasNextPage,hasPreviousPage,startCursor,endCursor}`；**每頁上限 250**；優先查 `nodes` 而非 `edges`；cursor＝base64(排序鍵+id) 不透明。
- **Mutation**：命名 `resourceVerb`（productCreate/orderCancel）；payload＝`{ <0..N 個 resource 欄位>, userErrors: [X!]! }`——**業務錯誤走 userErrors（HTTP 200）**，top-level errors 只承載 syntax/THROTTLED/ACCESS_DENIED/INTERNAL（附 requestId）。宣告式 upsert 用 `*Set`（metafieldsSet/productSet）。

<!-- 🔴 2026-08-15 本尊考掘（Admin API 2026-07 逐頁查證）：本行原文有**四處**與本尊不符，
     全部改寫於下方 §0.3.1–§0.3.4。原文：
     「input object `{Mutation}Input`；payload＝`{ resource, userErrors: [{field: [String],
       message: String!, code: Enum}] }`……**一開始就上 typed code enum**。」
     四處分別是：①`field` 的 nullability 寫反 ②`{Mutation}Input` 命名規則已落後本尊兩年
     ③payload 寫死「一個 resource」 ④「typed code enum」被寫成慣例，實際上是我方加嚴。 -->

#### §0.3.1 `userErrors.field` 的型別與路徑（🔴 全部照抄本尊）

- **型別＝`[String!]`**（list 可為 null、元素非 null）。
  出處：`shopify.dev/docs/api/admin-graphql/latest/interfaces/DisplayableError` 的 SDL
  逐字 `interface DisplayableError { field: [String!]  message: String! }`。
  ⚠️ 本文原本寫 `[String]`（元素可空）是**寫反了**。graphql-ruby 的對應寫法是
  `field :field, [String], null: true`——寫成 `[String, null: true]` 才會渲染成 `[String]`。
- **`input:` 這層外殼要剝掉**：mutation 參數是單一 `input: XInput!` 時，
  path 從 input object 的內層欄位名起算。
  出處：`/mutations/productDelete` 的官方錯誤範例逐字
  `{"field": ["id"], "message": "Product does not exist"}`——參數是 `input: ProductDeleteInput!`、
  id 住在 `input.id`，回的是 `["id"]` **不是** `["input","id"]`。
  ⇒ `docs/specs/63` §A.4 的 `field: ["lockVersion"]` **與本尊一致，不需要改**。
- **具名參數會進 path**：`productVariantsBulkCreate(productId:, variants:)` 的錯誤回
  `["productId"]`、`["variants","0","optionValues","0"]` ⇒ 參數名是第一段。
  ⚠️ **只有名為 `input` 的參數被剝殼**這條規則，是由上述三個官方實例歸納的；
  「`productCreate(product: {title: ""})` 回 `["product","title"]` 還是 `["title"]`」
  **沒有官方範例可證**，登記為假設（見 §0.3.5）。
- **陣列索引＝十進位裸字串段**，與其他段平鋪在同一個一維陣列，
  不用括號、不用 JSONPath、不用 `$` 前綴；path 也允許**終止於索引段**。
  出處：`["variants","0","metafields","0","value"]`、`["variants","0","optionValues","0"]`。
  🔴 **不得**與 Checkout Validation Function 的 `target: "$.cart.deliveryGroups[0]..."` 混用，
  那是另一個介面的另一套語法。
  ⇒ `docs/specs/63` 第 717 行的 `field: ["compareQuantity"]` **要改**——單段寫法同時丟了
  層級與索引，多筆一起送時前端無法定位是第幾筆。
- **無法歸屬到任何欄位時 `field` 回 `null`**，不回 `[]`。
  出處：`/mutations/draftOrderComplete` 的官方錯誤範例逐字 `"field": null`；
  全站查不到任何 `"field": []` 的官方範例。

#### §0.3.2 `userErrors.code`（🔴 **ours：加嚴，非照抄**）

- **本尊的泛用 `UserError` 沒有 code**，只有 `field`／`message`；
  `DisplayableError` interface 也沒有。`/enums/UserErrorCode` 回 **404** ⇒ 無共用 base enum。
  官方 build guide 教的選取形狀逐字只有 `userErrors { field message }`。
- **我方一律有 code**，理由：admin SPA 是唯一客戶端，錯誤分支必須機器可判別；
  且本尊自己也在逐支遷往 typed error（留著無 code 的舊型別是相容包袱，不是設計偏好）。
  ⇒ 這是「往本尊正在走的方向走完」，但**必須標為 ours**。
- **enum 的 GraphQL 形狀照抄本尊：一個 UserError object type 對應一個專屬 enum**
  （`PageDeleteUserErrorCode` 只有 1 個值、`PageCreateUserErrorCode` 8 值、
  `PageUpdateUserErrorCode` 9 值——同資源三支 mutation 三個獨立 enum）。
  **偏離的只有值域紀律**：我方強制各 enum 的值從共用池取（見 §6），
  因為本尊自己就有 `PRESENT`／`PRESENCE`（語義甚至相反）、
  `NOT_FOUND`／`RECORD_NOT_FOUND`／`*_DOES_NOT_EXIST` 三種拼法的分歧——
  那是二十年演進的產物，我方沒有相容包袱不需要繼承。
- 🔴 **`CONFLICT` 不得泛用化成樂觀鎖碼**：本尊的 `CONFLICT` 只存在於 `DiscountErrorCode`，
  語義是「折扣屬性選擇互相衝突」的**輸入驗證**，與樂觀鎖無關。
  樂觀鎖用 **`STALE_OBJECT`**、庫存 CAS 用 **`CHANGE_FROM_QUANTITY_STALE`**。
- **不採用 `elementIndex`**：本尊對陣列元素錯誤有兩種做法（索引編進 field ／ 另立
  `elementIndex: Int`，見 `MetafieldsSetUserError`），而**本尊自己沒把任一種做成全域鐵律**
  （`ProductSetUserError` 就只有 code/field/message）。②的並存語義官方從未定義，
  照抄等於抄一個語義未定的欄位 ⇒ 我方統一走索引編進 field。**此偏離只減不加**。

#### §0.3.3 payload 形狀

- **`userErrors: [X!]!` 是唯一必備欄位**（非空 list of 非空；成功時 `[]` 而非 `null`）。
- **resource 欄位數量下限是 0**（純副作用 mutation 只有 userErrors），上限是 N
  （多資源 ＋ `Shop!` ＋ `Job` ＋ async operation）。
  ⇒ BaseMutation **不得**把「一個 resource 欄位 ＋ userErrors」寫死成契約。
- **資源參數的 nullability 逐 mutation 決定**，BaseMutation 不得寫死：
  `productSet(input: ProductSetInput!)` 必填，但 **`productCreate(product: ProductCreateInput)` 是 nullable**
  （因為 deprecated 的 `input: ProductInput` 仍在 schema 裡共存，兩個互斥參數不可能同時 non-null）。
- **沒有 `clientMutationId`**（payload 與 input object 兩側都沒有）
  ⇒ 我方 BaseMutation 必須繼承 `GraphQL::Schema::Mutation`，
  **不得**用 `GraphQL::Schema::RelayClassicMutation`（後者會自動注入該欄位）。
- **棄用遷移形態**：本尊把 mutation 遷往 typed error 的手法是
  **在 payload 加一個新名字的欄位、把舊的標 deprecated 並保留**，不是改 `userErrors` 的型別
  （改型別會破 schema 相容）。例：`orderCancel` 的 `orderCancelUserErrors` 與 deprecated 的 `userErrors` 並存。

#### §0.3.4 input object 命名與參數風格（🔴 本文原規則已落後本尊兩年）

- 原文「input object 一律 `{Mutation}Input`」已不成立。本尊自 **2024-10** 起把
  `ProductInput` 拆成 `ProductCreateInput`／`ProductUpdateInput`，
  參數名改為 `product:`／`identifier:`＋`product:`，舊 `input:` 標 deprecated 保留。
- **新寫的 mutation 走具名參數**：資料本體 → input object；目標 → 獨立 ID scalar；
  行為策略 → options/strategy；附屬資源 → 獨立 list。

#### §0.3.5 `warnings`（成功但要提醒）——🔴 **ours：Admin 側新增，形狀照抄 Storefront**

- **Admin GraphQL 沒有 warnings 欄位**（`/objects/CartWarning` 在 Admin 命名空間回 **404**；
  抽樣 7 個 payload ＋ 3 輪站內搜尋皆無）。本尊唯一的先例在 **Storefront Cart**。
- 我方 `docs/specs/63` §L-9 需要一個「成功但要提醒」的位置（重複 SKU 放行但提醒），
  而**塞進 `userErrors` 會被前端當成失敗**（違反鐵律 4）。
- ⇒ 形狀 **100% 照抄 Storefront `CartWarning`**：`{ code: Enum!, target: ID!, message: String! }`
  ——三欄全非空，空時回 `[]`。
  🔴 **不得自創 `field` 欄位、不得丟掉 `target`**：那樣就變成自創語義而不是搬用既有機制。
- 本尊對重複 SKU 是**靜默行為**（無錯誤也無提醒）；我方判定靜默合併是可用性缺陷 ⇒ 這是加嚴。

#### §0.3.6 假設清單（本節唯一沒有官方範例的一條）

- ⚠️ **具名參數形下的多段 path**：官方只有單段 `["productId"]`、剝殼後的 `["id"]`、
  以及 `["variants","0",...]`。「剝殼規則只針對名為 `input` 的參數，還是針對所有單一資料本體參數」
  沒有官方範例可證。我方採**只剝 `input`**（三個官方實例都相容）。
  補證方式＝拿真實 Admin API token 打三發（productDelete 壞 id／productCreate 空 title／
  productVariantsBulkCreate 多筆其一壞），把 field 陣列原樣抄回本節。
- **標量**：`DateTime`（ISO8601 UTC）、`Date`、`Decimal`（字串）、`URL`、`HTML`、`JSON`；金額一律 **`MoneyV2{amount: Decimal, currencyCode}`**，多幣雙記 **`MoneyBag{shopMoney, presentmentMoney}`**（29 §3）。內部儲存仍 integer cents，序列化層轉 Decimal 字串。
- **陣列型 input 上限 250**。

### 0.4 限流（cost 制）
- 計費：object=1、scalar=0、connection=按 first 計、mutation 基礎=10；**單請求上限 1,000 points**（超過 `MAX_COST_EXCEEDED`）。
- Leaky bucket：預扣 requestedQueryCost、結算 actualQueryCost 退差額；demo 全店統一 **bucket 2,000 / restore 100 points/s**。
- 節流回應：HTTP 200＋`errors[0].extensions.code="THROTTLED"`；每個回應附 `extensions.cost{requestedQueryCost, actualQueryCost, throttleStatus{maximumAvailable, currentlyAvailable, restoreRate}}`——**前端 SDK 依此自主節流**。
- 前台 Ajax 面：IP＋cart token 滑動窗（15 §規格）；429＋Retry-After。

### 0.5 Bulk operations（規格保留、demo 簡化）
契約保留 `bulkOperationRunQuery/RunMutation`＋狀態機 `CREATED→RUNNING→COMPLETED|FAILED|CANCELED`＋JSONL `__parentId` 格式＋`bulk_operations/finish` topic；demo 以同步分批實作，介面不變。

### 0.6 冪等
寫入型 mutation 一律收 `idempotencyKey`；**強制清單見 `config/limits.yml` 的 `idempotency.required_for`**（含 Shopify 自 2026-04 起強制的 17 個 mutation，以 refund／inventory 為主，缺 key **執行期報錯**；另加本專案強制的 `returnProcess`、`orderCancel`、`orderEditCommit`）。

**本專案另強制的 10 支金流 mutation（55 號盤點補齊；`refundMarkAsSettled` 第 24 輪隨 16 §F5 落地格增列）**：`orderCapture`、`orderMarkAsPaid`、`draftOrderComplete`、`giftCardCreate/Credit/Debit/Deactivate`、`storeCreditAccountCredit/Debit`、`refundMarkAsSettled`。平台域另有 `required_for_platform`（`platformEinvoiceVoid`、`platformEinvoiceAllowanceCreate`）。

**🔴 這 10 支的強制冪等是「法域無關」的**（`limits.idempotency.jurisdiction_scope: core_all_packs`；含第 25 輪增列的 `refundMarkAsSettled`——線下退款確認是核心金流動作，COD 的法域素材（56 號 tw pack）不改變此鍵的 core 歸屬）——金流寫入點是「錢動了」，與賣方有沒有稅務憑證制度無關；在 hk／tw／任何未來 pack 下**完全相同**，**不得**搬進 `jurisdictions.*`。
**⚠ 但平台域那 2 支相反：它們是 pack-scoped 的**（`required_for_platform_pack_scope: jurisdictions.tw.tax_invoice`）。兩者都是台灣統一發票的專屬 mutation，基準法域 HK 下**根本不存在於 schema**（56 §A.4 CI-3）。CI 對未啟用 tw 的部署要斷言的是「這兩支不存在」，**不是**「這兩支要帶 key」——照 `required_for` 的方式做成無條件斷言，HK 首發的 schema 快照測試會直接紅掉。
<!-- 依 56 §E 分流，原 55 §D 結論：G-08「9 支金流 mutation 未列強制冪等」。
     依 56 §E，G-08 標為「**與法域無關，完整適用**」——本輪複核**確認此分流正確**，9 支一條不減。
     57 §G-08 補上的是 56 未涵蓋的一點：`required_for_platform` 的 2 支**不是**法域無關的，
     它們隨 tw pack 存廢。這一點在 56 §E.1 的 G-08 列與 §A.4 的 CI-3 之間掉了縫。 -->
**第二層業務唯一鍵**（`limits.idempotency.business_unique_keys`）：冪等 key 的 TTL 只有 24 小時（46a:789），但「同一張 fulfillment 只能請款一次」是**永久**約束——凡列於該表者，除冪等 key 外還要有業務唯一索引兜底。
<!-- 依 docs/specs/55 §A（金流寫入點總表 41 條）、§D G-08 補寫。原文只列了「官方 17 個 ＋ 我方 2 個」——
     官方清單是「Shopify 自己的金流寫入點」，**不涵蓋我方自己的**（禮品卡、抵用金、手動請款、標記已付、草稿轉單）。
     50/52/54 三輪都只抄官方清單，從未反向盤點「我方哪些路徑會動錢」；54 號的 NP1-D（orderEditCommit）
     只補了其中一支，這裡是同一個系統性缺口的其餘 9 支。判定標準沿用 NP1-D：**凡金流寫入一律強制冪等**。 -->

| 項 | 規定 | 出處 |
|---|---|---|
| TTL | **24 小時**，逾期同 key 重試視為**全新操作** | 46a:789、46a:1006 |
| 回放 | 🔴 **由當前 DB 狀態重建回應**（重載 `result_ref` ＋ 重跑 serializer），**不存回應快照** | 46a:791、46a:1009 |
| 參數指紋 | canonical_json（**物件 key 遞迴排序**後）→ SHA256；欄位順序會影響指紋 | 46a:793、46a:816 |
| 錯誤碼 | `IDEMPOTENCY_CONCURRENT_REQUEST`（退避後**用同一把 key** 重試）／`IDEMPOTENCY_KEY_PARAMETER_MISMATCH`（同 key 不同參數） | 46a:763–764、46a:1010–1011 |
| Bulk | **每個 JSONL row 一把獨立 key，絕不共用** | 46a:1015 |
| key 格式 | 互動 UUID v4/v7；排程 **UUID v5**（namespace + job 參數） | 46a（S47/S48） |

<!-- 依 46a:781–794、46a:1000–1016 修正，原文見上表。
     🔴 此處原本寫錯：本節原寫「重複 key 回首次結果」＋ 11:45–48 存 `response_body` 原樣回放，
     與官方「constructed from current database state」語義相反。完整規格見 docs/specs/11 §2.1。任何人翻舊版都不要改回去。 -->

**⚠ 待查證（來源未載明）**：冪等 key 的長度／字元格式硬性限制（46a §6⑤ 未載明）。

## 1. 商品線（read_products/write_products）

| 類別 | Queries | Mutations |
|---|---|---|
| 商品 | `products(first, query, sortKey)`, `product(id)`, `productByHandle` | `productCreate(input{title, descriptionHtml, vendor, productType, tags, status, seo, options})`, `productUpdate`, `productDelete`, `productDuplicate(newTitle, includeImages)`, `productSet`（upsert 全樹）, `productChangeStatus(ACTIVE\|DRAFT\|ARCHIVED)` |
| 變體 | product.variants | `productVariantsBulkCreate/Update/Delete/Reorder(productId, variants[]{options, price, compareAtPrice, sku, barcode, inventoryPolicy, inventoryItem{tracked, cost}})`——**diff 更新語義**（22 §2：改選項矩陣時保留既有變體資料） |
| 選項 | product.options | `productOptionsCreate/Update/Delete/Reorder` |
| 媒體 | product.media | `productCreateMedia(media[]{originalSource, alt, mediaContentType})`, `productUpdateMedia`, `productDeleteMedia`, `productReorderMedia`, `productVariantAppendMedia/DetachMedia` |
| 搜尋語法 | `query:` 支援 `title:* status:active vendor:X tag:Y created_at:>date`（22 §1 檢視列） | — |

規則：handle 自動生成＋唯一化（13 號）；`query` 與 `sortKey` 需同欄位（大集合逾時保護）；media 上限 250/商品（limits.yml）；userErrors code 例：`HANDLE_TAKEN`、`VARIANT_LIMIT_EXCEEDED`（2048）。

## 2. 系列與發佈

| 類別 | Queries | Mutations |
|---|---|---|
| 系列 | `collections`, `collection(id)`, `collectionByHandle` | `collectionCreate(input{title, descriptionHtml, image, ruleSet{appliedDisjunctively, rules[{column, relation, condition}]}, sortOrder, seo})`, `collectionUpdate`, `collectionDelete`, `collectionAddProducts`, `collectionRemoveProducts`, `collectionReorderProducts(moves)` |
| 發佈 | `publications` | `publishablePublish/Unpublish(id, publicationIds)`（online store／POS／市場 catalog 皆是 publication——與 29 §1.3 銜接）｜🔴 **2026-08-26 S1 補**：`publicationCreate(input)`、`publicationUpdate(id, input)`、`publicationDelete(id)` |

規則：智慧系列規則變更 → 背景重算 membership（Solid Queue，5000 上限）；手動系列 position 排序。

🔴 **發佈線的三條契約細節**（2026-08-26 S1 落地，全文＝`docs/dev/m2-publication-lifecycle.md`）：

1. **參數形態刻意不照 §0.3.4 的具名參數**：本尊 publication 線至今仍是舊式
   （`publicationCreate(input:)`、`publicationUpdate(id:, input:)`、`publicationDelete(id:)`），
   鐵律 12 的 1:1 對齊優先。⚠️ 連帶後果：create／update 的 `userErrors.field` path 第一段是
   `input`，**delete 是 `id`**（本尊 delete 沒有 input object）。
2. 🔴 **`publishablesToAdd`／`publishablesToRemove` 是累加／扣除，不是宣告式全量**
   ——與本檔同節的 `collectionCreate/Update`（`productSet` 家族）語義**相反**。
   實測依據＝`docs/research/82-admin-channels.md` §11.5。
3. **批次上限取「合計」是 ours 加嚴**：官方兩句措辭不同且都未指明切分（各自 vs 合計）
   ⇒ fail-closed。上限值引 `config/limits.yml` 的 `sales_channels.publication_bulk_products_max`。
   超限碼取共用池的 `TOO_BIG`（**不自創 `LIMIT_EXCEEDED`**，§0.3.2 的值域紀律）。

## 3. 庫存與地點（read_inventory/write_inventory）

| 類別 | Queries | Mutations |
|---|---|---|
| 庫存 | `inventoryItem(id)`, `inventoryLevel(參數化 GID ?inventory_item_id=&location_id=)`, `inventoryProperties` | `inventoryAdjustQuantities(input{reason, name(available\|on_hand), changes[{delta, inventoryItemId, locationId, ledgerDocumentUri}]})`, `inventorySetQuantities(setQuantities[], reason, compareQuantity 樂觀鎖)`, `inventoryItemUpdate(tracked, cost, countryCodeOfOrigin, harmonizedSystemCode)`, `inventoryActivate/Deactivate` |
| 地點 | `locations`, `location(id)` | `locationAdd/Edit/Deactivate` |

規則：一切變動走 **ledger**（06 §5 恆等式：`on_hand = available + committed + unavailable`，`incoming` 獨立不計入 on_hand）；併發用 compareQuantity CAS；`ledgerDocumentUri` 關聯單據。

<!-- 依 46c:608–617、46c:891–927 修正，原文：官方調整原因**七項**（更正〔預設〕/盤點/已收件/退貨重新入庫/損壞/遭竊或遺失/促銷或捐贈）；
     庫存頂層五態（現有/可販售/已分配/不可販售/待入庫）＋ unavailable 四子分類。
     🔴 此處原本寫錯：`reason` 枚舉原寫「correction/received/sold/returned/damaged…」——未列滿七項，且含官方**沒有**的 `sold`
     （出庫由 fulfillment 事件表達，不是調整原因），與 22:81 的清單也不一致。任何人翻舊版都不要改回去。 -->
- `name` 參數的量測面：`available` / `on_hand` / **`unavailable`** / **`incoming`**（四個實體欄位，見 13-F5.1）。
- `reason` 枚舉＝`limits.inventory.adjustment_reasons` **七項**：`correction`（預設）/ `count` / `received` / `return_restock` / `damaged` / `theft_or_loss` / `promotion_or_donation`。
- 狀態間移動（如「移至安全庫存」「草稿保留」）走 `inventoryMoveQuantities`，ledger 帶 `from_state` / `to_state`。
- **訂單草稿保留庫存進 `unavailable[draft_reserved]`，不是 `committed`**（46c:546–549）。

## 4. 訂單線（read_orders/write_orders）

| 類別 | Queries | Mutations |
|---|---|---|
| 訂單 | `orders(first, query, sortKey, **return_status 可篩**)`, `order(id)`（金額全 MoneyBag；timeline events connection） | `orderUpdate(note, tags, email, shippingAddress)`, `orderClose/Open`, **`orderCancel(orderId: ID!, reason: OrderCancelReason!, restock: Boolean!, notifyCustomer: Boolean, staffNote: String, refundMethod: OrderCancelRefundMethodInput) → { job{id,done}, orderCancelUserErrors }`**（**非同步**）, **`orderMarkAsPaid(idempotencyKey!)`**, **`orderCapture(amount, parentTransactionId, idempotencyKey!)`** |
| 訂單編輯 | **`order.editSession`**、**`calculatedOrder(id)`**（暫存區：`lineItems`／`addedLineItems`／`shippingLines{stagedStatus}`＋即時重算後的金額） | `orderEditBegin(id!) → { calculatedOrder, orderEditSession, userErrors }`；`orderEditAddVariant(id!, variantId!, quantity!, allowDuplicates=false, locationId)`／`orderEditAddCustomItem`／`orderEditSetQuantity(id!, lineItemId!, quantity!, restock=false)`／`orderEditAddLineItemDiscount`／**`orderEditUpdateDiscount`**／`orderEditRemoveDiscount`／**`orderEditAddShippingLine`**／**`orderEditUpdateShippingLine`（僅限新加入的行）**／**`orderEditRemoveShippingLine`**；`orderEditCommit(id!, notifyCustomer, staffNote)` |
| 草稿單 | `draftOrders`, `draftOrder(id)` | `draftOrderCreate(input{lineItems[{variantId\|custom{title,price}, quantity, appliedDiscount}], customerId, shippingAddress, appliedDiscount, shippingLine, note, email})`, `draftOrderUpdate`, `draftOrderDelete`, **`draftOrderComplete(paymentPending: Boolean, idempotencyKey!)`** → 轉正式單（第二層業務唯一鍵 `(draft_order_id)`）, `draftOrderInvoiceSend(email 主旨/內文)` |
| 棄單 | `abandonedCheckouts(first, query)` | `abandonedCheckoutSendRecovery`（15 §棄單信規則） |

規則：訂單號 `#1001` 起連號 per shop；60 天窗口概念佔位；search 語法 `financial_status/fulfillment_status/return_status/email/name`（**不含 `status`——Order 沒有單一 status 欄位**）。

**`orderCancel` 契約（P0-14，逐項）**
<!-- 依 46a:842–877 修正，原文：`reason` 與 `restock` 皆 non-null；`staffNote` ≤255 且買家不可見；`refundMethod` 可退原路或 store credit；
     回傳 `job{id,done}` ＋ `orderCancelUserErrors`（`userErrors` 已 deprecated）；mutation 為**非同步**。
     🔴 此處原本寫錯：原簽名 `orderCancel(reason, refund: Boolean, restock: Boolean, notifyCustomer)`——
     多出官方**不存在**的 `refund: Boolean`、少了 `staffNote`/`refundMethod`、`restock` 未標 non-null、且做成同步。任何人翻舊版都不要改回去。 -->
- `reason: OrderCancelReason!` **6 值**：`CUSTOMER` / `PAYMENT_DECLINED` / `FRAUD` / `INVENTORY` / `STAFF_ERROR` / `OTHER`。
- `restock: Boolean!` **non-null 無預設**；`staffNote` ≤ `limits.order.cancel_staff_note_max_chars`(255)、買家不可見。
- ~~`refund: Boolean`~~ **官方不存在，已刪除**（是否退款由 `refundMethod` 表達）。
- **非同步**：回 `job{id, done}` 供輪詢；job 本身帶冪等鍵。
- **不可取消五條件（聯集 guard）**：已取消／有待處理付款授權／**有進行中的退貨（`REQUESTED`/`OPEN`）**／有無法履行的未結出貨／已（部分）出貨 → 皆回 `INVALID_STATE`。
- **停用地點**：已付款 ＋ `restock:true` → **整個 mutation 失敗**；未付款 → 成功但庫存不回補。
- 副作用：關閉／取消所有未結 FulfillmentOrder（走 §5 的替代單語義）。

**訂單編輯契約（P1-16／P1-17／P1-21）**
<!-- 依 46a:889–903、46a:933、46a:959–963、46a:985–989、46c:462–463、46c:470、46c:479–488 補寫，原文：
     「Order ──orderEditBegin──> CalculatedOrder（暫存區，含 OrderEditSession）… ──orderEditCommit──> Order」；
     「`shippingLines` 有 `stagedStatus` 欄位，值為 ADDED / REMOVED / UNCHANGED」；
     「The system recalculates taxes and totals automatically as edits occur.」；
     「`orderEditUpdateShippingLine`：Modify title or price on **newly added** lines」；
     「**文檔未載明** OrderEditSession 的鎖機制、TTL、或同一訂單並發編輯的行為」。
     🔴 此處原本寫錯：本表原本只有 `orderEditBegin → …→ orderEditCommit` 一行鏈，**沒有 CalculatedOrder 暫存區、沒有 stagedStatus、沒有 OrderEditSession、缺 4 個 shipping/discount mutation**
     → 照原契約實作會做成「直接改單」，無法預覽與回退。任何人翻舊版都不要改回單行鏈。 -->
- **`CalculatedOrder` 是必做的暫存層**（獨立資料表，見 16-F8.1）：commit 前原 `orders` / `order_line_items` **一個欄位都不動**。
- **`stagedStatus`（`ADDED` / `REMOVED` / `UNCHANGED`）照抄**——前端 diff 渲染完全由它驅動，不得自行比對兩份 JSON。
- **每次 edit mutation 即時重算稅與總額**（回傳的 `calculatedOrder` 帶最新金額），不是 commit 才算。
- `orderEditUpdateShippingLine` **只能改本次新加入的 shipping line**（`stagedStatus == ADDED`），否則 `userErrors`。
- **⚠ 本專案決策（Shopify 文檔未載明）**：同一訂單同時只允許一個 open edit session（部分唯一索引），第二個 `orderEditBegin` 回 `INVALID_STATE`；session TTL ＝ `limits.order.edit_session_ttl_hours`(24)；commit 前以 `lock_version` 樂觀鎖重驗。見 16-F8.2。
- **`orderEditBegin` 的九條 guard**（help 6 條 ∪ dev 5 條的聯集，見 16-F8.3）：已取消／匯入單／Shop Pay 分期單／當地配送單／待處理付款單／非商店幣別單（未升級 Checkout Extensions）／預付型訂閱單 → 整單擋；已履行品項不可移除改量（**逐行**、且**每個 mutation 前都要檢查**）；訂單層折扣唯讀。
- **反直覺兩條**：①**已出貨品項「可以」管理品項層折扣**（只鎖移除／改量）；②運費**不重算、不可改配送方式**，只能加自訂運費行；稅則**每次編輯自動重算**。
- 補款結帳頁**沒有加速結帳**（Shop Pay／Apple Pay 不可用，46c:470）。
- **刻意不復刻**：46a:908「2019-01-01 前的訂單不可編輯」為 Shopify 歷史包袱，本專案不實作（46a §8⑦-46 建議）。

## 5. 履約（read/write_fulfillments）

| 類別 | Queries | Mutations |
|---|---|---|
| 履約單 | `order.fulfillmentOrders`（assignedLocation、lineItems、**status(7)**、**requestStatus(8)**、**supportedActions(12)**、fulfillmentHolds{reason(8)}） | **`fulfillmentOrderCancel(id) → { fulfillmentOrder, replacementFulfillmentOrder }`**, `fulfillmentOrderClose(id, message) → INCOMPLETE`, `fulfillmentOrderOpen(id)`, `fulfillmentOrderReschedule(id, fulfillAt)`, **`fulfillmentOrderHold(id!, fulfillmentHold!{reason, reasonNotes, notifyMerchant, handle, fulfillmentOrderLineItems}) → { fulfillmentHold, fulfillmentOrder, remainingFulfillmentOrder }`**, `fulfillmentOrderReleaseHold(id, externalId\|handle)`, **`fulfillmentOrderMove(id, newLocationId, lineItems) → { movedFulfillmentOrder, originalFulfillmentOrder, remainingFulfillmentOrder }`**, `fulfillmentOrderSplit(fulfillmentOrderSplits!)`, `fulfillmentOrderMerge`, `fulfillmentOrdersReroute`, `fulfillmentOrderReportProgress` |
| 3PL 請求軸 | fulfillmentOrder.requestStatus | `fulfillmentOrderSubmitFulfillmentRequest(id, message, notifyCustomer)`, `fulfillmentOrderAcceptFulfillmentRequest(id, message)`, `fulfillmentOrderRejectFulfillmentRequest(id, reason: FulfillmentOrderRejectionReason(14), message, lineItems)`, `fulfillmentOrderSubmitCancellationRequest`, `fulfillmentOrderAcceptCancellationRequest`, `fulfillmentOrderRejectCancellationRequest` |
| 出貨 | `fulfillment(id)` | `fulfillmentCreate(fulfillment{lineItemsByFulfillmentOrder[{fulfillmentOrderId, fulfillmentOrderLineItems[{id, quantity}]}], trackingInfo{number, company, url}, notifyCustomer, **originAddress{countryCode!}**})`, `fulfillmentTrackingInfoUpdate`, `fulfillmentCancel`, `fulfillmentEventCreate(status: IN_TRANSIT\|OUT_FOR_DELIVERY\|**READY_FOR_PICKUP**\|DELIVERED\|FAILURE…)` |

規則：**部分出貨**按 fulfillment order line 數量；出貨後 order.fulfillment_status 推導（16 號狀態機）；通知信走 18 號 outbox。

**FulfillmentOrder 契約補完（P0-04／P0-05）**
<!-- 依 46a:213–275、46a:236–240、46a:354–366 補寫，原文：`fulfillmentOrderCancel`＝「Cancels order and creates replacement for remaining work」；
     `fulfillmentOrderHold`／`Move` 回傳 `remainingFulfillmentOrder`（自動拆出新單承接未處理品項）；
     `fulfillmentOrderClose` 逐字「Marks in-progress order as incomplete」→ 導向 INCOMPLETE 不是 CLOSED。
     我方原本只列 `Move/Hold/ReleaseHold/Split` 四個名稱，拆單語義完全未寫 → 剩餘品項會憑空消失 -->
- **三個會產生新 FO 的操作必須回傳新單 ID**：`fulfillmentOrderCancel → replacementFulfillmentOrder`、`fulfillmentOrderHold/Move → remainingFulfillmentOrder`。無剩餘工作時回 `null`。
- **`fulfillmentOrderClose` 導向 `INCOMPLETE`（不是 `CLOSED`）**，中文 UI 標「未能完成」。
- `supportedActions` 為**伺服器端計算欄位**，admin 按鈕啟用完全由它驅動；**前端不得另寫 guard**。
- `fulfillmentCreate` 的多張 FO 必須**同一 order ＋ 同一 location**（service 層驗證回 `userErrors`，非 DB constraint）；`originAddress.countryCode` 必填。
- 每張 FO **≤`limits.fulfillment_order.max_active_holds`(10)** 個 active hold。
- 自營 FO（未指派 fulfillment service）**恆為 `requestStatus: UNSUBMITTED`**。
- **⚠ 待查證（來源未載明）**：`FulfillmentOrderHoldUserErrorCode` / `SplitUserErrorCode` / `OrderCancelUserErrorCode` 的具體 enum 值、`fulfillmentOrderSplit` 最大拆分數、tracking number/url 數量上限（46a:1049–1067 逐條標未載明）。

## 6. 退款與退貨

| 類別 | Queries | Mutations |
|---|---|---|
| 試算 | `order.suggestedRefund(refundLineItems, shippingAmount)` → maximumRefundable、按比例分攤結果；`return.suggestedRefund` → `SuggestedReturnRefund`；**`returnCalculate(input: CalculateReturnInput) → CalculatedReturn{returnLineItems, exchangeLineItems, returnShippingFee}`（不建立資料）**；`returnableFulfillments(orderId)` → **可退的 fulfillment line item ＋ 可退數量**（前提：已 delivered） | — |
| 退款 | `order.refunds` | `refundCreate(input{orderId, refundLineItems[{lineItemId, quantity, restockType, locationId}], refundShipping{amount\|fullRefund}, refundDuties[], transactions[{parentId, amount, kind: REFUND, gateway}], refundMethods[]（原路／store credit）, note, notify}) @idempotent(key:)`, `refundMarkAsSettled(transactionId) @idempotent(key:)`（線下待確認型退款的人工確認——16 §F5 步 3 落地格：權限 `orders.mark_refund_settled`＋二次確認＋audit log，第 24 輪登） |
| 退貨 | `returns`, `return(id)`（status/returnLineItems/exchangeLineItems/**returnShippingFees**/reverseFulfillmentOrders/refunds/decline） | `returnRequest(input)`→REQUESTED, `returnCreate(returnInput{orderId!, returnLineItems!, exchangeLineItems, returnShippingFee, requestedAt})`→OPEN, `returnApproveRequest`, `returnDeclineRequest(returnId, declineReason!)`, `returnLineItemRemoveFromReturn`, **`returnProcess(input: ReturnProcessInput)`**, `returnCancel(id)`, `returnClose(id)`, `returnReopen(id)`, `reverseFulfillmentOrderDispose`, `reverseDeliveryCreateWithShipping` |

規則：**退款金額走 16-F5.1 的唯一公式**（`refund = max(0, 退貨品項價值 − 退貨費用 − 換貨扣抵 − 未付款額)`）；比例分攤折扣與稅（15 §引擎同源）；退款匯率＝當下（29 §3.4）。

**退貨／退款契約補完（P0-01／P0-02／P0-06）**
<!-- 依 46a:642、46a:806–809 修正，原文：`returnRefund` **已 deprecated**（逐字「Deprecated mutation for refunding returns without restocking input」）；
     有退貨脈絡走 `returnProcess`（2025-07 起可用），無脈絡走 `refundCreate`。
     🔴 此處原本寫錯：本表原把 `returnRefund` 列為現行 mutation。任何人翻舊版都不要改回去。 -->
- ~~`returnRefund`~~ **已 deprecated，不實作**；有 return 關聯 → `returnProcess`；無 return 關聯（純取消、客訴補償）→ `refundCreate`。
- **費用不對稱設計照抄**：`RestockingFeeInput{percentage: Float!}`（**百分比**、**per line item**）／`ReturnShippingFeeInput{amount: MoneyInput!}`（**固定額**、**per return**、**必須 presentment 幣別**）。
- `returnReasonNote` ≤ `limits.return.reason_note_max_chars`(255)；`returnDeclineRequest.declineReason` **必填**（`FINAL_SALE`/`RETURN_PERIOD_ENDED`/`OTHER`）。
- `returnCalculate` 與 `returnProcess` **共用同一份計算程式碼**（數字同源，鐵律 7）。
- `returnProcess` 內含退款 → **本專案強制 `idempotencyKey`**（Shopify 未載明）。
- **退款上限是軟上限、不是 DB 硬鎖**：預設 `netPayment`，超額需 `orders.over_refund` 權限＋二次確認（46c:223 明載超額退款合法）。
- `ReturnErrorCode` **26 值全部落地**為 `userErrors.code`；`INVALID_STATE` 為狀態機違規統一碼。

**`ReturnErrorCode` 全 26 值（P1-11／S-20，逐字照抄）**
<!-- 依 46a:560–591 補寫，原文：46a 逐字標「這是本研究中**唯一一份完整的錯誤碼清單**（S29）」，並附每值的官方描述。
     本檔原本只寫「26 值全部落地」一句宣告，**沒有列出任何一個值** → 開發者無從照抄，必然各自發明錯誤碼。 -->

`ALREADY_EXISTS`（已存在）、`BLANK`（空白）、`CREATION_FAILED`（建立失敗）、`EQUAL_TO`（須等於）、`FEATURE_NOT_ENABLED`（功能未啟用）、`GREATER_THAN`（須大於）、`GREATER_THAN_OR_EQUAL_TO`（須大於等於）、`INCLUSION`（不在允許清單）、`INCOMPATIBLE_WITH_STANDARD_POLICY`（與標準退貨政策衝突）、`INTERNAL_ERROR`（內部錯誤）、**`INVALID_STATE`（狀態不符——狀態機違規統一碼，全專案沿用）**、`INVALID`（無效）、`LESS_THAN`（須小於）、`LESS_THAN_OR_EQUAL_TO`（須小於等於）、`MISSING_PERMISSION`（缺少權限）、`NOT_A_NUMBER`（非數字）、`NOT_EDITABLE`（不可編輯）、`NOT_FOUND`（找不到）、`NOTIFICATION_FAILED`（通知失敗）、`PRESENT`（須為空）、`TAKEN`（已被佔用）、`TOO_BIG`（值過大）、`TOO_LONG`（過長）、`TOO_MANY_ARGUMENTS`（參數過多）、`TOO_SHORT`（過短）、`WRONG_LENGTH`（長度錯誤）。

> **通用碼複用鐵律**：上表中 20 個是泛用驗證碼（`BLANK`/`TOO_LONG`/`NOT_FOUND`…），**全專案所有 mutation 的 `userErrors.code` 一律從這組取值**，不得各模組自造同義碼（`EMPTY` vs `BLANK`、`MISSING` vs `NOT_FOUND`）。`INCOMPATIBLE_WITH_STANDARD_POLICY` 與 `NOTIFICATION_FAILED` 為退貨線專屬。
- **⚠ 待查證（來源未載明）**：`restockType` 的真實列舉值——46a:747 為 `RESTOCK`/`NO_RESTOCK`/`LEGACY_RESTOCK`，本檔原寫 `RETURN`/`CANCEL`/`NO_RESTOCK`，實務另有第三套 → **三方互斥，須 GraphQL introspection 定案，實作前不得二選一**（50 號 T-08／V-01）。
- **⚠ 待查證（來源未載明）**：`maximumRefundable` 公式、稅額在退款時的分攤規則、`RefundShippingInput` 同時給 `amount` 與 `fullRefund` 的行為、`RestockingFeeInput.percentage` 最大值。

## 7. 顧客（read/write_customers）

| 類別 | Queries | Mutations |
|---|---|---|
| 顧客 | `customers(first, query)`, `customer(id)`（ordersCount/amountSpent/lastOrder/addresses/taxExempt/marketing consent） | `customerCreate(input{firstName, lastName, email, phone, addresses, tags, note, taxExempt})`, `customerUpdate`, `customerDelete`（有訂單→匿名化，16 §）, `customerAddressCreate/Update/Delete/SetDefault`, `customerMerge(customerOneId, customerTwoId)` |
| 行銷同意 | customer.emailMarketingConsent/smsMarketingConsent | `customerEmailMarketingConsentUpdate(input{marketingState: SUBSCRIBED\|UNSUBSCRIBED, marketingOptInLevel, consentUpdatedAt})`、`customerSmsMarketingConsentUpdate` |
| 分群 | `segments`, `customerSegmentMembers(segmentId)` | `segmentCreate(name, query)`, `segmentUpdate`, `segmentDelete`——query 語法＝分群 DSL（01 §顧客） |
| **商店抵用金** | `customer.storeCreditAccounts`, `storeCreditAccount(id){balance, expiresAt, transactions}` | **`storeCreditAccountCredit(id, creditInput{creditAmount, expiresAt}, idempotencyKey!)`**、**`storeCreditAccountDebit(id, debitInput{debitAmount}, idempotencyKey!)`** |

規則：email/phone 唯一 per shop；consent 帶時間戳與來源（GDPR 稽核）；merge 保留訂單歸屬。

**商店抵用金兩支的硬要求**（55 §A M23–M26／§D G-07・G-08；契約原本只有 `limits.store_credit` 的 5 個常數，**無任何 mutation 契約**）：
- `idempotencyKey!` **必填**；`storeCreditAccountDebit` 另有第二層業務唯一鍵 `(checkout_token, store_credit_account_id)`。
- 一律走**條件式 UPDATE**（`UPDATE store_credit_accounts SET balance_cents = balance_cents − ? WHERE id = ? AND shop_id = ? AND balance_cents >= ?`），🔴 **禁止先讀後寫**；`balance_cents` 恆 `>= 0`。累計上限 `max_balance_usd: 15000` 在**併發下同樣要靠條件式 UPDATE**，不是靠寫入前的 SELECT 檢查。
- `storeCreditAccountDebit` 先驗 `account.shop_id == checkout.shop_id`，不符回 `CROSS_SHOP_REDEMPTION_FORBIDDEN`（與餘額不足分開回）。
- 帳戶到期扣減走排程 job，冪等鍵 `UUID v5(scexpire, (store_credit_account_id, expiry_date))`（55 §A.3）。
<!-- 依 56 §E 分流，原 55 §D 結論：G-07「抵用金的稅務定位與併發安全皆未定義」＋ G-08。
     依 56 §E，G-07「**不消失，只改性質**」：TW＝決定**發票金額**（V-22），HK＝決定**收入認列金額**（V-29）。
     上面四點是 G-07 的**併發安全**那一半——那一半 56 §E 沒有提到，因為它法域無關：
     兩分頁同時結帳超額扣抵，與賣方在哪個法域完全無關。**不得**因為「G-07 移到會計層」而漏掉它。
     稅務／會計那一半見 `limits.jurisdictions.<code>.accounting.store_credit_on_issue|on_use`（兩邊皆 null，
     定案前 HK 走 `record_with_undetermined_basis`，🔴 **不擋發放與使用**）。 -->

## 8. 折扣與禮品卡（read/write_discounts）

| 類別 | Queries | Mutations |
|---|---|---|
| 自動折扣 | `automaticDiscountNodes` | `discountAutomaticBasicCreate/Update`（金額/百分比）、`discountAutomaticBxgyCreate/Update`、`discountAutomaticFreeShippingCreate/Update`、`discountAutomaticDelete/Activate/Deactivate` |
| 折扣碼 | `codeDiscountNodes`, `codeDiscountNodeByCode` | `discountCodeBasicCreate/Update`、`discountCodeBxgyCreate`、`discountCodeFreeShippingCreate`、`discountCodeDelete/Activate/Deactivate`、`discountCodeBulkCreate(codes[]，2000 萬配額)`、`discountRedeemCodeBulkAdd` |
| 禮品卡 | `giftCards`, `giftCard(id)` | **`giftCardCreate(initialValue, code?, customerId?, expiresOn, note, idempotencyKey!)`**, `giftCardUpdate`, **`giftCardDeactivate(idempotencyKey!)`**, **`giftCardCredit/Debit(amount, idempotencyKey!)`** |

規則：求值管線與組合裁決（17 號：allocation/combination matrix）；**用量併發硬保證**（usage_count CAS＋唯一索引）；input 統一 `{title, startsAt, endsAt, combinesWith{orderDiscounts, productDiscounts, shippingDiscounts}, minimumRequirement, **context{customerSegments | markets}**, usageLimit, appliesOncePerCustomer}`。

**禮品卡四支的額外硬要求**（55 §A M27–M32／§D G-06・G-08；法域無關）：
- `idempotencyKey!` **必填**（`limits.idempotency.required_for`）；`giftCardDebit` 另有第二層業務唯一鍵 `(checkout_token, gift_card_id)`——冪等窗只有 24 小時，「同一次結帳只能扣一次」是永久約束。
- `giftCardCredit/Debit` 一律走**條件式 UPDATE**（`UPDATE … WHERE balance_cents >= ?`），🔴 **禁止先讀後寫**；`balance_cents` 恆 `>= 0`。
- `giftCardDebit` 在條件式 UPDATE **之前**先驗 `gift_card.shop_id == checkout.shop_id`，不符回 `userErrors{code: CROSS_SHOP_REDEMPTION_FORBIDDEN}`。這與餘額不足是**兩個不同的失敗模式**，錯誤碼不得合併。
- 每一支在成功後於**同一個 transaction** 內落一列 `contract_liability_entries`（方向見 `limits.jurisdictions.hk.accounting.gift_card_entry_points`）。
<!-- 依 56 §E 分流，原 55 §D 結論：G-06「禮品卡稅務處理未定義」＋ G-08「四支 giftCard 未列強制冪等」。
     依 56 §E，G-06 在 HK **性質改變**（HKFRS 15 合約負債，已有答案，不是「開立時點二選一」），
     G-08 **與法域無關完整適用**。上面四點中，前三點法域無關、第四點是 HK 基準法域的落地（57 §G-07）。
     🔴 原 `limits.gift_card.resolver_refuses_start_when_undecided: true` 已移入 `jurisdictions.tw.accounting`
        並限定 TW——照搬到 HK 會讓禮品卡**永遠無法啟用**（HK 的 tax_event_* 本來就不存在）。 -->

<!-- 依 46b:248–257、46b:375 修正，原文：`customerSelection` **已 deprecated（2025-10）**，改用 `context{customerSegments | markets}`，且 **markets 與 customerSegments 互斥（XOR）**。
     🔴 此處原本寫錯：input 原列 `customerSelection` 且無 `context`、無 XOR 檢查。任何人翻舊版都不要改回去。 -->
- `context` 的 `customerSegments` 與 `markets` **互斥**（XOR 驗證，兩者皆給 → userError）。
- 免運折扣的 `combinesWith` **只有 `orderDiscounts` / `productDiscounts` 兩個旗標**（無 `shippingDiscounts`）——46b:197。
- `combinesWith` 三旗標**預設全 false**（46c:705）；**運費折扣不可疊運費折扣**是引擎級硬規則，不由旗標控制。
- `percentage` 線上格式為 **0–1 Float**（不是 0–100），內部存 basis points（46b:189、46b:272）。
- 上限一律引用 `config/limits.yml` 的 `discount.*`（自動折扣全店同時 ≤25、每店碼 2,000 萬、每碼適用清單 100、每次結帳 5 碼＋1 運費碼、tags 5／長度 255）。
- **⚠ 待查證（來源未載明）**：單一折扣可綁 markets 數上限（46b:993–1010 標未載明）。

**`DiscountErrorCode` 全 39 值（P1-12／S-23，逐字照抄）**
<!-- 依 46b:323–367 補寫，原文：46b §2⑤ 完整表格 39 值＋官方描述；46b §2⑥-7 逐字建議「**`DiscountErrorCode` 39 值全部照抄**進 `userErrors.code` 列舉——這是最省事的相容性資產，直接進 `28-api-contract.md`」。
     🔴 本檔原本把這條標成「⚠ 待查證（來源未載明）」——**分類錯誤**：來源（46b:323–367）載明得非常完整，它只是「還沒抄過來」，不是「查不到」。
     混在待查證清單裡會讓它永遠不被實作。已改為落地清單。任何人翻舊版都不要改回「待查證」。 -->

| 類別 | 值 |
|---|---|
| **折扣專屬（19）** | `ACTIVE_PERIOD_OVERLAP`（同時 active 的自動折扣超過 25）、`APPLIES_ON_NOTHING`、`CONFLICT`、`DISCOUNT_NOT_COMPATIBLE_WITH_CONDITION_TYPES`、`END_DATE_BEFORE_START_DATE`、`IMPLICIT_DUPLICATE`、**`INVALID_COMBINES_WITH_FOR_DISCOUNT_CLASS`**（17-F1 第 4 點的 shipping 旗標約束用它）、`INVALID_DISCOUNT_CLASS_FOR_PRICE_RULE`、`INVALID_PRODUCT_DISCOUNTS_FALSE_WITH_EXISTING_TAGS_ON_SAME_CART_LINE`、`INVALID_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_FOR_DISCOUNT_CLASS`、`INVALID_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_WITHOUT_PRODUCT_DISCOUNTS`、`INVALID_TAG_LENGTH`、`MAX_APP_DISCOUNTS`、`MINIMUM_SUBTOTAL_AND_QUANTITY_RANGE_BOTH_PRESENT`、`MISSING_FUNCTION_IDENTIFIER`、`MULTIPLE_FUNCTION_IDENTIFIERS`、`MULTIPLE_RECURRING_CYCLE_LIMIT_FOR_NON_SUBSCRIPTION_ITEMS`、`PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_NOT_ENTITLED`（方案不足）、`RECURRING_CYCLE_LIMIT_NOT_A_VALID_INTEGER` |
| **上限類（3）** | `EXCEEDED_MAX`、`TOO_MANY_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE`（>10）、`TOO_MANY_TAGS`（>5） |
| **泛用驗證（17）** | `BLANK`、`DUPLICATE`、`EQUAL_TO`、`GREATER_THAN`、`GREATER_THAN_OR_EQUAL_TO`、`INCLUSION`、`INTERNAL_ERROR`、`INVALID`、`LESS_THAN`、`LESS_THAN_OR_EQUAL_TO`、`MISSING_ARGUMENT`、`PRESENT`、`TAKEN`、`TOO_LONG`、`TOO_MANY_ARGUMENTS`、`TOO_SHORT`、`VALUE_OUTSIDE_RANGE` |

**用法對照**（三條最容易漏接的）：超過 `limits.discount.max_active_automatic_per_shop`(25) → `ACTIVE_PERIOD_OVERLAP`；shipping 類折扣寫入 `combinesWith.shippingDiscounts` → `INVALID_COMBINES_WITH_FOR_DISCOUNT_CLASS`；Plus 專屬的 `productDiscountsWithTagsOnSameCartLine` 在非進階方案 → `PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_NOT_ENTITLED`。

## 9. 內容與線上商店（read/write_content, read/write_themes）

| 類別 | Queries | Mutations |
|---|---|---|
| 頁面 | `pages`, `page(id)` | `pageCreate(title, body, handle, templateSuffix, isPublished)`, `pageUpdate`, `pageDelete` |
| 網誌 | `blogs`, `articles` | `blogCreate/Update/Delete`, `articleCreate(blogId, title, body, summary, image, tags, author, publishedAt)`, `articleUpdate/Delete`, `commentApprove/Delete/Spam` |
| 選單 | `menus`, `menu(id)` | `menuCreate(title, handle, items[{title, type, resourceId\|url, items 巢狀}])`, `menuUpdate`, `menuDelete` |
| 轉址 | `urlRedirects` | `urlRedirectCreate(path, target)`, `urlRedirectUpdate/Delete`, `urlRedirectBulkDeleteAll` |
| 主題 | `themes`, `theme(id)`（role: MAIN\|UNPUBLISHED\|**DEMO**\|DEVELOPMENT——DEMO＝試用主題（購買前）：不可編輯代碼、不可用 AI 生成、**不可 publish**（出口＝購買轉 UNPUBLISHED/發布，或刪除）、可刪（四值＝總綱 §3 狀態機表 F11 列，語義詳 90-blueprint/12 B.1 <!-- 第 20 輪更正：原複合引用「12 B.1 F11」——F11 是總綱表列號，12 章 grep 零命中 -->；（2026-08-17 更正，PR #52 第 19 輪）：原僅三值，DEMO 主題無法經 API 面忠實表達）；files connection） | `themeCreate(source: zip URL/staged upload, name)`（→ 25 §4 匯入管線＋授權 gate）, `themePublish`（**DEMO 拒絕**）, `themeUpdate(name)`, `themeDelete`, `themeDuplicate` |
| 主題檔 | `theme.files(filenames, first)` → body/contentType/size/checksumMd5 | `themeFilesUpsert(themeId, files[{filename, body{type: TEXT\|BASE64, value}}])`（**寫檔＝AST cache bust**）, `themeFilesDelete`, `themeFilesCopy(fromTheme)` |

規則：主題檔上限與白名單（25 §4）；publish＝原 MAIN 降級＋快取整體失效；redirects 命中在**資源不可用 handler 前**查表——404 與 unpublish 的 410 **兩個回應路徑皆查**（範圍同 90-blueprint/12 C.5／13-F2；（2026-08-17 更正，PR #52 第 18 輪）：原「404 前查表」會讓 410 路徑不查 `url_redirects`、無視商家設定的 301）。

## 10. 主題編輯器內部 API（31 號的 API 面；editor scope）

REST-ish 內部端點（编辑器高頻小 payload，不走 GraphQL）：

| 端點 | 說明 |
|---|---|
| `GET /editor/api/themes/{id}/schema` | 全主題編譯後 schema：sections/blocks 清單＋settings 定義＋presets＋翻譯後 labels（31 §ED） |
| `GET /editor/api/themes/{id}/template?path=index` | 模板 JSON＋section groups＋contextual overrides |
| `POST /editor/api/themes/{id}/draft` | 提交 op batch（add/remove/move/set-setting/toggle-disabled/duplicate/rename）→ 存 draft 態 |
| `POST /editor/api/themes/{id}/render_section` | **draft 渲染通道**（27 §6.3）：body={template draft JSON, sectionKey, context{market, locale, route}} → 回 wrapper HTML |
| `POST /editor/api/themes/{id}/publish_draft` | draft → 落正式檔（themeFilesUpsert 語義）＋清 undo stack |
| `GET /editor/api/fonts` | 字型庫清單（31 §R3） |
| `GET /editor/api/dynamic_sources?context=product` | 動態來源 picker 資料（metafields/資源屬性樹） |

## 11. 結帳、金流與設定域（read/write_settings）

| 類別 | Queries | Mutations |
|---|---|---|
| 商店 | `shop`（name/currency/ianaTimezone/domains/plan/billingAddress/backupRegion） | `shopUpdate`, `shopResourceFeedbackCreate` |
| 員工 | `staffMembers` | `staffMemberInvite`, `staffMemberUpdate(roles)`, `staffMemberDeactivate`（12 號權限模型） |
| 運送 | `deliveryProfiles`, `deliveryProfile(id)` | `deliveryProfileCreate/Update`（zones[{countries, methodDefinitions[{name, rateDefinition{price}\|conditions weight/price range}]}]）, `deliveryProfileRemove` |
| **其他配送方式**（44:322 實測三列） | `localDeliverySettings`, `localPickupSettings`, **`pickupPointProviders`** | `localDeliverySettingsUpdate`, `localPickupSettingsUpdate`, **`pickupPointProviderUpsert(carrier, subtypes[], enabled, codEnabled, credentialsRef)`**, **`pickupPointProviderDelete`** |
| **取貨點門市**（P0-13） | **`order.pickupPoint`**（門市快照：carrier/storeId/storeName/address/phone/isOutsideIsland）, **`checkout.pickupPoint`** | **`checkoutPickupPointSet(checkoutToken, carrier, subtype, storeId, storeName, storeAddress, storePhone, isOutsideIsland)`**（電子地圖回拋端點寫入）, **`orderPickupPointUpdate`**（門市關轉店的改派） |
| 稅 | `taxSettings` | `taxSettingsUpdate`（P1 簡化：per-country rate 表） |
| **退貨與取消規則**（P0-10） | **`returnRules`**（多條：預設 ＋ N 條，可按市場切換）, **`returnPolicySnapshot(id)`** | **`returnRuleCreate/Update/Delete(input{returnsEnabled, cancellationsEnabled, windowDays\|unlimited, windowStartBasis: ITEM_DELIVERED\|ORDER_LAST_ITEM_DELIVERED, shippingFeeMode: FREE\|FLAT_FEE\|CUSTOMER_BUYS_LABEL, shippingFeeAmount, restockingFeeBp, finalSaleTargets[{type: COLLECTION\|PRODUCT, id}], marketId})** |
| 結帳設定 | `checkoutSettings`（24 §5 全欄位） | `checkoutSettingsUpdate(contactMethod, requireLogin, nameMode, companyMode, addressAutocomplete, tipping{...}, abandoned{...}, cartItemLimit)` |
| 結帳外觀 | `checkoutProfiles`, `checkoutProfile(id)` | `checkoutProfileCreate/Duplicate/Delete`, `checkoutBrandingUpsert(profileId, designSystem{colors, typography, cornerRadius}, customizations{...})`（24 §6.4 jsonb 結構） |
| 通知 | `notificationTemplates`（**`eventKey`／`groupKey`／`channel`／`toggleable`／`enabled`／`locale`**；12 分組） | **`notificationTemplateUpdate(templateId, subject, bodyLiquid, enabled)`**（18 號 Liquid 沙箱）——`enabled` 僅在 `toggleable = true` 時可寫，否則 `userErrors`；`toggleable` **唯讀、由種子決定** |
| 網域 | `domains` | `domainCreate(host)` → DNS 驗證流程, `domainSetPrimary`, `domainDelete` |
| 支付 | `paymentProviders` | `paymentProviderActivate(stripe test keys)`（15 號） |

**退貨與取消規則契約說明（P0-10）**
<!-- 依 46c:422–426、44:437 補寫（三方一致），原文：H14 en 逐字「Changes to your return rules apply only to future orders. Changes don't apply to previous orders」；
     44 後台頁尾逐字「退貨與取消規則適用於在啟用或更新規則後所購買的品項」。我方 16／13／28 原本全無 → 商家改規則會追溯既往 -->
- **規則變更不追溯既往**：`returnRuleUpdate` **必定產生一筆新的 `return_policy_snapshots`**（append-only、immutable），舊快照永不更新。
- 訂單成立時把當下適用的 snapshot id 寫進 `order_line_items.return_policy_snapshot_id`（**NOT NULL**）；`returnCalculate`／前台申請入口**一律讀快照**。
- **兩個獨立 toggle**：`returnsEnabled` 管**已履行**品項、`cancellationsEnabled` 管**未出貨**品項，同一訂單可並存 → 前台「申請」按鈕**逐 line item 判斷**。
- **最終銷售品項**：粒度為 collection 或 product；命中即前台**不出現申請入口**（不是提交後被拒）；**bundles 不可設為最終銷售**。
- 退貨期間 `14/30/90/不限/自訂`、起算點兩選項、退貨運費三選一、重新上架費為百分比——值域見 `limits.return.*`。

**取貨點（pickup points）契約說明（P0-13）**
<!-- 依 44:322 補寫，原文：Shopify 後台「其他配送方式」三列＝當地配送／到店取貨／**取貨點**（44 已標「這正是台灣超商取貨的對應概念，
     我們 42 號前台的超商取貨流程在 admin 側要對應此設定」）；46b:551–552 佐證 `purchase.checkout.pickup-point-list.*` 擴充點與
     `pickup-location-list`（到店取貨）分屬不同家族。我方原本 15/16/22/28 皆無 admin 側規格 → 前台選了門市後台無處存、無法出貨 -->
- **`delivery_method_type` 三分法**：`SHIPPING`（宅配）／`LOCAL_PICKUP`（到店取貨，取貨點＝賣家 location）／**`PICKUP_POINT`（取貨點，門市為第三方）**。寫在 `shipping_lines` 與 `fulfillment_orders` 上。
- `PICKUP_POINT` 的訂單**不收運送地址**，改存**門市快照**（門市會關店，不可只存外鍵）。
- 履行事件多一個 **`READY_FOR_PICKUP`**；退貨的「已送達」前提以**實際領件時間**為準（16-F7.2）。
- 上限值（COD ≤NT$20,000、三邊和 ≤105cm、≤5kg）引用 `limits.pickup_point.*`。
- **⚠ 待查證（來源未載明）**：Shopify 官方對 pickup point 的 admin 側**是否有對應 GraphQL 型別**，三方文檔皆未載明——上表的 `pickupPointProviders` / `checkoutPickupPointSet` 為**本專案自定契約**；台灣各物流商的 COD 上限與材積限制須逐一以合約原文覆核（V-11）。

## 12. Metafields／Metaobjects／Files

| 類別 | Queries | Mutations |
|---|---|---|
| Metafield | 任意資源 `.metafield(namespace, key)` / `.metafields(first)` | **`metafieldsSet(metafields[{ownerId, namespace, key, type, value, compareDigest?}]) ≤25 筆 atomic`**, `metafieldsDelete` |
| 定義 | `metafieldDefinitions(ownerType)` | `metafieldDefinitionCreate(name, namespace, key, type, ownerType, validations, access{storefront: PUBLIC_READ\|NONE})`, `metafieldDefinitionUpdate/Delete` |
| Metaobject | `metaobjects(type)`, `metaobjectByHandle` | `metaobjectDefinitionCreate(type, fieldDefinitions)`, `metaobjectCreate/Update/Delete`（theme 的 metaobject template 資料來源，24 §1.7） |
| 檔案 | `files(first, query)` | `stagedUploadsCreate(input[{resource, filename, mimeType, fileSize}])` → 簽名 URL → `fileCreate(files[{originalSource, alt}])`, `fileUpdate`, `fileDelete` |

type 系統首發 15 種：single_line_text/multi_line_text/rich_text/integer/decimal/boolean/date/date_time/url/color/json/money/file_reference/product_reference/metaobject_reference（+list. 變體）。

## 13. Markets／翻譯（29 §7 全表併入）

`markets/market/marketCreate/Update/Delete`、`webPresence*`、`marketCurrencySettingsUpdate`、`catalog*`、`priceList*`＋`priceListFixedPrices*`、`translatableResources/translationsRegister/Remove`、`marketLocalizations*`、`shopLocale*`。金額回傳一律 MoneyBag；storefront context 由 SSR RequestContext 承擔（等價 @inContext）。

**Market 繼承與父子關係（P1-32／T-05）**
<!-- 依 46b:636–639、46b:659–664、46b:690–717 修正，原文逐字：
     「A market can have **one or more parent markets**. If a market does not define a customization, it will inherit the customization from its parents, or the store defaults」；
     「**parent 不是手動指定的，是自動推導的（lineage inference）**：子市場的 region 是父市場 condition 的嚴格子集 → 成立父子；…；**具體地點列舉不參與 lineage 計算**」；
     「**用 null 表達繼承**…**沒有 `inherited: Boolean` 這種顯式旗標，也沒有 `parentMarketId` 欄位**（Market 物件無 parent/child 欄位）」。
     🔴 我方 29:42 原本把 `parent_market_id` 當**權威欄位**存 → 商家改了 regions、父子關係不會跟著變。改為 derived 快取，見 29 §1.5。 -->
- **`Market` 物件不暴露 `parentMarketId` / `childMarkets`**（照抄官方 schema）；父子由 conditions 推導。我方 DB 的 `markets.derived_parent_market_id` 是**推導快取**（每次 conditions 變更重算），API 不可寫入。
- **繼承用 `null` 表達**：customization 欄位為 null ＝ 沿 lineage 上溯；`catalogs`／`webPresences` **累加**，`currencySettings`／`priceInclusions` **覆寫**。
- 新增 **`Market.assignedCustomization(customizationId:)`**——admin「繼承／已覆寫」徽章的資料來源（46b 有、本檔原本缺）。
- 逐項覆寫走 **`marketSettingUpsert(marketId, key, value)`**（`value = NULL` ⇒ 恢復繼承）；`market_setting(market_id, key, value NULL=繼承)` 見 29 §1.5。
- 市場命中優先序（buyer 同時命中多市場）：**Company Location > Retail Location > Region > Store Default**（46b:641–648）。
- **⚠ 待查證（來源未載明）**：`delivery.shipping` 到底繼不繼承——46b:659–661 逐字「Null means the market inherits shipping from its parent」vs 44:866 逐字「運送與隱私權不繼承，永遠市場本地」，**直接矛盾**，須 introspection 覆核（V-02，維持待查證，不得二選一寫死）。

## 13b. B2B（Company／CompanyLocation，P1-33／H-64～H-68）

<!-- 依 46b:810–830、46b:850–868、46b:881–911、46b:935–943 補寫，原文逐字：
     「`CompanyContact`：A person that acts on behalf of the company. A company contact is **associated with a retail customer record**.」；
     「Catalogs attach exclusively to company locations, not companies.」；
     「some information, such as tax IDs and exemptions, is **location-specific and must be updated from the location page**」；
     「`CompanyLocation.market` — **已 Deprecated**」；
     「…they receive the **lowest listed price** within those catalogs」＋「must be published in at least one applicable publication to be visible」。
     50 號 H-64 逐字：「44 行動項 71 說『我們 B2B 規格原本掛在 company 上——要改』，但實際上不存在該規格」——本輪複核確認 `docs/specs` 下**無任何 B2B 規格檔**，僅 admin 原型有註釋。 -->

| 類別 | Queries | Mutations |
|---|---|---|
| 公司 | `companies(first, query)`, `company(id)`（**只有** `name` / `note` / `defaultRole` / `mainContact` / `externalId`） | `companyCreate`, `companyUpdate`, `companyDelete`, `companyAssignMainContact` |
| 公司地點 | `company.locations`, `companyLocation(id)`（catalogs／paymentTerms／taxSettings／`buyerExperienceConfiguration`／currency／locale／billing+shipping 地址） | `companyLocationCreate`, `companyLocationUpdate`, `companyLocationAssignTaxExemptions`, `companyLocationAssignAddress`, `companyLocationDelete` |
| 聯絡人 | `company.contacts`（**每筆帶 `customerId`**） | `companyContactCreate(companyId, customerId)`, `companyContactAssignRole(contactId, companyLocationId, roleId)`, `companyContactRevokeRole`, `companyContactDelete` |
| 付款條件 | `paymentTermsTemplates` | `paymentTermsCreate`, `paymentTermsUpdate`, `paymentTermsDelete` |
| B2B 草稿單 | `draftOrder.purchasingEntity` | `draftOrderCreate(purchasingEntity{companyId, companyLocationId, companyContactId})`, **`draftOrderCalculate`**, `draftOrderInvoiceSend`, `draftOrderComplete` |

**掛載層級鐵律（H-64，照抄官方，最重要的一條）**
> **catalog／payment terms／tax（tax ID・exemptions）／checkout 設定（`checkoutToDraft`・`editableShippingAddress`・deposit）／currency／locale／billing+shipping 地址 —— 一律掛 `company_location`。**
> **`company` 層只有 `name` / `note` / `default_role` / `main_contact`。**
> admin UI 可提供「從 company 頁批次套用到所有 location」的便利操作，但**資料仍逐一寫進每個 location**——這樣就沒有「company 值 vs location 值誰贏」的繼承地獄。

其餘四條：
- **H-68 company contact 不是獨立帳號**：`company_contacts.customer_id` 外鍵 → 復用 `customers` 表；同一個 customer 可同時是 B2C 顧客與 B2B 聯絡人。**角色是 `contact × location` 的指派**（`ordering_only` / `location_admin`），不是 contact 的全域屬性。
- **H-66 多 catalog 取最低價**：同一 company location 命中多個含相同商品的 catalog → 取 **`MIN(price)`**；且商品**必須至少發佈到一個 applicable publication 才可見**。寫成 `B2b::PriceResolver` 並測「同商品多 catalog」。
- **H-67 `CompanyLocation.market` 已 deprecated**：**不得建 location → market 的正向外鍵**；改由 `COMPANY_LOCATION` 型 market 的 `companyLocationsCondition` 反查（與 §13 的 conditions 模型一致）。
- **S-26／S-27 付款條件與審核流**：`PaymentTermsType` **5 值** `FIXED` / `FULFILLMENT` / `NET`（搭 `dueInDays`）/ `RECEIPT` / `UNKNOWN`。`checkoutToDraft: true` ⇒ 結帳不建 order 而建 draft order（前台按鈕文案「送出待審核」）。付款結果**三態**：無 terms → 立即付款；NET → `payment_pending`；NET＋deposit → `partially_paid`。
  > **`checkoutToDraft` 是「轉向」、validation 是「擋」**——兩者職責不同，不要混用（46b §5⑥-3）。
- **上限**一律引用 `limits.b2b.*`（10,000 locations/company、10,000 contacts/company、**50 contacts/location**、25 catalogs/location、250 prices/request、**1 company/customer**）。
- **⚠ 待查證（來源未載明）**：標準 NET 7/15/30/45/60/90 的內建清單（46b:892 逐字「文檔未載明」，只給泛用 `dueInDays`）；`CheckoutProfile` 有無 company/location 欄位（46b:828 標未載明）。見 §待查證 V-19。

## 14. 分析（read_analytics）

| 類別 | Queries |
|---|---|
| 總覽 | `analyticsOverview(range, compareRange)` → 指標卡集（19 號辭典：total_sales/net_sales/orders/conversion_rate/AOV/returning_rate/sessions） |
| 報告 | `report(type, range, groupBy, filters)` → rows connection（sales_over_time/sales_by_product/by_channel/by_location/traffic…19 §報告清單） |
| 即時 | `liveView` → 當前 sessions/cart/checkout/orders 計數 |

規則：**同源鐵律**——pulse 卡/列表 badge/報告數字全部出自 rollup 服務（19 號）；range 用 shop timezone。

## 15. Webhooks（事件出口）

- 訂閱：`webhookSubscriptions` query＋`webhookSubscriptionCreate(topic, callbackUrl, format: JSON)/Update/Delete`。
- **簽章**：`X-CL-Hmac-Sha256`＝base64(HMAC-SHA256(raw body, app secret))，timing-safe 比較；headers `X-CL-Topic/X-CL-Shop-Domain/X-CL-Webhook-Id（去重）/X-CL-Event-Id/X-CL-Triggered-At/X-CL-API-Version`。
- **投遞**：5 秒內 2xx；重試指數退避（demo 3 次；規格目標 8 次/4 小時）；API 建立的訂閱連續失敗自動刪除；outbox 驅動（18 號）。
- **Topics 首發 24 個**：`app/uninstalled`, `shop/update`；`products/create|update|delete`；`collections/create|update|delete`；`inventory_levels/update`；`orders/create|updated|paid|cancelled|fulfilled|partially_fulfilled|edited`；`draft_orders/create|update`；`customers/create|update|delete`；`fulfillments/create|update`；`refunds/create`；`checkouts/create|update`（棄單）；`themes/publish`；`bulk_operations/finish`（佔位）。payload＝資源 snake_case JSON＋`admin_graphql_api_id`。
- **內部 topic（不對外開放訂閱；2026-08-24 依 63 §C.1 決議表回寫，第 19 包 §4.4）**：
  `product.updated`、`product.variant.updated`、`product.publication.changed`、
  `inventory.level.changed`、`inventory.adjusted`——細粒度內部消費（快取 stamp／搜尋索引／
  smart collection／發布同步／feed 增量），**不進 `webhookSubscriptionCreate` 可訂閱列表**
  （體例同 18 §F1-6 的 `einvoice/*` 先例）。正典常數表＝`app/services/events/topics.rb`。
- **內部 topic 3 個（不對外開放訂閱）**：`einvoice/issue_requested`、`einvoice/void_requested`、`einvoice/refund_routed`——由 16-F5.5 寫入、38 號的 job 消費。**不出現在 `webhookSubscriptionCreate` 的可選 topic 列表**（發票 payload 含統編等敏感欄位）。
  <!-- 依 38:876–877、38:1338–1356 補寫：全額取消自動作廢、部分退貨自動折讓。原本 topic 清單無 einvoice/* → 退款不觸發作廢/折讓＝稅務錯誤（50 號 TW-5） -->
- **⚠ 已知差異（不實作）**：44:447 實測 Shopify 的 webhook 支援 **XML 與 JSON 兩種格式**且歸在「通知」IA 下；本專案 `format: JSON` 單一（H-117 屬 P2，此處明文記錄以免被誤判為遺漏）。
- Feed/SEO 消費者（30 號）：products/update→feed 增量＋IndexNow；orders/*→Simprosys 訂單餵送。

## 16. 前台 HTTP 面（買家端）

- **頁面路由**（SSR，全部支援 `/{locale}` 前綴＋market 網域，29 §2.5）：`/`、`/products/{handle}`（`?variant=` canonical 規則 30 §1.3）、`/collections`、`/collections/{handle}`（分頁/排序/篩選 query）、`/pages/{handle}`、`/blogs/{handle}`、`/blogs/{handle}/{article}`、`/search`（`?q=`）、`/cart`、`/checkout`（15 號）、`/account/*`（login/register/orders/addresses）、`/gift_card/{code}`、`/password`、`/404`、**`?view={suffix}` alternate template**（25 §5）。
- **Ajax/JSON 面**：25 §5 全表（cart 家族雙格式、SRA、predictive search、recommendations、localization、shipping_rates）。
- **SEO 面**（30 §9）：`/sitemap.xml`＋分片、`/robots.txt`（liquid 可覆寫）、`/{indexnow-key}.txt`、`/feeds/google/{market}.xml|.tsv`（feed 直出）、`.well-known` 驗證檔路由。
- **結帳 POST**：`/checkout` 提交、`/checkout/shipping_rates`、`/checkout/complete`（Stripe confirm）——15 號欄位規格。

## 17. 三端對接矩陣（誰用哪個面）

| 客戶端 | 使用的 API 面 | 認證 |
|---|---|---|
| Admin React SPA | GraphQL Admin API（§1–14）＋編輯器內部 API（§10）＋stagedUploads | session cookie＋CSRF |
| 買家瀏覽器（主題 JS） | 前台 HTTP 面（§16）：Ajax cart/SRA/search/localization | cart token（cookie） |
| Liquid SSR 渲染器 | 內部 service objects（**不走 HTTP**——drops 直讀 preloaded scope，25 §6） | 進程內 |
| 外部整合（Simprosys/自建 feed 消費者/未來 apps） | GraphQL Admin API（token）＋Webhooks（§15） | `clat_` token＋scopes |
| Checkout（React island） | 結帳 POST＋`/checkout/shipping_rates`＋Stripe.js | checkout session token |

## 18. 驗收

1. Admin SPA 的**每一個**網路請求都是 `/admin/api/2026-08/graphql.json`（或 §10 編輯器端點）——瀏覽器 network 面板抽查零例外。
2. 任一 mutation 的業務錯誤出現在 userErrors（含 code），HTTP 恆 200；表單元件只消費 userErrors。
3. `extensions.cost` 在每個回應出現；壓測觸發 THROTTLED 後前端 SDK 自動退避重試成功。
4. 三個 webhook 消費者（feed 增量/IndexNow/測試 endpoint）HMAC 驗證通過並在 orders/create 後 5 秒內收到。
5. GID/分頁/MoneyV2 慣例 lint：schema 檢查器擋住裸 float 金額與 offset 分頁。
6. 22 號按鈕表逐行對照：每個 admin 按鈕都能映射到本文一個操作（缺口=補 mutation）。
