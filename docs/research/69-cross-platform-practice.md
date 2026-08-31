# 69 — 官方文檔以外的來源：13 條深挖（V-180～V-188 ＋ B-5／B-6／C-3／E-1）

> **本檔的用途**：使用者裁定「**深度分析和研究 shopify 對這些問題的官方文檔**如何處理。**如果官方文檔沒有相關介紹，可以到網上搜索其他相關的網站／文檔**如何介紹這些問題如何解決。」
> 68 號已把 `help.shopify.com` 與 `shopify.dev` 掃過一輪，17 條裡 **9 條查不到（V-180～V-188）**、**4 條 Shopify 根本沒有對應功能（B-5／B-6／C-3／E-1）**。
> **本檔專責這 13 條，而且刻意不走 Shopify 官方站**——改查：官方原始碼、競品官方文檔、標準組織與 PSP 官方文檔、法例原文與主管機關指引、廠商技術文章、論壇 staff 回覆。
>
> **查證日**：2026-08-12。**只新增本檔，未改任何既有檔案。**「要改哪些檔案」一律只列清單。
>
> 🔴 **四條凌駕規則**
> 1. **使用者裁定 > Shopify 做法 > 業界慣例**。本檔找到的業界慣例**不推翻**任何既有裁定，只提供「Shopify 沒答案時的參考座標」。
> 2. **寫錯的事實比缺漏的事實傷害大**。挖不到就寫挖不到，並在 §E 列出查過哪些來源，讓下一個人不用重查。
> 3. **來源分級必須明寫**（§0.1）。**不得把部落格寫得像官方事實。**
> 4. 🔴 **E-1 不下任何法律結論**。只陳述「存在哪些規範、業界怎麼做」，**需法務覆核**。

---

## 0.1 出處分級（本檔沿用 62 §0.3 並擴充；由強到弱）

| 等級 | 意義 | 本檔用量 |
|---|---|---|
| `src` | **官方原始碼**（可讀的一手實作，含其 API reference 對原始碼的逐行引述） | 4 |
| `law` | **法例原文／主管機關發布的指引**（香港海關、通訊局、立法會研究部、CMA、FTC） | 6 |
| `std` | **標準／協定規格站官方文本**（ucp.dev 規格、Google Search Central、Google Merchant） | 5 |
| `alt` | **競品／PSP／ERP 的官方文檔**（Adyen、Stripe、Datatrans、Airwallex、Oracle NetSuite、BigCommerce、WordPress/WooCommerce dev docs） | 9 |
| `vendor` | **廠商技術文章／app help center**（Crowdin、Orbe、Xotiny、Matrixify） | 5 |
| `staff` | **論壇官方 staff 回覆** | 1 |
| `blog` | **一般部落格／內容行銷文**（含 app 廠商的 SEO 部落格） | 3 |
| `dev`／`help` | Shopify 官方文檔（本檔只在**補正 68 號既有結論**時引用） | 3 |
| `ours` | 我方推論 | — |

> ⚠ **本檔的 `blog` 級來源有一個特殊陷阱，必須先講**：`craftshift.com` 與 `rubikify.com` 兩站在 combined listings 這個題目上**作者同為 `umid`／`Umid`**，且兩站都在推銷同一個 app。**它們不是兩個獨立來源，是同一個來源的兩個網域。** 本檔在 V-187 只把它們算作 **1 個** `blog` 級來源。

---

## 0.2 一覽表（13 條結案狀態）

| # | 題目 | 本輪狀態 | 最強新證據等級 |
|---|---|---|---|
| **V-180** | 非拉丁字集的 handle 官方規則 | **縮小（並排除一條查法）** — Shopify handleize **不開源**（一手確認），官方原始碼路線**永久關閉**；但找到**同構的開源實作**（WordPress）佐證「折疊拉丁變音／保留非拉丁」是業界成法 | `src` |
| **V-181** | 全形字元、`_`、空輸入 | **仍未知**（全形完全查不到）；`_` 與空輸入取得**競品開源實作**的對照答案 | `src` |
| **V-182** | 原生翻譯 CSV 是否存在、空白語義 | 🔴 **前提推翻＋部分結案** — Shopify **有原生翻譯 CSV 匯出／匯入**（Settings → Languages），且模型是**「覆寫既有翻譯」勾選框**，不是 Matrixify 的「空白＝刪除」。**B-3 的翻面裁定必須重審** | `help` ＋ `vendor` |
| **V-183** | handle 官方字元上限 | **縮小** — 255 現有**兩個互相獨立**的第三方出處；官方仍零出處 | `vendor` ×2 |
| **V-184** | 手填重複 handle：拒絕 or 加尾碼 | **縮小** — API／CSV 路徑確有 `Handle has already been taken` 這個**拒絕**錯誤；admin UI 表單路徑仍未證。競品慣例分成兩派 | `staff`（弱）＋ `alt` |
| **V-185** | 顯示價≠結帳價的官方合規說明 | **結案（負面）** — Shopify 官方無此說明；但**外部主管機關有明文**，見 E-1 | `law` |
| **V-186** | UCP default-on、`.well-known/ucp` | 🔴 **大部分結案** — `/.well-known/ucp` **確為規格明定路徑**（UCP spec 2026-04-08 ＋ Google Merchant 官方指引），且**必須公開可讀、不得要求驗證**。剩「Shopify 是否自動輸出」未知 | `std` ×2 |
| **V-187** | Combined Listings 子商品 canonical | **縮小** — 唯一來源（1 個 `blog`，非 2 個）稱 child **self-canonical**；Google 官方對「multi-page 變體」的規範**不要求** child→parent canonical，與 self-canonical 相容 | `std` ＋ `blog` |
| **V-188** | exponent=3 幣別的官方立場 | 🔴 **改由 PSP 側結案** — Shopify 側仍無立場；但 **PSP 側的答案完全確定且互相矛盾**：Adyen＝3 位、Datatrans＝3 位、Airwallex＝**十進位主單位字串**、Stripe＝自有表覆蓋 ISO。**這正面證實了鐵律 3「PSP 未宣告一律 reject」是對的**<br>🔴 **2026-08-31 更正（19.5）**：Airwallex 的「字串」判定**有誤**——一手複驗（airwallex.com/docs/api/data_types 逐字 "$9.99 is represented as 9.99"＋payment_intents create schema `amount: number`）：wire form 是 JSON **number**、非字串（當日所讀 platforms 範例的字串形＝後端強制轉型容忍、非契約）。「十進位主單位、非 minor units」的核心結論**維持正確**；65 §D 已落成第三格式 `decimal_number`（R7），decimal_string 的實證代表改由 PayPal 承接（value 官方 pattern 為 string，取證 2026-08-31）。四家四種算法的總結不受影響（現為五家三格式，見 65 §D.4） | `alt` ×4 |
| **B-5** | SKU 強制唯一 | 🔴 **結案** — **Shopify 是異類**。WooCommerce／BigCommerce／Magento／NetSuite **一律硬唯一**，且 NetSuite 明文說重複 SKU **會讓訂單同步失敗** | `src` ＋ `alt` ×3 |
| **B-6** | 變體獨立 URL | 🔴 **結案（並補正 68 號）** — Google 官方**要求**每個變體有可識別的獨立 URL，並定義**兩種都合規**的模式；Shopify 預設＝Google 的 single-page 模式，Combined Listings＝Google 的 multi-page 模式。**兩者都是 Google 官方支援形態，不是「Shopify 刻意不做」** | `std` ×2 |
| **C-3** | 地區重導的 recommendation banner | 🔴 **補正 68 號** — Shopify **曾經有第一方 banner**（Geolocation app），2025-03-24 移除；其預設值（裝了就開、關掉 14 天不再顯示）是可直接引用的參數。Google 官方**明確反對**自動重導 | `help` ＋ `std` ＋ `vendor` |
| **E-1** | 顯示價≠結帳價的法遵 | 🔴 **香港有明文規範存在**（不是空白地帶）：TDO Cap 362 §13E 誤導性遺漏 ＋ 海關／通訊局《一般指引》第 2.20 段直指「廣告價應與**結帳時**實收價相符」。**⚠ 需法務覆核，本檔不下結論** | `law` ×4 |

---

# A. 第一組：Shopify 官方文檔沒寫的（V-180～V-188）

## V-180 非拉丁字集的 handle 規則

**Shopify 官方文檔**：**沒有。** 68 號已逐頁掃過 `shopify.dev/docs/api/liquid/basics` 與 `filters/handleize`，只有四條 ASCII 導向的規則，對非拉丁字集通篇沉默。本輪未發現新的官方頁面。

**其他來源怎麼說**

1. 🔴 **官方原始碼路線本輪確認為「不存在」**（`src`，一手）
   `Shopify/liquid` gem（MIT，即本專案鐵律 9 允許使用的那個）的 `lib/liquid/standardfilters.rb` 內**完全沒有 `handleize`／`handle` 這兩個 filter**。本輪逐一列出該檔定義的 60 個 filter（size／downcase／…／sum），確認 handleize **不在其中**。
   ⇒ **`handleize` 是 Shopify 閉源 storefront renderer 的私有實作，不在任何 Shopify 開源專案裡。**
   ⇒ **「去讀 Shopify 原始碼」這條查法可以永久劃掉**，寫進 §E 讓後人不用重查。

2. **`ActiveSupport::Inflector.parameterize` 不是答案**（`src`／Rails 官方 API 文檔）
   Rails 的 `parameterize` 內部先呼叫 `transliterate`，而 `transliterate` 的文檔行為是「把非 ASCII 換成 ASCII 近似字；**沒有近似字的換成替代字元，預設為 `?`**」，之後 `parameterize` 再把 `?` 收斂成分隔符並去頭尾 ⇒ **純 CJK 輸入的結果是空字串**。
   ⇒ 這與 68 號 4 個 `press` 來源觀測到的「Shopify 保留 CJK」**方向相反**。**Shopify 的 handleize 不是 Rails parameterize，也不是它的薄包裝。**
   ⚠ 本輪**未能實跑驗證**（容器的 `gem install activesupport` 被 proxy 擋下，403）。以上為 Rails 官方 API 文檔的行為敘述，**不是實測**。

