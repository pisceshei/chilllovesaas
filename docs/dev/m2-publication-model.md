# m2 — 發布模型收口：生產者、回填、可購買／可發現

> 第 12 包。前身＝`m1-publication-model.md`（2026-08-14 建的兩張表與 model）。
> 本包補上那份文件明文延後的**寫入端**（`docs/specs/88` §5 待辦 #2／#5），
> 並在寫入端就位後才打開讀取端。
>
> 🔴 **動這個檔前先讀 §3（寫入契約狀態矩陣）與 §6（消費者影響圖）。**

---

## §1 這一包解掉的是什麼

`resource_publications` 這張表自 2026-08-14 建立起就存在，但**倉庫裡沒有任何一行程式碼會建立它的列**。

這個缺陷的形態很特別，值得單獨記一筆：

| | |
|---|---|
| 症狀 | 沒有。表是空的，沒有人讀它，一切正常 |
| 打開讀取面之後的症狀 | **全站每個商品瞬間變成不可購買**，而近千支 spec 全綠 |
| 為什麼 spec 抓不到 | 沒有任何一支 spec 斷言過「新商品必須有發布列」——每一支測試都**先種資料**再驗讀取 |

`app/models/product.rb` 當時的處置是正確的：**不開讀取面**，並把理由寫進註釋
（「一個叫 `purchasable` 的 scope 只做了三層 AND 的第一層，名字在說謊」）。
本包補齊寫入端後才解除。**順序不可倒。**

---

## §2 本尊怎麼做（六條實測結論）

證據全文＝`docs/research/82-admin-channels.md` §8（2026-08-26 實測）
＋ shopify.dev／help.shopify.com 官方取證（同日）。這裡只列直接寫成程式碼的：

| # | 結論 | 實作落點 |
|---|---|---|
| 1 | 建立當下就物化，不是 lazy | 三個 `after_create` |
| 2 | 稠密：每個變體都有自己的列，不是「無列＝繼承父層」 | `Publications::Materialize` |
| 3 | 🔴 層與層**不連動**：商品層寫入不改寫變體層 | 沒有任何串聯程式碼——這是「刻意不寫」的一條 |
| 4 | `status` 與 publication **正交** | `Product.purchasable` 把兩者分開 AND，不互相寫入 |
| 5 | 可見性＝三層 AND，在**讀取時**計算 | `Product.published_on` 的兩個 EXISTS |
| 6 | 變體生產者是否跟隨父商品＝**我方裁定**（ours） | 見 §4 |

**本尊官方的可見性真值表**（`shopify.dev/docs/apps/build/sales-channels/product-publishing`，
取證 2026-08-26，逐字）：

| Product state | Variant state | Visible to buyers |
|---|---|---|
| Published | Published | Yes |
| Published | Unpublished | No |
| Unpublished | Published | No |
| Unpublished | Unpublished | No |

⇒ 這就是 `published_on` 兩個 EXISTS 的來源。官方另有一句對應「全部變體都下架」的情形（help，逐字）：
> If every variant of a product is unpublished from a channel or catalog, then the parent product
> itself is entirely hidden from that channel or catalog until you republish at least one variant.

---

## §3 寫入契約狀態矩陣

`Publications::Materialize.for(publishable, at:)`

| 起始狀態 | 動作 | 結果 | 回傳 |
|---|---|---|---|
| 該店無任何 `auto_publish` 管道 | — | 不建列 | `0` |
| 有 N 個 `auto_publish` 管道、該資源零列 | 建 N 列 | 全部 `published_at = at` | `N` |
| 有 N 個、其中 M 個已有列 | 只建缺的 | **既有列的 `published_at` 不動** | `N - M` |
| `auto_publish = false` 的管道 | — | **不建列** | 不計入 |
| `publishable.id` 為 nil（未存檔） | — | 不建列 | `0` |
| `publishable.shop_id` 為 nil | — | 不建列 | `0` |
| 不在 `PUBLISHABLE_TYPES` 內的類別 | — | 不建列 | `0` |
| 無 `current_tenant`（seeds／rake／migration） | 照常建列 | 用 `publishable.shop_id` | `N` |
| `current_tenant` 是**別間店** | 照常建列 | 用 `publishable.shop_id`，**不受污染** | `N` |

