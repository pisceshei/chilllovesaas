# 70 — 商品 CSV 匯出入（多語言）·欄位契約·Shopify 匯入器

> ## ⭐ 本檔的一句話規則：**CSV 的語言維度＝語言，不帶地區**
>
> ```
> 內容維度（本檔）  shop_locales        en / fr / zh-Hant / zh-Hans      ⇒ 4 份內容 ⇒ CSV 4 組欄
> 呈現維度（62／67） market × locale     /en-hk /zh-hant-hk /zh-hans-hk
>                                       /en-ca /fr-ca /zh-hant-ca /zh-hans-ca ⇒ 7 條 URL 前綴
> ```
>
> 🔴 **加拿大的繁中與香港的繁中是同一格資料。** 7 條 URL 前綴只需要 4 個語言欄，不是 7 個。
> CSV 欄名是 `Title [zh-Hant]`，**永遠不是** `Title [zh-Hant-HK]`。防回退全文見 **§D.5**。

<!-- 🔴🔴 **本檔頭曾有一段「§D 欄名規則基於錯誤前提」的警示，本輪（2026-08-13 第二次）已執行修正並移除該警示。**
     沿革必須完整讀完再動手，否則會把修正再改回去：

     ① 初版（commit c2c1355）訂了 `locale_tag_requires_region: true`，欄名是 `Title [en-HK]`／`Title [zh-Hant-TW]`，
        範本檔 67 欄（24 個譯文欄，來源 zh-Hant-HK ＋ en-HK ＋ zh-Hant-TW）。
     ② 該版入庫時**自己標了缺陷**：它與 67 §A.1 直接衝突，而 67 是對的——67 §A.1 當時逐字寫著
        「一份 zh-Hant 譯文，兩個市場共用；市場差異走 translations.market_id」，
        並把「同一份繁中譯文存兩次」列為**事故**：商家改 HK 的商品標題，TW 不會變。
        （後記：其中「市場差異走 translations.market_id」半句其後依裁定 10 再變——該欄已於
          2026-08-13 刪除；「一份譯文兩市場共用」的主論點不受影響，反而更徹底。）
     ③ **根因是委派 prompt 的誤讀**，不是 agent 做錯：使用者 2026-08-13 裁定的是
        「**URL** 一律帶地區碼」（62 §I.2），prompt 把它讀成「**內容**也按語言＋地區鍵」。
     ④ 使用者隨後澄清（`ruling`，逐字）：「因為英文都是同一組英文，不同國家只要是使用英文，
        都是調用 `Product Name (English)`。**區別只是國家在後台設定的時候，會添加國家區分碼**。」

     🔴 **62 號自己早就寫過這個坑，而且寫得比本檔清楚**（62 §I.2 行 921，逐字）：
        「`zh-Hant` 這個標籤本身仍然存在，而且必須存在——它是 `platform_locales.tag`（**語言**的身分，67 §C.1）。
          恆帶地區改的是**輸出的碼**（hreflang 值、URL 前綴），**不是語言註冊表**。
          把 `zh-Hant-HK` 存進 `platform_locales` 是本次修改最容易犯的錯。」
        ⇒ 初版 70 犯的就是這一條被點名的錯，只是犯在 CSV 表頭而不是 `platform_locales`。
        **兩者是同一個錯**：CSV 表頭的語言標籤是 `shop_locales.tag` 的投影，不是 URL 前綴的投影。

     🔴 **防回退**：任何人看到 62／67 寫著「恆帶地區」而本檔的欄名不帶地區，**不要照 62／67 改本檔**。
        那兩份講的是**輸出的碼**（hreflang 值、URL 前綴），本檔講的是**內容的鍵**。
        兩者是不同維度，不是同一條規則的兩種寫法。要動這條，必須先推翻 67 §A.1 的「一份譯文多市場共用」。 -->

> **本檔要回答的三個問題**：①一份能同時吃 Shopify 匯出檔、又能表達 N 個語言的商品 CSV，欄名長什麼樣 ②多語言的商品欄位到底放商品 CSV 還是翻譯 CSV（兩個都放＝同一份資料兩個真相來源）③從 Shopify 搬過來的檔案，欄位對不上的地方怎麼處理。
>
> **實際範本檔在 `docs/templates/`**（本輪已依 4 語言配置重出），本檔 §附錄 A 有它們的可重跑驗證。上限值一律在 `config/limits.yml` §23（`csv:`）。
>
> 🔴 **本檔假設「無市場級覆寫」**：同一語言在不同市場的商品內容**完全一致**（香港英文 ≡ 加拿大英文）。
> 依據＝**2026-08-13 使用者裁定**（逐字：「不必考慮香港英文和加拿大英文的揭露事項因法規必須不同，所有的都會保持一致」）。
> ⇒ 本檔不定義任何市場級覆寫欄，理由與後果見 **§D.5(b)**。
> ⚠ ~~`docs/specs/67` 的 `translations.market_id` 欄位仍然存在且本檔不動它~~
> 🔴 **該欄位已依裁定 10 於 2026-08-13 移除**（67 §C.2 沿革註釋、§0.4 第 7 列）。本檔的核心假設
> （無市場級覆寫）被刪欄**加強**而非破壞——欄名規則、79 欄結構一字不變。
> 日後要市場覆寫：先依 67 §C.2 的復活條件恢復資料模型，再回頭改本檔（順序見 §D.5(b)）。
> <!-- 依裁定 10 修正，原文：「67 的 translations.market_id 欄位仍然存在且本檔不動它（那是 67 的範圍）——本檔只是不使用它，不是主張它該被刪。」成文時欄位確實還在；刪欄是 67 的裁定執行，不是本檔主張的實現。 -->

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
| 2 | 67 §A.4／§C.1：`en` 無地區、「**不得**為了表達『香港的繁體中文』而建 `zh-Hant-HK`」 | ✅ **完全採納，本檔不偏離**。<!-- 🔴 本列在 commit c2c1355 的原文是：「🔴 **被 2026-08-13 裁定推翻**：locale 一律「語言＋地區」（`en-HK`／`zh-Hant-HK`／`zh-Hant-TW`）。本檔的欄名規則依裁定寫。」——**那是誤讀**：裁定講的是 URL 與 hreflang 的**輸出碼**，不是內容的**儲存鍵**。使用者 2026-08-13 已澄清，見檔頭沿革 ③④。🔴 不得把本列改回「推翻」。 --> 裁定講的是**輸出的碼**（URL 前綴、hreflang 值，62 §I.2），不是**內容的鍵**。CSV 是內容 ⇒ 走 67 這一套（§D.5） |
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

🔴 **本輪新增：上面那 8 組成對欄名，我方匯入器現在全部認得**（§D.2b 的 `paren_display_name` 方言）。
初版把 `Product Name (English)` 判為「不可採用」，那是**在「一個語言會有多個地區變體」的錯誤前提下**做的判斷——
前提沒了之後，`(English) ↔ en` 是一對一的靜態映射，認得它的成本是十幾行對照，換到的是 **Shopline 商家零轉檔**。
🔴 **但我方輸出仍然只寫方括號**（理由與 locale 粒度無關，見 §D.1）。

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
| `csv.product_max_columns` | 512 | 🟡 **ours**，結構性護欄；推導見 §E.2.5 |
| `csv.multilingual.max_locales_per_file` | **4** | 🟡 **ours**；推導見 §E.2.3（判準＝譯文欄不得多過基礎欄）<!-- 🔴 初版值為 5。本輪改為 4：初版把 `R = 48/43 = 1.12` 讀成「同量級所以可以」，本輪讀成「已經越線」。判準沒換，只是算清楚了。 --> |
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

### D.0 🔴 先把維度分清楚——這一節是本章其餘部分的前提

```
內容維度：一份內容一個鍵            鍵 = 語言        = shop_locales.tag        ← CSV 在這裡
呈現維度：一個 (市場,語言) 一條 URL   鍵 = 語言＋地區   = market × locale        ← 62 §I.2／67 §F.1 在這裡
```

使用者 2026-08-13 的實際配置，攤開來看**兩個維度的數字根本不一樣**：

