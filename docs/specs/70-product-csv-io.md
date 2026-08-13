# 70 — 商品 CSV 匯出入（多語言）·欄位契約·Shopify 匯入器

> # 🔴 本檔 §D 的欄名規則基於**錯誤前提**，尚未修正 —— 實作前必讀
>
> **錯在哪**：§D.2 訂了 `locale_tag_requires_region: true`，於是譯文欄名是 `Title [en-HK]`、`Title [zh-Hant-TW]`。
> **這與 67 號直接衝突**，而 67 號是對的 —— 67 §A.1 逐字寫著「一份 `zh-Hant` 譯文，兩個市場共用；市場差異走 `translations.market_id`」，
> 並把「同一份繁中譯文要存兩次（`zh-Hant-HK` 一份、`zh-Hant-TW` 一份）」列為**事故**：商家改 HK 的商品標題，TW 不會變。
>
> **根因**：2026-08-13 使用者的裁定是「**URL** 一律帶地區碼（`en-HK`／`zh-Hant-TW`）」，
> 本檔的委派 prompt 把它誤讀成「**內容**也按語言＋地區鍵」。使用者隨後澄清：
> 「英文都是同一組英文，不同國家只要是使用英文，都是調用 `Product Name (English)`。區別只是國家在後台設定的時候會添加國家區分碼。」
>
> **正確規則**：**內容鍵＝語言**（`en`／`zh-Hant`／`zh-Hans`）；**URL 與 hreflang 鍵＝語言＋地區**。兩者是不同維度，CSV 屬前者。
> ⇒ §D.2 的 `locale_tag_requires_region` 應為 **false**，欄名應為 `Title [en]`／`Title [zh-Hant]`，
> `docs/templates/` 兩份範本要重新產生（譯文欄數由 24 降為對應語言數）。
>
> **仍然有效、不要一起丟掉的部分**：§D.2 的「方括號而非圓括號」結論（163 個表頭掃描、`[` `]` 命中 0）、
> §A 的三檔實測、§C 欄位總表、§E 變體重複列、§F 匯入語義、Shopify 匯入器映射 —— 這些與 locale 粒度無關。
>
> **待決**：寬表（Shopline 式，語言少時好用）vs 長表（Shopify 原生，8 欄固定不隨語言成長）要做哪一種或兩種都做，
> 已提交使用者裁決，未定案前不要據本檔實作匯出入。


> **本檔要回答的三個問題**：①一份能同時吃 Shopify 匯出檔、又能表達 N 個語言的商品 CSV，欄名長什麼樣 ②多語言的商品欄位到底放商品 CSV 還是翻譯 CSV（兩個都放＝同一份資料兩個真相來源）③從 Shopify 搬過來的檔案，欄位對不上的地方怎麼處理。
>
> **實際範本檔在 `docs/templates/`**，本檔 §附錄 A 有它們的可重跑驗證。上限值一律在 `config/limits.yml` §23（`csv:`）。

---

## 0. 範圍、出處等級、與既有規格的關係

### 0.1 觸發

使用者裁定（2026-08-13）：「**商品的匯出和匯入功能要做**，包括附件他的的匯出表格格式，以及匯入的 template 格式，**但是你要在這兩個你要加入多語言內容**。例如 shoplinecsv 這個 excel 的。你可以參考他的格式。」

⇒ 本檔的定位是**執行裁定**，不是重新討論要不要做。要討論的是**怎麼做才不會與 67（多語言）、65（金額單位邊界）、61／63（商品資料流）打架**。

### 0.2 出處等級（沿用 67 §0.3，本檔加一級 `observed`）

| 級別 | 意思 |
|---|---|
| `ruling` | 使用者裁定。優先於一切——它是產品決策，不是對 Shopify 的復刻 |
| `help` | Shopify 官方說明中心（透過 61／60／63 引用） |
| `alt` | 對照平台的官方產物（Shopline 的官方範本檔、Shopline 後台的 ng-model） |
| **`observed`** | **本輪對三個一手檔案的直接實測**（用 `csv` / `openpyxl` 解析，數字可重跑） |
| `ours` | 本專案決策，無外部依據 |

### 0.3 三個一手參考檔（本檔全部結論的證據底盤）

| 代號 | 檔案 | 是什麼 | 實測 |
|---|---|---|---|
| **E1** | `products_export.csv` | **Shopify 匯出**，使用者真實商店的一筆商品 | 44 欄、2 列、UTF-8 無 BOM、**LF**、`Body (HTML)` 內含換行 |
| **E2** | `product_template.csv` | **Shopify 官方匯入範本** | 57 欄、17 列（含 12 變體的實體商品、3 變體的數位商品、1 個單變體香水）、UTF-8 無 BOM、**CRLF** |
| **E3** | `shoplinecsv.xlsx` | **Shopline 商品範本**（多語言） | 62 欄、**第 1 列英文表頭 ＋ 第 2 列中文表頭**、1 列範例資料 |

### 0.4 本檔推翻／偏離的既有結論（逐條可追溯）

| # | 既有結論 | 本檔立場 |
|---|---|---|
| 1 | 67 §E.6 理由 1：「硬塞進商品 CSV 就要為每個語言加一組欄位……加第 4 個語言時整張表要改」 | ✅ **理由成立，結論部分修正**：它證明的是「商品 CSV 不該是譯文的**儲存**」，不是「商品 CSV 不該**攜帶**譯文」。真相仍在 `translations` 表，商品 CSV 是它的第二個傳輸面（§H）。裁定要求它存在，而 §H 給出一個結構性理由說明**為什麼它必須存在**（新目錄的 bootstrap 用翻譯 CSV 做不到） |
| 2 | 67 §A.4／§C.1：`en` 無地區、「**不得**為了表達『香港的繁體中文』而建 `zh-Hant-HK`」 | 🔴 **被 2026-08-13 裁定推翻**：locale 一律「語言＋地區」（`en-HK`／`zh-Hant-HK`／`zh-Hant-TW`）。本檔的欄名規則依裁定寫。**本檔不改 67**（有別的 agent 在改），衝突登記在 §M-1 |
| 3 | 61 §9.5：`csv.product_max_upload_mb` 標為「✅ 已有」 | 🔴 **實測不存在**：`config/limits.yml` 在本輪之前**沒有** `csv:` 頂層鍵（`yaml.safe_load` 可驗），61 指的其實是 `media.csv_max_upload_mb`。而 67 §E.6 又以 `max_upload_mb_key: csv.product_max_upload_mb` 引用它 ⇒ **兩處懸空引用**。本輪補上真鍵（§J） |
| 4 | 13 §F6：「一套 CSV 匯入」 | 已由 63 §L-8 拆成商品／庫存兩套；本檔確認**第三套是翻譯 CSV**（67 §E.6），並定義三套的分工（§H）。13 §F6 待其擁有者回寫 |

---

## A. 三個參考檔的實測發現

### A.1 🔴 Shopify 的匯出與匯入**不是同一套欄名**（observed）

這件事本身就該寫進規格——它是我方匯入器**必須認得兩套方言**的直接原因。

| 語義 | E1（匯出）欄名 | E2（匯入範本）欄名 |
|---|---|---|
| 唯一鍵 | `Handle` | `URL handle` |
| 商品描述 | `Body (HTML)` | `Description` |
| 分類 | `Product Category` | `Product category` |
| 上架 | `Published` | `Published on online store` |
| SKU | `Variant SKU` | `SKU` |
| 條碼 | `Variant Barcode` | `Barcode` |
| 售價 | `Variant Price` | `Price` |
| 原價 | `Variant Compare At Price` | `Compare-at price` |
| 課稅 | `Variant Taxable` | `Charge tax` |
| 稅碼 | `Variant Tax Code` | `Tax code` |
| 重量 | `Variant Grams` ＋ `Variant Weight Unit` | `Weight value (grams)` ＋ `Weight unit for display` |
| 庫存政策 | `Variant Inventory Policy`（`deny`） | `Continue selling when out of stock`（`DENY`） |
| 圖片 | `Image Src` | `Product image URL` |
| 變體圖 | `Variant Image` | `Variant image URL` |
| SEO | `SEO Title` / `SEO Description` | `SEO title` / `SEO description` |
| 選項名 | `Option1 Name` | `Option1 name` |

**連大小寫都不一致**（`Option1 Name` vs `Option1 name`、`Product Category` vs `Product category`）。

⚠ **本輪未查證**：Shopify 的匯入器是否同時接受兩套（很可能接受，但我方沒有一手證據）⇒ **V-310**。無論答案是什麼，**我方的正規欄名只有一套**，理由見 §I.1。

### A.2 Shopline 的多語言做法：成對欄位 ＋ 雙語表頭（`alt`，observed）

62 欄裡有 **8 組成對語言欄**（16 欄）：

```
Product Name (English) | Product Name (Traditional Chinese)
Product Summary …      | Product Summary …
SEO Title …            | SEO Title …
SEO Description …      | SEO Description …
Preorder Note …        | Preorder Note …
POS Categories …       | POS Categories …
Product Promotion Label … | Product Promotion Label …
Variant (English) (DO NOT EDIT) | Variant (Traditional Chinese) (DO NOT EDIT)
```