🔴 **最後兩列是本服務最重要的性質**，也是它整段跑在 `ActsAsTenant.without_tenant` 內的唯一理由：

- 沒有 `current_tenant` 而帶 default scope 查 `Publication` ⇒ 直接 `NoTenantSet`，
  而它炸在「建立商品」而不是「建立管道」，極難歸因；
- `current_tenant` 是別間店 ⇒ default scope 把管道過濾成 0 列 ⇒ **一列都不建、而且不拋錯**。
  那是「回報成功但什麼都沒做」的形態，比直接炸危險得多。

**隔離沒有變弱**：`shop_id` 一律取自 `publishable` 本身，查詢與寫入都逐句明帶 `shop_id`
（鐵律 2 配套條款②：豁免的是「表有沒有欄」，不是「查詢帶不帶條件」）。

---

## §4 🔴 變體生產者不跟隨父商品——這是 ours，不是照抄

**三份互相拉扯的證據，全部照實登記（鐵律 19）：**

**(a) 官方文檔說「跟父商品」。** `shopify.dev/docs/apps/build/sales-channels/product-publishing`
（2026-08-26）逐字：
> the variant is created with the default state of published to all channels and catalogs
> where the parent product is published.

**(b) 我方實測的儲存狀態不是那樣。** 父商品當時只發布到 2 個管道，新增的兩個變體各拿到 3 個
（82 §8.4②）。但這個實驗有一個**排除不掉的替代假說**：新變體可能是由前身
`Default Title` 變體衍生的，而它本來就有 3 列。⇒ 登記為**未取得**。

**(c) 兩邊其實不衝突，因為「儲存」與「生效」是兩回事。** 同輪在 UI 上拿到直接證據——
對變體開 Manage publishing 時，父商品沒發布的那個管道**呈灰、帶 ⓘ、而 toggle 仍是開的**，
提示逐字：
> **Product must be published to the channel before variants can appear**

**我方選「全部 `auto_publish` 管道」，理由是後果而非權威：**

1. 與實測的儲存狀態一致；
2. 與本尊自陳的 opt-out 模型一致（官方逐字：「Variants default to published (opt-out model)」、
   「Variant publishing state persists across product publishing changes, so you can configure
   variant visibility **before** publishing the product」）；
3. 商家後果較好——商品日後發布到新管道時，變體立刻跟著可見，不必逐一補發布；
4. 🔴 **兩種選法對「可見性」的結果完全相同**，因為閘控在讀取層的 AND，不在寫入層。

⇒ 這是一個**低風險的裁定**：選錯了也不會產生錯誤的可見性，只影響「日後開新管道時要不要手動補」。

---

## §5 讀取契約

```ruby
Product.purchasable(publication:, at: Time.current)
Product.discoverable(publication:, at: Time.current)
```

**管道是必填參數，沒有「任一管道」的版本。** 買家面的問題永遠是「這個商品在我正在逛的
這個店面買不買得到」。v1 只有 `online_store` 一個管道，呼叫端傳 `Publication.online_store`；
寫成「任一管道」現在也會過，但等第二個管道出現時語義會**靜默**變錯
（POS 專屬商品開始出現在線上商店的搜尋結果裡）。

**不變量 `discoverable ⊆ purchasable` 是定理不是測試項**：

```ruby
def self.discoverable(publication:, at: Time.current)
  purchasable(publication:, at:).where(status: DISCOVERABLE_STATUSES)
end
```

`discoverable` **由 `purchasable` 導出**，再收窄狀態集合，而
`DISCOVERABLE_STATUSES ⊆ PURCHASABLE_STATUSES`（`config/limits.yml` 的
`discoverable_subset_of_purchasable: true` 是該包含關係的正典）。
兩份各自獨立的 SQL 會讓不變量退化成「要靠測試盯著別漂移」的性質，而漂移的後果是
把買家從搜尋結果送進買不了的頁面（soft-404）。
`spec/models/product_spec.rb` 有一格**結構性斷言**盯著這個導出關係。

