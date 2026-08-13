# 71 — 商家後台全量 parity sweep 總登記簿（逐頁・逐控件・逐交互）

> **目的**：把我方 admin（`docs/design/chilllove-admin-v2.html`＋specs）與 Shopify 商家後台做**按鈕級交叉對比**，
> 找出遺漏／bug／死碼／佔位可轉真控件，逐模組補齊並寫 dev 文檔。使用者要求（2026-08-13）：
> 「admin 後台和 shopify 的商家後台不能有一絲的差異」。
> **雙源紀律**：實測（`test` 級，chill-love-u5q5mnzq **測試店**，使用者已授權可寫入操作）×
> 官方 help（`help` 級，help.shopify.com/zh-TW）。來源分級照舊：src > std > help/dev > alt > press > blog。
> **輪次制**：R0＝主清單（本檔）；R1..Rn＝每輪一個模組走完「實測 → help → 逐控件對比 → 原型補齊＋DOCS 註釋
> ＋dev 文檔 → lint → worklog」。本檔 §E 是進度總表，跨 session 續作以它為準。
> **視覺紅線**：對比作用於控件存在性、資訊架構、交互邏輯、狀態機；視覺值依鐵律 8 走我方 tokens，
> 像素抄 Polaris＝鐵律 9 法律紅線。

## §A 裁定偏離保護清單 🔴（對比前必讀，23 條）

**凡在此表的「我方 ≠ Shopify」都是裁定或明文登記的結果，任何對比輪不得建議「改回與 Shopify 一致」。**
要動表內任何一條，必須先推翻對應裁定（使用者本人）。逐條完整出處與原文＝parity-sweep-prep 工作流 guard 輸出
（journal：`wf_3ff4f4fd-6b3`）；主出處＝SESSION-EXPORT §2、62 §F.3-1/§I.2-1/§I.2-2、67 §0.4、65、15 §F4.2、58、68/69。

| # | key | 我方（不得改） |
|---|---|---|
| G1 | money-display-two-decimals | 全幣別顯示兩位小數（含 JPY/TWD） |
| G2 | money-storage-x100 | 儲存一律 integer cents ×100 不看幣別 |
| G3 | money-psp-format-per-pack | 送 PSP 依 pack 宣告 `amount_format`＋參數；未宣告 reject，不套 ISO |
| G4 | handle-ascii-only | handle 一律 ASCII；中文標題落 `{resource}-{token8}` fallback |
| G5 | handle-quality-gate | 品質閘門（拉丁 ≥3／丟棄比 ≤0.5）＋混排保留英文——我方獨有 |
| G6 | handle-not-translatable | handle 全站單一值不可翻譯，語言在 URL 前綴 |
| G7 | handle-collision-two-strategies | 生成撞號 `-1` 起；手填撞號 reject（HANDLE_TAKEN） |
| G8 | handle-generation-details-ours | NFKC／`_→-`／255／分隔符邊界截斷維持我方 |
| G9 | handleize-filter-separated | Liquid `handleize` 與 URL handle 生成器是兩套；filter 不套 ASCII-only |
| G10 | url-prefix-always-region | URL 前綴恆 `語言[-字體]-地區`，永不裸語言，無例外 |
| G11 | hreflang-always-region-qualified | hreflang 恆帶地區、多國市場逐國展開；裸碼＝CI 紅燈（例外僅 x-default） |
| G12 | root-path-not-content-page | `/` 302 到預設前綴，不進 sitemap/hreflang，爬蟲不豁免 |
| G13 | no-market-content-override | 不做市場級內容覆寫（translations.market_id 已刪） |
| G14 | translation-csv-blank-unchanged | 翻譯 CSV 空白＝不動作；清空 `__CLEAR__`；覆寫顯式旗標 |
| G15 | no-own-payment-system | 不自建支付；PSP capability 查詢（Airwallex/Stripe/PayPal） |
| G16 | sf-label-pdf-html-only | 順豐面單只用 PDF＋HTML 兩支；指令流 ⛔ 範圍決策 |
| G17 | sf-waybill-not-billed-but-ledger-stays | 運單號不計費，但銷號帳機制一條不拿 |
| G18 | unlisted-no-old-api-downgrade | 不做舊 API 版本把 UNLISTED 降級回 ACTIVE |
| G19 | geo-redirect-guardrails-non-disableable | 地區重導預設開＋三護欄不可關閉（我方硬化） |
| G20 | training-crawlers-allow | 訓練型爬蟲 allow；AI 爬蟲開關三組不合一 |
| G21 | hk-baseline-jurisdiction-packs | 基準法域 HK；憑證/儲值/取貨/隱私 per-pack；台灣內容降級不刪 |
| G22 | postal-code-backend-setting | 郵遞區號後台設定（HK 預設 optional），非寫死拿掉 |
| G23 | per-market-language-whitelist ＋ url-prefix-hreflang-two-functions | 白名單=呈現決策；`url_prefix()`/`hreflang_codes()` 兩函式不得合併 |

