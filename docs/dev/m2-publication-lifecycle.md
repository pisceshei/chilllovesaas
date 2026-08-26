# m2 — Publication 的生命週期 API（S1）

> 分步方案 `docs/plans/2026-08-26-發布與可見性-分步執行方案.md` 的 **S1**。
> 前置＝S0（`docs/dev/m2-publication-model.md` 是第 12 包的發布模型本體）。
> 研究全文＝`docs/plans/2026-08-26-S1-規格草案.md`；admin 實測＝`docs/research/82-admin-channels.md` §11。

---

## §1 這一步為什麼存在

S0 之前，`publications.operation_status` 是一個**零讀者零寫者**的欄位。研究階段的倉庫掃描
（S1 規格草案 C-12）發現一件更根本的事：

> 我方倉庫**根本沒有「發布切換」這個動作**——`resource_publications.published_at` 只在
> **建立時**被寫入（`Publications::Materialize` 的兩條路徑 ＋ 兩支 migration 的原生 SQL），
> 全倉**零 UPDATE 路徑、零 DELETE 路徑、零 publish／unpublish mutation**。

⇒ 「進行中的發布操作鎖」在這個狀態下是**空掛的**：沒有可被鎖住的動作。
**本步先交付那個動作**，鎖屬後續步驟。

---

## §2 交付了什麼

| 面 | 檔案 | 內容 |
|---|---|---|
| 讀取 | `app/graphql/types/publication_type.rb` | `Publication` type；`publications` query 掛在 `QueryType` |
| 寫入 | `app/graphql/mutations/publication_{create,update,delete}.rb` | 三支 mutation（薄殼） |
| 規則 | `app/services/publications/write.rb` | 唯一寫入入口；批次上限、租戶檢查、刪除守衛、cache stamp |
| 規則 | `app/services/publications/lookup.rb` | publication GID 解析（兩支 mutation 共用，避免 `field` path 分岔） |
| 契約 | `app/graphql/types/errors/publication_user_error_{code,type}.rb` | typed error code enum |
| 契約 | `app/graphql/types/inputs/publication_{create,update}_input.rb`、`publication_default_state_enum.rb` | input 與 enum |

---

## §3 🔴 四條最容易做錯的規則

### 3.1 `publishablesToAdd`／`Remove` 是**累加／扣除**，不是宣告式全量

本尊的發布 modal **一律以「全部未勾」開場**，即使選取的商品已經在某些管道上
（`docs/research/82` §11.5 實測，兩個商品的 `Channels` 欄都是 1、modal 仍全空）。

⚠️ **本倉庫的 `productSet`／`collectionSet` 家族是相反的**（宣告式全量：未列出＝移除）。
照那個習慣實作，商家的一次勾選會**清空整個管道**。

守衛：`spec/requests/publication_lifecycle_spec.rb` 的
「只送 publishablesToAdd 時，既有成員**不得**被移除」。
突變複驗：把 update 改成先 `destroy_all` 再重建 ⇒ 該格轉紅。

### 3.2 重複 add 是 **no-op success**，不是 `ALREADY_EXISTS`

本尊官方逐字：`If the variant is already published to that publication, the mutation
succeeds with no change.` ⇒ 用 `find_or_create_by!`，DB 兜底是既有的 `uq_res_pub_target`
唯一索引。

### 3.3 🔴 逐列 `find_or_create_by!`，**刻意不用 `insert_all`**

多型的 `publishable` 側**沒有資料庫外鍵**，唯一那道租戶守衛是
`ResourcePublication#publishable_belongs_to_same_shop`（一個 model validation）
⇒ `insert_all` 會直接繞過它，寫出跨租戶的列**而不拋任何錯**。

這個缺口已在 `resource_publication.rb` 與 `docs/dev/m2-publication-model.md` §6 登記，
而 **S1 是第一個真的會踩到它的批次寫入者**（50 筆一批很自然會寫 `insert_all`）。
代價是 N 次 INSERT，而 N ≤ 上限（見 3.4）。

守衛：「別間店的商品 ⇒ INVALID_PUBLISHABLE_ID」。
突變複驗：把解析改成 `.unscoped` ⇒ 該格轉紅。

### 3.4 批次上限取「**合計**」是 ours 加嚴