| | 內容維度（CSV） | 呈現維度（URL／hreflang） |
|---|---|---|
| 香港市場 | — | `/zh-hant-hk`、`/zh-hans-hk`、`/en-hk` |
| 加拿大市場 | — | `/en-ca`、`/fr-ca`、`/zh-hant-ca`、`/zh-hans-ca` |
| **合計** | **4 組**（`en`／`fr`／`zh-Hant`／`zh-Hans`） | **7 條** |

🔴 **`/en-hk` 與 `/en-ca` 讀的是同一格 `Title [en]`。** 這就是使用者說的「英文都是同一組英文，區別只是國家在後台設定的時候會添加國家區分碼」——
**國家區分碼加在 URL 上，不加在內容上。**

⇒ 把 CSV 欄名寫成 `Title [en-HK]`／`Title [en-CA]` 會製造**兩格資料**，而它們**必須永遠相同**。
沒有任何機制能保證這一點 ⇒ 商家改了 `[en-HK]` 忘了改 `[en-CA]`，加拿大站的英文標題就停在上個版本，**而且不會報錯**（67 §A.1 把這個形態列為事故）。

### D.1 輸出用方括號、匯入兩種都認 —— 一條規則兩個方向

**先講結論，因為它與初版不同**：

| 方向 | 規則 | 為什麼 |
|---|---|---|
| **輸出**（匯出、範本檔） | **只產生** `Title [en]` 這一種形態 | 三條理由，見下表 |
| **匯入** | `[en]`／`[zh-Hant]`／`(English)`／`(Traditional Chinese)` **全部認得**，走同一張映射表 | 成本是十幾行對照，換到的是 **Shopline 商家零轉檔** |

<!-- 🔴 初版此節標題為「為什麼**不**抄 Shopline 的 `(English)`」，並列了五條理由，其中理由 1（「裁定 locale 一律語言＋地區
     ⇒ en-HK 與 en-SG 都叫 English 會撞名」）與理由 4（「zh-Hant-HK 與 zh-Hant-TW 都叫繁體中文」）**建立在錯誤前提上，本輪刪除**：
     內容鍵不帶地區之後，`en` 就只有一個、`zh-Hant` 也只有一個，**根本不存在撞名**。
     🔴 **理由 1／4 消失，恰恰是「可以認得 Shopline 欄名」這件事變成可能的原因**——
        Shopline 的成對欄名之所以在初版被判死刑，正是因為初版假設一個語言會有多個地區變體。
        那個假設沒了，`(English)` 與 `[en]` 就是**一對一**的，映射表是靜態的、不會歧義。
     ✅ 理由 2／3／5 與 locale 粒度無關，原樣保留（下表 1／2／3）。 -->

**輸出只用方括號的三條理由**（全部與 locale 粒度無關，所以本輪修正不影響它們）：

| # | 理由 | 具體壞法 |
|---|---|---|
| **1** | 🔴 **語言的顯示名本身就是文案** | E3 自己證明了這一點：它需要**第二列中文表頭**（`商品名稱 (英文)`）才能給中文使用者看。⇒ 同一欄有兩個名字 ⇒ 表頭是文案不是解析鍵。我方若拿它當輸出格式，就得決定 `(Traditional Chinese)` 還是 `(繁體中文)` 還是 `(繁中)`，而三者都「對」 |
| **2** | **違反「語言集合是資料不是列舉」**（67 §A.2，`i18n.launch_locales_is_seed_not_enum`） | 顯示名 ⇒ 需要一張 `locale → 顯示名` 對照表才能**組出**欄名。新增一個語言就要動那張表 ⇒ 裁定明文的「後台一次操作、不改程式碼」做不到。<br>🔴 **注意這一條只擋輸出，不擋輸入**：匯入的對照表是**有限且封閉**的（只需涵蓋 Shopline 實際用過的語言名），新增我方語言時**不需要動它**——因為新語言不會憑空出現在別人的舊檔案裡。**組出**欄名需要全集，**認得**欄名只需要對方用過的那些。這個不對稱就是「輸出嚴格、輸入寬鬆」能成立的原因 |
| **3** | **鐵律 9** | 欄名是互通性契約（要吃對方的檔案就必須認得對方的欄名，§D.2b／§I.1 照做），但**我方自己產生的欄名**沒有互通性義務，照抄就只是抄文案 |

### D.2 我方規則（輸出）

```
{基礎欄名}␣[{BCP-47 語言標籤}]
```

- 分隔：一個半形空格 ＋ 方括號。
- 標籤：**`shop_locales.tag` 原樣**，大小寫依 `i18n.normalize_tag_case_on_write`（語言小寫／script Title case）。
- 🔴 標籤**不得帶地區**（`csv.multilingual.locale_tag_forbids_region: true`）。`Title [en-HK]`／`Title [zh-Hant-TW]` 在表頭裡**一律拒絕**，理由見 §D.0／§D.5。

範例（本檔範本檔實際使用的 36 個譯文欄之四）：

```
Title [en]           Title [zh-Hant]      ← 🔴 若來源語言是 zh-Hant，這一欄非法（§D.3）
Body (HTML) [fr]     SEO Description [zh-Hans]
```

**🔴 為什麼是方括號而不是圓括號**（`observed`，本輪**重新驗證**，可重跑）：把 E1（44 欄）＋E2（57 欄）＋E3（62 欄）＝ **163 個表頭字串**全部掃一次——

| 字元 | 命中數 | 命中的欄名 |
|---|---:|---|
| `[` `]` | **0** | —（**空的命名空間**） |
| `(` `)` | **33** | `Body (HTML)`、`Weight value (grams)`、`Color (product.metafields.shopify.color-pattern)`、`Product Name (English)`、`Quantity (DO NOT EDIT)`… |
| `/` | 13 | `Google Shopping / Gender`… |
| `\|` `｜` `{` `}` `<` `>` `#` `@` `"` `:` `;` `~` `^` | 0 | — |

<!-- 重驗方式（2026-08-13 第二輪，與初版數字一致）：openpyxl 讀 E3 第 1 列（62 欄，trailing None 已剝除）、
     csv.reader 讀 E1／E2 第 1 列，串成 163 個字串後逐字元 `in` 判定。初版 163／0／33 三個數字**全部重現**。 -->

⇒ 圓括號在 Shopify 的表頭裡**已經有兩種意思**（單位註記 `(grams)`、metafield 路徑 `(product.metafields.…)`），在 Shopline 又是第三種（語言）。
**這正是我方輸出不能用圓括號的具體壞法**：`Body (HTML)` 的英文譯文欄會變成 `Body (HTML) (English)` ——**兩層圓括號，而外層與內層無法靠語法區分**。
解析器只能靠**寫死的清單**去判斷 `(HTML)` 是註記、`(English)` 是語言，那正是 §D.1 理由 2 要避免的 enum。

方括號零出現 ⇒ `Body (HTML) [en]` **一眼可解析**：`[…]` 一定是語言，`(…)` 一定不是。
`|` `{}` 也是空的，但方括號在 BCP-47／i18n 工具鏈（gettext、XLIFF 檔名慣例）裡更常見，且在 Excel 裡不會觸發任何特殊解讀。

### D.2b 🔴 匯入的欄名方言表（`accept_locale_header_dialects`）—— Shopline 商家零轉檔

匯入器對**語言後綴**同時認得兩種方言。與 §I.1 的**基礎欄名**方言表是**兩張獨立的表**，可以自由組合
（`Product Name (English)` ＝ Shopline 基礎欄名 ＋ Shopline 語言後綴；`Title (English)` 也合法）。

| 方言 | 形態 | 例 | 來源 |
|---|---|---|---|
| `bracket_tag`（**我方正規**） | `{欄} [{BCP-47}]` | `Title [en]`、`Body (HTML) [zh-Hant]` | ours |
| `paren_display_name` | `{欄} ({英文顯示名})` | `Product Name (English)`、`SEO Title (Traditional Chinese)` | E3（`alt`，observed） |

**語言顯示名 → 標籤的對照表**（`locale_display_name_aliases`，大小寫不敏感）：

