# m2 — `resource_publications` 的完整語義（S2）

> 分步方案 `docs/plans/2026-08-26-發布與可見性-分步執行方案.md` 的 **S2**。
> 前置＝S0（管道身分）與 S1（publication 生命週期，`docs/dev/m2-publication-lifecycle.md`）。
> 研究全文＝`docs/plans/2026-08-26-S2-規格草案.md`；admin 實測＝`docs/research/82-admin-channels.md` §12。

---

## §1 🔴 本尊有兩個讀出投影，同名布林在一個狀態上**答案相反**

官方原文逐字（取證 2026-08-26）：

- **`ResourcePublication`（V1）**
  <https://shopify.dev/docs/api/admin-graphql/latest/objects/ResourcePublication>
  > Whether the resource publication is published. **Also returns true if the resource
  > publication is scheduled to be published.** If false, then the resource publication is
  > neither published nor scheduled to be published.

- **`ResourcePublicationV2`**
  <https://shopify.dev/docs/api/admin-graphql/latest/objects/ResourcePublicationV2>
  > Whether the resource publication is published. If true, then the resource publication is
  > published to the publication. **If false, then the resource publication is staged to be
  > published to the publication.**

| 實際狀態 | V1 `isPublished` | V2 `isPublished` |
|---|---|---|
| 已發布（到點） | true | true |
| 🔴 **已排程未到點** | **true** | **false**（staged） |
| 既未發布也未排程 | false | **該列不存在** |

第三列的官方依據逐字：

> Unlike `ResourcePublication`, an instance of `ResourcePublicationV2` can't be unpublished.
> It must either be published or scheduled to be published.

⚠️ **「相反」兩個字是由上面兩段原文導出的判斷，不是官方原文**——任何引用這個結論的地方
都要一併附原文（鐵律 19.1）。
⚠️ 官方在 V2 的**欄位描述**用 `staged`、在**物件描述**用 `scheduled`，且**從未把兩詞等同**
⇒ 我方註釋兩詞並列，不合併成單一術語。

### 1.1 另外兩個 V1 專屬的誤用源

1. **`publishDate` 是 `DateTime!`（non-null）**，官方逐字
   `If the product isn't published, then this field returns an epoch timestamp.`
   ⇒ 客戶端**不能**用 `publishDate == null` 判斷未發布。
   🔴 **epoch 的確切字面值、時區與序列化格式＝未取得**；**不得**在規格或 fixture 寫死
   `1970-01-01T00:00:00Z`。
2. **`channel` 欄位已 deprecated**（V2 沒有這個欄位）。

---

## §2 我方只實作 V2，不提供 V1（ours 偏離）

逐條理由：

1. **admin SPA 是唯一客戶端**。V1 存在的理由（`Channel.*PublicationsV3` 那條線）我方沒有。
2. V1 帶上面兩個已知誤用源，兩者都是「在**非排程態**下 100% 測綠」的形態。
3. **V2 是 V1 的功能超集**：`resourcePublicationsV2` **有** `onlyPublished`（Boolean, default true）
   **和** `catalogType`；V1 只有前者。本輪定點複驗
   <https://shopify.dev/docs/api/admin-graphql/latest/interfaces/Publishable>（2026-08-26）。
4. `catalogType` 是唯一能表達 market／company_location 目錄發布狀態的路徑（S10 只能走 V2）。

🔴 **不得寫「官方建議改用 V2」或「V1 是 legacy」**——**官方沒有這句**（未取得）。
可以說的只有「官方指南只教 V2」。兩者在 latest 皆**無** deprecation 標記，並存已逾六年。

🔴 **日後若要補 V1 相容面，必須用不同型別承載**，不得共用同一個 `is_published` 欄名——
形態與鐵律 3 的 `Money::Storage` / `Money::PspMinor` 型別隔離同構：
同名不同義的兩個值放同一個型別上，遲早有人拿錯。

---

## §3 交付了什麼

| 面 | 檔案 | 內容 |
|---|---|---|
| 資料 | `app/models/resource_publication.rb` | 三個 scope：`currently_published`／`staged`／`published_or_staged` |
| 契約 | `app/graphql/types/resource_publication_v2_type.rb` | V2 投影型別 |
| 契約 | `app/graphql/types/interfaces/publishable.rb` | `Publishable` interface（Product／Collection／ProductVariant 三者 implements） |
| 修正 | `app/graphql/types/publication_type.rb` | 🔴 C-10（見 §4） |
| 規則 | `app/models/resource_publication.rb` | 變體排程守衛改引 `config/limits.yml`（鐵律 6） |

