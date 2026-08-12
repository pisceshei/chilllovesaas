# 65 — 金額單位邊界契約（money unit boundary）

> **一句話**：系統裡有**五種**金額表示法，它們的單位互不相同；每一個跨界點都必須顯式轉換，而**在 HKD／USD／MYR 這些 exponent=2 的幣別下，錯的實作與對的實作輸出完全一樣**——所以這件事不能靠測試發現，只能靠型別與 CI 擋住。
>
> 覆蓋範圍：內部儲存／顯示／PSP 送出與回收／會計分錄與對帳／CSV 匯出入／結構化資料與 feed／物流商／平台 rollup。
> 本篇是 **63 §G.4**（救命條款）、**58 §G.3**（物流商金額）、**62 §A.4／§L**（`Offer.price`）三處既有裁定的**共同上位契約**——那三處都對，但各自只覆蓋自己那一段邊界，沒有人負責「一共有幾段邊界」這個問題。本篇負責。

---

## 0. 為什麼有這一篇

### 0.1 事故形狀（63 §G.4 的原始發現）

2026-08-12 裁定二讓**所有幣別顯示兩位小數**，並且**儲存一律 ×100，不看幣別**。於是：

| | JPY 的 ¥1,480 |
|---|---|
| 儲存（R1） | `148000` |
| 顯示（R3） | `¥1,480.00` |
| 送 Stripe（R5） | **必須是 `1480`** |

**把儲存值直接送出去 ⇒ 收款 ¥148,000，100 倍。**
**把 PSP 回報值直接落庫 ⇒ 記成 ¥14.80，少記 99%。**

### 0.2 為什麼它不會被測試抓到（本篇存在的唯一理由）

轉換式是 `divisor = 10 ** (2 - iso_exponent)`。

- HKD／USD／MYR／EUR（exponent=2）⇒ `divisor = 1` ⇒ **乘不乘、除不除，輸出一模一樣**。
- JPY／KRW（exponent=0）⇒ `divisor = 100` ⇒ 差 100 倍。

所以：**一個完全沒有實作轉換的系統，在 exponent=2 幣別的測試矩陣下 100% 通過。** 這個 bug 的發現時點不是 CI，是**上線後第一筆 JPY 交易的對帳日**——而那時候錢已經收錯了。

同型陷阱的既有處置見 58 §G.3（物流商側的 100 倍）與 62 §L.1 防呆 2（JSON-LD 側的 100 倍）。**同一個坑在本專案已經出現三次**，這是它第三次被寫進規格；本篇的目的是讓它不必有第四次。

### 0.3 出處等級

沿用 `config/limits.yml` 檔頭四級（`dev`／`help`／`live`／`ours`）。本篇**絕大多數內容是 `ours`**——單位邊界是我方架構決策，不是 Shopify 的功能邏輯，不適用「1:1 對齊」。凡引用 ISO 4217 或 PSP 行為之處一律標明出處或登記 V 編號。

### 0.4 本篇**不**改什麼

- 不改裁定二（顯示兩位小數、儲存 ×100）——本篇建立在它之上。
- 不改 62 §A.4 的 `Offer.price` 定案（`cents/100`，固定兩位）——本篇把它登記為 R4 的一個消費者，並確保兩處的表一致。
- 不改 58 §G.3 的物流商入向規則（一律 ×100，不看幣別）——本篇指出它**只覆蓋入向**，出向未定義（§J M-3）。

---

## A. 系統裡有幾種金額表示法

**五種對外可見 ＋ 一種只存在於解析器內部。** 任何金額值在任何時刻都**恰好屬於其中一種**；不知道自己屬於哪一種的值，就是 bug。

| # | 名稱 | Ruby 型別 | 單位 | 尺度 | 出現在哪 | 定義出處 |
|---|---|---|---|---|---|---|
| **R1** | 儲存 cents | `Money::Storage`（內含 `Integer`） | storage cent | **一律 ×100，不看幣別** | 所有 DB 金額欄位（後綴 `_cents`）、全部業務層運算、冪等鍵、會計分錄 | 鐵律 3 ＋ `currency_display.storage_scale_unchanged` |
| **R2** | micro-cents | `Integer`（裸值） | cents × 10⁶ | ×10⁸ 相對主單位 | **只在 `Pricing::PresentmentResolver` 的方法內部**；不得跨方法邊界、不得落庫、不得序列化 | 63 §G.3 |
| **R3** | 顯示字串 | `String` | — | 恆兩位小數 ＋ market locale 的符號與千分位 | Liquid `money` filter、admin UI、通知信、PDF、面單 | 裁定二 ＋ 鐵律 10 |
| **R4** | 十進位字串 | `Money::Decimal`（內含 `String`） | **主單位**（major unit） | 恆兩位小數、**無符號、無千分位**、小數點為 `.` | JSON-LD `Offer.price`、GMC/Meta feed、CSV 價格欄、GraphQL `MoneyV2.amount`、**物流商** | 62 §A.4 ＋ 58 §G.3 |
| **R5** | PSP minor unit | `Money::PspMinor`（內含 `Integer`） | **該 PSP 為該幣別宣告的 minor unit**（正常值＝ISO 4217 exponent） | 依幣別（JPY 0／HKD 2） | **只在 PSP adapter 的請求與回應 payload 內** | 本篇 §D |

