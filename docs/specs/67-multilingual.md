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
| `ruling` | **使用者裁定**（本檔即 2026-08-12 多語言裁定的落地，2026-08-13 再加一條 locale 碼裁定＋一條 per-market 白名單裁定） | ✅ 可，且**優先於 `dev`**——裁定是產品決策，不是對 Shopify 的復刻 |
| `alt`<br><!-- 2026-08-13 新增，與 62 §0.3 同步。 --> | **非 Shopify 的第三方商店／後台實測**。本輪兩個：strawberrynet.com（URL 前綴形態）與 **Shopline 商品新增頁的 ng-model 綁定**（翻譯輸入模式） | ⚠️ **僅供「這個形態在真實世界跑得起來 ／ 這是他家的資料形態」的存在性佐證**，🔴 **不得據以寫死實作**。一律登記 V 編號 |

🔴 **`alt` 級來源在本檔的用法必須逐條檢查，因為它同時觸到鐵律 9**：
- ✅ **可用**：他家產品的**行為與資料形態的觀察**（哪些欄位有 `_translations` 後綴、URL 前綴長什麼樣、一個輸入框綁一個語言還是綁一個 tab）。這是**看得到的介面事實**，與看原始碼無關。
- 🔴 **不可用**：他家的**程式碼、樣式表、文案**。Shopline 的 ng-model 字串（`product.title_translations[lang]`）在本檔出現時，**是被當成「他家的資料模型長這樣」的證據引用，不是被當成「我方要照抄的識別字」**——我方的欄位名一律走 §C.2 的 `translations(resource_type, resource_id, locale_tag, field_key)`，**不是** `*_translations` 這種以欄位後綴表達語言的形態（理由見 §E.2-1(c)）。
- ⚠ **`press` 與 `alt` 的差別**（69 §V-182 那次教訓的延伸）：`press` 錯在轉述失真、找到一手就能修；**`alt` 找到一手也沒用**——他家的取捨不是我家的取捨。⇒ **`alt` 足以支持「這個形態存在」，不足以支持「所以我們也要這樣」**。本檔每一處引用 `alt` 都必須另外給我方自己的理由。

### 0.4 本檔推翻／偏離的既有結論（逐條可追溯）
<!-- 2026-08-13 修正表頭：原「（5 條，…）」。前輪加第 5/6 列時計數已過時，本輪再加第 7 列——改為不寫死數字，防止三度過時。 -->

| # | 既有寫法 | 本輪處置 | 誰改 |
|---|---|---|---|
| 🔴 **0** | **本檔自己的 §E.6 空白語義**（`i18n.import.blank_means_unchanged`） | **2026-08-12 同日反轉兩次**：原 `true`（我方原設計）→ 68 §B-3 依 **Matrixify（第三方，`press`）** 改 `false`（空白＝刪除）→ 🔴 **69 §V-182 查到本尊原生語義（Settings → Languages，`help`）後改回 `true`**，並改成 **overwrite 旗標 ＋ 空白＝不動作**。<br>**教訓（寫在最前面，因為它適用於全檔）**：`press` 級來源足以「登記為未知」，**不足以翻面一條已生效的資料安全預設**。沿革全文見 §E.6 檔頭註釋、§M-9 | ✅ **本輪已改** |
| 1 | **62 §F.3**「handle 保留 CJK、URL 走 percent-encoding」（登記為 V-119） | **裁定推翻**：一律 ASCII。§F.3 已改寫並留追溯註釋。<br>🔴 **2026-08-12 二次修正（68 §B-1）**：V-119 的結案敘述原寫成「對齊問題消失」，實際是**本尊保留 CJK、裁定覆蓋 Shopify** ⇒ 已改寫為**明知偏離登記**（62 §F.3-1） | ✅ **本輪已改** |
| 2 | **13 §F2-1**「中文標題不轉拼音，demo 選 unicode handle（`/products/棉質短T` 可用）」 | 同上被推翻。本檔**不改 13 號**（另有 agent 在改 13/63/65），登記於 §M-1 | 13 §F2 |
| 3 | **29 §2.1** 把 `PRODUCT/COLLECTION/ARTICLE.handle` 列入可翻譯資源型別 | **我方刻意偏離**：handle **不可翻譯**，語言維度由 URL 前綴承載（§D.3）。登記於 §M-2 | 29 §2.1 |
| 4 | **63 §D.3** 頁級 fragment key **無條件**含 `locale` | 改為**依實際依賴降維**（§G.2），並沿用 63 §D.3 既有的 `touched_sources` 自檢把降維做成可執行斷言。登記於 §M-4 | 63 §D.3 |
| 🔴 **5**<br>（**2026-08-13 新增**） | **本檔 §F.1(b) 的 URL 前綴表**：「primary market ＋ shop 預設語言 ⇒ 無前綴；primary market ＋ 其他語言 ⇒ `/en`、`/zh-hans`」（承 29 §2.5 的既有約束）<br>**以及 62 §I.2**「單國市場 → `fr-ca`；多國市場 → `fr`」 | 🔴 **2026-08-13 裁定推翻兩者**：一律 `語言[-字體]-地區`，**永不出現裸語言碼／裸語言前綴**（`en-HK`／`en-CA`／`zh-Hant-HK`／`zh-Hant-TW`）。§F.1 已改寫；62 §I.2 已改寫並在 **62 §I.2-1** 留明知偏離登記。<br>**動機句的誠實拆解在 62 §I.2-2**（🔴 該節明寫「加地區碼就不會被判重複」**不成立**，真正有效的是「每個 (市場,語言) 一條專屬 URL ＋ 一個明確的碼」） | ✅ **本輪已改**（62／67 兩檔同輪改完，**不得只改一邊**——只改碼不改前綴 ⇒ 自指不變量破裂） |
| 🔴 **6**<br>（**2026-08-13 新增**） | **本檔 §A.1**「市場的可用語言掛在 `market_web_presence_locales`」只寫了**存在**，沒有寫**它是對買家的白名單**，也沒有定義未開放 locale 被直接存取的行為 | 🔴 **2026-08-13 裁定補上語義**：商店啟用的語言集合 ≠ 某市場對買家開放的語言集合（strawberrynet 模型）。新增 §A.5（概念與邊界）＋ §C.8（資料模型與 admin 契約）。🔴 **不新建 `market_locales` 表**，理由見 §C.8(a) | ✅ **本輪已改** |
| 🔴 **7**<br>（**2026-08-13 新增，明知偏離 Shopify**） | **本檔 §C.2 的 `translations.market_id` 欄**（承 29 §2.2 的 Adapt 覆寫；本尊官方能力＝Translate & Adapt 的 `marketLocalizationsRegister`，28:343） | 🔴 **裁定 10 推翻**：不做市場級內容覆寫（HK 英文＝CA 英文）⇒ 欄位**已刪**、UNIQUE 縮五欄（連帶修 MySQL nullable-UNIQUE 失效問題，SESSION-EXPORT §5.8）。resolve() 縮 4 層、L15 取消、I18N-6 反轉、V-201 翻轉、翻譯 CSV `market_handle` 降為純格式相容欄。**這是明知偏離**（形態比照 62 §F.3-1）：本尊有此能力、我方裁定不做；復活條件見 §C.2 沿革註釋。下游登記 §M M-5a | ✅ **本輪已改**（67＋70＋limits.yml＋原型同輪，不得只改一邊） |

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
| 同一市場多個語言 | HK 市場同時啟用 `zh-Hant`（預設）與 `en` | 若一市場一語言，62 §I.2 的碼粒度規則無從表達<!-- 依 2026-08-13 裁定改字。原文：「若一市場一語言，62 §I.2 的『多國市場 ⇒ 語言碼』規則無從表達」——括號裡引的那條規則已被裁定廢除（現為恆帶地區），但**本列的論點不變**：一市場一語言會讓 (market, locale) 這個對退化成 market，碼與前綴都失去語言那一維。 --> |
| 語言 ≠ 幣別 | `en` ＋ HK 市場 ⇒ 顯示 `HK$1,480.00` | 綁死 ⇒ 英文版顯示 `US$`（鐵律 10 ＋ 裁定二的直接違反，§H.1） |
| 語言 ≠ 法域 | `zh-Hant` ＋ HK 市場 ⇒ 走 `jurisdiction/hk`（無銷售稅、無政府發票，56 §B.1） | 綁死 ⇒ 繁中買家被套上 TW pack 的統一發票流程 |
| 市場的語言集合是**累加繼承**的 | 子市場的可用語言 ＝ 自身 ∪ 沿 lineage 上溯（29 §1.5，`market.inheritance_additive` 含 `web_presences`） | 用 `m.web_presences` 而非 `resolved_web_presences(m)` ⇒ hreflang 漏語言 ⇒ 雙向性破裂（62 §I.3(a) 已警告） |

**資料上的體現**：語言掛在 `shop_locales`（全店），市場的可用語言掛在 `market_web_presence_locales`（29 §1.4 已有），**兩張表是「全集」與「子集」的關係，不是兩份清單**。新增語言只動前者；把語言開給某市場才動後者。

🔴 **2026-08-13 裁定給了「子集」這件事一個名字與一組產品語義**：那個子集**就是對買家的語言白名單**（strawberrynet 模型）。⇒ 完整概念、admin 契約、繼承語義、以及「買家用直接 URL 進到未開放 locale 會怎樣」全部在 **§A.5**（概念與邊界）與 **§C.8**（資料模型）。🔴 **本節這句話一個字都不用改——裁定沒有推翻它，裁定是把它的下半截寫完。** 把白名單做成第三張表就是把這句話推翻掉（§C.8(a) 逐條說明後果）。

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

### A.5 ⭐ per-market 語言白名單（2026-08-13 裁定；strawberrynet 模型）

> **裁定逐字**（`ruling`）：「後台設定語言那裡，我新增語言後，不管是動態內容還是靜態內容，**我們可以在 admin 後台給不同地區指定客戶只能選擇哪些語言，前台不用全部顯示出來**。情況和 `https://www.strawberrynet.com/en-HK` 一樣。」

**(a) 三個集合，不是兩個**（§A.1 只寫了前兩個，裁定要求把第三個明確化）

```
① platform_locales            平台字典        —— 這個平台認得的語言（§C.1）
② shop_locales                商店啟用集      —— 這家店買了／開了哪些語言（§C.1）
③ market_locales（本節）      🔴 市場開放集   —— 這個市場的買家「能選」哪些語言
```
```
③ ⊆ ② ⊆ ①            三層真包含，🔴 任一層破了包含關係即資料錯誤（§C.8 有 CHECK）
```
- **② 與 ③ 分離的產品理由**（裁定明文）：商家可能為了做 SEO 或為了給內部員工預覽而啟用一個語言，但**還不想讓某個市場的買家看到它**。合成一個集合 ⇒ 商家一啟用日文，全世界所有市場的切換器立刻多一個日文選項。
- **② 與 ③ 分離的技術理由**：翻譯資料掛在 ②（`translations.locale_tag` 的值域是 `shop_locales`），**曝光決策掛在 ③**。把兩者合一 ⇒ 想關掉某市場的日文就得刪掉日文譯文。

**(b) 🔴 白名單是「呈現決策」，不是「存取控制」——這是本節最重要的一句**

```
🔴 白名單決定的是：切換器列什麼、hreflang 列什麼、sitemap 列什麼、地區重導的落點是什麼。
🔴 白名單**不**決定：一條已經存在的 URL 誰能打開。
```

**為什麼不可能做成存取控制**（三條，第一條是決定性的）：

1. **URL 是公開的物理事實。** `/en-hk/products/x` 這條 URL 存在、被索引、被外部連結指到。加拿大的買家把它貼進瀏覽器就會打開它。**「不讓加拿大客戶選英文」不可能靠隱藏一條全世界都看得到的 URL 來達成。**
2. **62 §0.2 原則 4 是硬不變量**：凡進 hreflang／sitemap 的 URL 必須對**任何**客戶端回 200。若「非本市場買家」拿到 404 或 302，Google 的爬蟲（它沒有市場身分）也會拿到 404 或 302 ⇒ 整組 hreflang 失效（62 §O REG-6 會紅）。
3. **`alt` 級對照樣本一致**：strawberrynet 的 `/en-HK` 對我方（非 HK 出口）的請求照樣回 200 並宣告 canonical 為 `/en-HK`（觀察日 2026-08-13，62 §附錄 B）。它**沒有**用 404 去隔離地區。

⇒ **真正把買家導到對的語言的機制有三個，白名單只是其中一個的輸入**：

| 機制 | 誰做 | 白名單在其中的角色 |
|---|---|---|
| **切換器只列開放語言** | 前台（§F.2） | 🔴 **唯一直接消費者**——裁定的「前台不用全部顯示出來」講的就是這一項 |
| **地區自動重導**（預設開，🔒 三條護欄不可關） | 62 §K.2 | 決定重導的**落點**＝目標市場的 `default_locale`（③ 的成員） |
| **hreflang** | 62 §I.1 | 決定矩陣的**成員**（③ ∩ published） |

**(c) 邊界情況：買家用直接 URL 進到一個「該市場沒開放」的 locale ⇒ 分兩種，處置不同**

🔴 **這一條直接影響 SEO，因為 hreflang 只能列可索引的 URL。把兩種情形混成一種是本節最貴的錯誤。**

