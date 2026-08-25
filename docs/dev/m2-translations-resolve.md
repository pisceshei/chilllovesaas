# M2：譯文解析與既有譯文稽核（第 7 包）

> 規格：`docs/specs/67-multilingual.md` §C.4（fallback 鏈）／§C.4(b)（空值定義）／§B.1（欄位三分類）
> 計畫列：`docs/plans/2026-08-24-三方向執行順序.md` 第 7 列 · 67 §I 的 **L4**（依賴 L3，L3 已在 M1 落地；§L 是 V-160 起的待查證表，2026-08-25 更正）
> 驗收：I18N-3（fallback 鏈唯一實作）、I18N-6（`resolve()` 不收 market）
> 配對 worklog：`docs/worklog/2026-08-25-第7包譯文解析.md`

---

## 0. 一句話

本包交付「前台要顯示哪個字串」這個問題的**唯一**答案來源，並把「什麼叫做沒有翻譯」
從三份各自為政的實作收斂成一份，順帶補上兩個線上實測到的缺口（譯文不 sanitize、
CSV 匯入不重算進度）。**本包無可見成果**——沒有新畫面、沒有新 GraphQL 欄位；
消費者是第 30／33／34 包。

---

## 1. 交付物

| 檔案 | 角色 |
|---|---|
| `app/services/locales/fallback_chain.rb` | BCP-47 截尾鏈（純函式，不碰 DB） |
| `app/services/translations/blank_value.rb` | 「等於沒有翻譯」的唯一判準（讀寫共用） |
| `app/services/translations/fields.rb` | 可翻欄位的中繼資料（kind／missing／base 屬性／上限與單位） |
| `app/services/translations/resolve.rb` | 67 §C.4 的四步演算法 ＋ 批載 ＋ 遙測 |
| `app/services/translations/audit.rb` | 既有譯文稽核（四條規則 ＋ 一條棄權） |
| `lib/tasks/translations.rake` | `translations:audit` ／ `translations:fix` |
| `app/services/locales/registry.rb` | 新增 `published_tags`（前台解析範圍） |
| `app/services/translations/upsert.rb` | 🔴 補 sanitize；判空改呼叫 `BlankValue`；`recompute_status` 轉公開 |
| `app/services/translations/csv_import.rb` | 🔴 補 sanitize、補判空、補 `recompute_status`、修 `source_tag` N+1 |
| `config/limits.yml` | `i18n.resolve.*`／`i18n.blank_value.*` 新鍵 ＋ 截尾規則的 CLDR 出處 |

---

## 2. 逐控件註釋（鐵律 12.4 的四件事）

本包沒有 UI 控件，逐「介面」寫。

### 2.0 `Translations::Upsert` 的 prepare／commit 兩段式（2026-08-25 依審查 C4 拆分）

**①這是什麼**：寫入層拆成「純 CPU、不碰表」的 `prepare` 與「只寫 DB」的 `commit`。

**②為什麼**：`Upsert` 的契約是「必須在呼叫端的 transaction 內」，而本包給它加了 Loofah
sanitize——於是 HTML parse 跑在 `SaveProduct` 已持有 `products` 列鎖（改名時還有店級
`Shop.lock`）的 transaction 裡。實測貼近欄位上限的 `body_html` 一次 sanitize 是數百 ms，
admin SPA 又是宣告式**恆送全樹**（每次儲存重跑每個語言），4 個語言就把鎖持有拉到秒級，
20 語言（`i18n.max_shop_locales`）更糟。base 的 `description_html` 本來就在
`SaveProduct#normalize`（開 transaction **之前**）sanitize——譯文現在比照。

**③怎麼用**：
- `prepare(shop:, source_locale:, translations:)` → `Prepared(entries:, user_errors:)`。
  只讀 `shop_locales`，**不寫任何表**，在 transaction 外呼叫。
- `commit(shop:, resource_type:, resource_id:, source_locale:, source_values:, prepared:)`
  → `Result`。在呼叫端 transaction 內。收到 `user_errors` 非空的 `Prepared` 直接 raise。
- `call(...)` 保留為一段式便利入口（＝prepare＋commit），🔴 **productSet／collectionSet
  不要用**，用了就把 sanitize 拉回 transaction 內。

**④跨影響**：`SaveProduct#normalize` 與 `SaveCollection#normalize` 各自在 txn 外呼叫
`prepare` 並把 `Prepared` 放進 attributes；`save_translations!`／`reject_translations!`
在 txn 內呼叫 `commit`。新增第三個譯文寫入的呼叫端時照同一形態接。

