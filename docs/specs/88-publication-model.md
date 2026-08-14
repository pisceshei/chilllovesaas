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
| `catalog_id` | 三層 AND 的第三層；**暫無外鍵**，M5 建 catalogs 時補 |

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

---

## §4 `products.published_at` 已移除

🔴 **同一件事不留兩個事實來源**——這正是鐵律 7 要防的形態：兩處都能寫，遲早不一致。

- 既有值已在 migration 中搬進 `resource_publications`（線上商店管道）；
- 排程發布的語義**沒有消失**，它搬到了 `resource_publications.published_at`，且變成 **per channel**；
- 每間店在 migration 中已建一個 `online_store` publication。
  🔴 **建立商店的流程必須連帶建立它**（M1 待辦，§5）。

---

## §5 待辦（M1 承接）

| # | 事項 | 為什麼不在本次做 |
|---|---|---|
| 1 | **建店時自動建 online_store publication** | 建店流程本身是 M1/M8 的事；migration 只回填了既有店 |
| 2 | **`auto_publish` 的實際行為**（新商品自動納入 auto_publish 的管道） | 需要 Product 的 after_create 回呼，屬商品 CRUD |
| 3 | **排程發布要求商品為 Active** | 跨表條件，隨商品狀態機一起做 |
| 4 | **商品表單的「上架管道」區塊** | UI，M1 |
| 5 | **`ProductVariant` / `Collection` 展開** | 本次只建了最小 model（多型關聯需要類別存在），主體是 M1 |

---

## §6 誠實聲明

- **第三層 catalog 完全沒做**，只留了欄位。本檔標題寫「三層」但實作只有兩層——
  這是刻意的分期，不是漏做。
- **`ProductVariant` 與 `Collection` 是最小 model**（只有租戶隔離、關聯、基本驗證）。
  建它們的唯一理由是多型關聯需要類別存在；主體工作在 M1。
- **`auto_publish` 目前只是一個欄位**，沒有任何行為掛在上面。
- 本檔**不涵蓋** 71-R8-V4（系列建立式的概念差，本尊 2026 改為「來源」卡）——那條仍未裁定。
