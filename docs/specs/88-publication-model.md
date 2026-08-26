# 88 — 發布模型：Publishable × Publication × Catalog（2026-08-14）

> 裁定來源：**71-R13-V4**（84 §1 A-5）｜實測與官方對照＝`docs/research/82` §0.2

---

## §0 一句話結論

> **「商品有沒有上架」不是一個布林值，是三個條件同時成立。**

```
Publishable（Product／Collection／ProductVariant）
  × Publication（綁一個銷售管道）
  × Catalog（該管道市場的目錄）
```

help 原文（82 §0.2）：
> For a product to be made available in a sales channel, the product must be included in any
> catalogs that you assign to the channel market, **and** it must be published to the sales channel.

🔴 **「已發布到該管道」與「在該管道市場的目錄內」是兩個獨立條件**，缺一不可上架。

---

## §1 為什麼這條擋 M1

M0 用 `products.published_at` 表達上架——那是**扁平模型**：一個商品要嘛發布、要嘛沒有，
沒有管道維度。

🔴 若 M1 照扁平模型寫完商品 CRUD、GraphQL 契約與 UI，之後要拆成三層**不是加欄位，是結構改造**：
商品表單的上架區塊、目錄（R10）、市場（R10）、代理式目錄（R13）**四個掛載點要一起改**。

⇒ 本次先建**前兩層**（M1 需要的），第三層 catalog 留欄位待 M5。
理由見 §3.2：catalog 是**讀取時的過濾條件**，加它不需要改動這兩張表的結構。

> 🔴 **2026-08-26 S0**：第三層的**實體**已建（`sales_catalogs`，migration `20260826062000`），
> 判定式仍是兩層。詳見 §3.2 的更新註與 §6。

---

## §2 資料模型

### §2.1 `publications` — 管道在本店的發布容器

| 欄 | 說明 |
|---|---|
| `shop_id` | 🔴 業務資料，帶 shop_id（鐵律 2；G24 的豁免只給身分表） |
| `name` | 顯示名（線上商店／門市 POS／代理式） |
| `channel_handle` | 管道識別，`(shop_id, channel_handle)` 唯一 |
| `auto_publish` | 預設 **true**——本尊：新增管道時既有商品**自動可用**，不要就得逐一移除 |
| `supports_future_publishing` | 預設 true；🔴 **Shop 管道為 false**（本尊限制，82 §0.2） |
| ~~`catalog_id`~~ → `sales_catalog_id` | 三層 AND 的第三層。🔴 **2026-08-26 S0 更新**：`sales_catalogs` 表已建、外鍵已上、每筆 publication 都有 catalog（migration `20260826062000`）。原文「暫無外鍵，M5 建 catalogs 時補」已完成。⚠️ **仍未轉 NOT NULL**（理由＝兩支既有 migration 會先建 publication），屬 S1 |

### §2.2 `resource_publications` — Publishable × Publication 的關聯

🔴 **命名為 `resource_*` 而非 `product_*`**：它是**多型**的——本尊的 Publishable 介面由
Product／Collection／ProductVariant 三者實作，叫 `product_*` 會讓後兩者看起來像硬塞進來的。
對應本尊的 `ResourcePublication` 型別。

**`published_at` 的三種語義**：

| 值 | 語義 |
|---|---|
| `NULL` | 尚未發布到本管道 |
| 過去時間 | 已發布 |
| **未來時間** | **排程發布**（future publishing） |

**本尊的兩條排程限制**（已寫成 model validation 並有測試）：
1. 🔴 **不支援排程的管道不得排程**——能力旗標在 publication 上（`supports_future_publishing`）；
2. 🔴 **不得為單一 variant 排程**。

另有一條**本尊限制未實作**：排程發布要求商品為 `Active` 狀態才生效。
那是**跨表**條件（要看 `products.status`），留待 M1 商品 CRUD 一併處理（§5）。

---

## §3 三層 AND 的讀取規則