### 2.1 `Translations::Resolve.batch`

**①這是什麼**：批次解析器，本包的主要 API。輸入是**已載入的** base row 陣列，
輸出 `{[resource_type, resource_id] => {field_key => Resolved}}`。

**②具體功能（完整值域）**

| 參數 | 值域 | 預設 | 說明 |
|---|---|---|---|
| `shop:` | Shop | 必填 | 自己開 `ActsAsTenant.with_tenant` 脈絡 |
| `resources:` | `[Product \| Collection]` | 必填 | 上限 `i18n.resolve.max_resources_per_batch`（50），超過 raise；🔴 元素的 `shop_id` 必須等於 `shop.id`，否則 raise（base 值直接從物件讀，查詢層的 `shop_id` 條件擋不到——審查 A10） |
| `fields:` | `Fields::ALL` 的子集 | `Fields::ALL` | title／body_html／meta_title／meta_description |
| `locale:` | BCP-47 字串 | 必填 | 會先正規化大小寫 |
| `scope:` | `:published` ／ `:enabled` | `:published` | 其他值一律 raise（fail-closed） |

回傳的 `Resolved` 是 `Data.define(:value, :locale, :depth, :source)`：

| 欄 | 值域 | 說明 |
|---|---|---|
| `value` | String ／ nil | `source == :omitted` 時為 nil |
| `locale` | String ／ nil | 這個字串**實際**是什麼語言（第 34 包的 `lang` 屬性值） |
| `depth` | 0..鏈長 | 離請求語言幾步，以**完整**截尾鏈索引計（與 scope 無關）。0＝請求語言命中或請求語言＝來源語言；1..n＝鏈的第 n 階；鏈長＝落到 base。🔴 2026-08-25 依審查 A3 修正：首版用**過濾後**的索引，於是「請求語言不在 scope 內」時塌回 0，讓一次真正的 fallback 回報 `fallback?=false`、第 34 包不加 `lang`、遙測全盲 |
| `source` | `:translation` ／ `:base` ／ `:omitted` | — |

輔助謂詞：`#fallback?`（＝`depth.positive?`）、`#omitted?`。

**③怎麼做到（實作邏輯與規則出處）**

67 §C.4 的四步逐字對應：

```
1. translations[L]                  ⇒ candidates[0]
2. for A in fallback_chain(L)       ⇒ candidates[1..]
     translations[A]
3. base row                         ⇒ base_result
4. 仍為空 ⇒ 依 §B.1：required→回 3 的值；optional→整個欄位不輸出
```

四個非顯而易見的實作點：

1. **請求語言＝來源語言時 `depth` 必須是 0**。來源語言的文字在 base row；正規寫入路徑
   不會產生來源語言的譯文列（`Upsert` 以 code=`INVALID`、i18n key
   `errors.translation.source_locale_not_translatable` 擋——🔴 2026-08-25 更正：首版寫
   「用 `SOURCE_LOCALE_NOT_TRANSLATABLE` 擋」，倉庫裡**沒有這個識別字**；繞道寫入的
   歷史列由 `Audit` 的 `source_locale_row` 規則登記）。照「查不到就一路
   走到 base」算會得到 `depth = n+1`，於是**每一次正常的來源語言渲染都會發一筆遙測**
   ——§E.4 的缺漏可視化會被自己的正常路徑淹沒。實作上不需要特例分支：候選清單裡遇到
   `== source_locale` 就回 base，而來源語言的候選索引恰好是 0。
2. **鏈的中間階也可能是來源語言**（來源 `en`、請求 `en-GB`）：同樣直接回 base。
3. **`field_key` 不進 IN 清單**。MySQL 官方逐字：`If there are two IN() lists, the number
   of predicates combined with OR is the product of the number of literal values in each
   list.`；`eq_range_index_dive_limit` 預設 200，達到即從 index dive 換成統計估算，
   **同一支查詢的執行計畫無預警改變**。50 × 3 × 4 = 600 > 200；拿掉 field 維度後是 150。
   出處：<https://dev.mysql.com/doc/refman/8.4/en/range-optimization.html>（2026-08-25）
   ＋<https://dev.mysql.com/blog-archive/you-asked-for-it-new-default-for-eq_range_index_dive_limit/>（2026-08-25）
4. **按 `resource_type` 分組發查詢，不用 row constructor**。`(a,b) IN ((..),(..))` 走 range
   有四個條件，其中「右側必須多於一個 row constructor」在單筆時不成立而退化成全掃。
   🔴 這是對 67 §F.3(c) 字面「**一次** IN」的**刻意偏離**，理由如上；`RESOURCE_TYPES`
   封閉在兩值 ⇒ 每次 batch 最多 2 條 SQL。