**兩件最容易被「順手統一」而搞爛的事**：

1. **R4 ≠ R5。** 物流商走 R4（十進位字串，58 §G.3 已定），PSP 走 R5（整數 minor unit）。兩者都是「對外」，但**慣例不同**。有人把它們合成一個 `to_external_amount()` 就是下一次事故。
2. **R1 的 ×100 與 R5 的 exponent 沒有關係。** `100` 不是「因為大多數幣別是 2 位」，它是**我方選定的固定儲存尺度**。日後要支援 exponent=3，改的是 `storage_scale_multiplier`（全庫 migration），**不是**轉換函式（63 §G.4 已定）。

> 🔴 **`limits.currency_display.iso4217_zero_decimal_overridden` 不是 R5 的資料來源。** 那個鍵的語義是「哪些幣別的**顯示位數**被裁定二覆蓋」，鍵名裡的 `iso4217` 指的是被覆蓋的對象。拿它推導 PSP 單位＝下一個 100 倍。已在 `limits.yml` 該鍵旁加 `not_a_psp_unit_source: true` 反引用。（§J M-4）

---

## B. 邊界總表：每一個跨界點要做什麼

> **讀法**：每一列是一次表示法轉換。「斷言」欄的每一條都是**必跑**的，不是建議。
> 沒有出現在這張表裡的跨界點＝不存在的跨界點；要新增一個，先改這張表。

| # | 方向 | 從 → 到 | 轉換 | 必跑斷言 | 失敗行為 | 出處 |
|---|---|---|---|---|---|---|
| **X1** | 出 | R1 → R3（顯示） | `Money::Display.render(storage, locale:)`，固定兩位小數 ＋ locale 符號／千分位 | 位數恆為 `currency_display.force_minor_unit_digits` | — | 裁定二、鐵律 10 |
| **X2** | 出 | R1 → R4（GraphQL `MoneyV2.amount`） | `cents / 100`，兩位字串 | 符合 `money_boundary.decimal_string_regex` | 序列化失敗 | 鐵律 3（序列化層才轉） |
| **X3** | 出 | R1 → R4（JSON-LD `Offer.price`、feed） | `cents / limits.seo.jsonld.amount_divisor`（＝100，**不看幣別**） | 同上 ＋ `priceCurrency` 取自 `PriceView`，不是 shop currency | 不輸出 Offer | **62 §A.4／§L（本篇不改，只登記）** |
| **X4** | 出 | R1 → R4（CSV 匯出） | 同 X2；價格欄一律主單位 | 兩位小數；**不得輸出 cents** | 匯出中止 | §G |
| **X5** | 出 | R1 → R4（物流商：COD 代收額、報關申報價值） | **由 carrier pack 宣告**；未宣告 ⇒ reject | pack 宣告存在 | `CARRIER_CAPABILITY_UNDECLARED` | 🔴 **58 §G.3 只定義了入向，出向是缺口**（§J M-3） |
| **X6** | 入 | R4 → R1（物流商回傳、CSV 匯入） | `BigDecimal(raw) * 100`；小數 >2 位 ⇒ raise | 全程 `BigDecimal`；結果 `Integer`；**不得 round** | raise／該行失敗 | 58 §G.3 規則 1–2 |
| **X7** | 出 | **R1 → R5（送 PSP）** | `Money::Storage#to_psp_minor(psp:)` | **§D 四條斷言，全部 raise** | raise，**不送出** | 🔴 本篇 §D、63 §G.4 |
| **X8** | 入 | **R5 → R1（PSP 回應／webhook）** | `Money::PspMinor#to_storage` | 同 §D 的反向；型別必須是 `Money::PspMinor` 才准進來 | raise，webhook 進死信 | 🔴 本篇 §E |
| **X9** | 內 | R1 → R2 → R1（presentment 解析） | 放大 ×10⁶、最後一步取整一次 | R2 **不得**離開解析器 | — | 63 §G.3 |
| **X10** | 內 | R1 → 會計分錄 | **不轉換**（分錄就是 R1） | 分錄禁用 R5；雙幣別走 MoneyBag，兩欄都是 R1 | 拒絕入帳 | §F |
| **X11** | 內 | R1 → 平台 rollup | 不轉換 | **跨幣別不得直接相加** | 拒絕彙總 | §F.3、⚠ V-134 |

**這張表的完整性檢查（CI 可跑）**：對 `app/` 全庫搜尋「金額離開/進入行程邊界」的呼叫點（HTTP client、序列化器、CSV writer、view helper），每一處都必須對應到 X1–X11 的其中一列；對應不上的一律 fail。這條把「有沒有漏掉一個邊界」從人工紀律變成可執行斷言（同 63 §D.3 對 `cache_stamp` 的做法）。

---

## C. 型別層防呆：為什麼不能只寫「請注意」

### C.1 選定的手段（四層，缺一層就漏）

Ruby 沒有編譯期型別，所以「編譯期就看得出來」在本專案的等價物是**三件事**：**人眼的編譯期（命名）**、**機器的編譯期（CI）**、**執行期的第一次呼叫（值物件）**。四層合起來才擋得住。

