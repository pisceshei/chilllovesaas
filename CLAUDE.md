# CLAUDE.md — 專案共用規則（Claude 在本倉庫的任何工作都遵守）

> 分工：**Codex 實作**（守則見 `AGENTS.md`）、**Claude 審核驗收**（依本檔與 docs 規格）。完整上下文入口：`HANDOFF.md`。

## 專案是什麼

CHILL LOVE——多租戶電商 SaaS，功能邏輯與交互 1:1 對齊 Shopify 2026 春季版，視覺用自有設計語言。第一階段（研究＋規格＋高保真原型＋Liquid PoC）已完成；現在做第二階段實作，里程碑 M0–M6 見 `HANDOFF.md` §5。

## 技術鐵律（違反＝退回修改）

1. **技術棧（D1/D4）**：Rails 8.1 + MySQL 8 + Vite/React(TS) admin + Liquid 相容前台；Solid Queue/Cache，不用 Redis；不引入未討論的重型依賴。
2. **多租戶**：全表帶 `shop_id`，且複合索引以 `shop_id` 開頭。
3. **金額（單位邊界）**：內部全程 **integer cents（一律 ×100，不看幣別）**，出現 float 即 bug；序列化層才轉 `MoneyV2` / `MoneyBag`。**契約全文＝`docs/specs/65`，下列五條是它的鐵律摘要。**
   <!-- 依 63 號 §G.4 / 61 號 §1.3 修正，原文：「**金額**：全程 **integer cents**，出現 float 即 bug；序列化層才轉 `MoneyV2` / `MoneyBag`。」
        原文只擋住「float」，擋不住「單位」——2026-08-12 裁定二讓儲存一律 ×100 之後，
        把儲存值直接送 PSP 就是 100 倍收款，而原文對此完全沉默。🔴 任何人不得把本條縮回一行。 -->
   - 🔴 **儲存尺度 ≠ 顯示位數 ≠ 對外單位，這是三件事**：儲存一律 ×100／顯示一律兩位小數（2026-08-12 裁定二）／**送 PSP 依該 PSP pack 明文宣告的「格式 ＋ 該格式的參數」**——`amount_format: minor_units | decimal_string`**兩種都存在**（Stripe／Adyen／Datatrans＝整數 minor unit；**Airwallex＝十進位主單位字串，根本不用 minor unit**），格式與參數**任一未宣告一律 reject，不得預設**；`minor_units` 的 exponent 正常值＝ISO 4217，但 **Adyen 明文覆蓋 ISO、Stripe 對 HUF／TWD 另有「整除 100」約束** ⇒ **ISO 只是 pack 可以選擇的底表，不是換算基數**。物流商走十進位字串（58 §G.3），與 PSP 的**任何一種**格式**都不是同一件事**，不得合併成一個「對外轉換」。
     <!-- 依 69 號 §V-188 修正（2026-08-12），原文：「送 PSP 依該 PSP pack 明文宣告的 minor unit
          （正常值＝ISO 4217 exponent；**未宣告一律 reject，不得預設**）。」
          原文**不完整**：它假設所有 PSP 都收整數 minor unit，而 69 號查到四家 PSP 四種算法
          （`alt` 級＝PSP 官方文檔），其中 **Airwallex 用十進位主單位字串** ⇒ `Money::PspMinor`
          這個型別在該類 PSP 上根本不適用，照原文實作的人只能繞過型別自己組字串。
          🔴 **不得把本次修正讀成鐵律 3 放寬。** 恰恰相反：外部證據正面證實了「PSP 單位必須逐家宣告、
             不得套 ISO」是對的，只是**宣告的內容比原本想的多一個維度（格式）**。全文＝65 §A R6／§D。 -->
   - 🔴 **把儲存值直接送 PSP＝收款 100 倍**（JPY ¥1,480 儲存 `148000`，送出必須是 `1480`）；**把 PSP 回報值直接落庫＝少記 99%**；**拿 PSP 金額直接比對 checkout 金額＝每張 JPY 訂單被判成金額不符而自動退款**。三種形態同一個根因，**且在 HKD／USD 這些 exponent=2 的幣別下全部測試皆綠**。
   - 不同單位用**不同型別**（`Money::Storage` / `Money::PspMinor` / **`Money::PspDecimal`** / `Money::Decimal`，無隱式 `to_i`／`to_s`）與**不同識別字後綴**（`*_cents` / `*_minor` / `*_psp_decimal` / `*_decimal`）；PSP adapter 簽名**只收該 pack 宣告格式對應的那一個值物件**，傳裸 Integer／裸 String／**或傳 `Money::Decimal`（物流商與 JSON-LD 用的那個，字串長得一模一樣）**一律 `TypeError`。**註釋不算防呆**（65 §C）。
   - **zero-decimal 幣別必須進金額測試矩陣**（至少 **JPY／TWD／KRW**），缺者 CI fail（65 §H）。沒有這一條，這個 bug 只會在上線後的對帳日出現。**`amount_format` 兩種格式也各必須有 fixture pack**，且 **TWD 要測「整除 100 違反 ⇒ raise 且不得自動湊整」**（65 §H.1／T16／T19，依 69 號）——`decimal_string` 型的誤用**在 HKD 上也會錯**，它是唯一基準法域測得到卻沒人在測的送款事故形態。
   - **不得**用 `jurisdictions.<code>.currency_format.exponent` 或 `currency_display.iso4217_zero_decimal_overridden` 當換算基數——前者自 2026-08-12 起語義是**顯示位數**（58 §G.3），後者是**被覆蓋的顯示清單**，兩者都不是 PSP 單位來源。