索引沿用既有 `uq_translations_resource_locale_field (shop_id, resource_type, resource_id,
locale_tag, field_key)`——leftmost prefix 完全吻合 `shop_id(=) → resource_type(=) →
resource_id(IN) → locale_tag(IN)`，**不需要新增索引**。🔴 改欄序會讓整個批載退回掃描。

**④跨功能／跨頁／前端影響（預先對接）**

| 消費者 | 需要什麼 | 本包提供什麼 |
|---|---|---|
| **第 30 包**（Liquid 生產化） | `ProductDrop` 建構時 preload 全欄位譯文 | `.batch`，key＝`[resource_type, resource_id]`。🔴 **不得**在 drop 的每個 method 呼叫 `.field`（那是 N+1）。本包不碰 `poc/` |
| **第 33 包**（渲染管線／cache stamp 自檢） | `touched_sources` | `Resolve.touched_sources` ⇒ `[:translations]`。🔴 **只回傳、不呼叫**——接收端（`catalog_flow.cache_stamp_selfcheck_envs`）在 `app/` 尚無實作 |
| **第 34 包**（三層字串／lang／Vary） | 要不要加 `lang`、加什麼值 | `Resolved#fallback?` 決定加不加；`Resolved#locale` 是值。🔴 值是 `zh-Hant`（實際語言）**不是** `zh-Hant-HK`（請求語言）——W3C 的 `lang` 語義是「這段文字實際是什麼語言」 |
| **第 3 包**（cache stamp） | `translations` 的 stamp 欄 | 見 §5「交給下游的需求」。本包**不開 migration** |
| 後台 GraphQL `ProductType#translations` | 🔴 **什麼都不需要——禁止接 Resolve** | 見 §3 |
| 通知／訂單 | `notification_locale_chain` | 不接。`customers` 無 `locale` 欄、`orders.locale_snapshot` 的寫入者在 M3 ⇒ Resolve 只吃**外部給定**的 locale 字串，不去寫那些欄 |

### 2.2 `Translations::BlankValue.blank?(value, kind:)`

**①**：讀寫共用的空值判準。四個消費者：`Upsert`、`CsvImport`、`Resolve`、`Audit`。

**②完整值域**：`kind:` 兩值。

- `:text`（title／meta_title／meta_description）——只剝除不可見字元後判空。
  🔴 純文字欄裡的 `<p></p>` 是**真內容**（帶角括號的標題），不判空。
- `:html`（body_html）——另外承認語義空 HTML。

不可見字元集＝`[[:space:]]`（含 U+3000、U+00A0）＋`\p{Cf}`（含 U+200B、U+FEFF、U+200E）＋U+0000。

**③怎麼做到 / 三個裁定**

1. **parser 走 `Loofah.fragment`，理由是與 sanitizer 同源**。`Catalog::SaveProduct#sanitize_description`
   已經用它（複驗＝`grep -n "Loofah.fragment" app/services/catalog/save_product.rb`），
   同一支 parser 才不會出現「sanitizer 看得到 img、判空器看不到」的漂移。
   實測身分：`Loofah.fragment("<p>x</p>").class` ⇒ `Loofah::HTML4::DocumentFragment`（2026-08-25）。
2. **HTML4 這個選擇有代價不對稱的證據**（2026-08-25 實測）：截斷輸入 `"<p><img src=x"`
   在 HTML4 判非空、在 `Nokogiri::HTML5` 判空；而判空的動作是 `delete_all`＝**刪掉商家的譯文**
   ⇒ 選在假陰性側。HTML5 在這裡會靜默毀資料。
3. **判空必須在 sanitize 之後**（`i18n.blank_value.runs_after_sanitize`）。反例：
   `<video src=x></video>` sanitize 前是 content-bearing（判非空），sanitize 後變成 `""`
   ⇒ 先判空就會存進一列「後台已翻譯、前台空白」的鬼列。