| Shopline 顯示名 | 我方標籤 |
|---|---|
| `English` | `en` |
| `Traditional Chinese` | `zh-Hant` |
| `Simplified Chinese` | `zh-Hans` |
| `Japanese` / `Korean` / `French` / `German` / `Spanish` / `Thai` / `Vietnamese` / `Indonesian` / `Malay` | `ja` / `ko` / `fr` / `de` / `es` / `th` / `vi` / `id` / `ms` |

🔴 **這張表是封閉的、且只用於匯入**（`locale_display_name_aliases_import_only: true`）：
- **它不需要跟著我方的語言集合成長。** 商家可能拿來匯入的舊檔案只會出現 **Shopline 支援過的語言名**——新增我方語言不會讓別人的舊檔案多出一個語言名。⇒ 不違反 67 §A.2（那條講的是「組出」欄名需要全集）。
- **表裡沒有的顯示名 ⇒ 不猜、不模糊比對**，該欄照 `unknown_column_action: report_never_silent` 進報告。🔴 **絕不做 `startswith`／Levenshtein 之類的近似匹配**：`Product Summary (English)` 與 `Product Name (English)` 差三個字，猜錯就是把摘要寫進標題。
- 🔴 **顯示名解析出的標籤仍要過 `unknown_locale_column_action`**：`(Japanese)` 解析成 `ja`，但店鋪沒啟用 `ja` ⇒ **整檔拒絕**，與 `Title [ja]` 完全同路。方言只影響「怎麼讀懂欄名」，不影響「這個語言能不能寫」。

**為什麼值得做**（成本／效益是明確的）：成本＝一張十幾列的靜態對照表 ＋ 一條正則。
效益＝**Shopline 匯出檔可以原檔上傳**，商家不必先在 Excel 裡改 16 個表頭——而 §I 已經論證過，
「原檔就能吃」是這整個匯入器存在的理由（60 §5：官方把跨平台搬家導向第三方 app，反向路徑不存在）。
🔴 **我方的正規欄名仍然只有一套**（`canonical_dialect: chilllove_canonical`），匯出永遠只寫方括號。

### D.3 基礎欄（無後綴）＝ **來源語言**，不是「預設值」

```
Title              ⇒ 來源語言（本店＝ zh-Hant）的標題
Title [en]         ⇒ en 的譯文
Title [fr]         ⇒ fr 的譯文
Title [zh-Hant]    ⇒ 🔴 與第一列是同一格資料 ⇒ 整檔拒絕
```

🔴 **這條是「Shopify 匯出檔能原檔吃進來」的唯一理由**：一份沒有任何 `[locale]` 欄的檔案 ＝ 一份純來源語言的檔案 ＝ 就是 Shopify 匯出檔。若要求每欄都寫 `Title [zh-Hant]`，每個搬家的商家第一步都得先改表頭——而 60 §5 已經指出，我方做這個匯入器的**全部理由**就是降低搬家成本。

🔴 **同時出現無後綴欄與 `[來源語言]` 欄 ⇒ 整檔拒絕**（`source_locale_duplicate_column_action: reject_file`）。**不做仲裁**：任何「後者覆蓋前者」「非空者優先」的規則都會在某個商家的檔案上選錯，而且不會報錯。

### D.4 拒絕條件（五類，都是整檔或整列失敗，沒有「靜默忽略」）

| 條件 | 動作 | 鍵 | 理由 |
|---|---|---|---|
| `[locale]` 掛在**不可翻譯欄**上（`Handle [en]`、`Tags [en]`、`Variant Price [en]`） | 整檔拒絕 | `non_translatable_locale_column_action` | 靜默忽略 ⇒ 商家以為翻了。錯誤訊息要指出分類（識別碼／集合鍵／金額／URL） |
| 表頭出現**店鋪未啟用的語言**（含由顯示名解析出來的） | 整檔拒絕 | `unknown_locale_column_action` | 同上 |
| `Option1 Value = Default Title` 那一列帶了 `Option1 Value [*]` 譯文 | **該列失敗** | `default_title_translation_action` | 🔴 63 §B.2／67 §B.3-3 硬相容契約：翻成「預設標題」⇒ Ella 的 `variants.first.title != 'Default Title'` 判定翻轉 ⇒ 無變體商品渲染出空的變體選擇器，**M6 golden theme 驗收直接失敗** |
| 🔴 **標籤帶地區**（`Title [en-HK]`、`Title [zh-Hant-TW]`） | 整檔拒絕 | `locale_tag_forbids_region` | §D.5。<!-- 🔴 本列在初版是相反的（「標籤不帶地區 ⇒ 拒絕」，鍵 `locale_tag_requires_region`）。本輪整條翻面，理由見檔頭沿革。 --> 錯誤訊息必須指出正確形態並說明原因：「CSV 欄名用語言（`zh-Hant`），地區只出現在 URL。`/zh-hant-hk` 與 `/zh-hant-ca` 讀同一格資料」 |
| 同一語言出現兩次（`Title [en]` ＋ `Title (English)`） | 整檔拒絕 | `duplicate_locale_column_action` | 🔴 兩種方言指向同一個 `(欄, 語言)` ⇒ 與 §D.3 的來源語言雙欄是同一個問題（同一格資料兩個真相），處置也相同：**不仲裁** |

### D.5 🔴🔴 防回退：CSV 欄名**永遠不帶地區碼**

**(a) 規則本身**

```
🔴 CSV 表頭的語言標籤 ∈ shop_locales.tag，永遠是「語言(-script)」，永遠不帶地區。
   正則：^[a-z]{2,3}(-[A-Z][a-z]{3})?$        （csv.multilingual.locale_tag_regex）
   🔴 匹配 ^…-[A-Z]{2}$ 的一律拒絕，不論是匯入還是我方自己產生。
```

**(b) 🔴 若日後有人想加 `Title [en-HK]`，那代表資料模型改了，不是 CSV 格式改了**

這是本節存在的全部理由，所以講清楚：

| 想做的事 | 它真正需要的是 | CSV 該怎麼變 |
|---|---|---|
| 「香港英文和加拿大英文的標題要不一樣」 | **市場級覆寫**（67 §C.2 已依裁定 10 刪除該維度<!-- 依裁定 10（2026-08-13）修正，原文：「translations.market_id 非 NULL，67 §C.2／29 §2.2 的 Adapt」 -->，要先依其復活條件恢復資料模型） | ⚠ **那是一個新的資料維度進入 CSV**，不是「欄名多幾個字」 |

⇒ 三條連帶後果，任何一條都足以說明「這不是格式問題」：

1. **`[locale]` 欄的語義會變。** 現在 `Title [en]` 唯一對應 `translations(locale='en')`<!-- 依裁定 10（2026-08-13 刪欄）修正，原文：「translations(locale='en', market_id=NULL)」——市場維度已不存在，對應關係反而更乾淨 -->。加了市場維度之後，`Title [en]` 是「語言層」還是「所有市場的預設」？**這個問題在今天的格式裡不存在，加了地區欄才會出現**，而它沒有無爭議的答案。
2. **欄數從 `L` 倍變成 `L × M` 倍。** 4 語言 × 2 市場 ＝ 8 組譯文欄 ＝ 43 + 12×7 = **127 欄**；再開一個市場就是 163 欄。§E.2 的整個門檻推導要重做。
3. **§H.2 的「同一支 writer」約束會需要重新驗證**：翻譯 CSV 的 `market_handle` 欄現為**純格式相容欄**（恆空白，非空白拒收——67 §E.6(b)，依裁定 10）<!-- 依裁定 10 修正，原文：「翻譯 CSV 的鍵已經含 market（67 §E.6(b) 的 market_handle 欄），商品 CSV 目前不含」——刪欄後兩邊的鍵完全同構 -->，商品 CSV 亦不含 ⇒ 兩條路徑今天寫的是**同一種列**。加了市場維度之後才需要證明它們仍然一致。