**不成對（＝不可翻譯）的**：`SEO Keywords`、`Regular Price`／`Sale Price`／`Member Price`／`Product Cost`、`SKU`、`Quantity`、`Weight(KG)`、`Barcode`、`MPN`、`Brand`、`Supplier`、`Product Tag`、`Location ID`。

另外三個做法值得單獨記：

1. **雙語表頭**：第 1 列英文、第 2 列中文（`商品名稱 (英文)` / `商品名稱 (繁體中文)`）。⇒ **它的表頭是「文案」而不是「解析鍵」**（同一欄有兩個名字）。這一點對 §D.1 是關鍵證據。
2. **`(DO NOT EDIT)` 標記系統 ID**：`Product ID`／`Variant ID`／`Quantity`／`SL_STOCK_ID`／`SL_KEY0`／`SL_KEY1`／`Warehouse`。⇒ 它把「系統唯讀」做成表頭上的可見標記，不是靠文件。
3. **增量語法**：`Update Quantity (e.g. +5 or -8)` 與 `Quantity (DO NOT EDIT)` 成對——**顯示絕對值、只接受增量**。⇒ 與 Shopify 庫存 CSV 的 `On hand (current)` ＋ `On hand (new)` 樂觀鎖（61 §6.2）是同一個問題的兩種解法。

🔴 **這三個做法我方各採用一部分，但都不放在商品 CSV 裡**：
- `(DO NOT EDIT)` 的**意圖**採用（§C 的「系統唯讀」分類 ＋ 匯入時只讀不寫），**字面標記不採用**——欄名帶括號註記會與 §D 的 `[locale]` 後綴搶同一個位置，且它是文案（鐵律 9）。
- **增量語法不採用**：數量是庫存 CSV 的事（63 §L-8、60 §5 官方明確要求分流），商品 CSV 不寫庫存量。我方的樂觀鎖形態沿用 Shopify 庫存 CSV 的 `On hand (current)`（61 §6.2），因為那是 `help` 級且我方已定案。

### A.3 一手佐證：Shopline 後台的資料形態（`alt`）

從 Shopline 後台抓到的 ng-model：

```
product.title_translations[lang]      product.summary_translations[lang]
product.description_translations[lang]  product.preorder_note_translations[lang]
product.seo_title_translations[lang]    product.seo_description_translations[lang]
product.seo_keywords                  ← 沒有 _translations
```

⇒ 兩件事被同時證實：
1. 底層資料形態是 `{field}_translations: { locale: value }` ——**CSV 的成對欄位就是這個 map 的攤平**。與我方 `translations` 表（67 §C.2）是同一個模型，只是我方把它正規化成列而非 JSON map。
2. `seo_keywords` **沒有** `_translations` ⇒ 它在 Shopline 是不可翻譯的，與 E3 的表頭（`SEO Keywords` 不成對）互相印證。**兩個獨立來源指向同一結論**，可以當定論用。

---

## B. 檔案格式契約

### B.1 位元組層（`csv.*`）

| 項目 | 匯入 | 匯出 | 依據 |
|---|---|---|---|
| 編碼 | UTF-8；**接受 BOM** | UTF-8；**不寫 BOM** | E1／E2 皆無 BOM（observed）；Excel 存檔常帶（13 §F6 坑） |
| 換行 | **LF 與 CRLF 都收** | **LF** | E1＝LF、E2＝CRLF（observed）——同一家公司的兩份檔案就不一致，收兩種不是體貼是必要 |
| 引號 | RFC 4180（`""` 跳脫） | 同 | |
| 儲存格內換行 | 🔴 **合法** | 🔴 **會產生** | E1 的 `Body (HTML)` 實測含 `\n`。⇒ 解析器**必須有狀態**，不得以「一行一列」切割（`csv.multiline_cell_allowed`） |
| 大檔 | streaming（`CSV.foreach`） | streaming（`find_each`） | 13 §F6-2／F6-3 既有 |

### B.2 尺寸上限（全部在 `config/limits.yml`，鐵律 6）

| 鍵 | 值 | 出處 |
|---|---:|---|
| `csv.product_max_upload_mb` | 15 | 61 §6.1（help） |
| `csv.inventory_max_upload_mb` | 15 | 61 §6.2（help） |
| `csv.product_max_rows` | 50000 | 🟡 **ours**（13 §F6.2）；官方未載明 |
| `csv.product_max_columns` | 512 | 🟡 **ours**，結構性護欄；推導見 §E.2 |
| `csv.multilingual.max_locales_per_file` | 5 | 🟡 **ours**；推導見 §E.2 |
| `csv.export_email_threshold_variants` | 100 | 61 §6.1（help，P53） |
| `csv.collection_column_max_chars` | 255 | 61 §9.5（help，P51） |

---

## C. 欄位總表

**我方正規欄集 ＝ 43 個基礎欄**。前 40 欄逐欄等同 E1（Shopify 匯出）的欄序，去掉 `Option{n} Linked To` 三欄（未實作，§I.2）與店家自訂 metafield 欄；後 3 欄是我方新增。

分類統計：**可翻譯 12 欄｜不可翻譯 28 欄｜系統唯讀 3 欄**。

### C.1 可翻譯（12）——可掛 `[locale]` 後綴

| # | 欄名 | 67 §B.2 類別 | 出處 | 註 |
|---:|---|---|---|---|
| 1 | `Title` | 必翻 | E1／E2／E3 | 上限沿用 `product.title_max_chars` |
| 2 | `Body (HTML)` | 必翻 | E1／E2 | 富文本；譯文走與商品描述**同一條淨化管線**（67 §K.0 維度 1） |
| 3 | `Type` | 可選 | E1／E2 | 自由文字；平台分類法的標籤**不在此**（那是平台資料）。⚠ E3 沒有對應欄（它的 `Brand` 是廠商不是類型） |
| 4 | `Option1 Name` | 必翻 | E1／E2 | 🔴 變體身分不得依賴譯文（67 §B.3-4） |
| 5 | `Option1 Value` | 必翻 | E1／E2 | 🔴 `Default Title` 例外：**禁止翻譯**（§D.4） |
| 6 | `Option2 Name` | 必翻 | E1／E2 | |
| 7 | `Option2 Value` | 必翻 | E1／E2 | |
| 8 | `Option3 Name` | 必翻 | E1／E2 | |
| 9 | `Option3 Value` | 必翻 | E1／E2 | |
| 10 | `Image Alt Text` | 可選 | E1／E2 | 機翻 alt 要標（67 §B.2 引 62 §F.1 `alt_source`） |
| 11 | `SEO Title` | 可選 | E1／E2／E3 | 上限沿用 `content.seo_title_max_chars` |
| 12 | `SEO Description` | 可選 | E1／E2／E3 | 上限沿用 `content.seo_meta_description_max_chars` |

### C.2 不可翻譯（28）

| 分組 | 欄名 | 為什麼不可翻 |
|---|---|---|
| **識別** | `Handle` | 🔴 67 §D.3（我方刻意偏離 Shopify）：全站一個 handle，語言維度由 URL 前綴承載。**明知偏離**——本尊自 2023-06-26 起 handle 可翻（67 §M-2） |
| | `Variant SKU`、`Variant Barcode` | 識別碼。翻了 ⇒ 出貨單／WMS／feed 對帳全斷（67 §B.3-1）。E3 亦不成對 |
| **集合鍵** | `Tags` | 🔴 67 §B.3-2：tag 是集合運算的鍵。翻譯 tag ⇒ 商品的系列成員資格隨語言變動。要多語言的是 `FILTER.label`，不是 tag 值 |
| | `Product Category` | 平台分類法的節點，值域不是自由文字；各語言標籤由分類法 pack 提供 |
| **金額** | `Variant Price`、`Variant Compare At Price`、`Cost per item` | 🔴 鐵律 3 ＋ 67 §B.3-5：金額沒有「語言版本」。語言只影響格式化，格式化由 market locale 決定 |
| **數量／度量** | `Variant Grams`、`Variant Weight Unit`、`Variant Inventory Qty`、`Unit Price Total Measure`、`Unit Price Total Measure Unit`、`Unit Price Base Measure`、`Unit Price Base Measure Unit` | 數值與單位碼。🔴 **單位價格的兩個數值欄長得像金額（E2 實測 `500.00`／`50.00`）但不是**，見 §F.3 |
| **契約字串** | `Variant Inventory Tracker`、`Variant Inventory Policy`、`Variant Fulfillment Service`、`Variant Requires Shipping`、`Variant Taxable`、`Variant Tax Code`、`Gift Card`、`Published`、`Status` | enum／布林／服務代號。翻了就不是那個值 |
| **URL** | `Image Src`、`Variant Image` | 🔴 67 §B.2（`MENU/LINK.url` 同理）：在翻譯層改 URL 會產生跨語言死鏈 |
| **其他** | `Vendor`、`Image Position` | Vendor 是**一個**廠商名（61：每商品只能一個），E3 的 `Brand` 亦不成對；Position 是序數 |

### C.3 系統唯讀（3）——匯出填值、匯入只讀不寫

| 欄名 | 角色 | 出處 |
|---|---|---|
| `Product ID` | `gid://chilllove/Product/{id}`（鐵律 4 的 GID 格式）。匯入時**不建立、不改寫**，僅用於定位 | E3 的 `Product ID (DO NOT EDIT)` |
| `Variant ID` | `gid://chilllove/ProductVariant/{id}`。🔴 **有它就用它定位變體**，沒有才退回選項值組合比對（§E.4） | E3 的 `Variant ID (DO NOT EDIT)` |
| `Source Locale` | 🔴 **檔級不變量，逐列攜帶**：必須全檔一致、且等於目標店鋪的來源語言，不符 ⇒ **整檔拒絕** | **ours**；形態抄自 61 §6.2 的 `On hand (current)`（官方明載那是「安全驗證」用的逐列快照） |