**NULL 在 `published_on` 裡是安全的**——那裡是**正向** EXISTS，`published_at IS NULL`
的列單純不匹配即可。🔴 **日後若要加「未發布」的反向 scope，必須用
`NOT COALESCE(<expr>, FALSE)`**，不能直接對這段取反：第 11 包在三值邏輯上踩了三次
（`RuleCompiler` 的字串否定、數值否定、block 級 `NOT`），根因都是對可能為 NULL 的謂詞取反。

**第三層 catalog 不在這裡**（88 §3.2 裁定延後到 M5）。完整判準是三層 AND，本包做前兩層。

> 🔴 **2026-08-26 S0 更新**：`sales_catalogs` 表已建、每個 publication 都有一筆 catalog
> （migration `20260826062000`），但**判定式沒有變**——`published_on` 仍只有兩層 EXISTS。
> 理由：第三層要判的是「這個 publishable 在不在這個 catalog 的成員集合裡」，而成員語義
> 是三值（Included／Excluded／All，`82` §9.5c）且**非同步計算**，屬 S10。
> 在成員表存在之前，第三層對每個 publishable 都恆真 ⇒ 加進 SQL 只會多一次 JOIN、不改結果。
> ⚠️ S10 補上時，`ResourcePublication.published_exists_sql` 是**唯一**要改的地方
> （見 P12-B13：Ruby 版 `published?` 目前零生產呼叫端，改一邊會靜默分叉）。

---

## §6 消費者影響圖

| 消費者 | 關係 | 現況 |
|---|---|---|
| `Collections::RuleCompiler` | 智慧系列成員判定用的是 `p.status <> 'archived'`（`PRODUCT_ELIGIBLE_SQL`），**不是** `purchasable` | 🔴 **本包刻意不改**——改成 `purchasable` 是語義變更（智慧系列會開始排除未發布商品），要另外裁定。已登記 `91` §3 |
| 前台商品頁／系列頁（第 33／34 包） | 要用 `purchasable` | 尚未建立 |
| 前台搜尋索引 | `config/limits.yml` 已定 `scope: discoverable` | 尚未建立 |
| sitemap／feed／JSON-LD（第 35 包） | `unlisted_excluded_from` 已定正典 | 尚未建立 |
| 匯入器（第 20+ 包） | 🔴 見下 | 尚未建立 |
| 六支併發 spec 的 `purge!` 幫手 | 用 `delete_all` 清表（繞過 `dependent: :destroy`）⇒ 發布列殘留會讓 `fk_res_pub_publication_id` 擋住刪 `Publication` | 本包已各補一行「先刪 `resource_publications`」 |
| `spec/models/resource_publication_spec.rb` | 每一格都要手動建列才驗得到 validation，而自動列會撞唯一性 | 本包已加 `without_auto_publications` 幫手 |

🔴 **唯一的未來炸點：`insert_all`／`upsert_all` 繞過 callback。**

生產者掛在 model callback 上，涵蓋 GraphQL、seeds、factory、rake 每一條路徑——
**但批量寫入一律繞過**。匯入器（第 20+ 包）若走 `insert_all`，匯進來的商品會**全部沒有發布列**
⇒ 前台全部看不到，而且不拋任何錯。

**做匯入器的人必須做兩件事之一**：①逐列走 model 建立；②批量寫入後**明確呼叫**
`Publications::Materialize.for`（它是冪等的，重跑安全）。

這條與 `resource_publication.rb`／`product_variant.rb` 既有的 `insert_all` 限制聲明是同一族——
多型關聯拿不到 DB 外鍵、digest 與租戶歸屬也都靠 model 層，批量寫入路徑目前**沒有任何防護**。

---

## §7 回填 migration 與它的 spec

`20260826060000_backfill_resource_publications` **是一個薄呼叫端**，實作在
`Publications::Materialize.backfill_all!`。

🔴 **callback 修未來、migration 修歷史，兩半缺一等於沒修**——這與 `88` §5 #1
（建店預設 publication）是同一條教訓，那次也是兩半。

### §7.1 🔴 為什麼實作不在 migration 裡（對抗審查換來的）