---

## §4 🔴 修掉 S1 交付的一個真 bug（C-10）

S1 的 `PublicationType#published_resource_count` 實作是：

```ruby
object.resource_publications.count
```

**完全不看 `published_at`**。在 S1 當下無害（生產上 `published_at` 恆為過去），
但**排程一存在就是錯值**——一筆排程到下個月的商品會被算成「已發布」。

修法：拆成兩個語義各自明確的欄位，各自走 model scope（唯一產生處，鐵律 7）：

| 欄位 | 語義 |
|---|---|
| `publishedResourceCount` | **已到點**的列數 |
| `stagedResourceCount` | 已排程**未到點**的列數 |

⚠️ `published_at IS NULL` 的列**兩個都不算**——它既不是已發布也不是已排程。

---

## §5 🔴 排程態是強制測試維度（與鐵律 3 的 zero-decimal 陷阱同型）

兩種投影的語義分歧**只在「已排程未到點」這一格顯現**：
已發布時兩邊都 true，完全未發布時 V1 是 false 而 V2 根本沒有這一列。

⇒ **一份沒有排程 fixture 的測試矩陣會 100% 全綠，而實作可以完全做錯。**

S2 研究階段實查（HEAD `b399d79`）：`Collection.with_member_counts` 組與
`ProductVariant.purchasable_on` 組**各自零個**未來 `published_at` 的格子；
`spec/requests/publication_lifecycle_spec.rb` 的 `from_now` 命中數為 **0**。

本步補上 `spec/models/scheduled_publishing_spec.rb`（七組判準）與
`spec/requests/resource_publication_projection_spec.rb`。

**九個突變複驗，全部轉紅**（本輪實跑，逐字）：

| 突變 | 結果 |
|---|---|
| `PUBLISHED_SQL` 拿掉 `<= :at` | `87 examples, 9 failures` |
| `#published?` 不比較時間 | `87 examples, 3 failures` |
| `currently_published` 收排程中的（V1 語義） | `87 examples, 3 failures` |
| `staged` 收全部非 NULL | `87 examples, 2 failures` |
| `published_or_staged` 收 NULL 列 | `87 examples, 2 failures` |
| `publishedResourceCount` 退回 S1 的錯版本 | `87 examples, 2 failures` |
| 投影忽略 `onlyPublished` | `87 examples, 1 failure` |
| `isPublished` 不走 `published?` | `87 examples, 1 failure` |
| 變體排程守衛拿掉 limits 判準 | `87 examples, 1 failure` |
| 還原後 | `87 examples, 0 failures` |

🔴 第一個突變拉紅 **9** 格，證實 `<= :at` 這個謂詞跨四個消費者承重
（`Product.purchasable`／`discoverable`／`published_on`、`ProductVariant.purchasable_on`、
`Collection.with_member_counts`）。

---

## §6 「到點生效」我方已經做完了——**不要**再加任何翻狀態的 job

現況（唯一產生處）：

```
app/models/resource_publication.rb
  PUBLISHED_SQL = "%<a>s.published_at IS NOT NULL AND %<a>s.published_at <= :at"
  def published?(at: Time.current) = published_at.present? && published_at <= at
```

⇒ **到點那一刻資料庫不需要任何寫入**，商品自動出現在查詢結果裡。

🔴 **任何「掃描 due 的列並 UPDATE 成已發布」的設計都是自創形態 ＋ 鐵律 7 違反**
（製造第二個事實來源）。Saleor 走同一條路（`publicationDate`＋查詢時判定）；
Medusa 走反例（外掛 cron 翻 status），缺點正是我方要避開的：
cron 粒度決定精度、job 沒跑就永遠不上架、無法表達「已排程」中間態。

---

## §7 誠實聲明（本步**沒有**做的）