🔴 **`Source Locale` 為什麼不是設定而是斷言**：`i18n.source_locale_per_resource: false`（67 §C.3）——來源語言是**店鋪級**的，逐列不同就沒有消費者能回答「`products.title` 是什麼語言」。所以逐列不同的檔案是**整檔拒絕**，不是「這一列用別的語言」。它存在的唯一理由是擋掉「A 店（繁中來源）匯出的檔案倒進 B 店（英文來源）」——那會把整批繁中字串標成英文，而且**不會有任何一列報錯**。

🔴 **它不能是必填**，否則 Shopify 匯出檔無法直接匯入 ⇒ 缺欄時假定為目標店鋪的來源語言並在報告告警（`csv.product_import.source_locale_absent_action`）。

---

## D. ⭐ 多語言欄名的命名規則

### D.1 為什麼**不**抄 Shopline 的 `(English)`

五條，前兩條是硬的（會壞），後三條是結構性的（會慢慢壞）。

| # | 理由 | 具體壞法 |
|---|---|---|
| **1** | 🔴 **裁定：locale 一律「語言＋地區」**（`en-HK`／`zh-Hant-HK`／`zh-Hant-TW`） | HK 市場與 SG 市場**都有英文** ⇒ `Product Name (English)` 一個欄名要承載 `en-HK` 與 `en-SG` 兩份不同內容。**成對欄名在第二個英文市場出現的那一天撞名**，而在那之前所有測試都是綠的 |
| **2** | 🔴 **語言的顯示名本身就是文案** | E3 自己證明了這一點：它需要**第二列中文表頭**（`商品名稱 (英文)`）才能給中文使用者看。⇒ 同一欄有兩個名字 ⇒ 表頭是文案不是解析鍵。我方若抄，就得決定 `(Traditional Chinese)` 還是 `(繁體中文)` 還是 `(繁中)`，而三者都「對」 |
| **3** | **違反「語言集合是資料不是列舉」**（67 §A.2，`i18n.launch_locales_is_seed_not_enum`） | 顯示名 ⇒ 需要一張 `locale → 顯示名` 對照表才能組出／解析欄名。新增一個語言就要動那張表 ⇒ 裁定明文的「後台一次操作、不改程式碼」做不到 |
| **4** | **`zh-Hant-HK` 與 `zh-Hant-TW` 都叫「繁體中文」** | 我方範本裡就有現成反例：香港繁中寫「香薰蠟燭」、台灣繁中寫「香氛蠟燭」。同樣是 `Hant`，用詞不同。`(Traditional Chinese)` 無法區分，而 67 §A.4 已定「繁簡之間永不互為 fallback」——**地區之間也不該靠猜** |
| **5** | **鐵律 9** | 欄名是互通性契約（要吃對方的檔案就必須認得對方的欄名，§I.1 照做），但**我方自己產生的欄名**沒有互通性義務，抄它就只是抄文案 |

### D.2 我方規則

```
{基礎欄名}␣[{BCP-47 標籤}]
```

- 分隔：一個半形空格 ＋ 方括號。
- 標籤：**原樣的 BCP-47 標籤**，大小寫依 `i18n.normalize_tag_case_on_write`（語言小寫／script Title case／地區大寫）。
- 標籤**必須帶地區**（`csv.multilingual.locale_tag_requires_region: true`，依裁定）。裸 `en`／`zh-Hant` 在欄名裡一律拒絕。

範例（本檔範本檔實際使用的 24 個譯文欄之四）：

```
Title [en-HK]        Title [zh-Hant-TW]
Body (HTML) [en-HK]  SEO Description [zh-Hant-TW]
```

**🔴 為什麼是方括號而不是圓括號**（observed，可重跑）：把 E1（44 欄）＋E2（57 欄）＋E3（62 欄）＝ **163 個表頭字串**全部掃一次——

| 字元 | 命中數 | 命中的欄名 |
|---|---:|---|
| `[` `]` | **0** | — |
| `(` `)` | **33** | `Body (HTML)`、`Weight value (grams)`、`Color (product.metafields.shopify.color-pattern)`、`Product Name (English)`、`Quantity (DO NOT EDIT)`… |
| `/` | 13 | `Google Shopping / Gender`… |
| `｜` `{` `}` `<` `>` `#` `@` `"` | 0 | — |

⇒ 圓括號在 Shopify 的表頭裡**已經有兩種意思**（單位註記 `(grams)`、metafield 路徑 `(product.metafields.…)`），在 Shopline 又是第三種（語言）。我方再加一種，解析器就必須靠**寫死的清單**去判斷 `(HTML)` 是註記、`(en-HK)` 是語言——那正是 §D.1 理由 3 要避免的 enum。方括號在三份真實檔案裡零出現，是**空的命名空間**。

`|` `{}` 也是空的，但方括號在 BCP-47／i18n 工具鏈（gettext、XLIFF 檔名慣例）裡更常見，且在 Excel 裡不會觸發任何特殊解讀。

### D.3 基礎欄（無後綴）＝ **來源語言**，不是「預設值」

```
Title                 ⇒ 來源語言（本店＝ zh-Hant-HK）的標題
Title [en-HK]         ⇒ en-HK 的譯文
Title [zh-Hant-HK]    ⇒ 🔴 與上面第一列是同一格資料 ⇒ 整檔拒絕
```

🔴 **這條是「Shopify 匯出檔能原檔吃進來」的唯一理由**：一份沒有任何 `[locale]` 欄的檔案 ＝ 一份純來源語言的檔案 ＝ 就是 Shopify 匯出檔。若要求每欄都寫 `Title [zh-Hant-HK]`，每個搬家的商家第一步都得先改表頭——而 60 §5 已經指出，我方做這個匯入器的**全部理由**就是降低搬家成本。

🔴 **同時出現無後綴欄與 `[來源語言]` 欄 ⇒ 整檔拒絕**（`source_locale_duplicate_column_action: reject_file`）。**不做仲裁**：任何「後者覆蓋前者」「非空者優先」的規則都會在某個商家的檔案上選錯，而且不會報錯。

### D.4 拒絕條件（四類，都是整檔或整列失敗，沒有「靜默忽略」）

| 條件 | 動作 | 鍵 | 理由 |
|---|---|---|---|
| `[locale]` 掛在**不可翻譯欄**上（`Handle [en-HK]`、`Tags [en-HK]`、`Variant Price [en-HK]`） | 整檔拒絕 | `non_translatable_locale_column_action` | 靜默忽略 ⇒ 商家以為翻了。錯誤訊息要指出分類（識別碼／集合鍵／金額／URL） |
| 表頭出現**店鋪未啟用的語言** | 整檔拒絕 | `unknown_locale_column_action` | 同上 |
| `Option1 Value = Default Title` 那一列帶了 `Option1 Value [*]` 譯文 | **該列失敗** | `default_title_translation_action` | 🔴 63 §B.2／67 §B.3-3 硬相容契約：翻成「預設標題」⇒ Ella 的 `variants.first.title != 'Default Title'` 判定翻轉 ⇒ 無變體商品渲染出空的變體選擇器，**M6 golden theme 驗收直接失敗** |
| 標籤不帶地區（`Title [en]`） | 整檔拒絕 | `locale_tag_requires_region` | 依裁定 |

---

## E. 變體的表達與列 × 欄爆炸

### E.1 沿用 Shopify 的重複列（不自創）

```
第 1 列   ：商品層全部欄位 ＋ 第 1 個變體的變體層欄位 ＋ 第 1 張圖
第 2 列起 ：Handle 必須重複；商品層欄位必須留白；只填該變體的選項值／SKU／價格／重量／圖
純圖片列 ：只有 Handle ＋ Image Src ＋ Image Position ＋ Image Alt Text（＋ 其譯文）
```

依據 61 §6.1（help）。**格式相容比自創漂亮重要**——60 §5 的匯入 modal 逐字證明 Shopify 把跨平台搬家導向第三方 app，我方的反向路徑（吸引 Shopify 商家轉移）只有在「原檔就能吃」時才成立。

🔴 **商品層欄位在續列必須留白**這條，在多語言下要**連同它的 `[locale]` 欄一起**：`Title` 留白而 `Title [en-HK]` 有值的列是**非法**的（該列會被判成一個沒有來源語言標題的商品層更新）。範本檔的驗證腳本（§附錄 A）第 5 項就在斷言這件事。

### E.2 欄數公式與上限

```
總欄數 = 基礎欄(43) + 可翻譯欄(12) × (選取語言數 − 1)
```

（減 1 是因為來源語言用的是無後綴的基礎欄，§D.3。）

| 語言數 | 譯文欄 | 總欄數 |
|---:|---:|---:|
| 1（僅來源） | 0 | **43** ← 匯出預設；欄序對齊 Shopify 匯出 |
| 2 | 12 | 55 |
| **3** | **24** | **67** ← 本檔範本檔（`zh-Hant-HK` 來源 ＋ `en-HK` ＋ `zh-Hant-TW`） |
| 5 | 48 | 91 ← `csv.multilingual.max_locales_per_file` |
| 20（`i18n.max_shop_locales`） | 228 | 271 |

