# 65 — 金額單位邊界契約（money unit boundary）

> **一句話**：系統裡有**七種**金額表示法，它們的單位互不相同；每一個跨界點都必須顯式轉換，而**在 HKD／USD／MYR 這些 exponent=2 的幣別下，錯的實作與對的實作輸出完全一樣**——所以這件事不能靠測試發現，只能靠型別與 CI 擋住。
> <!-- 依 69 號 §V-188 修正（2026-08-12），原文：「系統裡有**五種**金額表示法」。
>      新增的第六種是 **R6（PSP 十進位字串）**：69 號查到 **Airwallex 根本不用 minor units，
>      而是十進位主單位字串**（`alt`，airwallex.com/docs/api/data_types）。原本的五種表示法裡
>      **沒有任何一種能承載這個形態**——R4 雖然也是十進位字串，但它不帶 `psp` 綁定、不跑 §D 的斷言，
>      拿 R4 送 PSP 等於把 JSON-LD／物流商用的值直接送進收款通道（§A 末段第 3 點）。
>      🔴 **這不是鐵律 3 放寬**：反過來，四家 PSP 四種算法正面證實了「PSP 單位必須逐家宣告、
>         不得套 ISO」是對的，只是**宣告的內容比原本想的多一個維度（格式）**。任何人不得刪回五種。 -->
> <!-- 🔴 2026-08-31 更正＋增修（G6-0(b)，一手複驗）：第七種是 **R7（PSP 十進位主單位「數」，
>      `amount_format: decimal_number`，`Money::PspNumber`）**。Airwallex 官方 data_types 逐字
>      "Currency amounts specified in major units as defined by ISO 4217. For example, $9.99 is
>      represented as 9.99."，且 payment_intents create schema `amount: number`（JSON number）——
>      **69 號 2026-08-12 把它記成 decimal_string 是錯的**（見 69 號同日更正註；platforms 文檔
>      範例出現過字串形，屬後端強制轉型容忍、非契約）。decimal_string（R6）本身仍然真實存在：
>      **現任實證代表＝PayPal**（Orders v2 `amount.value` 型別 string、pattern
>      `^((-?[0-9]+)|(-?([0-9]+)?[.][0-9]+))$`，取證 2026-08-31）。
>      🔴 R6 與 R7 單位語義相同（主單位）、wire form 不同（string vs number）——**不得共用型別**：
>      共用會讓「宣告與實際 wire form 不符」在我方側靜默通過。任何人不得刪回六種。 -->
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

**七種對外可見 ＋ 一種只存在於解析器內部。** 任何金額值在任何時刻都**恰好屬於其中一種**；不知道自己屬於哪一種的值，就是 bug。

| # | 名稱 | Ruby 型別 | 單位 | 尺度 | 出現在哪 | 定義出處 |
|---|---|---|---|---|---|---|
| **R1** | 儲存 cents | `Money::Storage`（內含 `Integer`） | storage cent | **一律 ×100，不看幣別** | 所有 DB 金額欄位（後綴 `_cents`）、全部業務層運算、冪等鍵、會計分錄 | 鐵律 3 ＋ `currency_display.storage_scale_unchanged` |
| **R2** | micro-cents | `Integer`（裸值） | cents × 10⁶ | ×10⁸ 相對主單位 | **只在 `Pricing::PresentmentResolver` 的方法內部**；不得跨方法邊界、不得落庫、不得序列化 | 63 §G.3 |
| **R3** | 顯示字串 | `String` | — | 恆兩位小數 ＋ market locale 的符號與千分位 | Liquid `money` filter、admin UI、通知信、PDF、面單 | 裁定二 ＋ 鐵律 10 |
| **R4** | 十進位字串 | `Money::Decimal`（內含 `String`） | **主單位**（major unit） | 恆兩位小數、**無幣別符號、無千分位**、小數點為 `.` | JSON-LD `Offer.price`、GMC/Meta feed、CSV 價格欄、GraphQL `MoneyV2.amount`、**物流商** | 62 §A.4 ＋ 58 §G.3 |
| **R5** | PSP minor unit | `Money::PspMinor`（內含 `Integer`） | **該 PSP 為該幣別宣告的 minor unit**（正常值＝ISO 4217 exponent，**但不保證**——見 §D.4） | 依幣別（JPY 0／HKD 2） | **只在 `amount_format: minor_units` 的 PSP adapter payload 內** | 本篇 §D |
| **R6** | **PSP 十進位字串** | `Money::PspDecimal`（內含 `String`） | **主單位**（major unit），位數由 pack 宣告（**per-currency 生效位數 ≤ 2**，§D.2 A7） | 生效位數位小數、**無幣別符號、無千分位**、小數點為 `.`（0 位＝無小數點，如 PayPal 的 JPY `"1480"`） | **只在 `amount_format: decimal_string` 的 PSP adapter payload 內**（**PayPal 型**；2026-08-31 前實證代表寫 Airwallex——已更正，見 §D.4） | 本篇 §D |
| **R7** | **PSP 十進位主單位「數」** | `Money::PspNumber`（內含 `BigDecimal`） | **主單位**（major unit），位數由 pack 宣告（同 A7） | wire form＝JSON **number**（`9.99`）；🔴 全程 BigDecimal，**Float 即 bug** | **只在 `amount_format: decimal_number` 的 PSP adapter payload 內**（Airwallex 型；2026-08-31 新增） | 本篇 §D |

<!-- 2026-08-15 措辭修正（本尊考掘）。R4／R6 的尺度欄原文寫「無**符號**、無千分位」。
     🔴 那句話有歧義，而兩種讀法差很多：
       ①「無幣別符號」（不寫 HK$）——這是本意，`config/limits.yml:189` 逐字就是這樣寫的；
       ②「無正負號」（不許負數）——照這個讀法實作出 `^\d+\.\d{2}$`，就會**擋掉退款差額**。
     `money_boundary.decimal_string_regex` 原文是 `^-?\d+\.\d{2}$`（**明文允許前置負號**），
     所以規格內部本來就是 ①，只是中文寫得不夠死。五處全部改為「無幣別符號」。 -->

### §A.7 正負號：值物件層**不驗**，驗在寫入端與 PSP adapter

🔴 **本篇原本從頭到尾沒提過負數**，而鐵律 7 的註釋明說「總銷售額可以是負數」——
這個缺口會讓實作者在 `Money::Storage` 上加一條 `cents >= 0` 的驗證，然後退款流程整條卡死。

本尊考掘結論（Admin API 2026-07 逐頁查證）：

| 層 | 本尊行為 | 我方 |
|---|---|---|
| **scalar／型別層** | `Decimal` 官方明文是 **signed**；`MoneyV2`／`MoneyInput` 允許負數 | `Money::Storage`／`Money::Decimal` **一律不驗正負** |
| **業務讀取面** | 官方點名可為負的只有 `Order.totalOutstandingSet`、`Order.refundDiscrepancySet`、`TenderTransaction.amount` | 同 |
| **交易層（退款）** | 一律**正數**，方向由 `kind`（SALE／CAPTURE／REFUND／VOID）承載 | 同——**退款金額不是負數** |
| **送 PSP** | 正數（Stripe `POST /v1/refunds` 的 amount 官方逐字「A positive integer…」） | PSP adapter **驗正數**，負值一律 raise |
| **訂單編輯的減項** | 用**獨立型別 ＋ 正整數 delta**（Increment／Decrement、Add／Remove 成對），不用負數 | 同——輸入端一律禁負 |
| **tender 層** | 🔴 **相反**：`tenderTransactions` 明文「負數＝退款」 | 若日後做這個查詢面，**必須照抄這個相反的慣例並在此處寫明** |

⇒ **驗證放在邊界不是放在型別**：值物件負責單位，不負責業務方向。
在 `Money::Storage` 上驗非負，等於用型別系統表達一個**只在某些路徑成立**的業務規則。

⚠️ **仍未查到**：`OrderAdjustment.amountSet` 個別項的正負（官方只在其加總
`Order.refundDiscrepancySet` 上有負數語義）；`CalculatedOrder.totalOutstandingSet` 是否與
`Order.` 同語義；ShopifyQL 各 MONEY measure 的 **API 回傳**符號（報表 UI 明文
「reversal 顯示為負」，但沒有頁面把 UI 符號與 API 符號連起來）。
⇒ **鐵律 7 的一致性測試若要斷言 `sales_reversals` 的符號，目前沒有官方依據**，不得硬寫。

<!-- R6 依 69 號 §V-188 新增（2026-08-12）。原表只有五列，**R5 是唯一的對 PSP 出向表示法**，
     其隱含前提是「所有 PSP 都收整數 minor unit」。69 號查到的四家 PSP 是**四種算法**：
       Adyen（`alt`）＝整數 minor units，KWD/BHD/JOD/OMR/TND exponent 3，
                       且**明文說 CLP／CVE／IDR／ISK 以自家表為準、與 ISO 4217 不同**；
       Datatrans（`alt`）＝整數 minor units，三位小數幣別 ×1000，自稱遵循 ISO 4217；
       Stripe（`alt`）＝整數 minor units ＋ `Special cases` 表覆蓋 ISO（ISK／HUF／TWD／UGX），
                       且 **HUF／TWD 的 payout 金額必須整除 100**；
       Airwallex（`alt`）＝🔴 **十進位主單位字串**（`9.99` 就是九元九角九分），**完全不是 minor units**。
     ⇒ `Money::PspMinor` 這個型別在 Airwallex 型 PSP 上**根本不適用**，這是型別設計擋不住的形態，
        不是一個參數問題。🔴 **任何人不得以「Airwallex 也能用 R4」為由刪掉 R6**——理由見下方第 3 點。 -->

**三件最容易被「順手統一」而搞爛的事**：

