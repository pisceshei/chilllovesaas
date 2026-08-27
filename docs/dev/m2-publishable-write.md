# M2／S5：逐資源的發布寫入面（`publishablePublish` ／ `publishableUnpublish`）

> 射程＝分步方案的 **S5**（`docs/plans/2026-08-26-發布與可見性-分步執行方案.md`）。
> 規格草案＝`docs/plans/2026-08-27-S5-規格草案.md`；admin 實測＝`docs/research/82-admin-channels.md` §13。
> 前置：S1（`docs/dev/m2-publication-lifecycle.md`）、S2（`docs/dev/m2-resource-publication-semantics.md`）。
>
> 🔴 **這一包解掉的是 S1 與 S2 都登記過的阻塞缺口**：在它之前，全倉**沒有任何路徑
> 能修改既有列的 `published_at`** ⇒ 設排程／改期／取消排程結構上無路可達。

---

## §1 這是什麼

兩支以**資源**為中心的 mutation，把一個 publishable（商品／系列／子類選項）
發布到、或自 N 個銷售管道移除。與 S1 的 `publicationUpdate`（以**管道**為中心）
是同一件事的兩個方向，本尊自己也把兩者並列並給用法建議（層級 B，取證 2026-08-27）：

> The mutations above are resource-centric… For the inverse pattern, picking a
> publication and managing which products it contains, use the publicationUpdate mutation.

🔴 **功能邊界在 `publishDate`**：`PublicationUpdateInput` 官方**恰三欄且沒有 `publishDate`**
（`autoPublish` ／ `publishablesToAdd` ／ `publishablesToRemove`，取證 2026-08-27）
⇒ **排程只能經 `publishablePublish` 進入系統**。這不是我方省略，是本尊的功能邊界。

⚠️ 官方對「同一配對經兩支寫入時的優先權／衝突」＝**未取得**（五頁皆無相關陳述）。
不得反向斷言「官方認為兩者等價」。

### §1.1 🔴 admin 實測：發布是獨立的 mutation，不是商品儲存的一部分

測試店 `chill-love-u5q5mnzq` 實測（全文＝`docs/research/82` §13，取證 2026-08-27）：

| 觀察 | 結果 |
|---|---|
| 逐商品 `Manage publishing` modal 按 `Done` | **零個** `api/operations` 請求；商品表單標 dirty ＋ 冒出 `Unsaved changes` SaveBar |
| 按 `Save`（商品欄位 ＋ 發布都 dirty） | 兩個 POST：`ProductSaveUpdate` ＋ `ProductSavePublishablePublishUnpublish` |
| 按 `Save`（**只有**發布 dirty） | **只有** `ProductSavePublishablePublishUnpublish`，且 persisted-query hash 相同 |
| 存檔後讀回 | `ProductPublicationsV2`（`resourceLimit: 250`） |

三條可用結論：①發布永遠是**獨立的 mutation**，即使由同一顆 `Save` 觸發
⇒ 🔴 **不得把 publish／unpublish 併進 `productSet`**；②一支 operation 涵蓋兩個方向、
逐區塊判 dirty；③本尊自己的 admin 用的就是 **V2 投影**（補上 S2 裁定的實測支持）。

⚠️ **不可觀測（鐵律 14.3）**：admin 走 persisted query ⇒ 該 operation 的 variables
與 document 全文讀不到。「它內部是不是呼叫這兩支官方 mutation」＝**未取得**。

---

## §2 🔴 寫入狀態矩陣（本包的核心產出）

唯一實作處＝`Publications::Write.apply_publication!`。
`publishablePublish` 與 `publicationUpdate` **共用同一份**（§5 收斂）。