**有沒有上限？有兩個，而且真正會撞到的不是欄數那個：**

1. **`csv.multilingual.max_locales_per_file: 5`**（ours）。推導：12 個可翻譯欄 × 5 語 ⇒ 48 個譯文欄，已與 43 個基礎欄同量級；**超過這裡，這份檔案就不再是「商品 CSV」而是一張攤平的翻譯表**——而攤平的翻譯表已經有一套專用格式了（§H）。
   🔴 **超過上限不是錯誤，是把商家導去對的工具**（`over_max_locales_action: redirect_to_translation_csv`）：UI 說「你的店有 8 個語言，商品 CSV 一次最多帶 5 個；請選 5 個，或改用翻譯 CSV」。

2. **`csv.product_max_columns: 512`**（ours，結構性護欄）。它**不是**多語言的實際約束——先撞到的一定是 **15 MB**：以本檔範本檔實測，67 欄、三語、含富文本描述的檔案**平均 575 位元組／列**（表頭本身 1207 B）；15 MB ÷ 575 B ≈ **2.7 萬列**，早於 `csv.product_max_rows: 50000` 就會撞牆。⇒ **語言數對檔案大小的影響是乘法的，對列數是零**。UI 在勾選語言時必須即時顯示估算欄數與估算大小（`column_count_formula` 就是給它用的）。

🔴 **分檔一律落在 handle 邊界上**（`split_strategy: handle_boundary`）：續列離開它的首列就失去商品層欄位，整組變成孤兒列。這條比檔案大小重要。

### E.3 選項值的譯文是 **product-scoped 映射**，不是列值

一個 2 選項 × 4 變體的商品，`Option1 Value` 只有 2 個相異值卻出現 4 次。若把 `Option1 Value [en-HK]` 當成列值，同一個「白茶」要填 2 次。

規則：

| 規則 | 鍵 |
|---|---|
| 譯文掛在 **(商品, 選項, 選項值)** 上，不掛在列上 | `option_value_translation_scope: product` |
| 重複出現時**填相同值合法**，留空亦合法（空白＝不動作） | `option_value_translation_repeat_allowed: true` |
| 🔴 重複出現且**值不同** ⇒ **整個商品失敗**，不做 last-wins | `option_value_translation_conflict_action: fail_product` |
| 匯出時只在**該值第一次出現**的列填，其餘留空 | `export_column_layout` 的配套 |

🔴 **為什麼不 last-wins**：61 §6.1 官方明文警告「在試算表軟體裡排序 CSV 會讓變體或圖片 URL 脫鉤」⇒ **列序不是穩定的**。以列序決定勝負 ＝ 商家在 Excel 點一下排序，譯文就換了一個，而且不報錯。

### E.4 變體身分：選項值組合 vs `Variant ID`

| 情形 | 身分依據 | 鍵 |
|---|---|---|
| `Variant ID` 有值 | **它** | `variant_identity_id_wins: true` |
| `Variant ID` 空白 | 選項值組合（Shopify 語義） | `variant_identity_without_id` |

🔴 **必須複製 Shopify 的破壞性語義**（61 §6.1 明載：改動 `Option{n} Value` ⇒ 刪除既有變體 ID 並產生新 ID；61 同時明載我方若不複製，客戶搬過來後訂單歷史會對不上）。

🔴 **多語言讓這條變貴了一個量級**：譯文掛在 `product_option_values.id` 上（67 §B.3-4），選項值一改名 ⇒ 變體重建 ⇒ **掛在舊 id 上的所有語言譯文一起消失**。這正是 E3 把 `Variant (English)` 標成 `(DO NOT EDIT)` 的原因——它們也踩過。

⇒ 兩條落地：①匯出**一律**填 `Variant ID`（`always_emit_system_columns`）②沒有 `Variant ID` 而選項值有變動的匯入，UI 必須在預覽階段警告「這會重建 N 個變體並丟失 M 筆譯文」（`warn_on_option_value_rename_without_variant_id`）。

---

## F. 匯入語義

### F.1 🔴 同一份檔案裡有**兩套**空白語義，分界線寫在表頭上

這是本檔最容易被誤讀的一節，也是與 67 §E.6 對齊的關鍵。

| 情形 | **基礎欄**（無後綴） | **`[locale]` 欄** |
|---|---|---|
| 列缺席 | 該 handle 完全不處理 | 同左 |
| **欄缺席** | 該欄保持不變 | 該欄對全檔不處理 |
| 儲存格空白 ∧ 未勾對應覆寫旗標 | 不變更 | 不動作 |
| 儲存格空白 ∧ **勾了**對應覆寫旗標 | 🔴 **洗掉** | 🔴 **仍然不動作** |
| 有值 ∧ 未勾 | 新建則寫入；已存在則不動 | 只補新的（既有譯文保持） |
| 有值 ∧ 勾了 | 覆寫 | 覆寫 |
| `__CLEAR__` | **字面字串**（不是 token） | **唯一的清空手段** |

依據：
- 基礎欄那一欄 ＝ **61 §6.1（`help`）逐字**：「啟用後，CSV 裡有的欄位一律覆寫，**空白儲存格會把既有資料洗掉**；CSV 裡沒有的欄位則保持不變」。
- `[locale]` 那一欄 ＝ **67 §E.6(a)（`help`，69 §V-182）**：`i18n.import.blank_means_unchanged: true`、`overwrite_scope: non_blank_cells_in_present_columns`、`explicit_clear_token_is_alias_of_blank: false`。

🔴 **為什麼不統一成一套**（這一段比結論重要）：

- 統一到「空白＝洗掉」⇒ 推翻 67 §E.6。那條在 2026-08-12 同日被翻面兩次，最終依據是 `help` 級的本尊原生行為，而 68 那次翻面的教訓明文寫著「`press` 級來源足以登記為未知，不足以翻面一條資料安全預設」。**本檔沒有任何新的一手證據**，憑一個「一致性」的美學理由去翻它，就是把那次事故再犯一遍。
- 統一到「空白＝不動作」⇒ 從 Shopify 搬過來的商家，在一個名字一樣的勾選框下拿到不一樣的結果。而「清掉某個欄位」在 Shopify 就是靠留空達成的，拿掉它等於拿掉一個功能。
- ⇒ **保留兩套，但把分界線做成可讀的**：有 `[locale]` 後綴的欄走翻譯語義，沒有的走商品語義。**欄名本身就是規則**，不需要查表。

### F.2 兩個覆寫旗標，🔴 不得連動

| 旗標 | 作用範圍 | 預設 | 鍵 |
|---|---|---|---|
| 「以相同 handle 覆寫商品」 | 基礎欄 | **不勾** | `csv.product_import.overwrite_products_default: false` |
| 「覆寫既有翻譯」 | `[locale]` 欄 | **不勾** | `i18n.import.overwrite_existing_default: false`（沿用，不另立） |

🔴 **一個旗標控兩件事的具體壞法**：商家想批次改價，勾了「覆寫」，那份檔案裡的譯文欄是他上次匯出的舊版本 ⇒ 一次改價把整店譯文回退到上個月。這與 67 §E.1「兩個語言切換器不得連動」是同一條原則的不同表現。

### F.3 金額：X6（🔴 鐵律 3 ＋ 65 §B）

```
CSV 儲存格（R4，十進位主單位字串）
   → BigDecimal(raw)          ← 🔴 全程 BigDecimal，不得經 float
   → × 100                    ← money_boundary.storage_scale_multiplier（不看幣別）
   → Integer cents（R1）
小數 > 2 位 ⇒ 該列失敗，**不得 round**（money_boundary.decimal_parse_excess_precision_action: raise）
```

🔴 **接受的格式比輸出的格式寬**，而且這一條有實測依據：

| 面 | 正則 | 鍵 |
|---|---|---|
| 匯出（X4） | `^-?\d+\.\d{2}$` | `money_boundary.decimal_string_regex` |
| 匯入（X6） | `^-?\d+(\.\d{1,2})?$` | `csv.product_import.money_accept_regex` |

**為什麼不能兩邊都用嚴格的兩位正則**：E2（Shopify **官方**匯入範本）的 `Compare-at price` 實測有一格是 `80`——零位小數。⇒ 匯入端若直接套 `^-?\d+\.\d{2}$`，**Shopify 自己的官方範本會被我方拒收**。

**千分位**：只在無歧義時清洗。`^\d{1,3}(,\d{3})+(\.\d{1,2})?$` 命中才清洗（小數逗號寫法後面是 1–2 位，不是 3 位，所以這個 pattern 不可能是小數逗號）；其餘含 `,` 的金額格一律該列失敗。🔴 **不做 locale 猜測**：de-DE 的 `1,29`（＝1.29）與 en 的 `1,290`（＝1290）只能靠猜，猜錯是十倍價差且測試全綠。

🔴 **`Unit Price Total/Base Measure` 不是金額**：E2 實測值 `500.00`／`50.00`，與價格欄長得一模一樣，但語義是「500 毫升」。它們必須用**不同型別**（一般 `BigDecimal`，不是 `Money::Decimal`），否則會走進 X6 被 ×100，變成 50000「分毫升」。這正是 65 §C.2「不同單位用不同型別」在 CSV 層的形態。