4. 🔴 **單一實作 ＋ 讀取端尺寸 fast-path**（2026-08-25 二次修正）。

   > 🔴 **更正（對抗審查 C5）**：首版在此否決研究建議的讀取端快篩，依據是
   > 「一次判準 ~85µs、50 列列表頁 ~4ms」——**那個量測錯了 20 倍以上**。實測
   > 17KB `body_html` 一次 ≈**1987µs**、50 列全 parse ≈**95ms**（本機 `bundle exec ruby`，
   > 2026-08-25，對 ~17KB 中文段落跑 200 次取均值；審查方在較慢機器量到 14ms／700ms）。
   > 原否決理由連同那兩個數字一併**撤回**。

   修正後的設計：`BlankValue` **仍然只有一份實作**，但 `blank?` 多一個
   `skip_parse_above:` 參數。`Resolve`（讀取端）傳
   `i18n.blank_value.read_fast_path_max_bytes`（1024）：`:html` 且 bytesize 超過它就
   **不 parse、直接判非空**。理由是形態不對稱——語義空 HTML（`<p>&nbsp;</p>`、
   `<p class="x"></p>`、空清單）結構上都是幾十 bytes；大字串誤判成非空落在**假陰性側**
   （不刪資料、頂多多顯示一段）。🔴 **寫入端與稽核永遠傳 `nil`**（完整判準）——
   它們的動作是刪列，不可逆。

`CONTENT_BEARING` ＝ WHATWG「Embedded content」分類的**恰十個元素**
（`audio canvas embed iframe img math object picture svg video`；
<https://html.spec.whatwg.org/multipage/dom.html>，2026-08-25）＋**六個**可見加項
（`hr`、`table`、表單四控件 `input`／`select`／`textarea`／`button`）＝16 個。
🔴 2026-08-25 更正（審查 D10）：首版清單多了 `source` 且宣稱加項是「三項」——`source`
既不在 embedded 十元素內、也不在宣告的加項內，且它是 void、單獨渲染無物（違反本清單
「使用者看不看得到」的判準）。已移除；它的父元素 `picture`／`video`／`audio` 本就在清單內。
🔴 **不是 void elements 清單**（`area`／`base`／`col`／`link`／`meta`／`track`／`wbr` 是 void 但不可見）；
🔴 `br` **不在**清單裡——`<p><br></p>` 是 RTE 初始值，是主要要抓的形態。

**④跨影響**：寫入端判空 ⇒ 刪列（不可逆）；讀取端判空 ⇒ 往鏈的下一階；後台進度分子是
「有列」而不是「值非空」，兩者靠寫入端判空保持一致（鐵律 7）。

### 2.3 `Locales::FallbackChain`

**②完整值域**

```
zh-Hant-HK → ["zh-Hant"]      zh-Hant → []       zh-Hans-CN → ["zh-Hans"]
en-GB      → ["en"]           en      → []       pt-BR      → ["pt"]
ja         → []               sr-Latn → ["sr"]   sr-Latn-RS → ["sr-Latn", "sr"]
```

**③🔴 「截到 zh 就停」與 CLDR 同構，不是我方自創的加嚴**（2026-08-25 取證）。

> 🔴 **2026-08-25 更正（對抗審查 D1）**：本節首版引用
> `common/supplemental/parentLocales.xml` 並附一段「官方理由逐字」——**該路徑在
> unicode-org/cldr 不存在（404），該段引文在 CLDR 全文亦無法定位**。原引文與原 URL
> 一併**撤回**。結論（zh-Hant 的 parent 是 root、理由是換 script）不變，改由下列
> 三個親自抓取複驗的來源支持。

- CLDR 正典 XML，`common/supplemental/supplementalData.xml`（main 分支，第 5157 行）：
  `<parentLocale parent="root" localeRules="nonlikelyScript" locales="… sr_Latn … zh_Hant"/>`
  <https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml>
- 理由在 **CLDR 的 TR35（LDML 規格）**逐字（該檔在 unicode-org/cldr repo 內，非本倉庫）：
  `In some cases, the normal truncation inheritance does not function well. For example, if
  the truncation algorithm changes script, then a mixture of child and parent textual data is
  a mishmash of different scripts.`
  <https://raw.githubusercontent.com/unicode-org/cldr/main/docs/ldml/tr35.md>
- 衍生 JSON（**cldr-json** repo，非正典）把同一事實寫成 `"zh-Hant": "und"`：
  <https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-core/supplemental/parentLocales.json>
  🔴 `und` 這個值只出現在這個衍生 repo；正典 XML 寫的是 `root`。

🔴 **相對地，RFC 4647 §3.4 Lookup 的字面演算法會產生 `zh-Hant → zh`**（它不懂 script 語義）
⇒ 我方在此**刻意偏離 RFC 字面**，**不得寫成「照 RFC 實作」**。