1. **R4 ≠ R5。** 物流商走 R4（十進位字串，58 §G.3 已定），`minor_units` 型 PSP 走 R5（整數 minor unit）。兩者都是「對外」，但**慣例不同**。有人把它們合成一個 `to_external_amount()` 就是下一次事故。
2. **R1 的 ×100 與 R5 的 exponent 沒有關係。** `100` 不是「因為大多數幣別是 2 位」，它是**我方選定的固定儲存尺度**。日後要支援 exponent=3，改的是 `storage_scale_multiplier`（全庫 migration），**不是**轉換函式（63 §G.4 已定）。
3. 🔴 **R6 ≠ R4，即使兩者的線上形態（wire form）一模一樣。** 兩者都是 `"1480.00"` 這種字串，所以「R4 已經是十進位字串了，直接拿去送 Airwallex 就好」看起來完全合理——**而這正是要擋的那一步**：
   - R4 **不帶 `psp` 綁定**。§C L3 的 adapter 斷言靠 `psp` 欄位擋「A 家的值送去 B 家」；R4 沒有這個欄位，等於把該防線關掉。
   - R4 **不跑 §D 的斷言**。它的建構路徑是 `X2/X3/X4`（GraphQL／JSON-LD／CSV），**不經過 pack 宣告檢查、不經過整除檢查**。放行 R4 ⇒ 一個沒有任何 PSP 檢查的值直接進收款通道。
   - R4 的**消費者包含物流商與 feed**。一旦 adapter 收 R4，`carrier_declared_value_decimal` 這種變數就能一路傳到 charge 呼叫，而它在型別上完全合法。
   ⇒ **R6 是獨立型別，唯一建構路徑是 `Money::Storage#to_psp_amount(psp:)`（§D.1）。R4 傳進任何 PSP adapter 一律 `TypeError`。**

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
| **X7** | 出 | **R1 → R5／R6／R7（送 PSP）** | 🔴 **依該 pack 宣告的 `amount_format` 分流**，唯一入口 `Money::Storage#to_psp_amount(psp:)`；`amount_format` 未宣告 ⇒ reject（連分流都不做） | **§D.2 的斷言全部 raise**（A0／A4／A5 三種格式都跑；A1–A3 僅 `minor_units`；A6／A6c／A7 僅 decimal 兩格式） | raise，**不送出** | 🔴 本篇 §D、63 §G.4、69 §V-188 |
| **X7a** | 出 | R1 → **R5**（`amount_format: minor_units`：Stripe／Adyen／Datatrans 型） | `cents / 10**(2 − exponent)` ⇒ `Money::PspMinor` | A0–A5 | raise | §D.1 |
| **X7b** | 出 | R1 → **R6**（`amount_format: decimal_string`：**PayPal 型**） | `cents / 100` 的**生效位數**十進位字串 ⇒ `Money::PspDecimal`；🔴 **全程 `BigDecimal`／字串組裝，不得經 float**；0 位＝無小數點（`"1480"`） | A0、A4、A5、A6、A6c、A7 | raise | §D.1 <!-- 2026-08-31 更正：實證代表原寫 Airwallex（V-132 掛此）——Airwallex 實為 JSON number（X7c）。--> |
| **X7c** | 出 | R1 → **R7**（`amount_format: decimal_number`：Airwallex 型；2026-08-31 新增） | `cents / 100` 的 `BigDecimal` ⇒ `Money::PspNumber`；🔴 全程 BigDecimal，**Float 即 bug**；wire 序列化為 JSON **number**（adapter 責任，`BigDecimal#to_json` 預設吐字串 ⇒ 需原文注入，不得經 `to_f`） | A0、A4、A5、A6c、A7 | raise | §D.1 |
| **X8** | 入 | **R5／R6／R7 → R1（PSP 回應／webhook）** | 唯一入口 `Money.from_psp_amount(raw, currency:, psp:)`：**原始值先依 pack 的 `amount_format` 包成對應型別**，包不出來就不准進 | 同 §D 的反向；形態必須符合宣告格式（`minor_units`＝Integer／`decimal_string`＝String／`decimal_number`＝BigDecimal 或 Integer，**Float 恆 TypeError**），且 `psp` 相符 | raise，webhook 進死信 | 🔴 本篇 §E |
| **X8a** | 入 | R5 → R1 | `minor * 10**(2 − exponent)` | 型別＋`psp`＋exponent 來源同 X7a | raise | §E |
| **X8b** | 入 | R6 → R1 | `BigDecimal(str) * 100`；小數 > 該幣別生效位數 ⇒ raise（**不得 round**，同 X6）；🔴 無小數點字串＝0 位（PayPal 對 JPY 的合法形） | 型別＋`psp`＋A6／A7 的字串格式 | raise | §E |
| **X8c** | 入 | R7 → R1（2026-08-31 新增） | `number * 100`；小數 > 生效位數 ⇒ raise（不得 round）；🔴 **webhook 解析必須 `JSON.parse(raw, decimal_class: BigDecimal)`**——預設解析吐 Float，`from_psp_amount` 對 Float 一律 TypeError | 型別＋`psp`＋A7 | raise | §E |
| **X9** | 內 | R1 → R2 → R1（presentment 解析） | 放大 ×10⁶、最後一步取整一次 | R2 **不得**離開解析器 | — | 63 §G.3 |
| **X10** | 內 | R1 → 會計分錄 | **不轉換**（分錄就是 R1） | 分錄禁用 R5；雙幣別走 MoneyBag，兩欄都是 R1 | 拒絕入帳 | §F |
| **X11** | 內 | R1 → 平台 rollup | 不轉換 | **跨幣別不得直接相加** | 拒絕彙總 | §F.3、⚠ V-134 |
| **X12** | 入 | R4 → R1（**admin GraphQL mutation 金額輸入**：`ProductSetVariantInput.price` 等） | `Money::Decimal.from_string(raw, shop_currency)` → `#to_storage`（BigDecimal×100 ⇒ Integer） | 字串符合 `money_boundary.decimal_string_regex`（恆兩位小數）；**不得 round、不得補位**；價格域另擋負數（`GREATER_THAN_OR_EQUAL_TO`） | userErrors `INVALID`（HTTP 200，鐵律 4 ①） | 🔴 2026-08-23 新增（本表封閉條款：admin 入向此前**不存在於表中**，productSet 落地時補列）；63 §B.3 `variant_price_write_mutations` |

**這張表的完整性檢查（CI 可跑）**：對 `app/` 全庫搜尋「金額離開/進入行程邊界」的呼叫點（HTTP client、序列化器、CSV writer、view helper），每一處都必須對應到 X1–X11（PSP 兩向再細分 X7a／X7b／X8a／X8b）的其中一列；對應不上的一律 fail。這條把「有沒有漏掉一個邊界」從人工紀律變成可執行斷言（同 63 §D.3 對 `cache_stamp` 的做法）。

---

## C. 型別層防呆：為什麼不能只寫「請注意」

### C.1 選定的手段（四層，缺一層就漏）

Ruby 沒有編譯期型別，所以「編譯期就看得出來」在本專案的等價物是**三件事**：**人眼的編譯期（命名）**、**機器的編譯期（CI）**、**執行期的第一次呼叫（值物件）**。四層合起來才擋得住。

```ruby
# app/models/money.rb —— 五個值物件，彼此不可隱式互換
module Money
  Storage    = Data.define(:cents,  :currency)          # R1
  PspMinor   = Data.define(:minor,  :currency, :psp)    # R5  amount_format: minor_units
  PspDecimal = Data.define(:string, :currency, :psp)    # R6  amount_format: decimal_string
  PspNumber  = Data.define(:number, :currency, :psp)    # R7  amount_format: decimal_number（BigDecimal）
  Decimal    = Data.define(:string, :currency)          # R4  ← 🔴 無 :psp 欄位，**不是**對 PSP 的表示法
end
```

<!-- `PspDecimal` 依 69 號 §V-188 新增（2026-08-12）。原本只有三個值物件，其中 R5 是唯一的
     對 PSP 出向型別。🔴 **`Money::Decimal` 與 `Money::PspDecimal` 的欄位差別只有 `:psp` 一個，
     這不是冗餘**——沒有 `:psp` 就無法在 adapter 端斷言「這個值是為這一家算的」，
     而那正是 L3 存在的全部理由（§A 末段第 3 點）。任何人不得把兩者合併成一個型別。 -->

| 層 | 做什麼 | 擋住哪一種繞過方式 |
|---|---|---|
| **L1 值物件無隱式轉換** | `Money::Storage` **不實作** `to_i` / `to_int` / `coerce` / 數值型 `to_s`；🔴 `Money::PspDecimal` **不實作** `to_s`／`to_str`（它內含字串，最容易被字串插值靜默展開） | `stripe.create(amount: order.total)` 直接 `TypeError`。**若實作了 `to_i`，`Integer()`、多數序列化器、字串插值都會自動呼叫它，前三層全部失效**——這是本節最關鍵的一條。**R6 的等價陷阱是 `to_s`**：`"#{amount}"` 在 JSON body 組裝時到處都是，一旦 `to_s` 回傳裸金額字串，R6 的型別防線就跟不存在一樣 |
| **L2 單一建構路徑** | `Money::PspMinor.new`／`Money::PspDecimal.new`／`Money::PspNumber.new` 皆為 `private_class_method`；**三者唯一的建構路徑是 `Money::Storage#to_psp_amount(psp:)`（出向）與 `Money.from_psp_amount`（入向）**（依 pack 的 `amount_format` 決定產出哪一個） | 不存在「手工湊一個 PspMinor／PspDecimal／PspNumber」的路徑 ⇒ §D 的斷言**無法被繞過**。🔴 **也不存在「先做一個 R4 再改型」的路徑**——`Money::Decimal` 沒有任何轉成 `PspDecimal` 的方法 |
| **L3 adapter 簽名只收值物件，且只收「該 pack 宣告的那一種」** | PSP adapter 基類第一行斷言 `amount.is_a?(Psp.registry.fetch(psp).amount_value_class)`（`minor_units` ⇒ `Money::PspMinor`／`decimal_string` ⇒ `Money::PspDecimal`／`decimal_number` ⇒ `Money::PspNumber`），再斷言 `amount.psp == psp`；`#to_payload` 是唯一變回 `Integer`／`String`／`BigDecimal` 的地方 | 傳裸 Integer／裸 String 立刻炸；**把 Stripe 的 minor 拿去送 Airwallex 也會炸**（型別不符）；**把 PayPal 的十進位字串送去 Stripe 或 Airwallex 也會炸**；**把 JSON-LD／物流商用的 `Money::Decimal` 送去任何一家都會炸**（那個類別不在任何 pack 的 `amount_value_class` 值域裡） |
| **L4 命名 ＋ CI 靜態檢查** | 識別字後綴鐵律 ＋ 四條 CI 掃描（下表） | 擋住「新寫的程式碼繞過值物件」——L1–L3 只約束已經用了值物件的路徑，L4 約束**還沒寫出來的**路徑 |