| # | 情形 | 具體例（HK 市場開放 `zh-Hant`／`en`；CA 市場只開放 `en`） | 🔴 處置 | 理由 |
|---|---|---|---|---|
| **1** | **這個前綴根本不存在**（該 (market, locale) 組合不在 ③） | `/zh-hant-ca/products/x`（CA 市場沒開繁中） | 🔴 **404** | 前綴 ≡ (market, locale) 身分（§F.1(c)）。不存在的組合就是**沒有這條路由**——它不是「有頁面但不給看」，是**沒有頁面**。與 §F.1 的路由表是同一張表，不是另一套權限檢查 |
| **2** | **前綴存在，但屬於別的市場** | 加拿大買家開 `/en-hk/products/x` | 🔴 **200**（可能被地區重導攔**一次**，62 §K.2；爬蟲一律不攔） | 🔴 **這裡回 404 是嚴重事故**：`/en-hk/...` 是 HK 市場 hreflang 集合裡的成員，它必須對任何客戶端回 200（62 §0.2 原則 4）。**「該市場沒開放」對這條 URL 是無意義的判斷——這條 URL 不屬於加拿大市場，它屬於香港市場** |
| **3** | 曾經開放、後來被商家移除 | HK 市場移除 `en` 之後的 `/en-hk/...` | 🔴 **404**，並**同步**從 hreflang 與 sitemap 移除（62 §I.4 既有掛鉤 ＋ §I.3(b) 失效管線） | 跟隨 29 §1.2（`help`：自市場移除語言 ⇒ 該語言 URL 立即 404）。⚠ **410 是否更正確未查證 ⇒ V-224**；結案前用 404（跟隨本尊） |
| **4** | 語言在 ③ 但 `shop_locales.published = false` | 未發布語言 | 🔴 **404**（§F.1(d) 既有規則，不變） | 未發布語言只有預覽連結可見（29 §1.2） |

🔴 **三條連帶紀律**：
- **切換器永遠不會產生情形 1／3／4 的連結**（它只列 ③ ∩ published）⇒ 站內任何一條 404 的語言連結都是 bug，掛 lint（形態同 §F.4 的 `routes` lint）。
- 🔴 **不得用 302／301 把情形 1 導到該市場的預設語言。** 三個理由：①重導的 URL 不能進 hreflang（原則 4）而它看起來很像該進去；②Google 會把重導來源與目標視為同一頁，於是 `/zh-hant-ca/` 與 `/en-ca/` 被合併，**等於用重導製造了裁定要避免的那種混淆**；③商家改白名單時，一批 URL 從 200 變成 302 再變成 404，索引狀態抖三次。**404 一次到位。**
- **情形 2 的重導必須是 62 §K.2 那一條、而且只有那一條**（302、只攔一次、爬蟲不套用、EU ccTLD 例外）。🔴 **不得在白名單這一層再加一次重導**——兩層重導疊起來就是重導鏈，`seo.redirect_max_chain` 會開始告警，而且 debug 時完全看不出是誰導的。

**(d) 與 P0-02 市場父子繼承的互動：🔴 只能加，不能減**

29 §1.5：`web_presences` 是**累加繼承**（`limits.market.inheritance_additive` 已含它）。白名單掛在 web presence 上（§C.8(a)）⇒ **它自動沿用同一條語義**，不需要新的繼承規則。

```
open_locales(market M) = ⋃ over wp ∈ resolved_web_presences(M)  wp.open_locales
                          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 62 §I.3(a) 既有函式，不新增
```

| 問題 | 答案 | 理由 |
|---|---|---|
| 子市場繼承父市場的語言集？ | ✅ **是**，聯集 | `web_presences` 累加（29 §1.5）；白名單掛在 presence 上 |
| 子市場可以**加**語言？ | ✅ **可以**——在自己的 presence 上加 | 那是「自身 ∪ 上溯」的自身那一半 |
| 子市場可以**減**掉父市場開放的語言？ | 🔴 **不可以**（`limits.i18n.market_locales.subtractive_override_forbidden: true`） | 見下面三條 |

🔴 **為什麼禁止減法**（這是本節唯一一條「使用者可能會想要、而我方拒絕」的規則，所以理由要硬）：

1. **減法會讓 `resolved_*` 不再是聯集。** 62 §I.3(a) 的整套繼承正確性（REG-5）建立在「解析後集合 ＝ 自身 ∪ 祖先」這個純聯集上。加入例外集合後它變成 `(自身 ∪ 祖先) − 例外`，而例外是 per-market 的 ⇒ **hreflang 的雙向性再也不能靠「同一個函式產生同一個集合」來保證**（62 §I.1 不變量 2 的證明就沒了），只能逐對驗證。
2. **減法減不掉 URL。** 被「減掉」的語言，其 URL 屬於**父市場的 presence**——那條 URL 照樣存在、照樣回 200（上面 (b) 的物理事實）。⇒ 減法只能減掉「子市場切換器上的一個選項」，**卻讓商家以為自己關掉了一個語言版本**。🔴 **一個做不到它字面意思的開關，比沒有這個開關更糟。**
3. **想要窄，有正確做法**：**不要把那個語言開在父市場的 presence 上**，改為在需要它的每個子市場各自開。這是「白名單掛在 presence 而不是 market」這個設計的直接後果，也是它比較笨但比較誠實的地方。
   - 🔴 **admin UI 必須把這件事講出來**：子市場的語言列表要**分兩區**——「本市場開放」（可增刪）與「**繼承自 {父市場}**（唯讀，附「到 {父市場} 調整」連結）」。形態沿用 29 §1.5(d) 的繼承徽章，**不新造一套**。缺了這個分區，商家會在子市場頁找不到刪除按鈕，然後去客服說「壞了」。

**(e) 誠實的取捨（不寫「兩邊都好」）**

- ✅ 得到：切換器乾淨、hreflang 精確、地區重導落點明確、商家可以先啟用再逐市場放行。
- 🔴 **沒得到、也不打算得到**：**地區級的語言存取控制**。任何人都能打開任何一條已存在的語言 URL，這是 SEO 的要求（原則 4），不是我方偷懶。**若日後有真正需要「某地區看不到某語言」的合規要求（不是偏好），那是 jurisdiction pack 的能力（56 §A），不是白名單的延伸**——而且它會與 hreflang 直接衝突，必須在那時候當成一個新問題重新裁定。

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

1. **`region` 通常為 NULL。** 語言註冊的是**語言**；地區來自市場。只有語言本身確實因地區而不同（`pt-BR` vs `pt-PT`、`en-GB` vs `en-US` 的拼寫）才建帶 region 的條目。🔴 **不得**為了表達「香港的繁體中文」而建 `zh-Hant-HK`——那是 `zh-Hant` ＋ HK 市場，兩個維度（§A.1）。hreflang 的 `zh-Hant-HK` 由 62 §I.2 的 `hreflang_codes(market, locale)` **當場組出**，不是存起來的。

   > 🔴🔴 **2026-08-13 裁定之後，本條是全檔最容易被「好心改壞」的一條，所以在這裡把防線寫死。**
   >
   > 裁定的字面是「香港就是 `zh-Hant-HK`，台灣就是 `zh-Hant-TW`」。**照字面最自然的實作動作，就是往 `platform_locales` 裡插兩列 `zh-Hant-HK` 與 `zh-Hant-TW`。🔴 那是錯的，而且錯得很貴。**
   >
   > | | 若把 `zh-Hant-HK` 存進 `platform_locales`（❌） | 正確做法（✅ 當場組出） |
   > |---|---|---|
   > | 翻譯資料 | 🔴 **同一份繁中譯文要存兩次**（`zh-Hant-HK` 一份、`zh-Hant-TW` 一份）。商家改 HK 的商品標題，TW 不變——這正是 §A.1 第一列的反例欄已經寫過的事故 | 一份 `zh-Hant` 譯文，兩個市場共用（裁定 10：**內容不隨市場變**，`translations` 已無市場維度，§C.2<!-- 依裁定 10（2026-08-13 執行）修正，原文：「市場差異走 translations.market_id（Adapt 覆寫，§C.2）」 -->） |
   > | 新增市場 | 🔴 每開一個繁中市場就要**新增一個語言**（並為它把整套譯文再翻一次） | 開市場只動 `market_web_presence_locales` 一列 |
   > | fallback 鏈 | 🔴 `zh-Hant-HK` 缺譯時會截尾到 `zh-Hant`——但 `zh-Hant` 這一列**不存在譯文**（譯文都在兩個帶地區的列裡）⇒ 鏈走到底落回來源語言 ⇒ **繁中使用者看到英文** | 鏈只有一層，`zh-Hant` 直接命中 |
   > | 語言上限 | 🔴 `i18n.max_shop_locales: 20` 會被市場數吃掉 | 20 是語言數，與市場數無關 |
   >
   > **一句話**：🔴 **裁定管的是「輸出的字串」（URL 前綴與 hreflang 值），不是「儲存的身分」。** 恆帶地區發生在 `url_prefix()`／`hreflang_codes()` 這兩個**組字串的函式**裡（§F.1、62 §I.2），`platform_locales` 一列都不用加。**任何人看到 `platform_locales` 裡沒有 `zh-Hant-HK` 而想補上去之前，請先讀完上面那張表。**
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

  -- 🔴 五欄全 NOT NULL，唯一約束才真正生效（MySQL：nullable 欄進 UNIQUE ⇒ NULL≠NULL ⇒ 形同虛設）
  UNIQUE (shop_id, resource_type, resource_id, locale_tag, field_key),
  INDEX  (shop_id, locale_tag, outdated, resource_type),        -- 「列出某語言全部過期」
  INDEX  (shop_id, resource_type, resource_id, locale_tag),     -- 渲染期批次載入
  INDEX  (shop_id, locale_tag, review_required)                 -- 「列出未覆核機翻」
)
```

<!-- 🔴 依裁定 10（2026-08-12 裁定「不做市場級內容覆寫」；2026-08-13 執行刪欄）修正。
     原文兩處：
       欄位「market_id BIGINT NULL,   ‑- NULL=語言層；非 NULL=per-market 覆寫（29 §2.2 的 Adapt）」
       索引「UNIQUE (shop_id, resource_type, resource_id, locale_tag, market_id, field_key)」
     刪欄理由（兩條，缺一不足以刪）：
       ① 裁定 10 之後 market_id 永遠是 NULL——功能上死欄；
       ② MySQL 下 nullable 欄進 UNIQUE 索引等於沒約束（NULL≠NULL），同一 (resource, locale, field)
         可插多列語言層譯文，resolve() 變成不確定（SESSION-EXPORT §5.8）。
     🔴 防回退：Shopify 官方確實有此能力（Translate & Adapt 的 marketLocalizations*，29 §2.2、28:343）。
       這是「明知偏離」（唯一依據＝裁定 10，裁定 > Shopify），已登記於 §0.4 第 7 列與 §M M-5a。
       任何人拿 28/29 對照稽核想把欄位補回來之前，必須先推翻裁定 10。
     🔴 復活條件（日後真要做 Adapt 時，不是「加回一欄」就好）：
       ① market_id 不得以 nullable 形態回到 UNIQUE——必須 NOT NULL＋sentinel 0，或生成欄位
         IFNULL(market_id,0) 進唯一索引（m0 骨架 discount_applications 已有 COALESCE 先例），
         否則 ② 的 NULL≠NULL 問題原樣回來；
       ② 70 §D.5(b) 列的三條後果（[locale] 欄語義、欄數爆炸、單一 writer 驗證）要全部重做；
       ③ 翻譯 CSV 的 market_handle 匯入語義（V-201，§E.6(b)）要同步翻回。 -->

**三條說明**：

- ~~`market_id` 的語義不變~~ **`market_id` 欄已依裁定 10 移除**（沿革見上方註釋）。原型 `chilllove-admin-v2.html` 原「市場層覆寫優先於語言層翻譯」文案已同輪移除。
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
resolve(resource, field, locale L):
  1. translations[L]                            # 語言層翻譯
  2. for A in fallback_chain(L):                # §(a)，可能為空鏈
       translations[A]
  3. base row                                   # ＝ source locale 原文
  4. 仍為空 ⇒ 依 §B.1 的欄位類別決定：required→回 3 的值；optional→**不輸出整個欄位**
```

<!-- 依裁定 10（2026-08-13 執行刪欄）修正，原文：
     「resolve(resource, field, locale L, market M):
        1. translations[(L, M)]      # per-market 覆寫（Adapt）
        2. translations[(L, NULL)]   # 語言層翻譯
        3. for A in fallback_chain(L): translations[(A, M)] → translations[(A, NULL)]
        4. base row
        5. 仍為空 ⇒ …」
     鏈由 5 步縮為 4 步：market 維度整層消失（不是「M 恆為 NULL」——欄位已刪，§C.2）。
     🔴 resolve() 不收 market 參數。市場影響的是「曝光」（§A.5 的白名單）與「錢」（幣別/價格），
     不影響「內容」。任何人想把 M 加回簽名，先讀 §C.2 的沿革註釋。 -->

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

### C.8 `market_locales`：per-market 語言白名單的資料模型（§A.5 的落地）

**(a) 🔴 不新建表——`market_locales` 是既有 `market_web_presence_locales` 的邏輯名稱**

裁定用了 `market_locales` 這個名字。**我方採用這個名字作為概念名與 API 名，但實體沿用 29 §1.4 既有的 `market_web_presence_locales`**（`limits.i18n.market_locales.entity: market_web_presence_locales`，`separate_table_forbidden: true`）。

| 選項 | 後果 |
|---|---|
| ❌ 新建 `market_locales(shop_id, market_id, locale_tag, …)` | 🔴 **與 `market_web_presence_locales` 立刻不同步**。同一件事兩張表，且兩張表的**粒度不同**（market vs web presence）⇒ 一個市場有兩個 resolved presence 時，新表答不出「哪個 presence 上開放」，而 62 §I.1 的 `absolute_url(resource, wp, loc)` **需要那個答案**。這正是 §D.4(a) 拒絕「另建退役 handle 表」的同一條理由 |
| ✅ 沿用既有表 ＋ 補三欄 | 一張表、一個真相；繼承語義**免費**沿用 `market.inheritance_additive`（§A.5(d)）；62 §I.1 不用改資料來源，只改一個函式名（`wp.locales` → `open_locales(wp)`） |

🔴 **粒度是 presence 不是 market，這一點必須寫在程式碼註釋裡**：一個市場可以有多個 resolved presence（自身 ∪ 祖先），所以「市場的開放語言」是**聯集的結果**，不是一個可以直接 UPDATE 的欄位。任何 `UPDATE market_locales WHERE market_id = ?` 形態的寫入都是 bug。