| # | 既有列 | 輸入 `publishDate` | 語義 | 依據 |
|---|---|---|---|---|
| R1 | 不存在 | 省略 | 建列，`published_at = 現在`＝立即發布 | 沿用 `Materialize`／`Write` 既有預設 |
| R2 | 不存在 | 未來 T | 建列，`published_at = T`＝設排程 | 官方逐字 `Setting this to a date in the future will schedule the resource to be published.` |
| R3 | **NULL** | 省略 | 改成現在 | 🔴 硬需求，見下 |
| R4 | NULL | 未來 T | 改成 T | 同上 |
| R5 | 已發布（過去） | 省略 | **no-op success** | 官方逐字 `If the variant is already published to that publication, the mutation succeeds with no change.` |
| R6 | 已發布（過去） | 未來 T | 改成 T＝把已發布改成排程 | 🔴 **ours**（官方沉默） |
| R7 | **排程中（未來）** | 省略 | 🔴 **no-op，不得動排程日期** | 🔴 **ours，fail-closed** |
| R8 | 排程中 | 另一未來 T′ | 改成 T′＝改期 | ours |
| R9 | 排程中 | 過去／現在 T | 改成 T＝取消排程並立即發布 | ours |
| R10 | 任一 | **明確 `null`** | **reject `INVALID`** | 🔴 **ours，fail-closed** |
| R11 | 任一 | 未來 T，管道 `supports_future_publishing == false` | `FEATURE_NOT_ENABLED` | 官方逐字 `Only online store channels support future publishing.` |
| R12 | 任一 | 未來 T，publishable 型別在正典的不支援清單內 | `INVALID_STATE` | help 逐字 `You can't set a future publishing date for individual product variants.` |
| **U1** | 存在 | （unpublish） | **硬刪整列** | ours（§4.2） |
| **U2** | 不存在 | （unpublish） | **no-op success** | 🔴 ours（官方未涵蓋） |
| **U3** | 任一 | unpublish 帶 `publishDate` | 🔴 **完全無效果**：不驗證、不生效、不回錯 | 官方逐字 `This field has no effect if you include it in the publishableUnpublish mutation.` |

### §2.1 🔴 R3／R4 為什麼是硬需求，不是完整性練習

`published_at IS NULL` 的列**佔住** `uq_res_pub_target` 唯一索引。
S1 的 add 分支用 `find_or_create_by!` 帶 create-only 區塊——Rails 8.1.3.1 的實作是
`find_by(attributes) || create_or_find_by!(attributes, &block)`，
`find_by` 命中時 `create_or_find_by!` **根本不被呼叫**，區塊隨之不執行
⇒ 命中 NULL 列時**什麼都不寫**，而呼叫端收到成功。
**症狀＝回報發布成功、商品仍不可見、不拋任何錯。**

⚠️ NULL 列是**合法既存態**（來源＝migration `20260814200000` 的兩段原生
`INSERT…SELECT`，搬 `products.published_at`／`collections.published_at`，兩欄本身可為 NULL），
但**我方沒有任何生產路徑會產生它**——`Materialize` 與 `Write` 都寫 `published_at: at`。
🔴 S5 **不新造**設 NULL 的路徑（見 §4.2）。

### §2.2 🔴 R7 為什麼取 no-op（本包最重要的 fail-closed 裁定）

官方那句 no-change 的**主詞是「已發布」**（`If the variant is **already published**…`），
射程**未涵蓋「已排程未到點」**——那一格官方沉默。

反面選項是「省略 `publishDate` ⇒ 改寫成現在」，後果是**靜默取消商家設好的排程**
（S2 §4-E4 已登記的事故形態）。兩個未知之間，選不會毀掉既有商家意圖的那一個。

### §2.3 🔴 R10 為什麼 reject 而不是「取消排程」

官方對 `publishDate: null` **完全沉默**：三個版本的 `PublicationInput` 頁、兩支 mutation 頁、
兩份 sales-channel 指南全文皆無相關陳述（取證 2026-08-27）。
且官方**正面排除**了「用 unpublish 帶日期來取消排程」這條路（U3 的「無效果」）。
⇒ 自行把 `null` 定義成「取消排程」會與 `publishableUnpublish` 的語義重疊、且無官方背書。

⚠️ **實作重點**：GraphQL 把「省略」與「明確 null」都餵成 Ruby 的 `nil`，
**只有 `input.key?(:publish_date)` 分得開**。少了它，R5／R7 會全部退化成 reject。
突變測試 M4 就是那條路的守衛。