> 🔴 **為什麼 Airwallex 型必須靠型別擋，而不是靠 adapter 內部自己轉**：`decimal_string` 的錯誤形態**不是 100 倍**，是**「送出去的字串長得很像對的」**。`148000` 這個儲存值若被誤當主單位輸出成 `"148000.00"`，Airwallex 會收下並收款十四萬八千元——**而它在 HKD 上也錯**（不像 R5 的 bug 只在 zero-decimal 幣別現形）。也就是說 R6 的誤用**比 R5 更容易被基準法域的測試抓到**，但**代價更大**（任何幣別都會錯），所以防線只能更緊，不能更鬆。

### C.2 識別字後綴鐵律（人眼的編譯期）

| 表示法 | 後綴 | 用在 |
|---|---|---|
| R1 | `_cents` | DB 欄位、業務層變數、冪等鍵、分錄 |
| R5 | `_minor` | `minor_units` 型 PSP payload 的鍵與區域變數 |
| R6 | `_psp_decimal` | 🔴 `decimal_string` 型 PSP payload 的鍵與區域變數（**不是** `_decimal`） |
| R7 | `_psp_number` | `decimal_number` 型 PSP payload 的鍵與區域變數（2026-08-31 新增；⚠ C2 掃描的後綴白名單同步隨 CLAUDE.md 同步 PR 落 `scripts/check-money-boundary.rb`——該 PR 落地前，掃描對 `_psp_number` 仍是 fail-closed 拒收，方向安全） |
| R4 | `_decimal` | 十進位字串（JSON-LD／feed／CSV／MoneyV2／物流商）|
| R3 | `_display` | 顯示字串 |

**這條規則的全部價值在一件事上**：看到 `_cents` 出現在**送款呼叫點**，reviewer 不需要理解上下文就知道那是 bug。`amount: total_cents` 在 diff 裡是紅的，`amount: total_minor` 是綠的——這是純文字層面的判斷，不需要追型別。

🔴 **R6 的後綴刻意不是 `_decimal`**（依 69 §V-188 新增）：`_decimal` 已經被 R4 佔用，而 R4 與 R6 的**線上形態完全相同**——如果兩者共用後綴，§C.2 這條規則在 Airwallex 這條路徑上就**完全失效**（`amount: total_decimal` 看起來是綠的，但它可能是給物流商算的那個值）。**兩種表示法只要 wire form 相同，就必須靠後綴把它們在純文字層面分開。**

🔴 **DB 金額欄位一律 `bigint` ＋ `_cents` 結尾，不得用 `decimal`／`float`。** 這順便把鐵律 3 的「float 即 bug」從口號變成 migration 期的機械檢查。

### C.3 CI 靜態檢查（機器的編譯期，命中即 fail）

| # | 鍵（`money_boundary.ci_checks`） | 規則 | 為什麼是這一條 |
|---|---|---|---|
| C1 | `psp_dir_must_not_reference_cents` | `app/services/psp/**` 內出現識別字 `_cents` ⇒ fail（白名單：`Money::Storage` 的型別註記與 `#to_psp_amount` 的實作兩處） | PSP 目錄裡本來就不該有 storage 尺度的東西。這是 58 §K 15「transaction 內不得出現 adapter 呼叫」的同構做法 |
| C2 | `external_call_kwarg_must_be_minor` | 對 `Psp::*` 的呼叫，金額 kwarg 名必須以 `_minor` **或** `_psp_decimal` 結尾 ⇒ 否則 fail。<!-- 依 69 §V-188 擴充，原規則只允許 `_minor`：那會讓 Airwallex 型 adapter **無法在不違規的情況下被呼叫**，於是第一個實作它的人就會去改這條 CI 規則——**放寬一條擋不住新形態的規則，比一開始就寫對更難修回來** --> | 擋住「不經 adapter、直接組 HTTP body」的繞過 |
| C3 | `money_migration_must_be_bigint_cents` | 新增的金額欄位必須 `bigint` ＋ `_cents` 結尾；出現 `decimal`／`float` ⇒ fail | 鐵律 3 的 migration 期執法點 |
| C4 | `psp_dir_must_not_reference_money_decimal` | 🔴 `app/services/psp/**` 內出現 `Money::Decimal`（R4）或識別字 `_decimal`（不含 `_psp_decimal`）⇒ fail | 依 69 §V-188 新增。R4 與 R6 的 wire form 相同 ⇒ **在 PSP 目錄裡看到 R4，唯一的可能就是有人拿 feed／物流商的值來送款**（§A 末段第 3 點）。這條是 §A 那段論述的機械執法點 |

### C.4 為什麼註釋擋不住這個 bug（三個理由，都不是風格問題）

1. **註釋不進 CI。** 違反註釋的 PR 照樣綠燈合併。
2. **註釋不在事故現場。** 寫在 `money.rb` 的警告救不了三個月後在 `app/services/psp/airwallex/charge.rb` 新寫一行的人——他不會先去讀 `money.rb`。
3. **🔴 最致命的一條：這個 bug 在 exponent=2 幣別下測試全綠**（§0.2）。註釋唯一能起作用的時機是「有人心裡有疑問而去查」，但這個 bug **不會讓任何人產生疑問**——本地跑 HKD，一切正常。

> **不等 Sorbet／RBS。** 若日後導入，這四個值物件就是天然的 `sig` 邊界；但 L1–L4 在純 Ruby 下已經成立，不把防呆押在一個還沒發生的技術決策上。

---

## D. PSP 送出前的必跑檢查（X7）

### D.1 唯一出口

```ruby
# app/models/money.rb —— 送 PSP／任何外部收款系統前的唯一出口
#
# <!-- 依 69 號 §V-188 改寫（2026-08-12）。原方法名 `to_psp_minor(psp:)`，內文為單一分支
#      （只產出 Money::PspMinor）。🔴 **原設計的隱含前提是「所有 PSP 都收整數 minor unit」，
#      而 Airwallex 收的是十進位主單位字串**（`alt`）⇒ 原簽名在該類 PSP 上**沒有正確的用法**，
#      實作者只能繞過它（自己組字串），於是 §C 的四層防呆全部失效。
#      改法**不是**讓 `to_psp_minor` 回傳兩種型別（那會讓呼叫端不知道自己拿到什麼），
#      而是**上移一層**：`to_psp_amount` 依 pack 宣告的 `amount_format` 分流。
#      🔴 舊名 `to_psp_minor` **不保留為別名**——留著別名等於留著一條「不看 amount_format」的路徑。 -->
class Money::Storage
  # 儲存尺度（一律 ×100）與該 PSP 要的單位是兩件事，而**「單位」本身又有兩個維度**：
  #   顯示 → limits.currency_display.force_minor_unit_digits = 2   （裁定二）
  #   儲存 → limits.money_boundary.storage_scale_multiplier = 100  （不看幣別）
  #   對外 → ① 格式 amount_format（minor_units | decimal_string | decimal_number）② 該格式下的參數
  def to_psp_amount(psp:)
    pack = Psp.registry.fetch(psp)
    value = case pack.amount_format                            # A0：未宣告 ⇒ fetch 就 raise
            when :minor_units    then to_psp_minor(pack)
            when :decimal_string then to_psp_decimal(pack)
            when :decimal_number then to_psp_number(pack)      # 2026-08-31 新增（R7）
            end
    roundtrip_selfcheck!(value)                                # 非生產環境（D.2 末段）
    value
  end

  private

  def to_psp_minor(pack)                                       # X7a
    exponent = pack.minor_unit_exponent(currency)              # A1
    raise Money::PspMinorUnitUndeclared.new(psp: pack.code, currency:) if exponent.nil?
    raise Money::UnsupportedCurrencyExponent if exponent > LIMITS.money_boundary.max_supported_iso_exponent  # A2
    divisor = 10**(LIMITS.money_boundary.max_supported_iso_exponent - exponent)   # JPY⇒100、HKD⇒1
    raise Money::NonIntegralPspConversion unless (cents % divisor).zero?          # A3
    minor = cents / divisor
    check_divisibility!(pack, minor)                           # A5（基準＝送出值本身，見下）
    Money::PspMinor.__build(minor:, currency:, psp: pack.code) # A4（private 建構）
  end

  def to_psp_decimal(pack)                                     # X7b
    places = declared_places_with_guard!(pack)                 # A7（生效位數）＋ A6c（不得湊整）
    major = BigDecimal(cents).div(BigDecimal(100), 20)         # 🔴 全程 BigDecimal，禁 float
    check_divisibility!(pack, major)                           # A5（基準＝送出值本身，見下）
    str = format_fixed(major.to_s("F"), places)                # A6：定位數、**無幣別符號**、無千分位
    Money::PspDecimal.__build(string: str, currency:, psp: pack.code)      # A4
  end

  def to_psp_number(pack)                                      # X7c（2026-08-31）
    declared_places_with_guard!(pack)                          # A7＋A6c（同上）
    major = BigDecimal(cents).div(BigDecimal(100), 20)         # 🔴 全程 BigDecimal，禁 float
    check_divisibility!(pack, major)                           # A5
    Money::PspNumber.__build(number: major, currency:, psp: pack.code)     # A4
  end

  def declared_places_with_guard!(pack)
    places = pack.decimal_places_for(currency)                 # A7：overrides 優先於基準
    step = 100 / (10**places)                                  # 0 位⇒100、1 位⇒10、2 位⇒1
    raise Money::NonIntegralPspConversion unless (cents % step).zero?  # A6c：不得 round
    places
  end
end
```

🔴 **`check_divisibility!` 的基準一律是「即將送出去的那個值，用該 PSP 自己的單位」**——`minor_units` 就檢查 minor 整數，`decimal_string` 就檢查主單位的 `BigDecimal`（用 `BigDecimal#modulo`，**不得轉 float**）。
**為什麼不統一成「一律以 R1（cents）為基準」**：那樣 pack 作者就得把 PSP 文檔上的數字**自己換算一次**再填進 pack（例如某零小數幣別的「minor 須整除 100」要填成「cents 須整除 10000」）——**而那個換算就是本篇從頭到尾在防的那一類手工換算**。宣告值必須能與來源文件**逐字對照**，否則 pack 就成了下一個出錯的地方。

