# 67 — 多語言架構規格（內容 i18n・handle 政策・後台與前台在地化）

> **緣由**：使用者 2026-08-12 裁定逐字：
>
> 「**url hand 使用英文標題，禁止使用中文**。例如 `https://chill.deals › products › kerastase-specifique-stimuliste-nutri-energising-daily-anti-hairloss-spray-125ml-4-2oz`
> 所以你要做**多語言**。商品所有數據，前台，後台，都要做多語言。先開始時**繁體中文、簡體中文、英文**。之後我可以自行添加任何語言。」
>
> **本檔回答一個問題**：一份商品資料在 N 種語言下**如何存、如何編輯、如何渲染、如何被索引**。它是**架構規格**，不是翻譯字串表——本檔不含任何一條實際譯文。
>
> **本檔與既有規格的分工（不重寫別人已經定案的東西）**：
> - `62-seo-geo.md` §I hreflang 矩陣、§J 網域策略、§K 地區重導、§B canonical——**已定案，本檔接上不另立**。本檔只補「語言維度怎麼餵進 §I.1 的 `hreflang_set()`」（§F.1），**不重寫那個演算法**。
> - `62 §F.3` 的 handle 規則被本裁定**推翻**（原「保留 CJK」⇒ 現「一律 ASCII」），已於本輪改寫並結案 **V-119**；改動清單見 §M。
> - `29-markets-i18n.md` §2 翻譯層（可翻譯資源 30 型、`translations` 表 ＋ digest、Translate & Adapt 形態、locale 前綴路由）是**既有底座**，本檔補它沒有的五件事：來源語言的可變更性、fallback 鏈的明確定義、過期偵測的分級、翻譯進度的物化、以及 handle 從可翻譯清單中**移除**。
> - `63-product-data-flow.md` §D 快取階梯與 `cache_stamp`——**多語言讓快取鍵再乘一個維度**，本檔 §G 給對策，並沿用 63 §D.3 的 `touched_sources` 自檢機制（把它從「表」擴充到「維度」）。
> - `56-jurisdiction-architecture.md` 的可插拔哲學——**語言 pack 與 jurisdiction pack 正交，不得混成一個**（§A.3）。
> - `66-theme-editor-and-storefront-product.md` §A.9 的 Ella `locales/` 三個坑（JSONC、前台/編輯器兩套、語言清單不對稱）是主題端 i18n 的實證基準（§F.3）。
>
> **金額鐵律（鐵律 3／10 ＋ 2026-08-12 裁定二）**：**語言 ≠ 幣別。** 英文版的香港商店仍顯示 `HK$1,480.00`。金額字串的每一個部分由 **market locale** 決定，**不隨內容語言變**；日期與非金額數字**跟著內容語言**。分界表在 §H.2，那是本檔最容易做錯的一節。
>
> **法域鐵律（鐵律 11）**：本檔**不得**出現寫死的語言清單、國別分支。首發三語是**種子資料**不是列舉——裁定明文「之後我可以自行添加任何語言」，所以語言集必須是**資料**（§A.2）。
>
> **權威順序**（沿用 52／54／55／56／57／58／62／63）：官方開發文檔 ＞ 官方商家文檔 ＞ 實測 ＞ 我方既有規格。**我方與官方衝突時一律改我方**；但**使用者裁定高於一切**——本檔 §D 就是一條裁定推翻既有規格的實例。
>
> **盤點與查證日**：2026-08-12。**待查證編號自 V-160 起**（倉庫現有最大 V-146，留 13 號緩衝避免與其他 agent 撞號）。
>
> **本輪未做網路查證**：本檔對 Shopify／Google／MySQL 行為的每一條陳述，要嘛引用倉庫內既有已查證文件（帶原檔的查證日與出處等級），要嘛標 `未查證` 並登記 V 編號。**沒有第三種。**

---

## 0. 決議、原則與出處等級

### 0.1 裁定拆成可驗收的五條

| # | 裁定要點 | 本檔怎麼回應 | 驗收在哪 |
|---|---|---|---|
| a | 「url hand 使用英文標題，**禁止使用中文**」 | §D.1 從使用者的範例逆推完整 slug 規則（已用該範例做可重跑驗證，逐字元相同） | §K HDL-1～HDL-9 |
| b | 「所以你要做多語言」（商品所有數據） | §B 可翻譯欄位總表（逐資源、三分類）＋ §C 資料模型 | §K I18N-1～I18N-12 |
| c | 「**前台**……都要做多語言」 | §F URL 結構／偵測切換／Liquid 三層字串／結帳與通知的語言快照 | §K SF-1～SF-8 |
| d | 「**後台**……都要做多語言」 | §E 兩層語言（介面／內容）＋進度可視化＋批次機翻＋第三套匯入匯出 | §K AD-1～AD-9 |
| e | 「先開始時繁中、簡中、英文。**之後我可以自行添加任何語言**」 | §A.2 語言集是資料；§C.1 語言註冊表；新增語言**不需要改程式碼、不需要 migration** | §K I18N-1／I18N-2 |

### 0.2 八條設計原則

1. **語言與市場是兩個維度，永遠不綁死。** 同一語言可跨市場（`en` 在 HK 與 SG）、同一市場可多語言（HK 市場同時有 `zh-Hant` 與 `en`）。62 §I 的 hreflang 矩陣**正是建立在這個分離上**——把它們綁成一個「locale=語言+國家」的單一欄位，矩陣就退化成對角線，多國市場的語言碼粒度規則（62 §I.2）也無從表達。
2. **缺翻譯必須有明確且可預測的行為，不得靜默空白。** fallback 鏈是**規格**不是實作細節（§C.4）。承 56 §A.3 的「禁止第四種：靜默略過」——語言層的等價形態是「`translations[locale]` 是 nil 就印空字串」，它會編譯通過、測試通過、上線後在某個語言版本留下一整頁空白。
3. **URL 是永久身分，生成它的函式必須是確定性的。** 同輸入同輸出、不依賴外部服務、不依賴當日模型版本。這一條直接淘汰「機器翻譯產生 handle」（§D.2）。
4. **翻譯不碰金額，也不碰識別碼。** 金額走 65 號的型別邊界；SKU／條碼／GID／tag／`Default Title` 是**契約字串**不是文案（§B.3）。翻譯這些欄位不是「多語言做得深」，是資料毀損。
5. **兩層語言必須是兩個切換器。** 商家看到的按鈕文字（介面語言）與商家正在編輯哪個語言版本的商品（內容語言）是**兩件事**。合成一個下拉是常見設計錯誤，後果見 §E.1。
6. **語言 pack ⟂ jurisdiction pack。** 語言 pack 只管「文字怎麼呈現」；幣別、稅、地址格式、法律文本一律是 market／jurisdiction 的事（§A.3）。混成一個，第一個症狀就是「英文版的香港店顯示 US$」。
7. **快取維度要降維，不是硬吞。** 多語言把每一頁乘上 N。對策不是「多買記憶體」，是**只有真的讀了翻譯欄位的片段才進 locale 維度**，且判定必須 **fail-closed**（§G.2）。
8. **誠實記錄取捨。** 多語言與快取命中率、繁簡自動轉換與品質、機翻與 SEO 都有真實衝突，本檔**不寫「兩邊都好」**（§G.4、§E.5）。

### 0.3 出處等級（沿用 62 §0.3 的擴充集）

`dev`（shopify.dev）＞ `help`（help.shopify.com）＞ `live`（實測）＞ `ours`（本專案決策）；SEO 面另有 `google`／`openai`／`ucp`／`press`（62 §0.3）；主題面 `fixture`（`test/fixtures/themes/ella-7.2.0` 靜態掃描，66 §0.3）。**本檔新增一級**：

| 等級 | 意義 | 可否據以寫死實作 |
|---|---|---|
| `ruling` | **使用者裁定**（本檔即 2026-08-12 多語言裁定的落地） | ✅ 可，且**優先於 `dev`**——裁定是產品決策，不是對 Shopify 的復刻 |

### 0.4 本檔推翻／偏離的既有結論（5 條，逐條可追溯）

| # | 既有寫法 | 本輪處置 | 誰改 |
|---|---|---|---|
| 🔴 **0** | **本檔自己的 §E.6 空白語義**（`i18n.import.blank_means_unchanged`） | **2026-08-12 同日反轉兩次**：原 `true`（我方原設計）→ 68 §B-3 依 **Matrixify（第三方，`press`）** 改 `false`（空白＝刪除）→ 🔴 **69 §V-182 查到本尊原生語義（Settings → Languages，`help`）後改回 `true`**，並改成 **overwrite 旗標 ＋ 空白＝不動作**。<br>**教訓（寫在最前面，因為它適用於全檔）**：`press` 級來源足以「登記為未知」，**不足以翻面一條已生效的資料安全預設**。沿革全文見 §E.6 檔頭註釋、§M-9 | ✅ **本輪已改** |
| 1 | **62 §F.3**「handle 保留 CJK、URL 走 percent-encoding」（登記為 V-119） | **裁定推翻**：一律 ASCII。§F.3 已改寫並留追溯註釋。<br>🔴 **2026-08-12 二次修正（68 §B-1）**：V-119 的結案敘述原寫成「對齊問題消失」，實際是**本尊保留 CJK、裁定覆蓋 Shopify** ⇒ 已改寫為**明知偏離登記**（62 §F.3-1） | ✅ **本輪已改** |
| 2 | **13 §F2-1**「中文標題不轉拼音，demo 選 unicode handle（`/products/棉質短T` 可用）」 | 同上被推翻。本檔**不改 13 號**（另有 agent 在改 13/63/65），登記於 §M-1 | 13 §F2 |
| 3 | **29 §2.1** 把 `PRODUCT/COLLECTION/ARTICLE.handle` 列入可翻譯資源型別 | **我方刻意偏離**：handle **不可翻譯**，語言維度由 URL 前綴承載（§D.3）。登記於 §M-2 | 29 §2.1 |
| 4 | **63 §D.3** 頁級 fragment key **無條件**含 `locale` | 改為**依實際依賴降維**（§G.2），並沿用 63 §D.3 既有的 `touched_sources` 自檢把降維做成可執行斷言。登記於 §M-4 | 63 §D.3 |

---

## A. 語言與地區的關係

### A.1 三個正交維度，不得壓成一個

```
語言（locale）      = 文字怎麼寫             zh-Hant / zh-Hans / en / ja …
市場（market）      = 賣給誰、用什麼條件賣    HK / TW / SG / EU 多國市場 …（29 §1.1，由 conditions 命中）
法域（jurisdiction）= 受誰的法律管            hk / tw / my …（56 §A.0，由訂單成立時快照）
```

| 事實 | 對映 | 反例（做錯會怎樣） |
|---|---|---|
| 同一語言跨多個市場 | `en` 同時是 HK 市場與 SG 市場的可用語言 | 若把語言掛死在市場上，`en` 要存兩份翻譯 ⇒ 商家改一處另一處不變 |
| 同一市場多個語言 | HK 市場同時啟用 `zh-Hant`（預設）與 `en` | 若一市場一語言，62 §I.2 的「多國市場 ⇒ 語言碼」規則無從表達 |
| 語言 ≠ 幣別 | `en` ＋ HK 市場 ⇒ 顯示 `HK$1,480.00` | 綁死 ⇒ 英文版顯示 `US$`（鐵律 10 ＋ 裁定二的直接違反，§H.1） |
| 語言 ≠ 法域 | `zh-Hant` ＋ HK 市場 ⇒ 走 `jurisdiction/hk`（無銷售稅、無政府發票，56 §B.1） | 綁死 ⇒ 繁中買家被套上 TW pack 的統一發票流程 |
| 市場的語言集合是**累加繼承**的 | 子市場的可用語言 ＝ 自身 ∪ 沿 lineage 上溯（29 §1.5，`market.inheritance_additive` 含 `web_presences`） | 用 `m.web_presences` 而非 `resolved_web_presences(m)` ⇒ hreflang 漏語言 ⇒ 雙向性破裂（62 §I.3(a) 已警告） |

**資料上的體現**：語言掛在 `shop_locales`（全店），市場的可用語言掛在 `market_web_presence_locales`（29 §1.4 已有），**兩張表是「全集」與「子集」的關係，不是兩份清單**。新增語言只動前者；把語言開給某市場才動後者。

### A.2 語言集合是**資料**，不是列舉（裁定明文的直接落地）

裁定第三句是「之後我可以自行添加任何語言」。這一句在架構上的意思是：

```
🔴 新增一個語言必須是「後台一次操作」，不得需要：改程式碼 / 改 enum / 跑 migration / 重新部署。
```

因此：

- 語言在資料庫（§C.1 的 `platform_locales` ＋ `shop_locales`），不在 Ruby enum、不在 TypeScript union type、不在 `limits.yml` 的清單裡。
- `limits.yml` 只放**約束**（標籤格式、數量上限、禁用碼），**不放語言清單**。`i18n.launch_locales` 是**種子資料的指標**，不是值域（§J 註解已寫死這一點）。
- 前後端任何 `switch (locale)`／`if locale == 'zh-Hant'` 都是 bug。語言相依的行為一律查 `platform_locales` 的欄位（書寫方向、複數規則、日期格式 ID、排序 collation）。
- **驗收方式**：`I18N-2` —— 用一個測試新增 `ja` 並跑完整前台渲染，過程中不得有任何原始碼變更。

### A.3 語言 pack 與 jurisdiction pack 正交（承 56 號哲學，**不得混成一個**）

| | 語言 pack（`locale/<tag>`） | jurisdiction pack（`jurisdiction/<code>`，56 §A） |
|---|---|---|
| 管什麼 | 文字怎麼呈現 | 法律要求怎麼滿足 |
| 內容 | UI 字串、複數規則、書寫方向、日期／非金額數字格式、排序 collation、字型堆疊 | 稅務憑證能力、儲值監管、取貨網路、隱私法、稅號格式、**幣別格式** |
| 誰選中它 | 買家／員工選的語言 | 買家所在市場推導的法域（56 §A.0） |
| 換掉它會變什麼 | 文字 | 流程與憑證 |
| 🔴 **絕不含** | 幣別符號／小數位／千分位、稅率、地址格式、法律文本 | UI 按鈕文案 |

**為什麼一定要正交**（兩個具體事故形態）：

1. **合成的第一個症狀**：`en` pack 裡放了 `currency: USD` ⇒ 英文版的香港店顯示 `US$1,480`。這**同時**違反鐵律 10（符號由市場 locale 決定）與裁定二，而且在 HKD 商店的測試裡不會被發現——只有商家切到英文才出現。
2. **反向合成**：`jurisdiction/hk` pack 裡放了「繁體中文的退貨政策文本」⇒ 香港店的英文版顯示中文政策。法域決定「要不要有退貨政策」與「政策的法定最低內容」；**政策的語言版本是翻譯資源**（29 §2.1 `SHOP_POLICY`，本檔 §B.2）。

**接縫定義（唯一許可的耦合點）**：`RequestContext{market, locale, currency, jurisdiction}` 是**一個**結構（63 §D.1 已有前三者），四個欄位**各自獨立解析**，任何一個都不從另一個推導。唯一的例外是 fallback：市場未指定語言時取市場的 `defaultLocale`（29 §1.2），那是**取預設值**，不是推導。

### A.4 首發三語與 `zh-Hant` / `zh-Hans` 的硬規則

| 標籤 | 這是什麼 | 硬規則 |
|---|---|---|
| `zh-Hant` | 繁體中文（**字體**，ISO 15924 `Hant`） | 🔴 **不得**寫成 `zh-TW`（那是地區碼不是字體）。承 62 §I.4 已定案 |
| `zh-Hans` | 簡體中文（ISO 15924 `Hans`） | 🔴 **不得**寫成 `zh-CN` |
| `en` | 英文（無地區） | 需要地區時是 `en-HK`／`en-SG`，由 market 推導（62 §I.2），不預先建立 |
| `zh` | — | 🔴 **禁止使用裸 `zh`**（`i18n.forbidden_locale_tags`）：它在字體上是歧義的，任何以 `zh` 為 fallback 目標的鏈都會把繁體使用者送到簡體內容或反之 |

🔴 **`zh-Hant` 與 `zh-Hans` 之間永不互為 fallback**（`i18n.never_fallback_pairs`）。理由與 62 §I.4「`zh-Hant-HK` 不得借 `zh-TW`」是同一條，但更嚴重：地區借用只是用詞略有差異，**字體借用是整頁文字都不對**。缺 `zh-Hans` 翻譯時的正確行為是回落到**來源語言**（§C.4），不是回落到 `zh-Hant`。

**但繁簡轉換要做成工具**（§E.5(c)）：它是一個**商家主動觸發、產生真實譯文列、可覆核**的批次動作，**不是渲染期 fallback**。兩者的差別是：前者的結果進資料庫、可編輯、可稽核；後者是每次渲染都偷偷換一次字，商家永遠看不到、也改不掉。

---

## B. 可翻譯欄位總表

### B.1 三分類原則

| 類別 | 定義 | 缺翻譯時的行為 | 存哪 |
|---|---|---|---|
| **必翻**（`required`） | 缺了頁面就不成立（標題、按鈕、政策標題） | **回落來源語言原文**並在後台標「未翻譯」。🔴 顯示原文優於顯示空白 | `translations` |
| **可選**（`optional`） | 缺了頁面仍完整（SEO 描述、圖片 alt、副標） | **整個欄位不輸出**（不是輸出空字串）。承 62 §E.1「空描述不編造」 | `translations` |
| **不可翻**（`never`） | 翻了會壞（識別碼、契約字串、金額、集合運算的鍵） | 永遠取原值，**不進 `translations` 表** | 本表 |

🔴 **第四種行為（靜默輸出空字串／輸出 key 名／輸出 `nil`）一律禁止**（原則 2）。Liquid `t` filter 未命中的定義行為見 §F.3。

### B.2 逐資源清單

> 基準是 29 §2.1 的 30 個 `TranslatableResourceType`（`dev`，查證日 2026-08-11）。**本表只做三件事**：分類、標出我方偏離、補 29 §2.1 沒有的欄位級語義。

**商品線**

| 資源 | 欄位 | 類別 | 註 |
|---|---|---|---|
| `PRODUCT` | `title` | 必翻 | 上限沿用 `product.title_max_chars`（§J 的 `per_field_limits_follow_source_field`） |
| | `body_html` | 必翻 | 富文本；digest 前先做穩定序列化（§C.5） |
| | **`handle`** | **🔴 不可翻** | **本檔刻意偏離 29 §2.1**（§D.3）。語言維度由 URL 前綴承載 |
| | `product_type`（自由文字） | 可選 | 分類法（taxonomy）的**類別標籤**不在此——那是平台資料，由平台的分類法 pack 提供各語言標籤，商家不編輯 |
| | `meta_title` / `meta_description` | 可選 | 62 §E.1 的 fallback 鏈**在本檔的鏈之後**執行（先解語言，再解樣板） |
| `PRODUCT_OPTION` | `name` | 必翻 | 🔴 **變體身分不得依賴譯文**（§B.3-4） |
| `PRODUCT_OPTION_VALUE` | `name` | 必翻 | 同上；🔴 `Default Title` 例外，見 §B.3-3 |
| `MEDIA_IMAGE` | `alt` | 可選 | 62 §F.1 的 `alt_source` 稽核欄同樣適用於**譯文**（機翻 alt 要標） |
| `SELLING_PLAN` / `SELLING_PLAN_GROUP` | name／描述 | 必翻 | |
| `METAFIELD` | `value` | **視型別**（§B.4） | 🔴 money／number／date／reference 型別**不可翻** |
| `METAOBJECT` | 依 type 定義的欄位 | 視型別 | 同上規則逐欄套用 |