```ruby
# app/models/money.rb —— 三個值物件，彼此不可隱式互換
module Money
  Storage  = Data.define(:cents,    :currency)          # R1
  PspMinor = Data.define(:minor,    :currency, :psp)    # R5
  Decimal  = Data.define(:string,   :currency)          # R4
end
```

| 層 | 做什麼 | 擋住哪一種繞過方式 |
|---|---|---|
| **L1 值物件無隱式轉換** | `Money::Storage` **不實作** `to_i` / `to_int` / `coerce` / 數值型 `to_s` | `stripe.create(amount: order.total)` 直接 `TypeError`。**若實作了 `to_i`，`Integer()`、多數序列化器、字串插值都會自動呼叫它，前三層全部失效**——這是本節最關鍵的一條 |
| **L2 單一建構路徑** | `Money::PspMinor.new` 為 `private_class_method`；唯一建構路徑是 `Money::Storage#to_psp_minor(psp:)` | 不存在「手工湊一個 PspMinor」的路徑 ⇒ §D 的斷言**無法被繞過** |
| **L3 adapter 簽名只收值物件** | PSP adapter 每個帶金額的方法第一行 `raise TypeError unless amount.is_a?(Money::PspMinor)`；`#to_payload` 是唯一變回 `Integer` 的地方，且斷言 `psp` 相符 | 傳裸 Integer 立刻炸；**把 Stripe 的 minor 拿去送 Airwallex 也會炸**（兩家對同一幣別可能宣告不同單位 ⇒ 那是下一個 100 倍） |
| **L4 命名 ＋ CI 靜態檢查** | 識別字後綴鐵律 ＋ 三條 CI 掃描（下表） | 擋住「新寫的程式碼繞過值物件」——L1–L3 只約束已經用了值物件的路徑，L4 約束**還沒寫出來的**路徑 |

### C.2 識別字後綴鐵律（人眼的編譯期）

| 表示法 | 後綴 | 用在 |
|---|---|---|
| R1 | `_cents` | DB 欄位、業務層變數、冪等鍵、分錄 |
| R5 | `_minor` | PSP payload 的鍵與區域變數 |
| R4 | `_decimal` | 十進位字串 |
| R3 | `_display` | 顯示字串 |

**這條規則的全部價值在一件事上**：看到 `_cents` 出現在**送款呼叫點**，reviewer 不需要理解上下文就知道那是 bug。`amount: total_cents` 在 diff 裡是紅的，`amount: total_minor` 是綠的——這是純文字層面的判斷，不需要追型別。

🔴 **DB 金額欄位一律 `bigint` ＋ `_cents` 結尾，不得用 `decimal`／`float`。** 這順便把鐵律 3 的「float 即 bug」從口號變成 migration 期的機械檢查。

### C.3 CI 靜態檢查（機器的編譯期，命中即 fail）

| # | 鍵（`money_boundary.ci_checks`） | 規則 | 為什麼是這一條 |
|---|---|---|---|
| C1 | `psp_dir_must_not_reference_cents` | `app/services/psp/**` 內出現識別字 `_cents` ⇒ fail（白名單：`Money::Storage` 的型別註記與 `#to_psp_minor` 的實作兩處） | PSP 目錄裡本來就不該有 storage 尺度的東西。這是 58 §K 15「transaction 內不得出現 adapter 呼叫」的同構做法 |
| C2 | `external_call_kwarg_must_be_minor` | 對 `Psp::*` 的呼叫，金額 kwarg 名必須以 `_minor` 結尾 ⇒ 否則 fail | 擋住「不經 adapter、直接組 HTTP body」的繞過 |
| C3 | `money_migration_must_be_bigint_cents` | 新增的金額欄位必須 `bigint` ＋ `_cents` 結尾；出現 `decimal`／`float` ⇒ fail | 鐵律 3 的 migration 期執法點 |

### C.4 為什麼註釋擋不住這個 bug（三個理由，都不是風格問題）

1. **註釋不進 CI。** 違反註釋的 PR 照樣綠燈合併。
2. **註釋不在事故現場。** 寫在 `money.rb` 的警告救不了三個月後在 `app/services/psp/airwallex/charge.rb` 新寫一行的人——他不會先去讀 `money.rb`。
3. **🔴 最致命的一條：這個 bug 在 exponent=2 幣別下測試全綠**（§0.2）。註釋唯一能起作用的時機是「有人心裡有疑問而去查」，但這個 bug **不會讓任何人產生疑問**——本地跑 HKD，一切正常。

> **不等 Sorbet／RBS。** 若日後導入，這三個值物件就是天然的 `sig` 邊界；但 L1–L4 在純 Ruby 下已經成立，不把防呆押在一個還沒發生的技術決策上。

---

## D. PSP 送出前的必跑檢查（X7）

### D.1 唯一出口