### D.2 送出前的必跑斷言

> **讀法**：「適用」欄標明該斷言在哪一種 `amount_format` 下跑。**A0／A4／A5 三種格式都跑**——它們約束的是「有沒有宣告」「是不是給這一家的」「金額本身合不合該家的規矩」，與格式無關。A6／A6b 作用於 decimal 兩格式的位數宣告；A6c／A7 作用於 decimal 兩格式的轉換。

| # | 斷言 | 適用 | 違反時 | 為什麼不能寬鬆 |
|---|---|---|---|---|
| **A0** | 🔴 該 pack **必須明文宣告 `amount_format`**（`minor_units` \| `decimal_string` \| `decimal_number`）；未宣告 ⇒ raise `PSP_AMOUNT_FORMAT_UNDECLARED`，**不得預設 `minor_units`** | 三者 | 拒絕送出，且該 pack 不得 enable | 依 69 §V-188 新增；2026-08-31 增第三值。**五家 PSP 三種形態**（Adyen／Datatrans／Stripe＝整數 minor units、PayPal＝十進位主單位字串、Airwallex＝十進位主單位 JSON number）⇒ 「大家都用 minor unit」是**經驗證為假**的假設。預設 `minor_units` ＝ 對主單位型 PSP 送出**主單位被當 minor unit 解讀**的金額，**且該錯誤在所有幣別上都成立**（不像 A1 只在 zero-decimal 幣別現形） |
| **A1** | 該幣別的 minor unit **必須由該 PSP pack 明文宣告**；`nil` ⇒ raise `PSP_MINOR_UNIT_UNDECLARED` | `minor_units` | 拒絕送出 | **未宣告 ≠ 預設 ISO**（比照 56 §A.3、58 §A.3）。🔴 **本條原本標「業界存在特例（V-130 未取得出處）」，69 號把它證實了**：Adyen 官方文檔**明文**說 CLP／CVE／IDR／ISK 的小數位與 ISO 4217 不同、以自家表為準；Stripe 的 `Special cases` 表覆蓋 ISK／HUF／TWD／UGX（`alt` ×2）。⇒ **「拿 ISO 4217 exponent 當 PSP 換算基數」是已知會錯的實作**，不是保守假設 |
| **A2** | `exponent ≤ money_boundary.max_supported_iso_exponent`（＝2） | `minor_units` | 拒絕送出 | exponent=3（KWD/BHD/JOD）的最小單位，×100 的儲存尺度**表達不了**（`divisor` 會是 0.1）。<!-- 依 68 §D-3：market 建立期的閘門已移除（幣別可選），本條成為**唯一**執法點，比改動前更重要 -->⇒ 63 §G.4、⚠ V-94。Adyen／Datatrans 兩家都宣告這五個幣別為 exponent 3（`alt`）⇒ **這不是假想情境**，是接上任一家就會立刻遇到的 |
| **A3** | `cents % divisor == 0`；**餘數不為 0 ⇒ raise，不四捨五入** | `minor_units` | 拒絕送出 | JPY 的 `148050`（¥1,480.50）在 ISO 下不可表達 ⇒ **是上游算錯了**（湊整規則沒套用，29 §3.3）。悄悄抹掉 50 會讓對帳永遠差幾分錢卻查不出來——同 58 §G.3 規則 2 的理由 |
| **A4** | 回傳型別必為該 pack 的 `amount_value_class`（`Money::PspMinor`／`Money::PspDecimal`／`Money::PspNumber`），且送出前再驗 `psp` 相符 | 三者 | `TypeError` | 擋住「A 家的值送去 B 家」與「R4 混進來」（§C.1 L3、§A 末段第 3 點） |
| **A5** | 🔴 **`divisibility_constraint`**：pack 若宣告某幣別的金額必須為 N 的倍數，違反 ⇒ raise `PSP_DIVISIBILITY_VIOLATION`，**不得四捨五入湊整**。**基準＝即將送出的值，用該 PSP 自己的單位**（`minor_units` 檢查 minor 整數；decimal 兩格式以 `BigDecimal` 檢查主單位，禁 float） | 三者 | 拒絕送出 | 依 69 §V-188 新增。**這不是虛構需求**：Stripe 官方文檔明文要求 **HUF／TWD 的 payout 金額必須整除 100**（`alt`）。而 **TWD 正好在 §H.1 的測試矩陣裡**。🔴 **自動湊整是最壞的處置**——它會讓「送出去的錢」與「帳上記的錢」不同，而差額沒有任何一張表記得住（同 A3 的理由）。⚠ 該約束在 charge 與 payout 上是否同時成立 ⇒ **V-206** |
| **A6** | decimal 兩格式：`decimal_string` 的輸出字串必須匹配**生效位數**的正則、**無幣別符號**、無千分位、小數點為 `.`（0 位＝無小數點）；**pack 基準位數 > 2 ⇒ 該 pack 不得 enable**（per-currency 覆蓋 > 2 同樣載入即拒，見 A7） | decimal 兩格式 | 拒絕送出／pack 不得 enable | 我方儲存尺度 ×100 只能無損表達 2 位。宣告 3 位卻只能給到 2 位＝**靜默的精度謊報**（我方送 `"2.90"`，PSP 以為那是 `2.900`）。**這與 A2 是同一條規則在另一種格式下的形態**，不是新規則 |

| **A6b** | decimal 兩格式：**pack 基準位數 < 2 ⇒ 該 pack 不得 enable**（鍵：`money_boundary.psp_decimal_min_places`）。🔴 **per-currency 覆蓋（A7）可為 0／1，不受本條約束**——覆蓋幣別的湊整風險由 A6c 在轉換層 raise 擋住（見 A6c 欄） | decimal 兩格式（基準位數） | pack 不得 enable | 🔴 **2026-08-15 新增（PR #29 驗收指出的缺口）**。A6 原本只有上限 ⇒ 宣告 `0` 或 `1` **完全合法**，而 `to_psp_decimal` 走 `Money.fixed_string(major, decimal_places)`，內部 `value.round(digits)` **靜默四捨五入**：`decimal_places: 1` ＋ HKD 14.85（儲存 `1485`）**送出 `"14.9"`** ＝帳上 14.85、送款 14.90，**差額 0.05 沒有任何一張表記得住**——正是 A5 逐字說的「自動湊整是最壞的處置」。<!-- 原文此處記「decimal_string 側沒有 A3 等價物」的不對稱——A6c（2026-08-31）就是那個等價物，該句已由 A6c 收口；本條對基準位數維持 D16 裁定不放寬。 --> ⚠️ 且它**在 HKD 這個基準法域上就會發生**，不像 A1／A2 只在 zero-decimal 幣別現形 ⇒ §H 矩陣（全部宣告 2 位）**證明不了它**。裁定見 §D.5 |
| **A6c** | 🔴 decimal 兩格式的 **A3 等價物**（2026-08-31 新增）：儲存 cents 無法無損表達為該幣別**生效位數** ⇒ raise `NonIntegralConversion`，**不得 round**。判準＝`cents % (100 / 10**places) == 0` | decimal 兩格式 | 拒絕送出 | JPY 儲存 `148050`（¥1,480.50）對 0 位幣別送 `"1481"`／`1481` ＝送款與帳上差 0.50 而沒有任何一張表記得住（A5 同理由）。**沒有本條，A7 的 per-currency 覆蓋就是把 A6b 描述的湊整事故重新打開**——本條與 A7 必須同時存在，缺一即回退 |
| **A7** | 🔴 decimal 兩格式的**生效位數解析**（2026-08-31 新增）：`decimal_places_overrides[currency]` 覆蓋優先於基準 `decimal_places`；**覆蓋表是必填鍵**（空表＝已查證無例外 ≠ 缺鍵）；覆蓋值域 0..2，**> 2 載入即拒**（等到轉換層會變成 `% 0` 的 ZeroDivision——錯誤要可讀且早爆，同 A2 的理由） | decimal 兩格式 | pack 不得 enable | **兩家實證都覆蓋自己引用的底表**（取證 2026-08-31）：PayPal 官方逐字 "This currency does not support decimals. If you pass a decimal amount, an error occurs."（HUF／JPY／TWD——🔴 **HUF 在 ISO 4217 是 2 位**）；Airwallex payments 側零小數 20 幣（🔴 HUF／TWD／IDR 皆與 ISO 不同）。⇒ 這是 minor_units 側「Adyen 覆蓋 ISO」教訓在 decimal 側的重演，**ISO 又一次只是底表、不是換算基數** |

**額外一條（非生產環境每次轉換都跑）**：往返自檢 `from_psp_amount(to_psp_amount(x)) == x`（三種格式各跑一次；已落地為 `to_psp_amount` 內的 `roundtrip_selfcheck!`）。在 A3／A6／A6c 成立時它恆真——**它擋的不是今天的 bug，是日後有人改了 divisor 公式或字串格式化**。鍵：`money_boundary.roundtrip_selfcheck_envs`。

#### D.5 為什麼是「拒絕 sub-2 位」而不是「支援 sub-2 位」（2026-08-15 裁定）

發現 A6b 的缺口時有兩條修法，**選了拒絕**：

| 修法 | 內容 | 為什麼沒選／選了 |
|---|---|---|
| **(a) fail-closed** ✅ **採用** | `validate_decimal_string!` 一併 reject `decimal_places < 2` | 我方至今**沒有任何一家真的用 sub-2 位的 PSP**（本節 §D.4 四家實證表：Airwallex 是 2 位）。fail-closed 的代價是「真出現時第一次呼叫就 raise」——**看得見**的失敗 |
| (b) 補齊語義 | `to_psp_decimal` 加 A3 等價的位數餘數檢查 ＋ §H 補 0／1 位案例 | 要「支援」就得先發明湊整規則：**誰決定進位方向？差額記到哪張表？** 本規格全篇沒有出處可依 ⇒ 那是憑空造規則，而且造出來的規則第一次接真 PSP 時很可能就是錯的 |

