# 發布模型 Publication（M1 地基）

> 補寫於 2026-08-14，回應 PR #24 的驗收（Codex 與 Claude 都指出缺本篇）。

## 概述

回答「**這個東西在哪些銷售管道上架了**」。

對應 Shopify 的行為：本尊的上架**不是一個布林值**，是三個條件同時成立——
`Publishable × Publication × Catalog` 三層 AND。help 原文（`docs/research/82` §0.2）：

> For a product to be made available in a sales channel, the product must be included in any
> catalogs that you assign to the channel market, **and** it must be published to the sales channel.

🔴 「已發布到該管道」與「在該管道市場的目錄內」是**兩個獨立條件**，缺一不可上架。

## 規格出處

- `docs/specs/88-publication-model.md` — **本篇的契約**（三層定義、排程限制、待辦）
- `docs/research/82-admin-channels.md` §0.2 — 實測與 help 原文
- `docs/specs/71-admin-parity-sweep.md` §F **R13-V4**（裁定）、**R11-V12**（A-2 一併結案）
- `docs/specs/84-m1-gate-triage.md` §1 A-5

## 架構與資料流

```
Publishable（多型：Product／Collection／ProductVariant）
   └─ ResourcePublication ──→ Publication ──→ (M5) Catalog
                published_at          channel_handle      market 指派

上架判定（88 §3.1）
  上架? = resource_publication.published?(at:)          # 第二層：已發布到該管道
        && publication 的 catalog 包含這個 publishable   # 第三層：M5 才有
```

🔴 **`ResourcePublication#published?` 只是第二層**。用它當「商品是否可購買」會漏掉
市場目錄那一層——model 註釋已明寫，這裡再寫一次是因為它是最容易誤用的方法。

**`published_at` 的三種語義**：`NULL`＝未發布｜過去＝已發布｜**未來＝排程發布**。

## API

本次未新增 GraphQL 操作。M1 商品線接手時，商品表單的「上架管道」區塊與對應的
`publishable*` mutation 才會出現（§待辦）。

🔴 **跨功能影響（鐵律 12.4 ④）**：這兩張表是**前台可購買性**的來源之一。
M2 主題引擎的 Liquid `collection.products`、`product.available`、以及 M5 的市場目錄
都要經過同一組判定——**不要在各處各寫一份**。

## 資料表

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `publications` | `shop_id`／`channel_handle`／`auto_publish`／`supports_future_publishing`／`catalog_id` | 管道在本店的容器；`(shop_id, channel_handle)` 唯一 |
| `resource_publications` | `shop_id`／`publication_id`／`publishable_type`＋`publishable_id`／`published_at` | 多型關聯；`(shop_id, publication_id, publishable_type, publishable_id)` 唯一 |

- `auto_publish` 預設 **true**（本尊：新增管道時既有商品自動可用，不要就得逐一移除）。
- 🔴 `supports_future_publishing` 是 **per publication 的能力旗標**，**Shop 管道為 false**。
- `catalog_id` 是三層 AND 的第三層，**暫無外鍵**，M5 建 catalogs 時補。

**migration**：`db/migrate/20260814200000_create_publication_model.rb`（`down` 可逆）。

**移除的欄位**：`products.published_at` 與 `collections.published_at`——
🔴 **同一件事不留兩個事實來源**（鐵律 7 要防的形態，兩處都能寫遲早不一致）。
既有值已回填進 `resource_publications`（線上商店管道）。

**表定義出處**：被改動的 `products`／`collections` 見 `docs/research/06` §7；
🔴 新建的兩張表**不在 06 §7**——06 是本尊的研究檔，我方的表定義出處是
`docs/specs/88` §2，實測出處是 `docs/research/82` §0.2。
**刻意不把自創表補寫進 research 檔**，那會污染 research（本尊事實）與 specs（我方要建的）的界線。

## 關鍵取捨