### §2.4 R9 是「天然冪等」論述的唯一例外

R9（排程中 ＋ 過去時間 ⇒ 立即發布）帶的是呼叫端給的具體時間，**是收斂的**。
但若日後把 R10 改成「`null` ⇒ 取消排程並寫 `Time.current`」，重放兩次會得到兩個不同值
⇒ 那會讓本線失去「不需冪等鍵」的資格。**這是 R10 取 reject 的第二個理由**（見 §7）。

---

## §3 GraphQL 契約

### §3.1 兩支 mutation

```graphql
publishablePublish(id: ID!, input: [PublicationInput!]!): PublishablePublishPayload
publishableUnpublish(id: ID!, input: [PublicationInput!]!): PublishableUnpublishPayload
```

payload 兩欄：`publishable: Publishable`（nullable）／`userErrors`。

🔴 **不跟本尊的第三欄 `shop: Shop!`**：我方 `Shop` type 目前沒有 `publicationCount`，
跟了就是為零消費者新增一個欄位。登記為刻意偏離（§5）。

### §3.2 `PublicationInput`（兩支共用）

官方 SDL 逐字（取自官方頁的 schema payload，取證 2026-08-27）：

```graphql
input PublicationInput { channelId: ID  publicationId: ID  publishDate: DateTime }
```

三欄**全部 nullable、且 SDL 層沒有任何 `= value` 預設子句**。我方兩處偏離：

| 欄位 | 官方 | 我方 |
|---|---|---|
| `publicationId` | nullable | 型別同為 `ID`，但**缺席時回 `INVALID` 的 userError**（本尊 nullable 是為了相容 `channelId`） |
| `publishDate` | `DateTime` | 同 |
| `channelId` | `ID`，**已 deprecated** | 🔴 **不實作** |

🔴 `channelId` 的 provenance 必讀：渲染頁與官方 `.md` **只顯示 `Deprecated` 一字，
無描述、無 reason**（三個版本皆同）。描述與 reason **只存在於**同一官方 URL 的
schema hydration payload，逐字片段 `"channelId","ID of the channel.",[],"Use publicationId instead."`
⇒ **渲染層未取得、僅 payload 層取得**，引用時要標層級。
偏離依據＝`28 §0.3.2`「偏離只減不加」＋第 12 包 §2.4「deprecated 的不抄」。
⇒ 官方那條「同時給 `channelId` 與 `publicationId` 時只用後者」的優先序規則
（**只**出現在 unpublish 頁的 Examples）在我方情境不會發生，**不照抄成我方規則**。

### §3.3 錯誤

`field` path **不剝殼**：`["input", "0", "publicationId"]`。
依據是官方 fixture 逐字 `["input","0","publicationId"]`（unpublish 頁 Examples，取證 2026-08-27）
——這同時**推翻**了 `docs/research/28` §0.3.6 原本登記的「沒有官方範例可證是否剝殼」假設（已同批更正）。
⚠️ fixture 是**形狀**證據不是規則宣告，但形狀已足以定 path 慣例。
`id` 參數的錯誤是扁平 `["id"]`（本尊 `id` 不在 input object 裡）。

| code | 觸發 | publish | unpublish |
|---|---|---|---|
| `NOT_FOUND` | `id` 或 `publicationId` 解析不到本店資源 | ✅ | ✅ |
| `INVALID` | GID 格式錯、`publicationId` 缺席、`publishDate` 明確 `null` | ✅ | ✅（不含 `publishDate`） |
| `TOO_BIG` | `input` 超過 `api.array_input_max_items` | ✅ | ✅ |
| `FEATURE_NOT_ENABLED` | 管道不支援排程 | ✅ | ❌ 結構上不可達 |
| `INVALID_STATE` | 該型別不支援排程 | ✅ | ❌ 結構上不可達 |

🔴 **不自創 `LIMIT_EXCEEDED`**（`28 §2` 明文禁止，超限一律 `TOO_BIG`）。