**內容線**

| 資源 | 欄位 | 類別 | 註 |
|---|---|---|---|
| `COLLECTION` | `title` / `body_html` | 必翻 | |
| | **`handle`** | **不可翻** | 同 PRODUCT |
| | `meta_title` / `meta_description` | 可選 | |
| `COLLECTION_IMAGE` / `ARTICLE_IMAGE` | `alt` | 可選 | |
| `PAGE` / `ARTICLE` / `BLOG` | `title` / `body_html` / `summary_html` / `meta_*` | 必翻（本文）／可選（meta） | `handle` 不可翻 |
| `MENU` / `LINK` | `title` | 必翻 | 🔴 連結的 **`url`** 不可翻——URL 前綴由路由層加（§F.4），在翻譯層改 URL 會產生跨語言死鏈 |
| `FILTER` | `label` | 必翻 | 篩選的**值**（來自 tag／metafield）不在此；tag 不可翻（§B.3-2） |
| `SHOP` | `meta_title` / `meta_description` | 可選 | |
| `SHOP_POLICY` | `body` | **必翻** | 🔴 代理端點吃它（62 §H.4 `policy_refs`）；缺該語言政策 ⇒ 回落來源語言**並在頁面標示語言**，不得空白 |

**商務與通知線**

| 資源 | 欄位 | 類別 | 註 |
|---|---|---|---|
| `EMAIL_TEMPLATE` | `title` / `body_html` | 必翻 | 語言解析走**顧客語言快照**（§F.5），不是商家語言 |
| `PACKING_SLIP_TEMPLATE` | 內容 | 必翻 | |
| `PAYMENT_GATEWAY` | `name` / `message` / `instructions` | 必翻 | 🔴 **金額佔位符不可翻**：範本內的 `{{ amount }}` 之類 token 是契約，翻譯器要能鎖定（§C.5 的 token 保護） |
| `DELIVERY_METHOD_DEFINITION` | `name` / `description` | 必翻 | 費率**金額**不可翻（鐵律 3） |
| 結帳文案（平台 UI ＋ 商家覆寫兩層） | 見 §F.5 | 必翻 | 平台層字串屬**平台 i18n bundle**，不進租戶 `translations`（§E.1） |

**主題線**（29 §2.1 的七個 `THEME_*` 動態鍵型別）

| 資源 | 欄位 | 類別 | 註 |
|---|---|---|---|
| `THEME_LOCALE_CONTENT` | 主題 `locales/*.json` 的每一個 leaf key | 必翻 | 這是**商家覆寫主題字串**的層，是 §F.3 三層中的第三層 |
| `THEME_JSON_TEMPLATE` / `THEME_SECTION_GROUP` / `THEME_SETTINGS_DATA_SECTIONS` | setting 值中的文字型欄位 | 必翻 | 🔴 只有 `text`／`textarea`／`richtext`／`inline_richtext`／`html` 型 setting 可翻（型別表見 66 §A.3）；`color`／`range`／`url`／`image_picker` 等**不可翻** |
| `THEME_SETTINGS_CATEGORY` / `THEME_APP_EMBED` | 同上 | 必翻 | |
| `ONLINE_STORE_THEME` | 主題名 | 可選 | |

### B.3 不可翻清單（連同理由，避免日後有人「補上」）

| # | 欄位 | 為什麼不可翻 |
|---|---|---|
| 1 | `sku`／`barcode`／`gid://`／`inventory_item_id`／任何 ID | 它們是**識別碼**。翻譯識別碼 ⇒ 出貨單、WMS 整合、feed 對帳全部斷裂 |
| 2 | **`tags`** | 🔴 tag 是**集合運算的鍵**（13 §F4.3「標籤條件是集合運算，不是子字串」）。翻譯 tag ⇒ 該商品在中文版屬於「秋冬」系列、英文版不屬於任何系列——**系列成員資格隨語言變動**。要多語言的是**篩選標籤的顯示名**（`FILTER.label`），不是 tag 值本身 |
| 3 | **`Default Title`** | 🔴 硬相容契約（63 §B.2，`help` P18 ＋ Ella `fixture` 四處直接字串比對）。翻成「預設標題」⇒ Ella 的 `variants.first.title != 'Default Title'` 判定翻轉 ⇒ 無變體商品渲染出空的變體選擇器，**M6 golden theme 驗收直接失敗**。`limits.catalog_flow.default_variant_liquid_title` 的值**與語言無關** |
| 4 | 選項與選項值的**身分** | 譯文掛在 `product_option_values.id` 上，不是掛在字串上。63 §B.5「選項增刪時的變體身分保持」的前提是身分穩定；若變體以「選項值字串」比對，切語言就會找不到變體 |
| 5 | **所有金額**（price／compare_at／unit_cost／運費／禮品卡面額） | 鐵律 3 ＋ 65 號。金額是 integer cents，它沒有「語言版本」；語言只影響**格式化**（而格式化由 market locale 決定，§H.1） |
| 6 | 幣別碼、國家碼、語言碼本身 | ISO 值域。顯示名（「香港」／「Hong Kong」）是**平台字典**的翻譯，不是租戶資料 |
| 7 | `handle` | §D.3（本檔決策） |
| 8 | 訂單／退款／履行的**歷史文字** | 已發生事實的快照（56 §0.2 法域快照的同一條紀律）。訂單時間軸上的「已出貨」是**當時**寫入的字串，不隨日後語言設定重寫 |

### B.4 metafield：只有文字型可翻

```
可翻：single_line_text_field / multi_line_text_field / rich_text_field
      ＋ 上述三者的 list.* 變體（逐元素翻譯，元素順序即身分）
不可翻：number_* / date* / boolean / json / dimension / volume / weight / rating
        / color / url / 所有 *_reference / 🔴 money
```
🔴 **`money` 型 metafield 絕不進 `translations` 表**——這不只是「翻了沒意義」，而是**一旦它進了翻譯表，就存在一條把金額寫成字串再讀回來的路徑**，那正是鐵律 3 與 65 號要堵死的形態。實作上以 metafield definition 的 `type` 做**白名單**（不是黑名單）：未在白名單的型別，翻譯 API 一律回 `userErrors{code: FIELD_NOT_TRANSLATABLE}`。

---

## C. 資料模型

> 鐵律 2：以下每一張表都帶 `shop_id`，且複合索引一律以 `shop_id` 開頭。`platform_locales` 是**唯一的例外**（平台級字典，非租戶資料）——必須登記進 `config/tenancy_exempt_tables.yml`，比照 63 §L-2 的處置。

### C.1 語言註冊：兩張表，一個是字典、一個是租戶選擇

```sql
-- 平台級語言字典（跨租戶共用，隨平台版本演進；豁免 shop_id）
platform_locales(
  tag           VARCHAR(35) PRIMARY KEY,  -- BCP-47，正規化大小寫：zh-Hant / zh-Hans / en / ja
  language      CHAR(3),                  -- ISO 639-1（必要時 639-3）
  script        CHAR(4) NULL,             -- ISO 15924：Hant / Hans / Latn / Arab
  region        CHAR(2) NULL,             -- ISO 3166-1 alpha-2；**通常為 NULL**（見下）
  endonym       VARCHAR(64),              -- 語言自稱：繁體中文 / 简体中文 / English（切換器顯示這個）
  direction     ENUM('ltr','rtl') NOT NULL DEFAULT 'ltr',
  plural_rule   VARCHAR(32) NOT NULL,     -- 複數類別集合的識別字（'zh' 單型 / 'en' one+other / 'ar' 六型）
  date_format_id VARCHAR(32) NOT NULL,    -- 日期樣式集的識別字（§H.2）
  number_format_id VARCHAR(32) NOT NULL,  -- 非金額數字的分組與小數點（§H.2）
  collation     VARCHAR(64) NOT NULL,     -- 排序用（§C.7）
  status        ENUM('available','deprecated') NOT NULL
)

-- 租戶啟用的語言（承 29 §1.4 的 shop_locales，本檔補三欄）
shop_locales(
  shop_id, locale_tag,                     -- FK → platform_locales.tag
  is_source     BOOLEAN NOT NULL,          -- 🔴 恰一列為 true（§C.3）
  published     BOOLEAN NOT NULL,          -- 未發布＝只能用預覽連結（29 §1.2）
  position      INT,                       -- 切換器排序
  created_at, updated_at,
  UNIQUE (shop_id, locale_tag),
  UNIQUE (shop_id, is_source) WHERE is_source   -- 部分唯一索引；MySQL 用生成欄位模擬
)
```

**四條規則**：

1. **`region` 通常為 NULL。** 語言註冊的是**語言**；地區來自市場。只有語言本身確實因地區而不同（`pt-BR` vs `pt-PT`、`en-GB` vs `en-US` 的拼寫）才建帶 region 的條目。🔴 **不得**為了表達「香港的繁體中文」而建 `zh-Hant-HK`——那是 `zh-Hant` ＋ HK 市場，兩個維度（§A.1）。hreflang 的 `zh-Hant-HK` 由 62 §I.2 的 `hreflang_code(market, locale)` **當場組出**，不是存起來的。
2. **標籤格式驗證**（`i18n.locale_tag_format`）：ISO 639-1（+ 可選 ISO 15924 script + 可選 ISO 3166-1 alpha-2），沿用 62 §I.4 的白名單；拒 `EU`／`UK`／`es-419`／**裸 `zh`**。
3. **大小寫正規化在寫入層強制**（語言小寫、script Title case、region 大寫）。MySQL 的 `utf8mb4_0900_ai_ci`（11 §2-4）是大小寫不敏感的，所以 `zh-hant` 與 `zh-Hant` **不會**變成兩列——但**不得依賴 collation 做正規化**，因為 API 回傳與 URL 前綴生成都需要確定的字面值。
4. **上限**：`i18n.max_shop_locales`（20，出處 29 §1.2 `help`）。超過即 `userErrors{code: LOCALE_LIMIT_EXCEEDED}`。

### C.2 `translations` 表（承 29 §2.2，本檔補六欄）

```sql
translations(
  shop_id,
  resource_type   VARCHAR(48),   -- PRODUCT / COLLECTION / THEME_LOCALE_CONTENT / …
  resource_id     BIGINT,        -- 動態鍵資源（THEME_*）以 theme_file_id 當 resource_id
  locale_tag      VARCHAR(35),
  market_id       BIGINT NULL,   -- NULL=語言層；非 NULL=per-market 覆寫（29 §2.2 的 Adapt）
  field_key       VARCHAR(255),  -- 'title' / 'body_html' / 'sections.hero.settings.heading'
  value           MEDIUMTEXT,

  -- 承 29 §2.2 --------------------------------------------------------------
  source_digest   CHAR(64) NOT NULL,      -- SHA-256（正規化後，§C.5）
  outdated        BOOLEAN NOT NULL DEFAULT FALSE,

  -- 🔴 本檔新增六欄 ----------------------------------------------------------
  outdated_severity ENUM('none','minor','major') NOT NULL DEFAULT 'none',  -- §C.5
  value_source    ENUM('human','machine','script_conversion','import') NOT NULL,
  review_required BOOLEAN NOT NULL DEFAULT FALSE,   -- machine/script_conversion 一律 true
  source_locale_tag VARCHAR(35) NOT NULL,           -- 這條譯文是「從哪個語言翻的」（§C.3 改來源語言時要用）
  updated_by_staff_id BIGINT NULL,
  updated_at,

  UNIQUE (shop_id, resource_type, resource_id, locale_tag, market_id, field_key),
  INDEX  (shop_id, locale_tag, outdated, resource_type),        -- 「列出某語言全部過期」
  INDEX  (shop_id, resource_type, resource_id, locale_tag),     -- 渲染期批次載入
  INDEX  (shop_id, locale_tag, review_required)                 -- 「列出未覆核機翻」
)
```

**三條說明**：

- `market_id` 的語義**不變**（29 §2.2 已定）：per-market 覆寫優先於語言層翻譯。原型 `chilllove-admin-v2.html:6405` 已有這句文案，本檔不改語義。
- `value_source` 是稽核欄，形態對齊 62 §F.1 的 `alt_source`（`ai|human|imported`）與 62 §H.6-1 的 `content_source`——**同一條紀律**：無標記的大量自動內容日後無法回溯清理，而 Google 的 scaled content abuse（30 §1.2）是整站級處罰。
- `source_locale_tag` 不是冗餘：改來源語言（§C.3）時，需要知道哪些譯文是「從舊來源語言翻的」才能正確標記過期。

### C.3 來源語言（source locale）：誰是、能不能改

**(a) 誰是**：`shop_locales.is_source = true` 的那一列，**每店恰一列**。它的語義是：

```
🔴 base 資料表（products.title、collections.body_html…）裡的文字，一律是 source locale 的文字。
   其餘語言全部在 translations 表。
```

**(b) 為什麼不做 per-resource 來源語言**〔ours〕：一個看似體貼的設計是「這個商品是用英文寫的、那個是用中文寫的」。**拒絕的理由**：base row 的語言若逐列不同，就沒有任何消費者能回答「`products.title` 這個字串是什麼語言」——而站內搜尋的分析器（§C.7）、feed、AI 代理端點、匯出 CSV、admin 列表**全部**需要這個答案。一個無法從資料回答的問題，會變成每個消費者各自猜，最後長出五種不一致的猜法（鐵律 7 要防的形態）。**代價誠實記錄**：以英文為來源語言的商家新增一個只有中文的商品時，必須先填英文（可留簡短版）——這是刻意的摩擦，換來的是資料的語言可判定。

**(c) 能不能改**：**能，但它是一次性的資料遷移，不是設定切換。**

```
ChangeSourceLocale(from: A, to: B)  —— 走精靈，非同步 job，全程可回報進度
 1. 前置 gate：無進行中的翻譯匯入／機翻批次；B 必須已啟用且 published
 2. dry-run 報告：列出「B 有譯文的資源數 / B 缺譯文的資源數」——後者在遷移後 base row 會是空的
 3. 逐資源在同一 transaction 內：
      base(A 文字) → translations[(A, NULL)]（value_source 沿用原值，digest 重算）
      translations[(B, NULL)] → base（若缺 ⇒ 🔴 **base 保留 A 的原文**，並落一列 source_locale_migration_gaps）
 4. 全店 translations 的 source_digest 全部重算（因為 digest 綁的是「來源文字」，來源換了）
 5. shop_locales.is_source 切換；bump shops.catalog_version（63 §D.3）⇒ 全店快取失效
```

🔴 **步驟 3 的缺譯行為是本節最重要的一條**：若 B 沒有譯文就把 base 清空，商家會在一次「切換預設語言」之後看到**整店空白商品**。保留 A 的原文並記錄缺口，是唯一可接受的行為（原則 2）。

**(d) 不可刪除、不可 unpublish**：來源語言的 `published` 恆為 true，刪除操作一律 `userErrors{code: SOURCE_LOCALE_IMMUTABLE}`。

### C.4 fallback 鏈（🔴 必須明確定義，不得靜默空白）

```
resolve(resource, field, locale L, market M):
  1. translations[(L, M)]                       # per-market 覆寫（Adapt）
  2. translations[(L, NULL)]                    # 語言層翻譯
  3. for A in fallback_chain(L):                # §(a)，可能為空鏈
       translations[(A, M)] → translations[(A, NULL)]
  4. base row                                   # ＝ source locale 原文
  5. 仍為空 ⇒ 依 §B.1 的欄位類別決定：required→回 4 的值；optional→**不輸出整個欄位**
```

**(a) `fallback_chain(L)` 的規則**（`i18n.fallback_chain_mode: bcp47_truncation`）

```
zh-Hant-HK  → zh-Hant → ⛔停（不得續截到 zh）
zh-Hant     → ⛔停
en-GB       → en → ⛔停
pt-BR       → pt → ⛔停
```
- **只截尾、不跨枝**：`zh-Hant` 的鏈裡永遠不會出現 `zh-Hans`（`i18n.never_fallback_pairs`）。
- **不得續截到只剩語言碼、若該語言碼本身被禁用**（`zh`）。這是 `zh` 唯一被特別處理的地方，而處理方式是**縮短鏈**，不是特例分支。
- 商家**不可自訂** fallback 鏈〔ours〕。理由：可自訂的鏈會產生「A 回落 B、B 回落 A」的環，而環的偵測與診斷成本遠高於它的價值。需要跨語言借用內容時，正確作法是**複製成真實譯文**（§E.5(c) 的批次工具），那是看得見、可編輯、可稽核的。

**(b) 空值的定義**：`NULL`、空字串、**只含空白字元的字串**三者等價視為「無譯文」。🔴 富文本欄位另加一條：`<p></p>`／`<p><br></p>` 這類**語義空的 HTML** 也算空——否則富文本編輯器的初始值會讓 fallback 永遠不觸發，商家看到的是空白區塊而不是原文。

**(c) 前台的可見標記**：回落到來源語言的**大段文字**（`body_html`、政策）在前台加 `lang` 屬性標出真實語言（`<div lang="en">`）。理由是無障礙與搜尋引擎兩面：螢幕閱讀器會用錯的語音讀中文頁裡的英文段落；而 62 §I 的 hreflang 宣稱該頁是 `zh-Hant`，頁內卻有英文大段——`lang` 屬性是唯一誠實的表達。**短欄位（標題、按鈕）不加**，避免 DOM 噪音。

**(d) 遙測**：每一次落到步驟 3 以後都記一次 `i18n.fallback_hit{shop, locale, resource_type, field, depth}`。這是 §E.4 翻譯缺漏可視化的**真實資料來源**——比「掃描資料庫算缺幾筆」更有用，因為它按**實際流量**加權：沒人看的頁面缺翻譯不重要，首頁 banner 缺翻譯很重要。

### C.5 過期偵測（實務上最大的痛點，本節寫細）

**(a) digest 是什麼**：`SHA-256(normalize(來源文字))`，`normalize` 依欄位型別分三種（`i18n.digest_normalization`）：

| 欄位型別 | 正規化步驟 |
|---|---|
| 純文字 | NFC → trim → 內部連續空白摺疊為單一空格 |
| 富文本／HTML | 解析成 DOM → **屬性排序** → 移除純空白文字節點 → 摺疊空白 → 穩定序列化 |
| JSON（主題 setting） | 鍵排序 → 移除格式空白 → 穩定序列化 |

🔴 **為什麼一定要正規化**：不正規化的話，富文本編輯器把 `<p>a</p>` 存成 `<p>a</p>\n`、或把 `class="x" id="y"` 重排成 `id="y" class="x"`，就會把**全店全語言的譯文一次標成過期**。商家隔天看到「48,000 筆待更新」，然後這個功能就被永久忽略了。**過期偵測的價值完全取決於它的假陽性率。**