3. 🔴 **找到一個「同構的開源實作」——WordPress**（`src`／WordPress 官方 developer reference 逐行引述原始碼）
   WordPress 的 slug 產生管線是兩段式，而**這兩段合起來的行為，正好就是 68 號在 Shopify 上觀測到的那個「分兩類」行為**：
   | 段 | 函式 | 行為 |
   |---|---|---|
   | 1 | `sanitize_title()` | `$context === 'save'` 時**先呼叫 `remove_accents()`**，把拉丁系變音符號折成 ASCII，再交給 filter |
   | 2 | `sanitize_title_with_dashes()` | 對通過 UTF-8 檢查的字串做 `mb_strtolower` 後呼叫 `utf8_uri_encode($title, 200)`，把**剩下的非 ASCII 轉成 percent-encoded octet 保留**（不是丟棄）；並刻意保護既有的合法 `%XX` 序列不被破壞 |
   ⇒ **WordPress ＝「拉丁變音折疊，非拉丁保留（以 percent-encoding 形式）」**，與 68 號整理的 Shopify 兩類行為表**逐項對應**。
   ⇒ 這**不是** Shopify 行為的證據（不同公司、不同程式碼），但它證明：**「折疊拉丁 ＋ 保留非拉丁」是一個有開源實作、有明確理由（URL 可讀性 vs 資料保全）的成熟做法，不是 Shopify 的怪癖。**
   ⚠ 另注意 WordPress 在此處硬編了 **200** 的長度上限（`utf8_uri_encode($title, 200)`），與 `wp_unique_post_slug()` 內的 `_truncate_post_slug($slug, 200 - …)` 一致 —— 與 V-183 的 255 不同源、不可互相佐證。

**業界慣例**：CMS／電商的 slug 產生**分成兩派**，且各自有一致的內在邏輯：
- **保留派**（WordPress、Django `slugify(allow_unicode=True)`、觀測到的 Shopify）：URL 出現 percent-encoding，但資訊不遺失、不會撞出空 slug。
- **折疊／剝除派**（Rails `parameterize`、Django 預設、Magento 的 `url_key` 轉寫）：URL 全 ASCII，但**非拉丁標題會產生空字串**，必須另有 fallback —— 這正是我方（依裁定）所在的那一派，**而我方的 `{resource}-{token8}` fallback 正是這一派的必要配件，不是多餘設計。**

**建議處置**
- **我方行為不變**（裁定已定死 ASCII-only）。
- 🔴 **論述要改一個字**：68 號說「無一手來源」——現在可以更強：**「Shopify 的 handleize 不開源，官方原始碼不存在；本專案對 Shopify 此行為的一切描述永遠只能是 `press`／`test` 級，不可能升到 `dev` 級。」** 這句話讓 V-180 從「還沒查到」變成「查法已窮盡」。
- 我方 `{resource}-{token8}` fallback 的**論述**可以加一句業界佐證：**折疊派平台一律需要 fallback**（`ours` 推論，但有 Rails／Magento 的行為支撐）。

**仍未知**：Shopify 究竟在哪個 Unicode block 上劃「折疊 vs 保留」的界線。**這條在 Shopify 開源之前不可能有官方答案**，唯一可升級的路徑是 dev store 大量實測（成本高、收益為零，因為我方行為不受影響）。⇒ **建議把 V-180 標為「已窮盡，永久掛帳」，不再排查證工時。**

---

## V-181 全形字元、`_`、空輸入

**Shopify 官方文檔**：**沒有**（同 V-180）。

**其他來源怎麼說**

| 子題 | 找到什麼 | 等級 |
|---|---|---|
| **全形字元（`Ａ`／`１`／`　`）** | 🔴 **完全查不到。** 沒有任何平台文檔、原始碼或論壇討論處理過「全形 ASCII 在 slug 產生器裡會發生什麼」。連 WordPress／Rails 的文檔都沒提 NFKC。 | — |
| **`_` 底線** | WordPress `sanitize_title_with_dashes()` 的字元處理是**保留** `_`（它只把空白與特定標點換成 `-`）；Rails `parameterize` 的預設 regex 是 `[^a-z0-9\-_]`，**明文把 `_` 列入允許集**。⇒ **兩個開源實作都保留 `_`**，與 68 號在 kurand.jp 觀測到的「handle 中出現 `_`」一致。 | `src` ×2 |
| **空輸入／全分隔符輸入** | WordPress `wp_unique_post_slug()` 不處理空 slug（空 slug 由 `wp_insert_post` 另行以 post ID 補），Rails `parameterize("")` 回空字串。⇒ **兩個開源實作都會回空**，都把「空了怎麼辦」推給上層。 | `src` ×2 |

**業界慣例**：`_` 保留（兩派一致）；空輸入回空、由上層決定 fallback（兩派一致）；**全形無慣例可言，因為沒人寫過。**

**建議處置**
- `_ → -`：我方目前的做法（轉成 `-`）**與兩個開源實作相反**。這不是錯，但要**知情**：Shopify 實測也保留 `_`。⇒ 建議把 `handle` 區塊的 `_` 處置改標成**「刻意偏離，理由＝URL 一致性」**，或改成保留（本檔不代決，屬 UI/SEO 偏好）。
- **全形 → NFKC 正規化**：維持我方做法。它是**我方的獨立決定，沒有任何外部佐證，也沒有任何外部反對**——寫規格時不得寫成「業界慣例」。
- **filter 端 `h-{sha1}` fallback 只在空輸入時觸發**：與兩個開源實作的「空進空出、上層補」形態一致，維持。

**仍未知**：**全形字元的處置，本輪零收穫**（查過的來源見 §E）。`_` 與空輸入雖有競品佐證，但**仍不是 Shopify 的答案** ⇒ V-181 不結案，但**未知面從三項縮到一項半**。

---

## V-182 原生翻譯 CSV 是否存在、空白語義

**Shopify 官方文檔**：🔴 **有，而且 68 號的研判是錯的。**
68 號寫「研判**原生能力薄弱或不存在**」。實際上 Shopify **有完整的原生翻譯 CSV 匯出／匯入**，只是**不在 Translate & Adapt app 裡**，而在 **admin 的 Settings → Languages**（`help`：`help.shopify.com/en/manual/international/localization-and-translation`）。這就是為什麼 68 號在 Translate & Adapt 的說明頁上找不到它。

本輪從官方 help 頁確認的事實：
- **匯出**：Settings → Languages → Export → 選語言與內容類型 → **CSV 以 email 寄出**（非同步）。
- **匯入**：Settings → Languages → Import → 上傳 → **選擇是否覆寫既有翻譯** → 檢視後確認。
- **欄位（8 欄）**：`Type`／`Identification`／`Field`／`Locale`／`Market`／`Status`／`Default content`／`Translated content`。
- **`Status` 欄的三個值**：`Translated`／`Outdated`／`Untranslated`。（`Outdated` ＝ 來源語言內容改過但譯文沒跟上 —— 這正是 67 §C.5「過期偵測」的 Shopify 對應物，**而且它已經是匯出檔的一等公民欄位**。）
- 🔴 **匯入的核心語義是一個勾選框**：「覆寫任何既有翻譯」。**不勾＝只匯入新譯文、不取代既有的。**
- **官方 help 對「`Translated content` 留空會怎樣」完全沒寫。**

**其他來源怎麼說**
- **Crowdin 的 Shopify Translate & Adapt 整合產品頁**（`vendor`，`store.crowdin.com/shopify-translate-adapt`）：獨立佐證上述 8 欄的欄位名與順序，並描述其回匯流程會**原樣保留** market-scoped 的列、handle 與任何額外欄位。⇒ 佐證「Shopify 的 CSV 是**逐列對位**的格式，不是自由格式」。
- **Shopify Community #209362 第 11 樓**（`staff`／2023-12-25，回覆者 `richbrown_staff`）：明講**Translate & Adapt 本身沒有 CSV 功能，功能在 Settings → Languages**，且**必須先為店鋪加入至少一種語言**才會出現。

**業界慣例**：翻譯匯入的空白語義**沒有共識，而且兩種語義都真實存在**：
- **Matrixify 派**：空白＝**刪除該譯文**（68 號 B-3 引用的即此）。
- **Shopify 原生派**：以**「是否覆寫」的顯式旗標**取代對空白的隱式解讀 —— 也就是說，**Shopify 根本沒有選邊，它把這個決定做成了使用者的一次明示動作。**

**建議處置**
- 🔴 **B-3 必須重審。** 68 號把 `blank_means_unchanged` 翻面（改成「空白＝刪除」）的唯一依據是 Matrixify 這個第三方事實標準。**現在已知 Shopify 原生不是那個模型。** 「全部跟隨 Shopify」的字面結論**不是翻面，而是改成「顯式 overwrite 旗標」**。
- **建議的跟隨形態**（`ours`，但每一項都對應到已確認的 Shopify 行為）：
  1. 匯入時提供 `overwrite_existing: bool`（預設 **false**，即只補新的）。
  2. 空白 `Translated content` 的語義**明文定義為「本列不做任何事」**，**不**解讀成刪除 —— 刪除必須是另一個明示動作（例如專用的 `__DELETE__` 標記或後台批次刪除）。理由：**靜默刪除是不可逆操作，不該由「儲存格是空的」這種易誤觸的狀態觸發。**
  3. 匯出欄位對齊 Shopify 的 8 欄（`Type`／`Identification`／`Field`／`Locale`／`Market`／`Status`／`Default content`／`Translated content`），**尤其 `Status` 三值要落地**——它同時解決了 67 §C.5 的過期偵測要往哪裡輸出。
  4. 匯出走**非同步 ＋ email／通知**（Shopify 如此，也符合我方 outbox 形態）。