**匯出（X4）**：`JPY ¥1,480` 儲存 `148000` ⇒ 匯出 `1480.00`，**不得輸出 `148000`**（65 §G 逐字：商家在 Excel 看到 148000 會以為系統壞了，而且回匯時會被 X6 當成 ¥148,000 收下）。⇒ **X4 → X6 的往返是恆等的**：`148000 → "1480.00" → 148000`。本檔範本檔的驗證第 4 項在斷言輸出側。

### F.4 其餘匯入紀律

| 項目 | 規則 | 依據 |
|---|---|---|
| 交易邊界 | **逐行獨立 transaction ＋ 逐行結果報告** | 13 §F6.1、67 §E.6(b) |
| 冪等 | create 分支的 key ＝ `UUID v5(catalog_import, [import_job_id, row_no])` | 63 §A.3 既有，不重定義 |
| **預覽** | 🔴 **三類破壞性操作分開計數**：①基礎欄被洗掉的格數 ②`__CLEAR__` 明示清空數 ③既有譯文被覆寫數 | 67 只有 ②③；本檔多 ① |
| 二次確認 | 任一類佔總列數 > 0.2 | `preview_ratio_confirm_threshold`（形態同 `i18n.import.clear_ratio_confirm_threshold`） |
| 稽核軌 | 三類都寫（誰、何時、哪一次匯入、舊值） | `writes_audit_trail` |
| 必填 | `Title` 在**每個 handle 的第一列**必填；續列必須留白 | 61 §6.1／P54 |
| 未知欄 | 🔴 **一律進報告，永不靜默** | `unknown_column_action: report_never_silent` |
| 識別碼清洗 | 只對 SKU／Barcode／ID 欄剝除**單一個**開頭 `'`；🔴 不對文字欄做 | observed（E1 實測 `'7340032875324`，Excel 的強制文字前綴漏進 CSV） |
| 全形數字 | NFKC 後再解析 | 13 §F6 坑既有 |
| 編碼失敗 | **該列**報「編碼錯誤」，不是整檔炸 | 13 §F6 坑既有 |

🔴 **合成一個「將被改動 N 筆」的數字是不夠的**：商家無法從一個數字判斷風險落在商品資料還是譯文上，而這兩者的復原成本差一個量級（商品資料他手上有源檔；譯文他手上沒有）。

---

## G. 匯出語義

| 項目 | 規則 | 鍵 |
|---|---|---|
| 金額 | X4：主單位、**恆兩位小數** | `money_emit_regex_key` |
| 語言 | 🔴 **預設只有來源語言**（＝零個 `[locale]` 欄 ＝ 一份欄序對齊 Shopify 匯出的檔案） | `default_locales: [source_only]` |
| 語言選取 | 勾選式，即時顯示欄數與大小估算 | `selectable_locales`（形態同 `i18n.export.selectable_locales`） |
| 系統欄 | `Source Locale`／`Product ID`／`Variant ID` **一律填值** | `always_emit_system_columns` |
| 🔴 fallback | **絕不**把回落值填進譯文欄——該語言沒有譯文就是空格 | `emit_fallback_values_forbidden: true` |
| 分檔 | 落在 handle 邊界 | `split_strategy: handle_boundary` |
| 交付 | 非同步 ＋ 通知／email；簽名連結 24h | `async_delivery`、`signed_url_ttl_hours` |
| 大檔門檻 | 任一商品變體數 > 100 ⇒ 改 email | `csv.export_email_threshold_variants`（61 §6.1，help） |

🔴 **`emit_fallback_values_forbidden` 的壞法**：匯出時把 `zh-Hant-TW` 缺譯的格用 `zh-Hant-HK` 的原文填上 ⇒ 商家原檔回灌 ⇒ 那些回落值變成**真的譯文**寫進 `translations` 表 ⇒ 缺譯狀態被永久洗掉，`i18n.fallback_hit` 指標歸零、翻譯進度顯示 100%，而實際上台灣站看到的是香港用詞。**這個 bug 一旦發生就無法還原**（沒有任何紀錄能區分「回灌的回落值」與「譯者真的這樣翻」）。

---

## H. ⭐ 商品 CSV / 庫存 CSV / 翻譯 CSV：三套的關係，以及多語言欄位放哪一套

### H.1 三套的定位（60 §5 ＋ 61 §6.1/6.2 ＋ 67 §E.6）

| | **商品 CSV**（本檔） | **庫存 CSV**（61 §6.2） | **翻譯 CSV**（67 §E.6） |
|---|---|---|---|
| 鍵 | `handle` ＋ 選項值組合／`Variant ID` | `handle` ＋ 選項值 ＋ `Location` | `(resource_type, resource_gid, field_key, locale, market)` |
| 範圍 | 商品線 | 庫存量 | **30 種資源**（頁面／選單／主題字串／通知範本／政策…） |
| 可寫面 | 商品與變體的全部欄位 | 🔴 **只有 `On hand (new)`**，五態全部唯讀 | 譯文 |
| 併發控制 | 逐行 transaction | 🔴 `On hand (current)` ＝ 官方寫進欄位語義的樂觀鎖 | 逐行 transaction ＋ `source_digest` |
| 空白語義 | 覆寫時洗掉（61 §6.1） | — | 不動作（67 §E.6） |
| **多語言欄** | ✅ **商品線 12 欄的 `[locale]` 版** | ❌ **禁止**（`forbidden_on: [inventory_csv]`） | ✅ 全部資源 |
| 分流依據 | 60 §5 匯出 modal 逐字：「**如果只需要更新庫存數量，請使用庫存 CSV 檔案**」（help） | | 67 §E.6 四條理由 |

**庫存 CSV 為什麼禁止多語言欄**：它的 `Title`／`Option {n} Name` 官方明載是「**僅供閱讀，不會更新**」（61 §6.2）⇒ 在那裡放譯文欄是雙重無意義，而且會讓「庫存 CSV 只寫 `on_hand`」這條不變量出現例外——不變量一旦有例外就不再是不變量。

### H.2 🔴 結論：**真相放 `translations` 表；兩套 CSV 都只是它的傳輸面**

```
唯一真相（source of truth）＝ translations 表（67 §C.2）
        ↑                                    ↑
   商品 CSV                              翻譯 CSV
   （商品線 12 欄，opt-in，預設關）      （30 種資源，全部欄位）
        └──────────  同一個 writer  ──────────┘
                Translations::Upsert
```

**「兩個都放會產生兩個真相來源」——這句話的正確版本是「兩個 writer 會產生兩個真相來源」。** 兩個**檔案格式**指向同一張表、走同一支 writer、套同一組語義鍵，是**兩個視圖**，不是兩份資料。落地成三條可驗收的約束：

1. **同一支 writer**：商品 CSV 的 `[locale]` 欄與翻譯 CSV 的 `translated_text` 走**同一個 service**，不得有第二條寫入路徑。
2. **CI 斷言**：對同一個 `(resource, locale, field)`，兩條路徑產生的資料列（含 `value_source`、`outdated`、稽核軌）**必須逐欄相同**。這條把「有沒有第二個真相」從紀律變成可執行測試（同 65 §B 對跨界點的做法）。
3. **語義鍵不複製**：商品 CSV 的譯文語義**引用** `i18n.import.*` 的鍵（`blank_means_unchanged`、`overwrite_existing_default`、`explicit_clear_token`…），不另立同名鍵。⇒ 67 改了，商品 CSV 自動跟著改，**不可能分岔**。

### H.3 為什麼商品 CSV **必須**能帶譯文（結構性理由，不是偏好）

67 §E.6 的四條理由都成立，但它們論證的是「翻譯不能**只**靠商品 CSV」，不是「商品 CSV 不能帶譯文」。反方向有一條硬的：

🔴 **翻譯 CSV 的鍵是 `resource_gid`，而 gid 在商品被建立之前不存在。**

⇒ 一個**全新的多語言目錄**（1000 個商品 × 3 語）用翻譯 CSV **在結構上做不到**：

```
翻譯 CSV 路徑：匯入商品（僅來源語言）→ 等 job 完成 → 匯出翻譯 CSV（取得 gid ＋ source_digest）
              → 商家填 → 再匯入        ⇒ 兩次上傳、一次往返、中間狀態是「上線了但只有一種語言」
商品 CSV 路徑：一次上傳                  ⇒ 資源與譯文在同一次寫入
```

而且翻譯 CSV **要求 `source_digest` 欄，缺欄整檔拒絕**（`i18n.import.require_source_digest_column: true`）——digest 是對**既有原文**算的，對還不存在的商品算不出來。⇒ 這不是「比較麻煩」，是**用不了**。

### H.4 分工（寫進 UI 文案與 §I.5 的搬家順序）

| 情境 | 用哪一套 | 為什麼 |
|---|---|---|
| 建立新目錄／從別的平台搬家／整批新增商品 | **商品 CSV（含譯文）** | 資源與譯文同一次寫入，不需要先有 gid |
| 大批改價／改庫存政策／改 SEO | **商品 CSV**（可不勾任何語言 ⇒ 43 欄） | 語言是 opt-in，不勾就不會多出 48 欄 |
| 只改庫存量 | **庫存 CSV** | 60 §5 官方明確要求分流；且只有它有 `On hand (current)` 樂觀鎖 |
| 送外部譯者／TMS｜翻頁面・選單・主題字串・通知範本｜回填過期譯文 | **翻譯 CSV** | 只有它有 `source_digest`／`status` 三值／跨 30 種資源；也只有它能出境再回來 |
| 店有 > 5 個語言 | **翻譯 CSV** | `over_max_locales_action: redirect_to_translation_csv` |

