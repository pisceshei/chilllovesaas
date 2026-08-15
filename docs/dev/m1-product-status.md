# 商品狀態四態與 SKU 軟唯一（M1）

## 概述

商品狀態是**四**態（`ACTIVE`／`DRAFT`／`ARCHIVED`／`UNLISTED`），不是三態；
SKU 是**軟唯一**（偵測重複顯示警告但不阻擋），不是硬唯一。

兩者的共同形態：**規格與實作已經互相矛盾**——`config/limits.yml` 從一開始就是
四態、從一開始就宣告 `sku_unique_per_shop: false`，而 model／enum／DB 索引都沒跟上。

## 規格出處

- `docs/specs/13` §F1.2（四態真值表與轉換副作用）
- `config/limits.yml`：`product.status_values`（804）、`catalog_flow.sku_unique_per_shop`（2504）
- `docs/research/61` §1.5（SKU 軟唯一的 help 原文）｜`docs/research/63` §B.6／§L-1
- 原型 `docs/design/chilllove-admin-v2.html` 的 `P_STATUS`（約 3105 行，**文案正典**）

## 架構與資料流

```
config/limits.yml  product.status_values: [ACTIVE, DRAFT, ARCHIVED, UNLISTED]
   ├─ Limits.enum(:product, :status_values)
   │     ├─ Product::STATUSES（小寫，DB 值）
   │     ├─ Product::PURCHASABLE_STATUSES  = [active, unlisted]
   │     ├─ Product::DISCOVERABLE_STATUSES = [active]
   │     └─ Types::ProductStatusEnum（大寫 token → 小寫 value）
   └─ 前端 ProductsPage.tsx 的 statusPresentation（文案與 pip 取自原型 P_STATUS）
```

🔴 **`UNLISTED` 不是「多一個狀態」而已**：它的存在本身就證明「可購買」與「可被發現」
是**兩個獨立維度**。三態時兩維完全同步，所以一個 `published` 布林兼管兩件事剛好不出錯；
補上第四態必定撞牆——要嘛它完全買不到（商家把直接連結給客人卻結不了帳），
要嘛它出現在搜尋與 sitemap 裡（SEO 事故）。

## API

- `ProductStatus` enum 四值，每值帶取自 13 §F1.2 真值表的說明。
- 🔴 **不做舊 API 版本降級**（`limits.yml:817`，刻意偏離本尊，13 §F1.2(f)）：
  Shopify 對舊版 API 把 `UNLISTED` 回成 `ACTIVE`，那會讓舊版整合把它當 ACTIVE 處理、
  再送進 feed 與索引，**等於 noindex 完全失效**。我方任何版本一律照實回 `UNLISTED`。

## 資料表

- `products.status`：`varchar(32)`，**無 CHECK constraint** ⇒ 加第四值**不需要 migration**
  （本步驗證 `git diff --exit-code db/schema.rb` 為零 diff）。
- `product_variants.sku`：`uq_product_variants_sku`（unique）→ `ix_product_variants_sku`（一般）。
  migration：`db/migrate/20260815000000_relax_product_variant_sku_index.rb`。
  🔴 **索引名一起換**（`uq_` → `ix_`）：前綴是語義的一部分，留著 `uq_` 會讓之後讀
  schema.rb 的人以為它還是唯一索引——**那正是本次矛盾的來源形態**。

## 關鍵取捨

### 🔴 刻意不做 `purchasable` / `discoverable` 具名 scope

`13` §F1.2(d) 的 scope SQL 用 `product_publications` 與 `variant_publications`
兩張**不存在的表**（我方落地的是多型的 `resource_publications`），
而 `20260814200000` 的回填**一列 `ProductVariant` 都沒有**：

- 照規格加上變體層 `EXISTS` ⇒ **全站每個商品都靜默變成不可購買**；
- 省略變體層 ⇒ 一個叫 `purchasable` 的 scope 只做了三層 AND 的第一層，**名字在說謊**。

⇒ 只交付狀態集合 ＋ `with_status_set(statuses, shop_id:)` **單一產生器**（鐵律 7），
並用一條 spec（`expect(described_class).not_to respond_to(:purchasable)`）
把「刻意沒有」釘住。

### SKU 降級的兩個合法情境

唯一索引會擋掉：①同款不同包裝共用 SKU；②CSV 批次匯入（本尊是警告後照樣寫入，
唯一索引會讓整批在中途 `RecordNotUnique` 失敗）。兩者都是「商家做了官方允許的事，
我方回失敗」。

🔴 **降級之後重複 SKU 的提示沒有地方回**：`63` §B.6 要求走 payload 的 `warnings`
（不是 `userErrors`——後者代表操作失敗，鐵律 4），而 `warnings` 慣例目前不存在
⇒ **在第一支變體 mutation 落地前，重複 SKU 是靜默允許的**。

### 前端逐欄對照原型 `P_STATUS`，不自創

| 狀態 | 原型 `bt` | 原型 `pip` | 本輪 |
|---|---|---|---|
| ACTIVE | 啟用中 | full | 文案 **「使用中」→「啟用中」**（原文案是本專案自創） |
| UNLISTED | 未列出 | `''`（裸圈） | pip **`half` → `empty`** |
| DRAFT | 草稿 | `''` | 已相符 |
| ARCHIVED | 已封存 | **blocked** | ⚠ 未對齊，見已知限制 |