**(b) 分級**（`i18n.outdated_minor_change_ratio: 0.1`）

```
新舊來源文字正規化後相同        ⇒ severity = none   （digest 不變，什麼都不做）
字元層編輯距離 / 原長度 ≤ 0.1   ⇒ severity = minor  （標記，但不進「待翻譯」預設篩選）
其餘                            ⇒ severity = major  （進「待翻譯」，進進度條的分母）
```
分級存在的唯一理由是**假陽性**：修一個錯字不該讓三語 × 五萬商品全部進待辦。`minor` 仍然可查、可篩、可批次標為已覆核。

**(c) 🔴 `outdated` 不影響前台渲染。** 過期的譯文**照常顯示**。理由：一個錯字修正若讓整個語言版本退回英文，那是把小問題放大成事故。`outdated` 是**後台狀態**，影響的是：①翻譯後台的清單與進度條；②feed／AI 端點的內部品質訊號（不外洩）；③商家可選的「過期譯文顯示警示徽章（僅預覽模式）」。

**(d) 觸發時機**：來源欄位寫入時，在**同一 transaction 內**重算 digest 並比對；不相等則 `UPDATE translations SET outdated=1, outdated_severity=? WHERE shop_id=? AND resource_type=? AND resource_id=? AND field_key=?`（一次更新該欄位的全部語言）。這是一個以 `(shop_id, resource_type, resource_id)` 為前綴的索引命中，成本可控。🔴 **不得**丟到非同步 job：來源已改、譯文未標記的視窗裡，商家會以為翻譯是最新的。

**(e) token 保護**：範本類欄位（`EMAIL_TEMPLATE`、`PAYMENT_GATEWAY.instructions`）內含 `{{ … }}` 佔位符。digest 照全文算，但**譯文的驗證器必須檢查佔位符集合與來源一致**（缺少或新增一律 `userErrors{code: PLACEHOLDER_MISMATCH}`）。缺一個 `{{ order_number }}` 的訂單確認信是會真的寄出去的。

**(f) 🔴 `outdated` 的對外出口＝翻譯 CSV 的 `status` 欄**（依 69 §V-182 新增，2026-08-12）

本節原本只定義了 `outdated` 的三個**後台**用途（(c) 的清單、進度條、內部品質訊號），**沒有定義它怎麼交給譯者**——而譯者才是要處理過期譯文的那個人。

69 號查到本尊的原生翻譯 CSV 有一個 `Status` 欄，三值 **`Translated` / `Outdated` / `Untranslated`**（`help` ＋ `vendor` 獨立佐證），其中 `Outdated` 的語義**正是本節的過期偵測**——也就是說**本尊把「過期」做成了匯出檔的一等公民欄位**。

⇒ 我方對應：`i18n.export.status_values: [translated, outdated, untranslated]`，映射規則為

```
該 (resource, locale, field) 無譯文列                    ⇒ untranslated
有譯文列 ∧ outdated = true（severity 不分 major/minor）  ⇒ outdated
其餘                                                     ⇒ translated
```

- **severity 不進 CSV**：它是我方獨有的假陽性抑制機制（(b)），對外部譯者沒有意義，且多一個值就會與本尊的三值不對齊。要篩 `minor` 請用後台。
- 🔴 **`status` 純輸出，匯入時忽略**（`status_is_export_only: true`）：⚠ **V-201** 未查明本尊匯入時是否讀取該欄。讓譯者能用一個欄位值把資源標成「已是最新」，等於把 digest 比對（§E.6(b)）繞過去——**過期狀態只能由來源 digest 決定，不能由檔案宣稱**。

### C.6 翻譯進度物化表（鐵律 7：進度數字只有一個來源）

```sql
translation_status(
  shop_id, resource_type, resource_id, locale_tag,
  translatable_fields   INT,   -- 該資源在該時點的可翻欄位數（隨 metafield 定義變動）
  translated_fields     INT,
  outdated_major_fields INT,
  outdated_minor_fields INT,
  machine_unreviewed_fields INT,
  computed_at,
  PRIMARY KEY (shop_id, resource_type, resource_id, locale_tag),
  INDEX (shop_id, locale_tag, translated_fields)      -- 「這個語言最缺的資源」排序
)
```

- **一份資料四個出口**（鐵律 7）：①商品列表的「翻譯」欄徽章 ②翻譯後台的資源樹進度 ③SEO／內容健康頁的全店百分比 ④GraphQL `translationStatus` 欄位。四者**必須讀同一張表**，不得任一處現算 `GROUP BY`。
- 維護方式：翻譯寫入／來源寫入／metafield 定義變更 ⇒ 同 transaction 內增量更新該列；nightly job 全量重算對帳（形態同 29 §1.5(a) 的 `derived_parent_market_id`）。
- **不含未啟用語言**：只為 `shop_locales` 內的語言建列。啟用新語言時批次建列（背景 job，可斷點續跑）。

### C.7 排序與搜尋：語言相依，且**不是同一件事**

| 面 | 規則 |
|---|---|
| **排序（collation）** | `platform_locales.collation`。中文以 `utf8mb4_0900_ai_ci` 排序會得到近似碼點序，對使用者是隨機的。⚠ MySQL 8 是否提供可用的中文拼音 collation（如 `utf8mb4_zh_0900_as_cs`）**未查證 ⇒ V-166**。在結案前：admin 列表排序沿用預設 collation 並在 UI 標「依系統順序」，**不宣稱是筆畫或拼音排序** |
| **站內搜尋** | 🔴 索引鍵含 `locale`，**且分析器 per-locale**。D6（DECISIONS.md）定的 `MySQL ngram` 對中文正確、對英文會產生大量噪音詞元；反之 word-boundary 分析器對中文只能整句成詞。⇒ `i18n.search_analyzer_by_script`（`Hant/Hans/Jpan → ngram`，其餘 → 內建詞界）。**同一個查詢只搜當前語言的索引**，並在無結果時提示「以其他語言搜尋」（不自動跨語言搜——那會讓中文查詢回英文結果，看起來像壞掉） |
| **可被發現的範圍** | 站內搜尋索引一律套 `discoverable` scope（13 §F1.2(e) 第 5 項）。**多語言不改變這條**：`UNLISTED` 商品的任何語言版本都不進索引 |

---

## D. ⭐ handle 政策（裁定的核心）

### D.1 生成規則：從裁定的範例逐條逆推

**裁定給的範例**（`ruling`）：

```
標題（推定）：Kérastase Spécifique Stimuliste Nutri-Energising Daily Anti-Hairloss Spray 125ml/4.2oz
handle      ：kerastase-specifique-stimuliste-nutri-energising-daily-anti-hairloss-spray-125ml-4-2oz
                                                                                 ↑ 86 字元、12 個 token
```

**逆推出的六個事實**（每一條都能從範例本身讀出來）：

| # | 觀察 | 規則 |
|---|---|---|
| 1 | `Kérastase` → `kerastase` | **變音符號折疊**（NFKD → 去除 combining marks）。⚠ 也可能來源標題本就無重音；無論如何我方**定案為折疊**，因為帶重音的字元在 URL 需 percent-encoding，違反「一律 ASCII」 |
| 2 | 全部小寫 | **大小寫折疊**在折疊變音符號之後（避免 `İ` 之類的邊界） |
| 3 | `Nutri-Energising` 的連字號保留為 `-` | 既有 `-` 與分隔符**同構**，不做特別處理 |
| 4 | `125ml/4.2oz` → `125ml-4-2oz` | 🔴 **`/` 與 `.` 都轉成分隔符，不是刪除。** 若刪除 `.` 會得到 `42oz`——**規格數字被改寫**。這是本節最重要的一條 |
| 5 | 長度 86 未被截斷 | 上限**遠大於 86**。我方定 255（`handle.max_chars`；⚠ 官方出處未取得，但已有 `press` 級二手佐證且**數值相同** ⇒ 原 V-160 降級，官方出處由 68 的 **V-183** 承接） |
| 6 | 沒有任何連續分隔符、沒有首尾分隔符 | **收斂 ＋ 修剪** |

**完整管線**（`Handles::Generate`，全專案唯一實作；下列步驟已用範例做過可重跑驗證，輸出與裁定給的字串**逐字元相同**）：

```
handleize_url(text):
  1. NFKC 正規化            # 全形 → 半形：ＳＫ－ＩＩ　230ｍL → SK-II 230mL；全形空白 U+3000 → 空白
  2. 刪除撇號與引號類        # ' ’ ‘ ʼ " “ ” ` ´  →  ""（**刪除，不是分隔**）
                            #   Bob's → bobs（不是 bob-s）；L'Oréal → loreal
  3. 不可分解拉丁字母轉寫表   # ß→ss  ø→o  đ→d  ł→l  æ→ae  œ→oe  þ→th  ð→d  ı→i  ŋ→ng
                            #   🔴 必要：NFKD 不分解這些字母，少了這一步 Straße → stra-e
  4. NFKD → 去除 combining marks → NFC   # é→e  ü→u  ñ→n
  5. 轉小寫（ASCII 範圍）
  6. 所有非 [a-z0-9] 的連續字元 → 單一 "-"   # 空白 / _ . , : ; ! ? % & ( ) [ ] " " / \ … 全部在此
  7. 修剪首尾 "-"
  8. 若長度 > handle.max_chars：在 max_chars 位置**向前找最近的 "-" 切斷**，再修剪尾部 "-"
                                            # 🔴 不得從字元中間切（會產生半個詞）
  9. 品質閘門（§D.2(b)）：ASCII 字母數 < handle.min_latin_alpha_chars(3)
                          ∨ 被丟棄的字母比例 > handle.max_dropped_letter_ratio(0.5)
                          ⇒ **不採用本結果**，落 §D.2 的 fallback
```

**驗證樣本**（可重跑；輸出即規格）：

| 輸入 | 輸出 | 閘門 |
|---|---|---|
| `Kérastase Spécifique … 125ml/4.2oz` | `kerastase-specifique-stimuliste-nutri-energising-daily-anti-hairloss-spray-125ml-4-2oz` | ✅ 通過 |
| `Bob's Burgers — 50% OFF!!` | `bobs-burgers-50-off` | ✅ |
| `Müller Straße Größe 10` | `muller-strasse-grosse-10` | ✅（步驟 3 生效） |
| `ＳＫ－ＩＩ　フェイシャル　230ｍL` | `sk-ii-230ml` | ⚠ 丟棄比例 0.5 ⇒ 邊界通過，**但標記「handle 可能不完整」** |
| `無印良品 MUJI 有機棉 T-Shirt` | `muji-t-shirt` | ✅ 通過（丟棄 0.41） |
| `棉質短T` | `t` | ❌ 字母數 1 < 3 ⇒ **落 fallback** |
| `香港手工曲奇禮盒` | `（空）` | ❌ ⇒ **落 fallback** |

> **`%` 的處置**：`50%` → `50`（分隔後收斂）。**不做 `%`→`percent` 的詞彙展開**，也不做 `&`→`and`〔ours〕。理由：詞彙展開是**英文特定**的，一旦開了頭就要為每個語言維護一張展開表，而它換來的 SEO 收益沒有任何證據支持。
> ✅ **依 68 號 §C-6 補證：與 Shopify 完全一致，實測 5 次確認**（`test`）：`Carroll&Chan → carroll-chan`、`Bags & Wallets → bags-wallets`、`Herbs & Grow Kits → herbs-grow-kits`、`Plant Duos & Trios → plant-duos-trios`、`… Clarks Originals & the New York Yankees → …-clarks-originals-the-new-york-yankees`；**0 例展開成 `and`**。`%`／`$` 同樣轉分隔（`Clearance 50% Off → clearance-50-off`、`Only HK$88 → only-hk-88`）。⇒ 本條從〔ours〕升為**已對齊本尊**，不得再被當成待確認項重開。

**與 Shopify 實際行為的逐條對照**（依 68 號 §C-4 補入；`dev` ＝官方文檔，`test` ＝本輪對真實店鋪 `/products.json`／`/collections.json` 的一手實測）：

| 我方步驟 | Shopify 行為 | 對照 | 出處 |
|---|---|---|---|
| 1 NFKC（全形→半形） | **未查證** | ⚠ 未知 | 68 **V-181** |
| 2 撇號／引號**刪除** | 刪除（`Women's → womens`、`16" Cash Drawer → 16-cash-drawer`） | ✅ 一致 | `test` |
| 3 不可分解拉丁字母轉寫 | 拉丁擴充**折疊成 ASCII**（`mašīna → masina`、`… ŭ → …-u`） | ✅ 同方向 | `press`（staff 復現） |
| 4 變音符號折疊 | 折疊（`Créature → creature`、`Décor → decor`） | ✅ 一致 | `test` |
| 5 轉小寫 | 一律小寫 | ✅ 一致 | `dev` |
| 6 其餘 → 分隔符（含 `.` `/` `%` `$` `&`） | 全部轉分隔（`A.P.C. → a-p-c`、`#AU/NZ → au-nz`、`&` 不展開 ×5） | ✅ 一致（🔴 觀察 4 被 `A.P.C.` 與 `#AU/NZ` 獨立佐證） | `dev` ＋ `test` |
| 7 收斂＋首尾修剪 | 收斂；**開頭移除**（官方明載）、**結尾修剪**（官方只提開頭，實測確認結尾也修） | ✅ 一致 | `dev` ＋ `test` |
| 8 分隔符邊界截斷（255） | 上限 255、超過截斷 | ⚠ 僅 `press` ⇒ 68 **V-183** | `press` |
| 9 **品質閘門** | 🔴 **Shopify 無此概念**（它保留 CJK 就不需要） | 🔴 **我方獨有**，「一律英文」裁定的必然衍生物 | 68 §C-4 |
| `_` 的處置 | handle 中**允許存在**；自動生成是否保留**未證** | ⚠ 未知；我方 `_ → -` | 68 **V-181** |
| 非拉丁（CJK 等） | 🔴 **原樣保留** | 🔴 **明知偏離**（裁定 > Shopify），登記於 62 §F.3-1 | `press` ×4 |
| 改標題不動 handle | 不自動改 | ✅ 一致（`regenerate_on_title_change: false`） | `dev` |

**保留數字與規格串**：步驟 6 不在字母與數字之間插入分隔符（`125ml` 保持一個 token），這與範例一致，也是規格型 handle 可讀的關鍵。

### D.2 中文標題怎麼產生英文 handle —— **我方決策**

**選項評估（四選一，逐條寫明淘汰理由）**

| 選項 | 淘汰／採用理由 |
|---|---|
| **A. 音譯（拼音）** | ❌ ①**對粵語圈是錯的**：基準法域是香港（鐵律 11），「靚太保濕面膜」的普通話拼音 `liang-tai-bao-shi-mian-mo` 對香港買家、對英文買家、對 AI 代理**同時**無意義；②**多音字讓「確定性」也不成立**（行 xing/hang、長 chang/zhang、重 zhong/chong），要選讀音就要維護一張詞典，而詞典會出錯且要跨繁簡；③產生的字串**沒有任何搜尋價值**——沒有人會搜 `liang-tai`。裁定要的是「英文標題」，拼音不是英文 |
| **B. 機器翻譯自動落庫** | ❌ **違反設計原則 3（URL 是永久身分，生成器必須確定性）**：MT 的輸出隨供應商模型版本改變，同一個標題今天譯成 `moisturizing-mask`、明天譯成 `hydrating-mask`；而 handle 每變一次就是一條 301 ＋ 一個永不回收的舊 handle（§D.4）。另外它**在寫入路徑上引入外部 IO**，直接撞 63 §A.2「transaction 內禁外部 IO」與鐵律 5 |
| **C. 要求商家手填** | ⚠ 品質最高但**不能當成唯一路徑**：擋住儲存 ⇒ 商家繞道亂打（`aaa-bbb`），那比自動代碼更糟——**亂打的字串無法被偵測與修復，自動代碼可以** |
| **D. 用 SKU／型號** | ❌ ①SKU 非必填、可重複（軟唯一，61 §1.5）；②SKU 常含內部編碼與供應商代號，放進公開 URL 是**營運資訊外洩**；③`sku-ab-12345` 對搜尋與 AI 一樣無語義 |
| **E. 照 Shopify 保留 CJK**（中文標題 ⇒ 中文 handle，URL 走 percent-encoding） | 🔴 **這是本尊的實際做法**（68 §B-1：非拉丁字集**原樣保留**，`press` ×4；本尊沒有 fallback 代碼也沒有品質閘門，因為它不需要）。**被使用者裁定直接排除**——裁定逐字「url hand 使用英文標題，**禁止使用中文**」。<br>⇒ 本選項不是「評估後淘汰」，是「**裁定 > Shopify**，沒有評估空間」。<!-- 依 68 號 §B-1 新增本列：原表只有 A–D 四個選項，讀起來像是「我方在四個爛選項裡挑一個」，而事實是**還有第五個選項、它是本尊的做法、而且我方明知並偏離**。缺這一列，日後回頭看會以為我方沒查過本尊怎麼做。 --> |

**🔴 我方決策 D-67-H1：handle 的來源是「英文（`en`）標題」，並以確定性 fallback 兜底；不做拼音、不做 MT 自動落庫、不擋商家做生意。**

> 🔴 **本決策是「明知偏離 Shopify」，不是「對齊 Shopify」**（68 §B-1，登記於 62 §F.3-1）：本尊會保留 CJK 並給出中文 handle，從不落代碼、也不擋發布。我方偏離的**唯一依據是使用者裁定**。
> ✅ **「不擋發布」這一半與本尊一致**（Shopify 也不擋，官方沒有 handle 品質的閘門、警告或健康度概念）——所以 `require_meaningful_on_publish: false` 是**對齊**，不是我方的寬鬆。
> 🔴 **品質閘門（§D.2(b)）與中英混排保留英文片段是「一律英文」裁定的必然衍生物**，本尊**無此概念**（68 §C-4／C-5）。裁定若改，它們必須連帶重審——它們不是獨立的設計選擇。

```
handle_source_priority（handle.source_field_priority）:
  1. 商家手填的 handle                      → 直接使用（仍過 §D.1 的清洗與驗證）
  2. translations[(en, NULL)].title 的 slug  → 過 §D.1 全部步驟含品質閘門
  3. base title 的 slug（來源語言即為拉丁文字時，這一步與 2 同義）
  4. 確定性 fallback：product-{token}        → token = 8 字元 Crockford base32，per-shop 隨機且不重用
```

**為什麼「英文標題」這一步是免費的——這是本決策成立的關鍵**：裁定的第二句是「**商品所有數據……都要做多語言。先開始時繁體中文、簡體中文、英文**」。也就是說**英文標題本來就是要填的欄位**，不是為了 handle 額外增加的負擔。**只要多語言做對了，handle 的中文問題自動消失。** 反過來說，這也解釋了為什麼裁定把這兩件事寫在同一段話裡。

**(a) 不擋發布，但擋「靜默」**〔ours〕

`handle.require_meaningful_on_publish: false`（商家可自行開成 true 作為自我約束）。理由：URL 品質是**商家的 SEO 資產**，不是平台的合規紅線。用硬擋去換 URL 品質，換來的是選項 C 的失效模式（亂打）。取而代之的是四條**可觀測**的摩擦：