⚠ guard 工作流另發現：**limits.yml 的 hreflang 相關鍵疑未同步 2026-08-13 裁定**（實質漂移警告）⇒ 已登記 §F 71-R0-V1，查證後修。

## §B 實測主清單（R0，2026-08-13 實測 zh-TW 介面）

**商店**：chill-love-u5q5mnzq（Plus・dev・測試店）。⚠ 部分模組受商店狀態閘門（未啟用 Shopify Payments ⇒ 財務
empty-state；未解鎖商店 ⇒ 首頁 setup guide）——對比要分「功能面」與「本店狀態面」。

### B.1 本尊側欄導航樹（實測全量）↔ 我方原型對照

<!-- 依 parity-sweep-prep 工作流修正（2026-08-13）：本節初稿曾把 成長/內容/財務/草稿/運送標籤/公司 等標為
     「我方整區缺失」——那是拿 M0 React shell（僅商品頁）當對比對象的誤判。正確對象是原型 full 版
     （MODULES L7896-7923/L10899）。教訓：先建我方側地圖再標缺口，不要憑最近看過的畫面。 -->

```
本尊（實測）                          我方原型                    判定
首頁 /                               home（pulse 指標列+AI 框）   ✅ 有；差異點→R2（Sidekick 面板形態 G12、setup 卡）
訂單 /orders                         orders                      ✅ 有
  草稿 /draft_orders                 m-drafts＋d-draft 建單器     ✅ 有
  運送標籤 /shipping_labels          m-shiplabels                ✅ 有（批次工作流佔位多→R7）
  未完成結帳 /checkouts              m-abandoned                 ✅ 有
產品 /products                       products＋d-product          ✅ 有（59/60/61 深蓋）
  商品系列 /collections              m-collections               ✅ 有
  庫存 /products/inventory           m-inventory（四 tab）        ✅ 有
  採購單 /purchase_orders            m-inventory 的 tab           🔶 STRUCT：本尊獨立側欄頁 vs 我方 tab（71-R0-STRUCT1）
  轉移 /transfers                    m-inventory 的 tab           🔶 同上
  禮品卡 /gift_cards                 m-giftcards                 ✅ 有
顧客 /customers                      m-customers＋d-customer      ✅ 有
  分群 /customers/segments           m-segments＋d-segment        ✅ 有（建立器覆蓋薄→R5）
  公司 /companies                    m-companies（B2B）           ✅ 有
成長 /growth                         m-growth                    ✅ 有（覆蓋最薄①→R1）
  歸因 /growth/reports/channels      m-attribution               ✅ 有
  行銷活動 /growth/campaigns         m-campaigns                 ✅ 有
折扣 /discounts                      m-discounts＋d-discount      ✅ 有（表單內層薄⑦→R6）
內容 /content/metaobjects            m-metaobjects               ✅ 有
  檔案 /content/files                m-files                     ✅ 有
  選單 /content/menus                m-menus＋d-menu              ✅ 有
  部落格貼文 /content/articles       m-blog＋d-article            ✅ 有
市場 /markets                        m-markets＋d-market          ✅ 有
  目錄 /catalogs                     m-catalogs                  ✅ 有
  推出 /rollouts                     —                           🔴 MISS（71-R0-MISS1）
財務 /finance                        m-finance（2FA gate）        ✅ 有（薄④→R4）
  （帳單併設定側）                    m-billing                   ⚠ 歸屬映射→R4
分析 /analytics                      analytics＋m-reports/m-live  ✅ 有
線上商店 /themes                     m-themes                    ✅ 有
  頁面 /pages                        m-pages                     ✅ 有
  偏好設定 /online_store/preferences m-prefs                     ✅ 有
  （我方另有 m-redirects 網址重導）   m-redirects                 ⚠ 本尊側欄未見此頁→R9 查歸屬（可能在內容/選單內）
代理式 /apps/agentic                 側欄「AI 代理」純 toast      🔴 STUB（71-R0-STUB1）
銷售點 /apps/point-of-sale-channel   側欄「門市 POS」純 toast     🔴 STUB（同上；44:907 曾判 POS 刻意不覆蓋→需使用者確認範圍）
Translate & Adapt /apps/...          我方原生翻譯（67 號）        ⚠ 形態差（設計決策），R12 登記映射
應用程式>新增應用程式                 純 toast                    🔴 STUB（71-R0-STUB1）
API 相關需求搜尋結果（側欄底）        —                           🔴 MISS（71-R0-MISS2）
Sidekick 對話（側欄底）              AI 助理對話（聚焦首頁輸入框） ⚠ G12 形態差
設定 /settings（21+account 子頁）    設定 overlay 22 分頁         ✅ 數量級對齊；逐頁映射→R12
```