⚠️ 我方只把 `zh` 放進 `forbidden_locale_tags`，所以 `sr-Latn → sr` **仍會發生**，
與 CLDR 對 `sr-Latn` 的處理**不同構**。這是已知且刻意的射程限制（首發五語沒有 sr）；
支援塞爾維亞語時要做的是把 `sr` 加進禁用表，不是改本模組。

---

## 3. 🔴 紅線：後台 GraphQL 不得接 `Resolve`

`Types::ProductType#translations`（`app/graphql/types/product_type.rb`）與
`Types::CollectionType#translations` 目前是對 `locale_tag` **精確比對**後排序，**沒有任何鏈**
——這是**刻意的**。

前端 `ProductDetailPage.tsx` 用 `toTranslationMap` 把回來的列直接當表單值，儲存時用
`translationEntries` 送回 `productSet`。⇒ **若這兩支吃到 fallback 值，商家一按儲存就會把
來源語言原文寫成該語言的「真譯文」**，且從此 `outdated` 與進度數字全部失真。

守衛＝`spec/services/translations/resolve_spec.rb` 的兩格反向 spec（SQL 斷言 ＋ 行為斷言）。

---

## 4. 本包順帶修補的兩個線上缺口

兩者都不是「順手擴修」：它們與本包的根因（`translations.value` 的寫入端沒有 parser 級紀律）
是同一個 producer，且都是 §5 那個 cache stamp 方案的**前提**。

### 4.1 🔴 譯文 `body_html` 完全不 sanitize（儲存型 XSS）

**實證**（2026-08-25 於 bt3 正式環境 rev `1a75ceb` 以 `rails runner` 實跑）：同一段
`<p>ok</p><script>alert(1)</script><img src=x onerror=alert(2)>`

| 路徑 | 落庫值 |
|---|---|
| `descriptionHtml`（base） | `<p>ok</p>alert(1)<img>` |
| `translations[body_html]` | 🔴 **原樣**，`<script>` 與 `onerror` 俱在 |

原因：`SaveProduct#normalize` 的註釋逐字寫「譯文原樣帶下去（驗證在 `Translations::Upsert`）」，
而 `Upsert` 只驗長度與欄位白名單、**不 sanitize**。第 30／34 包把譯文渲染到前台的那一刻，
它就是儲存型 XSS。

修法：`Upsert#sanitize` 與 `CsvImport#sanitize` 都呼叫
`Catalog::SaveProduct.sanitize_description_for`（`SaveCollection` 已是同形態）
——全倉恰一份 `ALLOWED_TAGS`／`ALLOWED_ATTRIBUTES`。
🔴 **兩條寫入路徑都要修**：只修 GraphQL 那條等於把同一個洞留了一個入口。

順序＝**量 raw → sanitize → 判空（毀內容則報錯）→ 再量**。
> 🔴 **更正（審查 S2／S4）**：首版寫「sanitize → 判空 → 量長度，三者不可對調」。兩處被推翻：
> ①**量長度必須有一次在 sanitize 之前**——Loofah 對無上界輸入是超線性 CPU
> （實測 64KB≈0.78s、1MB≈14s、5MB≈160s），而 nginx 收 32MB、`Rack::Attack` 只限
> `admin-login` ⇒ 認證後的巨大 payload 可在量長度之前把 CPU 燒光。代價是「raw 超限但
> sanitize 後會縮到限內」改為拒收，已裁定接受。②**「判空⇒刪列」對「sanitize 毀掉的
> 非空內容」是錯的**——`<video>`／`<iframe>` 與 libxml2 深度 256 懸崖都會讓真內容變成
> `""`，首版會靜默刪掉商家的譯文；現在那條路徑回 userError `INVALID`。

**既有資料**：`translations:audit` 的 `unsanitized_html` 規則掃得出來，`translations:fix` 可修。
🔴 **正式環境現況＝0 命中**（bt3 唯讀盤點，2026-08-25：全平台 8 列譯文，全部是 `title`
純文字欄，`blank_value`／`unsanitized_html` 命中皆 0）⇒ **本次修復是預防性的，不是清理
既有損害**；缺口本身確實存在且可寫入（同段落的實測），只是還沒有人踩到。

### 4.2 🔴 `CsvImport` 完全不重算 `translation_status`

先前 `csv_import.rb` 全程沒有任何 `recompute_status` 呼叫 ⇒ 經 CSV 進來的譯文既不反映在
後台進度徽章，也不推進 `translation_status.updated_at`。後者正是 67 §G.3 建議拿來當
`translations` cache stamp 載體的那一欄 ⇒ 不補這個缺口，第 3 包會在一個**已知破**的
不變式上建快取失效機制，而快取失效的失敗是**靜默的**（商家改了譯文、前台永遠是舊的）。