### §3.1 完整判定
```ruby
上架? = resource_publication.published?(at:)          # 第二層：已發布到該管道
      && publication 的 catalog 包含這個 publishable   # 第三層：在該管道市場的目錄內
```

🔴 `ResourcePublication#published?` **只是第二層**。model 的註釋已明寫：
「只用這個方法當『商品是否可購買』會漏掉市場目錄那一層。」

### §3.2 為什麼第三層可以延後
catalog 是**讀取時的過濾**，不是寫入時的結構：加上它等於在查詢後面多一個條件，
`publications` / `resource_publications` 兩張表的欄位與索引都不用改。
⇒ M5 建 markets/catalogs 時，只需補 `publications.catalog_id` 的外鍵與查詢條件。

> 🔴 **2026-08-26 S0 部分完成**：`sales_catalogs` 表與外鍵已建（migration `20260826062000`），
> 但**判定式沒有變**——`Product.published_on` 仍只有兩層 EXISTS。
> 原因是本節這句話只說對了一半：第三層確實是讀取時的過濾，但它要過濾的是
> **catalog 的成員集合**，而成員語義是三值（Included／Excluded／All，`docs/research/82` §9.5c）
> 且**非同步計算**（進行中會鎖住逐商品切換）⇒ 需要一張成員表，那不是「查詢後面多一個條件」。
> 成員表屬 S10。在它存在之前第三層對每個 publishable 恆真，加進 SQL 只多一次 JOIN 不改結果。
> 落地狀態表＝`docs/plans/2026-08-26-S0-方案D-schema設計.md` §7.2。

---

## §4 `products.published_at` 與 `collections.published_at` 皆已移除

🔴 **同一件事不留兩個事實來源**——這正是鐵律 7 要防的形態：兩處都能寫，遲早不一致。

- 既有值已在 migration 中搬進 `resource_publications`（線上商店管道）；
- 排程發布的語義**沒有消失**，它搬到了 `resource_publications.published_at`，且變成 **per channel**；
- 每間店在 migration 中已建一個 `online_store` publication。
  🔴 **建立商店的流程必須連帶建立它**（M1 待辦，§5）。
- `collections` 的索引由 `(shop_id, collection_type, published_at)` 改為
  `(shop_id, collection_type)`——列表仍要照類型篩，只是不再篩上架狀態。

<!-- 2026-08-14 補（PR #24 的 Claude 驗收「🔴 必須修」第 1 條）。本節原文只寫 products。
     🔴 `collections` 本來就有一個語義完全相同的扁平 `published_at`，而本次又把 Collection
     接進 `resource_publications`（`has_many ... as: :publishable`）
     ⇒ **Collection 同時有兩個上架事實來源**，正是本節自己要防的形態。
     我把移除 products 的理由寫得很清楚，卻沒有把同一條理由套用到同批接進來的 Collection——
     而且 §5／§6 也沒有登記成刻意分期，所以它是**漏掉不是分期**。
     教訓：**「同一件事不留兩個來源」要對這一批接進來的每一個型別各檢查一次**，
     不能只檢查觸發這次改動的那一個。 -->

### §4.1 多型的代價：跨租戶只能靠 model validation

🔴 `acts_as_tenant` **不驗證多型外鍵的租戶歸屬**（gem 原始碼
`acts_as_tenant-1.0.1/lib/acts_as_tenant/model_extensions.rb:57-62` 明確排除），
且 MySQL **無法對多型欄位建外鍵** ⇒ `publication` 有複合外鍵、`publishable` 沒有
⇒ **gem 層與 DB 層都沒有人擋**。

保護只有一道：`ResourcePublication#publishable_belongs_to_same_shop`。

常規請求下 `belongs_to` 的存在性驗證 ＋ `default_scope` 會**順帶**擋住跨店 id，
但那是偶然的副作用，在 `ActsAsTenant.without_tenant`（資料遷移／seeds／維運腳本）、
明確指定 `shop_id`、或 `insert_all`／`upsert_all` 之下全部失效。
⚠️ **本驗證擋不住 `insert_all`／`upsert_all`**（Rails 一律跳過 validation）。