---

## I. Shopify 匯入器（我方自製）

**為什麼要自製**：60 §5 的匯入 modal 逐字——「使用我們推薦的其中一款應用程式，從其他平台匯入您的資料副本〔Matrixify — Built for Shopify〕」⇒ 官方把跨平台搬家導向第三方 app，**反向路徑（Shopify → 我方）不存在**。這是「吸引 Shopify 商家轉移」這條產品路徑的必要條件。

### I.1 欄名別名表（`accept_header_dialects`）

匯入器同時認得三套方言，**不得要求商家先改表頭**：

| 我方正規（＝E1 匯出名） | 也接受（E2 匯入範本名） |
|---|---|
| `Handle` | `URL handle` |
| `Body (HTML)` | `Description` |
| `Product Category` | `Product category` |
| `Published` | `Published on online store` |
| `Option{n} Name` / `Option{n} Value` | `Option{n} name` / `Option{n} value` |
| `Variant SKU` | `SKU` |
| `Variant Barcode` | `Barcode` |
| `Variant Price` | `Price` |
| `Variant Compare At Price` | `Compare-at price` |
| `Variant Taxable` | `Charge tax` |
| `Variant Tax Code` | `Tax code` |
| `Variant Grams` | `Weight value (grams)` |
| `Variant Weight Unit` | `Weight unit for display` |
| `Variant Inventory Tracker` | `Inventory tracker` |
| `Variant Inventory Qty` | `Inventory quantity` |
| `Variant Inventory Policy` | `Continue selling when out of stock` |
| `Variant Fulfillment Service` | `Fulfillment service` |
| `Variant Requires Shipping` | `Requires shipping` |
| `Image Src` / `Image Position` / `Image Alt Text` | `Product image URL` / `Image position` / `Image alt text` |
| `Variant Image` | `Variant image URL` |
| `SEO Title` / `SEO Description` | `SEO title` / `SEO description` |
| `Gift Card` | `Gift card` |
| `Cost per item` | `Cost per item`（兩份一致） |
| `Status` | `Status`（兩份一致） |
| `Unit Price *`（4 欄） | `Unit price *`（4 欄） |

🔴 **我方的正規欄名只有一套**（`canonical_dialect: chilllove_canonical`）。名稱衝突時取 **Shopify 匯出**那一套，理由是 tiebreak 不是偏好：①商家手上實際有的檔案是**匯出檔**，不是空白範本 ②`Handle` 這個名字同時出現在 Shopify 的**庫存 CSV**（61 §6.2）⇒ 三份官方文件裡有兩份用它。

🔴 **我方的匯出必須能原檔回灌**（`docs/templates/` 兩份檔案的表頭逐字相同，§附錄 A 第 10 項在斷言）。Shopify 用兩套欄名這件事是**缺陷不是特性**，不複製。

### I.2 Shopify 有、我方沒有的欄位 ⇒ 逐欄宣告處置，🔴 **沒有「靜默丟棄」**

| Shopify 欄 | 處置 | 理由 |
|---|---|---|
| `Option{n} Linked To` | `drop_with_report` | taxonomy 連動選項（E2 實測值 `product.metafields.shopify.color-pattern`），我方未實作 |
| `Google Shopping / *`（13 欄） | `map_to_marketing_attributes` | 30 §9-8 已規劃 feed 欄位組（`gtin`／`google_product_category`／`gender`／`age_group`／`custom_label_0-4`），這是它的落點。**不丟**——搬過來才發現 feed 屬性沒了會直接流失 |
| `Included / [Primary]`、`Included / International` | `drop_with_report` | market 別上架旗標，我方改由 market 設定表達（29 §1） |
| `Price / International`、`Compare-at price / International` | `drop_with_report` | 同上（market 別價格表） |
| `Variant Inventory Tracker = shipwire\|amazon_marketplace_web` | `drop_with_report`（欄位保留、值丟棄） | 我方不接這兩個第三方 tracker |
| `Fulfillment service = <第三方>` | `map_to_manual_with_report` | E2 實測有 `music-man-fulfillment`。改 `manual` 並在報告列出，讓商家知道要重接 |
| `X (product.metafields.ns.key)` 形態 | `upsert_by_definition` | E1／E2 都實測有（`Fecify product ID (…)`／`Color (…)`）。依 metafield 定義寫入；🔴 型別不在 `i18n.translatable_metafield_types` 白名單者不得帶 `[locale]` 後綴（67 §B.4） |
| 其餘未知欄 | `report_never_silent` | |

### I.3 我方有、Shopify 沒有的欄位 ⇒ 建立時的預設值**宣告在 limits，不散在程式碼**

| 我方欄 | Shopify 檔案裡沒有時 | 鍵 |
|---|---|---|
| `Source Locale` | 假定為目標店鋪的來源語言 ＋ **報告告警** | `source_locale_absent_action: assume_shop_source_and_warn` |
| `Product ID` / `Variant ID` | 空白 ⇒ 走 handle upsert ＋ 選項值組合比對（Shopify 語義） | `variant_identity_without_id` |
| 全部 `[locale]` 欄 | 欄缺席 ⇒ **不建立任何譯文**（不是建立空譯文） | `defaults_on_create.locale_columns: absent_means_unchanged` |
| `Status = UNLISTED` | 🔴 **永遠不會從 Shopify 檔案進來**（本尊只有三態） | `never_infer_unlisted: true` |

🔴 **`UNLISTED` 不得從 `Published = FALSE` 推導**：`Published` 管的是「有沒有上架到線上商店這個管道」，`UNLISTED` 管的是「**可購買但不可被發現**」（`product.purchasable_statuses` 含 UNLISTED、`discoverable_statuses` 不含，13 §F1.2）。把 `Published=FALSE` 推成 UNLISTED ⇒ 一批本來是草稿的商品變成**可以被下單**的商品。

### I.4 值域映射（大小寫不敏感比對，輸出一律我方 enum 的大寫形態）

```
status              active→ACTIVE  draft→DRAFT  archived→ARCHIVED   (UNLISTED 不可推導)
inventory_policy    deny→DENY      continue→CONTINUE                (E1 用小寫、E2 用大寫)
inventory_tracker   shopify→chilllove
boolean             TRUE/true/1/yes → true ；FALSE/false/0/no/空 → false
```

（E1 與 E2 對同一語義同時用了 `deny` 與 `DENY`、`true` 與 `TRUE` ⇒ 大小寫不敏感是必須的。）

### I.5 一次性搬家的順序（`migration_order`）

```
① 商品 CSV（含譯文）  ⇒ 建立商品／變體／媒體／SEO ＋ 商品線譯文
② 庫存 CSV            ⇒ 各地點的 on_hand（Shopify 商品 CSV 的 Inventory quantity 只有單一地點）
③ 翻譯 CSV            ⇒ 非商品線資源（頁面／選單／政策／主題字串）的譯文
```

🔴 **倒過來做，第 ③ 步的 `resource_gid` 還不存在**（§H.3）。這條順序不是建議，是依賴。

---

## J. `config/limits.yml` 新增鍵（本輪已落鍵，§23 `csv:`）

**新增一個頂層區塊 `csv:`**，20 個一級鍵 ＋ 4 個子區塊（`multilingual` / `product_import` / `product_export` / `shopify_import`）。

🔴 **本區塊在本輪之前不存在，但已經被兩個地方引用了**：

| 引用處 | 引用的鍵 | 實況 |
|---|---|---|
| 67 §E.6(b) ＋ `i18n.export.max_upload_mb_key` | `csv.product_max_upload_mb` | 🔴 **懸空**——`yaml.safe_load` 取不到 `csv` 頂層鍵 |
| 61 §9.5 | `csv.product_max_upload_mb`（標為「✅ 已有」） | 🔴 實際指的是 `media.csv_max_upload_mb`（值相同但語義是媒體匯入） |

⇒ 本輪補上真鍵。**`media.csv_max_upload_mb` 不動**（它是媒體匯入的上限，數值相同、用途不同）。

**既有鍵一律沿用、不重複定義**（這是 §H.2 約束 3 的機械保證）：

| 既有鍵 | 本檔引用處 |
|---|---|
| `i18n.import.blank_means_unchanged` / `overwrite_existing_default` / `overwrite_scope` / `explicit_clear_token` / `absent_*` | §F.1、§F.2 |
| `i18n.export.selectable_locales` / `async_delivery` | §G |
| `i18n.locale_tag_format` / `normalize_tag_case_on_write` / `max_shop_locales` | §D.2、§E.2 |
| `i18n.translatable_metafield_types` | §I.2 |
| `i18n.source_locale_per_resource`（`false`） | §C.3 |
| `money_boundary.decimal_string_regex` / `decimal_parse_type` / `decimal_parse_excess_precision_action` / `storage_scale_multiplier` | §F.3、§G |
| `product.status_values` / `purchasable_statuses` / `discoverable_statuses` | §I.3 |
| `product.title_max_chars` / `content.seo_title_max_chars` / `seo_meta_description_max_chars` | §C.1 |
| `catalog_flow.default_variant_liquid_title`（`Default Title`） | §D.4 |
| `media.csv_max_upload_mb` | 不動，見上 |