同時修掉 `write_row` 每列各查一次 `Locales::Registry.source_tag(shop)` 的 N+1
（一份千列的檔案＝一千次查詢）。

### 4.3 上限單位量錯

`Fields.limit("body_html")` 回的是 `product.description_max_bytes`（**位元組**），
base 的 `SaveProduct#normalize` 用 `description.bytesize` 量，而譯文端一律用 `value.length` 量
⇒ 同一個上限，base 擋在 N bytes、譯文放行到 N **字元**；中文譯文（每字 3 bytes）等於
拿到三倍額度。修法＝`Fields.measure(field, value)`，把「哪個欄位用哪個單位」收在一處。

---

## 5. 交給下游的需求（本包只登記，不落欄）

1. **`translations` 必須進 `limits.catalog_flow.cache_stamp_sources`**——67 §G.3 明文
   「cache_stamp 必須覆蓋該 drop 實際讀過的每一張表」，否則 63 §D.3 紀律 2 的自檢會在
   第一次渲染翻譯欄位時 raise。
   🔴 **本包不加這個值**，理由＝不再增加第四個懸空來源名。
   > 🔴 **更正（審查 D2）**：首版寫「現行 `cache_stamp_sources` 的每一項都指向實際存在的
   > 欄位」——**不成立**：`market_settings_version` 與 `price_list_updated_at` 兩項在
   > `db/` 與 `app/` 都查不到（複驗＝
   > `grep -c "market_settings_version\|price_list_updated_at" db/schema.rb` ⇒ 0），
   > 它們是第 32 包的預告名。`i18n.cache.additional_cache_stamp_sources` 的兩項同理。
   > 已在 `config/limits.yml` 該處就地標註。決策不變（本包仍不加），但依據改成
   > 「已知有三個懸空名，不再增加」，而不是一個假的全稱句。**第 3 包立欄時一起加。**
2. **粒度已裁定**：`i18n.cache.translations_stamp_granularity: resource_locale`（已在 limits）。
3. **載體建議（P7-L14）**：借 `translation_status.updated_at`——資源×語言粒度的唯一索引恰為
   `(shop_id, resource_type, resource_id, locale_tag)`（該表另有 `(shop_id, id)` 的
   租戶唯一索引），零新欄。
   🔴 **前提是 §4.2 的缺口已補**，本包已補。
4. **`shop_locales_version`（P7-L15）**：全店級、無欄、無寫入面、無裁定。建議放 `shops`，
   bump 點＝`shop_locales` 任何 insert／update／delete。**由第 3 包裁定並落欄。**
5. 🔴 **新增任何 stamp 欄必須經 `Catalog::CacheStamps`（唯一寫入面）且沿用 `TOUCH` 常數的
   `update_all` 形態**：`"%s = UTC_TIMESTAMP(6), lock_version = lock_version"`。
   Rails 8.1 的 `update_all` 對有樂觀鎖的 model 會自動 `+1 lock_version`，官方 opt-out 就是
   把 locking column 顯式列進更新——照抄 hash 形式會讓「改譯文的人」把「正在編輯商品的人」
   撞成 `STALE_OBJECT`。

---

## 6. 🔴 已知限制（Pending，不得讀成已完成）