---

## §5 待辦（M1 承接）

| # | 事項 | 為什麼不在本次做 |
|---|---|---|
| ~~1~~ | ~~**建店時自動建 online_store publication**~~ | ✅ **2026-08-15 結案**，見下方批註 |
| ~~2~~ | ~~**`auto_publish` 的實際行為**~~ | ✅ **2026-08-26 結案（第 12 包）**，見下方批註 |
| 3 | **排程發布要求商品為 Active** | 跨表條件，隨商品狀態機一起做 |
| 4 | **商品表單的「上架管道」區塊** | UI，前端包 |
| ~~6~~ | ~~**publication 的建立／更新／刪除 API**~~ | ✅ **2026-08-26 結案（S1）**，見下方批註 |

<!-- 2026-08-26 結案（#6，S1）。交付＝`publicationCreate`／`publicationUpdate`／
     `publicationDelete` 三支 mutation ＋ `Publication` type ＋ `publications` query
     ＋ `Publications::Write`（唯一寫入入口）。全文＝`docs/dev/m2-publication-lifecycle.md`。

     🔴 **本條原本不在本節清單裡**，是 S1 的研究階段掃描倉庫時才浮現的缺口：
     `resource_publications.published_at` 在 S1 之前**只在建立時被寫入**
     （`Publications::Materialize` 兩條路徑 ＋ 兩支 migration 的原生 SQL），
     全倉**零 UPDATE、零 DELETE、零 publish／unpublish 入口**。
     ⇒ §2.1 指派給 S1 的「`sales_catalog_id` 轉 NOT NULL」與「進行中的鎖」
     都建立在一個**還不存在的動作**上。S1 先補那個動作。

     ⚠️ **仍未做**（逐條理由見 dev doc §6）：`defaultState: ALL_PRODUCTS`（非同步 add-all）、
     `operation_status` 的寫入者、`sales_catalog_id` 轉 NOT NULL、逐資源的
     `publishablePublish`／`publishableUnpublish`（分步方案劃給 S5）。 -->

<!-- 🔴 2026-08-26 S1 對本檔 §2.1 的一處更正：該節寫「`catalog_id` 三層 AND 的第三層；
     **暫無外鍵**，M5 建 catalogs 時補」——外鍵已於 S0 PR A 補上
     （`fk_publications_sales_catalog_id`），欄位也已改名 `sales_catalog_id`。
     ⚠️ `db/schema.rb` 該欄的**欄位註釋**仍是舊文（改註釋要一支 migration）
     ⇒ 登記於 `docs/specs/91-pit-register.md` §3.20，隨下一支動 publications 的 migration 一併更正。 -->
| ~~5~~ | ~~**`ProductVariant` / `Collection` 展開**~~ | ✅ **2026-08-26 結案（第 12 包）**，見下方批註 |

<!-- 2026-08-26 結案（#2 與 #5，第 12 包）。交付＝`Publications::Materialize`
     ＋ Product／ProductVariant／Collection 三個 `after_create`
     ＋ 回填 migration `20260826060000`（配對 spec 含 source-guard）。
     完整說明＝`docs/dev/m2-publication-model.md`；本尊實測憑證＝`docs/research/82` §8。

     🔴 **本條的關鍵發現：`auto_publish` 有兩半，而 §2.1 只寫了我方不會先遇到的那一半。**
     §2.1 把它寫成「新增管道時既有商品自動可用」——那是**新增 publication** 的那一半，
     而 v1 建店只建 online_store、之後沒有新增管道的流程，永遠遇不到。
     先遇到的是另一半：**新增商品時要不要填既有管道的列**。
     實測本尊（82 §8.4①）：新增商品表單在**存檔前**就顯示 `All channels`，存檔後預設變體
     即有全部管道的列 ⇒ auto_publish 同時管這一半。
     不填的後果：全站商品永遠不可購買，而所有 spec 照樣綠。

     ⚠️ **§2.1 那一半仍是 help 單源、本輪未實測**（需安裝新管道 app 才測得到）
     ⇒ 登記於 82 §8.7 與 `m2-publication-model.md` §8 的 P12-B3。

     🔴 **本次同時證實了 §3.1 的三層 AND 是「讀取時計算」而非「寫入時串聯」**（82 §8.4③ 決定性實驗）：
     商品層取消發布某管道後，變體層的列**原封不動**。這一條決定了不變量不能靠寫入時
     串聯維持——照那個直覺做會在「父層關了又開回來」時把使用者刻意關掉的子層設定
     一起還原，且還原不回去（資訊已被覆蓋）。 -->