```ruby
# app/models/money.rb —— 送 PSP／任何外部收款系統前的唯一出口
class Money::Storage
  # 儲存尺度（一律 ×100）與該 PSP 的 minor unit 是兩件事：
  #   顯示 → limits.currency_display.force_minor_unit_digits = 2   （裁定二）
  #   儲存 → limits.money_boundary.storage_scale_multiplier = 100  （不看幣別）
  #   對外 → 該 PSP pack 宣告的 minor unit（正常值＝ISO 4217 exponent）
  def to_psp_minor(psp:)
    exponent = Psp.registry.fetch(psp).minor_unit_exponent(currency)   # A1
    raise Money::PspMinorUnitUndeclared.new(psp:, currency:) if exponent.nil?
    raise Money::UnsupportedCurrencyExponent if exponent > LIMITS.money_boundary.max_supported_iso_exponent  # A2
    divisor = 10**(LIMITS.money_boundary.max_supported_iso_exponent - exponent)   # JPY⇒100、HKD⇒1
    raise Money::NonIntegralPspConversion unless (cents % divisor).zero?          # A3
    Money::PspMinor.__build(minor: cents / divisor, currency:, psp:)              # A4（private 建構）
  end
end
```

### D.2 四條斷言

| # | 斷言 | 違反時 | 為什麼不能寬鬆 |
|---|---|---|---|
| **A1** | 該幣別的 minor unit **必須由該 PSP pack 明文宣告**；`nil` ⇒ raise `PSP_MINOR_UNIT_UNDECLARED` | 拒絕送出 | **未宣告 ≠ 預設 ISO**（比照 56 §A.3、58 §A.3）。業界存在「ISO 為 2 位、但該 PSP 要求金額為 100 的倍數」的特例幣別，靜默套 ISO 會在那些幣別上直接算錯 ⇒ ⚠ **V-130** |
| **A2** | `exponent ≤ money_boundary.max_supported_iso_exponent`（＝2） | 拒絕送出 | exponent=3（KWD/BHD/JOD）的最小單位，×100 的儲存尺度**表達不了**（`divisor` 會是 0.1）。首發擋在 market 建立期（`catalog_flow.unsupported_currency_exponents: [3]`，回 `INCLUSION`），本條是第二道 ⇒ 63 §G.4、⚠ V-94 |
| **A3** | `cents % divisor == 0`；**餘數不為 0 ⇒ raise，不四捨五入** | 拒絕送出 | JPY 的 `148050`（¥1,480.50）在 ISO 下不可表達 ⇒ **是上游算錯了**（湊整規則沒套用，29 §3.3）。悄悄抹掉 50 會讓對帳永遠差幾分錢卻查不出來——同 58 §G.3 規則 2 的理由 |
| **A4** | 回傳型別必為 `Money::PspMinor`，且送出前再驗 `psp` 相符 | `TypeError` | 擋住「A 家的 minor 送去 B 家」（§C.1 L3） |

**額外一條（非生產環境每次轉換都跑）**：往返自檢 `from_psp_minor(to_psp_minor(x)) == x`。在 A3 成立時它恆真——**它擋的不是今天的 bug，是日後有人改了 divisor 公式**。鍵：`money_boundary.roundtrip_selfcheck_envs`。

### D.3 PSP pack 的宣告形態（比照 58 的 carrier pack）

```
psp_packs:
  <psp_code>:
    minor_unit_source: iso4217          # 必填；沒有這一行 ⇒ 該 pack 不得 enable
    minor_unit_overrides: { }           # 幣別 → exponent 的例外表；空表代表「無例外」（≠ 未宣告）
    enable_gate: [ ]                    # 未結案的 V 編號填這裡；非空 ⇒ enabled 必為 false
```

`minor_unit_overrides: {}`（明文空表）與**沒有這個鍵**是兩件不同的事——前者是「已查證、無例外」，後者是「沒人查過」。這個區分在 58 §A.3 已經吃過一次虧，此處沿用。

---

## E. 反方向：從 PSP 進來的金額（X8）

**入向的錯不是 100 倍，是 1/100，而且更難發現**——訂單金額看起來「只是小一點」，不會觸發任何金額上限告警。

```
storage_cents = psp_minor * 10 ** (max_supported_iso_exponent - exponent)
```

### E.1 三條硬規則

1. **PSP 回應／webhook 的金額欄位一律先包成 `Money::PspMinor` 再轉 R1**，不得直接 `update(amount_cents: event.amount)`。
2. 🔴 **金額比對必須先化到同一表示法。** 15 §F4「⚠️坑」第 2 條：「PI 金額與 checkout 現值必須在建單時比對，不符 → 不建單、自動退款、告警」。
   **若拿 PI 的 R5（`1480`）直接比 checkout 的 R1（`148000`）**：
   - HKD ⇒ 兩者相等 ⇒ 正常 ✅
   - **JPY ⇒ 永不相等 ⇒ 每一張 JPY 訂單都被判定為「金額不一致攻擊」⇒ 自動退款 ＋ 告警風暴。**
   這是同一個根因的**第三種表現形態**（前兩種是 100 倍收款與 1/100 記帳），而且它同樣在 HKD 下測試全綠。
3. **冪等鍵一律用 R1。** 15 §F4-1 的 `"pi-#{checkout.token}-#{amount_cents}"` 是 R1，**不要「順手統一成送出去的那個數」**——改成 R5 會讓所有既有 key 失效 ⇒ 重複建 PaymentIntent。鍵：`money_boundary.idempotency_key_amount_representation: storage_cents`。

---

## F. 會計分錄、對帳與平台彙總

### F.1 分錄一律 R1