| 編號 | 內容 |
|---|---|
| **P7-L1** | 🔴 **截尾鏈在今天的生產資料上不可達**。`shop_locales belongs_to :platform_locale`，而 `platform_locales` 沒有任何一列的截尾目標也在表內（`pt-BR`／`pt-PT` 的父 `pt` 不在表內；`zh-Hant`／`zh-Hans` 的父 `zh` 是禁用碼）。**bt3 正式環境快照 2026-08-25：28 列，可達截尾目標＝`[]`**。🔴 複驗要用**推導版**（只印 tag 清單無法證明那個全稱句，且 test 庫有 spec 殘留的 `zh-Hant-HK` 會多一列）：<br>`bin/rails runner 'set=PlatformLocale.pluck(:tag).to_set; fb=Limits.fetch(:i18n,:forbidden_locale_tags).map{\|v\| v.to_s.downcase}.to_set; puts set.select{\|t\| p2=t.split("-")[0..-2].join("-"); p2.present? && set.include?(p2) && !fb.include?(p2.downcase)}.inspect'` ⇒ 應為 `[]`。⇒ §C.4 步驟 2 目前只在單元測試（helper 自行補平台字典列）中生效。補平台字典是 **ML-0** 的事，不是本包 |
| **P7-L2** | 🔴 **我方的 fallback 鏈與本尊不同構**，屬 ours 分歧，**不得寫成「對齊本尊」**。本尊 Markets fallback 的官方範例全用敘述名稱（`Base Dutch`），第 3–4 階是**同一 market 的另一語言**而非 BCP-47 截尾。取得方法：鐵律 12 在測試店 `chill-love-u5q5mnzq` 實測 |
| **P7-L3** | ⚠️ **本輪研究最大的誤讀陷阱**：本尊 checkout/customer-account **extension locale 檔案**確實有五階截尾鏈（`de-DE → de → fr-FR → fr → default`，官方明文），但那是 **extension JSON 翻譯檔**，**不是** `translatableResource` 的商家內容譯文。兩者是不同子系統，不得互相引用 |
| **P7-L4** | 本尊 `translationsRegister` 對「送空字串」的實際行為、以及本尊是否把**語義空 HTML** 也視為未翻譯並回落，官方文檔只標 `value: String!` 與 `TranslationErrorCode.BLANK` ⇒ **未取得**。不得從型別反推行為 |
| **P7-L5** | 本尊是否對回落內容加註 `lang` ⇒ **未取得**。Liquid 物件面已確認無此能力（`shop_locale` 只有 `iso_code`／`endonym_name`／`name`／`primary`／`root_url`）⇒ 我方 `mark_fallback_with_lang_attribute_on` 是 **ours 加嚴** |
| ~~**P7-L6**~~ ✅ | **已取得**（2026-08-25 bt3 正式環境）：`@@eq_range_index_dive_limit = 200`、`@@range_optimizer_max_mem_size = 8388608`、MySQL `8.4.10`。與 `max_resources_per_batch: 50` 推導所用的官方預設值**相同** ⇒ 推導成立。複驗＝`SELECT @@eq_range_index_dive_limit, @@range_optimizer_max_mem_size;` |
| ~~**P7-L17**~~ ✅ | **已取得**（同上）：正式環境 `sql_mode` 含 `STRICT_TRANS_TABLES,STRICT_ALL_TABLES` ⇒ DB 層不會靜默截斷 `translations.value`。這**縮小**但不消除 `BlankValue` 選 HTML4 所防的截斷風險（截斷仍可能來自 RTE 崩潰或上游），判準不變 |
| **P7-L7** | RFC 4647 §3.4.1 的**多 range language priority list** 與 `*` 跳過規則未實作。目前 `resolve` 只收單一 locale ⇒ 不適用；**接 `Accept-Language` 前必須補**（外層要跑遍所有 range 才 fallback 到 source，不得對每個 range 各自 fallback 一次） |
| **P7-L8** | `field_key` 到 67 §B.1 三分類的**權威對照倉庫內不存在**。`Fields::MISSING` 是我方裁定；`Upsert::REQUIRED_FIELDS` 是**進度分母**，語義不同。兩者目前值相同純屬 v1 射程小，`spec/services/translations/fields_spec.rb` 有 tripwire |
| **P7-L9** | Resolve 對 `PRODUCT`／`COLLECTION` 以外 resource_type（`SHOP_POLICY`／`PAGE`／`METAFIELD`／`THEME_LOCALE_CONTENT`）的射程未定。`Translation::RESOURCE_TYPES` 目前封閉在兩值 |
| **P7-L10** | `digest` 的正規化實作本尊未公開；我方既有 `Translation.digest_for` 與 `limits.i18n.digest_normalization` 不相符，`Upsert#severity_for` 也與 67 §C.5(b) 的字元層編輯距離不同。**既有落差，不在本包射程**（鐵律 20.5）。讀取端**不得**自行重算 digest 當判準，只讀 `translations.outdated` 欄 |
| **P7-L11** | 🔴 **繁簡誤借稽核（`script_mismatch`）本包一律棄權，不是零筆**——見 §7 |
| **P7-L18** | 🔴 **`Resolve` 的讀取端 fast-path 是刻意的假陰性**：超過 `read_fast_path_max_bytes`（1024）的 `:html` 值一律當成有內容，不 parse。⇒ 一個「體積大但語義空」的譯文列在前台會顯示成空白區塊而不觸發 fallback。寫入端會擋住新的這種列（判空刪列），舊列由 `translations:audit` 掃出 ⇒ 殘餘窗＝立規之前就存在的大型空值列。接受，因為另一側（讀取端誤判成空）會讓前台顯示原文蓋掉真譯文 |
| **P7-L19** | ⚠️ **`Translations::Audit` 是分鐘級任務**：每個 html 欄列要跑判空＋sanitize 兩次 parse（本機量級 ~50ms/列），5 萬列的店一次 audit 約十分鐘（審查 C6 的外推）。已改成逐列短 transaction（不再持長鎖）＋每 500 列印進度；**慢是接受的，鎖不是**。若日後要縮短：先分頁、不要把 parse 搬回 transaction 內 |
| **P7-L20** | ⚠️ **`BlankValue.text_bearing?` 是刻意不精確的**：它用正則剝標籤而非 parser（因為它要偵測的正是 parser 的資料遺失，共用 parser 就共用盲點）。只處理數值字元參照與一份**不可見具名參照白名單**；白名單外的具名參照一律當可見內容 ⇒ 落在「報錯而不是刪列」那一側 |
| **P7-L12** | 遙測只發 `ActiveSupport::Notifications`，倉庫內**沒有任何 metrics backend**（無 StatsD／OpenTelemetry），所以目前**沒有訂閱者**——這是正確狀態不是缺口。接 metrics 時採「View 丟高基數屬性 → 設 cardinality limit → 超限合併成 `otel.metric.overflow`」，不自創截斷規則 |
| **P7-L13** | 67 §C.4(d) 的「落到步驟 3 以後」寫於 market 維度還在、步驟編號為 5 的版本；刪欄後步驟重編為 4 而該句未同步 ⇒ 「步驟 3」現在指到 base row。我方採 `depth >= 1`（只要沒命中請求語言就記），涵蓋兩種讀法，`depth` 欄位本身區分「走了鏈」與「落到 base」。**這是 ours 的解讀，不得寫成「照 §C.4(d) 字面實作」** |

