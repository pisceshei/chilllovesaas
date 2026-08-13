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
| R1 | 成長（growth/歸因/行銷活動/Autopilot） | 薄① | ⬜ |
| R2 | 首頁＋全域 chrome（指標列/搜尋 CtrlK/通知/Sidekick 形態/API 搜尋入口） | 薄②＋MISS2 | ⬜ |
| R3 | 設定·應用程式＋銷售管道＋網域＋顧客隱私＋custom_data | 薄③⑥ | ⬜ |
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
| 71-R0-MISS2 | MISS | 側欄底「API 相關需求搜尋結果」入口我方無 | ⬜ R2 |
| 71-R0-STRUCT1 | STRUCT | 採購單/轉移：本尊獨立側欄頁 vs 我方庫存頁 tab | ⬜ R8 |
| 71-R0-STUB1 | STUB | 「AI 代理」「門市 POS」「新增應用程式」三導航項純 toast、無 page 容器（最大顆佔位） | ⬜ R13 |
| 71-R0-DEAD1 | DEAD | 舊 MODULES/renderModule/legacy helper（L3010-3230）整區死碼，內含 ~20 不可達 toast | ⬜ R14 |
| 71-R0-DEAD2 | DEAD | 死註釋 2 條：`ck-acct-credit`/`ck-announce`（X-07 超前實作形態） | ⬜ R14 |
| 71-R0-DOC1 | DOC | 17 條 DOCS i 欄無 P0/P1/P2 標記 | ⬜ R14 |
| 71-R0-DOC2 | DOC | 74 個 `[api:TBD-*]` 待逐輪落 28 號契約命名 | ⬜ 各輪 |
| 71-R0-V1 | V | limits.yml hreflang 相關鍵疑未同步 2026-08-13 恆帶地區裁定（guard 工作流警告）——查證後修 | ⬜ 優先 |