- **要改哪些檔案**（僅列清單）：`config/limits.yml` `i18n` 區塊的 `blank_means_unchanged`（68 號要求翻面 ⇒ **本檔建議不翻面，改成 overwrite 旗標**）；`docs/specs/67-multilingual.md` §E（匯入匯出格式與空白語義）、§C.5（`Outdated` 接上匯出欄位）；`docs/handoff/2026-08-12-open-decisions.md` B-3 條（結論再反轉，須標明依據是本檔）。

**仍未知**：`Translated content` 留空時，Shopify **在勾與不勾 overwrite 兩種模式下分別做什麼** ⇒ 新登記 **V-200**。`Status` 欄在**匯入**時是否被讀取（還是純輸出欄），以及 `Market` 欄留空的語義 ⇒ 新登記 **V-201**。

---

## V-183 handle 官方字元上限

**Shopify 官方文檔**：**沒有。** GraphQL Admin API 的 `handle` 欄位型別是 `String`，schema 不帶長度約束；`shopify.dev/docs/api/usage/limits` 講的是 API 速率不是欄位長度。本輪未找到任何官方頁面寫出 handle 的字元上限。

**其他來源怎麼說**
| 來源 | 說法 | 等級 |
|---|---|---|
| Matrixify《Shopify Limits》 | handle **255**（68 號已引用） | `vendor` |
| Xotiny《Shopify Limits》 | handle **255**；同頁另列 tag 255／metafield namespace 255／metafield key 64／SEO title 70／SEO description 320／image alt 255 | `vendor` |
| —— | 兩者**互相獨立**（不同公司、不同產品、清單涵蓋範圍不同），且**數值一致** | |
| 對照組：WordPress | slug 上限 **200**（`utf8_uri_encode($title, 200)`，原始碼硬編） | `src` |

**業界慣例**：200～255 這個量級是 slug 欄位的通行區間，且 255 明顯來自 `VARCHAR(255)` 這個資料庫慣例。

**建議處置**：`handle.max_chars: 255` **維持**。註釋改成「**兩個互相獨立的第三方出處一致（Matrixify、Xotiny），Shopify 官方零出處**；本數值同時是 `VARCHAR(255)` 的通行慣例」。**V-183 從「單一二手出處」升級到「雙獨立二手出處」，但不得標成官方事實。**

**仍未知**：官方出處。取得方式只剩 dev store 以超長標題實測（本輪無 dev store）。**優先級建議降到最低**——數值本身已與我方相同，實測的邊際價值接近零。

---

## V-184 手填重複 handle：拒絕還是加尾碼

**Shopify 官方文檔**：**沒有直接說明。** 官方講的自動加尾碼（`potion` / `potion-1`）描述的是**同名標題自動生成**的情境，不是商家手填。

**其他來源怎麼說**

1. **Shopify 確實存在一個「拒絕」的錯誤字串**（`staff` 弱／論壇多例）：`Handle has already been taken`。它在 **API 與 CSV 匯入**兩條路徑上都被回報（community 201996、251412／2229673，2023-09-18；後者無 staff 回覆）。
   ⇒ 這是本輪對 V-184 最重要的一步：**「Shopify 一律自動加尾碼」這個假設被證偽了** —— 至少在**非 UI 路徑**上，Shopify 會**回錯誤而不是靜默改寫**。
   ⚠ 該串同時有一則**混淆觀測**：有人說 CSV 裡把 handle 留空、第二次匯入仍拿到同樣的錯誤。若屬實，代表「留空 ⇒ 由標題生成 ⇒ 生成結果撞號 ⇒ **也是報錯而不是加尾碼**」。**本輪無法判定該觀測是否為使用者操作誤解**，不採信為事實。

2. **競品分成兩派，而且兩派都很堅決**：
   | 平台 | 手填／匯入的重複 slug 行為 | 等級 |
   |---|---|---|
   | **WordPress** | **自動加尾碼，從 `-2` 起算**。`wp_unique_post_slug()` 原始碼是 `$suffix = 2;` 後接 `…-$suffix` 遞增 | `src` |
   | **Magento 2** | **拒絕**，錯誤字串 `URL key for specified store already exists.`；REST API 建立同名商品時也拋這個錯（magento2 issue #11266／#7298） | `alt` |
   | **Shopify（自動生成）** | 加尾碼，**從 `-1` 起算**（68 號已證） | `dev`＋`test` |

**業界慣例**：**「自動生成撞號 ⇒ 加尾碼」是共識；「使用者明確輸入的值撞號 ⇒ 怎麼辦」沒有共識。** 兩派的分界線正好落在「這個值是誰決定的」——系統生成的可以改，使用者輸入的不敢改。

**建議處置**：🔴 **維持我方 `collision_strategy_explicit: reject`**，並把理由從「保守失效」升級成有據可循的：
- **Shopify 自己在 API 路徑上就是 reject**（`Handle has already been taken`）；
- **Magento 全路徑 reject**；
- **WordPress 加尾碼**是 CMS 慣例，但 WordPress 的 slug 不是商品識別鍵，語境不同。
- 生成路徑維持 `-1` 起算（跟隨 Shopify，68 號已裁）。**注意：生成 `-1` ＋ 手填 reject 是兩條不同規則，實作時不得共用同一個 strategy 參數。**

**仍未知**：**admin UI 表單**手填重複 handle 時的行為（是即時驗證擋下、送出後報錯、還是靜默加尾碼）。API 路徑已有錯誤字串佐證，UI 路徑仍需 dev store 實測。⇒ **V-184 不結案，但範圍從「全平台」縮到「僅 admin UI 表單」。**

---

## V-185 顯示價 ≠ 結帳價：Shopify 有無官方合規說明

**Shopify 官方文檔**：🔴 **結案（負面結論）。** 68 號已逐頁查過 help 的價格／結帳章節；本輪再從外部反向搜尋（找任何引用 Shopify 官方合規立場的第三方文章），**同樣一無所獲**。Shopify 對此只有排錯導向的社群回覆，**沒有任何官方合規敘述，也沒有價格鎖定選項。**

**其他來源怎麼說**：本條的實質內容**全部在 E-1**（香港與各法域的規範、以及業界怎麼做）。此處只記結論：**Shopify 的沉默不是「沒有規範」，是「Shopify 把這個責任留給商家」。** 外部主管機關對這件事**有明文**（見 E-1）。

**業界慣例**：見 E-1。

**建議處置**：V-185 **標為已結案（Shopify 側確認為「無」）**，並在 62／15 的相關章節把「Shopify 無官方說明」與「因此沒有規範」**明確切開**——這兩句話在日後回頭看時意義完全不同。合規面的處置**移交 E-1**。

**仍未知**：無（Shopify 側已窮盡）。

---

## V-186 UCP 是否 default-on、`.well-known/ucp` 是否自動輸出

**Shopify 官方文檔**：**未回答商家端的 default-on 問題**（68 號已查）。

**其他來源怎麼說** — 🔴 **本條有重大進展，而且直接影響我方 62 §H.3 的規格。**

1. **UCP 規格站的正式規格本文**（`std`，`ucp.dev/2026-04-08/specification/overview/`，版本日期 **2026-04-08**）：
   - 規格**確實定義了 discovery 機制**，商家在 **`/.well-known/ucp`** 發布自身的 profile，作為**能力協商與金鑰發現的標準入口**。
   - 規格分層：`Checkout`／`Cart`／`Catalog`／`Order`／`Identity Linking`（走 OAuth 2.0）／`Payment Handlers`。
   - 🔴 **協定版本相容性與能力協商是分開的兩件事**（同一個 business 可同時支援多個協定版本）。
   - 能力識別字用**反向網域命名**（如 `dev.ucp.shopping.checkout`、`com.example.payments`），**不需要中央註冊**。
   - 付款採「Trust Triangle」：平台取得的是**不透明憑證**而非原始金融資料，以壓低 PCI-DSS 範圍。

2. **Google Merchant 的 UCP profile 官方指引**（`std`，`developers.google.com/merchant/ucp/guides/ucp-profile`）：
   - profile ＝ 一份 **JSON**，公開宣告伺服器的 UCP 能力與設定，供 Google 做 server-selects 架構的能力協商。
   - 🔴 **路徑就是 `/.well-known/ucp`，且明文要求「公開可存取、不得要求任何驗證」。**
   - 內容含：UCP 版本與 services、capabilities（checkout／fulfillment／discounts／order management／identity linking）、payment handler 設定、**JWK 格式的簽章金鑰**（用於驗證 webhook 與已簽名訊息）。
   - **由 business 自己在自己的伺服器上發布**；該頁**完全沒提到 Shopify 或任何平台會代為自動輸出**。

**業界慣例**：`/.well-known/{protocol}` 是 IETF 既有慣例（`.well-known/oauth-authorization-server` 在 UCP 的 identity linking 章節也被當範例引用），UCP 只是照做。

**建議處置**
- 🔴 **我方 62 §H.3 規劃的 `/.well-known/ucp` 端點，路徑是對的** —— 這條之前只是我方猜測，現在有**規格本文 ＋ Google 官方指引**兩個 `std` 級出處。**可以把該端點從「推測」升級成「有規格依據」。**
- 🔴 **「不輸出指向 404 的 `ucp_discovery_url`」這條我方規定，現在有了外部支撐**：規格明文要求該檔**公開可讀且不要求驗證**，而 profile 內含**簽章金鑰**與**能力宣告**——輸出一份不完整或不可讀的 profile，等於對代理宣告了做不到的能力。**這條要從「我方判斷」升格為「規格衍生的硬約束」。**
- **資料模型要補的欄位**（第二階段實作前就要在 schema 裡留位）：協定版本清單（複數）、capability 識別字（反向網域字串）、payment handler 設定、**JWK 金鑰輪替**。其中 **JWK 輪替是我方目前完全沒有的能力**，且它不是 SEO 問題是**安全問題**。
- **要改哪些檔案**（僅列清單）：`docs/specs/62-seo-geo.md` §H.3；`docs/research/43-platform-ecosystem-and-wiring.md`（`agentic` 通路）；`config/limits.yml` `seo` 的 ucp 區塊。