---

## 7. 🔴 需使用者裁定（本包不做，命中鐵律 17.3 例外）

**繁簡誤借偵測要不要引入 OpenCC 的字表？**

- 可靠的繁簡誤借判別需要繁簡字表。**本輪調查所及**唯一成熟的公開字表是 OpenCC 的
  `STCharacters.txt`／`TSCharacters.txt`，授權為 **Apache-2.0**
  （<https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE>，2026-08-25 複驗）。
  🔴 「唯一」未經窮舉，僅代表本輪搜尋範圍。
- 鐵律 9 逐字：「Apache-2.0 可用但有專利授權與 NOTICE 保留義務，混入前法務面要知情。」
  ⇒ 這是**計畫外的授權裁定**，命中鐵律 17.3 的例外，不在本包擅自做。
- 本包的處理：`Translations::Audit::ABSTAINED` 明文登記該規則「未執行」，
  **絕不回報 0 筆**（回報 0 筆＝宣稱掃過且乾淨＝把未取得寫成事實，違反鐵律 19）。
  守衛＝`audit_spec.rb` 的「script_mismatch 一律登記為棄權」＋對應突變。
- 裁定「引入」的話，同一個 PR 要一併交付：`NOTICE` 檔、attribution、
  `docs/specs/107-external-adoption-register.md`（尚未建立，隨合併版總方案 R-8 引入）條目。
- 登記落點＝`docs/specs/91-pit-register.md` §3（本包的 P7 條目，本 PR 一併入籍）。
- ⚠️ 另有 **P7-L16 未取得**：OpenCC 詞庫對電商領域詞（加入購物車／結帳／運費／退款／庫存）
  的覆蓋率未知（`TWPhrases` 共 **819 個詞條**＋6 行註釋＝825 行，以資訊科技與一般詞彙為主；
  2026-08-25 以 `wc -l` 與 `grep -vc "^#"` 複驗）⇒ 引入後實際能抓到多少
  仍待量測。
- ⚠️ 另有 **P7-L13 未取得**：字形啟發式的誤判率是在 CLDR `exemplarCity`（838 個平均 3.6 字的
  **地名**）上量的，**不得外推**到商品標題／選項名／政策條款。

---

## 8. 驗證

```bash
bundle exec rspec spec/services/translations spec/services/locales spec/requests/product_translations_spec.rb spec/requests/translation_csv_spec.rb
```

突變驗證（初始 18 格 ＋ 整合修復輪 22 格）＝`docs/worklog/2026-08-25-第7包譯文解析.md`
的兩張突變表。🔴 表中另註明**兩道結構上不可達**的 fail-closed 守衛
（`fallback_chain.rb` 的 `never_pair?`、`resolve.rb` 的 scope 跳過），它們刪掉不會紅、
不在突變射程內，**不得**宣稱有測試證明其有效。

稽核任務：

```bash
bin/rails translations:audit
```