🔴 **所以正確的做法是**：需要市場級覆寫時，**先在 67 號把資料模型與 admin 契約定下來**，再回頭決定商品 CSV 要不要承載它（很可能答案是「不要，走翻譯 CSV」，因為翻譯 CSV 已經有 `market_handle` 欄）。
**不得**在本檔悄悄把欄名正則放寬——那會讓一個資料模型變更偽裝成一個格式變更，而且**先落地的會是 CSV**，資料模型反而被 CSV 倒逼。

**(c) 本檔的現行假設與其依據**

```
假設：同一語言在所有市場的商品內容完全一致（無市場級覆寫）
依據：2026-08-13 使用者裁定（ruling，逐字）——
      「不必考慮香港英文和加拿大英文的揭露事項因法規必須不同，所有的都會保持一致」
```

⚠ ~~`docs/specs/67` 的 `translations.market_id` 欄位不受本假設影響，本檔也不動它~~
🔴 **該欄位已依裁定 10 於 2026-08-13 移除**（67 §C.2）——**砍欄的依據是裁定 10 本身＋MySQL nullable-UNIQUE 失效（SESSION-EXPORT §5.8），不是本檔**。
本段原本的防線（「不得拿本檔去砍 67 的欄位」）**在當時是對的**：格式假設不構成刪資料模型的理由；後來刪欄走的是正規程序（使用者裁定→67 §0.4 登記→同輪執行），防線沒有被違反。
<!-- 依裁定 10 修正，原文：「67 的 translations.market_id 欄位不受本假設影響，本檔也不動它：那個欄位服務的是 67 §C.2 與 29 §2.2 的 Adapt 能力（其他資源也用得到），本檔只是不使用它。🔴 商品 CSV 不帶市場維度 ≠ 市場覆寫能力該被刪掉——把這兩件事混為一談，就會有人拿本檔去砍 67 的欄位。」 -->

---

## E. 變體的表達與列 × 欄爆炸

### E.1 沿用 Shopify 的重複列（不自創）

```
第 1 列   ：商品層全部欄位 ＋ 第 1 個變體的變體層欄位 ＋ 第 1 張圖
第 2 列起 ：Handle 必須重複；商品層欄位必須留白；只填該變體的選項值／SKU／價格／重量／圖
純圖片列 ：只有 Handle ＋ Image Src ＋ Image Position ＋ Image Alt Text（＋ 其譯文）
```

依據 61 §6.1（help）。**格式相容比自創漂亮重要**——60 §5 的匯入 modal 逐字證明 Shopify 把跨平台搬家導向第三方 app，我方的反向路徑（吸引 Shopify 商家轉移）只有在「原檔就能吃」時才成立。

🔴 **商品層欄位在續列必須留白**這條，在多語言下要**連同它的 `[locale]` 欄一起**：`Title` 留白而 `Title [en]` 有值的列是**非法**的（該列會被判成一個沒有來源語言標題的商品層更新）。範本檔的驗證腳本（§附錄 A）第 5 項就在斷言這件事。

### E.2 ⭐ 欄數，以及寬表／長表的門檻

#### E.2.0 兩套基數，不要混用

<!-- 🔴 初版 §E.2 只有我方基數一套；commit c2c1355 的 commit message 卻用 Shopline 基數
     （2 語 62／3 語 70／5 語 86／8 語 110）向使用者提問。**兩套數字在同一個討論裡出現而沒有標示，
     是本輪最容易產生誤會的地方**，故本節把兩套都寫出來並標明各自的用途。 -->

| | 我方（本檔的規範基數） | Shopline E3（`alt`，對照用） |
|---|---|---|
| 不可翻譯欄 | 43 個基礎欄裡的 31 個 | **46** |
| 可翻譯**欄位** | **12** | **8** |
| 來源語言 | 用**無後綴**的基礎欄（§D.3） | 沒有這個概念，每個語言都有後綴 |
| 公式 | `43 + 12 × (L − 1)` | `46 + 8 × L` |

**兩套並排**（`observed`，E3 實測 62 欄 ＝ 46 + 8×2 ✅ 公式成立）：

| 語言數 L | 我方總欄數 | Shopline 基數 |
|---:|---:|---:|
| 1 | **43** ← 匯出預設；欄序對齊 Shopify 匯出 | 54 |
| 2 | 55 | **62** ← E3 實測值 |
| 3 | 67 | 70 |
| **4** | **79** ← 🔴 **本檔範本檔＝使用者實際配置** | 78 |
| 5 | 91 | 86 |
| 20（`i18n.max_shop_locales`） | 271 | 206 |

🔴 **本檔一律用我方基數（4 語言＝79 欄）**，因為範本檔、`column_count_formula`、`product_max_columns` 的推導全部是它。
Shopline 基數只在與 E3 對照時出現。**兩者在 4 語言處差 1 欄（79 vs 78），這個巧合不代表可以互換**——
差別是結構性的：我方的來源語言不佔後綴欄、可翻譯欄位多 4 個（`Type`／`Option{n} Name`／`Option{n} Value`／`Image Alt Text` 那一組）。

#### E.2.1 🔴 先說一件反直覺的事：**欄數與檔案大小都定不出門檻**

要訂門檻，得先知道**什麼會壞**。四個候選判準，逐一用實測檢驗：

| 候選判準 | 實測 | 能不能當門檻 |
|---|---|---|
| **A. 欄數硬上限** | `product_max_columns: 512` ⇒ L=40 才撞到 | ❌ **太遠**。訂在這裡等於沒訂 |
| **B. 檔案大小** | 見下表 | ❌ **平滑退化，沒有懸崖** |
| **C. Excel／人的可用性** | 43 個基礎欄本身就超過任何「舒適」欄數；**Shopify 官方範本 57 欄、0 個語言**（E2） | ❌ 判不出來。真正的痛不是欄數 |
| **D. 🔴 這份檔案由「幾個人」填** | — | ✅ **這才是判準**，見 §E.2.2 |

**判準 B 的實測**（以本檔範本檔為基準，含富文本描述；`csv.product_max_upload_mb: 15`）：

| 語言數 | 欄數 | 表頭 | 資料 | 15 MB 可容列數 |
|---:|---:|---:|---:|---:|
| 1 | 43 | 666 B | 388 B/列 | ~40,600 |
| 2 | 55 | 871 B | 556 B/列 | ~28,300 |
| 3 | 67 | 1,136 B | 711 B/列 | ~22,100 |
| **4** | **79** | **1,341 B** | **817 B/列** | **~19,300** |
| 5 | 91 | ~1,546 B | ~923 B/列 | ~17,000 |
| 8 | 127 | ~2,161 B | ~1,242 B/列 | ~12,700 |

**邊際成本：每多一個語言 ＝ +12 欄、表頭 +205 B、資料 +106 B/列。**

🔴 **兩件事要從這張表讀出來，而且初版讀錯了一件**：

1. ✅ **先撞到的一定是 15 MB，不是 `product_max_rows: 50000`** ——這一點初版是對的，但**它在 1 個語言時就已經成立**（40,600 < 50,000）。⇒ 15 MB 是這個功能的常態約束，**不是多語言引進的**。
2. 🔴 **初版說「語言數對檔案大小的影響是乘法的」——這是錯的。** 實測是**加法**（每語 +106 B/列，約當 1 語言列寬的 27%）。從 1 語到 8 語，容量從 4.06 萬列降到 1.27 萬列——**明顯，但沒有任何一點是懸崖**。⇒ **檔案大小不可能產生「N 語以下用寬表、以上用長表」這種門檻**，它產生的是「列數 × 語言數」的乘積約束。
   <!-- 🔴 初版原文：「⇒ **語言數對檔案大小的影響是乘法的，對列數是零**。」前半錯（是加法）、後半對。
        初版還寫「67 欄、三語……平均 575 位元組／列（表頭本身 1207 B）」——本輪重測為 711 B/列、1,136 B 表頭。
        差異來源：初版的範本檔譯文較稀疏。**兩次都是實測，以本輪為準（範本檔已改）**。 -->

#### E.2.2 ⭐ 真正的判準：寬表與長表的差別是**編輯迴圈的方向**