🔴 **pip 也釘進測試，不是只釘文案**：UNLISTED 原本寫 `half`（半圈＝進行中），
語義上是錯的——它不是「進行中」，是「啟用但不被發現」。**文案斷言抓不到這種錯。**

## 🔴 跨功能／跨頁／前端影響（鐵律 12.4 ④）

| 影響對象 | 什麼時候會碰到 | 要注意什麼 |
|---|---|---|
| **商品列表／詳情（前端）** | 已影響 | `statusPresentation` 四值；未知狀態有 fallback（GraphQL enum 再擴值不會炸頁） |
| **admin 商品列表的 status 篩選器** | 13 §F1.2(e) 要求 | **尚未做**：`docs/research/60` 沒有實測任何篩選控件、原型也沒有，且 DOCS 條目措辭衝突 ⇒ 登記為 V 項，需回頭實測本尊 |
| **前台商品頁（M2）** | UNLISTED 的對外行為 | `unlisted_meta_robots: noindex,nofollow` 要注入 `<head>`；直接 URL 回 200 |
| **sitemap／搜尋／系列／推薦（M2）** | 同上 | `unlisted_excluded_from` 的八個排除點，散在 M2 與 M5 |
| **feed／JSON-LD（M3 SEO）** | 同上 | UNLISTED 一律排除 |
| **市場 catalog（M5）** | 同上 | ⚠ `limits.yml` 的鍵值與註釋不一致（鍵只有 `agent_catalog`、註釋寫「平台 catalog」）⇒ V 項 |
| **排程發布（88 §5 #3）** | 做排程發布時 | 「排程發布要求商品為 Active」——**UNLISTED 算不算 Active 沒有規格**，會直接決定驗證式 |
| **CSV 匯入器** | 擴 enum 時 | 🔴 **不得**順手把 `value_maps.status` 補上 unlisted，也不得加「Published=FALSE ⇒ UNLISTED」的推導（`never_infer_unlisted: true`） |
| **變體 mutation（M1 後續）** | 重複 SKU | 需要 `warnings` 形狀（`63` §L-9）；在那之前靜默允許 |
| **`inventory_items.sku`** | 任何碰 SKU 的地方 | 🔴 **權威表是 `inventory_items`**（`sku_owner: inventory_item`），`product_variants.sku` 是雙寫。本輪**刻意不加同步 callback**——那會把結構問題用隱形副作用蓋住 |

## 測試

- `spec/models/product_spec.rb`（14）：四態值域、`discoverable ⊆ purchasable` 恆等不變量、
  單一產生器、**「刻意未實作」的斷言**。
- `spec/models/product_variant_spec.rb`（9）：軟唯一 ×3、租戶隔離、索引形狀 ×3、
  **真併發 ×2**。
- `spec/migrations/pr1_schema_alignment_spec.rb`（12）：對原始碼的不變量。
- `spec/graphql/products_contract_spec.rb`：UNLISTED 端到端序列化 ＋ introspection。
- `app/frontend/admin/pages/ProductsPage.test.tsx`（5）：四態渲染 ＋ **pip class 斷言** ＋
  未知狀態 fallback。

**負面驗證**：把索引還原成唯一 ⇒ 5/9 紅（含併發那條）；enum 退回三值 ⇒ 5 條紅
（含端到端序列化——本輪之前那條路徑**從未被走過**，既有 7 條契約測試全部只用 draft）。

### 🔴 併發測試的取捨（寫下來免得被當成偷懶）

- **SKU 重複寫入不用執行緒**：唯一索引在第二筆 INSERT 就 raise，與併發無關。
- **`handle` 併發衝突非用執行緒不可**：`Product` 有 model 層的 uniqueness validation，
  順序寫入時 validation 先擋，**唯一索引沒機會發言**。降級 SKU 索引時最容易的誤操作
  就是連帶動到別的索引，而那只會在併發下顯形。
- `self.use_transactional_tests = false`，且清理**寫在 `before` 也寫在 `after`**
  ——`after` 自己失敗過一次，殘留資料讓下一次整個 rspec 程序在無關的地方紅。

## 已知限制與 TODO

- 🔴 **`purchasable`／`discoverable` 具名 scope 延後**，解鎖條件＝`63` §H.2 與 `88` 的
  發布模型收斂，且變體層 `resource_publications` 要先有回填。
- 🔴 **13 §F1.2 的六條驗收只完成三條**，另三條散在 M2／M5。
- ⚠️ **ARCHIVED 的 pip 未對齊**：原型是 `blocked`，而 `23` §1 的 Badge 規格只定義
  **三種** pip ⇒ **原型與 CSS 規格本身不一致**，補第四種是視覺語言變更。
  測試刻意斷言**現況**，之後對齊時那條會紅。
- ⚠️ **UNLISTED 的狀態機合法轉移邊沒有規格**（`06` 只寫三態、`13` 只定義三種轉移）
  ⇒ 本輪**不加轉移驗證**（加了就是發明規則）。
- ⚠️ **SKU 雙寫未解**（`product_variants` vs `inventory_items`）——本輪之前就存在，
  登記為已知偏差，免得下一輪稽核當成本輪引入。
- ⚠️ **V-91 未裁定**：要不要提供「SKU 必須唯一」設定項以服務有 WMS 整合的商家（比官方嚴）。

## 變更記錄

- 2026-08-15 PR-1：建立（四態 UNLISTED ＋ SKU 軟唯一降級 ＋ 前端對照原型）