| # | 內容 | 為什麼 |
|---|---|---|
| S2-A | **沒有任何能修改既有列 `published_at` 的路徑** | `Publications::Write` 的 add 走 `find_or_create_by!` 的 **create-only** 區塊（既有列完全不寫 `published_at`）、remove 是**硬刪列**。⇒ **設排程／改期／取消排程都還做不到**，那是 S5 的寫入面。本步交付的是**讀取面在排程態下的正確行為** |
| S2-B | 🔴 **cache stamp 到點不會前進** | `products.publications_updated_at` 只在寫入路徑被 bump，而排程到點那一刻**沒有任何寫入** ⇒ 以該戳為 key 的前台快取會在邊界之後繼續供應舊內容，**且不拋任何錯**。修法方向（零新增基建）：建立排程列的同一 transaction 內寫一筆 `event_outbox`，`available_at: published_at`，消費者到點 bump。⚠️ 那會是 `available_at` 未來值的**第一個使用者**，既有 spec 從未覆蓋該分支 ⇒ 隨 S5 一起做 |
| S2-C | **「到點時商品必須是 ACTIVE」未實作** | help 明文（`Products must be in Active status for future publishing to work.`）但 **shopify.dev API 側完全沉默**。且它的正確位置是「到點事件的投遞條件」不是可見性謂詞——放進謂詞會打爛 `purchasable_statuses` 含 UNLISTED 的既有裁定。隨 S2-B 一起做 |
| S2-D | **時區分層未實作** | `shops.timezone` 欄位存在（default `Asia/Hong_Kong`）但**app 層零讀取者零寫入者** ⇒ 它現在一定是預設值，任何依賴它的商家自訂行為**還不存在**。**不得寫成「沿用既有店鋪時區設定」**。輸入層要接時區時再做 |
| S2-E | **`catalogType` 參數未實作** | 我方 catalog 成員表屬 S10；現在加參數只會是一個永遠沒效果的參數 |
| S2-F | **V1 投影不做**（見 §2） | |
| S2-G | **`Publishable` 的其餘四個非 deprecated 欄位不做** | `publishedOnPublication`／`resourcePublicationsCount`／`availablePublicationsCount`／`unpublishedPublications`。⚠️ 其中兩個的官方描述含 `feedback errors`，而**我方沒有 feedback 概念** ⇒ 照抄名字會給出不同語義。逐條理由在 interface 檔頭 |
| S2-H | **本尊 connection、我方回 list** | 集合大小由本店 publication 數界定（`max_channels` 文檔未載、實測三個管道）。S10 的 catalog publication 大量出現時要改 |

---

## §8 未取得（S2 射程內仍未解的）

| # | 未取得 | 怎麼取得 |
|---|---|---|
| S2-U1 | 🔴 **Shop 管道到底支不支援排程**：help 說 `Future publishing isn't available for the Shop app.`，但 `82` §10.3 的實測 payload 顯示 Shop 的 `supportsFuturePublishing: **true**` | 兩者可能不同層（help 講商家功能、payload 講能力旗標）。需在測試店對 Shop 管道實際設排程並記三層。**取得前不得改 seed 值** |
| S2-U2 | **V1 未發布時 epoch 的確切字面值** | 官方只寫 `an epoch timestamp`。需實測 payload |
| S2-U3 | **官方為何並存兩個投影** | 已窮盡 changelog／release notes／社群鏡像 ⇒ 官方從未解釋。只知引入時間是 2020-10 版 |
| S2-U4 | **排程輸入以哪個時區解讀** | 官方無正面陳述。admin UI 內嵌顯示 `GMT+8`（`82` §12.3），help 要求商家先確認 Store defaults ⇒ 只能推到「店鋪層」，API 契約未取得 |
| S2-U5 | **到點的執行精度與延遲** | 官方無任何數字或 SLA |
| S2-U6 | **API 層是否也拒絕過去的排程時間** | UI 的月曆把過去日期禁用（`82` §12.3），API 層未知 |
| S2-U7 | **UNLISTED／ARCHIVED 商品到點的行為** | 官方只講 Draft，**不得由 Draft 外推** |
| S2-U8 | **到點失敗後排程本身的去向**（保留／清除／重試）、是否 catch-up | 官方全面沉默 ⇒ 我方要自訂，屬裁定項 |

---

## §9 一條官方自相矛盾與一條我方規格矛盾

**官方自相矛盾**：支援排程的管道範圍。
API 兩頁寫 `Only online store channels support future/scheduled publishing`（單一管道），
help 寫 `your online store and for some sales channels`（複數，未列舉）。
官方未正面調和 ⇒ 我方以**能力旗標**（`publications.supports_future_publishing`）承載，
**不硬編「只有 online store」**。實測支持 API 那一側：admin 的
`Schedule publishing` 圖示**只出現在 Online Store 那一列**（`82` §12.3）。

**我方規格矛盾**：`docs/research/90` 的 V-4 逐字寫「variant 不得排程發布
（**publishDate 必須為空**）」，而 `variant_cannot_be_scheduled` 只擋**未來**時間、
允許 variant 帶過去時間的 `published_at`——那正是 `Publications::Materialize` 的既有寫法。
照 V-4 字面收緊會打爛既有生產者 ⇒ **本輪維持現行**，登記 `docs/specs/91` §3.21。