官方兩句措辭不同且**都沒有指明切分**：

- input object 頁：`A list of publishable IDs to add. The maximum number of publishables to update simultaneously is 50.`
- mutation 頁：`You can add or remove products from the publication, with a maximum of 50 items per operation.`

⇒ 「各自 50」還是「合計 50」＝**官方未取得**。我方 fail-closed 取較嚴的一側（合計），
上限值引 `config/limits.yml` 的 `sales_channels.publication_bulk_products_max`（鐵律 6）。
取得證據後（測試店以 add／remove 各 26 個實測）再放寬。

---

## §4 刪除的三條裁定（全部是 ours）

🔴 **官方對 `publicationDelete` 的副作用完全沉默**——全文只有 `Deletes a publication.` 一句
（同一 URL 抓兩次字串完全相同，取證 2026-08-26）。既沒說會級聯刪，也沒說不會。
以下三條**不得讀成照抄本尊**：

| # | 裁定 | 理由 |
|---|---|---|
| 1 | **綁著 channel 的 publication 不可刪**（`CANNOT_MODIFY_APP_CATALOG_PUBLICATION`） | channel 是 app 的身分（S0），移除它是**卸載管道**不是刪 publication。⚠️ 沒有這條守衛，刪線上商店 publication 會讓 `Publication.online_store` 回 nil，而那個 nil 的後果是**整店商品前台不可見且不拋任何錯**（與 S0 修掉的 C-9 同一個症狀）。技術上 `fk_channels_publication_id` 也擋得住，但那是 **500 不是 `userErrors`**，違反鐵律 4 ① |
| 2 | **級聯刪 `resource_publications`** | 外部旁證：Saleor `channelDelete` 逐字 `Orders associated with the deleted channel will be moved to the target channel. Checkouts, product availability, and pricing will be removed.`（取證 2026-08-26）⇒ **交易類資料必須遷移、配置類可刪**。發布列是配置類（可重建），不是財務憑證 |
| 3 | 🔴 **絕不連帶刪 publishable 本體** | Medusa 明文區分 `dismiss`（解除關聯）與 `delete`（連帶刪被連記錄）兩件事；我方只做前者。有反向 fixture 鎖死——沒有它，未來有人在 publishable 側加 `dependent: :destroy` 就是**靜默資料遺失** |

🔴 **刪除前必須 bump cache stamp**：`dependent: :destroy` **不會** bump
`products.publications_updated_at`。刪 publication 會讓大量商品的前台可見性改變，
而快取**不失效且不拋錯**。**順序不可倒**——刪掉之後就查不到受影響的是哪些商品了。

⚠️ bump 一律走既有的 `Product.bump_publications_stamp!`，它刻意用 `update_all` 的
**字串形式**避開樂觀鎖遞增。照抄 hash 形式的後果是**把商家開著的編輯表單直接作廢**
（`StaleObjectError`），而商家什麼都沒做。守衛：「加入商品會 bump stamp 且**不動** lock_version」。

---

## §5 對外契約的三處刻意選擇

| # | 選擇 | 理由 |
|---|---|---|
| 1 | **不曝露 `name`，只曝露 `title`（取自 catalog）** | 本尊 `Publication.name` 已 deprecated，reason 逐字 `Use Catalog.title instead.` |
| 2 | **`catalogId` 的 GID Type 是 `AppCatalog`**，不是我方 model 名 `SalesCatalog` | model 名加 `Sales` 前綴是實作層為了避開既有命名空間（`Catalog::` 是服務層），那不該漏到對外契約上（鐵律 4） |
| 3 | **參數形態照抄本尊的 `input:`／扁平 `id:`**，不用具名參數 | `docs/research/28-api-contract.md` §0.3.4 說新 mutation 走具名參數，但依據是「本尊自 2024-10 起改具名」——而 publication 線**至今仍是舊式**。鐵律 12 的 1:1 優先。⚠️ 連帶後果：create／update 的 `userErrors.field` path 第一段是 `input`，**delete 是 `id`**（本尊 delete 沒有 input object） |

---

## §6 誠實聲明（本步**沒有**做的）