```sql
-- 29 §1.4 既有表，本檔補三欄（🔴 鐵律 2：複合索引以 shop_id 開頭）
market_web_presence_locales(
  shop_id,                         -- 既有
  market_web_presence_id,          -- 既有
  locale_tag,                      -- 既有（FK → shop_locales(shop_id, locale_tag)，🔴 不是 platform_locales）
  position          INT NOT NULL,  -- 既有（29 §1.4 的 alternateLocales position）＝ 🔴 切換器顯示順序

  -- 🔴 本檔新增三欄 --------------------------------------------------------
  is_market_default BOOLEAN NOT NULL DEFAULT FALSE,  -- 該 presence 的預設 locale（見下 (b)）
  open_to_buyers    BOOLEAN NOT NULL DEFAULT TRUE,   -- §A.5 的白名單開關本身
  closed_at         DATETIME NULL,                   -- 關閉時點（§A.5(c) 情形 3 的 404 與失效掛鉤要用）

  UNIQUE (shop_id, market_web_presence_id, locale_tag),
  INDEX  (shop_id, locale_tag),                      -- 「這個語言開給了哪些市場」（關語言前的影響評估）
  -- 🔴 三層真包含（§A.5(a)）以 FK ＋ 應用層 CHECK 一起守：
  --    locale_tag 必須存在於 shop_locales(shop_id, locale_tag)  ⇒ ③ ⊆ ②（FK）
  --    shop_locales.locale_tag 必須存在於 platform_locales.tag  ⇒ ② ⊆ ①（既有 FK，§C.1）
  CONSTRAINT fk_mwpl_shop_locale FOREIGN KEY (shop_id, locale_tag)
    REFERENCES shop_locales(shop_id, locale_tag)
)
```

- 🔴 **`open_to_buyers` 是欄位不是「刪除該列」**：刪列會讓 `position` 與 `closed_at` 一起消失，而 §A.5(c) 情形 3 需要知道「這個組合曾經開過」才能決定 404 與失效範圍。**關閉是狀態轉換，不是刪除**（同 §D.4「舊 handle 永不回收」的紀律）。
- 🔴 **FK 指向 `shop_locales` 而不是 `platform_locales`**：這一條 FK 就是「③ ⊆ ②」這個不變量的執法點。指錯目標的話，商家可以把一個**沒有啟用**的語言開給市場，然後前台切換器上出現一個沒有任何譯文、也沒有 published 狀態的語言。

**(b) 每個 presence 的預設 locale：沿用既有欄位，不新增**

29 §1.4 的 `market_web_presences.default_shop_locale` **已經存在**。本檔的 `is_market_default` 與它**不是兩份真相**——`is_market_default = (locale_tag == market_web_presences.default_shop_locale)`，以生成欄位或 trigger 維持，理由是要一個能進**複合唯一索引**的形態：

```
UNIQUE (shop_id, market_web_presence_id, is_market_default) WHERE is_market_default
  -- 每個 presence 恰一個預設 locale；MySQL 用生成欄位模擬部分唯一索引（同 §C.1 shop_locales.is_source 的手法）
```
🔴 **預設 locale 必須 `open_to_buyers = true`**（應用層 CHECK）：關掉預設語言 ⇒ 地區重導沒有落點（62 §K.2）、`{% form 'localization' %}` 切國家後沒有語言可落（§F.2 最後一列）。試圖關閉預設 locale ⇒ `userErrors{code: MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED}`，訊息要求商家**先改預設再關**。

**(c) admin UI 契約（裁定的「在 admin 後台給不同地區指定客戶只能選擇哪些語言」）**

**位置：市場設定頁的「網域與語言」分區**（29 §1.5(d) 的繼承分區已在那裡；**不新開一個頁面**——語言白名單是市場設定的一部分，放到「設定 → 語言」那頁會讓商家找不到，因為那頁的心智模型是全店）。

| 元素 | 規格 |
|---|---|
| **兩個分區** | 🔴 **「本市場開放」（可增刪、可拖曳排序）** ＋ **「繼承自 {父市場}」（唯讀，附跳轉連結）**。形態沿用 29 §1.5(d)，不新造（§A.5(d) 第 3 條） |
| **可選值域** | `shop_locales` 中 `published = true` 的語言。🔴 **未發布語言不出現在這個選單裡**——把未發布語言開給市場沒有任何效果（前台仍 404，§A.5(c) 情形 4），只會製造「我開了為什麼沒用」 |
| **每列顯示** | `endonym`（`繁體中文`／`English`）＋ **該語言在該市場的翻譯進度徽章**（讀 `translation_status`，鐵律 7）＋ **它會產生的 URL 前綴**（`/zh-hant-hk`，§F.1）＋ **它會產生的 hreflang 碼**（`zh-Hant-HK`；多國市場顯示「N 個碼」可展開，62 §I.3(d)） |
| 🔴 **預設語言** | 單選（radio），恆為開放；改預設 ⇒ 顯示「這會改變本市場自動重導的落點」 |
| **排序** | 拖曳 ⇒ 寫 `position` ⇒ **前台切換器的順序**。🔴 這是商家唯一能控制切換器順序的地方，**不得**在前台另加一套排序規則（鐵律 7 的形態） |
| 🔴 **關閉語言的確認對話** | 必須顯示三個數字：**①將 404 的 URL 數**（該市場 × 該語言 × 可索引資源數）**②將從 hreflang 移除的條目數 ③該語言在該市場的既有譯文筆數（不會被刪，只是不再曝光）**。形態與理由同 §E.6(a) 的匯入預覽——**破壞性操作在按下確認前必須有一個數字**。第 ③ 個數字專門用來回答商家的「我的翻譯會不會不見」 |
| **開啟語言** | 不需要確認對話，但要顯示「將新增 N 個可索引 URL」（形態同 62 §J.3 的「本市場新增了 N 個可索引 URL」提示） |
| 🔴 **上限** | `limits.i18n.market_locales.max_per_market`（沿用 `i18n.max_shop_locales: 20` 作上界——③ ⊆ ② 已經保證了，這個鍵只是讓錯誤訊息說得出話） |

**(d) 寫入的連帶動作（🔴 缺一個就是一個看得見的 bug）**

```
開啟／關閉／改順序／改預設 locale  ⇒ 同一 transaction 內：
  1. bump  shop_locales_version(shop_id)        -- §G.3：全店快取失效（切換器出現在每一頁）
  2. 觸發  62 §I.3(b) 的失效管線                 -- hreflang 矩陣 ＋ sitemap 重生（去抖 5 分鐘）
  3. 關閉時：寫 closed_at，並把該 (market, locale) 的路由標記為 404（§A.5(c) 情形 3）
  4. 🔴 **不刪任何 translations 列**             -- 譯文是資產，曝光是決策，兩件事（§A.5(a)）
```
🔴 **第 2 步的觸發條件要加進 62 §I.3(b) 的清單**（既有清單只綁 market conditions）——這一條已登記在 §M-6，**本輪已於 62 §I.3(e) 補上**。

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

### E.2-1 ⭐ 翻譯輸入的**兩種 UI 模式**：堆疊式 vs 分頁式（2026-08-13 新增）

> **本節的證據來源**：Shopline 商品新增頁的 **ng-model 綁定**（`alt` 級，觀察日 2026-08-13，⇒ **V-226**）。
> 🔴 **鐵律 9 的界線在這裡要先講清楚**：下面引用的是**他家 UI 的資料綁定形態**——一個外部可觀察的介面事實，屬於「行為與資料形態的觀察」。**不引用、不移植他家的任何程式碼、樣式或文案**；我方的欄位命名、元件、樣板一律自寫（§H.5 有完整的界線表）。

**(a) 觀察到的事實**（`alt`，逐字保留綁定字串作為證據，🔴 **這些不是我方的識別字**）

| 觀察到的綁定 | 索引 | ⇒ 對應的 UI 模式 |
|---|---|---|
| `product.title_translations[lang]` | `[lang]`（對語言集合 repeat） | 每語言一個輸入框，同時可見 |
| `product.summary_translations[lang]` | `[lang]` | 同上 |
| `product.preorder_note_translations[lang]` | `[lang]` | 同上 |
| `product.description_translations[currentEditLang]` | `[currentEditLang]`（綁「當前編輯語言」） | 單一輸入框，內容隨 tab 切換 |
| `product.seo_title_translations[currentEditLang]` | `[currentEditLang]` | 同上 |
| `product.seo_description_translations[currentEditLang]` | `[currentEditLang]` | 同上 |
| `product.seo_keywords` | **無 `_translations` 後綴** | ⇒ **該欄位不翻譯** |

```
[lang]            = 對語言集合 repeat  ⇒ 🔵 堆疊式（stacked）：N 個輸入框並列，各自標語言
[currentEditLang] = 綁當前 tab        ⇒ 🔵 分頁式（tabbed）：1 個輸入框，N 個 tab
```

**(b) 判準 —— 🔴 這是我方推導，不是觀察到的規則**

Shopline 的畫面只告訴我們**哪些欄位用了哪一種**，**沒有告訴我們它的判準是什麼**。下面這條判準是我方從那個對應關係反推的，**必須標為推導**（`limits.i18n.admin.translation_input_mode.*`）：

| 模式 | 用在 | 🔵 推導出的判準 | 為什麼（我方的理由，不是他家的） |
|---|---|---|---|
| **堆疊式** | 短的單行欄位：`title`、`summary`／副標、選項名、選項值、`FILTER.label`、`MENU/LINK.title`、圖片 `alt` | **單行 ∧ 短（≤ 一行輸入框）∧ 欄位數少** | 🔴 **一次看完所有語言，才看得出「這三個是不是同一件事」**——譯錯語言、貼錯欄位、漏一個語言，全部一眼可見。這正是 §E.1「兩層語言不得連動」那個事故（把中文打進英文版標題）的**視覺防線**：兩個框並排時，把中文打進標著「English」的那個框需要刻意 |
| **分頁式** | 長內容／富文本／整組欄位：`body_html`、`seo_title` ＋ `seo_description`（**整組**）、政策本文、通知範本、主題 `THEME_LOCALE_CONTENT` 的一個 group | **富文本 ∨ 多行長文 ∨ 「一組要一起看的欄位」** | 三個富文本編輯器堆疊 ＝ 三個工具列、三倍高度、捲軸永遠在錯的位置；**而且富文本編輯器實例化成本高**（N 個實例 × 每個都要載入圖片挑選器）。SEO 那一組要分頁**不是因為長，是因為它是一組**——標題與描述必須一起讀才判斷得出來 |

🔴 **兩條硬規則，任一違反都是回退**：

1. **模式是 UI 的事，🔴 不影響資料模型**（`mode_does_not_affect_schema: true`）。兩種模式寫進去的都是 §C.2 的 `translations(resource_type, resource_id, locale_tag, field_key, value)` 列。<!-- 依裁定 10（2026-08-13 刪欄）修正，原文五元組含 market_id -->**分頁式最容易被實作成「一個語言一份 JSON blob」**（因為 tab 天然對應「一份文件」）——那會同時破壞：欄位級的 `source_digest`（§C.5）、欄位級的 `outdated`、`translation_status.translated_fields` 的分子、以及翻譯 CSV 的逐欄位列（§E.6(b)）。**四樣東西一起壞，而且要到匯出的時候才會發現。**
2. **堆疊式的每個輸入框必須標語言**（`stacked_label_suffix: endonym`）：`商品名稱 (English)`／`商品名稱 (繁體中文)`，用 `platform_locales.endonym`（§C.1）**不是**用語言碼、**不是**用國旗（國旗 ≠ 語言，鐵律 11 的同一條精神——`en` 不屬於任何一個國家）。

**(c) 🔴 兩種模式共用一個元件契約，且與 §E.2 的「上原文／下譯文」雙段形態相容**

§E.2 已定：非來源語言下，每個可翻欄位變成上下兩段（上＝來源語言原文唯讀、下＝譯文輸入）。**這一條在兩種模式下都成立，不打架**：

```
堆疊式：來源語言那一格本身就是原文 ⇒ 其餘語言各自在自己的框上方顯示原文（或以「原文」列置頂一次）
分頁式：來源語言 tab 顯示 base row；其餘 tab 的編輯區上方固定顯示原文（可摺疊，長文預設摺疊）
🔴 兩者共用 29 §2.4 翻譯後台「逐 key 雙欄」的同一個元件（§E.2 已定「兩者共用同一個元件」）
   ——本節只是為它加了第二種佈局，不是加了第二個元件
```

🔴 **不採用 Shopline 的欄位命名形態**（`*_translations[lang]` 這種「以欄位後綴 ＋ 語言索引」表達譯文）。理由不是鐵律 9，是資料模型：以欄位為單位的 map 表示法無法承載我方 `translations` 表的六個稽核欄（`outdated_severity`／`value_source`／`review_required`／`source_locale_tag`／`updated_by_staff_id`／`updated_at`，§C.2）。<!-- 依裁定 10（2026-08-13 刪欄）修正，原文尚有一句「也無法承載 market_id 這一維（per-market Adapt 覆寫）」——該維度已隨刪欄消失，六稽核欄的論證獨立成立，結論不變。 -->**他家的形態對他家的模型是自洽的；照抄形態會把我方的模型壓扁。**

**(d) `seo_keywords` 沒有 `_translations` ⇒ 這是「哪些欄位可翻譯」的一手級佐證，與 §B 對照**

`seo_keywords` 是該畫面上**唯一**沒有 `_translations` 後綴的欄位 ⇒ 在他家模型裡它**不可翻譯**。與使用者提供的 Shopline CSV 一致（`SEO Keywords` 是單一欄、無語言後綴）——**兩個獨立來源指向同一個結論，這在 `alt` 級證據裡算強的**。

**與 §B.2 逐欄對照（🔴 出入全部列出，不挑好的講）**：