🔴 **sub-2 位的語義刻意留白，等第一家真的這樣要求的 PSP 出現時再裁定。**
到那時要改的是**這一節 ＋ `psp_decimal_min_places`**，不是繞過閘門。

> 🔴 **2026-08-31 追記：那一家出現了——而且是兩家、在 per-currency 層。**
> PayPal 對 HUF/JPY/TWD、Airwallex（payments）對零小數 20 幣都要求 **0 位小數**（一手逐字見 A7）。
> 落法照本節預告的形：**基準位數維持 2（`psp_decimal_min_places` 不動、D16 不放寬）**，
> per-currency 覆蓋由 **A7** 宣告、湊整風險由 **A6c 的餘數 raise**（＝當年 (b) 修法描述的
> 「A3 等價的位數餘數檢查」）擋住——不發明湊整規則，無法無損表達一律 raise。
> §H 也照 (b) 的預告補了 0 位案例（T21／T23）。

⚠️ **配套（已落地）**：`Money.fixed_string` 在 `digits = 0` 時原本輸出 `"1480.0"`
（`"0".rjust(0, "0")` 回 `"0"`，而小數點是無條件接上的）——**連它自己「定位數」的契約都不符**。
該 bug 已獨立修掉並加測試。🔴 **分層刻意如此**：格式化器管「怎麼 render」（對任意 `digits` 都要正確），
政策層（A6／A6b）管「准不准 render」；把政策塞進格式化器會讓 `Money::Decimal`
（恆 2 位、與 PSP 無關）也被 PSP 規則綁住。

### D.3 PSP pack 的宣告形態（比照 58 的 carrier pack）

```
psp_packs:
  <psp_code>:
    amount_format: minor_units | decimal_string | decimal_number
                                        # 🔴 必填（A0）；沒有這一行 ⇒ 該 pack 不得 enable
    # --- amount_format: minor_units 時 -----------------------------------------
    minor_unit_source: iso4217          # 必填；「以 ISO 為底」也必須明講，不得靠預設
    minor_unit_overrides: { }           # 幣別 → exponent 的例外表；空表代表「無例外」（≠ 未宣告）
    # --- amount_format: decimal_string | decimal_number 時 ----------------------
    decimal_places: 2                   # 必填（基準位數）；> 2 ⇒ 不得 enable（A6）、< 2 ⇒ 不得 enable（A6b）
    decimal_places_overrides: { }       # 必填（A7，2026-08-31）：幣別 → 生效位數的覆蓋表；
                                        # 空表＝「已查證無例外」；值域 0..2，> 2 載入即拒
    # --- 三種格式都必填 ---------------------------------------------------------
    divisibility: { }                   # 幣別 → 倍數（例：某家要求某幣別金額整除 100）。
                                        # 空表＝「已查證、無此約束」；缺鍵＝「沒人查過」⇒ 不得 enable
    divisibility_scope: [ ]             # 該約束作用在哪些操作（charge／refund／payout）⚠ V-206
    storage_precision_shortfall: reject # 幣別的 PSP 最小單位比我方儲存尺度細時怎麼辦
                                        # （目前唯一合法值＝reject；見 A2／A6 與 catalog_flow.exponent3_*）
    enable_gate: [ ]                    # 未結案的 V 編號填這裡；非空 ⇒ enabled 必為 false
```

🔴 **空表 ≠ 缺鍵，這條在本節出現四次**（`minor_unit_overrides`／`decimal_places_overrides`／`divisibility`／`enable_gate`）：明文空表是「已查證、無例外」，沒有這個鍵是「沒人查過」。這個區分在 58 §A.3 已經吃過一次虧，此處沿用。
<!-- `amount_format`／`decimal_places`／`divisibility`／`divisibility_scope`／`storage_precision_shortfall`
     五個鍵依 69 號 §V-188 新增（2026-08-12）。原宣告形態只有 minor_unit_source／minor_unit_overrides／
     enable_gate 三鍵，🔴 **其中沒有任何一個鍵能表達「這家不用 minor unit」**——也就是說
     Airwallex 型 PSP 在原形態下**無法被合法宣告**，第一個接它的人只能改宣告形態或繞過它。
     🔴 任何人不得以「Airwallex 一家而已」為由把 amount_format 收回去：69 號查到的是
     **四家四種算法**，這個維度是外部世界的性質，不是我方的抽象偏好。 -->

### D.4 五家 PSP 的實證表（69 號查證＋2026-08-31 複驗輪，`alt` 級＝PSP 官方文檔）

> 🔴 **本表是「外部世界長什麼樣」的紀錄，不是我方的預設值。** 任何 pack 的實際值一律以該 pack 自己的宣告為準（A0／A1）；本表的用途是**證明 A0／A1／A5／A7 四條斷言不是過度設計**，以及讓下一個人知道接哪一家會遇到什麼。
> 鐵律 9：本表只記**數值行為**，不引用任何一家的條文文字、程式碼或文案（A7 的英文逐字引句屬取證紀錄，鐵律 16.2）。

| PSP | `amount_format` | 三位小數幣別（KWD/BHD/JOD/OMR/TND） | 是否自認可覆蓋 ISO 4217 | 對我方的意義 |
|---|---|---|---|---|
| **Adyen** | `minor_units` | exponent **3** | 🔴 **是**——官方明文列出 CLP／CVE／IDR／ISK 與 ISO 4217 不同，以自家表為準 | A1「未宣告 ≠ 預設 ISO」的**直接證據** |
| **Datatrans** | `minor_units` | exponent **3**（×1000） | 自稱**遵循** ISO | 「遵循」也必須寫進 pack（A1）——兩家都自稱遵循時，只有明文宣告能讓差異在 diff 裡看得見 |
| **Stripe** | `minor_units` | 現行文檔幣別清單為動態渲染，⚠ **V-204** 未取得 | 🔴 **實質是**——`Special cases` 表涵蓋 **ISK／HUF／TWD／UGX**；**HUF／TWD 的 payout 須整除 100** | 🔴 **A5 的直接證據，且命中 §H.1 矩陣裡的 TWD** |
| **Airwallex** | 🔴 **`decimal_number`**（payments／pa API） | payments 側**無 3 位檔**（只有 2／0 兩檔；⚠ payouts 產品線另有 3 位表——**射程不同，不得混用**） | 引用 ISO 定義主單位、🔴 **但 payments 零小數表覆蓋 ISO**（HUF/TWD/IDR 皆列 0 位） | 🔴 **R7 存在的理由**；per-currency 位數＝A7 的直接證據之一 |
| **PayPal** | 🔴 **`decimal_string`**（Orders v2 `amount.value`＝string） | 無（支援清單 25 幣不含）；HUF/JPY/TWD＝**0 位、帶小數即 error** | 🔴 **覆蓋**（HUF 在 ISO 是 2 位） | 🔴 **R6 的現任實證代表**；A7 的直接證據之二 |

<!-- 🔴 2026-08-31 更正（19.5）：Airwallex 列原記 `decimal_string`＋「per-currency 位數未給 ⇒ V-132」。
     一手複驗（airwallex.com/docs/api/data_types＋payments-and-fee-rounding，取證 2026-08-31）：
     ①wire form 是 JSON **number**（"$9.99 is represented as 9.99"、create schema `amount: number`）
       ——69 號當時據 platforms 文檔的字串範例推斷為字串，該範例屬後端強制轉型容忍、非契約；
     ②per-currency 位數已取得（payments 側零小數 20 幣逐字清單）⇒ **V-132 三項缺口全數結案**（§L）。
     原「R6 與 A0 存在的唯一理由」句隨之失效——R6 的存在理由由 PayPal 承接，A0 的理由不變（仍是
     「格式必須逐家宣告」）。 -->

**這張表要記住的一句話**：**五家三種格式、每一家的小數位都是自家的表**（連「引用 ISO」的兩家都各自覆蓋了 ISO）。「業界有共識、跟著 ISO 走就對了」這個假設在本專案已經被外部證據正面否定——**鐵律 3 的「逐家宣告」不是保守，是唯一正確的做法。**

---

## E. 反方向：從 PSP 進來的金額（X8）

**入向的錯不是 100 倍，是 1/100，而且更難發現**——訂單金額看起來「只是小一點」，不會觸發任何金額上限告警。

```
amount_format: minor_units     ⇒ storage_cents = psp_minor * 10 ** (max_supported_iso_exponent - exponent)
amount_format: decimal_string  ⇒ storage_cents = BigDecimal(psp_decimal) * 100   （小數 > 生效位數 ⇒ raise；
                                                                                   無小數點＝0 位，PayPal JPY 合法形）
amount_format: decimal_number  ⇒ storage_cents = psp_number * 100                （同上；🔴 解析必須
                                                                                   decimal_class: BigDecimal，Float 即 TypeError）
```

<!-- 第二行依 69 號 §V-188 新增（2026-08-12）。原文只有 minor_units 一行 ⇒ Airwallex 型 PSP 的
     webhook 金額**在原契約下沒有合法的入向路徑**。🔴 注意兩者的錯誤形態不同：
     minor_units 入向錯 ＝ 少記 99%（只在 zero-decimal 幣別）；
     decimal_string 入向錯（把 "14.80" 當 cents 直接落庫）＝ **少記 99%，且在所有幣別上都成立**。 -->

### E.1 三條硬規則

1. **PSP 回應／webhook 的金額欄位一律先包成該 pack 的 `amount_value_class`（`Money::PspMinor`／`Money::PspDecimal`／`Money::PspNumber`）再轉 R1（唯一入口 `Money.from_psp_amount`）**，不得直接 `update(amount_cents: event.amount)`。🔴 **包不出來就不准進**——webhook 收到的形態與 pack 宣告的 `amount_format` 不符（例如宣告 `decimal_string` 卻收到整數），代表**要嘛 pack 宣告錯了、要嘛對方改了 API**，兩者都必須進死信人工看，不得就地猜一個轉換。
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
| **TWD** | ⚠ 見下 | **本矩陣最危險的一格**（§H.3）。🔴 **自 69 §V-188 起再多一條**：Stripe 對 TWD 有**整除 100** 的要求（`alt`）⇒ TWD 同時是 A1（單位未宣告）與 **A5（整除約束）** 的測試載體 |
| **KRW** | 0 | 第二個 zero-decimal，防止「只對 JPY 特判」的錯誤實作 |
| HKD | 2 | 基準法域；回歸案例——確保修正沒把 `divisor = 1` 的路徑弄壞 |
| USD | 2 | 第二個 exponent=2 |
| KWD | 3 | 斷言**被擋下**（A2），不是斷言算對 |