- 分錄的金額欄位一律 `*_cents`（R1）＋ 幣別碼。**禁止**以 R5 記帳——記了就對不回訂單金額，而且 JPY 的帳會小 100 倍。
- 雙幣別走 `MoneyBag{shopMoney, presentmentMoney}`（29 §3.1），**兩欄都是 R1**。
- 既有實作已對齊，登記於 §J M-6（`37 §6.2` 的 `platform_absorption_journals.amount_cents BIGINT`）——列出來是為了**防止日後有人「順手」改成 PSP 單位**。

### F.2 三方對帳的三種表示法

| 來源 | 表示法 | 轉換 |
|---|---|---|
| 我方訂單／分錄 | R1 | — |
| PSP 結算檔（含手續費、爭議扣款） | **R5** | 先 `to_storage` |
| 銀行入帳明細 | **R4**（十進位字串） | 先 `BigDecimal × 100`（X6） |

**三者必須先各自化成 R1 再比。** 直接比對＝在 JPY 市場上三份檔案永遠對不起來，而在 HKD 市場上永遠對得起來。
⚠ **V-133**：PSP 結算檔（而非 API 回應）的金額單位是否與 API 一致，本輪未取得一手文檔。

### F.3 平台 rollup

`platform_shop_daily_rollups.gmv_30d_cents`（63 §F）是 R1。**跨幣別不得直接相加**——不同租戶的 shop currency 不同，`SUM(gmv_30d_cents)` 是一個沒有單位的數。
處置：要嘛分幣別呈現，要嘛先經 `rate_ppm` 換算成平台記帳幣別。⚠ **V-134**：換算時點口徑（交易日匯率 vs 報表日匯率）未定，兩者在匯率波動期會給出不同的平台營收數字，違反鐵律 7。

---

## G. CSV 匯出入（X4／X6）

| 面 | 規則 |
|---|---|
| 匯出 | 價格欄一律 **R4（主單位、兩位小數）**。JPY 匯出 `1480.00`，**不得輸出 `148000`**——商家在 Excel 看到 148000 會以為系統壞了，而且回匯時會被 X6 當成 ¥148,000 收下 |
| 匯入 | `BigDecimal` 解析 → ×100 → `Integer`；**小數超過兩位 ⇒ 該行失敗**（不 round，58 §G.3 規則 2）；千分位、全形數字、BOM 的清洗沿用 13 §F6 |
| 與 Shopify CSV 的相容 | Shopify 的商品 CSV 價格欄也是主單位十進位 ⇒ R4 同時滿足「遷移友好」（13 §F6-1） |

---

## H. 測試矩陣（🔴 沒有這一節，這個 bug 會在上線後才出現）

### H.1 必進矩陣的幣別

| 幣別 | ISO exponent | 為什麼必須在矩陣裡 |
|---|---:|---|
| **JPY** | 0 | `divisor = 100` 的主案例；100 倍事故的原型 |
| **TWD** | ⚠ 見下 | **本矩陣最危險的一格**（§H.3） |
| **KRW** | 0 | 第二個 zero-decimal，防止「只對 JPY 特判」的錯誤實作 |
| HKD | 2 | 基準法域；回歸案例——確保修正沒把 `divisor = 1` 的路徑弄壞 |
| USD | 2 | 第二個 exponent=2 |
| KWD | 3 | 斷言**被擋下**（A2），不是斷言算對 |

🔴 **CI 規則**：金額路徑的測試檔若一個 zero-decimal 幣別都沒有 ⇒ 視為未涵蓋，**CI fail**（`money_boundary.test_matrix_missing_zero_decimal_action: ci_fail`）。這條是本節唯一的機械化保證——其餘都是清單，清單會被忘記。

### H.2 必測案例（每一條都是一個具體斷言）

| # | 幣別 | 輸入 | 期望 | 擋住什麼 |
|---|---|---|---|---|
| T1 | JPY | 儲存 `148000` | 顯示 `¥1,480.00` | 裁定二 |
| T2 | JPY | 儲存 `148000` | `Offer.price == "1480.00"` | 62 §A.4 |
| T3 | **JPY** | 儲存 `148000` → `to_psp_minor` | **`1480`** | 🔴 **100 倍** |
| T4 | **JPY** | webhook `amount: 1480` → `to_storage` | **`148000`** | 🔴 **1/100** |
| T5 | **JPY** | PI `amount 1480` vs checkout `148000` 的比對 | **判定為相符** | 🔴 每張 JPY 訂單被自動退款（§E.1-2） |
| T6 | JPY | 儲存 `148050`（¥1,480.50） | **raise `NonIntegralPspConversion`** | 悄悄抹掉 50 分 |
| T7 | KRW | 儲存 `1200000`（₩12,000） | psp minor `12000` | 只對 JPY 特判的實作 |
| T8 | **TWD** | 任意值 → `to_psp_minor(psp:)` | **pack 未宣告 ⇒ raise `PSP_MINOR_UNIT_UNDECLARED`**（不是斷言某個 exponent） | §H.3、V-130 |
| T9 | HKD | 儲存 `148000` | psp minor `148000`（`divisor = 1`） | 修正把 exponent=2 弄壞 |
| T10 | USD | 邊界值 `0` / `1` / `BIGINT max` | 往返一致 | 溢位與零值 |
| T11 | KWD | market 建立 | `userErrors{code: INCLUSION}`，且 `to_psp_minor` 亦 raise（A2） | exponent=3 漏網 |
| T12 | 全部 | `from_psp_minor(to_psp_minor(x)) == x` | 恆真 | 日後有人改 divisor 公式 |
| T13 | JPY | CSV 匯出 → 再匯入 | 儲存值不變（`148000`） | §G 的來回失真 |
| T14 | 任一 | 對 PSP adapter 傳裸 `Integer` | `TypeError` | §C L3 |