4. **API-first（D5）**：admin SPA 只打 `/admin/api/{version}/graphql.json`；命名 `resourceVerb`；業務錯誤走 `userErrors{field,message,code}`（HTTP 恆 200）；分頁用 cursor＋`pageInfo`（≤250）；GID 格式 `gid://chilllove/{Type}/{id}`。契約見 `docs/research/28`。
5. **冪等與事件**：訂單成立／退款／庫存調整必帶 `idempotencyKey`；transaction 內禁外部 IO；事件走 outbox。
6. **上限值**：一律引用 `config/limits.yml`（常數表見 `docs/research/22` §9.4），不得硬編碼。
7. **數字同源**：同一指標在 pulse／列表 badge／分析頁必須來自同一 rollup 查詢。
8. **UI 值**：一律取自 `docs/design/23-interaction-css-spec.md` §1 的 tokens，不自創色值與尺寸；icon 用 Lucide（MIT）。
9. **法律紅線**：不用 `@shopify/polaris`、不抄 Dawn/Horizon 代碼與 Shopify 的 CSS/圖片/文案/商標；Liquid gem、theme-check、theme-liquid-docs 為 MIT 可用；`test/fixtures/themes/ella-7.2.0` 是使用者已購授權的測試 fixture，僅供測試、不得隨平台散布。
10. **文案**：繁體中文為主、技術名詞保留英文；金額顯示 `HK$1,480`（tabular-nums），實際符號與小數位由市場的 locale 決定，不得硬編。
11. **司法管轄區（2026-08-12 決議，取代先前的台灣預設）**：**基準法域＝香港**，並且**必須做成可插拔的 jurisdiction pack**，因為目標是全球市場。
    - 稅務憑證是**法域能力**不是核心功能：HK＝無銷售稅／無政府發票（收據僅為商業單據）；TW＝統一發票＋字軌＋折讓＋作廢；MY＝LHDN e-Invoice。核心流程只發「稅務事件」，由 pack 決定要不要落地成憑證。
    - 儲值監管同理：HK＝PSSVFO/SVF，**單一用途豁免 ⇒ 禮品卡不得跨租戶通用**（產品級硬限制）；TW＝電支條例不得資金池。
    - 取貨網路、隱私法（HK PDPO / TW 個資法 / GDPR）、幣別格式、稅號格式（HK BR / TW 統編）一律 per-jurisdiction。
    - **既有台灣內容不刪，降級為 `jurisdiction/tw` pack 的素材**；核心規格不得再直接引用 `統一發票／字軌／折讓／超商取貨／統編／電支條例`——要引就引 pack 介面。