| Shopline 欄位（`alt`） | 該處的可翻性 | 我方 §B.2 | 出入 | 處置 |
|---|---|---|---|---|
| `title` | 可翻 | `PRODUCT.title` **必翻** | ✅ 一致 | — |
| `description` | 可翻 | `PRODUCT.body_html` **必翻** | ✅ 一致 | — |
| `seo_title` / `seo_description` | 可翻 | `meta_title` / `meta_description` **可選** | ✅ 一致（分類不同是我方的三分類更細，不是衝突） | — |
| 🔴 `seo_keywords` | **不可翻** | **我方沒有這個欄位** | ⚠ **出入 1（形態不同，結論同向）**：我方**根本不提供 meta keywords**——62 §E 的欄位只有 title／description，`content.*` 也沒有 keywords 鍵。⇒ 兩邊都不翻，但我方是「沒有這個欄位」，他家是「有但不翻」 | 🔴 **不新增這個欄位**。若日後有人以「Shopline 有」為由要加：meta keywords 對搜尋引擎早已無效，加了它就要回答「它要不要翻」，而正確答案是「不要」——**加一個不翻的 SEO 欄位是純負債**。本條登記於 §M-10 |
| 🔴 `summary` | 可翻（**堆疊式**） | **我方 `PRODUCT` 沒有短摘要欄位**（`summary_html` 只出現在 `PAGE`／`ARTICLE`／`BLOG`） | ⚠ **出入 2（真缺口，但不是 i18n 的缺口）**：商品層是否要有短摘要／副標是 **13／63 的欄位決策**，不是本檔能定的 | 🔴 **本檔不新增商品欄位**（13／63 有別的 owner）。登記於 §M-10 ＋ **V-227**。**但先寫下 i18n 面的答案**：若日後加了，它是**必翻 ＋ 堆疊式**（短單行，(b) 的判準直接適用） |
| 🔴 `preorder_note` | 可翻（**堆疊式**） | **我方沒有預購功能** | ⚠ **出入 3（功能缺口，不是欄位缺口）** | 同上，登記 §M-10。i18n 面的答案：預購說明是**必翻**（買家據以決定要不要下單的文字，缺了頁面不成立）＋ 堆疊式 |
| **`handle`** | 🔴 **該畫面上未觀察到 `handle_translations`** | 我方 **不可翻**（§D.3） | 🟡 **同向，但這是弱佐證**：商品新增頁上 handle 可能根本不在畫面上 ⇒ **「沒看到」不等於「沒有」** | 🔴 **不得**把這條寫成「Shopline 也不翻 handle 所以我方對了」。§D.3 的依據**只有裁定**，一個字都不改（§D.3 表格「偏離的依據」欄已寫死） |

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
        market_handle(≈Market，純格式相容欄), status(≈Status), source_text(≈Default content，唯讀參考),
        translated_text(≈Translated content), source_digest(🔴 我方獨有)
  status ∈ {translated, outdated, untranslated}（本尊三值）；**純輸出**，匯入時忽略 ⇒ ⚠ V-201
  🔴 market_handle：匯出**恆空白**；匯入時**空白＝唯一合法值**，非空白 ⇒ 拒絕該列並明示
     「本平台不做市場級內容覆寫（裁定 10）」。欄位保留只為對齊本尊 8 欄的檔案格式。
     （依裁定 10 於 2026-08-13 定；原「留空⇒拒絕」的保守處置已翻轉，沿革見 §M V-201 列）
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

**(a) 兩個字串函式，語義不同，🔴 仍然不得互相借用——但理由在 2026-08-13 裁定後整條換掉了**

```
url_prefix(web_presence, locale)    → 路由用。本檔定義（下表）。回傳 **一個字串**
hreflang_codes(market, locale)      → 標註用。**62 §I.2 已定義，本檔不重寫**。回傳 **一個 Set**
```

<!-- 🔴 依 2026-08-13 locale 碼裁定改寫本段（62 §I.2）。
     原文（保留供追溯，**任何人不得改回**）：
       「兩者由**同一對 (market, locale)** 推導，字面上常常長得很像（`/zh-hant-sg` vs `zh-Hant-SG`），
         但規則來源不同：前者受路由與可讀性約束，後者受 Google 的碼合法性約束
         （62 §I.4 的白名單、禁 `EU`／`UK`／`es-419`）。**借用會在第一個多國市場上出錯**：
         多國市場的 hreflang 是語言碼（`en`），但它的 URL 前綴仍需要能區分市場。」

     🔴 **原文最後那句話（決定性的那句）在裁定後已經不成立**：多國市場的 hreflang 不再是裸 `en`。
        ⇒ 原本「不得互借」最硬的那條理由消失了。
     🔴 **本輪的任務就是重新確認一次「兩者是否仍需分離」——結論是：仍需，而且新理由比舊的更硬。**
        舊理由是「值域在某個情形下不同」（一個可以用特例分支繞過去的差異）；
        新理由是「**基數不同**」（1 vs N，那不是分支能繞過去的，那是型別不同）。 -->

🔴 **本輪重新確認的結論：仍然必須分離，而且新理由比舊理由更硬。**

| 判準 | `url_prefix()` | `hreflang_codes()` | 可否合併 |
|---|---|---|---|
| 🔴 **基數（決定性）** | **恰 1 個字串**——一條路由不可能是一個集合 | **N 個碼**（多國市場逐國展開，62 §I.2）；EU 27 國市場 ⇒ 27 個 | 🔴 **不可**。`1 : N` 不是值域差異，是**型別差異**。合併後函式必須回 Set，而路由層拿到 Set 只能取 `.first`——**那一行 `.first` 就是 bug 的全部**（它會在第一個多國市場上選到一個看起來對的國家） |
| **大小寫** | **全小寫**（`/zh-hant-hk`）——URL 路徑大小寫敏感，混用會造成同一頁兩條 URL | **Title case script ＋ 大寫地區**（`zh-Hant-HK`）——Google 不區分大小寫，但一致性讓 diff 測試可行（62 §I.2） | 🔴 不可（合併後要在呼叫端做大小寫轉換，等於把規則搬到每一個呼叫點） |
| **值域約束** | 不得與第一路徑段衝突（`products`／`cart`／`.well-known`…）；`UNIQUE (shop_id, domain_id, url_prefix)` | Google 碼合法性：拒 `EU`／`UK`／`es-419`（62 §I.4）；🔴 **驗證器另須「認得」裸碼以巡檢外部標註**（62 §I.4） | 🔴 不可（兩組約束無交集，合併後的驗證器要同時滿足兩邊 ⇒ 取交集 ⇒ 兩邊都變嚴，且沒人說得出為什麼） |
| **輸入** | `(web_presence, locale)`——**presence 級**（同一市場的兩個 presence 有**不同**前綴） | `(market, locale)`——**market 級**（同一市場的兩個 presence 產生**相同**碼，那正是 62 §I.3(c) 情形 2 的殘留衝突源） | 🔴 不可（連參數都不同一個東西） |
| 相同處 | 都由同一對 (market, locale) 推導；都恆帶地區；字面常常很像 | 同左 | ⇒ **共用「組字串的原料」，不共用函式** |

🔴 **允許的共用只有一項**：兩者都必須從**同一個** `(market, locale)` 解析結果出發（`RequestContext`，§A.3），且都必須經過同一個 `region_of(market)` 取地區碼。**共用原料、不共用出口**——這與 §D.5「`Handles::Generate` 與 Liquid `handleize` filter 不得共用實作」是同一條紀律的第二個實例。

> **驗收**：`SF-9`（新增）——對一個三國多國市場的同一個 (market, locale)，`url_prefix()` 必須回傳恰一個字串、`hreflang_codes()` 必須回傳三個碼；🔴 **測試中不得出現任何把後者取 `.first` 餵給路由的路徑**（以型別禁止：`url_prefix` 的簽名不接受 `Set`）。

**(b) `url_prefix` 的規則 —— 🔴 恆帶地區，永不裸語言前綴**（2026-08-13 裁定）

<!-- 🔴 依 2026-08-13 使用者裁定整表改寫。裁定逐字（重點句）：
       「不同地區如果同樣有英文，那就在 url 加入識別，香港就是 en-HK，如果加拿大，那就是 en-CA；
         共用繁體中文，那香港就是 zh-Hant-HK，台灣就是 zh-Hant-TW，以此類推。
         這是考慮到之後 SEO，和進行區分，避免被 google 等搜索引擎誤判為重複頁面。」

     本表原文（保留供追溯，🔴 **任何人不得改回**）：
       | primary market ＋ shop 預設語言 | **（無前綴）** | 29 §2.5 |
       | primary market ＋ 其他語言 | `/{locale_slug}` — `/en`、`/zh-hans` | 29 §2.5「primary 其他語言 → `/{lang}`」 |
       | 次級市場（子資料夾） | `/{locale_slug}-{subfolder_suffix}` — `/zh-hant-sg` | 29 §1.2 |
       | 子網域／獨立網域市場 | defaultLocale 在根、alternate 在 `/{locale_slug}` | 29 §2.5 |
       locale_slug = BCP-47 標籤全小寫，連字號保留    zh-Hant → "zh-hant"    en → "en"

     🔴 **原表忠實復刻了 Shopify／29 §2.5 的模型，它沒有寫錯——它是被裁定換掉判準的。**
        原表有兩處與裁定直接衝突：
          ① 「primary market ＋ 其他語言 ⇒ `/en`」——那正是裁定說的「同樣有英文卻不加識別」；
          ② 「primary market ＋ 預設語言 ⇒ 無前綴」——根路徑與帶前綴頁並存 ⇒ 真重複（62 §I.2-2 結論 3）。
        ⇒ 這同樣是**明知偏離 Shopify**，登記在 62 §I.2-1（碼）與本節（前綴）。
        29 §1.2 的 XOR 約束**沒有被推翻**，被推翻的只有「語言-only 子資料夾」那一半（62 §J.1 已改）。 -->

```
🔴 url_prefix(wp, loc) = "/" + downcase( locale_tag(loc) + "-" + region_of(wp.market) )
   ——恆帶地區、恆有前綴、無例外。與市場是不是 primary 無關、與語言是不是預設無關。
```

| 情境 | 🔴 前綴（新） | ~~舊~~ | 依據 |
|---|---|---|---|
| primary market（HK）＋ 預設語言 `zh-Hant` | `/zh-hant-hk` | ~~（無前綴）~~ | 裁定 ＋ V-221 |
| primary market（HK）＋ `en` | `/en-hk` | ~~`/en`~~ | 🔴 裁定逐字 |
| 次級市場 CA ＋ `en` | `/en-ca` | ~~`/en-ca`~~（形態相同但**推導路徑不同**：舊的是「語言 ＋ subfolderSuffix」，新的是「語言 ＋ market 地區」） | 裁定 |
| 次級市場 TW ＋ `zh-Hant` | `/zh-hant-tw` | ~~`/zh-hant-tw`~~（同上） | 🔴 裁定逐字 |
| 子網域／獨立網域市場 | 🔴 **一樣帶前綴**（`ca.example.com/en-ca/`、`example.ca/en-ca/`） | ~~defaultLocale 在根~~ | 見下「為什麼獨立網域也要帶」 |
| **多國市場 EU（FR/DE/BE）＋ `en`** | 🔴 **前綴只有一個**（`/en-eu`？`/en-fr`？）⇒ **見下面的 (b-2)，這是本次修改唯一沒有被裁定直接回答的洞** | — | ⚠ **V-225** |

```
locale_tag 全小寫，連字號保留        zh-Hant → "zh-hant"    en → "en"
region 全小寫                        HK → "hk"              TW → "tw"
結果一律匹配                         ^/[a-z]{2,3}(-[a-z]{4})?-[a-z]{2}$
```

**🔴 為什麼獨立網域／子網域也要帶前綴**（這一條看起來多餘，其實是防回退的關鍵）：`example.ca` 只賣加拿大，語言前綴看起來是廢話。但 ①**同一個網域上可以有多語言**（`example.ca/en-ca/` 與 `example.ca/fr-ca/`），一旦其中一個沒有前綴，兩者的路由規則就不對稱；②**根路徑一旦是內容頁，就與帶前綴頁重複**（62 §I.2-2 結論 3）；③`url_prefix()` 變成部分函式（有時回空字串）⇒ **每一個呼叫點都要處理空字串**，而那正是 hreflang／sitemap／canonical／`routes` drop 四處各自長出一套拼接邏輯的起點。**恆有前綴讓這個函式是全函式，這比省掉六個字元有價值得多。**

🔴 **根路徑 `/` 的處置**（`limits.i18n.locale_prefix.root_path_behavior: redirect_to_default_prefix`）：

```
GET /            ⇒ 302 → /{預設 market 的預設 locale 前綴}/      （不是 301：預設市場會變）
GET /products/x  ⇒ 302 → /{預設前綴}/products/x                  （保留路徑）
🔴 根路徑**不是內容頁**：不進 sitemap、不進 hreflang、不作為 x-default 的目標（62 §I.2 已改）
🔴 爬蟲**不豁免**這個重導——它與 62 §K.2 的地區重導是兩件事：
   地區重導是「依訪客推測市場」（🔒 爬蟲不套用，因為它會讓不同客戶端看到不同內容）；
   根重導是「這條路徑沒有內容」（對所有客戶端相同）⇒ **不套用爬蟲豁免是正確的，且必須如此**
   ——若對爬蟲回 200，爬蟲會索引一個與 /{預設前綴}/ 逐位元組相同的頁面，那就是自製重複。
```
⚠ **這一條是我方推導，不是裁定明文** ⇒ **V-221**（裁定只說「url 加入識別」，沒說根路徑）。`alt` 佐證：strawberrynet 未觀察到裸根內容頁（62 §附錄 B）。🔴 **結案前照上面實作**——它是三個選項中唯一不製造重複的那個。

**(b-2) ⚠ 多國市場的前綴：唯一沒被裁定回答的洞（V-225）**

裁定舉的四個例子（`en-HK`／`en-CA`／`zh-Hant-HK`／`zh-Hant-TW`）**全部是單國市場**。多國市場（一個 web presence 服務 FR/DE/BE）只有**一條 URL**，但 `region_of(market)` 有三個值。三個選項：

