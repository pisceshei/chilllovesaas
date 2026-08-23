# 109 — SHOPLINE 多語言方案研究（R-9，2026-08-23）

> 依總方案 §十 序 12b（R-9 SHOPLINE 輔助參考）落庫；使用者 2026-08-23 裁定逐字
> 「參考和複製shopline的多語言方案」。研究方法＝官方 help center／blog 文檔
> 取證（workflow 產出，49 次工具呼叫），逐條標 URL＋取證日期；未取得逐項標明。
> 🔴 與 67 號的十點對照表在文末——照抄與否逐點判定，非整包照抄。


---

# SHOPLINE 多語言方案研究報告（供 CHILL LOVE 67 號規格對照）

**取證日：2026-08-23。** 所有來源均為 SHOPLINE 官方 help center／官方 blog，逐條標註 URL。查不到的逐項標「未取得」。

## 0. 先決事實：SHOPLINE 有兩套平台、兩套多語言方案（不可混引）

| | **Asia 平台**（shopline.hk／shopline.tw，商店網域 `*.shoplineapp.com`，help＝support.shoplineapp.com） | **Global 平台**（myshopline.com，help＝help.shopline.com） |
|---|---|---|
| 技術形態 | AngularJS 舊制，翻譯欄位**內嵌在商品資料本體**（`*_translations[lang]` map，67 §E.2-1 的 V-226 觀察即此平台） | Shopify 形態複刻：Settings>Languages＋Markets＋獨立翻譯 app |
| 任務指定的（shopline.hk/tw）**＝ Asia 平台** | ✅ 本報告以它為主 | 一併登記供對照 |

---

## ① 商家怎麼開多語言