**仍未知**：**Shopify 是否為每個店鋪自動輸出 `/.well-known/ucp`、商家端是否 default-on。** 規格與 Google 的指引都把發布責任寫給 business，**沒有任何一方描述「平台代發」這個形態**。⇒ V-186 保留，但未知面**只剩 Shopify 側的一句話**。另新登記 **V-202**（UCP profile 的最小必要欄位集與版本協商失敗時的行為，規格 overview 未展開）。

---

## V-187 Combined Listings 子商品的 canonical

**Shopify 官方文檔**：🔴 **本輪把 dev docs 也讀了（68 號只讀了 help），結論仍是沒有。**
- `shopify.dev/docs/apps/build/product-merchandising/combined-listings`：給出 parent／child 資料模型（parent **不可購買、無庫存、無銷售數據**；child 各自有自己的圖片與 URL；銷售掛在 child）、方案限制（Plus）、通路限制（僅 Online Store，**不支援 POS／第三方通路／訂閱**）、上限（child ≤ **60**、parent options ≤ **3**、跨 child 變體總數 ≤ **2000**）。
- `…/build-for-combined-listings`：給出 GraphQL 面 —— `combinedListingRole`（`PARENT`／`CHILD`）、`combinedListing`、`parentProduct`、`combinedListingChildren`，以及 `productSet`／`combinedListingUpdate` 兩個 mutation。
- 🔴 **兩頁都對 URL、canonical、SEO 完全沉默。** 只說「主題必須改造才能支援 combined listings」，不說改造後 canonical 長什麼樣。

**其他來源怎麼說**
1. **Google 官方（`std`）—— 這才是本條真正該對齊的東西。** Google 的 product variant 結構化資料文檔定義**兩種**站台形態：
   - **single-page**：所有變體掛在同一個基底 URL 上以 query param 切換 ⇒ 🔴 **要求整個 `ProductGroup` 只有一個 canonical URL**（即去參數的基底 URL）。
   - **multi-page**：每個變體自己一個 URL、切換要換頁 ⇒ 🔴 **「單一 canonical」這條要求明文不適用**，各變體頁**地位對等**。
   ⇒ **Combined Listings 就是 multi-page 形態** ⇒ 依 Google 的規範，child **不應該**被 canonical 指向 parent（那會把它們從索引裡拿掉，等於白做）。
2. **`blog` 級來源（僅 1 個，不是 2 個）**：`craftshift.com`（作者 Umid，2026-05-10）與 `rubikify.com`（作者 umid，2026-02-25／2026-08-04 更新）**同一作者、同一 app 廠商**，兩站都稱 child「canonical 指向自己，這是 Shopify 的預設行為」，並警告不要把 sibling 互指 canonical。**兩篇皆無測試數據、無案例、無排名資料**，屬於 SEO 原則的複述 ⇒ **不可當事實引用。**

**業界慣例**：multi-page 變體 ⇒ **各頁 self-canonical**，這在 SEO 界沒有爭議，且與 Google 官方對 multi-page 形態的敘述一致。

**建議處置**：我方若做 Combined Listings 等價物，**child 預設 self-canonical**（與 62 §B.4「一律 self-canonical」一致）。**論述依據改成 Google 官方的 multi-page 規範，不要引用那兩篇 blog** ——它們是同一個來源，且無證據。

**仍未知**：Shopify 對 child 的**實際輸出**仍未一手驗證（需要一個已啟用 native Combined Listings 的 Plus 店；本輪的容器出站被 proxy 擋，無法直接抓任意店鋪的 canonical）。⇒ V-187 保留。另新登記 **V-203**：**parent 商品本身是否有可索引 URL、是否進 sitemap** —— 官方只說 parent 不可購買，**沒說它在 online store 上是什麼**，而這對我方 sitemap／canonical 規則是必答題。

---

## V-188 exponent=3 幣別的官方立場

**Shopify 官方文檔**：**仍然沒有**（68 號已窮盡）。**但本條的重點根本不在 Shopify。**

**其他來源怎麼說** — 🔴 **PSP 側的答案完全確定，而且四家四個樣。這才是要對齊的對象。**

| PSP／閘道 | 金額表達法 | KWD／BHD／JOD／OMR／TND | 是否自認可覆蓋 ISO 4217 | 等級 |
|---|---|---|---|---|
| **Adyen** | **整數 minor units** | **exponent = 3** | 🔴 **明文：CLP／CVE／IDR／ISK 的小數位與 ISO 4217 不同，「以本頁表格為準」** | `alt` |
| **Datatrans** | **整數 minor units** | **exponent = 3**（×1000） | 自稱**遵循** ISO 4217 | `alt` |
| **Stripe** | **整數 minor units**（預設兩位小數，「除非另有說明」） | 現行文檔的幣別清單為動態渲染，**本輪抓不到**；且**現行文檔已無「three-decimal currencies」這個章節** | 🔴 **實質上是**：`Special cases` 表把 **ISK／HUF／TWD／UGX** 的處理方式訂成與 ISO 4217 不同（如 ISK 已是 zero-decimal 幣別，Stripe 仍要求以兩位小數表達且小數必為 `00`；TWD／HUF 在**付款**時可兩位小數、在**payout** 時必須整除 100） | `alt` |
| **Airwallex** | 🔴 **十進位「主單位」**（`9.99` 就是九元九角九分），**完全不是 minor units** | 文檔未給 per-currency 小數位 | 引用 ISO 4217 定義主單位 | `alt` |

**業界慣例**：**沒有統一慣例，而且各家都知道自己不統一，所以都把小數位寫成一張自家的表。**

**建議處置** — 🔴 **這是本輪對本專案最有價值的一條，因為它把鐵律 3 從「我方的保守設計」變成「有外部證據的必要設計」。**

1. **鐵律 3 的「PSP 未宣告 minor unit 一律 reject，不得預設」＝正確，且現在有四份 PSP 官方文檔佐證。** Adyen 白紙黑字說自家表格覆蓋 ISO 4217；Stripe 的 special cases 表實質上也是覆蓋；**任何「拿 ISO 4217 exponent 當 PSP 換算基數」的實作，在 Adyen 的 CLP／CVE／IDR／ISK 與 Stripe 的 ISK／HUF／TWD／UGX 上就是錯的。** 而 **TWD 正好在鐵律 3 §H 要求的測試矩陣裡**。
2. 🔴 **PSP pack 的宣告介面必須能表達「不是 minor units」這一種。** Airwallex 用十進位主單位 —— 我方目前的 `Money::PspMinor` 型別**在 Airwallex 這種 PSP 上根本不適用**。這是一個**現有型別設計擋不住的形態**，不是參數問題。建議 PSP pack 至少宣告：`amount_format: minor_units | decimal_string`、`exponent`（僅 minor_units 時）、`divisibility_constraint`（如 Stripe payout 的「必須整除 100」）。<!-- 2026-08-31 更正註：本句的兩值枚舉已隨 Airwallex wire form 更正擴為三值（65 §D.3：minor_units | decimal_string | decimal_number）；本句原文保留為當日結論的紀錄。 -->
3. **`divisibility_constraint` 不是虛構需求**：Stripe 的 HUF／TWD payout 明文要求金額整除 100，否則不能出款。**我方若做 payout／對帳，這條會直接變成生產事故。**
4. **exponent=3 幣別本身**：跟隨 68 號的裁定（幣別可選、顯示與儲存 2 位、精度損失明文登記）。**但要補一句**：若某 PSP pack 宣告 KWD exponent=3，我方 ×100 的儲存尺度**無法無損表達**該 PSP 的最小單位 ⇒ **該 pack 必須同時宣告「儲存精度不足時怎麼辦」**，否則 pack 不合法。
5. **要改哪些檔案**（僅列清單）：`docs/specs/65-money-unit-boundary.md`（PSP pack 宣告介面新增 `amount_format` 與 `divisibility_constraint`；並記錄四家 PSP 的實證表）；`docs/specs/55-money-tax-event-inventory.md`（金額測試矩陣補「PSP 表覆蓋 ISO」的案例，至少 TWD payout 整除 100 一條）；`config/limits.yml` `currency_display`。

**仍未知**：Shopify 側仍無立場（**建議 V-188 結案為「Shopify 永久無立場」，並把本條的實質答案改掛在 PSP 側**）。新登記 **V-204**：Stripe 現行是否仍支援 KWD／BHD／JOD 作為 presentment currency，以及其「three-decimal currencies」章節是否已被移除（現行文檔的幣別清單為動態渲染，本輪抓不到）。

---

# B. 第二組：Shopify 沒有對應功能的 4 條

## B-5 SKU 強制唯一：別人怎麼解

**Shopify 官方文檔**：**無此功能**（68 號已結）。本輪補一條 68 號沒提的官方時間點：`changelog.shopify.com/posts/accurately-track-your-inventory-with-unique-skus`（**2021-11-10**）——Shopify 是**在 2021 年才加上重複 SKU 的警告**，而且**只加了警告，沒加阻擋**。⇒ **這是一個 Shopify 明知問題存在、刻意只做一半的決定，不是疏漏。**

**其他來源怎麼說** — 🔴 **Shopify 是異類。查到的每一個競品都是硬唯一。**