| 選項 | 前綴 | 問題 |
|---|---|---|
| A. 用 presence 的 `subfolderSuffix`（商家自填） | `/en-eu` | 🔴 `EU` 不是 ISO 3166-1 國碼，62 §I.4 明文拒（Google 常見錯誤清單）。**前綴不是 hreflang 碼，所以嚴格說不違規**——但兩者字面幾乎相同，日後一定有人把它當碼用 |
| B. 取市場的「代表國」 | `/en-fr` | 🔴 對德國買家顯示 `en-fr`，看起來像錯的；且「代表國」沒有非任意的選法 |
| ✅ **C. 用 presence 的 `subfolderSuffix` 但強制它是 ISO 3166-1 國碼或明確的非國碼標記** | `/en-eu`（並在 admin 明示「`eu` 不是國家碼，它只是這個市場的識別字」） | 需要 admin 文案；且要在 lint 層擋住有人把它送進 hreflang |

**我方暫採 C**（`limits.i18n.locale_prefix.multi_country_region_source: web_presence_subfolder_suffix`），理由：①它是**唯一不需要平台替商家做任意選擇**的選項；②`hreflang_codes()` 那邊已經逐國展開（62 §I.2），所以**碼那一維是對的，前綴這一維只需要唯一與穩定**；③它與 29 §1.2 的既有 `subfolderSuffix` 欄位相容，不加欄位。🔴 **連帶硬規則**：`url_prefix` 的輸出**永遠不得**被當成 hreflang 值使用（`limits.i18n.locale_prefix.never_reused_as_hreflang_code: true`，這就是 (a) 那張表的可執行形態）。⚠ **待使用者裁定 ⇒ V-225**。

> ⚠ **V-162 已由本裁定結案的部分**：「Shopify 對帶 script subtag 的語言用什麼子資料夾字串」這個問題，**對我方已無決策意義**——裁定直接給了 `zh-Hant-HK`／`zh-Hant-TW`，我方前綴即 `/zh-hant-hk`／`/zh-hant-tw`。🔴 **結案理由是「裁定覆蓋」，不是「查到了」**（比照 62 §F.3-1 對 V-119 的處置紀律）。本尊用什麼仍然未知，只是我方不再需要那個答案；若日後做 Shopify 遷移工具，需要重開（併入 V-162 的殘留）。

**(c) 唯一性、保留字，與 🔴 「前綴 ≡ (market, locale) 身分」**

```
UNIQUE (shop_id, domain_id, url_prefix)          -- 兩個 (market, locale) 不得產生同一前綴
url_prefix ∉ handle.reserved_first_segments      -- products / collections / pages / blogs / cart /
                                                 -- checkout / account / search / apps / .well-known / …
🔴 反向也必須成立（本輪新增，恆帶地區的直接紅利）：
   url_prefix ⇒ 恰一個 (market, locale)          -- 前綴是身分，不只是裝飾
   `limits.i18n.locale_prefix.prefix_is_market_locale_identity: true`
```

🔴 **「前綴 ≡ 身分」是恆帶地區換來的最大一項結構收益，它讓 §A.5(c) 的邊界情況變成一行路由查表**：

```
路由解析：剝第一路徑段 → 查 (shop_id, domain_id, prefix) → 命中 ⇒ (market, locale)，繼續
                                                        → 未命中 ⇒ 🔴 404（§A.5(c) 情形 1／3／4 全部走這裡）
```
- **在舊規則下這件事做不到**：`/en` 這個前綴在 primary market 是「英文」，但它不帶市場資訊 ⇒ 市場要另外從 GeoIP／cookie 推 ⇒ **同一條 URL 對不同人是不同市場 ⇒ 不同幣別、不同價格、不同 hreflang**。那正是 §F.2 開頭那條「同一 URL 對不同人回不同語言」事故的**市場維度版本**，而且它更嚴重（金額會變）。
- ⇒ 🔴 **恆帶地區順手修掉了一個 §F.2 沒能覆蓋的洞。** 這一點值得寫下來，因為它是本次裁定**技術上**最站得住的收益（比動機句那個 SEO 因果站得住得多，62 §I.2-2）。
- 🔴 **連帶紀律**：市場**不得**再從 GeoIP／cookie 推導（`limits.i18n.locale_prefix.market_determined_by: url_only`）。GeoIP 的唯一用途是 62 §K.2 的**一次性重導建議**，與 §F.2 對 `Accept-Language` 的處置完全對稱。

**(d) 餵給 62 §I.1 的東西——本檔只提供這三樣**

```
1. resolved_web_presences(m) 的每個 wp 上的**開放且已發布**的 locale 集合 ⇒ 62 §I.1 的 `open_locales(wp)`
   來源：market_web_presence_locales（29 §1.4 ＋ 本檔 §C.8 補三欄），
        條件 open_to_buyers = true ∧ shop_locales.published = true，
        且**沿 lineage 累加**（62 §I.3(a) 已警告過）
   🔴 依 2026-08-13 白名單裁定，本項從「wp 上的 locale 集合」收窄為「開放集」（§A.5）
2. absolute_url(resource, wp, loc) = origin(wp) + url_prefix(wp, loc) + canonical_path(resource)
   canonical_path = "/products/" + handle   ← 🔴 handle 不含語言（§D.3），所以這是純拼接
   🔴 url_prefix 恆非空（(b)）⇒ 本式不再有「前綴為空時要不要多一個斜線」的邊界情形
3. 只有 published = true **且 open_to_buyers = true** 的語言進矩陣
   🔴 未發布／未開放語言的 URL 不進 hreflang、不進 sitemap、且 **404**
      （29 §1.2「自市場移除語言 → 該語言 URL 立即 404」＋ §A.5(c)）
      ——因為 62 §0.2 原則 4 要求矩陣內每個 URL 對任何客戶端回 200
```
<!-- 🔴 依 2026-08-13 裁定改寫下面這句（原句已不成立）。原文（保留供追溯）：
       「**本檔不重寫 `hreflang_set()`、不重寫碼粒度規則、不重寫 `dedupe_codes`。**」
     🔴 本輪**三樣全部動了**，但**改的人是 62 號自己**（62 §I.1／§I.2／§I.3(c) 已同輪改完）。
        分工原則沒有變：碼的規則在 62、前綴的規則在 67。本檔仍然不在這裡重寫它們的內容，
        只在此標示「它們已經改了、去哪裡讀」——否則下一個人會照這句話以為 62 §I 還是舊的。 -->
🔴 **2026-08-13 更新**：碼粒度規則、`hreflang_set()` 的簽名、`dedupe_codes` 的殘留衝突處置**本輪三樣都改了**，改在 **62 §I.1／§I.2／§I.2-1／§I.2-2／§I.3(c)**——**本檔仍然不重寫它們**，分工不變（碼在 62、前綴在 67）。**本檔與 62 的接縫只有三個**：`open_locales(wp)`（§C.8）、`url_prefix()`（(b)）、以及下面這條失效掛鉤。**改任一邊都必須同輪改另一邊**（只改碼不改前綴 ⇒ 62 §I.1 不變量 1 自指破裂；只改前綴不改碼 ⇒ 不變量 4 可達性破裂）。

語言的新增／發布／取消發布**與 per-market 白名單的開關**必須掛上 62 §I.3(b) **既有的**失效管線（market conditions 變更 ⇒ 矩陣與 sitemap 失效，去抖 5 分鐘）——本檔只補一句：**該管線的觸發條件要加上 `shop_locales` 與 `market_web_presence_locales` 的變更**，否則商家發布了新語言，hreflang 會停在舊值好幾天（同 62 §I.3(b) 已警告的病根）。

### F.2 語言偵測與切換

| 項 | 規則 | 依據 |
|---|---|---|
| 自動重導（**語言維度**） | 🔴 **不做**（`i18n.storefront.auto_redirect_on_language: false`）。<!-- 依 68 號 §C-3 修正理由（2026-08-12）。原文：「🔴 **不做**（地區自動重導預設關閉已由 62 §K.2 定案，Google 明文建議避免）。**語言維度同樣不自動重導**」🔴 **值不變，理由必須換**：原文把「語言不重導」掛在「地區也不重導」上，而**地區的預設已翻成啟用**（62 §K.2）。不改這行，下一個人會照著括號裡那句話把語言也一起翻開——那是 Shopify **明文預設停用**的東西。 -->✅ **這一條本來就與 Shopify 一致**：本尊**預設停用自動語言偵測**（`help`，68 §C-3），只有**地區**重導預設啟用。**兩個預設值方向相反，不得連動。** | 62 §K.2（地區維度已翻為預設啟用）＋ `help` |
| `Accept-Language` | **只用來決定「要不要顯示建議橫幅」與切換器的預設高亮**，🔴 **不得改變同一 URL 的輸出內容** | 本檔〔ours〕 |
| Cookie | 同上：只影響建議橫幅是否再顯示。🔴 **不得**讓 cookie 決定頁面語言 | 本檔〔ours〕 |
| 切換器 | 必須是**真實 `<a href>`**，指向目標語言的完整 URL | 62 §K.2 已定（爬蟲發現其他版本的路徑之一） |
| 🔴 **切換器的內容**<br>（2026-08-13 裁定） | **只列「當前市場開放且已發布」的語言**（`open_locales(當前 wp)` ∩ published，§A.5／§C.8），依 `position` 排序，顯示 `endonym`。<br>🔴 **不列全店啟用語言**——裁定逐字「前台不用全部顯示出來」。<br>🔴 **切換器產生的每一條連結都必須回 200**：它只列開放語言 ⇒ 它**在定義上不可能**產生 §A.5(c) 情形 1／3／4 的 404 連結。站內任何一條 404 的語言連結都是 bug ⇒ 掛 lint（形態同 §F.4 的 `routes` lint）。<br>🔴 **語言切換器與地區切換器是兩個控件**，不得合成一個——理由見下方註 | `ruling` ＋ §A.5(b) |
| `Vary` | 🔴 頁面內容不隨 `Accept-Language` 變 ⇒ **不得輸出 `Vary: Accept-Language`**。輸出它等於把快取切成 N 份卻沒有任何內容差異（§G） | 本檔〔ours〕 |
| 建議橫幅 | 必須是 **locale-invariant 片段**（client-side 渲染或獨立快取），否則它會把 `Accept-Language` 重新拉回快取鍵 | 本檔〔ours〕 |
| `{% form 'localization' %}` | 兩個欄位名（`country_code`／`language_code`）都要收 | 25 號坑 #4、29 §4 |
| 切國家導致語言不支援 | 落到該市場的 `defaultLocale` | 29 §4 |

🔴 **語言切換器 vs 地區切換器：兩個控件，一個表單**（2026-08-13，`alt` 對照 ＋ 我方定案）

`alt` 觀察（strawberrynet，62 §附錄 B）：該站 header 只有**一個**合併的「Country / Region」控件。**我方不採用這個形態**，理由三條：

1. **兩個維度的後果不同。** 換語言只換文字；換地區換的是幣別、稅、運費、可購品項、法域（§A.1 三個正交維度）。合成一個控件 ⇒ 買家想看英文，結果連幣別一起變了——**這是 §E.1「兩層語言不得連動」在前台的同一個事故形態**（那裡是後台 UI 語言 vs 內容語言，這裡是語言 vs 市場）。
2. **25 號坑 #4 的既有結論已經預設兩個欄位**：`{% form 'localization' %}` 有 `country_code` 與 `language_code` **兩個**欄位名（29 §4），兩個都要收。前台合成一個控件，Liquid 那一層仍然是兩個欄位 ⇒ 主題與平台的模型不一致。
3. **恆帶地區讓合併看起來更誘人，所以要明文擋住**：前綴 `en-hk` 字面上就是「語言＋地區」，很容易被實作成「一個下拉列出所有前綴」。🔴 **前綴的形態是 URL 的事實，不是 UI 的規格**（`limits.i18n.market_locales.switcher_is_two_controls: true`）。

✅ **允許的形態**：兩個控件放在**同一個 `<form>`／同一個彈出層**（視覺上是一組，語義上是兩個欄位），提交後一次解析。**改地區時，若當前語言不在新市場的開放集 ⇒ 落到新市場的 `default_locale`**（29 §4 既有規則，本輪只補上「開放集」這個限定詞）。

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
| 8 UI 值 | 語言切換器用既有 tokens 與 Lucide icon，本檔不新增視覺值。🔴 **§H.5(b) 紅線 3 明文擋住「為了相容而讓我方視覺長得像 Dawn」** |
| 🔴 **9 法律紅線** | 兩節，**分工不同不得混讀**：**§H.3** ＝ 文案面（不抄 Shopify／Ella 的字串）；**§H.5** ＝ 命名契約面（✅ 對齊主題 class 名與 API 欄位名，🔴 不複製樣式表內容與說明文字）。判準兩節共用一條：**這個字串有沒有被別人的程式碼比對** |
| 11 法域 | §A.3 正交；本檔無任何國別分支 |

---

### H.5 ⭐ 鐵律 9 的界線：**可以對齊命名契約，不可以複製樣式表內容**（2026-08-13 新增）

> **緣由**：使用者 2026-08-13 說：「商品參數或者接口必須百分百的和 shopify 一樣，例如什麼 `product__section-title` `product-title` 之類的」。
>
> 🔴 **這句話裡有兩件不同的東西，規格必須先把它們拆開，否則整條會撞上鐵律 9。** 拆開之後兩件事的答案**都是「對齊」，但對齊的東西不同、依據不同、紅線的位置也不同**。

**(a) 先把「參數／接口」拆成三類（🔴 使用者舉的那兩個例子不屬於同一類）**

| 類別 | 例 | 它其實是什麼 | 誰擁有它 |
|---|---|---|---|
| **① 主題端的 class 名／DOM 契約** | `product__section-title`、`product-title`、`data-option`、`swatch-*` | **佈景主題（Dawn／Ella）的 CSS class 與 DOM 結構** | 🔴 **商家／第三方**（主題是商家買來或自己改的資產） |
| **② API 契約層的識別字** | GraphQL `title`／`bodyHtml`／`variants`／`userErrors{field,message,code}`／`gid://`／enum 值 | **admin／storefront API 的欄位與型別名** | 平台（我方） |
| **③ 主題端的 Liquid 物件／filter 面** | `product.title`、`{{ … \| handleize }}`、`routes` drop | **Liquid 相容層的介面** | 平台（我方），但**形狀由本尊定義** |