1. 落 fallback 時，商品編輯頁與 SEO 卡（62 §E.3）顯示常駐提示：「此商品的網址是自動代碼，建議填寫英文標題」＋一鍵跳到內容語言 `en`。
2. 商品列表可篩「網址為自動代碼」。
3. SEO 健康頁顯示全店「自動代碼 handle 佔比」。
4. 提供「以機器翻譯產生英文標題草稿」按鈕——**MT 產生的是 `en` 標題的草稿（人確認後才成為譯文），handle 再由該譯文推導**。MT 因此始終在**人的確認之後**，決策 3 的確定性不被破壞。

**(b) 品質閘門的存在理由**：`棉質短T` → `t` 這種「殘渣 slug」比 `product-a7k3m2q9` **更糟**——它幾乎必然與其他商品碰撞（於是變成 `t-2`、`t-3`），而且對任何人都無語義。閘門把「殘渣」與「可用的部分英文」分開（`無印良品 MUJI 有機棉 T-Shirt` → `muji-t-shirt` 是可用的）。

**(c) handle 只在建立時自動生成一次。** 之後標題變更**不自動改 handle**（改 URL 是有代價的動作，見 §D.4）。改標題時在 SEO 卡顯示可選動作：「同步更新網址（會建立 301 轉址）」。

### D.3 每語言一個，還是全站一個？—— **全站一個，語言在前綴**

**🔴 決策 D-67-H2 —— 明知偏離 Shopify：`handle` 是 per-shop-per-resource 的單一值，不隨語言變；語言維度由 URL 路徑前綴承載。**

<!-- 依 68 號 §F-1 改標（2026-08-12）。原標題：「**🔴 我方決策 D-67-H2：…**」
     🔴 **原標題讀起來像是我方自己選的技術偏好，實際上它偏離了 Shopify 的既有能力，而 68 號之前
        沒有人把這件事寫下來**（它甚至不在 2026-08-12 的待裁決清單裡）。
     Shopify 的實際能力（`dev`：shopify.dev/changelog/resource-url-handles-are-now-translatable，
       **2023-06-26**，API 2023-04）：**product／collection／article／blog／page 的 URL handle
       可透過 `translationsRegister` 註冊翻譯**，產生在地化的線上商店 URL
       （官方例 `/products/red-shoes` 與 `/products/…/zapatos-rojos`）。
       實務佐證（`press`）：啟用多語言後同一商品在各語言下**就是不同的 handle**；
       AJAX API `/products/{handle}.js` 必須用**該語言的 handle**。
     我方 `docs/research/29-markets-i18n.md` §2.1 **早就記載** PRODUCT 的可翻欄位含 `handle`。
     ⇒ 這條偏離**同樣是「handle 一律英文」裁定的下游後果**，不是獨立的技術偏好：
       handle 一律英文 ⇒ per-locale 的三個 handle 都會是英文 ⇒ 那不是在地化，是同義詞增生。 -->

| | 內容 |
|---|---|
| **Shopify 的能力** | handle **是可翻譯欄位**（2023-06-26 起，`dev`）；多語言下同一資源在各語言可有不同 handle |
| **我方的行為** | 單一 handle（`limits.handle.per_locale_enabled: false`、`translatable: false`），語言走 URL 前綴 |
| **偏離的依據** | 🔴 **裁定的下游後果**：handle 一律英文 ⇒ per-locale 收益為零，卻要付三倍的 301、唯一性與 N+1 成本（下面四條理由）。**唯一依據是裁定，不是技術偏好** |
| **裁定若改** | 本決策**必須連帶重審**。逃生口已就位（`per_locale_schema_reserved: true`，開鍵即可，不需 migration） |
| **待使用者確認** | ⚠ 「handle 一律英文」是否**同時**意味著放棄 Shopify 的 per-locale handle 能力？**我方推定是，但這是推定**（68 §F-1 明列為要問使用者的一句話） |

```
✅ 採用           /products/kerastase-…-4-2oz            （primary market 的預設語言，無前綴）
                  /en/products/kerastase-…-4-2oz
                  /zh-hans/products/kerastase-…-4-2oz

❌ 不採用（A）    /products/kerastase-…-4-2oz-en          （語言寫進 handle 尾綴）
❌ 不採用（B）    /en/products/kerastase-…  ＋ /zh-hans/products/kaisi-…   （每語言不同 handle）
```

**理由（四條，其中前兩條是決定性的）**

1. **裁定已經讓 per-locale handle 失去意義。** handle 一律英文 ⇒ 三個語言版本會有**三個英文 handle**。那不是在地化，是**同義詞增生**：三條 URL 描述同一個商品、三份 301 要管、三倍的唯一性衝突機會，而在地化收益是**零**（因為都必須是英文）。
2. **與 62 §I.1 的矩陣天然對齊。** 62 的 `absolute_url(resource, wp, loc)` 在本決策下是純字串拼接：`origin(wp) + url_prefix(wp, loc) + "/products/" + handle`——**不需要查每語言 handle 表**。若 handle per-locale，這個函式就要對每個 (wp, locale) 查一次 DB，而它會被 hreflang（每頁 N 條）、sitemap（每資源 N 條）呼叫，直接變成 N+1。
3. **301 與唯一性大幅簡化**：`url_redirects` 以**不帶前綴的正規路徑**登記（`/products/old` → `/products/new`），路由層對任何 locale 前綴的請求**先剝前綴再查表**。若 handle per-locale，一次改名要為每個語言寫一列，且刪一個語言時那些列變成孤兒。
4. **淘汰方案 A 的具體理由**：`-en` 尾綴與衝突尾綴 `-2` 在字面上**無法區分**，路由層與唯一性檢查都要特例；而且它把語言塞進了「商品身分」的字串裡，違反 §A.1 的維度分離。

**逃生口（不改 schema 就能開）**：表結構預留 `resource_handles(shop_id, resource_type, resource_id, locale_tag NULL, handle)`，首發 `locale_tag` **恆為 NULL**，並以 `handle.per_locale_enabled: false` 鎖住。日後若某市場的 SEO 真的需要不同英文用詞，開鍵即可，不需 migration。

**與 62 §B.4 的對齊**：每個語言版本各自 self-canonical（62 §B.4 已定「一律 self-canonical，不跨市場 canonical」），因此三條 URL 都可索引、都能作為 hreflang 的有效目標。本決策**不改變**這一點——它只決定了「差異放在前綴而不是 handle」。

### D.4 唯一性、衝突、改名 301、永不回收

**(a) 唯一性範圍**：`UNIQUE (shop_id, resource_type, handle)`（鐵律 2：複合索引以 `shop_id` 開頭）。

- **per resource_type，不是 per shop 全域**：`/products/summer` 與 `/collections/summer` 可以並存（URL 前綴不同）。
- **不乘 locale**（§D.3 的直接結果）。
- 🔴 **唯一性檢查的對象是「現用 handle ∪ 已退役 handle」**：退役集合＝`url_redirects` 中該 shop、`from_path` 形如 `/{resource_prefix}/{handle}` 且 `source='handle_change'` 的列。這就是 62 §F.3「舊 handle 永不回收」的可執行定義——**不另建第二張表**，因為 62 已經允許商家手動刪除該重導來釋放 handle，兩張表會立刻不同步。

**(b) 衝突處置：生成與手填要用不同策略**〔ours〕

<!-- 依 68 號 §C-4/5/6 附帶條跟隨 Shopify 做法修正（2026-08-12）。
     原文（保留供追溯，🔴 任何人不得改回）：
       「| **系統生成**（§D.2 的 2/3/4 步） | 自動加尾碼 `-2`、`-3`…（`handle.collision_strategy_generated`）。
           首個重複者得 `-2`（不是 `-1`）——「第二個」的直覺對應 |
        > ⚠ 既有 13 §F2-2 寫的是「衝突自動 `-1` `-2` 後綴」，與本節的 `-2` 起算及「手填拒絕」不一致
          ⇒ 登記於 §M-1。」
     🔴 **這條不一致是反向解決的：13 §F2-2 寫的 `-1` 本來就是對的，要改的是本檔。**
        Shopify 實際行為＝**自 `-1` 起算**：官方例兩個同名商品得到 `potion` 與 `potion-1`
        （`dev`，liquid/basics）；本輪實測（`test`）同店兩個同名系列得到
        `ceiling-fans` / `ceiling-fans-1`，另見 `home-decor-accessories-1`、`nathan-road-collection-1`。
        原文的「『第二個』的直覺」**沒有任何依據**，而它的代價是：從 Shopify 匯入的資料重新生成時
        整批偏移一號（本尊 `potion-1`、我方 `potion-2`），對不上舊 URL。 -->

| 來源 | 衝突時 |
|---|---|
| **系統生成**（§D.2 的 2/3/4 步） | 自動加尾碼 **`-1`、`-2`…**（`handle.collision_strategy_generated: numeric_suffix_from_1`）。**首個重複者得 `-1`**——跟隨 Shopify（`dev` 官方例 `potion`／`potion-1` ＋ `test` 實測 ×4） |
| **商家手填** | 🔴 **拒絕**，回 `userErrors{field:"handle", code:"HANDLE_TAKEN"}`，並在訊息中指出佔用者（含「該 handle 已退役但仍有 301 指向 X」的情形）。**不得靜默加尾碼**：那是把商家明確輸入的值偷偷改掉。⚠ 官方講的自動加尾碼是針對「duplicate **title**」，**不是手填 handle**，本尊對手填重複的處置**無一手證據**（68 **V-184**）⇒ **維持 reject（保守失效）** |

> ✅ **與 13 §F2-2 的不一致已反向結案**（§M-1）：13 的 `-1` 起算是對的，本節改為 `-1`。**兩份規格現已一致，任何一方不得單獨改回 `-2`。**

**(c) 保留字**：`handle.reserved` —— 至少含 `all`（`/collections/all` 是平台路由）、`new`、`index`、以及**全部啟用中的 locale 前綴與市場 subfolder suffix**。新增語言時必須檢查其前綴不與既有第一路徑段衝突（`handle.reserved_first_segments`），衝突則拒絕新增語言。

**(d) 改名 301**（承 62 §F.3，本檔不改語義，只補多語言面）：handle 變更時在同一 transaction 插入 `url_redirects(from=/products/舊, to=/products/新, 301, source=handle_change)`。**多語言的補充**：登記與比對一律用**不帶前綴的正規路徑**；路由層命中 404 前，先剝 locale 前綴 → 查表 → **命中後把前綴加回去再 301**（`/en/products/舊` → `/en/products/新`，不是丟回 `/products/新`——那會把英文使用者踢回預設語言）。

**(e) 重導鏈**：沿用 `seo.redirect_max_chain: 10` 與 13 §F2 的環偵測。

### D.5 🔴 Liquid `handleize` filter **不是** URL handle 生成器（本節防的是一次靜默的主題事故）

Ella 用 `handle`／`handleize` filter **91 處**（27 §5 的 Ella 相容集用量表，`fixture`）——它們**幾乎都不是在產生 URL**，而是在把選項名、選項值、色票名轉成 **CSS class 名／DOM id／JS 物件鍵**：

```liquid
data-option="{{ option.name | handleize }}"      ⇒ 選擇器要靠它比對
class="swatch-{{ value | handleize }}"
```

若把 §D.1 的 ASCII-only 管線直接套上這個 filter：

```
{{ '顏色' | handleize }}  →  ""     ⇒  data-option=""  ⇒  多個選項的選擇器全部相同
                                     ⇒  變體選擇器選錯選項，**不報錯、不空白，只是選錯**
```

**規定**（`handle.liquid_filter_ascii_only: false`）：

<!-- 依 68 號 §F-3 跟隨 Shopify 做法修正（2026-08-12）：**fallback 觸發條件收窄**。
     原文（保留供追溯，🔴 任何人不得改回）：
       「| 空結果 | 落 §D.2 的 fallback | 🔴 落 `h-{sha1(input)[0,8]}`——**空字串會造成選擇器碰撞，必須有值** |」
     原文沒有說清楚「空結果」是怎麼來的，實作時最自然的讀法是「套完清洗規則後結果為空」——
     而那個讀法會讓 `{{ '顏色' | handleize }}` 落到 `h-xxxxxxxx`。
     68 §F-3 查到（community.shopify.dev/t/unicode-in-handleize-output/1060，2024-10，**staff 已復現**）：
       `{{ 'Abc 123-D--E 🔪 ŭ' | handleize }}` 的實際輸出**保留 emoji**、`ŭ` 折成 `u`
       ⇒ Shopify 的 filter 對非拉丁字元是**保留**，不是落空。
     🔴 ⇒ `{{ '顏色' | handleize }}` 在本尊**回 `顏色`**。我方若落 fallback，會輸出一個
        **本尊永遠不會產生的字串**；主題若把 handleize 的輸出寫死進 CSS（Ella 91 處用量）就對不上，
        而且是「樣式靜默失效」這種最難查的形態。 -->

| | `Handles::Generate`（URL 身分） | Liquid `handleize` filter（主題字串工具） |
|---|---|---|
| 值域 | `[a-z0-9-]`，ASCII only（裁定） | **保留非 ASCII 字母**（維持既有行為，✅ 與本尊一致：staff 復現的輸出保留 emoji） |
| **fallback 觸發** | 品質閘門不過 ⇒ 落 §D.2 的 fallback | 🔴 **只在「輸入本身為空或全為分隔符」時**落 `h-{sha1(input)[0,8]}`（`handle.liquid_filter_fallback_trigger: empty_or_all_separator_input_only`）。<br>🔴 **不得因「結果非 ASCII」觸發**（`liquid_filter_fallback_on_non_ascii_result_forbidden: true`）——`{{ '顏色' \| handleize }}` 必須回 `顏色`，**不是** `h-xxxxxxxx` |
| 用途 | 資源的永久 URL 身分 | DOM id／CSS class／JS 鍵 |
| 實作 | 🔴 **兩個獨立實作，不得共用**；filter 的文檔註釋必須寫明「這不是 URL 生成器」。<br>（本條**不變**：URL 要 ASCII-only 是裁定、filter 要保留非 ASCII 是相容需求，兩個值域天生不同。68 §F-3 修正的是 fallback 觸發條件與其**依據**，不是這條分離規則。） | |

> ✅ **V-161 已依 68 §F-3 縮小**：原問題「Shopify `handleize` filter 對 CJK 的實際輸出（保留／落空／轉寫）」**已被正面回答＝保留**（`press`，staff 復現的 bug 報告；官方文檔與實際輸出不符，staff 承認並轉產品團隊，無結論）。
> ⇒ 這正面解決了本節最擔心的情境：**本尊不會產生空結果，所以我方的 fallback 在對齊本尊的情境下永遠不該被觸發**。殘留未證的只剩**全形字元**與**空輸入／全分隔符輸入**兩個邊界（併入 68 的 **V-181**）。主題匯入的 degradation report（25 §4-4）仍加一行說明。

### D.6 遷移：既有 unicode handle 的處置

M0 之前無應用程式碼（HANDOFF §5），**沒有生產資料要遷移**。真正要處理的是**從 Shopify 匯入的商家**：

1. 匯入器遇到非 ASCII handle ⇒ **保留原 handle 作為 301 來源**，用 §D.2 的管線產生新 handle，並寫入 `url_redirects(source='import')`。
2. 🔴 **保留原 handle 的可訪性是硬要求**：商家從 Shopify 搬過來時，舊 URL 已經有外部連結與索引。匯入報告必須列出「已改寫的 handle 數」與逐筆對照，供商家覆核。
3. 匯入產生的 fallback handle（`product-xxxx`）計入 §D.2(a) 的「自動代碼佔比」指標。

---

## E. 後台（admin）多語言

### E.1 兩層語言：**兩個切換器，不得連動**

| | **介面語言**（admin UI locale） | **內容語言**（content locale） |
|---|---|---|
| 誰的屬性 | **員工**（`staff_members.ui_locale`） | **編輯工作階段** |
| 值域 | 平台支援的 admin 語言（隨平台版本部署） | 該 shop 已啟用的語言（`shop_locales`） |
| 字串存哪 | 🔴 **平台 i18n bundle**（跨租戶共用、隨版本部署） | 🔴 **租戶 `translations` 表** |
| 預設 | 員工設定 → shop 的 admin 預設 → 平台預設 | shop 的 **source locale** |
| 狀態放哪 | 使用者偏好（DB） | 🔴 **URL query（`?content_locale=en`）** ＋ 記住上次選擇 |
| 影響 | 按鈕、欄位標籤、錯誤訊息 | 正在讀寫哪一份譯文 |

**🔴 為什麼平台 UI 字串不得進租戶 `translations` 表**：①每個租戶會存一份平台字串副本（幾千 key × N 租戶 × N 語言）；②租戶能改平台 UI 文案，平台改版時無法覆蓋；③平台字串的 key 命名空間會與租戶內容混在同一個唯一索引裡。**兩者連查詢路徑都不同**：平台字串在部署時載入記憶體，租戶譯文隨請求查 DB。

**🔴 為什麼不得連動**（合成一個下拉的具體事故）：商家把「語言」切成 English 想看懂 UI，系統同時把內容語言切到 `en` ⇒ 商家在**英文版商品**的標題欄看到空白（尚未翻譯），以為資料掉了，於是把中文標題打進去 ⇒ **英文版商品的標題是中文**，而中文版沒有變。這個錯誤只有在前台切語言時才會被發現。

**為什麼內容語言要進 URL**：可分享（「你去改一下這個商品的英文版」貼連結就行）、可回退、重新整理不丟失。形態沿用 52 號 P0-18「路由進 URL」的既有裁定。

### E.2 內容語言切換器的規格

- **位置**：商品編輯頁的標題列，與狀態（四態，13 §F1.2）選單同一列。本輪原型已把該頁做到 1:1（`docs/design/chilllove-admin-v2.html` 的 `productPage()`）——**本檔只寫規格，不改原型**。
- **顯示**：`endonym`（`繁體中文`／`简体中文`／`English`）＋ 該語言的進度徽章（讀 `translation_status`，鐵律 7）。
- **來源語言以外的語言：欄位形態改變**——每個可翻欄位變成上下兩段：**上＝來源語言原文（唯讀，可一鍵複製）**，下＝譯文輸入。這是 29 §2.4 翻譯後台「逐 key 雙欄」形態在**單資源頁**的版本，兩者共用同一個元件。
- **切到未啟用語言**：不可能（值域即已啟用語言）。切到未發布語言：允許編輯，並顯示「此語言尚未發布，僅預覽連結可見」（29 §1.2）。
- **建立新商品**：🔴 **一律在 source locale 下建立**，內容語言切換器在建立態**停用**（base row 還不存在，沒有東西可翻）。

### E.3 🔴 非來源語言下必須唯讀的欄位（最貴的誤操作在這裡）

編輯 `en` 版商品時，下列欄位**必須唯讀並附說明「此欄位不隨語言變動」**：