### B.2 設定區子頁（本尊 21＋account）

`組織`(organization-details)、`使用者`(organization-account)、`一般`(general；內含 商店聯絡資料/中繼欄位/品牌/商店活動記錄)、
`方案`、`帳單`、`付款`、`結帳`、`顧客帳號`、`運送與配送`、`稅額與關稅`、`地點`、`應用程式`、`銷售管道`、`網域`、
`顧客事件`、`通知`、`中繼欄位與 metaobject`、`語言`、`顧客隱私`、`政策`、`帳戶`。
R12 做本尊 21+1 ↔ 我方 22 的逐頁映射（合併/缺失/改名）。

### B.3 新區塊首屏速記（R0 淺層）

- **首頁**：頂部指標列（所有管道/過去30天）＋問候語＋setup guide 卡＋右側 Sidekick 面板（預設開）。
- **成長**：Campaign Autopilot（搶先體驗）＋成效卡（歸因銷售額/佔比、流量類型工作階段）＋管道卡＋Autopilot 區。
- **財務**：本店未啟 Payments ⇒ 2FA banner＋稅務卡＋啟用 empty-state＋右上「文件」下拉。完整形態靠 help 補（R4）。
- **市場**：左樹（商店預設值/+地區）＋市場表（市場/狀態/包含/自訂項目）＋建立International建議列＋圖表檢視。
- **代理式**：Agentic Storefronts 開關＋readiness 清單（目錄存取/更新政策）＋「允許 Shopify 為我管理」per-agent
  白名單（ChatGPT/Copilot/其他/Shop）＋來源卡（Catalog 商品數/Knowledge Base）＋補充條款 ⇒ 餵 B-7（UCP）。

## §C 我方側地圖（parity-sweep-prep 工作流產出，2026-08-13）

- **C.1 原型構成**：5 頂層靜態頁＋27 模組頁（full 版 MODULES L7896-7923/L10899）＋13 詳情頁＋設定 22 分頁
  ＋20 設定次級視圖＋結帳與帳號編輯器 overlay。路由 go()/hash（L2221-2315）、冷開降級表 URL_OPEN。
- **C.2 佔位（STUB 素材）**：全檔 `toast('Demo：…')` 139 處，其中約 20 處在**死碼區**（舊 MODULES 3010-3230
  已被 full 版整批覆蓋，實際不可達）⇒ 71-R0-DEAD1。活佔位完整清單見工作流 journal（逐行號），各輪轉真時取用。
- **C.3 DOCS 註釋系統**：505 條無重複；markup 字面引用 301 唯一 key＋18 處動態注入管道全數反查對上；
  **缺註釋 0**；真死註釋僅 2（`ck-acct-credit`/`ck-announce`，DOCS 超前 storefront 實作的 X-07 形態）⇒ 71-R0-DEAD2；
  74 個 `[api:TBD-*]`（⇒ 71-R0-DOC2 逐輪落 28 號契約）；17 條 i 欄無 P 標記（⇒ 71-R0-DOC1）。
  ⚠ popup 查表有通用 fallback（L3557）會靜默掩蓋未來缺條目——新增 data-doc 後必須人工比對。