| 平台 | 行為 | 證據 | 等級 |
|---|---|---|---|
| **WooCommerce** | 🔴 **預設硬唯一**。`wc_product_has_unique_sku($product_id, $sku)` 查資料庫確認唯一，不唯一即拒絕（admin 顯示 `Invalid or duplicated SKU`）。提供兩個 filter 讓開發者覆寫：`wc_product_pre_has_unique_sku`（前置短路）與 `wc_product_has_unique_sku`（後置改結果） | WooCommerce 原始碼 `wc-product-functions.php` | `src` |
| **BigCommerce** | **拒絕**。API 回 `The product SKU is a duplicate`（support 討論串多例）。⚠ **但 BigCommerce 的 dev docs 本身沒有明文寫「必須唯一」**，只寫 variant 必須有 SKU ⇒ **行為明確、文檔缺漏**，與 Shopify 相反的缺漏方式 | support.bigcommerce.com 討論串；docs.bigcommerce.com catalog overview（未明文） | `alt`（行為為討論串，屬弱） |
| **Magento 2** | **SKU 是主識別鍵**，唯一性由資料庫層保證；同族的 `url_key` 撞號直接拒絕（`URL key for specified store already exists.`） | magento2 issue #11266／#7298 | `alt` |
| **Oracle NetSuite** | 🔴 **要求跨所有 item type 唯一**。官方文檔《Troubleshooting Duplicate SKUs Error in NetSuite on Order Sync》明講：同一個 SKU 同時用在 inventory item 與 kit item 上，**NetSuite Connector 的訂單同步就會失敗**；官方的修法是「決定保留哪一個，把另一個改名（如 `MYSKU` → `MYSKU-OLD`），等下一次同步」，並**明文警告不要用停用或刪除來解**（停用後 connector 仍會找到它、刪除會弄壞未完成的出貨） | `docs.oracle.com` NetSuite online help | `alt` |

**業界慣例**：🔴 **SKU 在下游系統（ERP／WMS／3PL／feed）裡是「查詢鍵」，不是「標籤」。** NetSuite 的文檔把這件事講得最白：重複 SKU 不是資料品質瑕疵，是**讓訂單同步失敗的功能性故障**，而且**沒有下游側的解法**——只能回上游改名。這就是為什麼所有以 ERP 為中心的系統都硬唯一。
Shopify 之所以敢軟唯一，是因為它的內部一切都以 `variant_id` 為鍵，SKU 對它而言真的只是一個字串欄位——**代價由接它的第三方吃下**（68 號已觀測到 Cin7／Whiplash／GoDataFeed 都把「Shopify 允許重複 SKU」寫進自己的前提）。

**建議處置**
- **軟唯一預設 ＝ 維持**（與 Shopify 一致，1:1 對齊不破）。
- 🔴 **硬唯一開關：本檔的證據強烈支持「要做」**，而且應該**照 WooCommerce 的形態做**——不是一個布林開關，而是**「預設啟用的檢查 ＋ 明確的覆寫點」**。WooCommerce 的兩段式 filter（前置短路／後置改結果）值得抄形態：前置給租戶級策略，後置給例外個案（組合包）。
- **但要注意方向差異**：WooCommerce 是**預設硬、可放寬**；我方跟隨 Shopify 是**預設軟、可收緊**。**兩者的預設值相反，錯誤處理的預設也就相反**——實作時預設值不可抄 WooCommerce。
- **這仍然是產品範圍決定，本檔不代決。** 本檔只把 68 號的「我方評估值得做」從意見升級成有證據：**四個競品全部硬唯一，且 NetSuite 官方明文說重複 SKU 會讓訂單同步失敗。**
- **要改哪些檔案**（僅在使用者同意時）：同 68 號 B-5 的清單。

**仍未知**：Salesforce B2C Commerce 的對應行為（本輪查了 dw.catalog.Product 的 script API 但未取得唯一性的明文陳述）。**不另開 V**——四個樣本已足以支持結論，第五個的邊際價值低。

---

## B-6 變體獨立 URL：Google 怎麼說、別人怎麼做

**Shopify 官方文檔**：預設無獨立 URL、`?variant=` canonical 去參數、要獨立 URL 走 Combined Listings（68 號已證，含一手實測）。

**其他來源怎麼說** — 🔴 **Google 官方對這題有明文，而且它把 68 號的定性修正了。**

1. **Google 的電商 URL 結構文檔**（`std`，`developers.google.com/search/docs/specialty/ecommerce/designing-a-url-structure-for-ecommerce-sites`）：
   - 🔴 **Google 明文建議「讓每個變體能被一個獨立的 URL 識別」。** 兩種都可以：路徑段（`/t-shirt/green`）或查詢參數（`/t-shirt?color=green`）。
   - 🔴 **當變體用的是「可省略的查詢參數」時，Google 明文建議 canonical ＝去掉該參數的 URL** ——理由是幫 Google 理解變體之間的關係。
     ⇒ **這正是 Shopify `?variant=` 的行為。** 也就是說 **Shopify 的預設不是「不做」，是照著 Google 的建議做。**
   - **明確反對用 fragment（`#…`）切變體**——Google 索引不使用 fragment。
   - 參數格式要用 `?key=value`，不要 `?value`。
2. **Google 的 product variant 結構化資料文檔**（`std`）：定義 `ProductGroup`／`hasVariant`／`variesBy`／`productGroupID`，並明分兩種站台形態（見 V-187）：**single-page 需單一 canonical；multi-page 各頁對等、該要求不適用**。每個 variant 的 `offers.url` 要指向該變體的購買頁，且**站台必須能以一個明確的 URL 直接預選該變體**。🔴 **Google 對兩種形態不表偏好。**
3. **Salesforce B2C Commerce**：其 SEO 文檔有專門的「Create Canonical URL Tags」章節（`alt`），但本輪抓到的頁面只有導覽骨架、**未取得變體 canonical 的實質內容** ⇒ 不採信。

**業界慣例**：**兩種形態並存且都合規**，選擇取決於「變體之間的內容差異有多大」——差異小（只有顏色）用 single-page，差異大（各自有標題／描述／主圖／評論）用 multi-page。

**建議處置** — 🔴 **68 號 §B-6 的一句話要改。**
- 68 號寫「**Shopify 刻意不做**〔變體加 URL〕的形態（會產生近似頁面）」。**更精確的說法是**：Shopify 的預設**就是** Google 的 single-page 形態（含 Google 建議的去參數 canonical），Combined Listings **就是** Google 的 multi-page 形態。**Shopify 兩種都做了，只是把 multi-page 那種鎖在 Plus 方案後面。**
- ⇒ 我方的「模式 B」該廢的不是「變體有 URL」這個目標，而是**「同一個 product 底下的 variant 各自掛 URL」這個資料模型**——因為那會讓一個資源有多個 canonical 候選。**改成 Combined Listings 形態（多個真實 product ＋ 合併展示）之後，模式 B 的目標（每變體可索引）反而達成了，而且是 Google 官方支援的形態。**
- **要在 62 §B.2 補的硬規則**（依 Google 官方）：single-page 模式下 `ProductGroup` 只能有一個 canonical；multi-page 模式下**禁止**把 child canonical 指向 parent；**任何模式都禁止用 fragment 切變體**；變體參數一律 `?key=value`。
- **要改哪些檔案**（僅列清單）：同 68 號 B-6 的清單，另加 `docs/research/30-seo-merchant-feeds.md`（`ProductGroup`／`hasVariant`／`variesBy` 的結構化資料輸出）。

**仍未知**：無新增。V-187 承接 canonical 的實際輸出。

---

## C-3 地區重導的 recommendation banner：那些 app 怎麼做

**Shopify 官方文檔**：68 號的結論是「Shopify **自己沒有**內建 recommendation banner，官方把『建議』推給第三方 app」。

**其他來源怎麼說** — 🔴 **這句話需要補正：Shopify 曾經有，而且是第一方的。**

1. **Shopify Geolocation app（第一方、免費）**（`help`＋`dev` changelog）：
   - 🔴 **它的形態正是 recommendation banner**：官方 help 明講該 app **只提供建議、不會依訪客位置自動調整國家或語言**；客人必須**主動接受**建議，語言與幣別才會變。
   - **預設值（可直接引用的參數）**：安裝後**建議功能自動啟用**，預設列出所有已發布的語言與幣別；🔴 **客人關掉建議後 14 天內不再顯示**（清 cookie 會重置）；另可選擇在 footer 放國家／語言下拉選單；顏色可自訂或自動取自主題。
   - **生命終點**：`changelog.shopify.com/posts/geolocation-app-removal`（貼文 **2024-02-12**）宣告移除；**2025-02-01 起不能再安裝**，**2025-03-24 完全關閉**。官方給的理由是平台本身的進展（自動重導擴大市場覆蓋、瀏覽器語言自動重導、GeoIP 併入自動重導）**降低了對「同意制在地化」的需求**。
   - 🔴 **官方明白寫出唯一的例外**：**用 EU 頂級網域（如 `example.fr`）銷售的店鋪仍然需要同意制重導，官方要他們去 app store 找第三方方案。**
   ⇒ **完整的 Shopify 立場是：先做了第一方 banner → 認為自動重導夠用了 → 把 banner 收掉 → 但在 EU ccTLD 這個法遵情境下承認自己沒有替代品。** 68 號說的「推給第三方 app」只描述了最後一格。

2. **Google 官方對「banner vs 自動重導」的表態**（`std`，`developers.google.com/search/docs/specialty/international/managing-multi-regional-sites`）：
   - 🔴 **明文「避免把使用者從一個語言版本自動重導到另一個語言版本」**，理由是這會讓使用者與搜尋引擎都碰不到全部版本。
   - **建議的替代做法**：加上指向其他語言版本的**超連結**，讓使用者自己點。
   - 🔴 **關鍵技術事實**：Google 的爬取**大多但非全部**來自美國，且**Google 不會刻意變換位置去偵測站台差異** ⇒ 依爬蟲位置動態換內容**不可靠**。
   - **要用的是顯式訊號**：`hreflang`、alternate URL、顯式連結。
   ⇒ **Google 的立場是「連結／選擇」而不是「自動重導」，而且理由是技術性的（爬蟲看不到），不是偏好。**

3. **第三方 app 實際怎麼做**（`vendor`，以 Orbe 為例，`help.orbe.app`）：
   - **預設是 Welcome Popup**（首訪詢問偏好），之後才依儲存的偏好自動重導。
   - 🔴 **明文處理爬蟲**：說明自動 IP 重導會傷 SEO（爬蟲多來自美國 IP），其做法讓爬蟲能讀到每一個在地化版本。
   - 🔴 **明文處理同意**：指出某些國家禁止未經同意就把使用者導向特定在地體驗，並點名 **GDPR**；以 popup 取得明示同意後才儲存權限。
   - 商家可切換「首訪就問」與「只在使用者跑錯體驗時才問」。