## 驗收基準

- 每個功能過 `docs/specs/11` §0 七維度（安全／資料／併發／效能／可觀測／測試／合規）；各 spec 末尾有該模組驗收清單。
- 畫面對照 `docs/research/22` 逐按鈕打勾；原型 `docs/design/chilllove-admin-v2.html`（開「⌗ 註釋模式」可看每個控件的功能／邏輯／實作）。
- 主題引擎 golden theme＝Ella：`docs/research/27` §8 十條、`docs/research/31` §6 矩陣；Liquid API 面對照 `docs/research/26`。
- 併發要害必須有測試：超賣、折扣用量、退款上限。
- **註釋與文檔強制驗收**（缺了一律 🔴 打回）：public 介面缺文檔註釋；複雜邏輯（金額/併發/冪等/Liquid 相容）缺「為什麼」註釋與規格出處；新增功能 PR 缺 `docs/dev/m{N}-{功能}.md`（規範見 `AGENTS.md` 註釋與文檔節、模板見 `docs/dev/README.md`）。

## 文件地圖

`docs/research/00-10` 模組研究｜`21/22` 實測與按鈕表｜`24` 編輯器與結帳 teardown｜`25/26/27/31` Liquid 引擎四件套｜`28` API 契約｜`29` Markets 國際化｜`30` SEO 與 feed｜`docs/specs/11-19` 生產級規格｜`docs/specs/65` **金額單位邊界契約（鐵律 3 全文）**｜`docs/design/20/23` UI 方案與 tokens｜`poc/liquid-engine` 引擎 PoC。

## 工作方式

- 🔴 **階段對齊標準（2026-08-13 使用者裁定，硬性——任何階段/輪次/畫面/功能，缺一層即打回）**：
  每做一個階段，必須與 Shopify 本尊保持一致性，**六層**缺一不可（2、3 為 2026-08-13 追加）：
  0. 🔴 **載入紀律：不存在「空白頁面」（2026-08-13 使用者裁定，最高優先——違反即整輪作廢）**：
     Shopify admin 載入常常慢、會卡成空白，**那是還沒載完，不是頁面沒有內容**。
     **任何情況下都不得以「空白／沒有內容／此商店沒有這功能」作為結論或登記事實。**
     遇到空白的強制處置順序：①**繼續等**（每次 5–10 秒，反覆截圖直到出現內容）
     ②🔴 **重新載入 1–3 次**（2026-08-13 使用者追加：頁面有問題一律先重載重試，**不得只試一次就下判斷**；
     截圖 API 逾時＝仍在渲染，也照此重試）③查 **iframe**（`querySelectorAll('iframe')` 看 src 與尺寸——
     內嵌 app 頁的內容在跨域 iframe 裡，R9 的線上商店即此形態）④查 **shadow root**（DOM 收割穿透）
     ⑤查 console／network 是否真有錯誤 ⑥仍拿不到就登記為「**工具限制／待補實測**」（V 項），
     **永遠不寫「該頁空白」**。
     🔴 **404 的正確歸因**：出現 404 先懷疑**自己猜的 URL 錯**（用側欄連結的真實 `href` 驗證），
     不要當成「本尊沒有這個頁面」——R10 的 `/markets/rollouts` 猜錯即前例（真實路由是頂層 `/rollouts`）。
  1. **按鈕級完全複製功能邏輯與交互邏輯**：每個按鈕、欄位、tab、選單、radio/checkbox 值域、
     空態、錯誤態、狀態機、副作用——逐控件實測（測試店 chill-love-u5q5mnzq，已獲全權授權），
     modal/子頁/深連結都要點開，不點開不登記。**點開後也要等到內容真的出現**（見第 0 條）。
  2. 🔴 **值域窮舉（2026-08-13 使用者追加）**：**所有下拉選單、下拉欄位、選擇器、autocomplete、
     ⋯ 選單、右鍵選單、分段控制、多選清單的選項一律逐項展開並全量記錄**——不是記「有一個下拉」，
     是記「這個下拉有哪 N 個選項、各自原文、預設值、條件顯示規則、選了會怎樣」。虛擬捲動清單
     要捲到底；被 shadow DOM 包住的用 DOM 收割（`[role=option]` 掃描）；截圖只用於版面確認。
     值域直接落 7x teardown 檔與原型（enum 不得自創、不得省略）。
  3. 🔴 **網站架構深度分析（同上追加）**：每輪先建該模組的**架構圖**——URL 路由樹（含 302 導向、
     query 參數語義）、頁面層級（列表→詳情→子頁→modal 的容器歸屬）、資料流與跨頁深連結、
     元件家族（哪些是跨頁共用元件，如時間軸/查詢視圖/欄位選擇器）。**讀完該模組所有功能內容**，
     不只點得到的按鈕：條件性控件（因商店狀態隱藏的）、方案分層功能、法域限定功能都要登記。
  4. **研究它所有的 CSS**：量測三段式＝token 值表 → 元件量測（字級/字重/行高/色/間距/圓角/陰影/
     狀態樣式）→ 我方 token 映射（照 73 §5 格式）。**量測歸研究、實作走我方 tokens**
     （鐵律 8/9：記錄本尊值供對標，不抄其代碼與視覺資產）。
  5. **必須結合 help.shopify.com 說明文檔**：實測＋help 雙源缺一不可——help 補條件性控件的
     條件枚舉、狀態機、上限值、原文措辭；規則性斷言標註取證日期（規則會改版，R6 組合規則
     即前例）。上限值一律落 `config/limits.yml` 帶出處。
  6. **條件性控件三源判定**：實測（看得到的）＋help（條件枚舉）＋商店狀態（為什麼看不到）——
     單源下結論即誤判（R4 幣別管理鈕、財務導航子項為前例）。
  產出入 `docs/research/7x` teardown 檔＋`docs/specs/71` §F 登記；與 Shopify 的差異只有兩種
  合法形態：71 §A 保護清單（使用者裁定）或 §F 登記的 V（待驗證）——**其餘一律修到一致**。