```
寬表（本檔）  一列 = 一個變體 × 全部欄位 × 全部語言     ⇒ 適合「一個人把一個商品填完」
長表（67 §E.6）一列 = 一個 (資源, 欄位, 語言)            ⇒ 適合「一個人把一個語言填完」
              9 欄固定，🔴 **不隨語言數成長**
```

⇒ **選哪一種，取決於這份檔案由一個人填、還是由多個人分工填。語言數只是這件事的代理變數。**

**而「多個人分工」有兩條硬後果，都不是美學問題：**

| # | 後果 | 具體 |
|---|---|---|
| **1** | 🔴 **寬表交給外部譯者 ＝ 連成本一起交出去** | 43 個基礎欄裡有 `Cost per item`（成本）、`Variant Inventory Qty`（庫存）、`Variant Barcode`／`Variant SKU`（供應鏈識別碼）。**長表的 9 欄沒有任何一欄是這些。**<br>⇒ 一旦檔案要**出境**，寬表在合規上就是錯的工具，**與它有幾欄完全無關**（`wide_form_forbidden_for_external_translators: true`） |
| **2** | 🔴 **寬表在結構上無法分工** | 4 個譯者要同時改同一份檔案的不同欄 ⇒ 只能序列化，或合併時手工對欄。**長表可以按 `(locale, resource_type)` 分檔**（67 §E.6(b) 既有） |

**兩個對照平台把答案夾在中間**（這是本節唯一的外部證據）：

| 平台 | 寬表帶幾個語言 | 出處 |
|---|---|---|
| **Shopline** | **2**，然後停住——它沒有出 5 語言的寬表範本 | E3（`alt`，observed） |
| **Shopify** | **0**。它的商品 CSV 完全不帶語言，翻譯 100% 走長表（8 欄 ＋ Status） | 61 §6.1／67 §E.6（`help`） |

⇒ **語言最多的那個平台選了長表；語言少的那個選了寬表。** 我方要兩種都做（§H.3 已論證商品 CSV **必須**能帶譯文——新目錄用長表 bootstrap 不了，因為 `resource_gid` 還不存在），
所以問題只剩：**寬表的線畫在哪。**

#### E.2.3 線畫在 4，推導如下

代理變數要能量化才有用。用**譯文欄與基礎欄的比值**：

```
R = 譯文欄數 / 基礎欄數 = 12 × (L − 1) / 43

L=2 → 0.28    L=3 → 0.56    L=4 → 0.84    L=5 → 1.12    L=6 → 1.40
                                    ↑ 最後一個 R < 1     ↑ 譯文欄首次多過商品欄
```

**判準：`R < 1`** ——譯文欄不得多過基礎欄。
- `R < 1` ⇒ 檔案的主體仍是**商品資料**，譯文是附掛的 ⇒「商品 CSV」這個名字還成立。
- `R ≥ 1` ⇒ 譯文欄多過商品欄 ⇒ 這份檔案**已經是一張攤平的翻譯表**，而攤平的翻譯表已經有一套專用格式（長表，9 欄，不隨語言成長）。

⇒ **`csv.multilingual.max_locales_per_file: 4`**（R 首次 ≥ 1 的前一個整數）。

🔴 **三條必須跟著寫進來的誠實註記**：

1. **這個判準不是本輪為了配合使用者的 4 語言反推出來的——它上一輪就在規格裡。** 初版原文逐字：
   「12 個可翻譯欄 × 5 語 ⇒ 48 個譯文欄，**已與 43 個基礎欄同量級**；超過這裡，這份檔案就不再是『商品 CSV』而是一張攤平的翻譯表」。
   **本輪沒有換判準，只是把「同量級」這句話算清楚**：48 > 43，`R = 1.12` ——**它不是「同量級所以可以」，它是「已經越線」**。初版把線畫在 5（含），是把 `R ≥ 1` 的那一格算進了允許範圍。
2. 🔴 **門檻（4）剛好等於使用者的配置（4），這件事本身要標出來。** 使用者卡在**最後一格**：現在合法，**開第 5 個語言就會撞上**。
   ⇒ UI 不能只在超過時才講話（見 §E.2.4）。也**不得**因為「使用者剛好是 4」就覺得這條規則已經被驗證過——它沒有，它只是還沒被觸發。
3. **這條是 `ours`，是判斷不是量測。** §E.2.1 已經證明沒有任何機械懸崖可以當依據。誠實的說法是：
   **4 這個數字比兩個對照平台的寬表都寬**（Shopline 2、Shopify 0），而 `R < 1` 是一條能講清楚、能重算、且在語言數以外的維度變動時仍然可算的規則
   （例如日後可翻譯欄從 12 增加到 14，門檻會自動變成 `43/14 + 1 = 4.07 ⇒ 4`，不需要重新拍腦袋）。

#### E.2.4 超過門檻怎麼辦：**不是錯誤，是換工具**；而且要提早講

🔴 `over_max_locales_action: redirect_to_translation_csv` ——**上限是「一份檔案能帶幾個語言」，不是「店裡能有幾個語言」**。
一家 8 個語言的店照樣可以匯出商品 CSV，只是一次帶 ≤4 個。

**後台的語言勾選器（匯出 modal）必須做到四件事**：

| # | 行為 | 鍵 | 為什麼 |
|---|---|---|---|
| 1 | **即時顯示欄數與檔案大小估算**（勾一個變一次） | `locale_picker_live_estimate: true` | `column_count_formula` 就是給它用的。誤差要 < 10%（CSV-16） |
| 2 | 🔴 **勾到第 4 個時就預告**，不是等到第 5 個才擋 | `locale_picker_warn_at_max: true` | 使用者恰好卡在最後一格（§E.2.3 註記 2）。等他把工作流建立在寬表上，第 5 個語言才告訴他要換工具，**換工具的成本已經從「選一個選項」變成「改流程」** |
| 3 | 🔴 **擋下時同時給出口**，文案要說明**為什麼**而不只是「超過上限」 | `over_max_locales_action` | 例：「商品 CSV 一次最多帶 4 個語言——再多，譯文欄就會多過商品欄，這份檔案其實是一張翻譯表了。<br>請選 4 個語言，**或改用翻譯 CSV**（不限語言數，且不含成本與庫存欄）」 |
| 4 | 🔴 **偵測到「要交給外部譯者」的意圖時，即使未超過門檻也推薦長表** | `suggest_long_form_for_external_translation: true` | §E.2.2 後果 1：**出境是與語言數無關的獨立理由**。2 個語言的寬表交給外部譯者，一樣洩漏全部商品成本 |

🔴 **兩種形態在 UI 上必須呈現為「同一次匯出的兩種輸出形狀」，不是兩個埋在不同選單裡的功能**
（`export_form_choice_is_single_control: true`）。商家在同一個 modal 裡選「寬表（可直接編輯商品）／長表（適合送譯）」，
否則他根本不會知道長表存在——而 §E.2.2 的兩條硬後果，是他**不知道就會踩**的那種。

#### E.2.5 其餘上限（未變）

**`csv.product_max_columns: 512`**（ours，結構性護欄）。它**不是**多語言的實際約束——先撞到的一定是 15 MB（§E.2.1）。
推導保留給日後的 metafield 欄與 Google 屬性欄：`43 + 12 × (4 − 1) = 79`，離 512 還很遠，這是刻意的。

🔴 **分檔一律落在 handle 邊界上**（`split_strategy: handle_boundary`）：續列離開它的首列就失去商品層欄位，整組變成孤兒列。這條比檔案大小重要。

### E.3 選項值的譯文是 **product-scoped 映射**，不是列值

一個 2 選項 × 4 變體的商品，`Option1 Value` 只有 2 個相異值卻出現 4 次。若把 `Option1 Value [en]` 當成列值，同一個「白茶」要填 2 次。

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