**業界慣例**：**「首訪 popup 取得同意 → 記住偏好 → 之後才自動」** 是 app 生態的通行形態，而且**三家關切點一致**：爬蟲要排除、同意要明示、偏好要記住一段時間。

**建議處置**
- **68 號的 C-3 主結論（地區重導 `enabled_default: false → true`）不因本檔改變**——那是「跟隨 Shopify」的裁定結果，本檔不推翻。
- 🔴 **但 68 號的三條護欄（排除已驗證爬蟲／反查 DNS 驗證／hreflang 必須 200）現在有了 Google 官方的技術理由**：Google 自己說它不會變換爬取位置。**這讓「排除爬蟲」從『可能被 Google 視為 cloaking 的灰色手法』變成『Google 自己描述的必要配合』。**（⚠ 這是我方讀法，Google 未明文允許排除爬蟲 ⇒ **V-116 的重寫不得寫成「Google 允許」**。）
- 🔴 **若要做 recommendation banner（超出 Shopify 現況），有現成的參數可抄，不用自創**：
  - 形態：只建議、不自動改（Shopify Geolocation app 的定義）。
  - **關閉後 14 天不再顯示**（Shopify 的實際預設值）。
  - 預設列出所有已發布的語言與幣別。
  - 首訪詢問 ＋ 記住偏好（Orbe 的預設形態）。
  - 爬蟲一律不顯示、不重導。
- 🔴 **EU ccTLD 情境是唯一一個 Shopify 自己承認沒有解的缺口**（官方要商家去裝第三方 app）。我方鐵律 11 的 jurisdiction pack 正好是承接它的地方 —— **在 EU pack 裡，banner 不是選配功能而是重導的替代品**。
- **要改哪些檔案**（僅列清單）：同 68 號 C-3 的清單，另加 `docs/specs/56-jurisdiction-architecture.md`（EU pack：banner 作為重導替代品的介面）。

**仍未知**：無新增（Shopify 側已完整；業界形態已取得三個獨立來源）。

---

## E-1 顯示價 ≠ 結帳價：有哪些規範存在、業界怎麼做

> 🔴🔴 **本節是法律資訊，不是法律意見。**
> 本節**只陳述「存在哪些規範、業界怎麼做」**，**不判斷我方任何設計是否合規、不判斷任何行為是否違法、不給任何應對建議的法律效力**。
> 🔴 **本節全部內容需法務覆核。** 覆核前不得被任何規格檔引用為「合規結論」。
> 基準法域＝**香港**（鐵律 11）；其他法域僅作業界對照，**不得當成香港的標準**。

**Shopify 官方文檔**：**無任何合規說明、無價格鎖定機制**（V-185 已結案）。**「跟隨 Shopify」在這一條上等於「什麼都沒決定」。**

### E-1.1 香港：本輪查到「存在」的規範（只列存在什麼）

| 規範 | 出處 | 與「顯示價 ≠ 結帳價」的關聯（只陳述文本內容） | 等級 |
|---|---|---|---|
| **《商品說明條例》（Cap. 362）** 的公平營商條文 | 香港海關「不良營商手法」專頁 | 涵蓋六類：**服務的虛假商品說明**、**誤導性遺漏（§13E）**、**具威嚇性的營業行為（§13F）**、**餌誘式廣告宣傳（§13G）**、**先誘後轉銷售手法（§13H）**、**不當地接受付款（§13I）** | `law` |
| **§13E(4)「購買邀請」的重要資料清單** | 執法指引第 **3.21** 段 | 清單中**明列「價格或價格的計算方式」**，並要求披露**額外的運費／送遞費用**，或在無法事先計算時**告知可能須支付該等費用** | `law` |
| 🔴 **執法指引第 2.20 段** | 《遵從與執法政策聲明》＋《〈商品說明條例〉公平營商條文一般指引》 | 🔴 **直接命中本題**：廣告所列的價格**應與銷售點／結帳（checkout）時的實際售價相符**；與供應直接相關的額外收費須事先清楚披露 | `law` |
| 執法指引第 **3.24** 段 | 同上 | 與供應直接相關的收費須**在購買前**清楚傳達；並以「宣傳 $1 但配菜收 $50」為例說明可能構成誤導性遺漏 | `law` |
| 執法指引第 **3.32** 段 | 同上 | **價格**與**銷售單位／數量單位**在多數情況下屬於**重要資料** | `law` |
| **指引本身的效力自述** | 執法指引前言（第 IV／V 段） | 🔴 **指引明文自述「不具法律約束力、非附屬法例」，且「不提供法律意見」**；並載明不會僅因違反指引任何部分而招致民事或刑事責任 | `law` |
| **《貨品售賣條例》（Cap. 26）** | 立法會研究簡報 ISE08/19-20 | 規定貨品須具滿意品質、適合用途、與說明或樣本相符 | `law` |
| **香港沒有的東西**（同樣重要） | 立法會研究簡報 **ISE08/19-20**（2020 年 6 月，《電子商貿消費者的保障》） | 🔴 **香港無電子商貿專法**；🔴 **無法定冷靜期**；報告指出的缺口包括：無低成本的另類糾紛解決機制、無標準化退貨安排；並引消委會調查稱網購平台退貨成功率不足五成 | `law` |
| **本輪未找到** | —— | 🔴 **香港沒有查到獨立的「價格標示／標價」專門規例**（無類似英國 Price Marking Order 的東西）。價格議題是**經由 TDO 的誤導性遺漏等條文處理**，而不是經由專門的標價法 | —— |
| **消費者委員會** | `consumer.org.hk`「不良營商手法」系列 | 本輪讀到的「第一宗罪」頁只在一般提示中把**價格**列為消費者應留意的商品說明之一，**沒有價格標示的專門指引，也沒有標價與實收不符的案例** | `law`（弱） |

⚠ **一則編號不確定**：本輪對執法指引 PDF 的兩次讀取，一次把「廣告價應與結帳實收價相符」定位在 **2.14**，一次定位在 **2.20** 並自我更正。**本檔採 2.20，但該段號需法務覆核時一併核對原文。** 段落**內容**兩次一致，不確定的只有編號。

### E-1.2 其他法域的對照（只作業界座標，不是香港標準）

| 法域 | 規範 | 內容重點 | 等級 |
|---|---|---|---|
| **英國** | **DMCC Act 2024** ＋ CMA 的《Unfair commercial practices: price transparency》（**CMA209**，2025-11-18 發布，2026-01-07 更新） | 專門處理**「drip pricing」（消費者往下走的過程中才加上去的價格）**；要求價格資訊涵蓋強制性費用、稅項與收費 | `law` |
| **美國** | **FTC《Rule on Unfair or Deceptive Fees》（16 CFR Part 464）**，**2025-05-12 生效** | 要求揭露 **Total Price**（含所有已知且可事先計算的費用，及必須一併購買的商品／服務）；🔴 **適用範圍僅限「現場活動門票」與「短期住宿」兩業**，**不涵蓋一般電商實體商品**；付款前必須以**同等或更顯著**的方式顯示最終應付金額 | `law` |
| **歐盟** | GDPR（在 C-3 的重導同意情境）；價格面另有 Price Indication Directive 體系 | 本輪未深查價格指令本身 | —— |

⇒ **業界座標**：把「消費者往下走才冒出來的價格」當成違規來管，是英美近兩年的共同方向；**但兩者管的都是「事先不揭露的費用」，本輪未查到任何法域專門處理「商家在客人購物途中改價」這個情境。** 這兩件事不同，**不得混為一談**。

### E-1.3 業界怎麼做（購物車價格變動的揭露）

| 平台 | 做法 | 等級 |
|---|---|---|
| **Etsy** | 🔴 **在購物車直接顯示警示文字 `The item price has changed.`**（買家社群多例回報）。⇒ **有平台把「加入購物車後改價」做成一個明示狀態，而不是靜默套用。** | `blog`（買家論壇） |
| **Shopify** | 無此提示。cart line 反映當前價格、cart cost 有快取延遲、結帳一律重算（68 號已證） | `press` |
| **Shopify（唯一的鎖價機制）** | **draft order / invoice** 把價格固定在建立當下（68 號已證） | `press` |

### E-1.4 建議處置（**工程面，不含任何法律判斷**）

- **技術面：不改。** server 端結帳重算與 Shopify 一致。
- 🔴 **68 號提的兩條工程護欄，本輪找到了外部參照，可以從「我方發明」降級成「有先例」**：
  1. **改價／改匯率／改市場／改 price list 前，在 admin 顯示「此變更會即時影響已在購物車中的訂單」** —— 無外部先例，維持 `ours`。
  2. **結帳頁在金額與加入購物車時不同時明示變更** —— 🔴 **Etsy 已經這樣做**（`The item price has changed.`）。這條從 `ours` 變成「業界已有實作」。
- 🔴 **jurisdiction pack 要承接的東西，本輪可以具體化了**：HK pack 至少需要一個「價格揭露」能力位，內容對應 TDO §13E(4) 清單裡與電商相關的項目（**價格或計算方式**、**額外運送費用或其可能性的告知**、**商戶身分與營業地址**、**撤銷／取消權（如有）**）。**這是把法規清單映射成能力位，不是判斷合規。**
- 🔴 **需法務覆核的具體問題（本檔不回答，只列出來給法務）**：
  1. 執法指引第 2.20 段的「結帳」是否涵蓋「線上購物車 → 結帳頁」這一段？
  2. 「商家在客人購物途中改價、結帳頁顯示新價」是否落入 §13E 誤導性遺漏，或落在 §13G／§13I？
  3. §13E(4) 的「購買邀請」定義是否涵蓋商品頁、購物車頁、還是只到某一步為止？
  4. 執法指引自述不具約束力 —— 那麼在實務上它對合規設計的分量為何？
  5. 香港是否真的沒有獨立的標價規例（本檔查不到 ≠ 不存在）？