🔴 **`product__section-title` 與 `product-title` 是 ①，不是「admin API 參數」。** 它們不出現在任何 API 回應裡，它們出現在**主題渲染出來的 HTML** 上。把它們當成「API 參數要對齊」去讀，會讓人去改 GraphQL schema——那是完全找錯地方。

**(b) ① 主題 class 名：✅ 渲染出主題期待的字串是「相容性需求」，🔴 但不得複製樣式表**

```
🔴 可以（而且必須）：我方渲染出主題期待的 class 名與 DOM 結構
🔴 不可以：把 Shopify／Dawn 的 CSS 規則（選擇器 → 宣告 → 值）複製進我方的任何檔案
```

| | 內容 |
|---|---|
| **為什麼必須做** | 主題的 CSS、主題的 JS 選擇器、**以及商家自己寫的自訂 CSS**（後台「自訂 CSS」欄、`theme.liquid` 內的 `<style>`）全部靠 class 名選中元素。我方若改寫或省略 class，**商家的自訂 CSS 靜默失效**——不報錯、不空白，只是樣式沒套上。這與 §D.5 的 `handleize` 事故是**同一個形態**（`data-option=""` ⇒ 選擇器碰撞 ⇒ 變體選錯而不報錯），也與 §B.3-3 的 `Default Title` 是**同一條紀律**（被程式碼比對的字串是契約，不是文案） |
| **判準（沿用 §H.3 既有那條，只是把「程式碼」擴到「第三方資產」）** | 🔴 **它是否被第三方資產（主題 Liquid／主題 CSS／主題 JS／商家自訂 CSS）比對或選取？**<br>是 ⇒ **契約字串**（必須逐字產生）；否 ⇒ **文案**（一律自寫） |
| 🔴 **紅線 1：class 名 ≠ 樣式** | class 名是**介面**（一個字串），樣式是**內容**（一組宣告與值）。我方輸出 `class="product-title"` **不涉及任何 Shopify 的著作物**；我方複製 `.product-title { font-size: 1.5rem; letter-spacing: … }` **就是抄 Shopify／Dawn 的 CSS**（鐵律 9 明文禁止）。**兩者的界線是「有沒有帶著值」。** |
| 🔴 **紅線 2：class 名的來源是主題，不是平台** | ⇒ 我方**不維護、也不對外宣告一份「Shopify class 名清單」**。我方要做的是兩件**被動**的事：①**不改寫主題輸出的 class**（渲染引擎原樣輸出主題寫的字串）②**平台注入的 wrapper 不覆蓋、不包壞主題的 class 與 DOM 層級**（62 §A.1 的平台 JSON-LD 注入已有同一條「只能新增節點」的紀律）。<br>🔴 **主動去產生一份 Dawn class 名清單並照著渲染 ＝ 把主題的責任搬到平台身上**，那既做不完（每個主題都不同），又會在第一個非 Dawn 主題上壞掉 |
| 🔴 **紅線 3：不得讀成「我方預設主題要長得像 Dawn」** | 鐵律 8：UI 值一律取自 `docs/design/23-interaction-css-spec.md` §1 的 tokens，不自創也不外抄色值與尺寸。**相容性只作用在「主題吃得到我方的資料與 DOM」這一面，不作用在「我方自己的視覺」那一面**（CLAUDE.md 開宗明義：功能邏輯 1:1，**視覺用自有設計語言**） |
| **驗收** | golden theme＝Ella（`test/fixtures/themes/ella-7.2.0`，已購授權 fixture）：渲染輸出中主題寫的 class 逐字保留（diff 測試）；平台注入的節點**不出現在**主題 section 的容器內部。形態沿用 27 §8 十條與 31 §6 矩陣 |

**(c) ② API 欄位名：✅ 對齊命名與形狀，🔴 但錯誤訊息的字串內容一律自寫**

這一半**本來就是既有規則，不是新規定**——鐵律 4（API-first）已定 `resourceVerb` 命名、`userErrors{field,message,code}`、cursor 分頁、`gid://chilllove/{Type}/{id}`；契約全文在 `docs/research/28`。本節只補**界線**：

| 對齊 | ✅ 對齊 | 🔴 不對齊（一律自寫） |
|---|---|---|
| **欄位名／型別名／enum 值** | `title`、`bodyHtml`、`variants`、`ProductStatus.ACTIVE` | — |
| **錯誤的形狀** | `userErrors{field, message, code}`；HTTP 恆 200 | — |
| **錯誤碼字面值** | ✅ 對齊本尊已有的碼；🔴 我方新增的碼自己命名（本檔已新增五個：`LOCALE_LIMIT_EXCEEDED`／`SOURCE_LOCALE_IMMUTABLE`／`FIELD_NOT_TRANSLATABLE`／`PLACEHOLDER_MISMATCH`／`HANDLE_TAKEN`，§H.4） | — |
| 🔴 **`message` 的字串內容** | — | 🔴 **一律自寫**（鐵律 9 ＋ 鐵律 10 繁中為主）。`code` 是契約、`message` 是文案，**同一個物件裡兩個欄位分屬兩邊** |
| 🔴 **文檔描述文字** | — | 🔴 一律自寫。API 文檔不得逐句轉貼 shopify.dev |
| 🔴 **GID 的 namespace** | — | 🔴 `gid://chilllove/…`，**不是** `gid://shopify/…`（鐵律 4 已定） |

**(d) 一張表講完界線（🔴 三個反例，每個都是真的會有人做的事）**

| 動作 | 判定 | 為什麼 |
|---|---|---|
| 渲染出 `<h1 class="product__title">` 因為 Ella 的 CSS 選這個 class | ✅ **可以** | 契約字串（被第三方資產比對）。等同 §B.3-3 的 `Default Title` |
| 把 Dawn 的 `base.css` 貼進我方預設主題 | 🔴 **禁止** | 抄 CSS（鐵律 9 明文）。而且違反鐵律 8（UI 值要取自 23 號 tokens） |
| 把 GraphQL 欄位取名 `bodyHtml` 而不是 `descriptionHtml` | ✅ **可以** | API 契約對齊（鐵律 4）。**這是相容性，不是抄襲**——欄位名是介面 |
| 把 shopify.dev 的欄位說明逐句貼進我方 API 文檔 | 🔴 **禁止** | 抄文案（鐵律 9）。**同一個欄位名可以用，說明它的那段話不可以** |
| 把 Shopify 的 `locales/en.default.json` 內容當成我方預設主題的字串 | 🔴 **禁止** | §H.3 已定。Ella 的 locale 檔是測試 fixture，**其字串不得進入我方預設主題或平台 bundle** |
| 我方渲染時把主題寫的 `class="foo"` 改寫成 `class="cl-foo"` 加前綴 | 🔴 **禁止** | 這不是鐵律 9 的問題，是**相容性事故**：主題與商家自訂 CSS 全部失效（本節 (b) 的核心） |

🔴 **一句話版本**（`limits.naming_contract.*` 是它的可執行形態）：**介面（名字、形狀）可以一樣，內容（樣式值、文案、說明）一律自寫。判準是「這個字串有沒有被別人的程式碼比對」——是就是契約，不是就是文案。**

## I. 落地：里程碑對應

| # | 項目 | 里程碑 | 依賴 | 驗收 |
|---|---|---|---|---|
| L1 | `platform_locales` ＋ `shop_locales`（含 `is_source`）＋ 標籤驗證 | **M0**（表）/ **M1**（後台） | — | 新增語言不需改碼（I18N-2） |
| L2 | `Handles::Generate` ＋ `resource_handles` ＋ 唯一性 ＋ 退役集合比對 | **M1** | 62 §B.5 `url_redirects`（M0 建表） | HDL-1～HDL-9 |
| L3 | `translations` 表（六個新欄）＋ digest 正規化 ＋ 過期分級 | **M1** | — | I18N-4／I18N-5 |
| L4 | fallback 鏈解析器（唯一實作）＋ 遙測 | **M2** | L3 | I18N-3 |
| L5 | `translation_status` 物化 ＋ 商品列表翻譯欄 | **M2** | L3 | AD-4（四個出口同源） |
| L6 | 商品編輯頁內容語言切換器 ＋ 非來源語言唯讀規則 | **M2** | L4／L5 | AD-1～AD-3 |
| L7 | URL 前綴路由 ＋ `routes` drop ＋ 切換器 ＋ `Vary` 紀律<br>🔴 **含恆帶地區的前綴規則、根路徑重導、「前綴 ≡ (market, locale) 身分」路由表**（§F.1(b)(c)）<!-- 依 2026-08-13 裁定補。🔴 **不得拆成兩期**：先做裸語言前綴再改成帶地區＝一次 URL 全站搬遷（每一條都要 301），而 M2 之後就有可索引內容了。 --> | **M2**（i18n P0，HANDOFF §5 已列） | L1 | SF-1～SF-4、**SF-9** |
| **L7b** | 🔴 **per-market 語言白名單**：`market_web_presence_locales` 補三欄 ＋ 市場設定頁兩分區 UI ＋ 切換器只列開放語言 ＋ 關閉語言的三數字確認（§A.5／§C.8）<!-- 依 2026-08-13 裁定新增。 --> | **M2**（與 L7 同批——白名單是路由表的**內容**，路由表先做出來會是空的） | L1／L7 ＋ 29 §1.4 既有表 | 62 §O **REG-11** 四條 |
| L8 | Liquid 三層字串 ＋ tolerant JSONC parser ＋ 逐檔 fallback | **M2** | 31 號 lint 管線 | SF-5／SF-6 |
| L9 | 快取維度降維 ＋ `touched_dimensions` 斷言 ＋ 新 `cache_stamp` 來源 | **M2** | 63 §D.3 | I18N-10／I18N-11 |
| L10 | hreflang 的語言維度接入（餵 62 §I.1）＋ 語言變更的失效掛鉤 | **M2**（單市場多語言，62 S11 已列） | L7 | 62 §O REG-1／REG-2／REG-7 |
| L11 | 翻譯後台（資源樹 ＋ 雙欄 ＋ outdated 標示） | **M2** | L3～L5 | 29 §2.4 形態 |
| L12 | 翻譯 CSV 匯入匯出（digest 比對、🔴 **空白＝不動作、清空走 `__CLEAR__`、覆寫走 `overwrite_existing` 顯式旗標** ＋ 選擇性匯出 ＋ 匯入預覽四鍵）<!-- 依 69 §V-182（B-3 二次反轉，§E.6 定案）修正，原文：「空白＝清空／缺席＝不變更」——那是 68 輪的中間態，B-3 反轉回 true 時本列漏改，與 §E.6(b) 直接矛盾（2026-08-13 grep 補出）。上一層 68 註釋保留：「選擇性匯出與清空計數不是加分項」的結論仍成立，它們現在的用途是界定 overwrite 的爆炸半徑。 --> | **M5** | L3 | AD-7、AD-7b、AD-8、AD-9 |
| L13 | 機器翻譯 provider ＋ 批次 ＋ 稽核欄 | **M5** | L3 | AD-5／AD-6 |
| L14 | 繁簡轉換工具（含歧義報告） | **M5** | L13 的批次骨架 | AD-6 |
| ~~L15~~ | ~~per-market 翻譯覆寫（Adapt，`market_id` 非 NULL）~~ **已依裁定 10 取消**（不做市場級內容覆寫；欄位已刪，§C.2 沿革）。🔴 **29 §8 的 P1 清單仍列著它——那是 research 檔（證據）不改，不代表要做**；要復活先推翻裁定 10，見 §C.2 復活條件 | ~~M5~~ | — | ~~I18N-6~~ |
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

**2026-08-13 依 locale 碼裁定 ＋ per-market 白名單裁定 ＋ 鐵律 9 界線的鍵變更**
🔴 **這一組的依據是「使用者裁定」，不是查證，也不是跟隨 Shopify。** 其中 `i18n.locale_prefix.*` 是本檔第二處明知偏離本尊（第一處＝handle 的 `ascii_only`，62 §F.3-1）。

> 🔴 **2026-08-31 更正（包 32；鐵律 19.5）**：本節標題「本輪已落鍵」對下表這一組**當時不實**——
> 2026-08-13 只改了規格文字，`i18n.locale_prefix.*`／`i18n.market_locales.*`／
> `i18n.admin.translation_input_mode.*`／`naming_contract.*` 四組**從未寫進 `config/limits.yml`**
> （可重跑驗證：對 2026-08-31 前任一 commit `git grep -c locale_prefix -- config/limits.yml` ＝ 0）。
> 四組已隨包 32 於 2026-08-31 實際落鍵；`naming_contract` 落為 limits **§24**（原文寫 §23，
> 該編號其時已被商品 CSV 區塊佔用）。原文照鐵律 19.5 保留不改。

| 鍵 | 原值 → 新值 | 依據 | 本檔落點 |
|---|---|---|---|
| 🔴 `i18n.locale_prefix.*`（**新子區塊**） | 新增：`always_region_qualified: true`／`bare_language_prefix_forbidden: true`／`format`／`case: lowercase`／`root_path_behavior: redirect_to_default_prefix`／`root_redirect_status: 302`／`prefix_is_market_locale_identity: true`／`market_determined_by: url_only`／`unknown_prefix_status: 404`／`never_reused_as_hreflang_code: true`／`multi_country_region_source` | 裁定 2026-08-13（§F.1(b)）＋ 我方推導兩處（根路徑 ⇒ **V-221**、多國市場前綴 ⇒ **V-225**） | §F.1(b)(b-2)(c) |
| 🔴 `i18n.market_locales.*`（**新子區塊**） | 新增：`entity: market_web_presence_locales`／`separate_table_forbidden: true`／`grain: web_presence`／`inheritance: additive_only`／`subtractive_override_forbidden: true`／`whitelist_is_presentation_not_access_control: true`／`switcher_lists_open_locales_only: true`／`switcher_is_two_controls: true`／`unopened_prefix_status: 404`／`other_market_prefix_status: 200`／`close_requires_impact_counts: true`／`close_does_not_delete_translations: true`／`max_per_market` | 裁定 2026-08-13（§A.5） ＋ `alt` 對照（strawberrynet，⇒ **V-223**） | §A.5、§C.8 |
| 🔴 `i18n.admin.translation_input_mode.*`（**新子區塊**） | 新增：`stacked_for`／`tabbed_for`／`mode_does_not_affect_schema: true`／`stacked_label_suffix: endonym`／`no_flag_icons: true` | `alt`（Shopline ng-model 綁定，⇒ **V-226**）＝**形態的觀察**；🔵 **判準是我方推導**（§E.2-1(b)） | §E.2-1 |
| 🔴 `naming_contract.*`（**新頂層區塊 §23**） | 新增 | 鐵律 9 的界線（§H.5）。**獨立成頂層區塊的理由與 `handle:` 相同**：它同時被 14／25／27／31（主題）、28（API 契約）、62／67 引用，塞進任一方都會讓其餘的人跨區塊引用「別人的鍵」 | §H.5 |
| ~~`seo.hreflang.region_qualified_when_single_country_market`~~ | **刪除** ⇒ `seo.hreflang.always_region_qualified: true` ＋ `bare_language_code_forbidden: true` 等六鍵 | 裁定（62 §I.2）。🔴 **鍵名裡有「single_country_market」就是舊模型的化石**，留著會讓人以為多國市場還有另一種行為 | 62 §I.2、§I.3(c) |