<!-- 2026-08-15 結案（#1）：`Shop#after_create :create_default_publication`
     ＋ `20260815000010_backfill_missing_online_store_publication`。
     🔴 **這個缺陷有兩半，缺一半就等於沒修**：callback 修未來、migration 修歷史。
     `20260814200000` 只回填了它執行當下既有的店，之後每一次 seeds／spec／手動建店
     都產生一間沒有管道的店——而且**不拋任何錯**，只是那間店所有商品都上不了架。

     掛在 model callback 而不是 service：本倉庫目前沒有 service 層也沒有 shops
     controller，而 callback 的好處是**每一條建店路徑都涵蓋**（seeds／factory／rake／
     未來的 M8 平台後台），不會有人新開一條路徑而忘了建管道。

     🔴 **刻意不順便回填 `resource_publications`**：`20260814200000` 當時是把
     `products.published_at` 原樣搬過去，但那個欄位已被同一支 migration 移除，
     時間窗裡的商品從來沒有過它 ⇒ 只剩兩個都要靠猜的選項：填 `NOW()` 等於實作
     `auto_publish` 行為（＝下面的 #2，明確延後），填 `NULL` 又與該 publication 自己的
     `auto_publish: true` 自相矛盾。⇒ 整包留給 #2 一次做對。

     ⚠️ **只建 `online_store` 一個管道**。`docs/research/82` §0.1 實測本尊的「已安裝管道」
     有三個（銷售點／線上商店／Shop），但本規格全篇只規範 online_store，
     其他管道由誰在什麼時候建**沒有規格** ⇒ 不猜，登記於此。 -->

---

## §6 誠實聲明

- ~~**第三層 catalog 完全沒做**，只留了欄位。~~ 🔴 **2026-08-26 S0 更新**：
  `sales_catalogs` 表、回填、外鍵與寫入者都已交付，**每筆 publication 都有 catalog**。
  仍未做的是**成員三值語義與 price list**（屬 S10）⇒ 本檔標題寫「三層」而
  **判定式**仍是兩層。這仍是刻意的分期，界線改由
  `docs/plans/2026-08-26-S0-方案D-schema設計.md` §7.2 定義。
- ~~**`ProductVariant` 與 `Collection` 是最小 model**~~／~~**`auto_publish` 目前只是一個欄位**~~
  🔴 **2026-08-26 更正（第 12 包）**：這兩句在 2026-08-14～2026-08-26 之間為真，現已不成立。
  三個型別都掛上了 `after_create :materialize_publications`，`auto_publish` 是該生產者的判準。
  原文保留在此以維持沿革可讀（鐵律 19.5）。現值見 `docs/dev/m2-publication-model.md`。
- 🔴 **多型關聯拿不到 DB 層外鍵**（§4.1）。要有底線防護只能改成「逐型別各一張關聯表」，
  代價是三張近乎相同的表。本次選多型，**並把這個取捨明寫出來**而不是假裝沒有。
  `insert_all`／`upsert_all` 這條路徑目前**沒有任何防護**。
- 本檔**不涵蓋** 71-R8-V4（系列建立式的概念差，本尊 2026 改為「來源」卡）——那條仍未裁定。