🔴 **`emit_fallback_values_forbidden` 的壞法**：匯出時把 `fr` 缺譯的格用來源語言（`zh-Hant`）或 `en` 的原文填上 ⇒ 商家原檔回灌 ⇒ 那些回落值變成**真的譯文**寫進 `translations` 表 ⇒ 缺譯狀態被永久洗掉，`i18n.fallback_hit` 指標歸零、翻譯進度顯示 100%，而實際上加拿大法文站看到的是英文（或繁中）。**這個 bug 一旦發生就無法還原**（沒有任何紀錄能區分「回灌的回落值」與「譯者真的這樣翻」）。

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
| 大批改價／改庫存政策／改 SEO | **商品 CSV**（可不勾任何語言 ⇒ 43 欄） | 語言是 opt-in，不勾就不會多出 36 欄 |
| 只改庫存量 | **庫存 CSV** | 60 §5 官方明確要求分流；且只有它有 `On hand (current)` 樂觀鎖 |
| 送外部譯者／TMS｜翻頁面・選單・主題字串・通知範本｜回填過期譯文 | **翻譯 CSV** | 只有它有 `source_digest`／`status` 三值／跨 30 種資源；也只有它能出境再回來 |
| 店有 > 4 個語言，或**要把檔案交給外部譯者**（不論幾個語言） | **翻譯 CSV**（長表） | `over_max_locales_action: redirect_to_translation_csv`；出境那條理由與語言數無關（§E.2.2） |

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

🔴 **本表是「基礎欄名」的方言表，與 §D.2b 的「語言後綴」方言表是兩張獨立的表**，可以自由組合——
`Product Name (English)` ＝ Shopline 基礎欄名 ＋ Shopline 語言後綴 ⇒ 解析成 `(Title, en)`。
分開的理由：一個檔案可能用 Shopify 的基礎欄名配我方的方括號後綴（商家從我方匯出後自己改過），
把兩張表併成一張窮舉組合表就會漏掉這種混用。

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

### J.0 🔴 本輪（2026-08-13 第二次）對 `csv.multilingual` 的變更

| 鍵 | 初版 | 本輪 | 為什麼 |
|---|---|---|---|
| `locale_tag_requires_region` | `true` | 🔴 **刪除** | 錯誤前提（§D.0）。**不得復活** |
| `locale_tag_forbids_region` | — | **新增 `true`** | 取代上一列，方向相反 |
| `locale_tag_regex` | — | **新增** `^[a-z]{2,3}(-[A-Z][a-z]{3})?$` | 讓「不帶地區」可機械驗證，範本檔驗證第 11 項用它 |
| `region_bearing_tag_action` | — | **新增** `reject_file` | |
| `max_locales_per_file` | `5` | **`4`** | §E.2.3：判準沒換（`R < 1`），只是把「同量級」算清楚了 |
| `max_locales_derivation` / `translation_to_base_ratio_*` | — | **新增** | 🔴 讓門檻**可重算**，而不是一個記在人腦裡的數字。日後可翻譯欄從 12 變 14，門檻自動變 `43/14 + 1 = 4.07 ⇒ 4` |
| `accept_locale_header_dialects` / `locale_display_name_aliases`（12 條）／`*_import_only` / `*_fuzzy_match_forbidden` / `dialect_does_not_bypass_locale_validation` | — | **新增** | §D.2b：Shopline 商家零轉檔 |
| `duplicate_locale_column_action` | — | **新增** `reject_file` | 兩種方言指向同一 `(欄, 語言)` |
| `assumes_no_market_level_override` / `market_override_ruling_date` / `locale_columns_map_to_market_id` | — | **新增** | §D.5(c)：把「本檔的假設」與「它的依據日期」寫成鍵，讓日後要改的人先看到裁定 |
| `wide_vs_long_criterion` / `long_form_*`（4 鍵）／`wide_form_forbidden_for_external_translators` / `commercially_sensitive_base_columns` | — | **新增** | §E.2.2：門檻的判準本身要落鍵，否則下一個人只看到「4」不知道為什麼 |
| `locale_picker_*`（3 鍵）／`suggest_long_form_for_external_translation` / `export_form_choice_is_single_control` | — | **新增** | §E.2.4：後台呈現 |
| `measured_*_bytes*`（3 鍵） | — | **新增** | §E.2.1 的實測值，供 UI 估算與日後重測對照 |
| `bracket_choice_evidence` | 原字串 | **改寫**（標明重新驗證 ＋ 補 33 這個數字） | §D.2 |
| `product_max_columns` 的推導註解 | `43 + 12×(5−1) = 91` | `43 + 12×(4−1) = **79**` | 隨門檻改 |

🔴 **`i18n.*` 一個鍵都沒動**（§H.2 約束 3）。特別是 `i18n.launch_locales`、`i18n.locale_tag_format`、
`i18n.max_shop_locales` 維持原狀——本輪改的是**商品 CSV 怎麼表達語言**，不是**語言註冊表**。

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
| **4 效能** | streaming parse／streaming write，不整檔載入；1 萬列 × 79 欄的匯入在背景 job 完成且進度可 poll；🔴 匯出的 N+1：譯文必須**一次批次載入**（每 1000 列 ≤ 一次 `translations` 查詢），不得逐列查 |
| **5 可觀測** | 結構化日誌帶 `request_id`＋`shop_id`＋`import_job_id`＋`row_no`；指標 `csv.import.rows_{ok,failed}`、`csv.import.{base_wipe,translation_clear,translation_overwrite}_count`、`csv.import.unknown_column_count`、`csv.export.locale_count`、`csv.export.bytes`；🔴 每一次金額跨界（X4／X6）落 65 §K 維度 5 要求的欄位 |
| **6 測試** | 見 K.1；🔴 **金額代碼 100% 覆蓋**（11 §0 維度 6）——含 zero-decimal 幣別的 CSV 往返（65 §H.1 的 JPY／TWD／KRW 必進矩陣） |
| **7 合規/隱私** | 匯出檔含商家內容 ⇒ 走既有匯出授權與稽核；🔴 **匯入的原始檔要有保存期限與 purge**（它可能含 PII——商家把顧客資料貼進描述）；匯出檔的簽名連結不得進日誌 |

### K.1 逐條驗收