- **要改哪些檔案**（僅列清單）：同 68 號 E-1 的清單，另加 —— `docs/specs/56-jurisdiction-architecture.md` 的 HK pack 需新增「價格揭露」能力位；並在該處**明寫「本節依據為法律資訊蒐集，未經法務覆核，不得作為合規結論引用」**。

**仍未知**：全部法律判斷（**本檔刻意不答**）。另新登記 **V-205**：香港是否存在獨立於 TDO 之外的價格標示規例（本輪未查到，但「查不到」不等於「不存在」，需法務確認）。

---

# C. 🔴 對 68 號既有結論的三條補正（不改檔，只登記）

| # | 68 號寫的 | 本檔查到的 | 影響 |
|---|---|---|---|
| **補正 1（最重）** | V-182：「研判 Shopify **原生能力薄弱或不存在**」；B-3 據此裁定把 `blank_means_unchanged` **翻面**，依據是 Matrixify | 🔴 Shopify **有完整原生翻譯 CSV**（Settings → Languages，8 欄，`Status` 三值），且其模型是**顯式的「覆寫既有翻譯」勾選框**，不是「空白＝刪除」 | 🔴 **B-3 的翻面裁定失去依據，必須重審。** 建議改成 overwrite 旗標 ＋ 空白＝不動作 |
| **補正 2** | C-3：「Shopify **自己沒有**內建 recommendation banner」 | Shopify **曾有第一方 Geolocation app**（只建議不自動、裝了就開、關掉 14 天不再顯示），**2025-03-24 移除**；官方承認 **EU ccTLD 情境沒有替代品** | 主結論（重導預設開）不變；但「Shopify 沒有 banner」要改成「**有過，收掉了，且自承 EU 情境有缺口**」，並可直接引用其預設參數 |
| **補正 3** | B-6：「〔變體加 URL〕正是 Shopify **刻意不做**的形態」 | Google 官方**要求**每個變體有可識別的獨立 URL，並定義 single-page／multi-page **兩種都合規**的形態。Shopify 的預設＝single-page（含 Google 建議的去參數 canonical），Combined Listings＝multi-page | Shopify **兩種都做了**，只是把 multi-page 鎖在 Plus。我方要廢的是「同一 product 下 variant 各掛 URL」這個**資料模型**，不是「變體可索引」這個**目標** |

---

# D. 新登記（V-200 起）

| # | 未知 | 怎麼查 | 在查明前怎麼處置 | 相關節 |
|---|---|---|---|---|
| **V-200** | Shopify 原生翻譯 CSV 中 `Translated content` **留空**時，在「勾選覆寫」與「不勾選」兩種模式下**分別**做什麼（官方 help 對此完全沉默） | dev store 實測（匯出 → 清空一列 → 兩種模式各匯入一次 → 看譯文是否消失） | 我方**不**把空白解讀成刪除；刪除必須是另一個明示動作 | V-182、B-3 |
| **V-201** | 原生翻譯 CSV 的 `Status` 欄在**匯入**時是否被讀取（還是純輸出欄）；`Market` 欄留空的語義 | 同上 | 我方 `Status` 純輸出；`Market` 留空＝套用到所有市場（保守做法：留空即拒絕匯入該列） | V-182 |
| **V-202** | UCP profile 的**最小必要欄位集**，以及版本協商**失敗時**的行為（規格 overview 只說「版本相容性與能力協商分開」，未展開失敗路徑） | `ucp.dev/2026-04-08/specification/` 逐節；Google Merchant UCP 指引其餘章節 | 維持「不實作就不輸出 `/.well-known/ucp`」 | V-186 |
| **V-203** | Combined Listings 的 **parent 商品**在 online store 上是什麼：有無可索引 URL、是否進 sitemap、canonical 指向哪裡（官方只說 parent 不可購買、無庫存、無銷售數據） | 已啟用 native combined listings 的 Plus 店實測 | 我方若做等價物：parent **不進 sitemap**、若有 URL 則 self-canonical | V-187、B-6 |
| **V-204** | Stripe 現行是否仍支援 KWD／BHD／JOD 作 presentment currency，以及其「three-decimal currencies」章節是否已被移除（現行 `docs.stripe.com/currencies` 的幣別清單為**動態渲染**，本輪抓不到；`Special cases` 表只剩 ISK／HUF／TWD／UGX） | 直接讀 Stripe 幣別清單（需能執行 JS 的抓取），或 Stripe API 實測 | 不影響我方：PSP pack 未宣告 ⇒ reject（鐵律 3 不放鬆） | V-188 |
| **V-205** | 香港是否存在**獨立於 TDO 之外**的價格標示／標價規例（本輪未查到；「查不到」≠「不存在」） | 🔴 **需法務**。本檔不再自行查 | 不作任何合規假設；jurisdiction pack 的 HK 價格揭露能力位標為「待法務」 | E-1 |

---

# E. 🔴 本輪查過、但沒有結果的來源清單（讓下一個人不用重查）

> 這一節的價值等同於有結果的那些。**下列每一條都已排除，不要再花時間。**

**V-180／V-181（handle 的實作與規則）**
- `Shopify/liquid` gem `lib/liquid/standardfilters.rb` —— 🔴 **確認 `handleize`／`handle` 不在其中**（已列出全部 60 個 filter）。**Shopify 的 handleize 不開源，此路永久不通。**
- `Shopify/theme-liquid-docs` 的 `data/filters.json` —— 抓到的內容裡沒有 handleize 條目（檔案疑似被截斷或路徑已變，但**即使找到也只會是文檔不是實作**）。
- GitHub code search —— 容器內**無 `gh` CLI**，`curl` 到 `raw.githubusercontent.com` 以外的主機被 proxy 以 403 CONNECT 擋下；code search API 需認證。**要做這件事必須換環境。**
- `rubygems.org` —— `gem install activesupport` 被 proxy 403 擋下 ⇒ **本輪無法實跑 Rails `parameterize` 驗證**，只能引 Rails 官方 API 文檔。
- 網路上的 handleize 移植（`gist.github.com/tyteen4a03`、`gist.github.com/wrglbr`、`gist.github.com/pablogiralt`、`gist.github.com/smoopins` 的 PHP 版、`codepen.io/luc_tran_solislab`、`doomcommerce.github.io/Shopify/Handleization-Helper`）—— 🔴 **全部是社群逆向重寫，彼此不一致，無一標明來源或測試方法。一律不採信，不要再逐個比對。**
- **全形字元（`Ａ`／`１`／`　`）在 slug 產生器裡的處置** —— 🔴 **查遍 Shopify、WordPress、Rails、Magento、Django 的文檔與原始碼引述，零結果。這是一個業界普遍沒寫過的題目。**

**V-183**
- `shopify.dev/docs/api/usage/limits` —— 只有 API 速率限制，**沒有欄位長度**。
- GraphQL Admin API 的 `handle` 欄位 —— 型別是 `String`，**schema 不帶長度約束**。

**V-184**
- community 201996（`API Error 'Handle has already been taken'`）—— **舊版 URL 已 404**，只能從搜尋結果標題確認該錯誤字串存在。
- community 251412／2229673 —— **無 staff 回覆**，且原 po 的觀測自相矛盾（見 V-184 正文）。

**V-187**
- `shopify.dev/docs/apps/build/product-merchandising/combined-listings` 與 `…/build-for-combined-listings` —— 🔴 **兩頁都對 URL／canonical／SEO 完全沉默**（68 號只讀了 help，本輪把 dev docs 也讀完了，結論一致）。
- `craftshift.com` 與 `rubikify.com` —— 🔴 **同一作者、同一 app 廠商、無測試數據。算 1 個來源，不是 2 個。**
- 直接抓真實店鋪的 canonical —— 🔴 **本輪環境做不到**：容器出站被 proxy 以 403 CONNECT 擋下（`allbirds.com`、`kith.com`、`thesill.com`、`bombas.com`、`deathwishcoffee.com` 皆被擋）。68 號能做到是因為它在別的環境跑。**下一輪要做實測必須先確認出站權限。**

**V-188**
- `docs.stripe.com/currencies`（含 `.md` 版本）—— 抓到的內容裡**幣別清單為動態渲染，抓不到**；且**現行文檔已無「three-decimal currencies」章節**（歷史版本可能有，本輪未查歷史版本）。
- Airwallex 的 per-currency 小數位表 —— **未找到**；其 data types 只說「以 ISO 4217 定義的主單位表達」。

**B-5**
- `docs.bigcommerce.com` 的 catalog overview —— 🔴 **沒有明文寫 SKU 必須唯一**（只寫 variant 必須有 SKU）。BigCommerce 的唯一性只能從 support 討論串的錯誤字串反推。
- `developer.bigcommerce.com/docs/rest-catalog/product-variants` —— **302 轉址到 `docs.bigcommerce.com`**，內容同樣未述唯一性。
- `support.bigcommerce.com` 的討論串 —— **內容需登入或由 JS 載入**，抓到的只有導覽骨架。
- Salesforce B2C Commerce 的 SKU 唯一性 —— **未取得明文**。

**B-6**
- `sfcclearning.com` 的 Create Canonical URL Tags —— **抓到的頁面只有導覽骨架，無實質內容**。

**C-3**
- 無死路。三個來源（Shopify help／changelog、Google Search Central、Orbe help center）都直接給出答案。

**E-1**
- `elegislation.gov.hk` —— 🔴 **`robots.txt` 禁止抓取**，無法直接讀條文原文。本檔的條文內容**全部來自海關／通訊局的執法指引與立法會研究簡報的轉述**，**不是條文原文** ⇒ 法務覆核時必須回到 eLegislation 核對。
- `consumer.org.hk` —— 讀到的「不良營商手法」頁**沒有價格標示的專門指引**。消委會的其他出版品（如價格調查報告）本輪未查。
- 香港是否有獨立的價格標示規例 —— **查不到**（見 V-205）。

---

# F. 出處清單（查證日 2026-08-12，依 §0.1 分級）