| # | 內容 | 為什麼 |
|---|---|---|
| S1-A | **`defaultState: ALL_PRODUCTS` 不支援**，傳它回 `FEATURE_NOT_ENABLED` | 本尊那條路是非同步的 `AddAllProductsOperation`（帶 `processedRowCount`／`rowCount` 進度），我方**完全沒有進度欄位的落點**。加欄就是第二個零消費者欄位（`publications.catalog_id` 空轉兩週那個坑的同型）。**誠實拒絕，不做「同步跑一遍假裝是它」** |
| S1-B | **`operation_status` 仍然零寫入者、恆為 null** | 鎖與被鎖的動作要同批設計；本步先交付動作。⚠️ **不得因為 type 上有這個欄位就以為鎖已生效** |
| S1-C | **`publications.sales_catalog_id` 未轉 NOT NULL** | `docs/specs/88` §2.1 指派給 S1，但它要先讓兩支既有 migration 的建立順序對齊，屬語義獨立的一件事 ⇒ 另包 |
| S1-D | **`name`／`channel_handle` 的欄位刪除** | 兩者已降級為 legacy／快照（S0 PR B），刪欄要改所有讀取端 ⇒ 另包 |
| S1-E | **`publishablePublish`／`publishableUnpublish`（逐資源切換）** | 分步方案明文劃給 S5；契約形態已取證完畢，做時直接用 |
| S1-F | **不進 `idempotency.required_for`** | 該清單目前收的是**金流與庫存**寫入，判準是「重放會不會憑空多出一筆錢或一批庫存」。重放 `publicationCreate` 只會多出一個可刪、無金流、無庫存的容器。⚠️ **這是我方判斷不是本尊規則**；若日後 publication 牽動計費（管道訂閱），必須重新裁定 |
| S1-G | **`publications` query 不做 connection 分頁** | `sales_channels.max_channels` 是 **null（文檔未載）**，實測本尊測試店恰三個管道。為個位數集合套 keyset 分頁，前端要寫一整套 cursor 卻永遠只有一頁。⚠️ S10 的 catalog publication 大量出現時要改 |
| S1-H | **本尊 `PublicationUserErrorCode` 的 22 個值只宣告了會發出的幾個** | 宣告一個永遠不會出現的錯誤碼，前端會為它寫一條永遠死掉的分支。刻意不宣告的逐條理由寫在該 enum 檔內 |

---

## §7 未取得（S1 射程內仍未解的）

| # | 未取得 | 怎麼取得 |
|---|---|---|
| S1-U1 | `ProductBulkPublish`／`ProductBulkUnpublish` 的 variables 與回應形狀 | persisted query ＋ POST body，現有工具不可觀測（鐵律 14.3）。需要能讀 request body 的抓包工具 |
| S1-U2 | `Publication.operation` 的實地形態（進行中的鎖、進度數字） | 需安裝一個管道 app（使用者已裁定不安裝） |
| S1-U3 | 批次上限 50 的**切分語義**（各自 vs 合計） | 測試店以 add／remove 各 26 個實測 |
| S1-U4 | `publicationDelete` 之後既有發布資源的官方去向 | 官方沉默；需在測試店對真實 publication 實測 |
| S1-U5 | 「操作整體失敗」在本尊怎麼表達 | `ResourceOperationStatus` 恰三值無失敗態，但 `processedRowCount` 的描述**明文含 failed 列** ⇒ 兩層如何對應＝官方未說明 |
| S1-U6 | `PublicationUpdateInput.autoPublish` 的官方預設值 | 該欄在 input object 頁**未標 default**（與另兩欄不同）⇒ 不得外推 create 頁的 `false`。我方明文選「缺席＝保持現值」 |

---

## §8 一條官方自相矛盾（照 schema 不照散文）

`ResourceOperationStatus` 的 enum 頁恰三值（`ACTIVE`／`COMPLETE`／`CREATED`，**無 `FAILED`**），
但同一家的指南頁 `.../products-and-collections/sync-data` 逐字要求
`Poll the productOperation query with the operation ID from Step 1 until the status changes
to COMPLETE or FAILED.`（取證 2026-08-26）。

🔴 **輪詢終止條件必須以 schema 值域為準，不以散文為準**，否則會寫出一條**永遠等不到的
`FAILED` 分支**。這是「教學層 vs schema 層」錯位，不是誰權威的問題。
⚠️ **執行期是否可能真的回 `FAILED`＝未取得**（S1-U5）。