**另外兩個維度也必須進矩陣**（依 69 §V-188 新增；它們不是幣別，是 pack 形態）：

| 維度 | 必測形態 | 為什麼 |
|---|---|---|
| **`amount_format`** | `minor_units`／`decimal_string`／`decimal_number` **各**至少一個 fixture pack（2026-08-31 增第三格式）；另各至少一個 **per-currency 零位覆蓋** pack（A7／A6c 的載體） | 🔴 **只測 `minor_units` 的矩陣，在主單位型 PSP 上等於零覆蓋**——而那條路徑的錯誤**在 HKD 上也會錯**（§C.1 末段），是本專案目前唯一「基準法域測得到、但沒人在測」的金額事故形態 |
| **`divisibility`** | 至少一個宣告了整除約束的 fixture pack（以 TWD／100 為原型） | A5 若沒有測試，它與註釋無異（§C.4）。**且這條約束的真實來源是 Stripe 的 payout**，不是假想 ⇒ 一旦做 payout／對帳就會生效 |

🔴 **CI 規則**：金額路徑的測試檔若一個 zero-decimal 幣別都沒有 ⇒ 視為未涵蓋，**CI fail**（`money_boundary.test_matrix_missing_zero_decimal_action: ci_fail`）。**同一條規則套用到 `amount_format`**：`test_matrix_amount_formats_required` 列舉的每一種格式（現＝三種）缺任一 fixture pack ⇒ CI fail。這兩條是本節唯二的機械化保證——其餘都是清單，清單會被忘記。

### H.2 必測案例（每一條都是一個具體斷言）

| # | 幣別 | 輸入 | 期望 | 擋住什麼 |
|---|---|---|---|---|
| T1 | JPY | 儲存 `148000` | 顯示 `¥1,480.00` | 裁定二 |
| T2 | JPY | 儲存 `148000` | `Offer.price == "1480.00"` | 62 §A.4 |
| T3 | **JPY** | 儲存 `148000` → `to_psp_amount`（`minor_units` pack） | **`1480`** | 🔴 **100 倍** |
| T4 | **JPY** | webhook `amount: 1480` → `to_storage` | **`148000`** | 🔴 **1/100** |
| T5 | **JPY** | PI `amount 1480` vs checkout `148000` 的比對 | **判定為相符** | 🔴 每張 JPY 訂單被自動退款（§E.1-2） |
| T6 | JPY | 儲存 `148050`（¥1,480.50） | **raise `NonIntegralPspConversion`** | 悄悄抹掉 50 分 |
| T7 | KRW | 儲存 `1200000`（₩12,000） | psp minor `12000` | 只對 JPY 特判的實作 |
| T8 | **TWD** | 任意值 → `to_psp_amount(psp:)` | **pack 未宣告 ⇒ raise `PSP_MINOR_UNIT_UNDECLARED`**（不是斷言某個 exponent） | §H.3、V-130 |
| T9 | HKD | 儲存 `148000` | psp minor `148000`（`divisor = 1`） | 修正把 exponent=2 弄壞 |
| T10 | USD | 邊界值 `0` / `1` / `BIGINT max` | 往返一致 | 溢位與零值 |
| T11 | KWD | market 建立 | <!-- 依 68 §D-3：market 建立已不再回 INCLUSION（幣別可選），斷言改為「可建立 ＋ 送款被擋」 -->market **可建立**（`exponent3_currency_selectable`）、以 2 位小數儲存顯示、精度損失被登記；且 `to_psp_amount` **raise**（A2） | exponent=3 漏網 |
| T12 | 全部 | `from_psp_amount(to_psp_amount(x)) == x`（三種 `amount_format` 各跑） | 恆真 | 日後有人改 divisor 公式或字串格式化 |
| T13 | JPY | CSV 匯出 → 再匯入 | 儲存值不變（`148000`） | §G 的來回失真 |
| T14 | 任一 | 對 PSP adapter 傳裸 `Integer` | `TypeError` | §C L3 |
| **T15** | **JPY** | 儲存 `148000` → `to_psp_amount`（**`decimal_string`** pack） | **`"1480.00"`**（字串，兩位，無幣別符號、無千分位） | 🔴 依 69 §V-188 新增。**主單位字串型的主案例**——`"148000.00"` 就是收款 100 倍，而**這一條在 HKD 上也會錯**，所以它是矩陣裡唯一不需要 zero-decimal 幣別就能抓到的送款事故 |
| **T20** | JPY | 儲存 `148000` → `to_psp_amount`（**`decimal_number`** pack） | `Money::PspNumber`，數值 `1480` | 🔴 2026-08-31 新增（R7）。T15 的 number 版——`148000` 就是收款 100 倍，HKD 也會錯 |
| **T21** | JPY | `decimal_places_overrides: {JPY: 0}` 的 pack：出向 `"1480"`（無小數點）；入向 `"1480"` 合法 | 出向無小數點；入向 `148000` cents | 🔴 A7。PayPal 官方逐字「帶小數即 error」——出 `"1480.00"` 就是被拒付的形；入向殺「`split('.')` 對無點字串誤數 4 位」 |
| **T22** | HKD | 入向 `BigDecimal("16.66")`（`decimal_number` pack）→ `from_psp_amount` | `1666` cents | X8c：不包型別直接落庫＝少記 99% |
| **T23** | JPY | 儲存 `148050` → 0 位覆蓋 pack（兩種 decimal 格式各跑） | **raise `NonIntegralConversion`** | 🔴 A6c。湊成 `1481` ＝送款與帳上差 0.50 而沒有表記得住；只測「有 raise」不夠，訊息須含不得四捨五入 |
| **T24** | 任一 | `from_psp_amount(16.66, …)`（Float）（`decimal_number` pack） | **`TypeError`** | 🔴 X8c：`JSON.parse` 預設吐 Float——約定「decimal_class: BigDecimal」必須是機械限制，不是註釋 |
| **T16** | **TWD** | 宣告 `divisibility: {TWD: 100}` 的 fixture pack；金額 `148050` | **raise `PSP_DIVISIBILITY_VIOLATION`**，且**不得**回傳被湊整後的值 | 🔴 A5。Stripe 對 TWD／HUF payout 的整除要求（`alt`）。**斷言要同時檢查「有 raise」與「沒有靜默湊整」**——只測前者的話，一個「先湊整再 raise」的實作也會綠 |
| **T17** | 任一 | 把 `Money::Decimal`（R4，物流商／JSON-LD 用的那個）傳進任何 PSP adapter | **`TypeError`** | 🔴 §A 末段第 3 點。R4 與 R6 的字串內容可能一模一樣 ⇒ **這條是唯一能證明「型別而非字串」真的在守門的測試** |
| **T18** | 任一 | 把 `Money::PspMinor(psp: :stripe)` 傳進 `decimal_string` 型 adapter（反之亦然） | **`TypeError`** | A4 的格式維度：擋住「格式對了但家別錯了」與「家別對了但格式錯了」兩種交叉誤用 |
| **T19** | 任一 | pack **未宣告** `amount_format` | `to_psp_amount` **raise `PSP_AMOUNT_FORMAT_UNDECLARED`**，且該 pack **不得 enable** | 🔴 A0。**不得預設 `minor_units`**——這條測的是「沉默時系統拒絕，而不是猜」 |

### H.3 🔴 TWD 是這張表最危險的一格（必讀）

`limits.currency_display.iso4217_zero_decimal_overridden: [JPY, TWD]` 把 TWD 與 JPY 並列，而 `jurisdictions.tw.currency_format.exponent` 已被裁定二從 `0` 改成 `2`（＝顯示位數）。於是同一個幣別在 limits 裡有**兩個看起來都像 exponent 的數字，而且都不是 PSP 該用的那個**。

- **ISO 4217 對 TWD 的 minor unit，本專案至今沒有任何一手出處。**
- 🔴 **「部分 PSP 對 TWD 另有『金額須為 100 的倍數』的特例規則」——這句話原本是傳聞，69 號把它證實了。**
  <!-- 依 69 號 §V-188 修正（2026-08-12），原文：「業界普遍以 2 位處理，且部分 PSP 對 TWD 另有
       「金額須為 100 的倍數」的特例規則——⚠ **V-130**，未取得官方明文。」
       🔴 **這不是措辭升級，是需求性質的改變**：原文把它寫成「傳聞中的特例」⇒ A5 讀起來像防禦性設計；
       現在它是 **Stripe 官方文檔明文的 payout 條件**（`alt`）⇒ **A5 是必須實作與測試的功能**，
       不是「以防萬一」。任何人不得把 A5 降級成選配。 -->
  Stripe 的 `Special cases` 表把 **ISK／HUF／TWD／UGX** 訂成與 ISO 4217 不同的處理方式，並明文要求 **HUF／TWD 的 payout 金額整除 100**（`alt`，69 §V-188）。⇒ **TWD 在本矩陣裡同時承載兩條斷言**：A1（單位必須宣告）與 **A5（整除約束必須實作，見 T16）**。
  ⚠ 該整除約束在 **charge** 上是否同樣成立（69 號讀到的是「付款時可兩位小數、payout 時須整除 100」）⇒ **V-206**。**在 V-206 結案前，pack 的 `divisibility_scope` 缺鍵 ⇒ 不得 enable**（§D.3）。
- **結案前的處置**：TWD **一律走 A0／A1 的 pack 宣告路徑**。pack 沒宣告 ⇒ `reject`。
  **不得**從 `iso4217_zero_decimal_overridden` 或 `currency_format.exponent` 任何一個推導 TWD 的 PSP 單位。
