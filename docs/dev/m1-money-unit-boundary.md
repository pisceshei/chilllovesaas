# 金額單位邊界（M1）

## 概述

金額在系統裡有**四種表示法**，彼此不可互換。這一層的職責是：讓「用錯表示法」在
**執行期第一次呼叫時就炸**，而不是在上線後的對帳日才被發現。

對應本尊：`MoneyV2` 的 `amount` 是十進位字串，而各家 PSP 收的格式**四家四種**
（`docs/specs/65` §D.4）。本層不是抄本尊的實作，是**滿足鐵律 3**。

🔴 **本層目前沒有任何生產呼叫端**：`app/` 全庫 `Money::` 只出現在本層自己，
`Types::ProductType` 連價格欄位都沒有，`Psp::BaseAdapter` 沒有任何子類。
它的正確性靠三件事保證——規格逐行寫死的欄位形狀、六幣別 × 兩種格式的測試矩陣、
以及六條帶「故意違反 fixture」的 CI 檢查。**這一點必須誠實揭露，不得假裝已被使用。**

## 規格出處

- `docs/specs/65`（全文，鐵律 3 的契約）｜`CLAUDE.md` 鐵律 3
- `config/limits.yml` 的 `money_boundary:` 與 `psp_packs:` 區塊
- `docs/research/69` §V-188（四家 PSP 的實證表）

## 架構與資料流

```
DB（*_cents，bigint）
  └─ Money::Storage.from_cents ──┬─ #to_decimal ─────→ Money::Decimal（R4）
                                 │                      ├─ JSON-LD Offer.price
                                 │                      ├─ GMC/Meta feed、CSV
                                 │                      ├─ GraphQL MoneyV2.amount
                                 │                      └─ 物流商 payload
                                 ├─ #to_psp_amount(psp:) ── 依 pack.amount_format 分流
                                 │     ├─ minor_units    → Money::PspMinor（R5）
                                 │     └─ decimal_string → Money::PspDecimal（R6）
                                 │              ↓
                                 │        Psp::BaseAdapter#to_payload
                                 │              ↓（唯一變回 Integer／String 的地方）
                                 │           PSP HTTP body
                                 └─ Money::Display.call ─→ 顯示字串（R3；符號待 M5 markets）

入向：PSP webhook → 依 pack.amount_format 包成 R5／R6 → #to_storage → R1 落庫
```

🔴 **`Money::Decimal`（R4）與 `Money::PspDecimal`（R6）的線上形態完全相同**
（都是 `"1480.00"`），差別只有 `:psp` 欄位。**任何人不得把兩者合併成一個型別**——
沒有 `:psp` 就無法在 adapter 端斷言「這個值是為這一家算的」。

## API

本層**不出任何 GraphQL 操作**。它是被 mutation／serializer 呼叫的內部型別層。
第一個消費端預期是 `productVariantsBulkCreate` 的價格欄位（M1 後續 PR）。

## 資料表

**不新增任何表**。約束是對既有金額欄位的：一律 `bigint` ＋ `_cents` 結尾
（`scripts/check-money-boundary.rb` 的 C3 在 migration 期執法）。

`config/iso4217_minor_units.yml`（新增，非資料表）：ISO 4217 exponent 底表，
**手工輸入的最小子集**，只在 pack 宣告 `minor_unit_source: iso4217` 時作為底表。
🔴 **TWD 刻意不在表裡**（65 §H.3：本專案至今沒有任何一手出處）。

## 關鍵取捨

### 為什麼是四個型別而不是一個帶單位欄位的類別

一個 `Money(amount, unit)` 類別擋不住「把 storage 的實例傳給 PSP」——
它們是同一個型別，靜態上看不出差別。**四個不同的類別讓誤用在 `is_a?` 就失敗**。

### L2「唯一建構路徑」在 `Data` 上有**三條**後門

規格只說把 `.new` 設 `private_class_method`，但 `Data.define` 另外給了：

| 後門 | 實測（Ruby 3.4.10） | 危險 |
|---|---|---|
| `Klass[...]` | 建得出完整實例 | 與 `.new` 等價 |
| `instance.with(...)` | 建得出完整實例 | 「換幣別、保留同一個數字」變成一行 |
| `Klass.allocate` | 欄位全 nil，**但 `is_a?` 為 true** | 🔴 L3 的 adapter 斷言只看 `is_a?` |

四個型別的三條後門全關（`app/models/money.rb` 檔尾），R5／R6 另外關 `.new`。

### `__build` 是 public——Ruby 表達不了「friend class」

`Money::Storage` 與 `Money::PspMinor` 是兩個不同的類別，private class method 呼叫不到。
⇒ 這條限制靠**命名（`__` 前綴）＋ CI 檢查 C5** 執行。
**這是四層防線裡唯一一處「型別擋不住、只能靠 CI 擋」的地方。**

### 型別層**不驗**正負（65 §A.7）

在 `Money::Storage` 上驗非負會讓退款差額與撤銷整條卡死
（`Order.totalOutstandingSet` 官方明文可為負）。正負的業務規則驗在**寫入端與 PSP adapter**
——在值物件上驗非負，等於用型別系統表達一個只在某些路徑成立的業務規則。

### `format("%.2f", big_decimal)` 內部會轉 Float