---

## K. 驗收清單

### K.0 對照 `docs/specs/11` §0 七維度

| 維度 | 本模組的最低標準 |
|---|---|
| **1 安全** | 翻譯寫入需 `staff` 權限且過 shop scope；🔴 **匯入的譯文一律當不可信輸入**——富文本走與商品描述同一條淨化管線（譯文是最容易被當成「已經是自家內容」而漏掉淨化的入口）；MT provider 金鑰走 Rails credentials；公開端點（語言切換）無狀態 |
| **2 資料完整** | `translations` **五欄唯一索引（五欄全 NOT NULL——nullable 欄不得進 UNIQUE，SESSION-EXPORT §5.8）**<!-- 依裁定 10（2026-08-13 刪 market_id）修正，原文：「六欄唯一索引」 -->；`shop_locales` 的 `is_source` 部分唯一；handle 唯一索引 ＋ 退役集合比對；來源語言遷移全程 transaction 且缺譯保留原文；FK 到 `platform_locales` |
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
| I18N-3 | **fallback 鏈** | 逐分支：語言 → 截尾鏈 → 來源原文 → 依欄位類別<!-- 依裁定 10（2026-08-13 刪欄）修正，原文首分支「per-market →」已隨欄位消失 -->；🔴 `zh-Hant` 缺譯**不得**取到 `zh-Hans`；🔴 `zh-Hant-HK` 不得截到 `zh` |
| I18N-4 | 過期偵測不誤報 | 對來源做「僅空白／僅屬性順序」變更 ⇒ `severity = none`，零筆被標記 |
| I18N-5 | 過期不影響渲染 | 標記 outdated 後前台輸出不變 |
| I18N-6 | **translations 無市場維度**（反向斷言） | schema 斷言：`translations` 表不存在 `market_id` 欄；resolve() 簽名不收 market 參數；同一 (resource, locale, field) 在**所有市場**輸出逐位元組相同<!-- 依裁定 10（2026-08-13）反轉本條，原文：「per-market 覆寫優先：同一 (resource, locale) 有市場覆寫時，該市場取覆寫、其餘取語言層」。原正向驗收已無受測物，改為防回歸斷言。 --> |
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
| **AD-1b** | 🔴 **翻譯輸入的兩種模式不影響 schema**（2026-08-13，§E.2-1） | ①短單行欄位（`title`）以**堆疊式**呈現，每個輸入框標題帶 `endonym` 後綴（`商品名稱 (English)`），🔴 **不得用國旗**；②富文本／SEO 組以**分頁式**呈現；🔴 ③**兩種模式寫入後，`translations` 表的列數與欄位粒度必須相同**——以分頁式編輯 `body_html` 後，該資源的 `(locale, field_key)` 仍是**逐欄位一列**，不得出現任何「一個語言一份 JSON blob」的列；④分頁式編輯後 `source_digest`／`outdated`／`translation_status.translated_fields` 三者仍逐欄位正確（🔴 這一條是 ③ 壞掉時唯一會亮的燈） |
| **AD-1c** | 🔴 **per-market 語言白名單的 admin 契約**（2026-08-13，§C.8(c)） | ①市場設定頁分兩區：「本市場開放」（可增刪、可拖曳）＋「繼承自 {父市場}」（**唯讀**，有跳轉連結）；②子市場**無法**移除繼承來的語言（前端無按鈕 ＋ 後端拒絕，雙層）；③可選值域只含 `published = true` 的語言；④關閉語言的確認對話顯示**三個數字**（將 404 的 URL 數／將移除的 hreflang 條目數／既有譯文筆數）且與實際相符；⑤關閉市場預設 locale ⇒ `MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED`；⑥拖曳排序後**前台切換器順序**跟著變（同一個 `position`，鐵律 7） |
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
| **SF-9** | 🔴 **前綴恆帶地區 ＋ 兩個函式不得合併**（2026-08-13） | ①全站輸出的內部連結、`routes` drop、canonical、sitemap 中，**任一 URL 的第一路徑段不匹配 `^[a-z]{2,3}(-[a-z]{4})?-[a-z]{2}$` 即紅燈**（含「沒有第一路徑段」＝裸根內容頁）；②`GET /` 與 `GET /products/x` ⇒ **302 到帶前綴 URL**，且根路徑不在 sitemap／hreflang 內；③對一個**三國多國市場**的同一 (market, locale)：`url_prefix()` 回**恰一個字串**、`hreflang_codes()` 回**三個碼**；🔴 ④**型別禁止合併**——`url_prefix` 的簽名不接受 `Set`，任何 `hreflang_codes(...).first` 形態的呼叫在 lint 掃描中即紅燈 |
| **SF-10** | 🔴 **前綴 ≡ (market, locale) 身分**（2026-08-13） | ①以同一條帶前綴 URL、三種不同 GeoIP 出口與三種 cookie 請求 ⇒ **解析到的 market 必須相同**（跟隨重導後比對；`market_determined_by: url_only`）；②**幣別**因此也必須相同（這一條同時守鐵律 3／§H.1：市場一飄，金額字串就飄） |
| **SF-11** | 🔴 **未開放／未發布 locale 的處置四情形**（2026-08-13，§A.5(c)） | ①該 shop 不存在的 (market, locale) 前綴 ⇒ **404**（🔴 不得 302）；②**別的市場**的合法前綴 ⇒ **200**（測試須跟隨地區重導後再判；回 404 即紅燈）；③曾開放後關閉 ⇒ **404** ＋ 已從 hreflang／sitemap 移除（去抖窗內）；④未發布語言 ⇒ **404**。🔴 ⑤四種情形下**譯文列一筆都不得被刪除**（關閉語言後重新開啟，譯文必須原樣回來） |

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
| ~~**V-162**~~<br>⚠ **決策面已由裁定覆蓋，事實面仍未知** | ~~Shopify 對帶 script subtag 語言（`zh-Hant`／`zh-Hans`）使用的 URL 子資料夾字串~~ | help.shopify.com/manual/markets；實測 | <!-- 依 2026-08-13 locale 碼裁定改寫。原處置：「我方用 `/zh-hant`／`/zh-hans`（理由見 §F.1(b)），**不用 `/zh-tw`**」——那個處置的前提（前綴可以是裸語言）已被裁定消滅。 -->🔴 **裁定直接給了答案**：`zh-Hant-HK`／`zh-Hant-TW` ⇒ 我方前綴 `/zh-hant-hk`／`/zh-hant-tw`。**本尊用什麼我方不再需要知道** ⇒ 決策面結案。<br>🔴 **結案理由是「裁定覆蓋」，不是「查到了」**（比照 62 §F.3-1 對 V-119 的處置紀律——兩者在日後重審時意義完全不同）。<br>**殘留**：做 Shopify 遷移工具時需要本尊的前綴字串以產生 301 對照表 ⇒ 屆時重開 | §F.1(b) |
| 🔴 **V-221**<br>（2026-08-13，與 62 §附錄 A 同號同條） | **根路徑 `/` 在恆帶地區之後應該是什麼**（裁定只說「url 加入識別」，沒說根路徑）。三選一見 62 §附錄 A V-221 | **使用者裁定**（產品決策，查本尊沒用——本尊的模型是「primary 預設語言在根」，前提不同）；`alt` 佐證：strawberrynet 無裸根內容頁 | 採 `root_path_behavior: redirect_to_default_prefix`（302）。🔴 理由：它消滅系統內**最大的一組真重複**（`/` 與 `/zh-hant-hk/` 逐位元組相同），收益比碼粒度大（62 §I.2-2 結論 3） | §F.1(b) |
| 🔴 **V-225**<br>（2026-08-13 新增） | **多國市場的 URL 前綴用什麼地區碼**——裁定舉的四個例子全是單國市場（`en-HK`／`en-CA`／`zh-Hant-HK`／`zh-Hant-TW`），**多國市場只有一條 URL 但有 N 個國家**，裁定沒有涵蓋 | 使用者一句話裁定 | 暫採 **C：用 presence 的 `subfolderSuffix`**（`/en-eu`），並在 admin 明示「這不是國家碼」；🔴 連帶 `never_reused_as_hreflang_code: true`（碼那一維已由 62 §I.2 逐國展開處理，前綴這一維只需唯一與穩定）。三個選項的完整比較見 §F.1(b-2) | §F.1(b-2) |
| **V-226**<br>（2026-08-13 新增） | **Shopline 翻譯輸入模式的判準**——我方從 ng-model 綁定（`alt`）反推出「短單行 ⇒ 堆疊、長內容／整組 ⇒ 分頁」，🔴 **但那是推導，他家的實際判準未知**（也可能根本沒有判準，只是歷史累積） | 無可靠途徑（他家的內部設計決策）。**替代途徑＝我方自己的可用性測試** | 🔴 **不需要結案，也不打算結案**：`alt` 級來源本來就不能據以寫死實作（§0.3）。**§E.2-1(b) 的判準是我方的，理由也是我方自己寫的**（一次看完所有語言 vs 富文本實例化成本）——他家的判準是什麼**不影響我方**。本條登記的用途是防止日後有人把 §E.2-1(b) 引用成「Shopline 的規則」 | §E.2-1 |
| **V-227**<br>（2026-08-13 新增） | **商品層是否要有短摘要（`summary`）與預購說明（`preorder_note`）欄位**——Shopline 兩者都有且都可翻（`alt`），我方兩者都沒有 | **13／63 的欄位決策**，不是 i18n 的決策 | 🔴 **本檔不新增商品欄位**（13／63 有別的 owner，鐵律：不改別人的檔）。**但 i18n 面的答案先寫下來**：若日後加了，`summary` ＝ 必翻 ＋ 堆疊式；`preorder_note` ＝ 必翻（買家據以決定要不要下單）＋ 堆疊式。登記於 §M-10 | §E.2-1(d)、§B.2 |
| ~~**V-163**~~<br>✅ **主體已結案**（69 §V-182） | ~~Shopify **原生**是否提供翻譯 CSV 匯入匯出、格式與欄位、以及**空白語義**~~<br>🔴 **已答（`help`，69 §V-182）**：**有**原生匯出／匯入，位置在 **Settings → Languages**（不在 Translate & Adapt app 裡——**68 號因此找不到，這正是它誤判「原生能力薄弱或不存在」的原因**）；**8 欄** ＋ `Status` 三值（`Translated`／`Outdated`／`Untranslated`）；匯入的核心是**「覆寫既有翻譯」勾選框**；匯出以 email 非同步寄出。**官方對「Translated content 留空會怎樣」完全沒寫** ⇒ 承接到 **V-200**。<br>**殘留**：XLIFF 官方格式是否存在（我方列 P2） | ~~help.shopify.com Translate & Adapt 子頁~~ ⇒ **已由 69 號在 `localization-and-translation` 頁查到**；XLIFF 殘留仍需 help 逐頁 | <!-- 二次修正。68 §B-3 的處置是：「🔴 空白＝清空、缺席＝不變更（§E.6(a) 三件套）」，依據是 Matrixify（`press`）；並註明「若查出官方原生行為不同，本條要重判（連 blank_means_unchanged 一起）」——**69 §V-182 正是那個觸發條件，本條依該註記重判**。 -->我方 CSV ＋ 強制 `source_digest` ＋ 🔴 **空白＝不動作、清空走 `__CLEAR__`、覆寫走顯式旗標**（§E.6(a)）；欄位對齊本尊 8 欄 ＋ `status` 三值；XLIFF 列 P2 | §E.6、§C.5(f) |
| 🔴 **V-200**<br>（承 69 號登記） | 本尊的 `Translated content` **留空**時，在「勾選覆寫」與「不勾選」**兩種模式下分別**做什麼（官方 help 對此完全沉默——**這是本尊模型裡唯一沒寫清楚的一格**） | dev store 實測：匯出 → 清空一列 → 兩種模式各匯入一次 → 看譯文是否消失 | 🔴 我方**不**把空白解讀成刪除（`blank_means_unchanged: true`）；刪除必須是另一個明示動作（`__CLEAR__`）。**即使日後查出本尊在勾選覆寫時會刪，也不得自動跟隨**——不可逆操作由易誤觸狀態觸發，屬產品決定，需使用者裁定 | §E.6(a)① |
| 🔴 **V-201**<br>（承 69 號登記） | 本尊的 `Status` 欄在**匯入**時是否被讀取（還是純輸出欄）；以及 `Market` 欄**留空**的語義 | 同 V-200（dev store 實測） | `status` **純輸出**，匯入時忽略（§C.5(f)：過期狀態只能由 digest 決定，不能由檔案宣稱）；`market_handle` **空白＝唯一合法值**（我方無市場覆寫，匯出恆空白）；**非空白 ⇒ 拒絕匯入該列**，訊息明示「本平台不做市場級內容覆寫（裁定 10）」<!-- 依裁定 10（2026-08-13 刪欄）翻轉，原處置：「market_handle 留空 ⇒ 拒絕匯入該列（保守做法：留空可能是『套用到所有市場』也可能是『漏填』）」。🔴 翻轉理由：刪欄後所有匯出檔的 Market 欄恆空白，維持原處置＝每一列都被拒＝匯入功能整個失效。原處置的兩難（所有市場 vs 漏填）在無市場維度後不存在。本尊語義的實測問題（Status 欄）保留待查。 --> | §C.5(f)、§E.6(b) |
| **V-164** | `translationsRegister` 在 `translatableContentDigest` 不符時的官方行為（拒絕？寫入並標過期？） | shopify.dev mutation 頁的錯誤碼表 | 我方**寫入並標 outdated ＋ review_required**（§E.6）。不得靜默當成最新 | §C.5、§E.6 |
| **V-165** | 商家可新增的語言集合是否封閉（Shopify 是否只允許其支援清單內的語言） | help.shopify.com 語言設定頁；`shopLocaleEnable` 的錯誤碼 | 我方**開放**（裁定明文「可自行添加任何語言」），只驗 BCP-47 格式與禁用碼 | §A.2、§C.1 |
| **V-166** | MySQL 8 可用的中文排序 collation（是否有 `utf8mb4_zh_0900_as_cs`、其排序依據是拼音或筆畫） | MySQL 官方文檔；實機 `SHOW COLLATION` | 沿用預設 collation，UI 標「依系統順序」，**不宣稱拼音或筆畫排序** | §C.7 |
| **V-167** | RTL 語言在 Shopify 主題的支援形態（平台注入 `dir` 或全由主題負責） | shopify.dev 主題架構頁；實測 | `platform_locales.direction` 欄位先就位；主題層落地排 M6；匯入 degradation report 標示主題是否有 RTL 樣式 | §C.1、§I L18 |
| **V-168** | 多語言下站內搜尋的官方行為（是否只搜當前語言、譯文是否進索引） | help.shopify.com 搜尋頁；實測 | 我方：per-locale 索引、只搜當前語言、無結果時提示跨語言搜尋（不自動） | §C.7 |
| **V-169** | 官方機翻「限 2 種語言」的現況與依據（29 §2.4 記載，本輪未覆核） | help.shopify.com Translate & Adapt | 以 `limits` 鍵表達，**不寫死**；我方不必對齊該限額 | §E.5(a) |
| **V-170** | 通知信語言解析的官方優先序（顧客語言 vs 訂單語言 vs 市場預設） | shopify.dev 通知範本頁；實測 | 我方：`customers.locale` → 訂單 `locale_snapshot` → shop source locale | §F.5 |
| **V-171** | Shopify 是否提供官方的繁簡自動轉換（若有，其方向與品質標示） | help.shopify.com 語言頁 | 我方做成獨立工具（§E.5(c)），寫入真實譯文列且標 `script_conversion` | §E.5(c) |