- 因此 T8 斷言的是**「未宣告時正確地拒絕」**，而不是某個具體 exponent 值——**這正是 §D.2 A1「未宣告 ≠ 預設」設計的價值所在**：在事實不明的幣別上，系統的行為是「拒絕送出」而不是「猜一個數送出去」。
- 🔴 **69 號在這一格上給出的最終判斷**：Adyen 明文覆蓋 ISO、Stripe 實質覆蓋 ISO ⇒ **「以 ISO 4217 exponent 當 PSP 換算基數」是已知會在真實 PSP 上算錯的實作**。A1 因此不再是「保守失效」，而是**唯一正確的做法**；`money_boundary.psp_minor_unit_source_default: iso4217` 這個鍵的語義是「pack 若宣告以 ISO 為底時的底表來源」，**不是**「沒宣告時的預設值」。

---

## I. `config/limits.yml` 新增的鍵（已落檔）

**本篇不硬編任何數字**（鐵律 6）。新增區塊 `money_boundary:`（位於 `currency_display:` 之後）：

| 鍵群 | 用在本篇哪一節 |
|---|---|
| `storage_scale_multiplier` / `storage_scale_ignores_currency` / `storage_column_suffix` / `storage_column_sql_type` / `storage_column_decimal_or_float_forbidden` | §A R1、§C.2 |
| `decimal_string_digits` / `decimal_string_regex` / `decimal_string_divisor` / `decimal_parse_*` | §A R4、§B X2/X4/X6、§G |
| `psp_minor_unit_source_default` / `psp_minor_unit_must_be_declared_by_pack` / `psp_undeclared_currency_action` / `psp_undeclared_error_code` / `max_supported_iso_exponent` / `psp_non_integral_conversion_action` / `psp_rounding_forbidden` | §D.2 A1–A3 |
| 🔴 `psp_amount_formats` / `psp_amount_format_must_be_declared_by_pack` / `psp_amount_format_undeclared_error_code` / `psp_amount_format_default_forbidden` / `psp_decimal_max_places` / `psp_divisibility_must_be_declared_by_pack` / `psp_divisibility_violation_action` / `psp_divisibility_error_code` / `psp_divisibility_rounding_forbidden` / `psp_pack_required_keys` | §D.2 **A0／A5／A6**、§D.3（依 69 §V-188 新增） |
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
| ~~**M-9**~~ ✅ **已結案**（2026-08-13，使用者授權全範圍；實改清單見 §J.2）<br>原 🔴（依 69 §V-188 新增，2026-08-12） | **15 號的落地文字用的是舊方法名與單一型別** | **15 §F4-5／§F4-6／§F5-2** 是 M-1 結案時依本篇 §D 改寫的，逐字寫著 `Money::Storage#to_psp_minor(psp:)` 與「adapter 簽名只收 `Money::PspMinor`」——**那在當時是對的**（本篇當時只有 R5） | 本篇 §D.1 的唯一出口已改名 `to_psp_amount(psp:)` 並依 `amount_format` 分流；adapter 收的是**該 pack 宣告格式對應的值物件**。⇒ 15 的三處需同步改名 ＋ 補 R6 分支。<br>⚠ **危害等級低但不可不改**：照 15 現行文字實作，Airwallex 型 PSP **沒有合法的呼叫方式**，實作者只能自己組字串 ⇒ **繞過整個 §C 防呆**。<br>🔴 **不做別名**（§D.1 註釋已明寫）：留 `to_psp_minor` 當別名等於留一條不看 `amount_format` 的路徑 | **15 §F4／§F5**（本輪不得改 15；比照 M-1 的處置，需要一次授權範圍的裁定，見 open-decisions A-1 的形態） |
| ~~**M-8**~~ ✅ **已結案**（2026-08-13，使用者授權全範圍；實改清單見 §J.2）<br>原 🔴（依 69 §V-188 新增，2026-08-12） | **「對外一律依 ISO 4217 exponent 換算」這句話現在是不完整的** | **63 §G.4** 的硬規則逐字寫「送 PSP／物流商／任何外部系統的金額一律依 ISO 4217 exponent 換算」，並落成 `limits.currency_display.psp_minor_unit_follows_iso4217: true`（63 §G.4／§9 鍵表）。**63 §G.4 的方向完全正確**（它是本篇的來源之一），但它成文時的世界觀是「PSP＝整數 minor unit，只是 exponent 各異」 | 69 號查到的四家 PSP 是**四種算法**：Adyen 明文覆蓋 ISO、Stripe 實質覆蓋 ISO ＋ 對 HUF／TWD 有整除約束、**Airwallex 根本不用 minor unit**（`alt` ×4）。⇒ 該句應改為「**依該 PSP pack 明文宣告的 `amount_format` 與其參數換算；ISO 4217 只是 `minor_units` 格式下 pack 可以選擇的底表之一**」。<br>🔴 **這不是放寬**：63 §G.4 要擋的 100 倍事故一個字都沒鬆，本條只是指出它擋的形態比原本以為的多一種 | **63 §G.4 與 §9 鍵表**（本輪不得改 63）。`limits.yml` 側已在 `currency_display.psp_minor_unit_follows_iso4217` 加追溯註釋指向本條；**鍵值未動**，以免出現「規格說 A、鍵說 B」的分裂 |

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

**已知仍在其他檔案的同根因文字**（原登記為 M-7；✅ **已於 2026-08-13 隨 M-8/M-9 同輪結案**，見 §J.2）：

| # | 位置 | 現況 | 該怎麼改 |
|---|---|---|---|
| **M-7** | `52 §1 P0-01`（退款公式列的「公式」欄，逐字「零小數幣別只在序列化層處理」）；`57` 檔頭「金額鐵律」引言（逐字「零小數幣別只在序列化層」） | 兩處都只是**轉述** 16-F5.1 的三個捨入點，**沒有**重複 15 §F4-5 那句「不乘 100」⇒ **危害等級遠低於 M-1**，但仍指向一個已改寫的定義 | 兩處各改一個交叉引用指向 65 §D，並比照 #6 澄清「③不是捨入點」。**不阻塞**——照這兩處實作不會產生 100 倍，只會多跳轉一次。⚠️ 兩檔皆不在 2026-08-12 A-1 的授權範圍內 |

### J.2 M-7／M-8／M-9 的結案紀錄（2026-08-13，使用者授權「全 8 檔 16 處」）

**授權形態**：比照 A-1（M-1 的先例）——使用者在四選項問答中選「批准全 8 檔約 16 處」，**明確否決**「只批登記的 3 檔 5 處」選項。範圍＝`docs/specs/15`／`16`／`52`／`55`／`57`／`58`／`62`／`63` ＋ `config/limits.yml` ＋ 本檔 §J。

**實際改動 17 處**（登記 5 處 ＋ grep 補出 12 處；每處都留追溯註釋，既有 M-1/M-2 註釋保留、新註釋疊加）：

| # | 位置 | 形態 | 改了什麼 |
|---|---|---|---|
| 1 | 15 §F4-5 | M-9 本體 | 唯一出口改 `to_psp_amount(psp:)`＋`amount_format` 分流；斷言四條改引 §D.2 A0–A6（標明各斷言適用格式）；Stripe 具體值保留並明標「Stripe pack＝minor_units」 |
| 2 | 15 §F4-6 | M-9 本體 | 退款 `amount:` 改 `to_psp_amount` 產物 |
| 3 | 15 §F5-2 | M-9 本體 | 入向改 §E.1-1 逐字語義（先包成該 pack 的 amount_value_class 再 `to_storage`）——F5 是通用流程，原文寫死 `PspMinor` 會讓 decimal_string PSP 的 webhook 金額沒有合法入向 |
| 4 | 15 §F2.1 | 🔴 **連續兩輪被登記表漏掉**（M-1 靠 grep 補、M-9 又漏） | 改名＋表示法一般化 |
| 5–6 | 15 §F4 ⚠️坑2、§F5 ⚠️坑末條 | 單一格式假設 | 「PI 是 R5」加註 Stripe 限定／一般化為「R5 或 R6」 |
| 7 | **16 §F5.1 ③** | 🔴 **二度過時且無任何登記列涵蓋**（M-2 用當時正確的 `to_psp_minor` 改寫、同日 V-188 又改名） | 改 `to_psp_amount`＋A3/A6 分支澄清 |
| 8 | **55 §A.0 ③** | 同 #7 | 同 #7 |
| 9 | 52 §1 P0-01 公式欄 | M-7 本體 | 交叉引用改指 §D＋「不是捨入點」澄清；🔴 **未照抄 16/55 的 M-2 版文字**（它們自己就是 #7/#8） |
| 10 | 57 檔頭金額鐵律 | M-7 本體 | 同 #9 |
| 11 | 58 §0.4 金額邊界警語 | R4≠R6 陷阱 | 「PSP 的整數 minor unit」改為「PSP 的任何一種格式」＋補「R6 與物流商字串長得一模一樣，判別依據是去向不是字面」 |
| 12–13 | 62 §L.5 收款列＋「唯一執法點」句 | minor-units-only 世界觀 | 補 A0/A6 維度；「A2 唯一執法點」改為「minor_units 分支唯一」；順帶把 62 §L.5 的三項待修清單核實結案（63 已修；65 T11／55 經 grep 無殘留，該清單對它們的判斷成文即過時） |
| 14 | 63 §G.4 | M-8 本體 | 「依 ISO 4217」句改寫；`to_psp_minor_unit` 裸簽名代碼塊**整個刪除不留簡化版**（裸 (Integer, String) 簽名正是 §C L1–L3 要禁的形態）；exponent=3 的「market 建立時擋、回 INCLUSION」句依 68 §D-3 同段修正（**兩個根因、兩條註釋**） |
| 15 | 63:175 `parse_to_cents` 註釋 | M-8 延伸（登記外） | 「換算回 ISO minor unit」改「依該 pack 宣告的 amount_format 換算」 |
| 16 | 63 §L 驗收清單 | M-8 延伸（登記外） | 點名的 `to_psp_minor_unit` 改 `Money::Storage#to_psp_amount`——驗收清單點名已廢函式會反向鎖死舊實作 |
| 17 | `limits.yml` `currency_display` | M-8 連帶 | `psp_minor_unit_follows_iso4217` 改名 `psp_amount_format_declared_per_pack`（鍵名兩個字面都已不成立；比照 D-2：不做別名、原位留 deprecation）；63 §9 鍵表同輪改 |