| 取捨 | 選擇 | 為什麼不選另一邊 |
|---|---|---|
| 表名 | `resource_publications` | 叫 `product_publications` 會讓 Collection／ProductVariant 看起來像硬塞進來的；本尊型別就叫 `ResourcePublication` |
| `products.published_at` | **移除**，不保留成快取 | 保留＝兩個事實來源，兩處都能寫 |
| 第三層 catalog | **只留欄位，M5 再做** | catalog 是**讀取時的過濾**，加它不需改這兩張表的結構 ⇒ 可安全分期 |
| 多型 vs 逐型別關聯表 | **多型** | 逐型別要三張近乎相同的表；代價是**拿不到 DB 外鍵**，見下 |

### 🔴 多型的代價：跨租戶只能靠 model validation

`acts_as_tenant` **不驗證多型外鍵的租戶歸屬**——gem 原始碼
（`acts_as_tenant-1.0.1/lib/acts_as_tenant/model_extensions.rb:57-62`）
把多型外鍵明確排除；MySQL 也無法對多型欄位建外鍵。
⇒ **gem 層與 DB 層都沒有人擋**，只有 `ResourcePublication#publishable_belongs_to_same_shop`。

常規請求下 `belongs_to` 的存在性驗證 ＋ `default_scope` 會**順帶**擋住跨店 id，
但那是偶然的副作用，在 `ActsAsTenant.without_tenant`（資料遷移／seeds／維運腳本）、
明確指定 `shop_id`、或 `insert_all`／`upsert_all` 之下全部失效。

⚠️ **本驗證擋不住 `insert_all`／`upsert_all`**（Rails 一律跳過 validation）。
要拿到 DB 層底線防護只能改成逐型別關聯表——那是另一個取捨，未做。

## 測試

`spec/models/resource_publication_spec.rb`（8 條）：

- `published_at` 三種語義（NULL／過去／未來）
- 不支援排程的管道不得排程；立即發布仍可（證明擋的是「排程」不是「該管道」）
- 不得為單一 variant 排程；立即發布仍可（🔴 用**真的存在**的 variant——
  原本用不存在的 id，測試會綠但綠的原因可能是「找不到物件」而不是規則生效）
- 同一 publishable 可在不同 publication，但同一 publication 內不得重複
- **跨租戶三條**：別店的 publishable 被拒；🔴 **`without_tenant` 下仍被拒**
  （這條才是重點——常規路徑的保護在這裡整個消失）；同店的通過

跑法：`bundle exec rspec spec/models/resource_publication_spec.rb`

## 已知限制與 TODO

- 🔴 **第三層 catalog 完全沒做**，只留了欄位。88 標題寫「三層」但實作只有兩層——
  這是刻意分期，88 §6 有明說。
- 🔴 **M1 承接五項**（88 §5），其中 ① 已於 2026-08-15 結案：
  ~~①建店時自動建 `online_store` publication~~
  ✅ `Shop#after_create :create_default_publication` ＋ `20260815000010` 回填 migration。
  **兩半缺一不可**：callback 修未來、migration 修歷史（`20260814200000` 只回填了它執行
  當下既有的店，之後每一次 seeds／spec／手動建店都產生一間沒有管道的店，
  **而且不拋任何錯**，只是那間店所有商品都上不了架）。
  ⚠ 只建 `online_store` 一個；82 §0.1 實測本尊有三個已安裝管道，其餘無規格 ⇒ 不猜。
  ②`auto_publish` 的實際行為
  （目前只是一個欄位，沒有行為掛在上面）③排程發布要求商品為 `Active`（跨表條件）
  ④商品表單的「上架管道」區塊 ⑤`ProductVariant`／`Collection` 主體展開。
- **`ProductVariant` 與 `Collection` 是最小 model**——建它們的唯一理由是多型關聯需要類別存在。
- **71-R8-V4 未裁定**（系列建立式的概念差，本尊 2026 改為「來源」卡），已在 `collection.rb` 註明。

## 變更記錄

- 2026-08-14 PR #24：建立兩張表與四個 model；補寫本篇；
  補多型跨租戶驗證與三條測試；一併移除 `collections.published_at`