| # | 項目 | 通過條件 |
|---|---|---|
| **CSV-1** | Shopify 匯出檔原檔可讀 | 把 E1（44 欄、`Handle`／`Body (HTML)` 方言、LF、`'`-前綴的 SKU）直接上傳，**零改動**建立出 1 個商品 1 個變體；報告列出被丟棄的欄與原因 |
| **CSV-2** | Shopify 匯入範本原檔可讀 | E2（57 欄、`URL handle`／`Description` 方言、CRLF、17 列含 12 變體與數位商品）直接上傳，建立出 3 個商品共 16 個變體；`Compare-at price = 80`（零位小數）**不得**被拒 |
| **CSV-3** | 多行儲存格 | `Body (HTML)` 含 `\n` 的列正確解析（不錯位）；匯出後再匯入，該欄逐位元組相同 |
| **CSV-4** | 欄名 locale 解析 | `Title [en]`／`Title [zh-Hant]`／`Title [zh-Hans]` 正確路由；🔴 `Title [en-HK]`（**帶地區**）拒絕且訊息說明「地區只出現在 URL」；`Handle [en]`／`Tags [en]`／`Variant Price [en]` 各自拒絕且錯誤訊息指出分類（識別碼／集合鍵／金額）<!-- 🔴 本列在初版是反的（拒絕無地區的 `Title [en]`）。翻面理由見檔頭沿革，不得改回。 --> |
| **CSV-4b** | 🔴 **匯入方言（Shopline 零轉檔）** | ①`Product Name (English)` 與 `Title [en]` 路由到**同一格**；②`SEO Title (Traditional Chinese)` → `(SEO Title, zh-Hant)`；③同時出現 `Title [en]` 與 `Title (English)` ⇒ **整檔拒絕**（同一語言兩欄，`duplicate_locale_column_action`）；④`(Japanese)` 而店鋪未啟用 `ja` ⇒ 整檔拒絕（與 `Title [ja]` 同路）；⑤表裡沒有的顯示名 ⇒ 進報告，**不做近似匹配** |
| **CSV-5** | 🔴 來源語言雙欄 | 同時有 `Title` 與 `Title [zh-Hant]`（＝來源語言）⇒ **整檔拒絕**，不做仲裁 |
| **CSV-6** | 🔴 兩套空白語義 | 表格測試：{基礎欄, locale 欄} × {空白, 有值, `__CLEAR__`} × {勾覆寫, 不勾} 共 12 格，逐格斷言 §F.1 的結果。🔴 **`[locale]` 欄空白 ＋ 勾覆寫 ⇒ 譯文不變**（這一格錯了就是回到 68 那條被推翻的語義） |
| **CSV-7** | 兩個旗標不連動 | 勾「覆寫商品」而不勾「覆寫翻譯」⇒ 既有譯文一筆未動；反之亦然 |
| **CSV-8** | 🔴 `Default Title` | `Option1 Value = Default Title` 那一列帶任何 `Option1 Value [*]` ⇒ 該列失敗。配套：無變體商品匯入後，Ella 主題的 `variants.first.title != 'Default Title'` 判定不翻轉（63 §B.2 的 golden theme 迴歸） |
| **CSV-9** | 選項值譯文 | 同一 handle 內同一選項值的譯文重複且**相同** ⇒ 通過；**不同** ⇒ 整個商品失敗（不是最後一列勝） |
| **CSV-10** | 🔴 變體身分 | ①有 `Variant ID` ⇒ 改選項值後變體 id 不變、譯文保留 ②無 `Variant ID` ⇒ 複製 Shopify 語義（重建變體）且預覽階段警告「將丟失 M 筆譯文」 |
| **CSV-11** | 🔴 金額往返（X4／X6） | 幣別矩陣 **JPY／TWD／KRW／HKD／USD**（65 §H.1）：`storage → 匯出字串 → 匯入 → storage` 恆等。JPY `148000` ⇒ `"1480.00"` ⇒ `148000`。🔴 匯出檔裡**不得出現 `148000`** |
| **CSV-12** | 金額拒收 | `19.999`（三位小數）⇒ 該列失敗且**不 round**；`1,29`（歧義逗號）⇒ 該列失敗；`1,290`（嚴格千分位）⇒ 清洗為 1290 |
| **CSV-13** | 🔴 單位價格不是金額 | `Unit Price Total Measure = 500.00` 匯入後**不得**變成 50000；型別斷言（傳 `Money::Decimal` 進去 ⇒ `TypeError`，65 §C.1） |
| **CSV-14** | 🔴 匯出不填 fallback | 某商品缺 `fr` 譯文 ⇒ 匯出該格為**空**（不得填來源語言或 `en` 的值）；把該檔原檔回灌 ⇒ `translations` 表**沒有**新增該列，翻譯進度不變 |
| **CSV-15** | 匯出可原檔回灌 | 匯出 → 不改任何一格 → 匯入（勾兩個覆寫）⇒ 資料庫**零變更**（含 `updated_at`）。這條同時證明表頭一致與 fallback 不落地 |
| **CSV-16** | 欄數與門檻 | **4 語 ⇒ 79 欄**（＝範本檔）；勾到**第 4 個**語言 ⇒ UI **預告**「再加一個就建議改用翻譯 CSV」；勾**第 5 個** ⇒ 擋下並給出口文案（含「為什麼」）；欄數與大小估算與實際產出誤差 < 10%<!-- 🔴 初版判準是「3 語 67 欄／勾第 6 個擋下」（門檻 5）。本輪門檻改為 4，推導見 §E.2.3。 --> |
| **CSV-16b** | 🔴 **寬表／長表的選擇是同一個控制項** | 匯出 modal 裡「寬表／長表」是**一個**選擇（`export_form_choice_is_single_control`），不是兩個選單；選長表時輸出的是 67 §E.6 的 9 欄格式，**欄數不隨語言數變**（1 語與 8 語都是 9 欄） |
| **CSV-16c** | 🔴 **長表不含商業敏感欄** | 長表輸出中**不得出現** `Cost per item`／`Variant Inventory Qty`／`Variant Barcode`／`Variant SKU`（§E.2.2 後果 1）。斷言方式：長表表頭 ∩ 該四欄 == ∅ |
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
| **M-1** | ~~locale 碼是否帶地區~~ ✅ **已消解，不是衝突** | 67 §A.4：「`en` 英文（無地區）……需要地區時是 `en-HK`／`en-SG`，由 market 推導，**不預先建立**」；62 §I.2：URL 與 hreflang 碼**恆帶地區** | ✅ **兩份都對，它們講的是不同維度**（§D.0）：67 講**內容的鍵**（`shop_locales.tag`，不帶地區）、62 講**輸出的碼**（URL 前綴／hreflang 值，恆帶地區）。CSV 是內容 ⇒ 本檔跟 67，`locale_tag_forbids_region: true`。<br>🔴 **62 §I.2 自己就寫過這條分界**（行 921 逐字）：「`zh-Hant` 這個標籤本身仍然存在，而且必須存在——它是 `platform_locales.tag`（**語言**的身分）。恆帶地區改的是**輸出的碼**，**不是語言註冊表**。把 `zh-Hant-HK` 存進 `platform_locales` 是本次修改最容易犯的錯。」初版 70 犯的就是這一條，只是犯在 CSV 表頭。<br>🔴 **不得把本列改回「衝突」**：那需要先推翻 67 §A.1 的「一份 `zh-Hant` 譯文兩個市場共用」 | 無（本列即修正紀錄） |
| **M-1b** | **市場級覆寫是否進商品 CSV** | ~~67 §C.2 有 `translations.market_id`~~ 🔴 **該欄已依裁定 10 於 2026-08-13 移除**（67 §C.2 沿革、§0.4 第 7 列）；67 §E.6(b) 的 `market_handle` 欄降為**純格式相容欄**（恆空白） | 🔴 **本檔假設無市場級覆寫**，依據＝**2026-08-13 裁定**（逐字：「不必考慮香港英文和加拿大英文的揭露事項因法規必須不同，所有的都會保持一致」）。⇒ 商品 CSV **不定義任何市場級覆寫欄**；`[locale]` 欄唯一對應 `translations(locale)`（無市場維度）。<br><!-- 依裁定 10 修正。原文中欄：「67 §C.2 有 translations.market_id（NULL＝語言層，非 NULL＝per-market 覆寫，29 §2.2 Adapt）；67 §E.6(b) 的翻譯 CSV 已有 market_handle 欄」；原文立場欄含：「這是『不使用』不是『不該存在』：translations.market_id 是 67 的範圍，本檔不動它，也不主張刪它——其他資源（政策／通知範本）可能仍需要它」。刪欄後「其他資源可能需要」的保留理由一併消滅：裁定 10 管的是整個 translations 表的市場維度，不是只有商品。 -->🔴 日後要讓商品 CSV 帶市場維度，**先依 67 §C.2 復活條件恢復資料模型與 admin 契約，再回頭改本檔**。放寬本檔欄名正則 ＝ 讓資料模型變更偽裝成格式變更，見 §D.5(b) | 無（本檔登記假設；67 已依裁定執行刪欄） |
| **M-2** | **`csv.*` 鍵不存在卻被引用** | 67 §E.6 的 `max_upload_mb_key: csv.product_max_upload_mb`；61 §9.5 標「✅ 已有」 | ✅ **本輪已修**：新增 `csv:` 頂層區塊（§J）。61 §9.5 的那一列描述仍不準（它指的是 `media.csv_max_upload_mb`），但 `docs/research/*` 是證據不是結論，**不改** | 無（本列即修正紀錄） |
| **M-3** | **13 §F6 只寫「一套 CSV 匯入」** | 13 §F6：「欄位對齊 Shopify CSV 格式（遷移友好）」，未區分商品／庫存／翻譯 | 三套已由 63 §L-8（商品／庫存）與 67 §E.6（翻譯）拆開，本檔 §H 補上三者關係與分工。13 §F6 需回寫（它同時還缺多語言欄與兩套空白語義） | **13 §F6** |
| **M-4** | **`Variant ID` 這種穩定主鍵，Shopify 沒有** | 61 §6.1 明載：改動 `Option{n} Value` ⇒ 刪除既有變體 ID 並產生新 ID；我方「必須複製這個語義」 | ✅ **兩者並存**：有 `Variant ID` 走穩定主鍵（我方擴充，E3 的做法），沒有才複製 Shopify 的破壞性語義。🔴 多語言把這條的成本從「訂單歷史對不上」提高到「訂單歷史對不上 **＋ 譯文消失**」（§E.4） | 無（本檔定案） |
| **M-5** | **商品 CSV 帶譯文 vs 67 §E.6「翻譯是第三套」** | 67 §E.6 理由 1 明確反對「硬塞進商品 CSV」 | ✅ **不衝突，但必須寫清楚**：67 反對的是把商品 CSV 當成譯文的**儲存**；本檔把它當成同一張表的第二個**傳輸面**，並以「同一支 writer ＋ CI 斷言 ＋ 不複製語義鍵」三條約束保證不分岔（§H.2）。裁定要求它存在，§H.3 給出它**必須**存在的結構性理由（新目錄用翻譯 CSV bootstrap 不了） | 無（本檔定案；67 §E.6 可加一行交叉引用，但本輪不改 67） |
| **M-6** | **`media.csv_max_upload_mb` 與 `csv.product_max_upload_mb` 同值不同義** | 兩處都是 15 | 登記。**不合併**——媒體匯入與商品匯入是兩個功能，日後任一方調整不該連動 | 無 |