**本輪 grep 詞表**（依 §J.1 教訓「登記表要靠 grep 補完」，傳給下一輪）：`to_psp_minor`／`psp_minor`／`minor unit`／`ISO 4217`／`零小數`／`zero-decimal`／`×100`／`amount_format`／`PspDecimal`／`stripe_amount`。
⚠️ **已知盲區**：三處「PI 金額是 R5」靠 `PspMinor` 命中；若某處用中文措辭（如「PSP 回報的整數金額」）轉述舊契約，上表任何詞都不命中。§B 末完整性檢查（X1–X11 機械化）落地前，文檔側只能靠本詞表傳承。

**方法論數據（第三次應驗）**：M-1 輪登記 3 → 實改 7；本輪登記 5 → 實改 17。比例穩定在 2–3 倍，**登記表永遠少算**。

---

## K. 本篇驗收（對照 `docs/specs/11` §0 七維度）

### 2 資料完整

1. §H.2 的 T1–T24 全綠；T3／T4／T5／T6 任一紅 ⇒ **不得上線**（這四條是三種事故形態的直接斷言）。<!-- 依 69 §V-188 擴充，原文：「T1–T14 全綠」；2026-08-31 隨 R7 擴至 T24 -->🔴 **T15／T17／T19／T20／T23／T24 亦為不得上線條件**——它們是主單位兩格式（`decimal_string`／`decimal_number`）的事故形態，而**該類型的錯誤在基準法域 HKD 上同樣會發生**（§C.1 末段），不像 T3–T6 只在 zero-decimal 幣別現形。
2. 對 `app/` 全庫掃描，每一個金額跨界點都對應到 §B 的 X1–X12（PSP 兩向細分 X7a/X7b/X7c/X8a/X8b/X8c）其中一列；對應不上即 fail。

### 4 效能

3. 值物件的建構不得出現在熱路徑的迴圈內（集合頁 50 張卡 ⇒ 50 次 `Money::Display.render`，可接受；50 × N 次不可）。

### 6 測試

4. **`money_boundary.test_matrix_zero_decimal_required` 的每個幣別都出現在金額測試檔中**；缺任一 ⇒ CI fail。
4b. 🔴 **`money_boundary.test_matrix_amount_formats_required` 的每一種格式都有 fixture pack**（依 69 §V-188 新增；2026-08-31 起共三種）；缺任一 ⇒ CI fail。理由與第 4 條同構：**沒有這條，主單位型路徑的零覆蓋不會被任何人發現**。
5. 金額路徑 100% 覆蓋（11 §0 維度 6）。
6. `app/` 下 grep `to_f` 在金額相關檔案命中數為 0（沿用 58 §K 24）。
7. §C.3 的**四條** CI 檢查各有一個「故意違反」的 fixture，證明檢查真的會 fail（**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有）。

### 5 可觀測

8. 每一次 X7／X8 轉換落結構化日誌：`psp`、**`amount_format`**、`currency`、`exponent`（僅 `minor_units`）、`divisor`／`decimal_places`、`divisibility`、`storage_cents`、送出值。對帳事故時這些欄位就是完整的還原資訊。<!-- 依 69 §V-188 補 amount_format／decimal_places／divisibility 三欄：沒有 amount_format，事故日誌無法回答「這筆到底是以哪一種格式送出去的」 -->
9. `NonIntegralPspConversion`／`PspMinorUnitUndeclared`／**`PspAmountFormatUndeclared`**／**`PspDivisibilityViolation`** 四個例外 ⇒ **P1 告警**（它們代表上游算錯或 pack 沒宣告，不是使用者輸入錯誤）。

---

## L. 待查證（V-130 起）

> 沿用 52 §附錄 A 與 58 §附錄 A 的規則：**無明確出處一律不自補規則；當前處置一律是保守失效**。

| # | 待查證項目 | 去哪查 | 當前處置 | 阻塞什麼 |
|---|---|---|---|---|
| **V-130**<br>🔴 **前提已由 69 號證實，範圍縮小** | ~~各 PSP 對各幣別實際採用的 minor unit 是否等同 ISO 4217——特別是 TWD，以及**業界傳聞中**「ISO 為 2 位但該 PSP 要求金額為 100 的倍數」的那一類幣別~~<br>**已答（`alt` ×4，69 §V-188）**：**不等同**，且四家四種算法（§D.4）。「傳聞中的整除規則」＝ **Stripe 對 HUF／TWD payout 的明文要求**。<br>**殘留**：我方**實際要接的那一家**對 TWD 的宣告值（單位＋整除＋作用範圍）——那必須來自該家的合約文件或沙箱實測，**不能從別家的表推**（Adyen 明文說自家表覆蓋 ISO 就是這條的反證） | 我方選定 PSP 的官方 API 參考（幣別與最小金額頁）；沙箱實測；或業務要一句書面（open-decisions A-3） | **pack 必須明文宣告 `amount_format` ＋ minor unit ＋ `divisibility`，未宣告 ⇒ reject**（§D.2 A0／A1／A5）。TWD 在宣告前不得送款 | §D、§H.3 |
| 🔴 **V-206**<br>（依 69 §V-188 新增） | **`divisibility_constraint` 的作用範圍**：Stripe 對 HUF／TWD 的「整除 100」是**只在 payout**，還是 charge／refund 也適用？（69 號讀到的敘述是「付款時可兩位小數、payout 時須整除 100」⇒ **兩個階段的規則不同**，而我方目前只有一個 `divisibility` 表） | Stripe 官方幣別頁的 `Special cases` 表 ＋ payouts 章節；沙箱以非整除金額實測 charge 與 payout 各一次 | pack 的 **`divisibility_scope` 缺鍵 ⇒ 不得 enable**（§D.3）。已宣告者以**最嚴格**解讀（charge 亦套用）——寧可拒絕送出，不可送出後才在 payout 卡住（那時錢已經收了，卡的是我方提款） | §D.2 A5、§D.3、§H.3 |
| **V-131** | **ISO 4217 minor unit 表的一手來源與落地形式**：進 repo 還是用 gem？用 gem 的話哪一個、如何釘版？ | ISO 4217 官方維護機構（SIX）發布的 `list-one` 資料；候選 gem 的維護狀態 | 表進 repo（`config/iso4217_minor_units.yml`）＋ 版本註記；**禁止未釘版的 gem**——一張會自己更新的表就是一顆定時炸彈 | §D.1 |
| ~~**V-132**~~<br>✅ **已結案（2026-08-31，G6-0(b) 複驗輪）** | ~~Airwallex 的金額欄位語義~~ 三項殘留全數以一手文檔答出：①**per-currency 小數位數**＝payments 側零小數 20 幣逐字清單（payments-and-fee-rounding 頁；🔴 HUF/TWD/IDR 覆蓋 ISO）＋其餘 2 位；②幣別欄位名＝`currency`（payment_intents create 必填欄位表）；③webhook 金額形態＝JSON **number**（payload 例 `16.66`）。🔴 **同輪更正**：單位的 2026-08-12 結論「十進位主單位**字串**」有誤——wire form 是 JSON **number**（data_types 逐字 "$9.99 is represented as 9.99"＋schema `amount: number`）⇒ 落成 **R7／`amount_format: decimal_number`**；R6 的實證代表改由 PayPal 承接。69 號已同步有日期更正（19.5） | ~~developer.airwallex.com~~ 已取得；沙箱 charge＋webhook 實測隨 G6-1（enable 前必做，`enabled: false` 承接把關） | `psp_packs.airwallex` 本體已落鍵、`enable_gate: []`、**`enabled: false` 維持**（enable 時點＝G6-1 adapter＋sandbox 端到端後） | §A R7、§D.3、§D.4 |
| **V-133** | **PSP 結算檔（非 API 回應）的金額單位**是否與 API 一致；手續費與爭議扣款的單位 | 各 PSP 的結算報表規格頁；實際下載一份對照 | 對帳器對結算檔一律先做 §F.2 的顯式轉換，並在轉換前後各記一次日誌 | §F.2 |
| **V-134** | **平台 rollup 跨幣別彙總的換算時點**：交易日匯率還是報表日匯率？ | 使用者裁定（會計政策問題，非技術問題） | `cross_currency_sum_forbidden: true` ⇒ 平台側**分幣別呈現**，不給單一合計數 | §F.3 |

---

## 附錄 A：一頁速查（貼在 PR 模板裡）

```
JPY ¥1,480
  R1 儲存      148000        ← DB、業務層、分錄、冪等鍵      （×100，不看幣別）
  R3 顯示      "¥1,480.00"   ← Liquid money、admin、通知信   （恆兩位）
  R4 十進位    "1480.00"     ← JSON-LD、feed、CSV、MoneyV2、物流商   🔴 不得送 PSP
  R5 PSP minor 1480          ← amount_format: minor_units 的 adapter （÷ 10^(2-exponent)）
  R6 PSP 十進位 "1480.00"     ← amount_format: decimal_string 的 adapter（PayPal 型；
                               JPY 覆蓋 0 位時＝"1480" 無小數點）
                               🔴 與 R4 長得一樣、型別不同、後綴不同（_psp_decimal）
  R7 PSP 主單位數 1480         ← amount_format: decimal_number 的 adapter（Airwallex 型；
                               BigDecimal，wire＝JSON number；後綴 _psp_number）

送出前（唯一出口 Money::Storage#to_psp_amount(psp:)）：
  A0 pack 宣告 amount_format 了嗎？（沒宣告 ⇒ reject，不得預設 minor_units）
  A1 該幣別的單位宣告了嗎？ A2 exponent ≤ 2 嗎？ A3 整除嗎？
  A4 型別是這一家的那一種嗎？ A5 過 divisibility 了嗎（TWD/HUF 可能要整除 100）？
  A6 位數與格式對嗎？ A6c cents 能無損表達為該幣別生效位數嗎（不能 ⇒ raise，不 round）？
  A7 生效位數＝overrides 優先（PayPal/Airwallex 都覆蓋自己引用的底表）——全過才准送。
收進來：Money.from_psp_amount 先包成該 pack 的 amount_value_class（Float 恆拒），
  再 to_storage，再比對。比對前兩邊都要是 R1。
測試裡有 JPY／TWD／KRW 嗎？三種 amount_format 的 pack 都有嗎？零位覆蓋的 pack 有嗎？
  沒有的話，你的測試全綠也證明不了任何事。
```