---

## M. 與既有規格的衝突登記

<!-- 依 2026-08-13 裁定改標。原標題：「## M. 與既有規格的衝突登記（本檔只改 62 §F.3 與 V-119，其餘只登記）」
     🔴 該括號在 2026-08-13 那一輪之後不成立：本輪與 62 號**同輪**改了 62 §I.1／§I.2／§I.2-1／§I.2-2／
        §I.3(c)／§I.3(d)(e)／§I.4／§J.1／§0.3／§0.4／§N／§O／附錄 A／附錄 B。
        留著那句話會讓下一個人以為 62 §I 還是舊的碼粒度規則。
     🔴 **「本檔不改別人的檔」這條紀律沒有放寬**：62 與 67 是同一輪同一個裁定的兩半
        （碼在 62、前綴在 67），**分開改必然產生半套狀態**（只改碼 ⇒ 自指破裂；只改前綴 ⇒ 可達性破裂）。
        13／29／55／63 這些**別人擁有的檔案本輪一行都沒動**，全部走下面的登記。 -->
> **本輪（2026-08-13）改了哪些檔**：`67`（本檔）、`62`（同一裁定的另一半，碼粒度在那邊）、`config/limits.yml`。
> 🔴 **13／29／55／63／docs/design／docs/research 一行都沒動**，與它們的衝突全部走下表登記。

| # | 衝突 | 現況 | 本檔立場 | 誰該改 |
|---|---|---|---|---|
| **M-1** | **handle 允許 CJK** | 13 §F2-1：「中文標題不轉拼音，改用『允許 unicode handle（URL encode）』……demo 選 unicode handle（`/products/棉質短T` 可用）」；13 §F2-2「衝突自動 `-1` `-2` 後綴」 | 🔴 **前半：被 2026-08-12 裁定推翻**——一律 ASCII（§D.1）。⚠ 但要寫清楚這是**明知偏離 Shopify**（本尊保留 CJK，68 §B-1；登記於 62 §F.3-1），不是「13 寫錯了」。<br>✅ **後半：反向結案**——<!-- 依 68 §C-4 修正，原文：「另衝突尾碼自 `-2` 起算，且**手填衝突拒絕不加尾碼**（§D.4(b)）」 -->**13 §F2-2 的 `-1` 起算本來就是對的**（Shopify 官方例 `potion`／`potion-1` ＋ 實測），要改的是本檔，已改（§D.4(b)）。**手填衝突拒絕不加尾碼**維持（68 V-184 無一手證據 ⇒ 保守失效） | **13 §F2-1 仍待改**（ASCII 化）；**13 §F2-2 不必改**（它是對的） |
| **M-2** | **handle 列為可翻譯資源** | 29 §2.1 把 `PRODUCT/COLLECTION/ARTICLE.handle` 列入 `TranslatableResourceType` 的欄位集。<br>🔴 **68 §F-1 補強了這條的份量**：這不只是 29 號的一張表——`shopify.dev/changelog/resource-url-handles-are-now-translatable`（**2023-06-26**）是**官方明文能力**，且實務上啟用多語言後同一商品在各語言**就是不同 handle**（AJAX API 必須用該語言的 handle） | 我方 handle **不可翻**（§D.3，**明知偏離**，依據＝「一律英文」裁定的下游後果，不是技術偏好）。29 §2.1 需加註「本專案不採用 handle 的可翻譯性，語言維度由 URL 前綴承載，見 67 §D.3」。⚠ **待使用者確認**：「handle 一律英文」是否**同時**意味著放棄 per-locale handle 能力（我方推定是） | 29 §2.1 |
| **M-8**<br>⚠ **部分已處理** | **跟隨 Shopify 的結論反轉，尚未全部回寫到下游檔案** | ✅ `docs/handoff/2026-08-12-open-decisions.md`：**B-3／B-6／C-1～C-3／D-3 已於 2026-08-12（69 號修正輪）更新並移入 §F**。<br>✅ `65 §A2·T11`：已更新為「market 可建立 ＋ 送款被擋」（同輪）。<br>❌ **仍未回寫**：`63 §G.4`（含其硬規則「一律依 ISO 4217 exponent 換算」——🔴 該句現已知**不完整**，見 65 §J **M-8**）、`55` 金額測試矩陣（仍記「market 建立時擋下」）、`13 §F2-1`（仍是 unicode handle） | 以 `config/limits.yml` 的鍵為準（每鍵都有 `依 68 號 §X`／`依 69 號 §V-XXX` 追溯註釋）。🔴 **63／55／13 本輪仍不得改**，必須由其擁有者回寫，否則會出現「規格說 A、鍵說 B」的分裂 | 63／55／13 |
| 🔴 **M-9**<br>（2026-08-12 二次修正） | **B-3 的結論在同一天反轉了兩次** | 68 §B-3 依 Matrixify（`press`）把 `blank_means_unchanged` 翻成 `false`；69 §V-182 查到本尊原生語義（`help`）後**改回 `true`** ＋ 改成 overwrite 旗標形態 | 🔴 **`docs/research/68` 的 B-3 條不會被修正**（research 是證據不是結論）⇒ 任何人讀到 68 §B-3 要求翻面時，**必須同時讀 69 §V-182 與本檔 §E.6 的沿革註釋**。三處已互相交叉引用，但**只讀 68 就動手是可能發生的**——這是本輪最現實的回退風險 | 無（本列即防回退措施） |
| **M-3** | ~~62 §M S2「`handle` 欄位＋可翻譯」~~ | — | ✅ **本輪已改**（改為標註不可翻並指向 67 §D.4） | — |
| **M-4** | **頁級 cache key 無條件含 locale** | 63 §D.3 的 key 組成把 `locale` 寫死在列表裡 | 改為**依實際依賴降維**（§G.2），並沿用該節既有的 `touched_sources` 自檢做 fail-closed 判定。另 `catalog_flow.cache_stamp_sources` 必須加入 `translations` | 63 §D.3（本檔不改 63） |
| **M-5** | **`translations` 表缺六個欄位** | 29 §2.2 的表定義只有 `source_digest` ＋ `outdated` | 需補 `outdated_severity`／`value_source`／`review_required`／`source_locale_tag`／`updated_by_staff_id`／`updated_at`（§C.2） | 29 §2.2 |
| 🔴 **M-5a**<br>（2026-08-13 新增） | **29／28／50 仍描述 per-market 內容覆寫（Adapt）為我方能力** | 29 §2.2 表定義含 `market` 引用與六欄唯一索引、§2.2 讀取 fallback「(locale, market) → (locale, 全域)」、§2.4「同語言選其他市場＝Adapt 模式」、§8 P1 清單列 `translations.market_id（Adapt）`；28:343 mutation 清單含 `marketLocalizations*`；50:313 的 API→UI 對照 | `translations.market_id` 已依**裁定 10** 於 2026-08-13 移除（§0.4 第 7 列、§C.2 沿革）。research 檔是證據不改正文，但**各檔 owner 應加批註**「per-market 內容覆寫已依裁定 10 取消，欄位已移除，見 67 §C.2」，防止 1:1 對照稽核把欄位補回來。28 的 `marketLocalizations*` 在我方 API 面**不實作**，對外文檔不得列出 | 29 §2.2/§2.4/§8、28 §契約、50:313 |
| **M-6**<br>✅ **本輪已改** | **hreflang 失效掛鉤只綁 market conditions** | 62 §I.3(b)：market conditions 變更 ⇒ 矩陣與 sitemap 失效 | 觸發條件需**加上** `shop_locales` 與 `market_web_presence_locales` 的變更（§F.1(d)）。否則發布新語言後 hreflang 停在舊值 | ~~62 §I.3(b)（小幅補充，本輪未改以免擴大改動面）~~ ⇒ ✅ **2026-08-13 已補在 62 §I.3(e)**（白名單裁定讓這條從「小幅補充」變成必要條件：白名單開關的頻率遠高於改 market conditions） |
| 🔴 **M-10**<br>（2026-08-13 新增） | **Shopline 有、我方沒有的三個商品欄位面** | `alt`（Shopline 商品新增頁 ng-model，§E.2-1）：`summary_translations`（短摘要，可翻）／`preorder_note_translations`（預購說明，可翻）／`seo_keywords`（**無** `_translations` ⇒ 不可翻）。我方：前兩者**沒有這個欄位**，第三者**沒有這個欄位** | 🔴 **三者本檔一律不新增**（欄位歸 13／63，本檔只寫 i18n 語義）。<br>**`seo_keywords`：🔴 建議永遠不要加**——meta keywords 對搜尋引擎早已無效，加了就要回答「要不要翻」，而正確答案是「不要」⇒ **一個不翻的 SEO 欄位是純負債**。<br>**`summary`／`preorder_note`：⇒ V-227**，i18n 面的答案已預先寫好（必翻 ＋ 堆疊式），欄位是否要有由 13／63 裁定 | 13／63（欄位）；本檔（i18n 語義，已寫） |
| 🔴 **M-11**<br>（2026-08-13 新增） | **29 §2.5 的 URL 前綴模型被裁定推翻** | 29 §2.5：「primary market 預設語言在根、其他語言 `/{lang}`」；29 §1.2：「語言-only 子資料夾僅限 primary market」 | 🔴 **裁定推翻「語言-only 子資料夾」與「預設語言在根」兩條**（§F.1(b)）。**XOR（`domain` 與 `subfolderSuffix` 互斥）不受影響，照抄**。62 §J.1 已於本輪改寫並留追溯註釋；**29 §2.5／§1.2 需加註指向 67 §F.1(b) 與 62 §I.2-1** | **29 §2.5／§1.2 仍待改**（本檔不改 29） |
| 🔴 **M-12**<br>（2026-08-13 新增） | **`market_web_presence_locales` 缺三欄** | 29 §1.4 的表定義只有 `alternateLocales` ＋ `position` | 需補 `is_market_default`／`open_to_buyers`／`closed_at`（§C.8(a)），並加 FK 到 `shop_locales`（那條 FK 就是「③ ⊆ ②」不變量的執法點）。形態同 §M-5 對 29 §2.2 的處置 | 29 §1.4 |
| **M-7** | **`Product.published` 的語言面** | 13 §F1.2 已拆成 `purchasable`／`discoverable`（四態） | 🔴 **兩個 scope 都與語言正交**：`UNLISTED` 商品的**每一個**語言版本都不可被發現。多語言不新增第三個 scope | 無（本檔確認既有設計正確，登記以防日後有人加 `published_in_locale`） |

---

## 附錄 A · 本檔的可重跑驗證

§D.1 的管線與 §D.1 驗證樣本表由下列步驟產生（供覆核者重跑；腳本本身不入庫，因為它只是 §D.1 規格的直譯）：

1. 以 Python `unicodedata` 實作 §D.1 的九個步驟（NFKC → 撇號刪除 → 不可分解字母轉寫表 → NFKD 去 combining → 小寫 → 非 `[a-z0-9]` 轉分隔 → 收斂修剪 → 分隔符邊界截斷 → 品質閘門）。
2. 以裁定給的標題為輸入，斷言輸出 == 裁定給的 handle（**已通過，逐字元相同**）。
3. 以 §D.1 表中其餘六個樣本為輸入，記錄輸出與閘門結果——即該表的內容。
4. 實作時的對應測試是 `HDL-2`～`HDL-6`，測試資料**直接使用該表**（規格與測試同源，鐵律 7 的文件版）。