### §3.4 🔴 陣列上限用哪一個

**`api.array_input_max_items`（250）**，不是 `sales_channels.publication_bulk_products_max`（50）。

官方那個 50 **只**出現在 `PublicationUpdateInput.publishablesToAdd/Remove` 的欄位描述上；
`publishablePublish` 頁對 `maximum`／`limit`／`up to`／`at most`／`partial`
五個關鍵字**皆 Not found on page**（取證 2026-08-27）⇒ **本支上限＝官方未取得**，
外推 50 過去是把別支的規則當成這支的。

---

## §4 副作用（GraphQL 層看不見的三件事）

### §4.1 cache stamp：`at` 與 `publishDate` 必須解耦

🔴 `bump_stamps!` 一律傳 **`Time.current`**，**絕不傳 `publishDate`**。
`Product.bump_publications_stamp!` 是**直接賦值** `publications_updated_at = ?`（不是取現在），
把未來時間寫進去之後，後續每一次真實變動要嘛不讓 stamp 前進、要嘛讓它倒退——兩種都污染語義。

⚠️ **讀取側目前零消費者**（W6 前台包尚未存在）。正典 `catalog_flow.cache_stamp_sources`
已宣告這個欄位，S5 履行的是**寫入側義務**。
🔴 **不得**寫成「bump 了所以前台快取會失效」——那句話今天沒有實作支撐。

⚠️ **既有限制照登記**：`collections` 表**沒有** `publications_updated_at` 欄
⇒ 系列的發布變動目前**沒有任何 cache stamp 表達**。不順手加欄（schema 變更＋鐵律 18.3）。

### §4.2 🔴 取消發布＝硬刪列（ours；官方對紀錄去向完全沉默）

已讀完並確認**不存在**該陳述的官方頁（皆 2026-08-27）：`publishableUnpublish` 正文
與**全部八個 Examples**、`PublicationInput`、`ResourcePublication`、`ResourcePublicationV2`、
`Publishable`、`product-publishing.md`。

可用的**間接**訊號只證明一件事：**官方 API 面上沒有任何入口可以觀測「被取消發布的紀錄」**——

- `resourcePublications(onlyPublished:)` 逐字 `Whether to return only the resources that are
  currently published. If false, then also returns the resources that are scheduled to be published.`
  ⇒ 值域**只有兩類**，沒有第三類「已取消發布的歷史」；
- 「未發布」在官方是用 `Publishable.unpublishedPublications`（逐字
  `The list of publications that the resource isn't published to.`）表達的，回的是
  **Publication** 而不是一筆特殊紀錄。

⇒ **「硬刪列」與「留列標未發布」在對外 GraphQL 契約上不可區分。**
這是本題唯一可安全發布的結論；**「本尊實際怎麼存」＝未取得**。

我方選硬刪的理由**不是**「本尊也刪」，而是：我方只出 V2 投影，而 V2 的三個 scope
全部以 `published_at IS NULL` 為「不存在」⇒ NULL 列在我方全部讀出面與「沒有列」不可區分。
🔴 更關鍵：留 NULL 列會**佔住唯一索引**，而重新 publish 命中它就踩 §2.1 的靜默失效。

⚠️ 外部參考只作旁證：Saleor（BSD-3）同樣刪列並明說會丟資料，另留一條軟移除路徑
——🔴 **那條路在我方不成立**，因為 Saleor 的 listing 列上有 per-channel 售價與日期要保住，
我方 `resource_publications` **只有 `published_at` 一欄可保**。
日後 S10 把 price list 掛上這條線時本裁定需重開。取捨登記 `docs/specs/107`。

🔴 `destroy_all` 不是 `delete_all`（走 model、跑 callback）；
**絕不連帶刪 publishable 本體**（Medusa 在方法名層級就分開 `dismiss` 與 `delete`，我方只做前者）。

### §4.3 outbox：全倉第一個 `available_at` 未來值的使用者