---

## K. 驗收清單

### K.0 對照 `docs/specs/11` §0 七維度

| 維度 | 本模組的最低標準 |
|---|---|
| **1 安全** | 匯入需 `staff` 權限且過 shop scope；🔴 **CSV 一律當不可信輸入**——`Body (HTML)` 與其**所有譯文欄**走與商品描述同一條淨化管線（譯文最容易被當成「已經是自家內容」而漏掉）；🔴 **CSV injection 防護**：匯出時對以 `=` `+` `-` `@` `\t` `\r` 開頭的儲存格加前綴逃逸（商家把匯出檔在 Excel 打開就是一次公式執行）；上傳走病毒掃描與 MIME 檢查；簽名下載連結 24h 且綁 `shop_id` |
| **2 資料完整** | 逐行獨立 transaction；create 分支冪等 key ＝ `UUID v5(catalog_import,[job_id,row_no])`（63 §A.3）；`Source Locale` 檔級不變量；同一 handle 內選項值譯文衝突 ⇒ 整個商品失敗；🔴 **`[locale]` 欄與翻譯 CSV 共用同一支 writer**，CI 斷言兩條路徑寫出的列逐欄相同（§H.2） |
| **3 併發** | 匯入期間商家在後台改同一個商品 ⇒ 以 `lock_version` 樂觀鎖擋（63 §A.4）；同一份檔案重複上傳 ⇒ 冪等 key 兜底；handle 配號用唯一索引重試 |
| **4 效能** | streaming parse／streaming write，不整檔載入；1 萬列 × 67 欄的匯入在背景 job 完成且進度可 poll；🔴 匯出的 N+1：譯文必須**一次批次載入**（每 1000 列 ≤ 一次 `translations` 查詢），不得逐列查 |
| **5 可觀測** | 結構化日誌帶 `request_id`＋`shop_id`＋`import_job_id`＋`row_no`；指標 `csv.import.rows_{ok,failed}`、`csv.import.{base_wipe,translation_clear,translation_overwrite}_count`、`csv.import.unknown_column_count`、`csv.export.locale_count`、`csv.export.bytes`；🔴 每一次金額跨界（X4／X6）落 65 §K 維度 5 要求的欄位 |
| **6 測試** | 見 K.1；🔴 **金額代碼 100% 覆蓋**（11 §0 維度 6）——含 zero-decimal 幣別的 CSV 往返（65 §H.1 的 JPY／TWD／KRW 必進矩陣） |
| **7 合規/隱私** | 匯出檔含商家內容 ⇒ 走既有匯出授權與稽核；🔴 **匯入的原始檔要有保存期限與 purge**（它可能含 PII——商家把顧客資料貼進描述）；匯出檔的簽名連結不得進日誌 |

### K.1 逐條驗收

| # | 項目 | 通過條件 |
|---|---|---|
| **CSV-1** | Shopify 匯出檔原檔可讀 | 把 E1（44 欄、`Handle`／`Body (HTML)` 方言、LF、`'`-前綴的 SKU）直接上傳，**零改動**建立出 1 個商品 1 個變體；報告列出被丟棄的欄與原因 |
| **CSV-2** | Shopify 匯入範本原檔可讀 | E2（57 欄、`URL handle`／`Description` 方言、CRLF、17 列含 12 變體與數位商品）直接上傳，建立出 3 個商品共 16 個變體；`Compare-at price = 80`（零位小數）**不得**被拒 |
| **CSV-3** | 多行儲存格 | `Body (HTML)` 含 `\n` 的列正確解析（不錯位）；匯出後再匯入，該欄逐位元組相同 |
| **CSV-4** | 欄名 locale 解析 | `Title [zh-Hant-HK]`／`Title [en-HK]` 正確路由；`Title [en]`（無地區）拒絕；`Handle [en-HK]`／`Tags [en-HK]`／`Variant Price [en-HK]` 各自拒絕且錯誤訊息指出分類 |
| **CSV-5** | 🔴 來源語言雙欄 | 同時有 `Title` 與 `Title [zh-Hant-HK]`（＝來源語言）⇒ **整檔拒絕**，不做仲裁 |
| **CSV-6** | 🔴 兩套空白語義 | 表格測試：{基礎欄, locale 欄} × {空白, 有值, `__CLEAR__`} × {勾覆寫, 不勾} 共 12 格，逐格斷言 §F.1 的結果。🔴 **`[locale]` 欄空白 ＋ 勾覆寫 ⇒ 譯文不變**（這一格錯了就是回到 68 那條被推翻的語義） |
| **CSV-7** | 兩個旗標不連動 | 勾「覆寫商品」而不勾「覆寫翻譯」⇒ 既有譯文一筆未動；反之亦然 |
| **CSV-8** | 🔴 `Default Title` | `Option1 Value = Default Title` 那一列帶任何 `Option1 Value [*]` ⇒ 該列失敗。配套：無變體商品匯入後，Ella 主題的 `variants.first.title != 'Default Title'` 判定不翻轉（63 §B.2 的 golden theme 迴歸） |
| **CSV-9** | 選項值譯文 | 同一 handle 內同一選項值的譯文重複且**相同** ⇒ 通過；**不同** ⇒ 整個商品失敗（不是最後一列勝） |
| **CSV-10** | 🔴 變體身分 | ①有 `Variant ID` ⇒ 改選項值後變體 id 不變、譯文保留 ②無 `Variant ID` ⇒ 複製 Shopify 語義（重建變體）且預覽階段警告「將丟失 M 筆譯文」 |
| **CSV-11** | 🔴 金額往返（X4／X6） | 幣別矩陣 **JPY／TWD／KRW／HKD／USD**（65 §H.1）：`storage → 匯出字串 → 匯入 → storage` 恆等。JPY `148000` ⇒ `"1480.00"` ⇒ `148000`。🔴 匯出檔裡**不得出現 `148000`** |
| **CSV-12** | 金額拒收 | `19.999`（三位小數）⇒ 該列失敗且**不 round**；`1,29`（歧義逗號）⇒ 該列失敗；`1,290`（嚴格千分位）⇒ 清洗為 1290 |
| **CSV-13** | 🔴 單位價格不是金額 | `Unit Price Total Measure = 500.00` 匯入後**不得**變成 50000；型別斷言（傳 `Money::Decimal` 進去 ⇒ `TypeError`，65 §C.1） |
| **CSV-14** | 🔴 匯出不填 fallback | 某商品缺 `zh-Hant-TW` 譯文 ⇒ 匯出該格為**空**；把該檔原檔回灌 ⇒ `translations` 表**沒有**新增該列，翻譯進度不變 |
| **CSV-15** | 匯出可原檔回灌 | 匯出 → 不改任何一格 → 匯入（勾兩個覆寫）⇒ 資料庫**零變更**（含 `updated_at`）。這條同時證明表頭一致與 fallback 不落地 |
| **CSV-16** | 欄數爆炸 | 3 語 ⇒ 67 欄；勾第 6 個語言 ⇒ UI 擋下並提示改用翻譯 CSV；欄數與大小估算與實際產出誤差 < 10% |
| **CSV-17** | 分檔 | 超過 15 MB 的匯出分檔，**每個分檔的每個 handle 都以其商品層列開頭**（無孤兒列） |
| **CSV-18** | 預覽三類分開 | 一份同時觸發三類破壞的檔案 ⇒ 預覽顯示三個獨立數字；任一類 > 20% ⇒ 二次確認；三類都寫稽核軌且可查到舊值 |
| **CSV-19** | 未知欄不靜默 | 含 5 個未知欄的檔案 ⇒ 報告逐欄列出（欄名、命中列數、處置），匯入不失敗 |
| **CSV-20** | 🔴 `Source Locale` | ①缺欄 ⇒ 假定店鋪來源語言 ＋ 告警 ②全檔一致但與店鋪不符 ⇒ 整檔拒絕 ③逐列不同 ⇒ 整檔拒絕 |
| **CSV-21** | 🔴 CSV injection | 標題為 `=cmd|' /C calc'!A0` 的商品，匯出後該格以逃逸前綴開頭；匯入時前綴被還原（往返恆等） |
| **CSV-22** | 識別碼清洗 | `'7340032875324` ⇒ SKU 存成 `7340032875324` 且報告計數；標題 `'Tis the season` ⇒ **不**剝除 |
| **CSV-23** | 🔴 單一 writer | CI：對同一 `(product, locale, field)`，經商品 CSV 與經翻譯 CSV 寫入 ⇒ `translations` 列逐欄相同（含 `value_source`／`outdated`／稽核軌） |
| **CSV-24** | 庫存 CSV 無語言欄 | 庫存 CSV 帶任何 `[locale]` 欄 ⇒ 整檔拒絕 |
| **CSV-25** | 範本檔本身 | `docs/templates/*.csv` 兩份的 §附錄 A 十項驗證全綠（CI 跑，範本檔改了就要重跑） |

---

## L. 待查證（V-310 起）