**Asia 平台**：
- 入口：Admin > **[Settings] > [Basic Settings] > 「Supported Shop Languages」** 區塊勾選語言。（[Step 8: App Language Settings](https://support.shoplineapp.com/hc/en-us/articles/41882448284569)，取證 2026-08-23）
- 硬規則（同上出處）：**至少 2 種語言**；**English 是系統預設語言、不可移除**。
- 預設語言二選一：**「based on customer's browser language」或「your custom choice」**（同上出處）。
- 刪除語言：該語言欄位自前台移除，**但資料保留在資料庫**，重新加回不需重填。（[Multiple Currency And Language Display Setting](https://support.shoplineapp.com/hc/en-us/articles/206313605)，取證 2026-08-23）
- 商品內容支援語言（bulk 檔案明列）：**繁中、簡中、英、越南文、泰文、馬來文**；「日、印尼、德、法」標示 coming soon。（[Bulk Update Products](https://support.shoplineapp.com/hc/en-us/articles/360019883172)，取證 2026-08-23）；早期功能起點是中英雙語（[官方 blog](https://blog.shopline.hk/new-feature-bilingual-content/)）。**完整可勾選清單未取得**（需登入後台實測）。

**Global 平台**：
- 入口：Admin > **Settings > Languages**（Supported languages > Add languages）；再到 **Markets >（市場）> Domains and languages** 把語言指派給市場、設市場預設語言、自市場移除語言；主網域市場一律跟隨 primary market 設定。刪除商店語言＝**永久刪除所有相關譯文**。語言管理受 RBAC 權限控制。（[Managing Languages for Your Global Markets](https://help.shopline.com/hc/en-001/articles/13259908085017)，取證 2026-08-23）
- 可勾選語言總清單：**未取得**（彈窗內容需登入實測）。

## ② 翻譯的資料形態

**Asia 平台**：
- **無獨立翻譯後台、無機器翻譯**（help center 搜「translation」僅 5 篇，無 MT 功能文；取證 2026-08-23）。翻譯＝在**商品編輯頁本體逐欄位填各語言**：「Please fill in the product information according to the correct language. If you do not fill in the English information, the customer will only see the information in Chinese.」（[Upload Products](https://support.shoplineapp.com/hc/en-us/articles/208614546)，取證 2026-08-23）
- 缺譯 fallback＝**顯示已填語言的原文**（不空白）：「if the store only has the product content in Traditional Chinese, when consumers switch... to English, the product description will still show the content in Traditional Chinese.」（[Product Summary & Description](https://support.shoplineapp.com/hc/en-us/articles/204937899)，取證 2026-08-23）；分類名 fallback 依「Supported Shop Languages」的**優先順序**逐語言找第一個有值的（Bulk Update Products 同文）。
- 批次通道＝**商品 Excel 匯出／匯入，每個可翻欄位按語言各一欄**（名稱、summary、SEO title/description、preorder note；「At least one Chinese or English name is required」）（Bulk Update Products，取證 2026-08-23）。
- 可翻資源（官方文檔＋blog 合併）：商品（名稱/summary/描述/SEO/預購說明）、分類名稱、頁面、通知範本（逐語言 tab，[Custom Notifications 搜尋摘要](https://support.shoplineapp.com/hc/en-us/search?query=translation)）、店面介面。通知變數存在 `{{persistent_cart_item.child_product_translations}}` 這類 `*_translations` 後綴——**佐證全平台資料形態就是欄位級 language map**（與 67 §E.2-1 V-226 的 ng-model 觀察互證）。

**Global 平台**：
- 三條通道共用同一份翻譯資料：**Settings > Language 的匯出/匯入**、**UGC Multi-Language Visual Translator app**（逐資源逐語言的可視化雙欄編輯＋**Automatic translation** 一鍵機翻）、Auto Translate & Currency Assistant。（[UGC Visual Translator](https://help.shopline.com/hc/en-001/articles/13759854105753)，取證 2026-08-23）
- 可翻資源樹（同文，逐項）：Product／Collections；Custom page／Blog posts／Blog category／**Store policy**／Navigation／**Store metafields／metaobjects**；**Templates（靜態元件、theme templates、theme settings）**；**Automatic discounts／Discount codes**；File library／**Payment method**／第三方 app。metafield 只翻文字型（單行/多行/rich text/JSON 可勾選）。
- 機翻限制：**每店自動翻譯至多 2 種語言**（要加語言需找 account manager）；Starter 方案配額（商品 2,000 次/分類 200 次/頁面 100 次）；**DNT 不翻清單**（50 條 × 200 字元）；**每日 01:00 GMT-8 增量自動翻譯**；可中止、可按語言×模組刪除譯文。（同文）
- 🔴 **市場級覆寫存在**：UGC app 有「market selector ＋ language selector」，同語言可做 All markets 的通用翻譯＋單一市場的在地化翻譯，**「localized 優先於 general」**。（同文）

## ③ 前台呈現

**Asia 平台**（[Language in URL for SEO](https://support.shoplineapp.com/hc/en-us/articles/4402396232601)，2026-01-12 正式上線，取證 2026-08-23）：
- 舊制＝**query 參數** `?locale=en`；新制＝**裸語言碼子路徑** `https://example.shoplineapp.com/en/`，形如 `domain/{locale}/products/{product name}`。
- **預設語言首次進站無前綴**（「no language code will appear」）；切到其他語言後才加；**切回預設語言時 URL 也會帶預設語言的 `{locale}` 路徑**；舊 `?locale=` URL 仍可用（並存）。
- 覆蓋頁面：`/pages`、`/products`、`/categories`、`/promotions`。
- SEO：文中明說「Labeling Hreflang can also help search engines」，但 **hreflang 具體輸出規則未取得**。
- 切換器：可整個隱藏（Advanced Settings >「Hide the language selector on storefront」）；可**「Hide specific language」**逐語言隱藏（內容沒準備好就先不上架——店級呈現白名單）。（[Multiple Currency And Language Display Setting](https://support.shoplineapp.com/hc/en-us/articles/206313605)）

**Global 平台**：
- 市場網域四型：主網域（全語言同一 URL＋**系統自動輸出 hreflang tags**）、子網域（ca.yourstore.com）、ccTLD（yourstore.ca）、**子資料夾（官方推薦，例＝`yourstore.com/en-ca`、`yourstore.com/fr-fr`——語言-地區合體碼）**。（[How to Choose the Best Domain Setup for Global SEO](https://help.shopline.com/hc/en-001/articles/13260473345049)，取證 2026-08-23）
- 市場導向：手動彈窗／IP 自動重導（官方自己警告自動重導傷 SEO、建議手動）；**`?country=JP` 參數鎖市場且優先於重導規則**。（[Understanding Domain Management Features and Use Cases](https://help.shopline.com/hc/en-001/articles/58253965443097)，取證 2026-08-23）

## ④ 商品編輯頁的翻譯入口形態

- **Asia 平台＝編輯頁內建，不是獨立翻譯頁**：短欄位（名稱/summary/預購說明）＝**每語言一個輸入框並列（堆疊式）**；長欄位（描述/SEO）＝**綁「當前編輯語言」的分頁式**——這正是 67 §E.2-1 已登記的 V-226 觀察；本輪 help 文（Upload Products「照正確語言填入」）與 blog（「中文分類名稱／英文分類名稱」兩個欄位）雙源佐證。
- **Global 平台**＝翻譯主入口在**獨立 app（UGC Visual Translator）**與 Settings>Language 匯入匯出；商品編輯頁內是否有直達翻譯入口：**未取得**。

## ⑤ 多幣別與語言的關係

- **Asia 平台：不綁定。** 語言切換器與幣別切換器是兩個獨立控件、兩個獨立開關（同在 Design > Advanced Settings）。幣別＝**純顯示參考**：Open Exchange Rates 匯率每日更新兩次、19 種幣別、預設依買家 IP；**「Order payments will be calculated and charged using the currency set in Shop Settings」**——收款一律店設幣別。（[Multiple Currency And Language Display Setting](https://support.shoplineapp.com/hc/en-us/articles/206313605)，取證 2026-08-23）
- **Global 平台：語言與幣別各自掛在市場上，選擇器互相獨立**；Auto Translate & Currency Assistant 的幣別切換同樣**「for display purposes only. The actual payment currency is determined by your store's checkout and payment settings」**。（[Auto Translate & Currency Assistant](https://help.shopline.com/hc/en-001/articles/15545973637913)，取證 2026-08-23）

---

## 與我方 67 號規格逐點對照

| # | 對照點 | SHOPLINE（標註平台） | 我方 67 號 | 判定 |
|---|---|---|---|---|
| 1 | 翻譯資料形態 | Asia＝欄位級 `*_translations[lang]` map 內嵌本體；Global＝獨立翻譯資料（三通道共用） | base row＋`translations(resource_type, resource_id, locale_tag, field_key)` 獨立表＋6 稽核欄（§C.2） | **不同（刻意）**。67 §E.2-1(c) 已明文拒絕 map 形態——它載不動 digest/outdated/value_source 六稽核欄 |
| 2 | 編輯頁 UI：堆疊式 vs 分頁式 | Asia＝短欄堆疊、長欄分頁（V-226） | §E.2-1 已照此形態收編＋自定判準 | **相同**（我方即參考它定的） |
| 3 | 內容語言切換器 | Asia＝無單一切換器概念（各欄位語言並列/分 tab）；Global＝app 內 language selector | §E.1/E.2 兩層語言、內容語言進 URL query | **不同**：我方多「兩個切換器不得連動」與 URL 化 |
| 4 | 缺譯 fallback | 顯示已填語言原文；分類依語言優先序取第一個有值 | §C.4 明確 fallback 鏈、必翻回原文/可選不輸出、禁繁簡互 fallback | **方向相同、我方更嚴**。SHOPLINE 的「優先序」允許跨語言亂借（英文版看到中文）；我方鏈定義排除繁簡互借 |
| 5 | 預設語言 | Asia＝**English 恆為系統預設、不可刪、至少 2 語** | §C.3 source locale 可自選可變更、恰一列 is_source | **不同**。照抄＝強迫香港繁中店以英文為源語言，違反裁定（首發繁中為源） |
| 6 | URL 結構 | Asia＝預設語言**無前綴**＋其他語言**裸語言碼** `/en/`（另存 `?locale=` 舊制）；Global 子資料夾＝`/en-ca`、`/fr-fr` | §F.1 恆帶地區恆有前綴 `/zh-hant-hk`，禁裸語言碼，根路徑 302 | **Asia 形態與 2026-08-13 裁定直接衝突；Global 子資料夾形態與我方裁定一致** |
| 7 | hreflang | Asia＝文中提及、規則未取得；Global＝依啟用語言自動輸出 | 62 §I 完整矩陣＋雙向性驗證 | 我方已定案更細 |
| 8 | 語言呈現白名單 | Asia＝店級「Hide specific language」＋整個切換器可隱藏 | §A.5 **per-market** 白名單（strawberrynet 模型） | **方向相同、粒度不同**：Asia 無市場維度，只有全店開關 |
| 9 | 市場級內容覆寫 | Global＝UGC app 通用翻譯＋市場在地化翻譯、localized 優先 | 🔴 裁定 10 **刪除** `market_id`（HK 英文＝CA 英文） | **不同（我方明知偏離）**。SHOPLINE Global 有此能力＝67 §0.4-7 復活條件的又一 `alt` 佐證，但不觸發復活 |
| 10 | 機器翻譯 | Asia＝**無**；Global＝UGC app 一鍵機翻（限 2 語言＋配額）＋ Auto Translate 的 **Google Translate 渲染期即時翻譯** | §E.5 可插拔 provider、寫真實譯文列、`value_source='machine'`＋`review_required` | **不同**。Global 的渲染期 Google 翻譯正是我方 §A.4/§E.5 明文禁止的「渲染期偷換字、商家看不到改不掉」形態；「限 2 語言」與 29 §2.4 記載的官方限額互證（V-169 佐證） |
| 11 | 匯入匯出 | Asia＝商品 Excel 逐語言欄；Global＝Settings>Language 專用翻譯匯入匯出 | §E.6 翻譯第三套 CSV、空白＝不動作 | **Global 同向**（翻譯獨立於商品檔）；Asia 混在商品檔＝67 §E.6 拒絕的形態 |
| 12 | 語言 × 幣別 | 兩平台皆**不綁定**、幣別切換純顯示、收款幣別另定 | §A.1/A.3 語言⊥市場⊥幣別 | **相同（正交這一點）**；但 SHOPLINE 的「IP 推匯率、顯示估價」機制我方無、也不採（見下） |
| 13 | 刪語言的資料語義 | Asia＝**保留資料**可復原；Global＝**永久刪除譯文** | shop_locales `published=false` 下架不刪資料 | 我方＝Asia 形態（保留），Global 形態較危險 |
| 14 | 可翻資源清單 | Global 清單含 discount codes、payment method、file library、metafield/metaobject、theme 三層 | §B.2 大致同構（29 §2.1 的 30 型） | **大致相同**；SHOPLINE 的「File library」我方無對應（媒體檔案級翻譯，僅 alt 有） |

## 若照抄 SHOPLINE（Asia 平台）需要改什麼——逐條與後果

1. **資料模型改成欄位級 `*_translations` map** → 必須拆掉 §C.2 六稽核欄、§C.5 過期偵測、§C.6 進度物化、§E.6 翻譯 CSV。**67 §E.2-1(c) 已明文裁定不採**；「複製 SHOPLINE」若指到這一層，與既有規格衝突，**需請使用者重新裁定**。
2. **URL 改成「預設語言無前綴＋裸 `/en/`」** → 直接推翻 2026-08-13 恆帶地區裁定與 62 §I.2。🔴 不可執行；**Global 平台的 `/en-ca` 子資料夾形態反而與我方裁定一致**，抄 SHOPLINE 應抄這一半。
3. **English 恆為預設且不可刪＋至少 2 語** → 推翻 §C.3 可變更 source locale；與「首發繁中」裁定衝突。不建議。
4. **可採納、且我方目前缺的**（照抄成本低、不違鐵律）：
   - **DNT 不翻詞彙表**（品牌名/尺寸單位/email 不翻；Global，50×200 上限形態）→ 可加進 §E.5 機翻管線，落 `limits.yml`。
   - **增量自動翻譯**（每日只翻新增/變更內容；Global）→ 可做為 §C.5 outdated 偵測的消費端批次。
   - **刪語言保留資料、加回即復原**（Asia）→ 與我方 `published=false` 同向，可在 §E 明文化「刪除＝下架不清資料」的 UI 承諾。
   - **「Hide specific language」的措辭**（內容沒準備好先不上架）→ 已被 §A.5 白名單涵蓋且我方粒度更細，無需改。
5. **不可採納（違我方鐵律/裁定）**：渲染期 Google Translate（違 §A.4/§E.5）；市場級內容覆寫（違裁定 10，除非重新裁定）；IP 匯率顯示估價（我方金額由 market 定價、鐵律 3/10 不做顯示換算）；翻譯混在商品總 CSV（違 §E.6 三套分離）。

**結論一句**：SHOPLINE Asia 的方案本質是「**欄位級雙語（後擴多語）內嵌、無翻譯治理**」，我方 67 號已把它的 UI 形態（堆疊/分頁、編輯頁內翻譯）收編為 V-226/V-227，而在資料層、URL 層、fallback 治理上刻意更嚴；「參考和複製」在 UI 互動層已完成、可再補收 DNT 詞彙表與增量翻譯兩件；資料層與 URL 層照抄會推翻既有使用者裁定，需回報請示而非靜默執行。

**主要來源**：[Language in URL for SEO](https://support.shoplineapp.com/hc/en-us/articles/4402396232601)｜[Multiple Currency And Language Display Setting](https://support.shoplineapp.com/hc/en-us/articles/206313605)｜[Step 8: App Language Settings](https://support.shoplineapp.com/hc/en-us/articles/41882448284569)｜[Upload Products](https://support.shoplineapp.com/hc/en-us/articles/208614546)｜[Product Summary & Description](https://support.shoplineapp.com/hc/en-us/articles/204937899)｜[Bulk Update Products](https://support.shoplineapp.com/hc/en-us/articles/360019883172)｜[SHOPLINE HK blog 雙語功能](https://blog.shopline.hk/new-feature-bilingual-content/)｜[Managing Languages for Your Global Markets](https://help.shopline.com/hc/en-001/articles/13259908085017)｜[UGC Multi-Language Visual Translator](https://help.shopline.com/hc/en-001/articles/13759854105753)｜[Auto Translate & Currency Assistant](https://help.shopline.com/hc/en-001/articles/15545973637913)｜[Understanding Domain Management Features and Use Cases](https://help.shopline.com/hc/en-001/articles/58253965443097)｜[How to Choose the Best Domain Setup for Global SEO](https://help.shopline.com/hc/en-001/articles/13260473345049)（全部取證 2026-08-23）