- **C.4 研究覆蓋圖**：深蓋＝訂單/產品/結帳運送設定/市場。**最薄排行**：①成長 ②首頁 ③設定·應用程式與銷售管道
  ④財務 ⑤分群建立器 ⑥設定·網域/隱私/custom_data ⑦折扣表單內層 ⑧B2B 公司 ⑨使用者權限顆粒 ⑩付款內層（刻意，G15）。
  樣式量測（47/64 方法）僅蓋訂單列表＋商品詳情兩類頁——薄模組補拆時順手帶量測。
- **C.5 既有缺口（去重基準）**：UI 側以 53 號為準（49 已凍結）：**open 162**（P0 未解 10：P0-01/02/07/09/14/15/16/17/18/19）；
  邏輯側 50 號殘餘＝P2 遞延 14＋V-01~14＋表 4 的 62 個 TBD＋台灣殘項。**新登記前先比對 49/50/52/53/54，
  title 或 evidence 命中即視為已登記，引用舊編號不開新項。**

## §D 對比方法（每輪固定）

1. **實測**：走該模組每一頁（測試店可寫入——可開 modal、送表單、看驗證與狀態機；避免產生費用/對外發信）。
   逐控件記錄：控件、預設值、驗證、互動後果、空/滿/錯三態、鍵盤行為。shadow DOM 紀律照 SESSION-EXPORT §5.1。
2. **help zh-TW**：該模組官方說明逐頁抽取（並行 agent），標 `help`；與實測矛盾時實測優先、登記 V-編號。
3. **對比**：↔ 22 號對應章節 ↔ 原型（含 §C.2 佔位清單、C.3 DOCS）↔ specs。先查 §A 再判定。
   產出五類：`MISS`／`BUG`／`DEAD`／`STUB`（佔位轉真）／`DOC`；結構性差異＝`STRUCT`。
4. **補齊**：原型改動＋每個新控件 DOCS 條目（功能/邏輯/實作出處）＋`docs/dev/` 篇章；lint ERROR 0、WARN 不新增；
   追溯註釋照 CLAUDE.md；22 號式「依 XX 修正、不得改回」批註回寫。
5. **收尾**：worklog（三段制）＋本檔 §E/§F 更新＋commit+push。

## §E 輪次進度總表（覆蓋薄弱度驅動）

| 輪 | 模組 | 依據 | 狀態 |
|---|---|---|---|
| R0 | 主清單＋方法＋保護清單＋我方側地圖 | 本檔 | ✅ 2026-08-13 |
| R1 | 成長（growth/歸因/行銷活動/Autopilot） | 薄① | ✅ 2026-08-13（V1＋7 fix＋4 V 遞延，見 §F R1） |
| R2 | 首頁指標系統（4 槽×16 池＋挑選器＋口徑 tooltip＋雙期圖卡）＋口徑目錄 72 號 | 薄②＋使用者截圖增補 | ✅ 2026-08-13 |
| R2b | 全域 chrome＋首頁全頁收尾（搜尋 CtrlK 升級/快訊 popover/AI 對話釘選/期間控制正式版/管道下拉/問候語時段制/ai-box 對齊/即時訪客連結） | MISS2＋R1-V4 | ✅ 2026-08-13 |
| R3 | 設定·應用程式＋銷售管道＋網域＋顧客隱私＋custom_data | 薄③⑥ | ✅ 2026-08-13（2 STRUCT＋4 MISS 全修＋RTE 考證＋limits 2 節；4 V 遞延，見 §F R3） |
| R4 | 財務＋帳單（含 help 補閘門後形態；G15 邊界） | 薄④ | ⬜ |
| R5 | 顧客線（分群建立器/B2B 公司/顧客詳情） | 薄⑤⑧ | ⬜ |
| R6 | 折扣（四型建立流內層/詳情/組合規則） | 薄⑦ | ⬜ |
| R7 | 訂單線（列表佔位轉真/詳情補齊/草稿建單器/運送標籤批次流/棄單） | 深蓋複核＋STUB 多 | ⬜ |
| R8 | 產品線子頁（庫存四 tab、STRUCT1 採購單/轉移、禮品卡、系列） | STRUCT1 | ⬜ |
| R9 | 內容（metaobjects/files/menus/blog）＋線上商店（themes/pages/prefs/redirects 歸屬） | | ⬜ |
| R10 | 市場（markets/catalogs/**rollouts MISS1**/裁定邊界 G13） | MISS1 | ⬜ |
| R11 | 分析（analytics/live/reports；鐵律 7 同源） | | ⬜ |
| R12 | 設定逐頁映射 I+II（21+1 ↔ 22）＋使用者權限顆粒⑨＋Translate&Adapt 映射 | 薄⑨ | ⬜ |
| R13 | 管道（代理式/POS/新增應用程式 STUB1 轉真；agentic↔B-7/UCP） | STUB1 | ⬜ |
| R14 | 收斂：DEAD1/DEAD2 清理、DOC1/DOC2 補完、STUB 殘差總表、22 號回寫 | | ⬜ |