```
價格 / 比較價格 / 每品項成本 / 利潤率        ← 金額（鐵律 3、§B.3-5）
SKU / 條碼 / 追蹤庫存 / 各地點庫存數          ← 識別碼與庫存（§B.3-1）
商品狀態 / 銷售管道發布 / 變體級發布          ← 全語言共用的可見性（13 §F1.2）
handle                                        ← §D.3（僅在來源語言頁可編輯）
標籤                                          ← 集合運算的鍵（§B.3-2）
分類法類別 / 選項的「數量」與順序              ← 結構
```

**為什麼這是最貴的一條**：不做唯讀，商家會在 `en` 頁面把價格從 1,480 改成 148（以為只影響英文版），而**實際上改的是唯一的那筆 `product_variants.price_cents`**（63 §B.3：商品層沒有價格）。這不是顯示問題，是**真的收錯錢**。UI 上必須**灰化＋tooltip**（形態同 `notification.non_toggleable_ui: disabled_with_tooltip`），不是隱藏——隱藏會讓商家以為英文版沒有價格。

### E.4 翻譯進度與缺漏的可視化

| 位置 | 顯示什麼 | 資料來源 |
|---|---|---|
| 商品／系列／頁面**列表** | 「翻譯」欄：每語言一個徽章（`完整`／`缺 N`／`過期 N`／`機翻未覆核 N`） | `translation_status`（鐵律 7） |
| 商品編輯頁 | 內容語言切換器上的進度環 ＋ 未翻欄位的行內標記 | 同上 |
| **翻譯後台**（29 §2.4 的資源樹＋雙欄表） | 側欄每個資源型別的 `已翻/總數`；主體逐 key 雙欄；`outdated` 列標示（分 major／minor 兩種樣式） | 同上 |
| **內容健康頁** | 全店百分比 ＋ **按實際流量加權的缺漏排行**（`i18n.fallback_hit` 遙測，§C.4(d)） | 遙測 ＋ 物化表 |
| SEO 健康頁 | 「自動代碼 handle 佔比」（§D.2(a)） | `resource_handles` |

🔴 **「缺 N」的 N 必須與翻譯後台的分母一致**（鐵律 7）。可翻欄位數會隨 metafield 定義變動，所以分母是**該時點計算並物化的**（`translation_status.translatable_fields`），不是硬編的常數。

### E.5 批次翻譯

**(a) 機器翻譯是可插拔 provider，且與兩種 pack 都正交**

```
語言 pack   = 資料（§A.3）
jurisdiction pack = 法律能力（56）
MT provider = 服務        ← 第三種，不要塞進前兩者
```
`i18n.machine_translation.provider_pluggable: true`；未設定 provider 時整個功能**不出現**（不是出現後報錯）。呼叫一律在**背景 job**（鐵律 5：transaction 內禁外部 IO），逐資源逐欄位，可斷點續跑。

**(b) MT 寫入紀律**（承 62 §F.1 `alt_source` ／ §H.6-1 `content_source` 的同一條）

```
value_source = 'machine'  ∧  review_required = true    ← 一律，無例外
```
- **MT 結果在前台照常渲染**（`i18n.machine_translation.publish_default: visible`）。理由：不渲染就等於整個批次沒有效果，商家會改用外部工具貼進來——那樣連 `value_source` 都沒有了。可由商家切成 `hidden`（未覆核的機翻不對外，仍走 fallback）。
- 後台常駐「N 筆機翻未覆核」入口；覆核 ＝ 人編輯過或按「確認無誤」⇒ `value_source='human'`。
- 🔴 **一次生成量的摩擦**：`i18n.machine_translation.max_resources_per_batch` ＋ 超過門檻的批次需二次確認並顯示警告——形態與理由同 62 §H.6-1（大量自動內容對 Google 是 scaled content abuse，可能整站受罰）。
- ⚠ 29 §2.4 記載官方機翻「限 2 種語言」（仿官方限額）。⚠ 該限額的現況與依據未在本輪覆核 ⇒ **V-169**；我方以 `limits` 鍵表達，**不寫死**。

**(c) 繁簡轉換是**獨立工具**，不是 MT，也不是 fallback**

```
Script::Convert(from: zh-Hant, to: zh-Hans)   ⇒ value_source = 'script_conversion', review_required = true
```
- **確定性**（查表，不是模型），所以它與設計原則 3 相容——但它**仍然要寫成真實譯文列**，不得做成渲染期轉換（§A.4）。
- 🔴 **兩個方向的品質不對稱，UI 必須說明**：繁→簡接近無損；**簡→繁是一對多**（`发`→`發`／`髮`、`干`→`干`／`乾`／`幹`、`后`→`后`／`後`），必然需要人工覆核。因此 `zh-Hans → zh-Hant` 的批次**預設把整批標為 `review_required` 並在完成報告中列出含歧義字的筆數**。
- 🔴 **它不做詞彙在地化**：`软件/軟體`、`视频/影片`、`鼠标/滑鼠` 是**用詞**不是字形，查表不會處理。UI 文案必須寫「這是字形轉換，不是翻譯」——否則商家會以為簡體版已經可以上線。

### E.6 匯入匯出：翻譯是**第三套**；🔴 空白＝不動作，覆寫走**顯式旗標**

<!-- 🔴🔴 **本節是二次修正（2026-08-12 同日兩次），沿革必須完整讀完再動手。**

     ① 原始設計（本檔初版）：`blank_means_unchanged: true`（空白＝不變更）。
        原節標題：「### E.6 匯入匯出：翻譯是**第三套**，且與商品 CSV 的空白語義**相反**」
        原理由 3（逐字保留）：
          「3. 🔴 **空白語義相反，而且相反的方向是資料毀損**：商品 CSV 的「以相同 handle 覆寫商品」
              語義是「**空白儲存格會把既有資料洗掉**」（61 §6.1）。同樣的語義套到翻譯上 ＝
              譯者交回一份只填了 20% 的檔案，其餘 80% 的既有譯文全被清空。」
        原 CSV 契約行：「🔴 空白 = 不變更（與商品 CSV 相反）。清空譯文必須明確寫 __CLEAR__」

     ② 68 號 §B-3 翻面為 `false`（空白＝清空），並把本節改寫成「三件套」。
        依據：**Matrixify（第三方 app，`press` 級）** 的翻譯匯入語義；
        並研判「Shopify **原生**能力薄弱或不存在」（68 的 V-182）。
        68 當時的節標題：「### E.6 匯入匯出：翻譯是**第三套**；空白語義與商品 CSV **同向**」

     ③ 🔴 **69 號 §V-182 推翻了 ② 的前提 ⇒ 本節改回「空白＝不動作」，並改成 overwrite 旗標形態。**
        69 號查到 Shopify **有完整的原生翻譯 CSV 匯出／匯入**——**不在 Translate & Adapt app 裡**，
        而在 **Settings → Languages**（`help`；另有 `staff` 論壇回覆與 `vendor` 側獨立佐證欄位表）。
        **這就是 68 號找不到它的原因：68 號找對了功能、找錯了地方。**
        本尊的模型是：8 欄 ＋ `Status` 三值 ＋ 匯入時一個**「覆寫既有翻譯」勾選框**。
        🔴 **本尊根本沒有對「空白」賦予刪除語義——它把這個決定做成使用者的一次明示動作。**
        ⇒ 「全部跟隨 Shopify」的字面結論**不是翻面，是換成顯式旗標**。

     🔴 **為什麼繞了這一圈（這一段比結論本身更有價值，不得刪）**：
        68 與 69 是**同時**進行的兩份查證。68 拿不到原生行為，就以生態事實標準（`press`）當依據，
        **翻掉了一條已生效的資料安全預設**；69 換一批來源後在**官方 help**（`help`）找到了原生行為。
        ⇒ **`press` 級來源足以「登記為未知」，不足以「翻面一條資料安全預設」。**
        來源分級（§0.3）不是學術潔癖——這次的成本就是一條規格改了兩次、三份文件要對齊。

     🔴 **防回退**：任何人看到 68 §B-3 寫著「要改成 false」而本節寫著 `true`，
        **不要照 68 改**。68 的該條已被 69 以更高等級的來源推翻；兩份 research 檔都不會再改
        （docs/research/* 是證據，不是結論）。要動這條，必須先推翻 69 §V-182 的 `help` 級出處。

     ✅ **68 號那一輪新增的東西，本次修正原樣保留**（它們解決的是真問題，與空白語義正交）：
        缺席語義三鍵（absent_row／absent_column／absent_vs_blank_distinguished_by_header）
        與匯入預覽四鍵（preview_required／preview_*_count_separate／*_ratio_confirm_threshold／
        *_writes_audit_trail）。**要換掉的只有「空白＝刪除」這個語義本身。** 理由見 (a) 末段。 -->

61 §6.1／§6.2 已確認商品 CSV 與庫存 CSV 是兩套（63 §L-8）。**翻譯必須是第三套**，理由四條（第 4 條是本輪新增的，它在 68 那一輪一度被刪掉）：

1. **鍵不同**：商品 CSV 的鍵是 `handle` ＋ 變體行；翻譯的鍵是 `(resource_type, resource_id, locale, field_key, market)`。硬塞進商品 CSV 就要為每個語言加一組欄位（3 語 × 6 欄 = 18 欄），加第 4 個語言時整張表要改。
2. **範圍不同**：翻譯涵蓋頁面、部落格、選單、主題字串、通知範本、政策——這些**根本不在商品 CSV 裡**。
3. **生命週期不同**：翻譯檔會**出境**（交給外部譯者／TMS）再回來，因此需要 `source_digest` 這種商品 CSV 沒有的東西（見下）。
4. 🔴 **空白語義不同，而且這一條現在有官方依據**（69 §V-182）：商品 CSV 的空白＝洗掉（`help`，61 §6.1）；**翻譯 CSV 的本尊不用空白表達刪除，改用一個顯式的覆寫勾選框**。⇒ 兩套 CSV 的破壞性語義**本來就不同源**，這不是我方的不一致。

#### (a) 🔴 空白＝不動作；「覆寫」是使用者的一次明示動作

**跟隨本尊的四件事**（每一項都對應到 69 §V-182 已確認的行為）：

| # | 機制 | 鍵 | 為什麼是這一條 |
|---|---|---|---|
| ① | **儲存格空白 ＝ 本列本欄不做任何事**（**不**解讀成刪除） | `i18n.import.blank_means_unchanged: true`<!-- 二次修正：原 true → 68 改 false → 69 改回 true --> | 本尊沒有對空白賦予任何刪除語義。**且刪除是不可逆操作，不該由「儲存格是空的」這種易誤觸的狀態觸發**——譯者交回一份只填 20% 的檔案是**常態**，不是異常 |
| ② | **`overwrite_existing` 顯式旗標**，預設 **false**（只補新的、不動既有） | `i18n.import.overwrite_existing_default: false` / `overwrite_scope` | 這是本尊模型的核心：**它不猜，它問**。預設不勾＝保守失效，與我方 56／58／65 三處「未宣告 ≠ 預設」同一條哲學 |
| ③ | **清空必須是另一個明示動作** | `i18n.import.explicit_clear_token: "__CLEAR__"`；🔴 `explicit_clear_token_is_alias_of_blank` ⇒ **`false`** | `__CLEAR__` **回到唯一清空手段**的位置（68 那一輪把它降級成「空白的同義寫法」）。<!-- 🔴 這兩鍵是同一語義的兩面，必須一起改：若只把 blank_means_unchanged 改回 false 而漏了這一鍵，語義仍然自洽（兩者都清空）⇒ **漏改不會被任何測試抓到** --> |
| ④ | **匯出欄位對齊本尊 8 欄，`Status` 三值落地** | `i18n.export.columns` / `status_values: [translated, outdated, untranslated]` / `status_is_export_only: true` | `Outdated` 在本尊是**匯出檔的一等公民欄位** ⇒ 它同時回答了 §C.5 過期偵測「要輸出到哪裡」這個問題。⚠ V-201：本尊匯入時是否讀 `Status` 未知 ⇒ 我方**純輸出** |

**「不變更」的四種表達（本節的核心契約）**：

```
列缺席                 ⇒ 該 (resource, locale, field) 完全不處理
欄位缺席               ⇒ 該欄位對檔案內所有列都不處理
儲存格空白             ⇒ 🔴 本列本欄不做任何事（69 §V-182；**不是**刪除）
有值 ∧ 未勾 overwrite  ⇒ 該譯文已存在時保持原值（只補新的）
```

🔴 **缺席與空白仍然必須在解析層就分開**（`i18n.import.absent_vs_blank_distinguished_by_header: true`）——**這條在本次修正後不但沒有失效，反而更關鍵**：

- **技術理由不變**：CSV 讀進來的「沒有這一欄」與「這一欄是空字串」在多數 CSV 函式庫裡都會塌成 `nil`。匯入器**必須以表頭判定欄位是否存在，不以值判定**；這一行寫錯，測試很可能全綠（因為測試檔通常欄位齊全）。
- 🔴 **新的理由**：**`overwrite_existing` 的作用範圍就是靠表頭界定的**（`overwrite_scope: non_blank_cells_in_present_columns`）。若解析層分不出缺席與空白，`overwrite: true` 會把「檔案裡根本沒有的欄位」也算進範圍——**一份只想改標題的檔案會把描述一起洗掉**。那正是 68 那一輪擔心的誤刪風險換了個入口回來。
- ⇒ **68 號新增的缺席語義三鍵一個都不刪。** 它們當時是為了讓「不變更」有辦法表達；現在是為了讓「覆寫」有辦法收斂範圍。**同樣三個鍵，換了一個更硬的理由。**

**匯入預覽四鍵同樣全部保留，但計數對象改了**（`preview_required` / `preview_clear_count_separate` / `preview_overwrite_count_separate` / `clear_ratio_confirm_threshold` / `overwrite_ratio_confirm_threshold` / `clear_writes_audit_trail` / `overwrite_writes_audit_trail`）：

| 破壞性來源 | 68 那一輪 | 本次修正後 |
|---|---|---|
| 空白儲存格 | 🔴 清空 ⇒ 要計數 | ✅ 不動作 ⇒ 不再是破壞性來源 |
| `__CLEAR__` | 同義寫法 | 🔴 **唯一的明示清空** ⇒ 要計數 |
| `overwrite_existing: true` | 不存在 | 🔴 **新的破壞性來源** ⇒ **要單獨計數** |

🔴 **`overwrite` 需要預覽數字的理由與清空一模一樣**：它雖然是使用者的明示動作，但**爆炸半徑仍然是整份檔案**——勾一個框而不知道會蓋掉多少既有譯文，與誤刪一樣不可接受。**「明示動作」只解決了『是不是故意的』，沒有解決『知不知道有多大』。**

#### (b) 檔案契約

```
翻譯 CSV（i18n.export.format: csv）
  欄位（對齊本尊 8 欄，69 §V-182；我方另加 source_digest）：
        resource_type(≈Type), resource_gid(≈Identification), field_key(≈Field), locale,
        market_handle(≈Market，選填), status(≈Status), source_text(≈Default content，唯讀參考),
        translated_text(≈Translated content), source_digest(🔴 我方獨有)
  status ∈ {translated, outdated, untranslated}（本尊三值）；**純輸出**，匯入時忽略 ⇒ ⚠ V-201
  🔴 translated_text 空白 = **本列不做任何事**（69 §V-182；**不是**清空）
     清空譯文 ＝ 明確寫 __CLEAR__（i18n.import.explicit_clear_token）——唯一手段
     覆寫既有譯文 ＝ 匯入時勾選 overwrite_existing（預設不勾）
  🔴 匯入必比對 source_digest：
       相符   ⇒ 正常寫入，outdated=false
       不相符 ⇒ **仍然寫入**（譯者是照當時原文翻的，內容多半可用）
                但 outdated=true, severity 依 §C.5(b) 計算, review_required=true
                並在匯入報告單列出。**不得靜默當成最新**
       缺欄   ⇒ 整檔拒絕（沒有 digest 就無法安全回寫）
  🔴 清空**與覆寫**都寫稽核軌（clear_writes_audit_trail / overwrite_writes_audit_trail）：
     誰、何時、哪一次匯入、舊值是什麼。沒有它，「譯者交錯檔案」在事後完全無法還原
  分檔：按 (locale, resource_type) 分檔；單檔上限沿用 csv.product_max_upload_mb(15MB)
  匯出走**非同步 ＋ 通知／email 交付**（i18n.export.async_delivery，跟隨本尊；亦符合我方 outbox 形態）
```

✅ **舊格式檔案不需要遷移**：本次修正把空白的語義**改回**原始設計（不變更），而 68 那一輪的翻面**只落在規格與 limits 鍵上、尚未實作**（M-8 登記的下游回寫也還沒發生）。⇒ **沒有任何已存在的商家檔案曾在「空白＝清空」的語義下被寫出來。**
<!-- 🔴 68 那一輪在此處原有一段警告：「⚠ 舊格式檔案的語義已經反轉……必須靠 ③ 的預覽數字讓商家
     在按下確認前看見」。本次修正後那段**不再適用**（語義回到原始值），故移除；
     但保留這行說明，讓下一個人知道那段警告是被「二次修正」消掉的，不是被漏掉的。 -->

- **匯出必含 `source_text`**（唯讀參考欄）：沒有原文的翻譯檔對譯者不可用。
- **XLIFF 2.1 匯出**列為 P2〔ours〕：TMS 工作流的產業標準；⚠ 我方是否需要、以及 Shopify 是否提供對應格式**未查證 ⇒ V-163**。首發只做 CSV。
- 匯入一律**逐行獨立 transaction ＋ 逐行結果報告**（沿用 13 §F6.1 的既有形態）。

---

## F. 前台（storefront）多語言

### F.1 URL 結構，以及餵給 62 §I 的「語言維度」

**(a) 兩個字串函式，語義不同，🔴 不得互相借用**

```
url_prefix(web_presence, locale)   → 路由用。本檔定義（下表）
hreflang_code(market, locale)      → 標註用。**62 §I.2 已定義，本檔不重寫**
```
兩者由**同一對 (market, locale)** 推導，字面上常常長得很像（`/zh-hant-sg` vs `zh-Hant-SG`），但規則來源不同：前者受路由與可讀性約束，後者受 Google 的碼合法性約束（62 §I.4 的白名單、禁 `EU`／`UK`／`es-419`）。**借用會在第一個多國市場上出錯**：多國市場的 hreflang 是語言碼（`en`），但它的 URL 前綴仍需要能區分市場。

**(b) `url_prefix` 的規則**（承 29 §1.2／§2.5 的既有約束，本檔補 script subtag 的處置）

| 情境 | 前綴 | 依據 |
|---|---|---|
| primary market ＋ shop 預設語言 | **（無前綴）** | 29 §2.5 |
| primary market ＋ 其他語言 | `/{locale_slug}` — `/en`、`/zh-hans` | 29 §2.5「primary 其他語言 → `/{lang}`」；script subtag 的形態見下 |
| 次級市場（子資料夾） | `/{locale_slug}-{subfolder_suffix}` — `/zh-hant-sg` | 29 §1.2「語言-only 子資料夾僅限 primary market；次級市場一律語言-國家」 |
| 子網域／獨立網域市場 | defaultLocale 在根、alternate 在 `/{locale_slug}` | 29 §2.5 |

```
locale_slug = BCP-47 標籤全小寫，連字號保留    zh-Hant → "zh-hant"    en → "en"
```
> ⚠ **V-162**：Shopify 對帶 script subtag 的語言實際使用什麼子資料夾字串（`/zh-tw`？`/zh-hant`？）本輪未查證。我方採 `/zh-hant`，因為 ①`zh-tw` 會把**地區碼**塞進**語言**位置，與 62 §I.4「不得借 `zh-TW` 表示繁體」的既有定案直接矛盾；②同一個 shop 若同時有 HK 與 TW 市場，`/zh-tw` 會與市場後綴撞義。

**(c) 唯一性與保留字**（路由層 constraint，形態同 29 §9-5 的「語言-only 前綴僅限主市場」寫死規則）

```
UNIQUE (shop_id, domain_id, url_prefix)          -- 兩個 (market, locale) 不得產生同一前綴
url_prefix ∉ handle.reserved_first_segments      -- products / collections / pages / blogs / cart /
                                                 -- checkout / account / search / apps / .well-known / …
```

**(d) 餵給 62 §I.1 的東西——本檔只提供這三樣**

```
1. resolved_web_presences(m) 的每個 wp 上的 locale 集合  ⇒ 62 §I.1 的 `wp.locales`
   來源：market_web_presence_locales（29 §1.4），且**沿 lineage 累加**（62 §I.3(a) 已警告過）
2. absolute_url(resource, wp, loc) = origin(wp) + url_prefix(wp, loc) + canonical_path(resource)
   canonical_path = "/products/" + handle   ← 🔴 handle 不含語言（§D.3），所以這是純拼接
3. 只有 published = true 的語言進矩陣
   🔴 未發布語言的 URL 不進 hreflang、不進 sitemap、且 **404**（29 §1.2「自市場移除語言 → 該語言 URL 立即 404」）
      ——因為 62 §0.2 原則 4 要求矩陣內每個 URL 對任何客戶端回 200
```
**本檔不重寫 `hreflang_set()`、不重寫碼粒度規則、不重寫 `dedupe_codes`。** 語言的新增／發布／取消發布必須掛上 62 §I.3(b) **既有的**失效管線（market conditions 變更 ⇒ 矩陣與 sitemap 失效，去抖 5 分鐘）——本檔只補一句：**該管線的觸發條件要加上 `shop_locales` 與 `market_web_presence_locales` 的變更**，否則商家發布了新語言，hreflang 會停在舊值好幾天（同 62 §I.3(b) 已警告的病根）。

### F.2 語言偵測與切換

| 項 | 規則 | 依據 |
|---|---|---|
| 自動重導（**語言維度**） | 🔴 **不做**（`i18n.storefront.auto_redirect_on_language: false`）。<!-- 依 68 號 §C-3 修正理由（2026-08-12）。原文：「🔴 **不做**（地區自動重導預設關閉已由 62 §K.2 定案，Google 明文建議避免）。**語言維度同樣不自動重導**」🔴 **值不變，理由必須換**：原文把「語言不重導」掛在「地區也不重導」上，而**地區的預設已翻成啟用**（62 §K.2）。不改這行，下一個人會照著括號裡那句話把語言也一起翻開——那是 Shopify **明文預設停用**的東西。 -->✅ **這一條本來就與 Shopify 一致**：本尊**預設停用自動語言偵測**（`help`，68 §C-3），只有**地區**重導預設啟用。**兩個預設值方向相反，不得連動。** | 62 §K.2（地區維度已翻為預設啟用）＋ `help` |
| `Accept-Language` | **只用來決定「要不要顯示建議橫幅」與切換器的預設高亮**，🔴 **不得改變同一 URL 的輸出內容** | 本檔〔ours〕 |
| Cookie | 同上：只影響建議橫幅是否再顯示。🔴 **不得**讓 cookie 決定頁面語言 | 本檔〔ours〕 |
| 切換器 | 必須是**真實 `<a href>`**，指向目標語言的完整 URL | 62 §K.2 已定（爬蟲發現其他版本的路徑之一） |
| `Vary` | 🔴 頁面內容不隨 `Accept-Language` 變 ⇒ **不得輸出 `Vary: Accept-Language`**。輸出它等於把快取切成 N 份卻沒有任何內容差異（§G） | 本檔〔ours〕 |
| 建議橫幅 | 必須是 **locale-invariant 片段**（client-side 渲染或獨立快取），否則它會把 `Accept-Language` 重新拉回快取鍵 | 本檔〔ours〕 |
| `{% form 'localization' %}` | 兩個欄位名（`country_code`／`language_code`）都要收 | 25 號坑 #4、29 §4 |
| 切國家導致語言不支援 | 落到該市場的 `defaultLocale` | 29 §4 |

🔴 **「同一 URL 對不同人回不同語言」是本節要防的唯一事故**：它會讓爬蟲索引到隨機語言版本、讓 hreflang 的自指與雙向性（62 §I.1 不變量 1／2）失去意義、也讓 62 §0.2 原則 4 的可達性不變量無法驗證。**語言只由 URL 決定**，這是可測的（`SF-2`：對同一 URL 送三種不同的 `Accept-Language`，回應主體必須逐位元組相同）。

### F.3 Liquid 端：主題靜態字串與內容翻譯是**兩回事**，兩者都要有

**(a) 三層解析（承 29 §2.3，本檔補第三層與 fallback 的粒度）**

```
{{ 'products.product.add_to_cart' | t }}
  ① 商家覆寫      translations[THEME_LOCALE_CONTENT, theme_file_id, locale, key]
  ② 主題檔        locales/{locale}.json  →  locales/{fallback_chain…}.json  →  locales/*.default.json
  ③ 平台預設      平台自帶的最小字串集（只有主題完全沒有該 key 時）
  未命中 ⇒ dev/預覽：顯示 `translation missing: {locale}.{key}` ＋ 記遙測
           production：走 ② 的 default 檔字串 ＋ 記遙測。🔴 **絕不輸出 key 名或空字串給買家**
```

**(b) 66 §A.9 的三個坑必須接住**（`fixture`，Ella 7.2.0 實證）

1. **locale 檔是 JSONC 不是 JSON**（`/* */` 區塊註解、CRLF、BOM、尾隨逗號）⇒ 標準 parser 直接拋錯。**tolerant parser 是硬需求**，且要涵蓋 `locales/`（66 §C.1 G-8 指出 27 §7-4 的寬容解析只涵蓋 schema/settings JSON）。
2. **前台字串（`xx.json`，31 個）與編輯器字串（`xx.schema.json`，24 個）是兩套**：`| t` 只查前者，schema 的 `"label": "t:…"` 只查後者。**混用是靜默錯誤**（顯示原始 key）。
3. **兩套語言清單不對稱**（Ella：`ar`／`hi` 只有 schema 沒有前台；`bg`／`el`／`fi`… 只有前台沒有 schema）⇒ 🔴 **fallback 必須逐檔獨立解析**，不能有「本主題支援語言 X」這個單一布林。

**(c) 內容翻譯走 drops，不走 `t`**：`product.title` 由 `ProductDrop` 在建構時以當前 locale 解析（§C.4 的鏈），**在 preload 階段一次批次載入該資源的全部譯文**（63 §D.1 的 N+1 防線：每頁 SQL ≤15 條——翻譯載入必須是**一次** `WHERE (resource_type, resource_id) IN (…) AND locale IN (鏈)`，不是每欄一次）。

**(d) 主題若硬編字串**：66 §A.7 實證 Ella 有硬編英文（`Features` 分類名，未走 `t:`）⇒ **解析器必須「以 `t:` 開頭才查表，否則原樣顯示」**（66 §A.7 的既有結論），不得無條件查表。主題匯入的 degradation report 加一節：「本主題有 N 處硬編文字，切換語言時不會改變」。

### F.4 `routes` drop 與連結前綴

- `routes` drop 與 `window.Shopify.routes.root` **必須吐帶前綴的值**（29 §2.5 已點名為 Liquid 相容層銜接點）。
- 🔴 **主題產生的所有內部連結必須經 `routes`／`url_for` 過前綴**。硬編 `href="/products/…"` 的主題在切語言後會把買家踢回預設語言，而且**每一個連結都會**——這是切語言功能「看起來壞了」的最常見形態。
- 對策：theme-check 自訂 lint 規則（形態同 62 §F.2 的 `<h1>` 唯一性 lint，掛在 31 號的 lint 管線）——`href` 以 `/` 開頭且不經 `routes` 者 ⇒ warning，並列入匯入 degradation report。**不擋渲染**（第三方主題不可控，25 §0）。

### F.5 結帳與通知的語言：**鎖定與快照**

| 面 | 規則 | 依據／理由 |
|---|---|---|
| 結帳語言 | ＝ **進入結帳時**的 web presence locale，🔴 **結帳中不可換語言** | 對稱於 29 §5「結帳鎖定進入時的 presentment currency」——同一條紀律。結帳中換語言會讓已計算的稅務／運費文案與金額解釋不一致 |
| 訂單快照 | 🔴 訂單必須存 `locale_snapshot`（與 56 §0.2「訂單成立即快照法域碼」同一條紀律） | 顧客日後改語言偏好，**不應改變已成立訂單的頁面與憑證語言** |
| 通知信語言 | `customers.locale` → 訂單的 `locale_snapshot` → shop source locale | 原型 `chilllove-admin-v2.html:5520` 已有顧客「語言」欄位（「決定通知信與帳號頁語言」）。⚠ 官方的優先序未查證 ⇒ **V-170** |
| 結帳文案兩層 | 平台 UI 字串（平台 bundle）＋ 商家可覆寫文案（租戶 `translations`） | §E.1 的同一條分界 |
| 顧客帳號頁 | 同通知信的解析鏈 | |

---

## G. 與快取的交互（承 63 §D，🔴 多語言讓 63 §D.3 的鍵再乘一次）

### G.1 倍數是多少（先把問題量化）

63 §D.3 的頁級 fragment key：

```
[shop_id, theme.version, template.updated_at, locale, market_id, currency, page_kind, resource_stamp]
                                              ~~~~~~  ~~~~~~~~~  ~~~~~~~~