排程列在**同一個 transaction 內**補一筆 `event_outbox`（鐵律 5），
topic＝既有的 `Events::Topics::PRODUCT_PUBLICATION_CHANGED`，
**`available_at` 精確等於 `published_at`**（未來值）。

🔴 既有六個 producer **一律**寫 `Time.current`，既有 spec 從未覆蓋這個分支。

🔴 **只在「結果是排程態」時發**：立即發布的 cache stamp 已在同一個請求裡同步 bump 完，
沒有任何延後的事要做；排程列才有「到點那一刻要再 bump 一次」這件事。

🔴 **不掛在 `Publications::Materialize` 的 `after_create` 上**：掛上去會讓
`spec/services/events/producers_spec.rb` 的「status 未變更 ⇒ 不產 publication.changed」轉紅，
而那格斷言是對的——建立商品不是「發布狀態變更」。

⚠️ 🔴 **消費者尚不存在，這是誠實登記不是宣稱**：`Events::Consumers::REGISTRY` 目前四個鍵
（`MEDIA_UPLOADED`／`PRODUCTS_CREATE`／`PRODUCTS_UPDATE`／`INVENTORY_ADJUSTED`），
`PRODUCT_PUBLICATION_CHANGED` 不在其中（既有唯一生產者 `Catalog::StatusTransition` 同樣只發不接）。
⇒ **在 S2 PR-C 接上消費者之前，這些事件會在到點時被 relay 取出、派給零個消費者、標記完成。**
🔴 **PR-C 必須處理「在它之前已被消化掉的排程事件」**——這一點寫在這裡，不是留給下一個人自己發現。

⚠️ 官方 webhook 面：`product-publishing` 指南頁**完全未提** webhook／event（八節逐節檢查）。
鄰頁的 `scheduled_product_listings/add` 等屬 **channel app 的 product listing 語義**，
與 Publishable／publication 模型不是同一層（兩頁未說明關係）
⇒ 🔴 **不得照抄任何 topic 名稱**。

### §4.4 🔴 併發：列鎖與它擋不住的東西

**S5 是全倉第一條 `published_at` 的 UPDATE 路徑**（S1／S2 全倉零 UPDATE）
⇒ 併發風險是本包**新引入**的。

`uq_res_pub_target` 是 `(shop_id, publication_id, publishable_type, publishable_id)`
的唯一索引——它**不涉及 `published_at` 的值** ⇒ 同一列的兩個並發讀改寫，唯一索引一點忙都幫不上。

處置：`locked_publication_row` 用 `SELECT ... FOR UPDATE`，
且**依 `publication_id` 遞增取鎖**（`publicationUpdate` 側則依
`[publishable_type, publishable_id]` 遞增）——這是死鎖防線：
`publishablePublish` 是「一個資源 × N 個管道」、`publicationUpdate` 是「一個管道 × N 個資源」，
兩者交錯執行時若各自照輸入順序取鎖就會互相咬住。

🔴 **不加 `lock_version`**：`resource_publications` 是關聯表，加樂觀鎖欄會打穿所有
`update_all` 路徑（包含既有 migration 的原生 SQL），且需要 schema 變更＋鐵律 18.3。
顯式列鎖達到同樣目的且無 schema 成本。登記於 `docs/specs/91` §3。

⚠️ **`RecordNotUnique` 的 rescue 是縱深防禦，不是常規路徑**（誠實登記）：
本專案測試庫實測隔離級別＝`REPEATABLE-READ`，InnoDB 會對不存在的列取**間隙鎖**，
建列競態因此已被序列化 ⇒ 自然情境打不到那條 rescue。它存在的理由是
①隔離級別若改成 `READ COMMITTED`（許多生產設定的預設），gap lock 消失、它立刻成為常規路徑；
②本表**同時**有 DB 唯一索引與 model uniqueness validation，Rails 官方對這個組合逐字警告
`#find_by will never be called`。⇒ 用**故障注入**測它，不假裝那是自然競態。