初版把回填邏輯**抄一份**寫在 migration 裡，而它的 spec 又抄了第三份
⇒ **規則有三份實作，而測試守的是它自己那一份**。兩位審查員以不同方法各自實測證明：

| 對 migration 施的突變 | 後果 | 當時的 spec |
|---|---|---|
| 把 `where(shop_id:)` 刪掉一個 token | 寫出跨租戶的列（實測 `mismatched=2`）——`insert_all` 繞過 validation、多型欄位無外鍵，**兩層都不擋**，而 `down` 不可逆 | **38 examples 0 failures** |
| 把 `auto_publish: true` 拿掉 | 回填成完全相反的管道集合 | **全綠** |

當時副本與本體之間唯一的機械連結是一個掃字串的 source-guard，而那種守衛**可以被一行註釋
騙過**（實測：`ActsAsTenant.without_tenant do` → `begin # ActsAsTenant.without_tenant`，守衛照樣過）。

⇒ 現在：邏輯一份（服務層）、**spec 載入並執行真的 migration 類別**、字串守衛全數退場改由行為守住。

### §7.2 🔴 一句被證偽的因果（保留原文並更正）

初版的 migration 與 spec 都宣稱：

> 拿掉 `ActsAsTenant.without_tenant` ⇒ 正式環境只要有既有商品就 `NoTenantSet`。

**那是錯的。** 審查員實測：初版的讀取全走 `.unscoped`（`unscoped` 把 default scope 連同它的
`NoTenantSet` raise 一起拿掉）、寫入全走 `insert_all`（不經 model 寫入路徑）
⇒ 拿掉 `without_tenant` 照樣跑完、正確回填。那句因果是從第 11 包 `20260826058000`
**誤植**過來的——該包成立（它用 `find_or_create_by!` 走 model 寫入），本支不成立。

⇒ 現行版**刻意移除 `.unscoped`**，讓 `without_tenant` 真正承重，並由行為測試守住
（`spec/migrations/p12_backfill_publications_spec.rb` 有一格用 `with_tenant(nil)` 跑真 migration）。

### §7.3 仍然成立的兩條

🔴 **配對 spec 必須「先種既有資料」**：回填迴圈的本體只有在資料庫已有資料時才會被執行到。
**本次當場複驗到**——同一支 migration 在本機開發庫回填 **3 列**（有既有資料）、
在測試庫回填 **0 列**（空庫），**兩次都 exit 0**。

回填用 `insert_all` 而 `.for` 用 `create!`，是**刻意的不對稱**：`insert_all` 繞過 validation
（含 `publishable_belongs_to_same_shop`），在一般寫入路徑上那是漏洞——但回填的
`publishable_id` 是**從同一個 `shop_id` 的表裡查出來的**，租戶歸屬由查詢本身保證。
⚠️ 任何人把那段複製到**非回填**的路徑，那個保證就不存在了。

`down` 是 `IrreversibleMigration`：無法區分「本次回填建的列」與「使用者後來手動發布的列」。

### §7.4 測試有效性的驗收方式

本包的測試不是「寫完跑綠就算」，而是**逐條突變驗證守得住**。第二輪對 14 個突變
（含前一輪找到的全部七個假綠）實跑，**14/14 轉紅**。突變清單與結果見
`docs/worklog/2026-08-26-第12包發布模型.md`。

🔴 **下一個人改這組測試時請照做**：改完後至少對「拿掉 `after_create`」「拿掉
`publication_id` 條件（**單側**）」「拿掉 `where(shop_id:)`」「`published_at` 改 nil」
四個突變重跑一次。前一輪七個假綠裡有三個的根因都是同一個——
**測資落在兩種實作不會分岔的那一格**（例如把兩側的列一起刪掉，就測不出只漏一側的實作）。

---

## §8 邊界與未取得（P12-B）