```
62 §G 風險 1 已點名「快取鍵爆炸」是多市場與 CWV 的真接縫。**多語言讓它再乘一次**：

```
片段數 ≈ 資源數 × |published locales| × |active markets| × |presentment currencies|
HK 單市場三語首發：×3
HK + TW + SG 三市場、各兩語、各自幣別：×6（locale×market 的實際組合，不是笛卡兒積——語言是市場的子集）
```
🔴 **重要的緩和事實**：`locale` 與 `market` **不是**獨立相乘的——語言集合是市場的子集（§A.1），實際組合數 ＝ `Σ over markets |wp.locales|`，通常遠小於 `|locales| × |markets|`。快取鍵的維度計算必須用**實際存在的 (market, locale) 對**枚舉，不得用笛卡兒積預熱（那會生出大量永不命中的 entry）。

### G.2 對策：**維度降維 ＋ fail-closed 偵測**（本檔對 63 §D.3 的修正）

63 §D.3 把 `locale` **無條件**放進頁級 key。本檔改為**依實際依賴決定**：

```
render 前：context.registers[:touched_dimensions] = Set.new
drop 讀到「經 §C.4 解析的翻譯欄位」 ⇒ touched_dimensions << :locale
drop 讀到 money / 幣別 / 市場政策    ⇒ touched_dimensions << :market
drop 讀到 volatile 欄位（63 §D.5）   ⇒ render_flags << :volatile
render 後：fragment_key = base_key + 實際 touched 的維度
```

這是把 63 §D.3 **既有的** `touched_sources` 自檢機制（「drop 每讀一張表就註冊，渲染後斷言 `touched_sources ⊆ cache_stamp_sources`」）從**表**擴充到**維度**——同一個機制、同一個註冊點、同一個斷言形態。

**🔴 三條 fail-closed 紀律**（降維漏偵測 ＝ 跨語言污染，比多存幾份嚴重得多）：

1. **預設進入所有維度**：只有「本次渲染**完全沒有** touch 任何 locale 來源」才允許把 `locale` 從 key 移除。任何不確定一律保留維度。
2. **靜態字串也算 locale 依賴**：`{{ '…' | t }}` 命中主題 locale 檔同樣註冊 `:locale`。這一條容易漏，因為它不經過 `translations` 表。
3. **雙渲染驗證**（dev／staging，`i18n.cache.dimension_probe_enabled`）：同一 section digest 以兩個不同 locale 各渲染一次，**輸出逐位元組相同**才允許把它標記為 locale-invariant，結果存 `section_dimension_profile(shop_id, theme_version, section_digest, dimensions)`。生產環境只讀這張表，不現場判定。

**降維真正救得到什麼**：版面骨架、圖片區、評論星等、地圖、以及**完全由設定值驅動且設定值無文字**的 section。救不到商品卡與任何含文案的區塊——這是誠實的預期，不要對降維抱過高期待。

### G.3 `cache_stamp` 新增的來源（承 63 §D.3 的組成式）

```
cache_stamp = MAX(
  …63 §D.3 既有七項…,
  translations_updated_at(shop_id, resource_type, resource_id, locale),   -- 🔴 資源級，不是全店級
  shop_locales_version(shop_id)                                           -- 全店級（見下）
)
```

| 新增來源 | 粒度 | 為什麼是這個粒度 |
|---|---|---|
| `translations_updated_at` | **資源 × 語言** | 改一個商品的英文標題**不得**清掉全店快取。以 `(shop_id, resource_type, resource_id, locale)` 為鍵物化（可與 `translation_status` 同一張表共用一列的 `updated_at`） |
| `shop_locales_version` | **全店** | 新增／發布／取消發布語言、改來源語言 ⇒ 全店失效。這些是**罕見動作**，粗粒度可接受；反之若做細粒度，「取消發布某語言後該語言頁面仍被快取回應」就是一個對外可見的錯誤 |
| 主題 locale 檔變更 | 沿用 `theme_files.updated_at`（63 §D.3 的 AST cache 層已涵蓋） | 不新增來源 |

🔴 **`cache_stamp` 的組成必須覆蓋該 drop 實際讀過的每一張表**（63 §D.3 紀律 1）——`translations` 是新的一張表，**必須加入 `limits.catalog_flow.cache_stamp_sources`**，否則 63 §D.3 紀律 2 的自檢斷言會在第一次渲染翻譯欄位時就 raise（這是好事：它證明機制有效）。

### G.4 誠實的代價

- 63 §D.5 已記錄：Ella 的商品卡讀 `inventory_quantity` ⇒ 集合頁卡片 fragment **全部退化成 60 秒 TTL**，14 號「匿名流量命中 >90%」在 Ella 下達不到。**多語言讓這些 60 秒 TTL 的片段再乘上語言數**——同一張卡在三語下是三份、各自 60 秒。
- **我方選擇正確性優先**（同 63 §D.5 的既有取捨），對策是 §G.2 的降維（救得到版面與圖片，救不到卡片）＋ 把代價做成可觀測：
  - 遙測 `i18n.cache_key_cardinality{shop, page_kind, dimensions}`——**把「乘了幾倍」變成數字，不要用猜的**。
  - 預熱只針對 `published = true` 且**有實際流量**的 (market, locale) 對；未發布語言不進快取也不對外服務。
  - `i18n.cache.max_locale_dimensions_warn`：單一 shop 參與快取鍵的語言數超過此值即告警（不是擋——擋住商家新增語言違反裁定 e）。

---

## H. 鐵律交叉

### H.1 金額：語言不影響金額的任何一個部分（鐵律 10 ＋ 裁定二）

```
🔴 金額字串的符號、符號位置、小數位數、千分位分組、小數點字元
   —— 五者全部由 **market locale**（`jurisdictions.<code>.currency_format`）決定，**不隨內容語言變**。