🔴 rescue 的處置是**重走完整矩陣**（遞回一次，`attempt` 有界），不是就地補一個 update：
輸掉競態的一方帶著未來日期而來，若只做 `update! if published_at.nil?`，
那個排程日期會被**靜默丟掉**而呼叫端收到成功。

**列鎖擋不住的四件事**（照登記）：(a) 已由列鎖處理；
(b) 跨租戶 publishable（多型側無 DB 外鍵，唯一守衛是 model validation）；
(c) `insert_all`／`upsert_all`（跳過 validation ⇒ 連 (b) 也繞過）；(d) 跨列不變量。

🔴 **不得用 `insert_all`／`upsert_all`／`update_all` 寫本表**：
會同時打穿多型租戶守衛與兩道排程守衛。N ≤ 250 逐列走 model 是既有裁定。

---

## §5 與本尊的偏離（逐項登記）

| # | 面向 | 本尊 | 我方 | 依據 |
|---|---|---|---|---|
| 1 | 命名 | `publishablePublish` 是 **interfaceVerb** | 照抄 | 鐵律 12 的 1:1 優先於 `28 §0.3` 的 `resourceVerb` 慣例 |
| 2 | 參數形態 | 扁平 `id:` ＋ 舊式 `input:` | 照抄 | 引 `m2-publication-lifecycle.md` §5 #3 的**既有豁免**，不重新裁定 |
| 3 | 🔴 error 型別 | **裸 `UserError`**（恆兩欄，**無 `code`**） | 新增 `Publishable*UserError` type ＋ `code` 欄 ＋ 兩個獨立 enum | 鐵律 4 已授權；理由＝admin SPA 是唯一客戶端、錯誤分支必須機器可判別 |
| 4 | `channelId` | 存在（deprecated） | **不實作** | `28 §0.3.2` 偏離只減不加 |
| 5 | payload `shop: Shop!` | 有 | **不跟** | 我方 `Shop` type 無 `publicationCount`，跟了是零消費者欄位 |
| 6 | `publishable` 型別 | connection 化的相關欄位 | 見 `Types::Interfaces::Publishable` 檔頭的既有登記 | S2 已登記 |
| 7 | 批次原子性 | 🔴 **本支未取得** | **全有全無** | ours，見 §6 |

🔴 **#3 的量級要說清楚**：對照 S1（publication 線）——那次本尊**有**
`PublicationUserErrorCode`（22 值），我方只是精簡值域；**本包是從零造一個本尊 schema 中
不存在的型別，外加一個不存在的欄位**。
⚠️ 鐵律 4 註記另有一句「本尊自己也在逐支遷往 typed error」，
🔴 **本包不引用那句**作為正當性來源：它目前只有 `bulkOperationRunMutation` 一個具名錨，
單點證據撐不起全稱句（鐵律 19.1）。只引「admin SPA 唯一客戶端」這個 ours 理由。

---

## §6 批次語義：全有全無（ours，不是照抄本尊）

🔴 **`publishablePublish` 本身是否 all-or-nothing ＝未取得**：對 `partial`／`fails`
兩個關鍵字在該頁皆 Not found on page（取證 2026-08-27）。

我方取全有全無的三個理由：

1. **同表同線的既有先例**＝`Publications::Write.update`，且 `publication_lifecycle_spec.rb`
   已逐字釘死「🔴 任何一筆不合法 ⇒ 整批不寫入（不是寫一半）」；
2. 本尊在**別支**上把逐筆獨立做成明確 opt-in（`productVariantsBulkUpdate.allowPartialUpdates`
   逐字 `When partial updates are not allowed, any error will prevent all variants from updating.`）、
   `metafieldsSet` 更是硬性 atomic（逐字 `This operation is atomic, meaning no changes are
   persisted if an error is encountered.`）⇒ 預設側是全有全無；
3. Saleor 預設 `REJECT_EVERYTHING` 同向（取證 2026-08-27）。

⚠️ 我方 `Storage::FileCreate` 是逐筆部分成功——🔴 那是因為**檔案系統不可回滾**，
不是通用選擇，**不得**拿它當本支的先例。
🔴 **不採用** Saleor 的第三級 `IGNORE_FAILED`（單筆內部分保存）——會讓資源落到半完成狀態。

