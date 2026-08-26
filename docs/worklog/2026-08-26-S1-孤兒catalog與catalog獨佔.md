# 2026-08-26 S1 後修：孤兒 catalog 清理與「一個 catalog 最多一個 publication」

> S1（PR #148，已合併並部署）的**線上驗證**抓到的兩個缺陷。
> 本包是獨立的可驗收單位（獨立 PR）⇒ 依鐵律 21.4 另立 worklog。
> 主包 worklog＝`docs/worklog/2026-08-26-S1-publication生命週期.md`。

---

## 已完成的工作 (Done)

### 1. 🔴 缺陷一：刪 publication 留下孤兒 catalog（線上實跑抓到）

S1 合併部署後，在**正式庫**實跑三支 mutation 的服務層做線上驗證，輸出逐字：

```
delete ok=true
res_pub_rows_left=0
products_intact=true
cleanup: publication_left=0 catalog_left=1
```

⇒ `publicationDelete` 刪掉 publication，但 `sales_catalogs` 那一列**留在庫裡**。
每建一次刪一次就漏一列，**而且不拋任何錯**。

⚠️ **為什麼本機 spec 抓不到**：S1 的 29 格斷言的是 publication 與發布列的數量，
**沒有人數 catalog**。這是「測了相鄰的東西，沒測那一個」的形態。

**修法**：`Publications::Write.delete` 在銷毀 publication 之後呼叫
`destroy_orphan_catalog!`。判準是「**沒有任何 publication 指著它**」，不是
「這個 catalog 是不是我們建的」——理由逐條寫在該方法的註釋。

⚠️ **本尊在同一個位置留孤兒**（B2B 指南逐字：`the previous publication remains in the
system and becomes orphaned unless you explicitly delete it.`，取證 2026-08-26）
——它孤兒的是 publication，方向相反。我方選擇清理是 **ours**，理由是我方沒有 catalog
的管理介面，孤兒列商家永遠看不到也刪不掉。

### 2. 🔴 缺陷二：兩個 publication 可以共用一個 catalog（新測試自己帶出來的）

為缺陷一寫「catalog 還被別的 publication 用著時不得誤刪」那一格時，測試本身紅了：

```
expected: []
     got: [{"code" => "INVALID", "field" => ["input", "channelHandle"],
            "message" => "has already been taken"}]
```

⇒ 兩個 publication 共用 catalog 會撞 `channel_handle` 的唯一性（佔位值由 catalog id 導出）。
但那是**症狀不是根因**：我方 `SalesCatalog has_one :publication` 是 **1:1**，
「共用 catalog」本來就不該被接受，而在此之前**沒有任何東西擋它**
（`publications.sales_catalog_id` 沒有唯一索引）。

而且錯誤訊息指向 `input.channelHandle`——一個**呼叫端根本沒有傳的欄位**。

**修法**：`Publications::Write.create` 在源頭擋，回 `TAKEN`，`field` 指向 `input.catalogId`。

🔴 **不加 DB 唯一索引**：本尊的 `Publication : Catalog` 是 1:1 還是 1:N ＝**官方未取得**
（S1 規格草案 U-19）。在那之前把 1:1 硬寫進 schema 是把未取得寫成事實。

### 3. 🔴 突變複驗把一條死碼揪出來

第一輪突變：

| 突變 | 結果 |
|---|---|
| M7 刪除不清孤兒 catalog | `33 examples, 2 failures` |
| M8 拿掉「一個 catalog 最多一個 publication」守衛 | `33 examples, 2 failures` |
| **M9 孤兒判準改成「只要是我們建的就刪」** | **`33 examples, 0 failures`** ← 🔴 |

M9 全綠代表：**有了 M8 那道守衛之後，孤兒判準在服務層已經結構上不可達**
（catalog 恆 1:1 ⇒ 刪完 publication 後判準恆為真）。
⇒ 那行 `exists?` 是**沒人看著的死碼**。

**處置**：補一格**繞過服務層、直接在 model 層用 `update_columns` 構造共用狀態**的測試。
理由不是「為了讓突變轉紅」，而是：U-19 哪天解成 1:N，那道判準就從防禦變成承重，
而屆時沒有任何測試會告訴你它壞了。補格後：

| 突變 | 結果 |
|---|---|
| M7 | `34 examples, 2 failures` |
| M8 | `34 examples, 2 failures` |
| M9 | `34 examples, 1 failure` |
| 還原後 | `34 examples, 0 failures` |

---

## 修改的檔案與核心邏輯 (Changes)

| 檔案 | 內容 |
|---|---|
| `app/services/publications/write.rb` | `create` 加「catalog 已被佔用」守衛（`TAKEN`）；`delete` 加 `destroy_orphan_catalog!` |
| `spec/requests/publication_lifecycle_spec.rb` | 新增五格：孤兒清理、共用 catalog 不誤刪（繞過服務層構造）、TAKEN × 2、建店 catalog 不受影響 |
| `config/locales/{en,zh-Hant,zh-Hans,ja,fr}.yml` | `errors.publication.catalog_taken` × 五語系 |

---

## 尚未完成或需注意的風險 (Pending / TODO)

| # | 內容 |
|---|---|
| F1 | **`publications.sales_catalog_id` 沒有 DB 唯一索引**。1:1 目前只由服務層守衛擔保，`update_columns`／`insert_all`／raw SQL 都繞得過（本輪的測試就是這樣構造出共用狀態的）。加索引的前提是 U-19（本尊 1:1 還是 1:N）解掉 |
| F2 | **孤兒清理只涵蓋 `publicationDelete` 這條路徑**。若日後出現別的刪 publication 的入口（例如卸載管道），要各自呼叫 `destroy_orphan_catalog!`，或把它移到 model callback。目前只有一個入口 ⇒ 不預先抽象 |
| F3 | **正式庫在本輪之前漏掉的那一列 catalog 已由驗證腳本清掉**（線上驗證的 `cleanup` 段），不需要資料修復 migration。⚠️ 這是因為缺陷從引入到發現只隔了一次部署；隔久了就得寫回填 |
| F4 | 🔴 **教訓：29 格全綠 ＋ 六個突變全紅，仍然漏掉了「有沒有人數 catalog」這件事**。突變測試證明的是「已寫下的斷言擋得住對應的實作錯誤」，不是「斷言覆蓋了全部後果」。線上驗證是最後一道，且它這次真的抓到了東西 |