### H.3 🔴 TWD 是這張表最危險的一格（必讀）

`limits.currency_display.iso4217_zero_decimal_overridden: [JPY, TWD]` 把 TWD 與 JPY 並列，而 `jurisdictions.tw.currency_format.exponent` 已被裁定二從 `0` 改成 `2`（＝顯示位數）。於是同一個幣別在 limits 裡有**兩個看起來都像 exponent 的數字，而且都不是 PSP 該用的那個**。

- **ISO 4217 對 TWD 的 minor unit，本專案至今沒有任何一手出處。** 業界普遍以 2 位處理，且部分 PSP 對 TWD 另有「金額須為 100 的倍數」的特例規則——⚠ **V-130**，未取得官方明文。
- **結案前的處置**：TWD **一律走 A1 的 pack 宣告路徑**。pack 沒宣告 ⇒ `reject`。
  **不得**從 `iso4217_zero_decimal_overridden` 或 `currency_format.exponent` 任何一個推導 TWD 的 PSP 單位。
- 因此 T8 斷言的是**「未宣告時正確地拒絕」**，而不是某個具體 exponent 值——**這正是 §D.2 A1「未宣告 ≠ 預設」設計的價值所在**：在事實不明的幣別上，系統的行為是「拒絕送出」而不是「猜一個數送出去」。

---

## I. `config/limits.yml` 新增的鍵（已落檔）

**本篇不硬編任何數字**（鐵律 6）。新增區塊 `money_boundary:`（位於 `currency_display:` 之後）：

| 鍵群 | 用在本篇哪一節 |
|---|---|
| `storage_scale_multiplier` / `storage_scale_ignores_currency` / `storage_column_suffix` / `storage_column_sql_type` / `storage_column_decimal_or_float_forbidden` | §A R1、§C.2 |
| `decimal_string_digits` / `decimal_string_regex` / `decimal_string_divisor` / `decimal_parse_*` | §A R4、§B X2/X4/X6、§G |
| `psp_minor_unit_source_default` / `psp_minor_unit_must_be_declared_by_pack` / `psp_undeclared_currency_action` / `psp_undeclared_error_code` / `max_supported_iso_exponent` / `psp_non_integral_conversion_action` / `psp_rounding_forbidden` | §D.2 A1–A3 |
| `iso4217_table_source` / `iso4217_table_unpinned_gem_forbidden` | ⚠ V-131 |
| `value_objects` / `value_object_implicit_coercion_forbidden` / `psp_minor_single_construction_path` / `psp_adapter_rejects_bare_integer` / `identifier_suffixes` / `ci_checks` | §C |
| `inbound_psp_minor_must_convert` / `inbound_comparison_must_normalize_to_storage` / `idempotency_key_amount_representation` | §E |
| `journal_representation` / `journal_psp_minor_forbidden` / `reconciliation_normalize_to` / `cross_currency_sum_forbidden` | §F |
| `test_matrix_*` / `roundtrip_selfcheck_envs` | §H |

另在 `currency_display` 新增反引用鍵 `not_a_psp_unit_source: true`（§A 末段）。

---

## J. 與既有規格的衝突登記

> **本篇原則上不改其他檔案，只登記。** 例外：**M-1／M-2 已於 2026-08-12 依使用者裁定（A-1「現在修」）實際改檔結案**——見下表 ✅ 兩列與 §J.1 的結案紀錄。其餘各列仍是登記。

| # | 衝突 | 現況 | 本篇立場 | 誰該改 |
|---|---|---|---|---|
| ~~**M-1**~~ ✅ **已結案**（2026-08-12，使用者裁定 A-1「現在修」）<br>🔴 原 P0 | `stripe_amount()` 的定義描述的是**裁定二之前**的儲存模型 | ~~15 §F4-5 逐字：「幣別：`stripe_amount()` helper 統一處理小數位（**JPY 等零小數幣別不乘 100**、個別幣別有整除規則）」~~ **已改寫** | 那句話在「JPY 儲存 1480」的舊模型下是對的。**裁定二之後 JPY 儲存 148000**，`stripe_amount()` 對 JPY 必須**除以 100**。照現行文字實作＝收款 100 倍 | ✅ **15 §F4-5 已改寫為引本篇 §D**（四條斷言逐條列出）；`stripe_amount()` 全面退場，改為 `Money::Storage#to_psp_minor(psp:)` 值物件簽名。**結案 commit：見本輪**（§J.1） |
| ~~**M-2**~~ ✅ **已結案**（同上） | 兩處指標指向已過時的定義 | ~~16 §F5「零小數幣別 → 只在序列化層由 15-F4 的 `stripe_amount()` 處理，業務層不感知」；55 §A「③零小數幣別 → 僅在序列化層由 15-F4 `stripe_amount()` 處理」~~ **兩處已改指本篇 §D** | **指標方向正確**（業務層不感知 ✅），但指向的定義已過時 ⇒ 改指 65 §D | ✅ **16 §F5.1、55 §A.0 各已改一個交叉引用**，並補上「③其實不是捨入點（餘數 raise 不 round）」。**結案 commit：見本輪**（§J.1） |
| **M-3** | 物流商金額**只定義了入向** | 58 §G.3 標題即「物流商回傳的十進位字串怎麼變成 cents」 | 出向（COD 代收金額、報關申報價值）**未定義**。依 58 §A.3「未宣告 ≠ 預設」，carrier pack 須宣告 `money.outbound_format`，未宣告 ⇒ reject（§B X5） | 58 §G.3 補出向一節，或 `carrier.money` 加 `outbound_format` |
| **M-4** | 鍵名誤導 | `limits.currency_display.iso4217_zero_decimal_overridden: [JPY, TWD]` | 該鍵是「顯示位數被覆蓋的幣別」，**不是 PSP 單位來源**。已在 limits.yml 加 `not_a_psp_unit_source: true` 反引用 | ✅ 本輪已處理（limits.yml） |
| **M-5** | — | 62 §A.4／§L 的 `Offer.price` ＝ `cents/100` 固定兩位 | **無衝突**，登記為 R4 的一個消費者。本篇不改 62，只確保兩處的表一致 | — |
| **M-6** | — | 37 §6.2 `platform_absorption_journals.amount_cents BIGINT` | **無衝突**，已是 R1。列出來是為了防止日後被「順手」改成 PSP 單位 | — |