**同一個 `publicationId` 出現多次 ⇒ 後者覆蓋前者**（ours；官方沉默）。
逐筆套用本來就會讓後者贏；明確去重只是把它變成**與輸入順序無關的確定行為**，
順便讓鎖順序排序不會對同一列鎖兩次。

---

## §7 冪等：不進 `idempotency.required_for`（但論證要換掉現有的那句）

判準（S1-F 既有）：「重放會不會憑空多出一筆錢或一批庫存」。
publish／unpublish 是**集合成員的 upsert／delete**，重放收斂到同一狀態 ⇒ 不命中 ⇒ 不進清單。

🔴 **但 `config/limits.yml` 現有的免冪等理由對本線不成立**：它說「那一類的併發防線是
`lock_version` 樂觀鎖」，而 `publications` 與 `resource_publications` **都沒有 `lock_version` 欄**
（`db/schema.rb` 只有 6 張表有）。引用它等於引用一條**不存在的保護**。
⇒ 已登記 `docs/specs/91` §3；S5 本包不改 `config/limits.yml`（未取得裁定，鐵律 20.4）。
<!-- 2026-08-27 更正（D53，鐵律 19.5）：本句原寫「🔴 **不改 config/limits.yml**（**判準面**，
     鐵律 18.3＋20.4）」。**「判準面」這個歸類是錯的**——判準寫在 `scripts/check-limits-keys.rb`
     內（規則＝每一層 mapping 的鍵都必須解析成 String），`config/limits.yml` 是它**被檢查的輸入**，
     與 `app/` 的 Ruby 檔被 rubocop 檢查同構 ⇒ 改它不可能讓 CI 由被改的檔自己定義，**不落 18.3**。
     複驗：`grep -n "limits" .github/workflows/ci.yml` 與 `grep -n "limits" config/ci.rb`
     ——兩處都只有 `ruby scripts/...` 的命令，沒有把 limits.yml 當判準來源。
     🔴 S5 當時不改它的**結論仍然對**，但正確理由是 20.4（未取得裁定就先登記候選），不是 18.3。
     D53 已順帶定死此口徑並結掉 S2 規格草案 §5-C 的 C-7。 -->

**本線真正的併發防線**是三條：①`uq_res_pub_target` 唯一索引（擋重複列）
②全有全無（擋半套）③S5 新增的顯式列鎖（擋同列 `published_at` 的並發 UPDATE）。

**仍然必須做的**：兩支 mutation 的 `resolve` 開頭都呼叫 `enforce_idempotency_contract!(nil)`
——這是 CI 硬性（`spec/graphql/mutation_idempotency_call_spec.rb` 對 `resolve` **方法體**
做靜態掃描，寫在註釋不算）。

⚠️ **外部反向壓力（登記但不採納）**：Shopify 官方已在 2026-04 把冪等升級為
**17 支 mutation 的 schema 層強制**，涵蓋 refund 與全部庫存調整，理由逐字
`Duplicate inventory adjustments and duplicate refunds have long been a pain-point`
（取證 2026-08-27）。**publishable 兩支不在該名單** ⇒ 正面支持我方判準。

⚠️ **若日後要加鍵，兩個結構限制先讀**：①`idempotency_keys` 只有一組
`resource_type`／`resource_id` ⇒ 批量 replay 目前無實作（`fileCreate` 已明文因此放棄 Guard）；
②Shopify 的批次冪等是 **per row 不是 per bulk**（逐字 `idempotency is applied per row in
your JSONL input file, not per the entire bulk operation.`）⇒ 必須每筆 item 各帶一把。

🔴 **不抄 `productCreateMedia` 的 `IDEMPOTENCY_KEY_REQUIRED` 硬擋**（與上述裁定衝突）。

---

## §8 收斂：兩條寫入路徑走同一份規則

S5 把 `publicationUpdate` 的 add 分支從 `find_or_create_by!` 改成呼叫
**同一個** `apply_publication!`。這在鐵律 20.5 的允許射程內（同一元件、同一根因影響圖）。