- **每完成一個部分，就寫一份工作記錄**（2026-08-13 使用者裁定，硬性）：`docs/worklog/YYYY-MM-DD-<功能>.md`，**三段固定**，與該部分的改動**一起 commit**：
  - **已完成的工作 (Done)**：條列這次實作了哪些功能、修復了什麼 bug。
  - **修改的檔案與核心邏輯 (Changes)**：列出異動的檔案路徑，並簡述關鍵函式或架構變動。
  - **尚未完成或需注意的風險 (Pending / TODO)**：列出還沒寫的邊際條件、潛在 bug 或待補的單元測試。
  - 🔴 **「一個部分」＝一個可獨立驗收的單位**（一個 spec 章節／一個畫面／一支 API／一次修復），**不是一整輪工作**。做完就寫，不要累積到最後補。
  - 🔴 **Pending 段不得留空**。真的沒有待辦，要寫「無，理由是⋯⋯」，因為空白讀起來像「沒檢查」而不是「檢查過沒有」。
- **每次工作結束前，一律寫交接文件**（與上面的工作記錄**並存，不互相取代**：worklog 是「這個部分做了什麼」，handoff 是「這一輪的判斷與教訓」）：`docs/handoff/YYYY-MM-DD-<主題>.md`，並與該次改動一起 commit。四段固定：①我改了什麼 ②為什麼這樣改（含被推翻的假設）③還有什麼沒解決 ④下一個人要注意什麼。這是硬性規則，不是選配。交接文件要列出本輪產生的所有 worklog 檔名。
- **原型改動後跑 `python3 scripts/lint-prototype.py`**（ERROR 必須為 0）。它把 49/51/53 號稽核的不變量固化了，每條規則都註明對應事故——尤其「同檔頂層函式不得重名」，那次事故是整頁功能靜默消失。
- 開新畫面前先讀 `docs/research/22` 對應章節與相關 spec；規格沒寫到的才問使用者。
- 分支 `m{里程碑}/{功能}`，PR 描述附「對應規格章節＋自測結果＋假設清單」；不直接推 main。
- 不確定時在 PR 註明假設，不要靜默猜測。