| # | 項目 | 為什麼查不到 | 當前處置 | 影響 |
|---|---|---|---|---|
| **V-310** | Shopify 的匯入器是否**同時**接受匯出欄名與範本欄名 | 兩份檔案在手（E1／E2 實測欄名不同），但官方文件沒說匯入器認得哪幾套 | 我方**兩套都認**（`accept_header_dialects`），正規只有一套 | §A.1、§I.1 |
| **V-311** | 譯文的字面值若剛好是 `__CLEAR__` | 自 67 §E.6 繼承的窟窿；本檔**不自創逃逸語法**（自創會與 67 分岔） | 登記為已知限制（`clear_token_not_escapable: true`）；要解必須在 67 解 | §F.1 |
| **V-312** | Shopify 匯出 zero-decimal 幣別（JPY／KRW）時，價格欄輸出幾位小數 | 手上的 E1 是 HKD 商店 | 我方匯入接受 0–2 位（`money_accept_regex`）⇒ 兩種都收；匯出恆兩位（65 §G） | §F.3 |
| **V-313** | Shopline 的 `(DO NOT EDIT)` 欄在匯入時被改動會怎樣（拒絕／忽略／照收） | 只有範本檔，沒有它的匯入行為文件 | 我方系統唯讀欄**只讀不寫**，被改動時以報告告警而非拒絕（保守：拒絕會擋掉「商家只是重排了欄」這種無害情形） | §C.3 |
| **V-314** | 一份 CSV 能否同時建立**多個地點**的庫存 | 61 §6.1 明載商品 CSV 的 `Inventory quantity` **僅單一地點**，但沒說多地點商店匯入時填的是哪一個 | 我方：商品 CSV 的 `Variant Inventory Qty` 只寫**預設地點**，多地點一律走庫存 CSV（§H.4） | §H.1 |

---

## M. 與既有規格的衝突登記（本檔只改 `limits.yml` 與新增 `docs/templates/*`，其餘只登記）

| # | 衝突 | 現況 | 本檔立場 | 誰該改 |
|---|---|---|---|---|
| **M-1** | 🔴 **locale 碼是否帶地區** | 67 §A.4：「`en` 英文（無地區）……需要地區時是 `en-HK`／`en-SG`，由 market 推導，**不預先建立**」；67 §C.1 註 1：「**不得**為了表達『香港的繁體中文』而建 `zh-Hant-HK`」；`i18n.launch_locales: [zh-Hant, zh-Hans, en]` | 🔴 **2026-08-13 裁定：locale 一律「語言＋地區」**（`en-HK`／`zh-Hant-HK`／`zh-Hant-TW`）。本檔的欄名規則、範本檔、`csv.multilingual.locale_tag_requires_region` 全部依裁定寫。**本檔不改 67**（另有 agent 在改）。⚠ 若 67 最終沒有依裁定改，本檔的 §D 與範本檔要一起回退——**不得只改一邊**，那會讓 `Title [zh-Hant-HK]` 路由到一個不存在的 `shop_locale` | **67 §A.4／§C.1 ＋ `i18n.launch_locales`** |
| **M-2** | **`csv.*` 鍵不存在卻被引用** | 67 §E.6 的 `max_upload_mb_key: csv.product_max_upload_mb`；61 §9.5 標「✅ 已有」 | ✅ **本輪已修**：新增 `csv:` 頂層區塊（§J）。61 §9.5 的那一列描述仍不準（它指的是 `media.csv_max_upload_mb`），但 `docs/research/*` 是證據不是結論，**不改** | 無（本列即修正紀錄） |
| **M-3** | **13 §F6 只寫「一套 CSV 匯入」** | 13 §F6：「欄位對齊 Shopify CSV 格式（遷移友好）」，未區分商品／庫存／翻譯 | 三套已由 63 §L-8（商品／庫存）與 67 §E.6（翻譯）拆開，本檔 §H 補上三者關係與分工。13 §F6 需回寫（它同時還缺多語言欄與兩套空白語義） | **13 §F6** |
| **M-4** | **`Variant ID` 這種穩定主鍵，Shopify 沒有** | 61 §6.1 明載：改動 `Option{n} Value` ⇒ 刪除既有變體 ID 並產生新 ID；我方「必須複製這個語義」 | ✅ **兩者並存**：有 `Variant ID` 走穩定主鍵（我方擴充，E3 的做法），沒有才複製 Shopify 的破壞性語義。🔴 多語言把這條的成本從「訂單歷史對不上」提高到「訂單歷史對不上 **＋ 譯文消失**」（§E.4） | 無（本檔定案） |
| **M-5** | **商品 CSV 帶譯文 vs 67 §E.6「翻譯是第三套」** | 67 §E.6 理由 1 明確反對「硬塞進商品 CSV」 | ✅ **不衝突，但必須寫清楚**：67 反對的是把商品 CSV 當成譯文的**儲存**；本檔把它當成同一張表的第二個**傳輸面**，並以「同一支 writer ＋ CI 斷言 ＋ 不複製語義鍵」三條約束保證不分岔（§H.2）。裁定要求它存在，§H.3 給出它**必須**存在的結構性理由（新目錄用翻譯 CSV bootstrap 不了） | 無（本檔定案；67 §E.6 可加一行交叉引用，但本輪不改 67） |
| **M-6** | **`media.csv_max_upload_mb` 與 `csv.product_max_upload_mb` 同值不同義** | 兩處都是 15 | 登記。**不合併**——媒體匯入與商品匯入是兩個功能，日後任一方調整不該連動 | 無 |

---

## 附錄 A · 範本檔的可重跑驗證

`docs/templates/` 兩份 CSV 由一支 Python 腳本產生（腳本不入庫，同 67 附錄 A 的先例：它只是本檔 §C／§D／§E 的直譯）。驗證以 Python `csv` 模組重新解析，**十項全綠**：

| # | 斷言 | 結果 |
|---:|---|---|
| 1 | 每一列的欄數 == 表頭欄數 | 兩檔皆 **67 欄** |
| 2 | 表頭無重複欄名 | ✅ |
| 3 | 每個 `[locale]` 欄的基礎欄都在 `translatable_columns` 白名單內，且標籤符合「語言（-script）-地區」 | 24 個譯文欄全過 |
| 4 | 金額欄（`Variant Price`／`Variant Compare At Price`／`Cost per item`）全部符合 `^-?\d+\.\d{2}$`，無 cents、無千分位、無科學記號 | 每檔 15 格 |
| 5 | 每個 handle 的**首列** `Title` 非空；**續列**的 14 個商品層欄**及其 `[locale]` 欄**全部留白 | ✅ |
| 6 | `Option1 Value = Default Title` 的列，其 `Option1 Name [*]`／`Option1 Value [*]` 全部為空 | ✅ |
| 7 | `Source Locale` 全檔一致 == `zh-Hant-HK` | ✅ |
| 8 | 選項值譯文映射無矛盾（同一 (handle, 選項, 值, locale) 不出現兩個不同譯文） | 8 筆映射 |
| 9 | 存在多行儲存格與內嵌雙引號；`csv.reader` → `csv.writer` 往返後**逐位元組相同** | 匯入範本 5 格多行／2 處 `""`；匯出範例 4 格多行／2 處 `""` |
| 10 | 兩份檔案的**表頭完全相同**（⇒ 匯出檔可原檔回灌，§I.1） | ✅ |

**量測結果**：

| 檔案 | 位元組 | 表頭欄數 | 資料列 | 邏輯列（含表頭） | 實體行 | BOM | CRLF |
|---|---:|---:|---:|---:|---:|---|---|
| `product-import-template.csv` | 6366 | **67** | **9** | 10 | 24 | 無 | 無（LF） |
| `product-export-sample.csv` | 5256 | **67** | **7** | 8 | 16 | 無 | 無（LF） |

（「實體行 > 邏輯列」正是 §B.1 那條「儲存格內換行合法」的直接證據——以「一行一列」切割這兩個檔案會分別得到 24 與 16 列，全部錯位。）

**欄數公式核對**：`43（基礎） + 12（可翻譯） × 2（來源語言以外的語言） = 67` ✅

**範本檔的教學內容**（比照 Shopify 範本的教學性質，內容自編，不抄 E1／E2／E3 的範例資料）：

| 商品 | 形態 | 教到什麼 |
|---|---|---|
| `handcrafted-soy-candle` | 2 選項 × 4 變體 ＋ 2 個純圖片列（6 列） | 重複列、商品層留白、選項值譯文只填第一次出現、純圖片列、`Body (HTML)` 多行 ＋ 內嵌雙引號 |
| `rose-body-oil-100ml` | 單變體（2 列） | 🔴 `Default Title` 契約（選項譯文必須留白）、單位價格四欄（看起來像金額但不是） |
| `aroma-blending-workshop-online` | 數位商品（1 列） | 不需運送、不追蹤庫存、`CONTINUE`、`DRAFT` ＋ `Published=FALSE`、`zh-Hant-TW` 整欄未翻（示範「空白＝不動作」） |
| `candle-duo-gift-set`（僅匯出範例） | 單變體 | 🔴 `Status = UNLISTED`（我方四態的第四態，Shopify 沒有）、系統欄已填 GID |

🔴 **範本檔裡刻意留白的格不是漏填**：`Body (HTML) [zh-Hant-TW]`、`SEO Description [zh-Hant-TW]`、部分 `Image Alt Text [zh-Hant-TW]` 全部是空的，用來示範「部分翻譯」這個**常態**，以及它在匯入時的語義（不動作，不是清空）。