## §F 差異登記（編號 71-R{輪}-{類}{序}；先查 §C.5 去重）

| 編號 | 類 | 內容 | 狀態 |
|---|---|---|---|
| 71-R0-MISS1 | MISS | 市場>推出 `/rollouts` 頁我方無（分階段推出機制） | ⬜ R10 |
| 71-R0-MISS2 | MISS | 側欄底「API 相關需求搜尋結果」入口——實測揭曉**形態＝釘選的 Sidekick 對話**（點開=對話完整檢視：markdown 回答+追問建議+讚/倒讚+輸入框），非獨立功能。已以「AI 對話釘選」形態實作（我方命名，G12） | ✅ R2b |
| 71-R0-STRUCT1 | STRUCT | 採購單/轉移：本尊獨立側欄頁 vs 我方庫存頁 tab | ⬜ R8 |
| 71-R0-STUB1 | STUB | 「AI 代理」「門市 POS」「新增應用程式」三導航項純 toast、無 page 容器（最大顆佔位） | ⬜ R13 |
| 71-R0-DEAD1 | DEAD | 舊 MODULES/renderModule/legacy helper（L3010-3230）整區死碼，內含 ~20 不可達 toast | ⬜ R14 |
| 71-R0-DEAD2 | DEAD | 死註釋 2 條：`ck-acct-credit`/`ck-announce`（X-07 超前實作形態） | ⬜ R14 |
| 71-R0-DOC1 | DOC | 17 條 DOCS i 欄無 P0/P1/P2 標記 | ⬜ R14 |
| 71-R0-DOC2 | DOC | 74 個 `[api:TBD-*]` 待逐輪落 28 號契約命名 | ⬜ 各輪 |
| 71-R0-V1 | V | limits.yml hreflang 鍵未同步恆帶地區裁定——查證坐實：`region_qualified_when_single_country_market` 為裁定前化石鍵。已照 62 §L 處方落齊 8 鍵（改名＋7 新增，D-2 形態） | ✅ R1 結案 |
| 71-R1-BUG1 | BUG | 歸因頁做成「設定表單」（save bar＋儲存設定）——本尊為報表頁（參數隨選即重算、URL query 化）。已改寫＋FORMSEL 摘除 | ✅ |
| 71-R1-BUG2 | BUG | 「回溯窗 7/14/30 天」設定項為無中生有——本尊固定 30 天歸因期間、商家不可設。已移除並在報表 footer 明示 | ✅ |
| 71-R1-MISS1 | MISS | 歸因模型缺 2 型（任何點擊/線性）且無功勞分配描述；用語「最後」應為「最終」。已補齊 5 型（test＋help 雙源） | ✅ |
| 71-R1-MISS2 | MISS | 歸因 13 欄報表（成本/ROAS/CPA/CTR/AOV/新回客拆分）、維度切換（管道↔Campaign 活動）、列印/匯出、行銷 app 指標 banner、每分鐘~每年粒度——原型全部缺。已補 | ✅ |
| 71-R1-STRUCT1 | STRUCT | campaign 概念模型錯位：原型＝內容編輯器（Email 表單）；本尊＝歸因容器（名稱唯一必填＋短連結 /s/{id}+QR＋自動比對規則 5UTM+管道+類型＋指派行銷企劃）。已改寫三函式＋容器編輯器 | ✅ |
| 71-R1-MISS3 | MISS | Autopilot 實體設定（四管道連結/每月預算/防護措施 ROAS·地區·語言/權限二選一/策略狀態機/暫停語義/資格清單）原型僅一條 banner。已補設定區塊＋banner 加「加入等候名單」CTA | ✅ |
| 71-R1-FIX1 | FIX | 成長主頁口徑：KPI 改 help 定義（佔比表達/流量類型可點/歸因訂單數）；管道表格改卡片（本尊主頁形態）；期間選擇器補齊本尊預設集（今天~自訂範圍 9 檔） | ✅ |
| 71-R1-V1 | V | 行銷活動列表的實際欄位與狀態值域未驗證（測試店空列表）——存一筆後補驗；bulk 動作是否存在同 | ⬜ R7 前 |
| 71-R1-V2 | V | 已存 campaign 的詳情頁動作列（結束/複製/刪除？）未驗證；原型編輯器 footer 暫僅 捨棄/儲存 | ⬜ |
| 71-R1-V3 | V | 成長主頁「行銷成效六卡」完整形態（help 列六卡；本店僅見二卡＋管道卡）——受商店資料量閘門，待有數據店複驗 | ⬜ |
| 71-R1-V4 | V | 全域日期選擇器——已依 S-SHOPIFYQL-DATE-CONTROLS 實測選項集做成正式版共用元件（預設集＋過去 N 數值/單位/包含今天＋取消/套用；hm-scope-date）。雙月曆自訂範圍細節仍簡化（登記於 DOCS） | ✅ R2b |
| 71-R2b-MISS1 | MISS | 首頁 chrome 五處補齊：搜尋 palette 缺類型 chips/footer 兩動作（向 AI 詢問/應用程式市集）、快訊為 modal 非錨定 popover、問候語非時段制、ai-box 缺附加鈕+placeholder 不符、即時訪客不可點。全部已修 | ✅ |
| 71-R2b-V1 | V | 搜尋結果態的富形態（分類計數 chips「設定 24/導覽 15」+結果列描述關鍵詞粗體+再顯示 20 個）依賴搜尋後端——結構已記入 DOCS，M1 14-F4 落地時實作 | ⬜ M1 |
| 71-R2b-V2 | V | setup guide 實測為 7 卡（移轉/匯入目錄/付款/運費/解鎖商店/國際市場/Plus 功能，各帶進度環+下一任務+CTA）——內容依商店狀態而變，我方 3 卡結構同構；卡集數據面登記備查 | ⬜ 低 |
| 71-R2-MISS1 | MISS | 首頁指標列為靜態 4 pill（不可換指標、無挑選器、無口徑說明、無大圖卡）——本尊為 4 槽×16 池可編輯系統。已建成：挑選器（搜尋+16 列+圖型 icon+ⓘ 公式 tooltip）、雙期折線大圖卡、拆解表（含 HK pack 稅額恆 0）、per-user 語義入 DOCS | ✅ |
| 71-R2-DOC1 | DOC | 16 指標的計算口徑無任何文檔——已建 docs/research/72（實測 tooltip 原文＋help 公式逐條、交互規則 10 條、unknowns 4 條） | ✅ |
| 71-R2-V1 | V | 指標 tooltip 樣式化浮層（指標詞底色高亮）原型以 title 屬性近似；分析頁（R11）做正式 tooltip 元件時回頭替換 | ⬜ R11 |
| 71-R2-V2 | V | 本店 pinned 第 3 槽=總銷售額拆解，help 記載預設=總訂單數——per-user 狀態 vs 出廠預設，出廠值以 help 為準（總訂單數），原型 demo 沿用實測店組合並在 DOCS 註記 | ⬜ 低 |
| 71-R3-STRUCT1 | STRUCT | 設定導覽「應用程式與銷售管道」合併頁 vs 本尊 2026 兩個獨立設定頁（/settings/apps?tab=installed、/settings/sales_channels）。已拆兩頁＋導覽位置對齊（地點之後）；「自訂資料」同輪改本尊標籤「中繼欄位與 metaobject」 | ✅ |
| 71-R3-MISS1 | MISS | 應用程式頁形態缺：開發應用程式／App Store 鈕、已安裝 tab、列 ⋯ 選單（實測 3 動作、help 5 動作＋解除安裝）、詳情六區段（帳單與用量收費／活動與權限含未使用存取權／隱私權／擴充功能／Functions 分享記錄／像素）、解除安裝對話框（原因下拉＋資料保留與當期費用條款）、用量上限單向調高、釘選規則。已補齊（appDetail／appUninstall） | ✅ |
| 71-R3-MISS2 | MISS | 銷售管道頁缺：新增銷售管道（App Store 入口＋副作用 opt-out）、列 ⋯ 解除安裝＋必勾風險確認框「我瞭解解除安裝此銷售管道的風險」。已補（chUninstall）；53號 N-04（不做管道設定層）不變 | ✅ |
| 71-R3-MISS3 | MISS | 網域頁缺：樹狀列表（主要＋縮排子項）、連結現有網域分裂鈕（輸入／轉移）、網域詳情（DNS checklist／全球六地區點陣＋上次檢查／TLS／指向與類型＋變更鈕／網域設定▾ 三項）。已補（domainDetail）；help 補齊行為規則（60 天轉移鎖／15 天 ICANN 驗證／48 小時生效口徑／DNS 判準與警告文案全量） | ✅ |
| 71-R3-STRUCT2 | STRUCT | 顧客隱私頁 IA 不符：本尊＝隱私權設定卡（三列各帶自動化 badge＋子編輯器：政策 modal／Cookie 橫幅子頁（雙 tab＋顏色三檔＋位置五選＋結帳頁開關）／退出頁面子頁 /dns（導覽選單掛載））＋Network Intelligence 卡＋行銷設定兩條跨頁錨點深連結（結帳#marketingconsentoptions、通知 customer#optin）＋資料儲存託管地點。已改建；舊四 toggle 語義遷入子頁（GPC＋連結文字→退出頁；橫幅開關→橫幅子頁）；生成器補 HK PDPO 選項（G21） | ✅ |
| 71-R3-MISS4 | MISS | custom_data 缺：owner 分組入口（15 類含螢幕會漏的地點／轉移）、per-owner 列表（搜尋＋釘選）、編輯器缺單一/清單前綴＋類別指派（taxonomy 驅動，僅產品）＋owner 全 15 類、metaobject 選項五開關（啟用與草稿／翻譯／發布為網頁／Storefront API／顧客帳號 API）。已建三層結構＋編輯器升級＋metaobjDefNew；上限入 limits.yml custom_data.*（250／50／20，help 明載） | ✅ |
| 71-R3-DOC1 | DOC | RTE 考證（使用者指令）：本尊隱私政策編輯器引擎＝**TinyMCE 6.8.3**（DOM 實證：id `rte-uplift-PRIVACY_POLICY-*`、iframe `tox-edit-area__iframe`、plugins autoresize/lists/table、autoresize 150–300、valid_elements `*[*]`、原生 toolbar 停用＝工具列自繪驅動）。6.8.3＝最後 MIT 版（7.x 起 GPLv2+/商業雙授權）——本尊釘住 MIT 尾版。我方引擎選型屬鐵律 1 未討論依賴：候選 A 釘 TinyMCE 6.8.3（MIT、與本尊行為同源）／候選 B TipTap 2（MIT、ProseMirror 系）——**待使用者裁定（開放決策 B-8）** | ✅ 考證；⬜ 選型 |
| 71-R3-V1 | V | Cookie 橫幅「Cookie 偏好設定」tab 內容未逐控件展開（實測只拆了 Cookie 橫幅 tab）；GPC 開關在本尊 2026 主頁未見（可能在偏好設定 tab 或已併入自動化）——複驗後定 GPC 的最終落點 | ⬜ |
| 71-R3-V2 | V | metaobject「顧客帳號 API 存取權」選項 help 全站未載（實測獨有，2026 新）——語義與權限面需 dev 文件補證後才能落 API 契約 | ⬜ 低 |
| 71-R3-V3 | V | 網域模型：本尊 2026＝per-domain 網域類型（主要／別名／重新導向，一目標一主要；「導向主網域」全域開關的 help 頁已消失）vs 我方 62 §J 全域開關＋市場網址結構。含別名網域 SEO 語義（同內容多網域降排名警告）。R10 市場輪對齊裁定 | ⬜ R10 |
| 71-R3-V4 | V | 用語盤點：custom_data owner 已改「產品」，但全站「商品／產品」混用（本尊：模組＝產品、個體常用商品）——R12 設定映射輪做全站用語對照表一次收 | ⬜ R12 |
| 71-R3-DOC2 | DOC | 意外收割：本尊**完整鍵盤快捷鍵表**（? 開鍵盤說明；單鍵 S 儲存列／F 篩選列／OA OC OS ME BYE；A* 新增系 8 條；G* 兩鍵導航 ~40 條含設定子頁 GS*）——R2b 全域 chrome 補遺素材，原型快捷鍵系統落地時對表實作 | ⬜ R14 |