| 編號 | 內容 |
|---|---|
| P12-B1 | ~~**第三層 catalog 完全沒做**，只有 `publications.catalog_id` 欄位~~ ⇒ 🔴 **2026-08-26 S0 部分推翻**：`sales_catalogs` 表已建、每個 publication 都有 catalog（migration `20260826062000`）。仍未做的是**成員三值語義**（Included／Excluded／All）與 price list ⇒ `published_on` 的判定**仍是兩層**，第三層目前恆真。分期界線改由 `docs/plans/2026-08-26-S0-方案D-schema設計.md` §7.2 定義 |
| P12-B2 | **publish／unpublish mutation 與 `Publishable` 讀取欄位不在本包**。契約形態已取證（第 12 包執行規格 §2.4），做的時候直接用 |
| P12-B3 | **新增 publication 時是否回填既有商品**（`auto_publish` 的另一半）＝**未取得**。需安裝新管道 app 才測得到；v1 也沒有新增管道的流程 |
| P12-B4 | **`auto_publish` 在 admin UI 哪裡設定**＝**未取得**。只在 Markets › Catalogs 找到 "Automatically include new products in this catalog"，與 `Publication.autoPublish` 是否同一個開關**官方兩邊都沒互相指名** |
| P12-B5 | **變體生產者是否跟隨父商品**＝ours（§4）。儲存狀態的實測有排除不掉的替代假說 |
| P12-B6 | **`Unlisted` 的前台行為**（`noindex`／sitemap 排除／推薦排除）本包不做。`limits.yml` 已有正典，消費它的是前台包 |
| P12-B7 | **ARCHIVED 商品的發布列是否仍存在**＝**未取得**。官方沒有正面陳述。我方實作上 `archived` 只在 status 層被擋，發布列照常存在（與 `status` 正交一致） |
| P12-B8 | **`publications.auto_publish` 欄位預設 `true` vs 本尊 `PublicationCreateInput` 官方 Default:false**。我方唯一建立點已明文傳 `true`，現況行為正確 ⇒ 登記不改（`91` §3） |
| P12-B9 | 本尊 admin 的 Status 下拉**沒有 Archived**（歸檔是 More actions 的獨立動作）。我方若把 archived 做成下拉第四項就與本尊不一致 ⇒ 登記 `91` §3，屬商品編輯頁的包 |
| P12-B10 | 系列建立頁的 Collection items 篩選出現 **Suspended** 這個值（`Status: Active, Draft, Unlisted, and Suspended`），不在 `ProductStatus` 值域內——**未取得**它是什麼 ⇒ 登記 `91` §3 |
| P12-B11 | **`products.publications_updated_at` 沒有寫入者**。`db/schema.rb` 該欄的註釋指名寫入者「隨第 12 包」交付，本包**沒有交付**——`Materialize` 建不建列都不碰它。理由：那個 cache stamp 目前**零讀取者**，而真正的寫入者是 publish／unpublish mutation（不在本包，見 P12-B2）；只為它加一個「每建一個變體就 UPDATE 一次父商品」的機制，是第 11 包「為沒有入口的功能蓋機制」的重演 ⇒ 登記 `91` §3，由做 mutation 的那一包一起交付 |
| P12-B12 | **變體建立的 N+1**：`after_create` 每個變體多 **8 次查詢**（單管道），且**隨管道數線性增長**（每多一個管道 +6）。對抗審查實測：20 個變體 280→440 queries、200 個變體 3.44s→4.06s（+3.1 ms/variant，佔基線 18%）。v1 只有一個管道且 `VariantSync` 本來就有更大的 N+1 基線 ⇒ 本包不優化，登記 `91` §3。**管道數長到 5 以上時本項會變成主導項**，屆時把 `auto_publish_publication_ids` 的結果在 `VariantSync` 層一次撈完即可 |
| P12-B13 | **同一條規則有兩份實作**：`ResourcePublication#published?`（Ruby）與 `Product.published_on` 的 SQL 謂詞。目前 `published?` **零生產呼叫端**（只有一支 spec）⇒ 不改。⚠️ M5 補第三層 catalog 時只改一邊會靜默分叉 |
| P12-B14 | **`published_on` 寫死 `products.` 表名**：`Product.from("products AS p").purchasable(...)` 會 `Unknown column 'products.shop_id'`。是**大聲失敗**不是靜默錯誤，且目前零 caller ⇒ 不處理，登記備查 |