### J.1 M-1／M-2 的結案紀錄（2026-08-12，使用者裁定 A-1「現在修」）

**結案 commit：見本輪。** 授權範圍＝`docs/specs/15`／`16`／`55`／`58`／`65`／`config/limits.yml`（15 號先前不在任何 agent 的可改清單裡，這正是 M-1 拖到現在的唯一原因，見 `docs/handoff/2026-08-12-open-decisions.md` A-1）。

**實際改到的七處**（每一處都留了 `<!-- 依 65 §J M-1／M-2 修正，原文：… -->` 追溯註釋 ＋ 🔴 防回退註記）：

| # | 位置 | 形態 | 改了什麼 |
|---|---|---|---|
| 1 | **15 §F4 第 5 點** | 🔴 **出向 100 倍**（M-1 本體） | 「零小數幣別不乘 100」整條改寫為引本篇 §D：`to_psp_minor(psp:)` ＋ `divisor = 10**(2−exponent)` ＋ 四條斷言 |
| 2 | **15 §F2.1 捨入位置段** | 同上的**第四個指標** | 🔴 **本篇 §J 原本只點名三處**（15 §F4-5、16 §F5、55 §A），這一處是修 M-1 時 grep 出來的。指標方向對、指向的定義已廢 ⇒ 改指 §D |
| 3 | **15 §F4「⚠️坑」第 2 條** | 🔴 **第三形態**（§E.1-2） | 補「比對前兩邊都必須先化到 R1」。原文缺這句 ⇒ **每張 JPY 訂單被判成金額不符而自動退款** |
| 4 | **15 §F5 第 2 點** | 🔴 **入向 1/100**（§E.1-1） | 「金額＝PI 實收」補成「經 `Money::PspMinor#to_storage` 轉回 R1 後」入帳 |
| 5 | **15 §F5「⚠️坑」末條** | 第三形態的第二個落點 | 「PI vs Calculator 不一致標記 review」補上同一表示法前提，否則 JPY 100% 命中、淹掉 review 佇列 |
| 6 | **16 §F5.1 三個捨入點③** | M-2 交叉引用 | 改指 §D，並澄清**③不是捨入點**（餘數 raise 不 round，§D.2 A3）——原文寫在「捨入點」清單裡本身就在誤導 |
| 7 | **55 §A.0 捨入總則③** | M-2 交叉引用 | 同上；另補「分錄禁以 R5 記帳」（§F.1）與「M02 冪等鍵恆 R1」（§E.1-3） |

**順帶加固、非 M-1／M-2 本體的兩處**（同屬 §B 的跨界點，原文沉默）：
- **15 §F4 第 1 點**：冪等鍵裡的數恆為 R1，`money_boundary.idempotency_key_amount_representation: storage_cents`（§E.1-3 逐字點名本條）。
- **15 §F4 第 6 點**：`Stripe::Refund.create(amount:)` 是**出向**，同樣走 X7。退款側的 100 倍不會被買家投訴，會直接退超或撞退款上限。

🔴 **本輪的方法論教訓（比修正本身更值得留下）**：§J 原本登記三處，實際 grep 出**七處**，且其中三處（#3／#4／#5）**不是「零小數幣別」這個字串命中的**——它們是同一個根因的另外兩種形態，字面上完全看不出來。
⇒ **登記表要靠 grep 補完，不能靠登記表自己完整。** 找同根因時要搜的不是那句錯話，是**跨界點**：「金額離開／進入行程邊界」的每一個呼叫點（§B 的完整性檢查正是要把這件事機械化）。

**已知仍在其他檔案的同根因文字**（不在本輪授權範圍，未改，登記為 M-7）：