BIGINT max 上 `9223372036854775807` 會變成 `92233720368547760.00`（差 2 分錢）。
⚠️ **這個 bug 只在極大值現形**，一般金額測試全綠——與 65 §0.2 的
「exponent=2 幣別下測試全綠」是同一種病。`Money.fixed_string` 全程整數／BigDecimal 運算。

### `check_divisibility!` 的基準是「送出值的單位」，不是 cents

統一成 cents 的話，pack 作者就得把 PSP 文檔上的數字**自己換算一次**再填
——**而那個手工換算正是這一整篇在防的東西**。宣告值必須能與來源文件逐字對照。

## 🔴 跨功能／跨頁／前端影響（鐵律 12.4 ④）

| 影響對象 | 什麼時候會碰到 | 要注意什麼 |
|---|---|---|
| **任何金額 mutation** | 第一支帶價格的 mutation（M1） | input 的十進位字串 → `Money::Decimal.from_string` → `#to_storage`；**不得直接 `to_i`** |
| **GraphQL 序列化** | `MoneyV2.amount` 欄位落地時 | 一律 `Money::Storage#to_decimal.string`，不得自己 format |
| **`Types::ProductType`** | 加 `price` 欄位時 | 目前**連價格欄位都沒有**，加的時候要走本層 |
| **PSP adapter（M4 結帳）** | 接第一家 PSP 時 | 🔴 **必須先在 `limits.yml` 建 pack**（A0：未宣告 `amount_format` 一律 reject）；adapter 繼承 `Psp::BaseAdapter` |
| **webhook 接收（M4）** | PSP 回調落庫時 | 入向必須先包成 R5／R6 再 `#to_storage`；**包不出來就不准進**（`inbound_format_mismatch_action: dead_letter` 尚未實作） |
| **對帳／分錄（M6）** | 三方對帳 | 一律先化到 R1 再比（`reconciliation_normalize_to: storage_cents`） |
| **冪等鍵** | 任何帶金額的冪等鍵 | 🔴 一律用 R1（`idempotency_key_amount_representation: storage_cents`）；改成 R5 會讓既有 key 全失效 |
| **前台 Liquid（M2）** | `money` filter | R3；符號與千分位由 market locale 決定（M5），現在的 `Display.call` 是過渡形態 |
| **JSON-LD／feed（M3 SEO）** | `Offer.price` | R4；`62` §A.4 |
| **物流商（M4）** | 運費 payload | R4，**不是 R6**——`58` §G.3 與 PSP 的任何格式都不是同一件事 |
| **DB migration** | 任何新增金額欄位 | `bigint` ＋ `_cents`；C3 會擋 `t.decimal`／`t.float`／`t.integer :*_cents` |
| **`config/ci.rb` 與 `ci.yml`** | 改 CI 時 | 兩邊都要有 `check-money-boundary` 與 `test-money-rules` |

## 測試

- `spec/models/money_spec.rb`（22）：L1 反射斷言、L2 三條後門、R1／R4／R3、
  鐵律 6 的 stub 驗法。
- `spec/models/psp_amount_matrix_spec.rb`（32）：65 §H 的 T3–T19 全矩陣。
- `spec/models/psp/registry_spec.rb`（13）：鍵型別收斂 ＋ 五個違規 pack 各自被擋。
- `scripts/check-money-boundary.rb` ＋ `scripts/test-money-rules.rb`（10）：
  六條 CI 規則各自被故意違反的 fixture 打紅 ＋ 乾淨倉庫必須 exit 0。

**手動驗證**：
```bash
ruby scripts/check-money-boundary.rb   # 乾淨倉庫 exit 0
ruby scripts/test-money-rules.rb       # 10/10
bundle exec rspec spec/models/money_spec.rb spec/models/psp_amount_matrix_spec.rb
```

## 已知限制與 TODO

- 🔴 **`Money::Storage` 不能相加相減**。65 §F.3 只講 SQL rollup，值物件層是空白。
  現在猜一個實作，第一個使用者就會繞過它寫 `a.cents + b.cents`
  ⇒ 留給第一個需要小計／折扣的 PR。
- 🔴 **往返自檢沒有掛在轉換路徑上**：`roundtrip_selfcheck_envs` 要的是
  「非生產環境**每次轉換**都跑」，目前只有 T12 那條 spec 在跑。
- 🔴 **`divisibility_scope` 被完全忽略**（V-206 未結案）：當前處置是最嚴格解讀
  （charge 亦套用），scope 只進錯誤訊息。
- 🔴 **入向的 `dead_letter` 未實作**：需要 webhook 接收端（M4）。
- ⚠️ **C2 只掃明顯的 kwarg 呼叫**，動態 `send` 與 `**payload` 看不到。
- ⚠️ **`iso4217_minor_units.yml` 是手工輸入的**（V-131：一手來源與落地形式未取得）。
- ⚠️ **`Psp::Registry`／`Pack`／`BaseAdapter` 是 65 號只有呼叫端、沒有定義端的三個類別**
  ——它們有真實的設計自由度。刻意做得極薄。**第一家真 PSP 進來時預期會被改寫。**
- ⚠️ **65 §C.3 的 C1 白名單描述是空的**（掃描範圍與白名單路徑不重疊），規格待修。

## 變更記錄

- 2026-08-15 PR-1：建立（R1／R4／R3 ＋ R5／R6 ＋ registry ＋ adapter ＋ 矩陣 ＋ CI 執法）