**`src`（官方原始碼／官方文檔對原始碼的逐行引述）**
`raw.githubusercontent.com/Shopify/liquid/main/lib/liquid/standardfilters.rb`（確認無 handleize；列出 60 個 filter）｜`raw.githubusercontent.com/woocommerce/woocommerce/trunk/plugins/woocommerce/includes/wc-product-functions.php`（`wc_product_has_unique_sku` ＋ `wc_product_pre_has_unique_sku`／`wc_product_has_unique_sku` 兩個 filter）｜`developer.wordpress.org/reference/functions/wp_unique_post_slug/`（`$suffix = 2`，即 `-2` 起算；`_truncate_post_slug($slug, 200 - …)`）｜`developer.wordpress.org/reference/functions/sanitize_title/` ＋ `…/sanitize_title_with_dashes/`（`remove_accents()` 前置；`utf8_uri_encode($title, 200)` 保留非 ASCII 為 percent-encoded octet；保護既有 `%XX`）｜`api.rubyonrails.org/classes/ActiveSupport/Inflector.html`（`transliterate` 以 `?` 取代無近似字的非 ASCII ⇒ `parameterize` 對純 CJK 回空）

**`law`（法例原文／主管機關指引／立法機關研究）**
`customs.gov.hk/en/service-enforcement-information/consumer-protection/trade-desc/unfair/index.html`（TDO 六類不良營商手法）｜`customs.gov.hk/hcms/filemanager/common/pdf/pdf_forms/Enforcement_Guidelines2_en.pdf` ＋ 中文版 `coms-auth.hk/filemanager/tc/content_800/Enforcement_Guidelines_tc.pdf`（**§2.20 廣告價應與結帳實收價相符**；§3.21 §13E(4) 重要資料清單；§3.24；§3.32；前言 IV／V 自述不具約束力、不提供法律意見；2013 年 7 月，公平營商條文 2013-07-19 生效）｜`legco.gov.hk/research-publications/chinese/essentials-1920ise08-e-consumer-protection.htm`（**ISE08/19-20**，2020-06；香港無電子商貿專法、無法定冷靜期、保障缺口）｜`consumer.org.hk/unfair_trade_practices/p190`（**查過，無價格專門內容**）｜`gov.uk/government/publications/price-transparency-cma209`（**CMA209**，2025-11-18 發布、2026-01-07 更新；drip pricing）｜`ftc.gov/business-guidance/resources/rule-unfair-or-deceptive-fees-frequently-asked-questions`（**16 CFR Part 464**，2025-05-12 生效；**僅現場活動門票與短期住宿**）

**`std`（標準／協定／搜尋引擎官方規範）**
`ucp.dev/2026-04-08/specification/overview/`（UCP 規格 2026-04-08；`/.well-known/ucp` 為 discovery 入口；Checkout／Cart／Catalog／Order／Identity Linking／Payment Handlers；反向網域能力識別字；Trust Triangle）｜`developers.google.com/merchant/ucp/guides/ucp-profile`（profile 路徑 `/.well-known/ucp`，**必須公開可讀、不得要求驗證**；含 JWK 簽章金鑰；由 business 自行發布）｜`developers.google.com/search/docs/specialty/ecommerce/designing-a-url-structure-for-ecommerce-sites`（**建議每個變體有可識別的獨立 URL**；query param 型變體的 canonical **去參數**；反對 fragment；`?key=value`）｜`developers.google.com/search/docs/appearance/structured-data/product-variants`（`ProductGroup`／`hasVariant`／`variesBy`／`productGroupID`；single-page 需單一 canonical、multi-page 不適用；`offers.url`；**不表偏好**）｜`developers.google.com/search/docs/specialty/international/managing-multi-regional-sites`（**避免自動語言重導**；建議用連結；**Google 爬取多來自美國且不刻意變換位置**；用 hreflang／alternate／顯式連結）

**`alt`（競品／PSP／ERP 官方文檔）**
`docs.adyen.com/development-resources/currency-codes`（KWD／BHD／JOD／OMR／TND **exponent 3**；🔴 **CLP／CVE／IDR／ISK 以 Adyen 表為準、與 ISO 4217 不同**）｜`docs.stripe.com/currencies`（整數 minor units；`Special cases` 表 ISK／HUF／TWD／UGX 與 ISO 不同；HUF／TWD payout **須整除 100**）｜`docs.datatrans.ch/docs/currency-codes`（整數 minor units；三位小數幣別 ×1000；自稱遵循 ISO 4217）｜`airwallex.com/docs/api/data_types`（🔴 **十進位主單位**，`9.99`；非 minor units）｜`docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_164033747444.html`（**SKU 須跨 item type 唯一**；重複 ⇒ 訂單同步失敗；改名而非停用／刪除）｜`docs.bigcommerce.com/developer/docs/admin/catalog-and-inventory/products-overview`（**未明文 SKU 唯一**）｜`support.bigcommerce.com/.../api-product-update-error-the-product-sku-is-a-duplicate`（錯誤字串 `The product SKU is a duplicate`；**內容需登入**）｜`github.com/magento/magento2` issue #11266／#7298（`URL key for specified store already exists.`）｜`developer.salesforce.com/docs/commerce/b2c-commerce/references/b2c-script-api/dw.catalog.Product.html`（**未取得唯一性明文**）

**`vendor`（廠商技術文章／app help center）**
`store.crowdin.com/shopify-translate-adapt`（Shopify 翻譯 CSV 的 8 欄與逐列對位回匯）｜`help.orbe.app/before-starting/how-it-works`（預設 Welcome Popup、排除爬蟲、GDPR 同意）｜`docs.xotiny.com/xo-tunnel/shopify-limits/`（handle 255；tag 255；metafield namespace 255／key 64；SEO title 70／description 320；alt 255）｜`matrixify.app/documentation/shopify-limits/`（handle 255；68 號已引）｜`matrixify.app/documentation/translations/`（空白＝刪除；68 號已引）

**`staff`（論壇官方 staff 回覆）**
`community.shopify.com/t/how-to-export-translate-adapt-translations-to-csv/209362/11`（`richbrown_staff`，2023-12-25：CSV 功能在 **Settings → Languages**，不在 Translate & Adapt；須先加至少一種語言）

**`blog`（一般部落格／內容行銷；🔴 不得當事實）**
`craftshift.com/how-to-set-different-urls-per-variant-shopify/`（Umid，2026-05-10）＋ `rubikify.com/shopify-combined-listings-and-seo-...`（umid，2026-02-25／2026-08-04 更新）—— 🔴 **同一作者、同一 app 廠商，算 1 個來源**；稱 child self-canonical，**無測試數據**｜`community.etsy.com/.../The-item-price-has-changed`（買家論壇；Etsy 購物車顯示 `The item price has changed.`）

**`help`／`dev`（Shopify 官方；本檔僅用於補正 68 號）**
`help.shopify.com/en/manual/international/localization-and-translation`（🔴 **原生翻譯 CSV 匯出／匯入**：8 欄、`Status` 三值、**覆寫既有翻譯勾選框**、匯出以 email 寄出）｜`help.shopify.com/en/manual/markets/international-domains/directing-customers/geolocation`（Geolocation app **只建議不自動**；裝了就開；**關掉 14 天不再顯示**；2025-02-01 停止安裝、2025-03-24 關閉）｜`changelog.shopify.com/posts/geolocation-app-removal`（2024-02-12；移除理由；**EU ccTLD 例外要用第三方 app**）｜`changelog.shopify.com/posts/accurately-track-your-inventory-with-unique-skus`（**2021-11-10**；只加警告不阻擋）｜`shopify.dev/docs/apps/build/product-merchandising/combined-listings` ＋ `…/build-for-combined-listings`（parent／child 模型；`combinedListingRole`／`combinedListing`／`parentProduct`／`combinedListingChildren`；`productSet`／`combinedListingUpdate`；child ≤60／options ≤3／變體 ≤2000；**對 canonical 沉默**）

---

## G. 本檔的可重跑驗證

```
1. Shopify handleize 不開源：
   GET https://raw.githubusercontent.com/Shopify/liquid/main/lib/liquid/standardfilters.rb
   在檔內搜 "handleize" 與 "def handle" ⇒ 應為 0 命中。

2. WooCommerce 硬唯一：
   GET https://raw.githubusercontent.com/woocommerce/woocommerce/trunk/plugins/woocommerce/includes/wc-product-functions.php
   搜 "wc_product_has_unique_sku" ⇒ 函式本體 ＋ 兩個 apply_filters。

3. UCP discovery 路徑：
   讀 https://ucp.dev/2026-04-08/specification/overview/ 與
      https://developers.google.com/merchant/ucp/guides/ucp-profile
   兩處都應出現 /.well-known/ucp，且 Google 那頁應寫「不得要求驗證」。

4. HK 執法指引 §2.20：
   讀 https://www.customs.gov.hk/hcms/filemanager/common/pdf/pdf_forms/Enforcement_Guidelines2_en.pdf
   （中文版 https://www.coms-auth.hk/filemanager/tc/content_800/Enforcement_Guidelines_tc.pdf）
   找「廣告價格與銷售點／結帳實際售價相符」那一段，核對段號是 2.20 還是 2.14。

5. PSP 小數位不一致：
   並排讀 Adyen currency-codes、Datatrans currency-codes、Airwallex data_types。
   Adyen 應明文說 CLP/CVE/IDR/ISK 以自家表為準；Airwallex 應是十進位主單位。
```

> ⚠ **環境限制（下一個人必讀）**：本輪容器的出站被 agent proxy 以 **403 CONNECT** 擋下絕大多數主機（`curl` 僅 `raw.githubusercontent.com` 等少數可通），`gem install` 與 `gh` CLI 皆不可用。**所有「抓真實店鋪」與「實跑程式碼」的驗證本輪都做不了。** 68 號能做一手實測是因為它在別的環境跑 —— 要重現 68 號的 `test` 級證據，**先確認出站權限，再排工。**