| # | 位置 | 現況 | 該怎麼改 |
|---|---|---|---|
| **M-7** | `52 §1 P0-01`（退款公式列的「公式」欄，逐字「零小數幣別只在序列化層處理」）；`57` 檔頭「金額鐵律」引言（逐字「零小數幣別只在序列化層」） | 兩處都只是**轉述** 16-F5.1 的三個捨入點，**沒有**重複 15 §F4-5 那句「不乘 100」⇒ **危害等級遠低於 M-1**，但仍指向一個已改寫的定義 | 兩處各改一個交叉引用指向 65 §D，並比照 #6 澄清「③不是捨入點」。**不阻塞**——照這兩處實作不會產生 100 倍，只會多跳轉一次。⚠️ 兩檔皆不在 2026-08-12 A-1 的授權範圍內 |

---

## K. 本篇驗收（對照 `docs/specs/11` §0 七維度）

### 2 資料完整

1. §H.2 的 T1–T14 全綠；T3／T4／T5／T6 任一紅 ⇒ **不得上線**（這四條是三種事故形態的直接斷言）。
2. 對 `app/` 全庫掃描，每一個金額跨界點都對應到 §B 的 X1–X11 其中一列；對應不上即 fail。

### 4 效能

3. 值物件的建構不得出現在熱路徑的迴圈內（集合頁 50 張卡 ⇒ 50 次 `Money::Display.render`，可接受；50 × N 次不可）。

### 6 測試

4. **`money_boundary.test_matrix_zero_decimal_required` 的每個幣別都出現在金額測試檔中**；缺任一 ⇒ CI fail。
5. 金額路徑 100% 覆蓋（11 §0 維度 6）。
6. `app/` 下 grep `to_f` 在金額相關檔案命中數為 0（沿用 58 §K 24）。
7. §C.3 的三條 CI 檢查各有一個「故意違反」的 fixture，證明檢查真的會 fail（**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有）。

### 5 可觀測

8. 每一次 X7／X8 轉換落結構化日誌：`psp`、`currency`、`exponent`、`divisor`、`storage_cents`、`psp_minor`。對帳事故時這六個欄位就是完整的還原資訊。
9. `NonIntegralPspConversion` 與 `PspMinorUnitUndeclared` 兩個例外 ⇒ **P1 告警**（它們代表上游算錯或 pack 沒宣告，不是使用者輸入錯誤）。

---

## L. 待查證（V-130 起）

> 沿用 52 §附錄 A 與 58 §附錄 A 的規則：**無明確出處一律不自補規則；當前處置一律是保守失效**。

| # | 待查證項目 | 去哪查 | 當前處置 | 阻塞什麼 |
|---|---|---|---|---|
| **V-130** | **各 PSP 對各幣別實際採用的 minor unit 是否等同 ISO 4217**——特別是 TWD，以及業界傳聞中「ISO 為 2 位但該 PSP 要求金額為 100 的倍數」的那一類幣別 | Stripe／Airwallex 的官方 API 參考（幣別與最小金額頁）；沙箱實測 | **pack 必須明文宣告 minor unit，未宣告 ⇒ reject**（§D.2 A1）。TWD 在宣告前不得送款 | §D、§H.3 |
| **V-131** | **ISO 4217 minor unit 表的一手來源與落地形式**：進 repo 還是用 gem？用 gem 的話哪一個、如何釘版？ | ISO 4217 官方維護機構（SIX）發布的 `list-one` 資料；候選 gem 的維護狀態 | 表進 repo（`config/iso4217_minor_units.yml`）＋ 版本註記；**禁止未釘版的 gem**——一張會自己更新的表就是一顆定時炸彈 | §D.1 |
| **V-132** | **Airwallex 的金額欄位語義**（單位、幣別欄位名、webhook 金額形態）——本輪未取得一手文檔 | developer.airwallex.com | `psp_packs.airwallex.enable_gate: [V-132]` ⇒ 不得 enable | §D.3 |
| **V-133** | **PSP 結算檔（非 API 回應）的金額單位**是否與 API 一致；手續費與爭議扣款的單位 | 各 PSP 的結算報表規格頁；實際下載一份對照 | 對帳器對結算檔一律先做 §F.2 的顯式轉換，並在轉換前後各記一次日誌 | §F.2 |
| **V-134** | **平台 rollup 跨幣別彙總的換算時點**：交易日匯率還是報表日匯率？ | 使用者裁定（會計政策問題，非技術問題） | `cross_currency_sum_forbidden: true` ⇒ 平台側**分幣別呈現**，不給單一合計數 | §F.3 |

---

## 附錄 A：一頁速查（貼在 PR 模板裡）

```
JPY ¥1,480
  R1 儲存      148000        ← DB、業務層、分錄、冪等鍵      （×100，不看幣別）
  R3 顯示      "¥1,480.00"   ← Liquid money、admin、通知信   （恆兩位）
  R4 十進位    "1480.00"     ← JSON-LD、feed、CSV、MoneyV2、物流商
  R5 PSP       1480          ← 只在 PSP adapter payload      （÷ 10^(2-exponent)）

送出前：pack 有宣告嗎？exponent ≤ 2 嗎？整除嗎？型別對嗎？——四條都過才准送。
收進來：先包成 Money::PspMinor，再 to_storage，再比對。比對前兩邊都要是 R1。
測試裡有 JPY／TWD／KRW 嗎？沒有的話，你的測試全綠也證明不了任何事。
```