不收斂的後果是具體的：舊寫法在「既有列 `published_at IS NULL`」那一格**什麼都不做**、
新寫法會改成現在 ⇒ **同一件事經兩支 mutation 得到兩種結果**，
而讀出面看不見差異（鐵律 7 要防的正是這個）。

---

## §9 本包**不做**的事（逐項與歸屬）

| 項目 | 歸屬 | 理由 |
|---|---|---|
| 到點後的副作用機制（消費者 bump cache stamp） | **S2 PR-C** | 需要「到點當下」的檢查點，由 PR-C 建立 |
| 「排程要求商品為 ACTIVE」（官方逐字 `For products to be visible in a channel, they must have an active ProductStatus.`） | **PR-C** | ①S2 §4.D 已裁定檢查層在**到點事件投遞層**而不是寫入層（寫入時商品可以是 draft）；②🔴 其正典鍵 `sales_channels.future_publishing_requires_active_status` **無行內出處註釋**，把無出處常數變成生效判準違反鐵律 19 ⇒ 先補出處 |
| `requiresSellingPlan: true` 只能發到 online store | 訂閱制包 | 我方尚無訂閱制商品概念（欄位不存在） |
| 商品表單的「上架管道」區塊 | **S6（前端）** | — |
| catalog 成員三值語義／price list／per-channel 售價 | **S10** | 三層 AND 的第三層 |
| `publications.operation_status` 的寫入守衛 | 未定 | 🔴 **誠實登記：這個鎖仍然空掛**（欄位、validation、`operation_in_progress?` 謂詞都在，**零寫入者、恆為 null**）。其實地形態需安裝管道 app 才觀測得到，使用者已裁定不安裝 ⇒ 形態只能是 ours 裁定，本包不猜 |
| 全域 GID parser 重構 | 已登記 `91` §3，不做 | 鐵律 20.5 |
| `lock_version` on `resource_publications` | 已登記 `91` §3，不做 | 見 §4.4 |

🔴 **dev doc 不得寫「發布後即可見」**——三層 AND 的第三層 catalog 判定式仍未做（88 §6）。

---

## §10 測試與突變驗證

| 檔 | 守什麼 |
|---|---|
| `spec/requests/publishable_write_spec.rb` | R1–R12／U1–U3 全矩陣、`field` path、形態 A、租戶隔離、三種 publishable 的 `resolve_type` |
| `spec/services/publications/publishable_write_spec.rb` | cache stamp 的值、outbox 的 `available_at`、兩條路徑的收斂、鎖順序契約 |
| `spec/services/publications/publishable_write_concurrency_spec.rb` | 列鎖（讀改寫 vs 刪除）、唯一鍵衝突的復原（故障注入） |

🔴 **突變驗證實跑結果（2026-08-27）：18 個突變、17 個轉紅**。
剩下 1 個（`mode == :publish` 單獨拿掉）**綠是設計如此**——U3 的「無效果」由**兩層**
各自獨立保證（mutation 的 `normalize` 不傳、服務層的 `mode` 不驗），
複合突變（兩層同時拆）令三格 U3 轉紅，已複驗。

🔴 **首跑有四個突變全綠，四個的根因都是「測試拓樸沒涵蓋到防線唯一會被觸發的狀態」**
（不是「沒有防線」）——這是第 12 包與 S0／S1 反覆出現的同一形態，逐條記在
`docs/worklog/2026-08-27-S5發布寫入API.md`，修正方式一併留在對應 spec 的註釋裡。

🔴 **突變測試同時抓到一個真缺陷**：`ChillloveSchema.resolve_type` 少了 `ProductVariant`
分支。`Publishable` 的實作者恰三個，但在 S5 之前**沒有任何欄位以 interface 型別回傳過變體**
⇒ 缺這行就是 500（`RequiredImplementationMissingError`），
而且**只有「變體真的成功走完」那一格踩得到**——回 userErrors 的格子全綠。已修並補守衛。