---

## 附錄 A · 範本檔的可重跑驗證

`docs/templates/` 兩份 CSV 由一支 Python 腳本產生（腳本不入庫，同 67 附錄 A 的先例：它只是本檔 §C／§D／§E 的直譯）。
驗證以 Python `csv` 模組**重新解析產生出來的檔案**（不是驗證產生器的記憶體結構），**11 類斷言 × 兩檔 = 27 項全綠**。

**語言配置＝使用者 2026-08-13 的實際配置**（`ruling`）：

```
shop_locales（內容維度）= zh-Hant(來源) / en / fr / zh-Hans        ⇒ 4 份內容 ⇒ 36 個譯文欄
市場開放語言（呈現維度，不進 CSV）：
    HK = zh-Hant / zh-Hans / en          ⇒ /zh-hant-hk /zh-hans-hk /en-hk
    CA = en / fr / zh-Hant / zh-Hans     ⇒ /en-ca /fr-ca /zh-hant-ca /zh-hans-ca
⇒ 7 條 URL 前綴，4 組內容欄。加拿大的繁中與香港的繁中是同一格資料。
```

| # | 斷言 | 結果 |
|---:|---|---|
| 1 | 每一列的欄數 == 表頭欄數 | 兩檔皆 **79 欄** |
| 2 | 表頭無重複欄名 | ✅ |
| 3a | 每個 `[locale]` 欄的基礎欄都在 `translatable_columns` 白名單內 | 各 36 個譯文欄全過 |
| 3b | 🔴 標籤符合 `^[a-z]{2,3}(-[A-Z][a-z]{3})?$`（語言(-script)，**無地區**） | ✅ |
| 3c | 無 `[來源語言]` 欄（不得與無後綴欄並存，§D.3） | ✅ |
| **11** | 🔴 **防回退**：整張表頭中**沒有任何**匹配 `^…-[A-Z]{2}$` 的標籤 | ✅ 兩檔皆 0 |
| 4 | 金額欄（`Variant Price`／`Variant Compare At Price`／`Cost per item`）全部符合 `^-?\d+\.\d{2}$`，無 cents、無千分位、無科學記號 | 每檔 **15 格** |
| 5 | 每個 handle 的**首列** `Title` 非空；**續列**的 14 個商品層欄**及其 `[locale]` 欄**全部留白 | ✅ |
| 6 | `Option1 Value = Default Title` 的列，其 `Option1 Name [*]`／`Option1 Value [*]` 全部為空 | ✅ |
| 7 | `Source Locale` 全檔一致 == **`zh-Hant`**（🔴 不是 `zh-Hant-HK`） | ✅ |
| 8 | 選項值譯文映射無矛盾（同一 (handle, 選項, 值, locale) 不出現兩個不同譯文） | 各 **12 筆映射** |
| 9 | 存在多行儲存格與內嵌雙引號；`csv.reader` → `csv.writer` 往返後**逐位元組相同** | 匯入 10 格多行／1 格含 `"`；匯出 8 格多行／1 格含 `"` |
| 10 | 兩份檔案的**表頭完全相同**（⇒ 匯出檔可原檔回灌，§I.1） | ✅ |

**量測結果**：

| 檔案 | 位元組 | 表頭欄數 | 資料列 | 邏輯列（含表頭） | 實體行 | BOM | CRLF |
|---|---:|---:|---:|---:|---:|---|---|
| `product-import-template.csv` | 8692 | **79** | **9** | 10 | 37 | 無 | 無（LF） |
| `product-export-sample.csv` | 7068 | **79** | **7** | 8 | 24 | 無 | 無（LF） |

（「實體行 > 邏輯列」正是 §B.1 那條「儲存格內換行合法」的直接證據——以「一行一列」切割這兩個檔案會分別得到 37 與 24 列，全部錯位。）

**欄數公式核對**：`43（基礎） + 12（可翻譯） × 3（來源語言以外的語言） = 79` ✅
**列寬量測**（餵給 §E.2.1 的門檻推導）：表頭 1,341 B；資料 **817 B/列**（匯入 7,351 B ÷ 9 列、匯出 5,727 B ÷ 7 列，兩者一致）。

<!-- 🔴 初版此表為 67 欄／6366＋5256 位元組／24＋16 實體行／`Source Locale = zh-Hant-HK`／24 個譯文欄。
     本輪依「內容鍵＝語言」重出，全部數字改變。**斷言第 11 項是本輪新增的防回退**：
     它斷言的不是「範本檔對」，而是「範本檔沒有偷偷變回帶地區的形態」——
     初版的錯誤形態（`Title [en-HK]`）會被它擋下，而第 3b 項的正則單獨看還不夠明確，故獨立成一項。 -->

**範本檔的教學內容**（比照 Shopify 範本的教學性質，🔴 **內容自編，不抄 E1／E2／E3 的範例商品**，鐵律 9）：

| 商品 | 形態 | 教到什麼 |
|---|---|---|
| `handcrafted-soy-candle` | 2 選項 × 4 變體 ＋ 2 個純圖片列（6 列） | 重複列、商品層留白、**選項值譯文只填第一次出現**（§E.3）、純圖片列、`Body (HTML)` 多行 ＋ 內嵌雙引號 |
| `rose-body-oil-100ml` | 單變體（2 列） | 🔴 `Default Title` 契約（選項譯文必須留白）、單位價格四欄（`100.00`／`10.00` **看起來像金額但不是**，§F.3） |
| `aroma-blending-workshop-online` | 數位商品（1 列） | 不需運送、不追蹤庫存、`CONTINUE`、`DRAFT` ＋ `Published=FALSE`、**`fr` 整列未翻**（示範「空白＝不動作」） |
| `candle-duo-gift-set`（僅匯出範例） | 單變體 | 🔴 `Status = UNLISTED`（我方四態的第四態，Shopify 沒有）、系統欄已填 GID |

🔴 **範本檔裡刻意留白的格不是漏填**——它示範的是**部分翻譯這個常態**，以及它在匯入時的語義（不動作，不是清空）：

| 留白的格 | 敘事 |
|---|---|
| `Body (HTML) [fr]`、`SEO Description [fr]`（玫瑰油） | 加拿大市場剛開，法文只翻了標題與 SEO 標題 |
| `Title [fr]`／`Type [fr]`／`SEO Title [fr]`（線上課程） | **整個商品的法文都還沒開始** ⇒ 匯入後該商品的 `fr` 譯文一筆都不會被建立（不是建立空譯文，§I.3） |
| `SEO Description [en]`／`[zh-Hans]`（線上課程） | 連英文與簡中也可以有缺口 |
| `Image Alt Text [fr]`（禮盒圖、油體特寫） | alt 文字最常見的缺譯位置 |

🔴 **範本檔裡沒有一格是 `zh-Hant` 以外的地區變體**。若哪天有人在這兩個檔案裡看到 `[en-HK]`，那不是新需求，那是回退（§D.5）。