```

- 英文版的香港商店顯示 `HK$1,480.00`；繁中版顯示 `HK$1,480.00`。**兩者逐字元相同。**
- 依據：鐵律 10（「實際符號與小數位由市場的 locale 決定，不得硬編」）＋ 裁定二（顯示恆兩位小數）＋ 原型 `chilllove-admin-v2.html` 的 `MARKET_LOCALES` 表（符號／位置／小數位／千分位分組**全部**是市場資料）。本檔**不改變**這個既有實作，只補上「語言維度不參與」這一句。
- 🔴 **數字系統固定拉丁數字**（`i18n.numbering_system: latn`），不隨語言變。理由：金額字串會進 JSON-LD／feed／對帳／PSP 對照，`١٬٤٨٠٫٠٠` 與 `1,480.00` 是同一個數的兩種字串 ⇒ 違反鐵律 7；且 62 §A.4 已定 JSON-LD **不套用任何 locale 格式化**。
- **`money` filter 的簽名因此不吃 content locale**——只吃 `RequestContext.market`。這是可測的（`I18N-9`：同一 variant 在三個 locale 下渲染，`money` 輸出必須逐位元組相同）。

### H.2 數字與日期的分界表（鐵律 3／65 號：翻譯不碰金額，但數字與日期要跟 locale）

**分界的判準只有一個**：這個字串會不會出現在**對帳／結構化資料／對外系統**？

| 類別 | 由誰決定 | 例（`en` vs `zh-Hant`，同一 HK 市場） | 理由 |
|---|---|---|---|
| **金額**（符號／位數／分組／小數點） | **market locale** | `HK$1,480.00` ／ `HK$1,480.00` | 對帳字串（§H.1） |
| **日期**（格式、月份名、曆法） | **content locale** | `12 August 2026` ／ `2026年8月12日` | 純閱讀字串 |
| **時間**（12/24 制） | content locale | `3:00 pm` ／ `下午 3:00` | 同上 |
| **時區** | 🔴 **shop／market 設定，不隨語言** | 兩者皆 `HKT` | 時區是事實不是呈現 |
| **非金額數字**（重量、尺寸、數量、百分比） | content locale | `1,480 g` ／ `1,480 克` | 純閱讀字串 |
| **序數／複數** | content locale（`platform_locales.plural_rule`） | `1 item / 2 items` ／ `1 件 / 2 件` | 語言規則 |
| **排序** | content locale（`platform_locales.collation`，§C.7） | — | 語言規則 |
| 🔴 **JSON-LD／feed／API／匯出 CSV／webhook payload 內的一切數字與日期** | **locale-invariant** | ISO 8601 日期、`.` 小數點、無千分位 | 62 §A.4 已定；機器讀的字串沒有 locale |

**必須誠實記錄的視覺不一致**：同一張商品卡上可能同時出現 `HK$1,480.00`（market 格式）與 `1 480 g`（若內容語言的數字分組用空白）。**這看起來不一致，但它是刻意的**——統一的唯一方式是把金額格式交給語言，而那扇門的另一邊就是「英文版顯示 US$」。

### H.3 鐵律 9（不抄 Shopify 文案）在翻譯上的形態

- 平台自帶的 UI 字串（admin、結帳、預設主題、通知範本預設內容）**一律自寫**，不得從 Shopify 的 `locales/*.json` 或任何 Shopify 介面複製。
- `test/fixtures/themes/ella-7.2.0/locales/*` 是**已購授權的測試 fixture**（鐵律 9），只用於驗證解析器與 fallback，**其字串不得進入我方預設主題或平台 bundle**。
- **例外（不是文案，是契約字串）**：`Default Title`（63 §B.2 已論證）、`gid://` 前綴、`application/json` 這類魔法值。判準：它是否被程式碼比對？是 ⇒ 契約；否 ⇒ 文案。
- 機翻 provider 的輸出**不是** Shopify 文案，不受本條限制；但它受 §E.5(b) 的稽核紀律。

### H.4 其餘鐵律的落點

| 鐵律 | 本檔的落點 |
|---|---|
| 2 多租戶 | §C 全表帶 `shop_id`，複合索引以 `shop_id` 開頭；`platform_locales` 是唯一豁免，必須登記進 `config/tenancy_exempt_tables.yml` |
| 4 API-first | 翻譯操作走 `translationsRegister`／`translationsRemove`／`shopLocaleEnable/Disable/Update`（29 §7.1 已列）；業務錯誤走 `userErrors{field,message,code}`，本檔新增碼：`LOCALE_LIMIT_EXCEEDED`／`SOURCE_LOCALE_IMMUTABLE`／`FIELD_NOT_TRANSLATABLE`／`PLACEHOLDER_MISMATCH`／`HANDLE_TAKEN` |
| 5 冪等與事件 | 翻譯批次寫入帶 `idempotencyKey`；🔴 **MT／繁簡轉換一律在 transaction 外**（外部 IO 與大量 CPU） |
| 6 上限值 | §J 全部進 `config/limits.yml`，不硬編 |
| 7 數字同源 | 翻譯進度四個出口讀同一張 `translation_status`（§C.6）；金額三處同源不受語言影響（§H.1） |
| 8 UI 值 | 語言切換器用既有 tokens 與 Lucide icon，本檔不新增視覺值 |
| 11 法域 | §A.3 正交；本檔無任何國別分支 |

---

## I. 落地：里程碑對應

| # | 項目 | 里程碑 | 依賴 | 驗收 |
|---|---|---|---|---|
| L1 | `platform_locales` ＋ `shop_locales`（含 `is_source`）＋ 標籤驗證 | **M0**（表）/ **M1**（後台） | — | 新增語言不需改碼（I18N-2） |
| L2 | `Handles::Generate` ＋ `resource_handles` ＋ 唯一性 ＋ 退役集合比對 | **M1** | 62 §B.5 `url_redirects`（M0 建表） | HDL-1～HDL-9 |
| L3 | `translations` 表（六個新欄）＋ digest 正規化 ＋ 過期分級 | **M1** | — | I18N-4／I18N-5 |
| L4 | fallback 鏈解析器（唯一實作）＋ 遙測 | **M2** | L3 | I18N-3 |
| L5 | `translation_status` 物化 ＋ 商品列表翻譯欄 | **M2** | L3 | AD-4（四個出口同源） |
| L6 | 商品編輯頁內容語言切換器 ＋ 非來源語言唯讀規則 | **M2** | L4／L5 | AD-1～AD-3 |
| L7 | URL 前綴路由 ＋ `routes` drop ＋ 切換器 ＋ `Vary` 紀律 | **M2**（i18n P0，HANDOFF §5 已列） | L1 | SF-1～SF-4 |
| L8 | Liquid 三層字串 ＋ tolerant JSONC parser ＋ 逐檔 fallback | **M2** | 31 號 lint 管線 | SF-5／SF-6 |
| L9 | 快取維度降維 ＋ `touched_dimensions` 斷言 ＋ 新 `cache_stamp` 來源 | **M2** | 63 §D.3 | I18N-10／I18N-11 |
| L10 | hreflang 的語言維度接入（餵 62 §I.1）＋ 語言變更的失效掛鉤 | **M2**（單市場多語言，62 S11 已列） | L7 | 62 §O REG-1／REG-2／REG-7 |
| L11 | 翻譯後台（資源樹 ＋ 雙欄 ＋ outdated 標示） | **M2** | L3～L5 | 29 §2.4 形態 |
| L12 | 翻譯 CSV 匯入匯出（digest 比對、🔴 **空白＝清空／缺席＝不變更** ＋ 選擇性匯出 ＋ 匯入預覽清空計數）<!-- 依 68 §B-3 修正，原文：「翻譯 CSV 匯入匯出（digest 比對、空白＝不變更）」。🔴 選擇性匯出與清空計數**不是加分項，是翻面後的必要配套**，不得拆到後面的里程碑。 --> | **M5** | L3 | AD-7、AD-7b、AD-8、AD-9 |
| L13 | 機器翻譯 provider ＋ 批次 ＋ 稽核欄 | **M5** | L3 | AD-5／AD-6 |
| L14 | 繁簡轉換工具（含歧義報告） | **M5** | L13 的批次骨架 | AD-6 |
| L15 | per-market 翻譯覆寫（Adapt，`market_id` 非 NULL） | **M5**（Markets P1，29 §8 已列） | 29 markets 全表 | I18N-6 |
| L16 | 站內搜尋 per-locale 索引與分析器 | **M5** | L4 | I18N-12 |
| L17 | 改來源語言精靈（dry-run ＋ 缺譯保留原文） | **M6** | L3 | I18N-7 |
| L18 | RTL 支援（`direction` 欄位已在 L1 就位，主題層落地） | **M6** | 主題引擎 | ⚠ V-167 |
| L19 | i18n 可觀測（fallback 命中排行、快取維度基數、機翻未覆核） | **M8** | L4／L9 | §K 可觀測維度 |

---

## J. `config/limits.yml` 新增鍵（本輪已落鍵）

新增兩個頂層區塊：**`i18n:`**（§20）與 **`handle:`**（§21）。

**為什麼 `handle` 獨立成一個頂層區塊而不是塞進 `i18n` 或 `seo`**：handle 政策同時被 62（SEO／301／canonical）與本檔（語言維度）引用，也被 13（商品欄位）引用。放進任一方都會讓另外兩方跨區塊引用一個「看起來屬於別人」的鍵。

**既有鍵一律沿用不重複定義**：

| 既有鍵 | 用途 | 本檔引用處 |
|---|---|---|
| `content.seo_title_max_chars` / `seo_meta_description_max_chars` | SEO 欄位上限（譯文沿用同一上限） | §B.2、§J `per_field_limits_follow_source_field` |
| `product.title_max_chars` / `description_max_bytes` | 譯文長度上限的來源 | 同上 |
| `currency_display.*` | 金額顯示（語言不參與） | §H.1 |
| `market.inheritance_additive`（含 `web_presences`） | 語言集合沿 lineage 累加 | §A.1、§F.1(d) |
| `seo.hreflang.*` | 碼格式、禁用碼、失效去抖 | §A.4、§F.1(a) |
| `seo.redirect_max_chain` | handle 改名鏈長 | §D.4(e) |
| `catalog_flow.cache_stamp_sources` | 🔴 必須加入 `translations` | §G.3 |
| `catalog_flow.default_variant_liquid_title` | `Default Title` 契約（與語言無關） | §B.3-3 |
| `csv.product_max_upload_mb` | 翻譯 CSV 沿用同一上限 | §E.6 |
| `notification.non_toggleable_ui` | 唯讀欄位的 UI 形態（灰化＋tooltip） | §E.3 |

**2026-08-12 依 68 號「全部跟隨 Shopify」裁定的鍵變更**（本檔範圍；每鍵在 `limits.yml` 內都有 `依 68 號 §X … 原值：…` 的追溯註釋）。
🔴 **其中 `i18n.import`／`i18n.export` 一組已於同日再修一次**（69 號 §V-182 推翻了 68 §B-3 的前提）——下表已把兩次都寫進「原值 → 新值」欄，**沒有任何一列是單次改動的結果**，讀的時候不要只看箭頭的終點：

| 鍵 | 原值 → 新值 | 依據 | 本檔落點 |
|---|---|---|---|
| 🔴 `i18n.import.blank_means_unchanged` | `true` → 68 改 **`false`** → 69 **改回 `true`**（空白＝不動作） | **二次修正**：68 §B-3 依 Matrixify（`press`）翻面；**69 §V-182 查到本尊原生語義（`help`）後改回** | §E.6(a)① |
| `i18n.import.absent_row_means_unchanged` / `absent_column_means_unchanged` / `absent_vs_blank_distinguished_by_header` | 68 新增，**69 全數保留**（理由換成「界定 overwrite 範圍」） | 68 §B-3 ＋ 69 §V-182 | §E.6(a) |
| `i18n.export.selectable_locales` / `selectable_fields` / `omit_unselected_as_columns` | 68 新增，**69 保留**（理由換成「縮小覆寫爆炸半徑」） | 68 §B-3② ＋ 69 §V-182 | §E.6(a) |
| `i18n.import.preview_required` / `preview_clear_count_separate` / `clear_ratio_confirm_threshold` / `clear_writes_audit_trail` | 68 新增，**69 全數保留**（計數對象改為 `__CLEAR__` ＋ overwrite） | 68 §B-3③ ＋ 69 §V-182 | §E.6(a) |
| 🔴 `i18n.import.explicit_clear_token_is_alias_of_blank` | 68 新增 `true` → 69 **改 `false`** | 69 §V-182（`__CLEAR__` 回到**唯一**清空手段） | §E.6(a)③ |
| 🔴 `i18n.import.overwrite_existing_default` / `overwrite_scope` | **69 新增**（預設 `false`＝只補新的） | 69 §V-182（本尊＝「覆寫既有翻譯」勾選框，`help`） | §E.6(a)② |
| 🔴 `i18n.import.preview_overwrite_count_separate` / `overwrite_ratio_confirm_threshold` / `overwrite_writes_audit_trail` | **69 新增** | 69 §V-182（overwrite 是新的破壞性來源，爆炸半徑同樣是整份檔案） | §E.6(a) |
| `i18n.export.status_values` / `status_is_export_only` / `columns`（順序對齊本尊 8 欄） | **69 新增／調整** | 69 §V-182（`Status` 三值；`help` ＋ `vendor` 佐證）⚠ V-201 | §C.5(f)、§E.6(b) |
| `i18n.export.async_delivery` / `delivery_channels` | **69 新增** | 69 §V-182（本尊匯出以 email 寄出；亦符合我方 outbox 形態） | §E.6(b) |
| `handle.collision_strategy_generated` | `numeric_suffix_from_2` → **`numeric_suffix_from_1`** | 68 §C-4（`dev` `potion`／`potion-1` ＋ `test` ×4） | §D.4(b)、§M-1 |
| `handle.liquid_filter_fallback_trigger` / `liquid_filter_fallback_on_non_ascii_result_forbidden` | 新增 | 68 §F-3（staff 復現：filter **保留**非 ASCII） | §D.5、V-161 |
| `handle.ascii_only` / `expand_symbol_words` / `delete_chars` / `max_chars` | **值不變**，註釋補出處與偏離標記 | 68 §B-1／§C-4／§C-6 | §D.1 對照表、62 §F.3-1 |
| `i18n.storefront.auto_redirect_on_language` | **值不變（`false`）**，理由改寫 | 68 §C-3（本尊亦預設停用；**地區**那一半已翻為啟用） | §F.2 |

---

## K. 驗收清單

### K.0 對照 `docs/specs/11` §0 七維度

| 維度 | 本模組的最低標準 |
|---|---|
| **1 安全** | 翻譯寫入需 `staff` 權限且過 shop scope；🔴 **匯入的譯文一律當不可信輸入**——富文本走與商品描述同一條淨化管線（譯文是最容易被當成「已經是自家內容」而漏掉淨化的入口）；MT provider 金鑰走 Rails credentials；公開端點（語言切換）無狀態 |
| **2 資料完整** | `translations` 六欄唯一索引；`shop_locales` 的 `is_source` 部分唯一；handle 唯一索引 ＋ 退役集合比對；來源語言遷移全程 transaction 且缺譯保留原文；FK 到 `platform_locales` |
| **3 併發** | 同一 (resource, locale, field) 併發寫入 ⇒ 唯一索引兜底 ＋ `updated_at` 樂觀鎖；來源寫入與翻譯寫入的交錯 ⇒ digest 在**同一 transaction** 內比對（§C.5(d)）；handle 配號用唯一索引重試，不用 SELECT-then-INSERT |
| **4 效能** | 渲染期翻譯**一次批次載入**（每頁 SQL ≤15 條，63 §D.1）；進度數字讀物化表不現算；快取維度降維（§G.2）；`translation_status` 的批次建列可斷點續跑 |
| **5 可觀測** | `i18n.fallback_hit`（帶 depth）／`i18n.translation_missing`（Liquid `t` 未命中）／`i18n.cache_key_cardinality`／`i18n.machine_translation_batch`／`handle.auto_token_ratio`；全部帶 `shop_id`＋`locale` |
| **6 測試** | fallback 鏈的**全分支**單元測試（含 `zh-Hant`／`zh-Hans` 互不回退）；handle 管線以 §D.1 的七個樣本做表格測試；跨語言污染的 system test（§K I18N-11）；金額不隨語言變的斷言（I18N-9） |
| **7 合規/隱私** | 譯文可能含 PII（商家貼進描述）⇒ 進 PII 清單與 purge 任務；匯出檔含商家內容 ⇒ 走既有的匯出授權與稽核；機翻把商家內容送第三方 ⇒ 🔴 **provider 設定頁必須明示資料出境**，且 provider 未設定時整個功能不出現 |

### K.1 逐條驗收

**語言與資料模型**

| # | 條目 | 判準 |
|---|---|---|
| I18N-1 | 語言集是資料 | `limits.yml` 與原始碼中不存在語言值列舉（lint 規則掃 `zh-Hant`／`zh-Hans` 字面量；白名單只有種子檔、註解與 `limits.i18n.launch_locales` 這個明標為「種子指標非值域」的鍵） |
| I18N-2 | 新增語言零改碼 | 測試新增 `ja` 並完成一次前台渲染、一次 admin 編輯、一次 hreflang 產出，過程無原始碼變更、無 migration |
| I18N-3 | **fallback 鏈** | 逐分支：per-market → 語言 → 截尾鏈 → 來源原文 → 依欄位類別；🔴 `zh-Hant` 缺譯**不得**取到 `zh-Hans`；🔴 `zh-Hant-HK` 不得截到 `zh` |
| I18N-4 | 過期偵測不誤報 | 對來源做「僅空白／僅屬性順序」變更 ⇒ `severity = none`，零筆被標記 |
| I18N-5 | 過期不影響渲染 | 標記 outdated 後前台輸出不變 |
| I18N-6 | per-market 覆寫優先 | 同一 (resource, locale) 有市場覆寫時，該市場取覆寫、其餘取語言層 |
| I18N-7 | 改來源語言 | 目標語言缺譯的資源，遷移後 base row **仍是原文**，且落一列 gap 記錄 |
| I18N-8 | 不可翻欄位 | 對 `sku`／`tags`／money metafield／`handle` 呼叫翻譯 API ⇒ `FIELD_NOT_TRANSLATABLE` |
| I18N-9 | **金額不隨語言** | 同一 variant × 同一 market，三個 locale 渲染的 `money` 輸出**逐位元組相同** |
| I18N-10 | cache_stamp 覆蓋 | 開啟 63 §D.3 的自檢模式渲染含翻譯的頁面，`touched_sources ⊆ cache_stamp_sources` 不 raise |
| I18N-11 | **無跨語言污染** | 交錯請求三個 locale 各 100 次，回應中不得出現他語言字串（以譯文哨兵字串斷言） |
| I18N-12 | 搜尋 per-locale | 中文查詢不回英文結果；`UNLISTED` 商品任何語言皆不進索引 |

**handle**

| # | 條目 | 判準 |
|---|---|---|
| HDL-1 | **ASCII only** | 全店任一 handle 匹配 `^[a-z0-9]+(-[a-z0-9]+)*$`；CI 掃描資料庫，違反即紅燈 |
| HDL-2 | 範例逐字元相符 | 以裁定的標題輸入 ⇒ 輸出 `kerastase-…-125ml-4-2oz` |
| HDL-3 | 小數點不被吞 | `4.2oz` ⇒ `4-2oz`（**不是** `42oz`） |
| HDL-4 | 不可分解字母 | `Straße` ⇒ `strasse`（**不是** `stra-e`） |
| HDL-5 | 品質閘門 | `棉質短T` ⇒ 落 fallback；`無印良品 MUJI 有機棉 T-Shirt` ⇒ `muji-t-shirt` |
| HDL-6 | 截斷在分隔符 | 超長標題截斷後無半個詞、無尾隨 `-` |
| HDL-7 | 衝突策略 | <!-- 依 68 §C-4 修正，原文：「生成衝突 ⇒ `-2`」 -->生成衝突 ⇒ **`-1`**（第二個同名資源得 `-1`，第三個得 `-2`；對照 Shopify 官方例 `potion`／`potion-1`）；**手填衝突 ⇒ 拒絕**並回 `HANDLE_TAKEN` |
| HDL-8 | 永不回收 | 改名後以舊 handle 建新商品 ⇒ 拒絕（除非商家已刪該 301） |
| HDL-9 | **前綴保留的 301** | `/en/products/舊` ⇒ 301 到 `/en/products/新`（不得掉回無前綴） |
| HDL-10 | filter 不共用實作 | <!-- 依 68 §F-3 收緊，原判準：「`{{ '顏色' \| handleize }}` 不得為空字串；且與 `Handles::Generate` 是不同實作」——「不得為空」擋不住「落成 h-xxxxxxxx」 -->`{{ '顏色' \| handleize }}` **必須恰為 `顏色`**（不得為空字串，**也不得是 `h-{sha1}` fallback**——本尊保留非 ASCII）；`{{ '' \| handleize }}` 與 `{{ '---' \| handleize }}` ⇒ 落 `h-{sha1}`；且與 `Handles::Generate` 是不同實作 |

**後台**

| # | 條目 | 判準 |
|---|---|---|
| AD-1 | 兩個切換器獨立 | 改介面語言不改內容語言，反之亦然 |
| AD-2 | 內容語言進 URL | 重新整理後仍在同一內容語言；連結可分享 |
| AD-3 | **非來源語言唯讀** | 在 `en` 頁面對價格／SKU／庫存／狀態／handle／tags 的寫入嘗試 ⇒ 前端灰化 ＋ 後端拒絕（雙層） |
| AD-4 | 進度數字同源 | 列表徽章／翻譯後台／健康頁／GraphQL 四處數字相同（改一筆譯文後同時變） |
| AD-5 | 機翻稽核 | MT 寫入的每一列 `value_source='machine'` ∧ `review_required=true`；批次超門檻需二次確認 |
| AD-6 | 繁簡轉換 | 簡→繁批次的完成報告列出含歧義字的筆數；UI 明示「字形轉換不是翻譯」 |
| AD-7 | 🔴 **翻譯 CSV 空白＝不動作；清空與覆寫都要明示** | <!-- 二次修正：原文「翻譯 CSV 空白＝不變更」→ 68 §B-3 反轉成「空白＝清空」（三條測項）→ 69 §V-182 查到本尊原生語義後**改回不動作**，並補上 overwrite 維度。68 那一版的測項②（缺席 vs 空白對照）**原樣保留**，因為它現在測的是 overwrite 的作用範圍。 -->**五條一起測**：①匯入含**空白** `translated_text` 的列 ⇒ 該譯文**維持原值**（🔴 不得被清空）；②匯入**不含** `translated_text` 欄的檔案（表頭就沒有）⇒ 既有譯文不變（🔴 與 ① 用同一份資料對照，確認解析層真的分得出缺席與空白）；③`overwrite_existing: false`（預設）匯入有值的列 ⇒ **既有譯文不變、缺的補上**；④`overwrite_existing: true` 同一份檔案 ⇒ **有值的儲存格覆寫既有譯文，空白儲存格仍不動作**（🔴 這一條擋的是「overwrite 被實作成整列取代」）；⑤寫 `__CLEAR__` 的儲存格 ⇒ 該譯文被清空 |
| AD-7b | **清空與覆寫都可回溯** | 被清空**或被覆蓋**的舊譯文在稽核軌可查到（誰、何時、哪一次匯入、舊值）；dry-run 預覽的「將清空 N 筆」「將覆寫 M 筆」**分開兩個數字**且與實際筆數相等，任一比例 > 門檻時需二次確認 |
| AD-7c | **匯出欄位與 status** | 匯出檔欄位集合與順序對齊本尊 8 欄 ＋ `source_digest`；`status` 只有 `translated`／`outdated`／`untranslated` 三值且與 `translations.outdated` 一致；🔴 **匯入時修改 `status` 欄的值不產生任何效果**（純輸出，過期狀態只能由 digest 決定，§C.5(f)） |
| AD-8 | digest 不符不靜默 | digest 不符的列寫入後標 `outdated` ＋ `review_required`，並出現在匯入報告 |
| AD-9 | 缺 digest 欄拒收 | 缺 `source_digest` 欄的檔案整檔拒絕 |

**前台**

| # | 條目 | 判準 |
|---|---|---|
| SF-1 | 語言只由 URL 決定 | 同一 URL 送三種 `Accept-Language`，回應主體逐位元組相同。<!-- 依 68 §C-3 補測試實作註記（2026-08-12）：**地區**自動重導已預設啟用（62 §K.2），而其判定輸入含瀏覽器語言 ⇒ 三次請求的**狀態碼可能不同**（302 vs 200）。本條斷言的是**回應主體**，不是狀態碼 ⇒ 測試必須**跟隨重導到最終 URL 後再比對主體**，否則會把「地區重導預設開」誤判成跨語言污染。 -->⚠ 測試須**跟隨重導**後再比對主體（地區重導預設開，狀態碼可能不同；本條測的是語言維度） |
| SF-2 | 無 `Vary: Accept-Language` | 回應標頭不含該值 |
| SF-3 | **語言**不自動重導 | 預設不因**語言**重導（`auto_redirect_on_language: false`，✅ 與本尊一致）；切換器是真實 `<a href>`。<!-- 依 68 §C-3 補充：**地區**重導的預設已翻為啟用（62 §K.2），本條**只管語言維度**，兩者不得連動。 -->⚠ 本條**不涵蓋地區重導**——地區維度預設**啟用**，其驗收在 62 §O REG-9 |
| SF-4 | 未發布語言 404 | 未發布語言的 URL 回 404，且不在 hreflang／sitemap 內 |
| SF-5 | 三層字串解析 | 商家覆寫 → 主題檔 → 平台預設；未命中不得輸出 key 名或空字串 |
| SF-6 | JSONC 容錯 | 帶 `/* */`、CRLF、BOM、尾隨逗號的 locale 檔可解析 |
| SF-7 | 連結帶前綴 | 切語言後點擊主題內任一內部連結，仍在該語言 |
| SF-8 | 結帳鎖語言 ＋ 訂單快照 | 結帳中無語言切換；訂單存 `locale_snapshot`，顧客改語言不影響既有訂單頁與通知 |

---

## L. 待查證（V-160 起）

> 起編說明：倉庫現有最大編號 **V-146**（66 號 §C.3）。本檔自 **V-160** 起編，留 13 號緩衝避免與同輪其他 agent 撞號。
>
> **本檔結案的既有條目**：**V-119**（Shopify `handleize` 對 CJK 的行為）。
> <!-- 依 68 號 §B-1 改寫，原文：「政策面由 2026-08-12 裁定結案（我方一律 ASCII，**不再需要對齊**），
>      已於 62 §F.3 與 §附錄 A 標記結案；其**主題相容殘留**改由 V-161 承接。」
>      🔴 「不再需要對齊」是錯的敘述——68 號**把答案查出來了**（本尊保留 CJK），
>      所以這是「查到了、而且我方明知並偏離」，不是「不必比較」。 -->
> **正確形態**：68 號已查明本尊行為＝**保留 CJK**（`press` ×4，官方從未文件化）；我方一律 ASCII 是**明知偏離**，唯一依據＝使用者裁定（**裁定 > Shopify**）。偏離登記在 **62 §F.3-1**。其**主題相容殘留**（filter 面）由 V-161 承接，**該條亦已依 68 §F-3 縮小**（filter 保留非 ASCII 已證實）。

| # | 未取得的是什麼 | 取得途徑 | 結案前的處置 | 影響章節 |
|---|---|---|---|---|
| ~~**V-160**~~<br>✅ **後半已答，前半降級** | ~~Shopify handle 的字元數上限；以及 `handleize` 對 `.` 與撇號的實際處置（轉分隔／刪除）~~<br>**後半已答**（68 §C-4 `test`）：`.`→分隔（`A.P.C. → a-p-c`、`B.M.B BREWERY → b-m-b-brewery`）、`/`→分隔（`#AU/NZ → au-nz`）、撇號與引號**刪除**（`Women's → womens`、`16" Cash Drawer → 16-cash-drawer`）⇒ **逐條與我方相同**。<br>**前半（字元上限）**：255 已有二手佐證且**數值恰好相同**（`press`，matrixify）⇒ 從「未查證」降為「二手佐證」，**取得官方出處改由 68 的 V-183 承接** | shopify.dev 商品欄位頁；或以超長標題實測 | 維持 `handle.max_chars: 255`、`.`→分隔、撇號→刪除。**不因未查證而改動** | §D.1 |
| ~~**V-161**~~<br>✅ **已縮小** | ~~Liquid `handleize` **filter** 對 CJK 的實際輸出（保留／落空／轉寫）~~ ⇒ **已答：保留**（`press`，community.shopify.dev 1060，2024-10，**staff 復現**：輸出保留 emoji、`ŭ`→`u`）。**殘留**：全形字元、以及空輸入／全分隔符輸入的輸出 ⇒ 併入 68 的 **V-181** | 實測（中文選項名的主題渲染）＋ Liquid 沙箱 | <!-- 依 68 §F-3 縮小，原處置：「filter 保留非 ASCII ＋ 空結果落 `h-{sha1}`；與 `Handles::Generate` **不共用實作**」 -->filter **保留非 ASCII**（✅ 已證與本尊一致）；`h-{sha1}` fallback 🔴 **只在空／全分隔符輸入時觸發，不得因結果非 ASCII 觸發**；與 `Handles::Generate` **不共用實作** | §D.5 |
| **V-162** | Shopify 對帶 script subtag 語言（`zh-Hant`／`zh-Hans`）使用的 URL 子資料夾字串 | help.shopify.com/manual/markets；實測 | 我方用 `/zh-hant`／`/zh-hans`（理由見 §F.1(b)），**不用 `/zh-tw`** | §F.1 |
| ~~**V-163**~~<br>✅ **主體已結案**（69 §V-182） | ~~Shopify **原生**是否提供翻譯 CSV 匯入匯出、格式與欄位、以及**空白語義**~~<br>🔴 **已答（`help`，69 §V-182）**：**有**原生匯出／匯入，位置在 **Settings → Languages**（不在 Translate & Adapt app 裡——**68 號因此找不到，這正是它誤判「原生能力薄弱或不存在」的原因**）；**8 欄** ＋ `Status` 三值（`Translated`／`Outdated`／`Untranslated`）；匯入的核心是**「覆寫既有翻譯」勾選框**；匯出以 email 非同步寄出。**官方對「Translated content 留空會怎樣」完全沒寫** ⇒ 承接到 **V-200**。<br>**殘留**：XLIFF 官方格式是否存在（我方列 P2） | ~~help.shopify.com Translate & Adapt 子頁~~ ⇒ **已由 69 號在 `localization-and-translation` 頁查到**；XLIFF 殘留仍需 help 逐頁 | <!-- 二次修正。68 §B-3 的處置是：「🔴 空白＝清空、缺席＝不變更（§E.6(a) 三件套）」，依據是 Matrixify（`press`）；並註明「若查出官方原生行為不同，本條要重判（連 blank_means_unchanged 一起）」——**69 §V-182 正是那個觸發條件，本條依該註記重判**。 -->我方 CSV ＋ 強制 `source_digest` ＋ 🔴 **空白＝不動作、清空走 `__CLEAR__`、覆寫走顯式旗標**（§E.6(a)）；欄位對齊本尊 8 欄 ＋ `status` 三值；XLIFF 列 P2 | §E.6、§C.5(f) |
| 🔴 **V-200**<br>（承 69 號登記） | 本尊的 `Translated content` **留空**時，在「勾選覆寫」與「不勾選」**兩種模式下分別**做什麼（官方 help 對此完全沉默——**這是本尊模型裡唯一沒寫清楚的一格**） | dev store 實測：匯出 → 清空一列 → 兩種模式各匯入一次 → 看譯文是否消失 | 🔴 我方**不**把空白解讀成刪除（`blank_means_unchanged: true`）；刪除必須是另一個明示動作（`__CLEAR__`）。**即使日後查出本尊在勾選覆寫時會刪，也不得自動跟隨**——不可逆操作由易誤觸狀態觸發，屬產品決定，需使用者裁定 | §E.6(a)① |
| 🔴 **V-201**<br>（承 69 號登記） | 本尊的 `Status` 欄在**匯入**時是否被讀取（還是純輸出欄）；以及 `Market` 欄**留空**的語義 | 同 V-200（dev store 實測） | `status` **純輸出**，匯入時忽略（§C.5(f)：過期狀態只能由 digest 決定，不能由檔案宣稱）；`market_handle` 留空 ⇒ **拒絕匯入該列**（保守做法：留空可能是「套用到所有市場」也可能是「漏填」，兩者後果差很遠） | §C.5(f)、§E.6(b) |
| **V-164** | `translationsRegister` 在 `translatableContentDigest` 不符時的官方行為（拒絕？寫入並標過期？） | shopify.dev mutation 頁的錯誤碼表 | 我方**寫入並標 outdated ＋ review_required**（§E.6）。不得靜默當成最新 | §C.5、§E.6 |
| **V-165** | 商家可新增的語言集合是否封閉（Shopify 是否只允許其支援清單內的語言） | help.shopify.com 語言設定頁；`shopLocaleEnable` 的錯誤碼 | 我方**開放**（裁定明文「可自行添加任何語言」），只驗 BCP-47 格式與禁用碼 | §A.2、§C.1 |
| **V-166** | MySQL 8 可用的中文排序 collation（是否有 `utf8mb4_zh_0900_as_cs`、其排序依據是拼音或筆畫） | MySQL 官方文檔；實機 `SHOW COLLATION` | 沿用預設 collation，UI 標「依系統順序」，**不宣稱拼音或筆畫排序** | §C.7 |
| **V-167** | RTL 語言在 Shopify 主題的支援形態（平台注入 `dir` 或全由主題負責） | shopify.dev 主題架構頁；實測 | `platform_locales.direction` 欄位先就位；主題層落地排 M6；匯入 degradation report 標示主題是否有 RTL 樣式 | §C.1、§I L18 |
| **V-168** | 多語言下站內搜尋的官方行為（是否只搜當前語言、譯文是否進索引） | help.shopify.com 搜尋頁；實測 | 我方：per-locale 索引、只搜當前語言、無結果時提示跨語言搜尋（不自動） | §C.7 |
| **V-169** | 官方機翻「限 2 種語言」的現況與依據（29 §2.4 記載，本輪未覆核） | help.shopify.com Translate & Adapt | 以 `limits` 鍵表達，**不寫死**；我方不必對齊該限額 | §E.5(a) |
| **V-170** | 通知信語言解析的官方優先序（顧客語言 vs 訂單語言 vs 市場預設） | shopify.dev 通知範本頁；實測 | 我方：`customers.locale` → 訂單 `locale_snapshot` → shop source locale | §F.5 |
| **V-171** | Shopify 是否提供官方的繁簡自動轉換（若有，其方向與品質標示） | help.shopify.com 語言頁 | 我方做成獨立工具（§E.5(c)），寫入真實譯文列且標 `script_conversion` | §E.5(c) |

---

## M. 與既有規格的衝突登記（本檔只改 62 §F.3 與 V-119，其餘只登記）

| # | 衝突 | 現況 | 本檔立場 | 誰該改 |
|---|---|---|---|---|
| **M-1** | **handle 允許 CJK** | 13 §F2-1：「中文標題不轉拼音，改用『允許 unicode handle（URL encode）』……demo 選 unicode handle（`/products/棉質短T` 可用）」；13 §F2-2「衝突自動 `-1` `-2` 後綴」 | 🔴 **前半：被 2026-08-12 裁定推翻**——一律 ASCII（§D.1）。⚠ 但要寫清楚這是**明知偏離 Shopify**（本尊保留 CJK，68 §B-1；登記於 62 §F.3-1），不是「13 寫錯了」。<br>✅ **後半：反向結案**——<!-- 依 68 §C-4 修正，原文：「另衝突尾碼自 `-2` 起算，且**手填衝突拒絕不加尾碼**（§D.4(b)）」 -->**13 §F2-2 的 `-1` 起算本來就是對的**（Shopify 官方例 `potion`／`potion-1` ＋ 實測），要改的是本檔，已改（§D.4(b)）。**手填衝突拒絕不加尾碼**維持（68 V-184 無一手證據 ⇒ 保守失效） | **13 §F2-1 仍待改**（ASCII 化）；**13 §F2-2 不必改**（它是對的） |
| **M-2** | **handle 列為可翻譯資源** | 29 §2.1 把 `PRODUCT/COLLECTION/ARTICLE.handle` 列入 `TranslatableResourceType` 的欄位集。<br>🔴 **68 §F-1 補強了這條的份量**：這不只是 29 號的一張表——`shopify.dev/changelog/resource-url-handles-are-now-translatable`（**2023-06-26**）是**官方明文能力**，且實務上啟用多語言後同一商品在各語言**就是不同 handle**（AJAX API 必須用該語言的 handle） | 我方 handle **不可翻**（§D.3，**明知偏離**，依據＝「一律英文」裁定的下游後果，不是技術偏好）。29 §2.1 需加註「本專案不採用 handle 的可翻譯性，語言維度由 URL 前綴承載，見 67 §D.3」。⚠ **待使用者確認**：「handle 一律英文」是否**同時**意味著放棄 per-locale handle 能力（我方推定是） | 29 §2.1 |
| **M-8**<br>⚠ **部分已處理** | **跟隨 Shopify 的結論反轉，尚未全部回寫到下游檔案** | ✅ `docs/handoff/2026-08-12-open-decisions.md`：**B-3／B-6／C-1～C-3／D-3 已於 2026-08-12（69 號修正輪）更新並移入 §F**。<br>✅ `65 §A2·T11`：已更新為「market 可建立 ＋ 送款被擋」（同輪）。<br>❌ **仍未回寫**：`63 §G.4`（含其硬規則「一律依 ISO 4217 exponent 換算」——🔴 該句現已知**不完整**，見 65 §J **M-8**）、`55` 金額測試矩陣（仍記「market 建立時擋下」）、`13 §F2-1`（仍是 unicode handle） | 以 `config/limits.yml` 的鍵為準（每鍵都有 `依 68 號 §X`／`依 69 號 §V-XXX` 追溯註釋）。🔴 **63／55／13 本輪仍不得改**，必須由其擁有者回寫，否則會出現「規格說 A、鍵說 B」的分裂 | 63／55／13 |
| 🔴 **M-9**<br>（2026-08-12 二次修正） | **B-3 的結論在同一天反轉了兩次** | 68 §B-3 依 Matrixify（`press`）把 `blank_means_unchanged` 翻成 `false`；69 §V-182 查到本尊原生語義（`help`）後**改回 `true`** ＋ 改成 overwrite 旗標形態 | 🔴 **`docs/research/68` 的 B-3 條不會被修正**（research 是證據不是結論）⇒ 任何人讀到 68 §B-3 要求翻面時，**必須同時讀 69 §V-182 與本檔 §E.6 的沿革註釋**。三處已互相交叉引用，但**只讀 68 就動手是可能發生的**——這是本輪最現實的回退風險 | 無（本列即防回退措施） |
| **M-3** | ~~62 §M S2「`handle` 欄位＋可翻譯」~~ | — | ✅ **本輪已改**（改為標註不可翻並指向 67 §D.4） | — |
| **M-4** | **頁級 cache key 無條件含 locale** | 63 §D.3 的 key 組成把 `locale` 寫死在列表裡 | 改為**依實際依賴降維**（§G.2），並沿用該節既有的 `touched_sources` 自檢做 fail-closed 判定。另 `catalog_flow.cache_stamp_sources` 必須加入 `translations` | 63 §D.3（本檔不改 63） |
| **M-5** | **`translations` 表缺六個欄位** | 29 §2.2 的表定義只有 `source_digest` ＋ `outdated` | 需補 `outdated_severity`／`value_source`／`review_required`／`source_locale_tag`／`updated_by_staff_id`／`updated_at`（§C.2） | 29 §2.2 |
| **M-6** | **hreflang 失效掛鉤只綁 market conditions** | 62 §I.3(b)：market conditions 變更 ⇒ 矩陣與 sitemap 失效 | 觸發條件需**加上** `shop_locales` 與 `market_web_presence_locales` 的變更（§F.1(d)）。否則發布新語言後 hreflang 停在舊值 | 62 §I.3(b)（小幅補充，本輪未改以免擴大改動面） |
| **M-7** | **`Product.published` 的語言面** | 13 §F1.2 已拆成 `purchasable`／`discoverable`（四態） | 🔴 **兩個 scope 都與語言正交**：`UNLISTED` 商品的**每一個**語言版本都不可被發現。多語言不新增第三個 scope | 無（本檔確認既有設計正確，登記以防日後有人加 `published_in_locale`） |

---

## 附錄 A · 本檔的可重跑驗證

§D.1 的管線與 §D.1 驗證樣本表由下列步驟產生（供覆核者重跑；腳本本身不入庫，因為它只是 §D.1 規格的直譯）：

1. 以 Python `unicodedata` 實作 §D.1 的九個步驟（NFKC → 撇號刪除 → 不可分解字母轉寫表 → NFKD 去 combining → 小寫 → 非 `[a-z0-9]` 轉分隔 → 收斂修剪 → 分隔符邊界截斷 → 品質閘門）。
2. 以裁定給的標題為輸入，斷言輸出 == 裁定給的 handle（**已通過，逐字元相同**）。
3. 以 §D.1 表中其餘六個樣本為輸入，記錄輸出與閘門結果——即該表的內容。
4. 實作時的對應測試是 `HDL-2`～`HDL-6`，測試資料**直接使用該表**（規格與測試同源，鐵律 7 的文件版）。
