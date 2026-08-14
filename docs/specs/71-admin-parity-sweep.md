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

## §A 裁定偏離保護清單 🔴（對比前必讀，27 條）

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
| G24 | org-level-identity-tables-exempt-from-shop-id | 🔴 **身分與權限表豁免鐵律 2 的 `shop_id`**（2026-08-14 裁定，R12-STRUCT1 的解）。白名單**逐表列舉、用我方實際表名、不得口頭擴充**——**已建**：`staff_members`（＝本尊的 users）／`roles`／`role_permissions`／`sessions`；**未建（M5 RBAC 展開時再加）**：`organizations`／`user_roles`／`user_groups`／`user_group_roles`。🔴 `user_store_assignments` **不在豁免內、必須帶 `shop_id`**（它是 user × shop 的關聯本體）；🔴 `shops` 不是豁免項，它是租戶根。<!-- 2026-08-14 修正（寫 docs/dev/m1-identity-tenancy.md 對照 db/schema.rb 時發現）：原文清單抄自 R12 對**本尊**的觀察，與我方實作三處對不上——①5 張表我方尚未建 ②`user_store_assignments` 列進豁免是反的 ③🔴 **漏列 `sessions`**（migration 實際拆了它的 shop_id、CI 也放行，但本條從未授權，違反下面配套條款③自己的規定）。教訓：白名單是安全邊界，寫成願景清單時規則與機制會各跑各的，而 CI 照的是機制那一份。已把 `scripts/check-tenant-isolation.rb` 的 `ORG_LEVEL_TABLES` 拆出 `TENANT_ROOT_TABLES`／`MUST_HAVE_SHOP_ID` 並加白名單自檢。 -->理由不是「本尊這樣」，而是**分層不同**：鐵律 2 保護的是業務資料的租戶隔離，身分與權限是**授予租戶存取權的那一層**，位於租戶之上。三條配套約束：①白名單表不得放業務資料欄位 ②🔴 **豁免的是「表有沒有 shop_id 欄」，不是「查詢可不可以不帶 shop_id」**——跨店存取須先由 `user_store_assignments` 解析出可及 shop_id 集合，查詢層仍逐表帶條件 ③新增白名單表要同步改 CLAUDE.md 鐵律 2 與本條，PR 描述標明。✅ **2026-08-14 已落地**（採 `docs/specs/85` A 案）：migration 拆四張身分表的 shop_id 與複合外鍵、新建 `user_store_assignments`、email 唯一性改全平台級；安全網兩道＝`Current.accessible_shop_ids`（fail-closed）＋ CI 的 `scripts/check-tenant-isolation.rb`。業務資料表完全未動。rspec 52/52 |
| G25 | aov-numerator-not-shared-with-net-sales | 🔴 **AOV 不與 net_sales 同源**（2026-08-14 裁定，R11-V13 的解）：照抄本尊的官方例外——AOV 分子刻意排除 post-order adjustments，因此 `AOV ≠ net_sales / orders`，必須有自己的 rollup 分子。這是鐵律 7「數字同源」的**具名例外**，已於 CLAUDE.md 鐵律 7 加註。配套：總銷售額**允許負值**（撤銷 > 銷售的日子）；`any_click` 歸因加總會超過 metric 本身，一致性測試須白名單 |
| G26 | pos-not-implemented-but-model-stays-pos-aware | 🔴 **不實作 POS，但資料模型保留 POS 活口**（2026-08-14 裁定，R13-V1 的解）。理由：POS 是**第二個產品**不是一個模組（硬體／離線／裝置管理／店員 PIN／班次／現金抽屜），且其權限模型與後台完全不同（organization role・角色制不可逐權限・以裝置地點為軸）。保留的活口＝訂單來源標記、地點、員工歸屬三個欄位面，之後要加不用改表。**任何輪次不得因「本尊有 POS」而建議補做**——要翻案須推翻本裁定 |
| G27 | ucp-deferred-but-restricted-liquid-context-honoured | 🔴 **UCP 相容層延後（M6 後再評估），但 `agents.md.liquid` 的受限 render context 現在就要吃進主題引擎設計**（2026-08-14 裁定，R13-V7 的解）。理由：UCP 在有商店有商品之前實作沒有意義；但**受限 context 是架構約束**——只有 `request` 與 `agents` 兩個物件、且 `agents.md`／`llms.txt`／`llms-full.txt` 不可為 JSON template。M2 設計 render context 時若沒把它算進去，之後補會很痛（見 71-R13-V3，仍為 M2 前必答） |

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
- **C.5 既有缺口（去重基準）**：🔴 **2026-08-14 更正——基準是 83 號不是 53 號**。
  稽核序列＝**49 → 53 → 83**（83 原以 71 號產出於 2026-08-13 雲端 session，與本檔撞號，
  2026-08-14 合併時改編為 83）。R0–R13 各輪的去重是拿 53 比的，**漏了 83 這一層**——
  下次登記前必須改比 83。
  - 83 的淨變化：53 的 10 條未解 P0 中**已解 7 條**（P0-01/02/07/09/14/15/16/18/19），
    **剩 P0-10（聯動）／P0-11（通知分組）／P0-20③（頁尾儲存鈕）／P0-21（配額分母）**。
  - 🔴 **83 的三條嚴重新發現，皆為「防回退標記的反面」，需在 M1 前處理**：
    ①**訂單退款上限被寫回「硬擋＋DB 鎖」**（22 號紅字明令不得回退的形態）
    ②**分群 `segCount()` 是假解析器**（會顯示錯誤數字，是真 bug 不是佔位）
    ③**請款模式 UI 只渲染 3/4 顆**（22 §9.1 紅字防回退標記的正反面）
  - 邏輯側 50 號殘餘＝P2 遞延 14＋V-01~14＋表 4 的 62 個 TBD＋台灣殘項。
  - **新登記前先比對 49/50/52/53/54/83，title 或 evidence 命中即視為已登記，引用舊編號不開新項。**

## §D 對比方法（每輪固定；🔴 2026-08-13 使用者裁定升格為硬性**六層**標準——缺一層即該輪不算完成）

> 使用者原文（第一次）：「每做一個階段的時候，必須按鈕級，完全複製他所有的功能邏輯和交互邏輯，
> 以及研究它所有的 css，也必須結合 shopify 的說明文檔，去了解他所有的功能邏輯，和 shopify 保持
> 一致性。」
> 使用者原文（追加，同日）：「你必須深度去分析和研究他的網站架構，讀取他所有功能內容，除了上面
> 還有所有的下拉選單，下拉欄位等等。」
> ⇒ 六層＝①按鈕級實測 ②**值域窮舉** ③**架構深度分析** ④CSS 量測三段式 ⑤help 雙源
> ⑥條件控件三源判定。CLAUDE.md 工作方式與 AGENTS.md 開工前 §4 已同步收錄（實作階段同樣適用）。

> 🔴 **本節已升格為 CLAUDE.md 技術鐵律 12（Shopify 對齊鐵律）**——含：親自點擊禁止猜 URL、
> 不存在有問題的頁面/404、測試店全權授權寫入（走完整建立→修改→刪除流程）、註釋四件事
> （含跨功能跨頁前端影響的預先對接）。以下六層為其操作定義。

0. 🔴 **載入紀律（層⓪，2026-08-13 使用者裁定，最高優先——違反即整輪作廢）**：
   使用者原文：「網頁加載有時比較慢，會卡住變成空白頁面，你必須記住**不存在任何空白頁面**，
   你必須等他加載完成後，才繼續處理。」
   ⇒ **任何情況下不得以「空白／沒有內容／此商店沒有這功能」作結論或登記事實。**
   強制處置順序：①繼續等（5–10 秒一輪，反覆截圖到出現內容）②🔴 **重新載入 1–3 次**
   （使用者追加原文：「如果頁面有問題，必須重新加載多 1-3 次」——不得只試一次就下判斷；
   截圖 API 逾時＝仍在渲染，同樣重試）③查 iframe（內嵌 app 頁內容在跨域 iframe，R9 線上商店即此形態）
   ④查 shadow root（DOM 收割穿透）⑤查 console／network ⑥仍拿不到＝登記「工具限制／待補實測」的
   V 項，**永不寫「該頁空白」**。
   🔴 **404 歸因規則**：先懷疑自己猜的 URL 錯，用側欄連結真實 `href` 驗證，不得當成「本尊無此頁」。
   🔴 **禁止猜 URL**（鐵律 12.1）：導航一律 DOM 取真實 `href` 再 navigate；手打路徑只可用於已驗證過的頁。
   🔴 **測試店全權授權寫入**（鐵律 12.2）：資料全假，必須實際**建立→修改→刪除**走完整流程，
   不得停在唯讀觀察——狀態機／驗證訊息／副作用／成功失敗態只有做過才拿得到。避免真實費用與對外發信。
   反例在案：71-R9-V2（內嵌 app 未繪製被誤判為「商店空白＝條件閘門」）、R10 猜測 `/markets/rollouts`
   得 404（真實路由是頂層 `/rollouts`）。
1. **實測（按鈕級，層①）**：走該模組每一頁（測試店可寫入——可開 modal、送表單、看驗證與狀態機；
   避免產生費用/對外發信）。逐控件記錄：控件、預設值、驗證、互動後果、空/滿/錯三態、鍵盤行為；
   modal/子頁/深連結都要點開，不點開不登記（R0-MISS2 教訓）。shadow DOM 紀律照 SESSION-EXPORT §5.1。
1b. 🔴 **值域窮舉（層②）**：**每一個**下拉選單／下拉欄位／選擇器／autocomplete／⋯選單／分段控制／
   多選清單都要展開並記全量選項（原文、預設值、排序、條件顯示規則、選後果）。虛擬捲動清單捲到底；
   優先 DOM 收割（`[role=option]`／`[role=menuitem]`／`select>option` 掃描穿 shadow root），
   截圖只作版面確認。**值域直接落 7x 檔與原型 enum——不得自創、不得省略、不得「示意」**。
   已建立的權威值域：74 §2（分群條件目錄）、75 §1（折扣四型）、76 §2（訂單狀態機四軸＋27 篩選器）、
   77 §1（庫存狀態與原因）。
1c. 🔴 **架構深度分析（層③）**：每輪 7x 檔開頭必須有該模組的**架構圖**：URL 路由樹（含 302 導向與
   query 參數語義）、頁面層級（列表→詳情→子頁→modal 的容器歸屬）、跨頁深連結、**共用元件家族**
   （時間軸／查詢視圖／欄位選擇器／期間控制…），並標出**該模組所有功能內容**——包含條件性隱藏、
   方案分層、法域限定的功能（看不到也要登記為什麼看不到）。
2. **CSS 量測（層②）**：三段式＝token 值表 → 元件量測（字級/字重/行高/色/間距/圓角/陰影/狀態樣式）→
   我方 token 映射，照 73 §5 格式入該輪 7x 檔。**量測歸研究、實作走 23 號 tokens**（鐵律 8/9）；
   與 73 §5 同系統的頁面可引用不重測，新元件必測。
3. **help zh-TW（層③）**：該模組官方說明逐頁抽取（並行 agent＋雙 critic 容錯；agent 結果判 null）；
   標 `help`；與實測矛盾時實測優先、登記 V-編號；**規則性斷言標註取證日期**（規則會改版——R6 組合
   規則前例）；上限值一律落 `config/limits.yml` 帶出處。
4. **條件控件三源判定（層④）**：實測（看得到的）＋help（條件枚舉）＋商店狀態（為什麼看不到）——
   單源下結論即誤判（R4 幣別管理鈕/財務導航子項前例）。
5. **對比**：↔ 22 號對應章節 ↔ 原型（含 §C.2 佔位清單、C.3 DOCS）↔ specs。先查 §A 再判定。
   產出五類：`MISS`／`BUG`／`DEAD`／`STUB`（佔位轉真）／`DOC`；結構性差異＝`STRUCT`。
   **與本尊的差異只有兩種合法形態：§A 保護清單（使用者裁定）或 §F 登記的 V——其餘一律修到一致。**
6. **補齊**：原型改動＋每個新控件 DOCS 條目（功能/邏輯/實作出處）＋`docs/research/7x` teardown 檔；
   lint ERROR 0、WARN 不新增；追溯註釋照 CLAUDE.md；22 號式「依 XX 修正、不得改回」批註回寫。
7. **收尾**：worklog（三段制）＋handoff（四段制）＋本檔 §E/§F 更新＋commit+push——三件一起。

## §E 輪次進度總表（覆蓋薄弱度驅動）

| 輪 | 模組 | 依據 | 狀態 |
|---|---|---|---|
| R0 | 主清單＋方法＋保護清單＋我方側地圖 | 本檔 | ✅ 2026-08-13 |
| R1 | 成長（growth/歸因/行銷活動/Autopilot） | 薄① | ✅ 2026-08-13（V1＋7 fix＋4 V 遞延，見 §F R1） |
| R2 | 首頁指標系統（4 槽×16 池＋挑選器＋口徑 tooltip＋雙期圖卡）＋口徑目錄 72 號 | 薄②＋使用者截圖增補 | ✅ 2026-08-13 |
| R2b | 全域 chrome＋首頁全頁收尾（搜尋 CtrlK 升級/快訊 popover/AI 對話釘選/期間控制正式版/管道下拉/問候語時段制/ai-box 對齊/即時訪客連結） | MISS2＋R1-V4 | ✅ 2026-08-13 |
| R3 | 設定·應用程式＋銷售管道＋網域＋顧客隱私＋custom_data | 薄③⑥ | ✅ 2026-08-13（2 STRUCT＋4 MISS 全修＋RTE 考證＋limits 2 節；4 V 遞延，見 §F R3） |
| R4 | 財務＋帳單（含 help 補閘門後形態；G15 邊界） | 薄④ | ✅ 2026-08-13（1 STRUCT＋3 MISS＋2 BUG 全修＋73 號 teardown/CSS 研究＋limits billing 節；4 V 遞延，見 §F R4） |
| R5 | 顧客線（分群建立器/B2B 公司/顧客詳情） | 薄⑤⑧ | ✅ 2026-08-13（1 STRUCT＋5 MISS 全修＋74 號 teardown＋limits 13 鍵；5 V 遞延，見 §F R5） |
| R6 | 折扣（四型建立流內層/詳情/組合規則） | 薄⑦ | ✅ 2026-08-13（1 BUG＋4 MISS 全修＋組合規則 2026 改版對齊＋75 號 teardown＋limits 3 鍵；4 V 遞延，見 §F R6） |
| R7 | 訂單線（列表佔位轉真/詳情補齊/草稿建單器/運送標籤批次流/棄單） | 深蓋複核＋STUB 多 | ✅ 2026-08-13（1 BUG＋4 MISS 全修＋R5-V1 結案＋撤銷術語裁定＋76 號＋limits 9 鍵；5 V 遞延，見 §F R7） |
| R8 | 產品線子頁（庫存四 tab、STRUCT1 採購單/轉移、禮品卡、系列） | STRUCT1 | ✅ 2026-08-13（R0-STRUCT1 結案＋77 號 teardown；5 V 遞延，見 §F R8） |
| R9 | 內容（metaobjects/files/menus/blog）＋線上商店（themes/pages/prefs/redirects 歸屬） | | ✅ 2026-08-13（**六層標準首跑**：1 STRUCT＋3 MISS 修＋78 號含架構圖與值域窮舉＋limits 14 鍵；5 V 遞延，見 §F R9） |
| R10 | 市場（markets/catalogs/**rollouts MISS1**/裁定邊界 G13） | MISS1 | ✅ 2026-08-13（**R0-MISS1 結案**＋G13 複核維持＋79 號含四棵文檔樹與三套覆寫模型；5 V 遞延，見 §F R10） |
| R11 | 分析（analytics/live/reports；鐵律 7 同源） | | ✅ 2026-08-14（**鐵律 12 首跑**：全流程寫入實測 建立→儲存→改名→切模式→刪除；80 號含 §0 架構圖＋365 指標/299 維度/27+2 視覺化全窮舉＋ShopifyQL 語言規格；4 MISS＋2 BUG 修＋limits analytics 節；17 V/9 DOC，見 §F R11） |
| R12 | 設定逐頁映射 I+II（21+1 ↔ 22）＋使用者權限顆粒⑨＋Translate&Adapt 映射 | 薄⑨ | ✅ 2026-08-14（**RBAC 架構揭露**：使用者在組織層＋角色 10/4 類＋權限 115/17 群/3 層依賴圖；81 號含設定樹映射表＋通知 47 範本＋help 雙源 14 條矛盾；2 STRUCT＋1 MISS 修＋limits 7 節 63 鍵；10 V/3 DOC，見 §F R12） |
| R13 | 管道（代理式/POS/新增應用程式 STUB1 轉真；agentic↔B-7/UCP） | STUB1 | ✅ 2026-08-14（**R0-STUB1 結案**：三顆 toast 佔位轉真頁；🔴**管道全部是 app**（/apps/{handle}）＋發布模型三層 AND；**B-7/UCP 有官方答案**（ucp.dev 規格＋5 個 MCP 端點）；82 號含 POS Lite/Pro 完整對照與 POS 權限 9 群組；limits 4 節 59 鍵；7 V/2 DOC，見 §F R13） |
| R14 | 收斂：DEAD1/DEAD2 清理、DOC1/DOC2 補完、STUB 殘差總表、22 號回寫 | | ⬜ |

## §F 差異登記（編號 71-R{輪}-{類}{序}；先查 §C.5 去重）

| 編號 | 類 | 內容 | 狀態 |
|---|---|---|---|
| 71-R0-MISS1 | MISS | 市場>推出 `/rollouts` 頁我方無 | ✅ R10 結案：**推出＝排程與 A/B 測試商店更新**（非 R0 憑名稱推測的「分階段推出市場」）；路由＝**頂層 /rollouts**；建立式＝名稱 ≤255＋草稿＋變更類型二選（網路商店佈景主題／結帳頁面和帳號）；三入口。已補 rolloutsPage/rolloutNew＋導航子項 |
| 71-R0-MISS2 | MISS | 側欄底「API 相關需求搜尋結果」入口——實測揭曉**形態＝釘選的 Sidekick 對話**（點開=對話完整檢視：markdown 回答+追問建議+讚/倒讚+輸入框），非獨立功能。已以「AI 對話釘選」形態實作（我方命名，G12） | ✅ R2b |
| 71-R0-STRUCT1 | STRUCT | 採購單/轉移：本尊獨立側欄頁 vs 我方庫存頁 tab | ✅ R8（產品導航子項五項對齊：商品系列/庫存/採購單/轉移/禮品卡；poPage/transfersPage 兩頁殼＋空態原文；庫存頁 tab 4→2；舊 INVTAB 深連結轉導） |
| 71-R0-STUB1 | STUB | 「AI 代理」「門市 POS」「新增應用程式」三導航項純 toast、無 page 容器（最大顆佔位） | ✅ R13 結案：三頁轉真（m-agentic／m-pos／m-apps，MODULES full:true＋自帶 page-head）；代理式含 4 個 AI 管道與詳情浮卡、POS 含管道殼與分析、應用程式含已安裝清單與管道區＋⋯ 三動作 |
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
| 71-R2b-V1 | V | 搜尋結果態的富形態（分類計數 chips「設定 24/導覽 15」+結果列描述關鍵詞粗體+再顯示 20 個）依賴搜尋後端——結構已記入 DOCS，M1 14-F4 落地時實作 | ⬜ M1 後段（84 §3 C-1：依賴搜尋後端，14-F4 落地時） |
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
| 71-R4-STRUCT1 | STRUCT | 帳單所在層錯位：我方「財務→帳單」模組頁 vs 本尊帳單只活在設定層（本店 302 → /settings/organization-billing 組織級）；財務導航子項＝狀態函數（未啟收款無子項、啟用後有「支付款項」）。已修：m-billing 移出導航改指路卡、KPI/發票表併入 setBillingPage；子項動態化＝71-R4-V4 | ✅ |
| 71-R4-MISS1 | MISS | 財務頁缺三態：本尊未接收款＝推銷空態（2FA banner＋空態卡＋稅務列＋「文件」下拉=法域 pack 文件：US=1099-K/活動報表、HK=無）——我方恆顯示 active 形態。已補 FIN_PSP 三態（空態/2FA 閘門（53號 P0-19 加固不變）/active）＋文件下拉＋稅務列 | ✅ |
| 71-R4-MISS2 | MISS | 設定・帳單頁形態缺：目前帳單週期卡五要素（週期日期範圍/累積總計大數字/付款方式/距離門檻所剩/費用明細）＋查看目前費用→upcoming 明細（四類費用區塊＋稅費）＋檢視剩餘抵用金＋過去的帳單卡（7 態 tabs/搜尋/排序 開立日期 舊新新舊/五欄表/⋯匯出（目前頁面或依日期）+費用報告/分頁）＋帳單詳情（付款時間軸/匯出 CSV/PDF/折讓單）＋付費明細 檢視摘要（≤90 天）＋帳務資料子頁（付款方式 ⋯ 設為主要/取代/刪除守門＋幣別）＋新增付款方式表單（hosted fields＋HK 地址 schema）。已全部重建 | ✅ |
| 71-R4-MISS3 | MISS | 撥款面（PSP pack 對應面，G15）：狀態 enum 應為本尊四值（已排程/已存入/失敗/已提款——原「在途/已入帳」自創詞）、排程二段式（每日/每週+星期/每月+日期，超月末自動調整）、入帳 email 通知勾選、撥款詳情缺收款帳戶/轉移參考編號、匯出餘額交易 CSV（11 欄+7 鍵篩選）。已修 | ✅ |
| 71-R4-BUG1 | BUG | 帳單幣別做成可選 select——本尊＝計費設定檔「管理→切換帳單幣別」對話框且**選項集由公司所在國家/地區決定**（HK 無本地幣別選項⇒呈唯讀）；下一週期生效、換匯含 1.5% 手續費。已改唯讀列＋DOCS 記載「選項>1 才出現管理鈕」 | ✅ |
| 71-R4-BUG2 | BUG | 帳單門檻做成商家可選 select——help 坐實門檻＝平台定義金額（非商家控件），呈現＝週期卡內「距離達到計費門檻所剩的金額」。已改唯讀進度列 | ✅ |
| 71-R4-DOC1 | DOC | 73 號 teardown＋CSS 研究落檔：token 值表（bg/text/語義色/4px 間距/Inter 字級/圓角/inset-bevel 按鈕陰影）＋元件量測（h1 18/600、大金額 24/500、filter tab 選中 bg .08 r8、th 12/500 surface-secondary）＋§5.3 我方 token 映射（鐵律 8/9：記錄不抄用）；help 綜合（稅籍=法域欄位證實 pack 模型/抵用金四類/凍結狀態機/付款方式類型 pack 面） | ✅ |
| 71-R4-V1 | V | 帳務資料的稅務 ID／地址段：dev 店未現（副標有提）；各法域稅籍欄位規則已由 help 落 73 §7.1（AU ABN 11 位+聲明/EU VIES 驗證流轉/SG·MY 無欄位/US·CA 走支援），UI 形態待有資料店複驗 | ⬜ |
| 71-R4-V2 | V | 新增付款方式「類型」select 完整選項（PCI iframe 擋枚舉）；help 給類型集（卡/PayPal/餘額卡＋地區型 ACH/SEPA/UPI/JCB，不收預付卡/虛擬卡）→ pack 宣告面，實測選項清單待補 | ⬜ |
| 71-R4-V3 | V | 帳單詳情正式頁（dev 店 404）：付款時間軸事件型態、交易費區段（Plus 需組織帳單頁匯出才見明細）——待有費用帳單店複驗 | ⬜ |
| 71-R4-V4 | V | 財務導航子項動態化（未啟收款無子項→啟用後「支付款項」）＝導航資料驅動需求，M1 React shell 實作時落地；財務總覽 active 卡組（最近交易/帳戶四總額/稅費卡雙態/Bill Pay 雙態）中「帳戶卡」屬平台金融產品邊界（G15）不建，僅登記 | ⬜ **M4**（84 §3 C-2：財務模組本身在 M4，M1 只需導航殼支援資料驅動） |
| 71-R5-STRUCT1 | STRUCT | 🔴 顧客列表本體＝ShopifyQL 查詢視圖：AI 列 ⌄ 展開即五行查詢編輯器（FROM/SHOW/WHERE/GROUP/ORDER＋icon 條＋autocomplete＋即時「N 位顧客・佔客群 %」）；欄位選擇器＝SHOW 子句 UI 化（18 欄，姓名恆第一）；排序鍵 7×2。已對齊：分群編輯器改五行模型＋icon 條、custColumns 欄位/排序選擇器、SEG_FILTERS 換裝實測全量目錄（18 屬性＋11 事件族＋函式＋metafield 條件，含官方描述） | ✅ |
| 71-R5-MISS1 | MISS | 顧客詳情形態：KPI 第四格=RFM 群組（非 AOV）、「最近一筆已下訂單」單卡＋檢視所有訂單/建立訂單（非全訂單表）、交易時間軸 composer（😊@#🔗＋員工可見注記＋5 分鐘編輯窗）。已修 | ✅ |
| 71-R5-MISS2 | MISS | 更多動作五項（發放商店抵用金/合併顧客/要求顧客資料/清除個人資料〔10 天可取消窗〕/刪除顧客）；帳號動作（邀請/重設密碼）為條件性控件保留。已修 | ✅ |
| 71-R5-MISS3 | MISS | 分群列表：欄=名稱/顧客百分比/上次活動/建立者；系統預設 5 群開店即有（建立者=Shopify、名稱保留英文）；列 ⋯ 五動作（使用分群/複製/匯出/重新命名/刪除，系統群不可刪）。已修（SEGMENTS seed＋segRowMenu） | ✅ |
| 71-R5-MISS4 | MISS | 抵用金表單語義：發放（金額+幣別+到期〔商店時區〕）＋編輯（入帳/扣帳+通知顧客）＋上限 <US$15,000/顧客＋最早到期優先＋B2B 個檔僅限 D2C。已修＋limits.yml customers.store_credit_max_usd | ✅ |
| 71-R5-MISS5 | MISS | B2B 建立式缺「允許顧客運送至任何一次性地址」勾選。已補；方案限制入 limits.yml b2b.*（3 目錄非 Plus/25 目錄每地點/10 級距） | ✅ |
| 71-R5-DOC1 | DOC | 74 號 teardown 落檔：查詢視圖結構/條件目錄全量/合併不可 8 條/刪除不可 4 條/redact 10 天窗/CSV 管線/新版帳號無停用語義/B2B 方案矩陣/員工地址級權限（分析頁不過濾警告）。limits.yml customers 10 鍵＋b2b 3 鍵 | ✅ |
| 71-R5-V1 | V | 顧客列表 view tabs：本尊無 tabs（我方保留 tabbed views 慣例）；「更多檢視」按鈕出自帳單頁，顧客頁是否有 saved views 未證實——R7 訂單輪（saved views 主場）一併裁定 | ⬜ R7 |
| 71-R5-V2 | V | CLV 欄（predicted_spend_tier）在本尊列表/詳情的 UI 呈現位置未實測到（help 坐實條件存在、>100 筆銷售閘門）——有數據店複驗 | ⬜ |
| 71-R5-V3 | V | B2B 建立式我方前置目錄/付款條件二卡（本尊於地點詳情後置）——單地點建立流簡化，是否改為後置待 R10 市場輪連目錄一起看 | ⬜ R10 |
| 71-R5-V4 | V | 付款方式卡（⋯ 傳送更新卡片連結/取代卡片）與寄送 email 表單（主旨 shop.name 代碼/密件副本/檢閱）原型未建——dev 店無 vaulted 卡；M4 顧客實作時落地 | ⬜ M4 |
| 71-R5-V5 | V | metafield 分群條件（customer.[ns]_[key]，四型別）的建立器 UI 與運算子矩陣——待 custom_data 有顧客定義後實測 | ⬜ |
| 71-R6-BUG1 | BUG | 🔴 組合規則過時：我方「同類互斥＋自身類別 disabled」——本尊 2026＝三勾選開放（「商品折扣：每筆訂單可套用多項折扣」原文；同品項商品×商品僅 Plus 走雙向標籤機制；組合選項有 Checkout Extensibility 資格閘門），僅運費×運費硬禁止（免運型不出現運費勾選）。已改（⊕ 展開形態＋收合句原文＋free-shipping 特例）；17 號裁決矩陣複核＝71-R6-V1 | ✅ |
| 71-R6-BUG2 | BUG | 商品折扣「適用於」含「所有商品」＝發明選項（本尊僅 特定商品系列/特定商品；全品折扣走訂單型）。已移除 | ✅ |
| 71-R6-MISS1 | MISS | 四型表單逐欄對齊：卡標題=型名、折扣代碼欄+「產生隨機代碼」link 位置、最低購買要求獨立 radio 卡（無/最低購買金額 (HK$)/最低品項數量；BxGy 無此卡）、使用量限制選項兩勾選原文、BxGy 顧客購買/獲得結構（任何品項選自+以折扣價三選+每筆訂單最高使用次數）、免運 國家/地區二選+排除運費門檻、有效日期 (HKT)。已修 | ✅ |
| 71-R6-MISS2 | MISS | 右欄缺三卡：銷售管道存取權（2026 新；只控展示不控兌換）/摘要詳情 bullets 形態/標籤右欄位。已補 | ✅ |
| 71-R6-MISS3 | MISS | 顧客資格四選項（所有顧客/特定顧客/顧客群/市場）——原型三選項且缺「市場」軸。已修 | ✅ |
| 71-R6-MISS4 | MISS | 推廣語義：分享連結與 QR 共用配額（單折扣僅一個）＋可掛行銷活動帶 UTM＋/discount/{code} 深連結（恢復信取代車內原碼）。已修 discPromote | ✅ |
| 71-R6-DOC1 | DOC | 75 號落檔：組合矩陣 2026 全量＋資格閘門、狀態機（重新啟用清結束日期→limits 鍵）、多幣別口徑（預設幣別儲存+結帳換算，接 65 號）、草稿/POS/訂閱/禮品卡邊界、匯出 only（匯入=超集警示）。limits.yml discount +3 鍵 | ✅ |
| 71-R6-V1 | V | 17 號折扣求值管線裁決矩陣照 2026 規則複核（同品項 Plus 標籤機制/資格閘門/最優惠自動選擇）——M5 折扣引擎實作前必做 | ⬜ M5 前 |
| 71-R6-V2 | V | 固定金額折扣跨幣別換算的捨入規則 help 未載——dev 文件補證後入 65 號矩陣（zero-decimal 幣別的折扣換算是 T 案例候選） | ⬜ |
| 71-R6-V3 | V | 折扣列表頁完整形態（本店零折扣空態）：欄位/11 種篩選/「可與以下類別組合」篩選/組合欄黑框 icon/bulk——建測試折扣後實測或有資料店複驗 | ⬜ |
| 71-R6-V4 | V | Collabs 佣金折扣碼在列表的顯示與報表口徑（help 樹外）——R11 分析輪帶查 | ⬜ R11 |
| 71-R7-BUG1 | BUG | 訂單列表頁首「批次處理近期訂單」＝發明入口（本尊=匯出/更多動作〔顯示分析列〕/建立訂單）——已移除，語義併入導航「運送標籤」子項（本尊同位） | ✅ |
| 71-R7-MISS1 | MISS | 列表缺：出貨期限欄、欄位選擇器（14 欄全集＋隱藏已封存 toggle＋排序依據——原 toast 佔位轉真）、顧客欄 hover card（非列導航）、更多動作=顯示分析列。已修（orderColumns/custHover） | ✅ |
| 71-R7-MISS2 | MISS | 詳情缺：管道資訊卡（管道＋管道側 ID）、轉換摘要卡（3 指標+瞭解詳情；≤48hr 延遲/cookie 空態入 DOCS）、app 管道訂單編輯閘（「此 app 無法編輯此訂單」modal）、更多動作 App 組。已修（orderEditGate 等） | ✅ |
| 71-R7-MISS3 | MISS | 棄單頁缺「升級至全新的未完成結帳作業自動化功能」banner（本尊原文+CTA+可關閉）。已補（位置在標題上=listPage 引擎限制，M1 歸位） | ✅ |
| 71-R7-MISS4 | MISS | orderMore 缺 App 組（物流標籤動作）；措辭對齊（查看訂單狀態頁面/列印訂單頁面/列印裝箱單）。已修 | ✅ |
| 71-R7-DOC1 | DOC | 🔴 兩項裁定落檔（76 號）：①R5-V1 結案——檢視=saved views 家族，live 2026 訂單線=下拉形態（我方 view-chip 同構 ✓）、顧客線無檢視選擇器（我方 tabs=超集註記）；②「撤銷」術語只落分析線（銷售報告 11 組指標），訂單管理線仍「退貨」——我方兩線用詞現狀皆正確。另：狀態機四軸全值域/27 篩選器/bulk 13 動作/訂單號 #1001 不可改/合併訂單無原生/多幣別退款=退款時匯率（65 接口）/地址驗證 19 國=pack 佐證 | ✅ |
| 71-R7-V1 | V | 退貨/換貨建立流與退款執行 UI（退款計算器已抽；退貨核准/檢查/換貨流未實測）——建測試單走全流程後補 | ⬜ |
| 71-R7-V2 | V | 請款/付款條款/提醒 UI（dev 店無授權單）；「即將到期」badge 形態 | ⬜ |
| 71-R7-V3 | V | saved views 建立/重命名/刪除交互（另存為/＋/全部不可編輯）——我方 viewMenu 內容對 6 預設檢視補（含條件性「當地配送」） | ⬜ |
| 71-R7-V4 | V | 詐騙完整分析頁（方案分層：Grow+）＋Flow 高風險範本×4＋Protect 邊界（US only） | ⬜ R11/R13 |
| 71-R7-V5 | V | 多幣別詳情雙幣顯示 UI（help 未載版面）；65 號 T 案例：退款不得由下單換算值反推 | ⬜ M2 前 |
| 71-R8-DOC1 | DOC | 77 號 teardown：庫存欄 8＋檢視三（All/Incoming/Not Fulfillable，本尊無 tab）＋狀態公式（On hand=Committed+Unavailable+Available，Incoming 不在內）＋不可用手動子狀態 4＋調整原因 7＋歷史 8 欄 180 天＋CSV 19 欄僅 4 可寫＋PO/轉移建立式全欄＋系列 2026「來源卡＋排除」＋禮品卡雙鈕與兩套負債邊界 | ✅ |
| 71-R8-V1 | V | 庫存「箱名稱」欄與「Not Fulfillable」檢視我方未實作——M1 庫存頁實作時補 | ⬜ M1-B 邊做邊決定（84 §2 B-1：做庫存頁時定） |
| 71-R8-V2 | V | 🔴 批量編輯器**不建立稽核歷程**（help 明文：設絕對值、無來源/原因）vs 我方 13-F5「ledger 唯一入口」——需裁定我方是否照抄此例外，或要求批量也寫 ledger（偏離則入 §A） | ⬜ M1-B 邊做邊決定（84 §2 B-3：行為裁定不是結構，ledger 表照建） |
| 71-R8-V3 | V | 轉移建立式「連結採購單」欄（PO↔轉移關聯）我方無——資料模型要不要建關聯待定 | ⬜ |
| 71-R8-V4 | V | 2026 系列建立式＝「來源」卡（新增條件/新增商品同卡混用＋排除 negative 條件＋多來源組）vs 我方手動/智慧二分不可互轉（13-F4）——概念差待裁定 | ⬜ M1-B 邊做邊決定（84 §2 B-4：collections 表兩種都撐得住） |
| 71-R8-V5 | V | 庫存 CSV 19 欄與 4 可寫欄（On hand new/Bin name/HS Code/COO）＋防誤覆寫機制——我方匯入器僅 on hand，欄位面待補 | ⬜ M1-B 邊做邊決定（84 §2 B-2：匯入器是獨立元件，欄位面可後補） |
| 71-R9-STRUCT1 | STRUCT | 「網址重新導向」歸屬錯位：我方掛線上商店子項 vs 本尊在**內容區**（內容>選單頁的頁首鈕「網址重新導向」）。已修（導航移除＋GROUP_OF 改 m-metaobjects＋線上商店只留 頁面/偏好設定 兩子項，與本尊一致） | ✅ |
| 71-R9-MISS1 | MISS | 檔案頁缺「從網址上傳」鈕（本尊頁首雙鈕之一）；列表欄七與排序/篩選值域未記。已補鈕＋DOCS 值域（78 §2） | ✅ |
| 71-R9-MISS2 | MISS | 選單詳情用詞與動作：本尊＝名稱＋**控制代碼**（非 handle）＋頁首「更多動作（複製）」。已修 | ✅ |
| 71-R9-DOC1 | DOC | 78 號 teardown（**六層標準首份**）：§0 架構圖（路由樹＋內嵌 app 邊界＋跨頁共用元件家族）／§1-6 值域窮舉（metaobject 狀態 2 值、檔案格式與排序篩選全表、範本 11 型、區塊來源 3 類、搜尋語法全表、留言狀態 3 值、加速結帳按鈕 6+1）；limits.yml +14 鍵（範本 1000/區段 25/區塊 1250/巢狀 8/市場覆寫 250/檔案上限組/效能報表 36hr-90 天） | ✅ |
| 71-R9-V1 | V | 🔴 **架構邊界待裁定**：本尊把線上商店（/themes、/online_store/preferences）做成**內嵌 app**（online-store-web.shopifyapps.com 跨域 iframe，直開回 HMAC validation failed）——我方 M2 主題引擎是否照抄此「銷售管道 app」邊界？影響前台管理面是否獨立服務 | ⬜ M2 前 |
| 71-R9-V2 | V | 佈景主題頁與偏好設定頁**實測未取得**：內嵌 app iframe 在自動化瀏覽器 session 不繪製（2026-08-13 曾誤判為「商店空白/條件閘門」，同日更正——**是工具限制非商店狀態**）。控件事實暫以 help 為準（78 §4/§5），待一般瀏覽器補實測 | ⬜ |
| 71-R9-V3 | V | 本尊預設第三張選單「Customer account main menu」（顧客帳號主選單）我方 MENUS 無——與 R5 顧客帳號線相關 | ⬜ |
| 71-R9-V4 | V | 選單項目「連結」類型下拉全值域（combobox 未展開；help 未逐項列出）——層②未完成項，下次實測補 | ⬜ |
| 71-R9-V5 | V | 佈景主題結構上限已入 limits.yml（範本 1000/區段 25/區塊 1250/巢狀 8）——M2 主題引擎需在編輯器層強制 | ✅ 已落鍵 |
| 71-R10-DOC1 | DOC | 79 號 teardown：§0 架構（路由樹＋🔴**四棵並行文檔樹**＋🔴**三套市場覆寫模型**：主題 4 型／結帳 3 型／一般逐項，粒度＝「該類型停繼承其他續繼承」）／§2 值域窮舉（狀態 2・更多動作 2・市場類型 4・自訂項目 7・稅額顯示 3・關稅 2・匯率 2・網域 3・B2B 配對 3・語言優先序 3 層）／§3 方案矩陣／§5 硬限制 | ✅ |
| 71-R10-DOC2 | DOC | **G13 複核維持**：本尊市場級差異走「主題/結帳區段覆寫」而非「翻譯表 market 維度」——我方刪 translations.market_id 的裁定與本尊架構**不衝突**；日後要做市場差異化內容應走主題區段覆寫。敘述補強於 79 §6 | ✅ |
| 71-R10-V1 | V | 「推出」第二層值域未取得（網路商店佈景主題／結帳頁面和帳號 各自的變更選項清單）——層②未完成項，下次實測補 | ⬜ |
| 71-R10-V2 | V | 🔴 **三套覆寫模型的資料模型設計**：鍵須為 (market_id, target_id, **override_kind**)；主題 4 型 vs 結帳 3 型不可共用實作——**M2 前必答** | ⬜ M2 前 |
| 71-R10-V3 | V | 🔴 Managed Markets 五段金額鏈（保證關稅→+3.5%平台費及稅→+1.5%換匯費以 1/(1-1.5%) 實作→固定匯率換算→**末端 ±2.5% 進位**）進 65 §H 測試矩陣；並持久化「訂單建立時匯率快照」（30 天保證，退款沿用建立日匯率） | ⬜ M2 前 |
| 71-R10-V4 | V | 市場層結帳/主題覆寫的方案閘門（Advanced/Plus）我方是否實作分層——與 B-5~B-8 同屬產品政策，待裁定 | ⬜ |
| 71-R10-V5 | V | 銷售管道市場（Google&YouTube／Meta／TikTok Shop；**agentic storefronts 明文排除**）與我方 AI 代理管道的關係——R13 管道輪帶查 | ⬜ R13 |
| 71-R11-BUG1 | BUG | 「ShopifyQL 進階模式」做成**彈窗模式**（`reportQL()` openGen）——本尊沒有「模式」概念：QL 編輯器**常駐報告主欄**，與右側控制面板、URL `?ql=` 三向雙向同步。已改寫為常駐編輯器＋狀態列＋6 鈕工具列 | ✅ |
| 71-R11-BUG2 | BUG | 報告清單自創 4 個 tab（全部/我的報告/Shopify 報告/最近檢視）——本尊**無 tab 家族**，只有「建立者」「類別」兩個篩選器＋排序鈕。已移除 tab、改為雙篩選器（G12 自創控件第四例） | ✅ |
| 71-R11-MISS1 | MISS | 報告類別值域錯：我方 11 類（照 help 英文版），**實測 13 類**（多「商店」「成效」）。已改 REP_CATS 並註明實測優先 | ✅ |
| 71-R11-MISS2 | MISS | 匯出只有一顆 toast——本尊為彈窗：格式 4 選（CSV 預設／XML／JSONL／**Apache Parquet**）＋範圍 2 選（資料查詢的所有結果〔可能超過 1,000 列〕預設／僅限報表中顯示的結果）。已補完整彈窗 | ✅ |
| 71-R11-MISS3 | MISS | 具名報告動作選單缺（我方只有匯出/另存）——本尊 `⋯`【4】重新命名／匯出／列印／刪除；刪除彈窗「刪除報告？／此動作無法復原」＋紅色破壞鈕＋刪後導回列表。已補三者 | ✅ |
| 71-R11-MISS4 | MISS | 比較基準值域錯（前期/去年同期/不比較）——實測【4】不進行比較（預設）／前一期間／自訂／**目標**（`COMPARE TO TARGETS`）。已修；期間選擇器補齊 7 群組 25 值（含 BFCM 4 年、季度 4 季滾動窗） | ✅ |
| 71-R11-DOC1 | DOC | 🔴 80 號 teardown（**鐵律 12 首份**）：§0 架構（路由樹＋`?ql=` 為第一等狀態＋探索器三向投影＋自由形式 4 槽 vs 組別 5 槽＋條件閘控三形態）／§1 值域窮舉（指標 365/10 類逐項、維度 299/16 類、視覺化 27+2、篩選運算子 7、期間 7 群組 25 值、比較 4、組別定義 5、間隔 3）／§2 ShopifyQL 全語法（子句順序、WHERE 20 運算子、WITH 11 修飾子、日期 8 單位+14 函式+19 具名、時間維度 12、38 schema）／§3 指標公式與撤銷術語 11 組對照／§4 三頁實測／§5 CSS 三段式 8 條／§6 文檔矛盾 8 條＋未載 21 項 | ✅ |
| 71-R11-DOC2 | DOC | 🔴 **BFCM 與季度是滾動窗**（BFCM 取最近 4 年 2022-2025、季度取最近 4 季）——不是固定清單，須以當前日期推導；ShopifyQL 具名範圍 `bfcm2020`–`bfcm2025` 比 UI 多兩年。已於 80 §1.5 落檔 | ✅ |
| 71-R11-DOC3 | DOC | 🔴 **自動命名規則 `{指標} (依 {維度})`**（實測「訂單數 (依 日)」）為儲存彈窗預設值，須照抄；儲存後 URL `/explore` → `/reports/{numeric_id}` 且 `?ql=` 保留。已於 80 §4.3 落檔 | ✅ |
| 71-R11-DOC4 | DOC | 🔴 **兩棵文檔樹 8 條矛盾＋21 項未載**已逐條登記（80 §6）：方案分層自相矛盾／Total sales 三版本公式（Live View 少關稅與費用）／歸因預設值兩說／`app_events` schema 只在 help／比較基準值域 help≠實測／報告類別 11≠13／視覺化型別 23≠27≠cohort 2／`WITH CURRENTLY_UNAVAILABLE` 兩處皆無記載（**我方不得自創**） | ✅ |
| 71-R11-V1 | V | 🔴 **查詢字串是否為我方第一等狀態**：本尊 `?ql=` 承載完整查詢（可覆寫具名報告的儲存值而不改動它）——影響路由設計、分享連結語義、報告儲存格式（存 QL 文字 vs 存結構化 AST）——**M2 前必答** | ⬜ M2 前 |
| 71-R11-V2 | V | 🔴 視覺化型別**三份清單不相等**：freeform UI 27／API `TYPE` 23／cohort 專屬 `retention_curve`＋組別網格——`visualization_type` 建模必須帶 `mode` 維度，不可單表 | ⬜ M2 前 |
| 71-R11-V3 | V | 維度與篩選的可用性**不同源**：`FROM sales` 下維度禁用 3 類（工作階段與行為/庫存/財務與付款），篩選 15 類全可用——不可共用一份 `available_fields`；且類別內不相容項要走「根據現有選取項目無法使用」**降級展示**而非過濾 | ⬜ M2 前 |
| 71-R11-V4 | V | **Web Vitals 40 個指標**（CLS/FCP/INP/LCP/TTFB × 分佈·良好·需改進·不佳·P50·P75·P90·P99，對應 `web_performance` schema）未在我方 19 號 rollup 規格中——補或明確裁定不做 | ⬜ |
| 71-R11-V5 | V | 🔴 **鐵律 3 佐證**：本尊報表層把「支付款項金額」與「支付款項金額（付款貨幣）」當**兩個獨立指標**，另有幣別轉換費用／四捨五入後的付款淨額／現金進位原則——我方 rollup 需同時存店幣與付款幣別兩欄（不是一欄加幣別標籤） | ⬜ M2 前 |
| 71-R11-V6 | V | 「推出」是一等分析維度（`推出 ID`／`推出試驗變項 ID`）——R10 的 rollouts 實作必須輸出這兩個維度到分析層，否則 A/B 測試無法評估成效 | ⬜ M2 前 |
| 71-R11-V7 | V | 商品維度**雙軌**：「產品名稱」（當前值）vs「售出時的產品名稱」（快照）——本尊 2024 改版後預設用當前值，歷史需改用快照欄。我方商品線需雙軌落庫 | ✅ **2026-08-14 落地：`docs/specs/87` ＋ migration**——本尊有 5 個「售出時的」快照維度，我方 `line_items` 只做了 3 個（title/variant_title/sku），**補上 `vendor` 與 `product_type`**。nullable 且**刻意不回填**：既有列補不出正確歷史值，寧可留 NULL 表示「不知道」，也不要用當前值假裝知道。help 佐證：本尊 2024 改版後分析預設用**當前值**，貼近歷史必須改用「售出時的」那組欄位 |
| 71-R11-V7b | V | 🔴 **外鍵讓賣過的商品刪不掉**（做 A-3 時查證 `information_schema` 發現）：`fk_line_items_product_variant_id` 的 `DELETE_RULE = NO ACTION`（＝RESTRICT），只要一個變體被下過單就永遠刪不掉。這與快照設計互相矛盾（快照存在的前提是被參照物可能消失），而**商品刪除是 M1 範圍**（本尊權限樹有獨立的「產品 › 刪除」）。🔴 **不能直接改 `ON DELETE SET NULL`**——外鍵是複合的 `(shop_id, product_variant_id)`，MySQL 要求所有 FK 欄可為 NULL 而 `shop_id` 是 NOT NULL。三個方向見 87 §4.3：①不做硬刪除只封存 ②拆掉變體外鍵改純快照（與 16 §159 先例一致）③刪除時先改寫 line_items。需先確認「我方要不要支援商品硬刪除」 | ⬜ **M1 做商品刪除前必答** |
| 71-R11-V8 | V | **未填值的篩選列不進入查詢**（實測加「已送達訂單數 是 ⟨空⟩」後 ql 仍無 WHERE）——我方須複製「草稿篩選列」概念：UI 有列、查詢無條件、不得報錯 | ⬜ |
| 71-R11-V9 | V | 🔴 **鐵律 3 不放寬**：`WITH CURRENCY '<code>'` 是顯示／換算幣別宣告，**非單位宣告**；官方對 `MONEY` dataType 的序列化格式完全沉默——不得把 Shopify 的 MONEY/WITH CURRENCY 當我方單位契約參照物，65 號四型別維持 | ✅ 判定：維持 |
| 71-R11-V10 | V | ShopifyQL 官方明列陷阱：`!=` / `NOT IN` / `NOT CONTAINS` **不排除 NULL 列**——我方 parser 若照 SQL 三值邏輯直覺實作會與本尊不同；且 `AND` 優先於 `OR`、`min`＝分鐘而 `m`＝月 | ⬜ M2 前 |
| 71-R11-V11 | V | `VISUALIZE`/`TYPE` **只影響編輯器圖表，API 一律只回 table data**——我方 28 號契約應把視覺化型別歸在前端狀態，不進 API 回應 | ⬜ M2 前 |
| 71-R11-V12 | V | 🔴 **總銷售額可為負**（撤銷 > 銷售的日子，官方明列）——我方金額元件與 badge 必須支援負值顯示（tabular-nums 對齊），M1 前確認 | ⬜ **M1-A 動工前必答**（84 §1 A-2：建表約束——金額欄不得設 unsigned/CHECK≥0） |
| 71-R11-V13 | V | 🔴 **AOV 是鐵律 7「數字同源」的官方例外**：分子刻意排除 post-order adjustments ⇒ `AOV ≠ net_sales / orders`，必須有自己的 rollup 分子——**須在鐵律 7 條文加註此例外**，否則實作會「同源」到錯 | ✅ **2026-08-14 裁定：§A G25 照抄本尊例外**——AOV 有自己的 rollup 分子，不共用 net_sales；鐵律 7 已加註具名例外。配套：總銷售額允許負值、any_click 進一致性測試白名單 |
| 71-R11-V14 | V | 🔴 **撤銷款項術語改造**：2026-03-05 生效、2026-07 移除舊欄，11 組欄名對照（returns→sales_reversals 等）——19/76 號欄名需改造，且**保留 `returns` 作為「實體退貨」獨立概念**（兩者不可合併） | ✅ **2026-08-14 落地：`docs/specs/86`**——把「撤銷款項 vs 實體退貨」寫成概念邊界＋欄名契約。🔴 關鍵：`returns` **沒有消失**，它現在專指實體退貨；`sales_reversals` 是退款/退貨/取消/編輯四來源的**聚合指標**。我方無歷史包袱（舊欄名一個都沒建），本檔的價值在讓 M1 起就用對名字。已修訂 19 §F1 的 Total sales 公式（原文漏了訂單編輯、且用「退款」當被減項名）與 AOV 公式（原文 `Total sales/Orders` 是錯的，G25）；CI 新增 `check-reversal-naming.rb` 擋 11 個舊欄名與以指標命名的資源表 |
| 71-R11-V15 | V | 歸因模型**實測 4 種前綴 vs 官方 5 種**（多 `ANY_CLICK_ATTRIBUTION`，且其各通路加總會超過 metric 本身＝設計如此）——spec 應涵蓋 5 種，並把 any-click 列入「小計≠總計」白名單 | ⬜ |
| 71-R11-V16 | V | 組別查詢的 `BETWEEN -1 AND 11` ＋ `HAVING >= 0` 組合（取 13 期再濾第 -1 期，讓 `_totals` 算得出完整基期）——照抄時不可簡化成 `BETWEEN 0 AND 11` | ⬜ M2 前 |
| 71-R11-V17 | V | AI 提示列產出**三件套**（QL ＋ 自然語言說明 ＋ quick filter 狀態），不只查詢字串；追問態文案「調整搜尋範圍」——我方 AI 分析入口需比照 | ⬜ |
| 71-R11-V18 | V | 實測未觸發項：QL **語法錯誤態**（狀態列/parseErrors 呈現）、`?` 說明面板內容、`⌨` 快捷鍵清單、註解 annotations 建立流、目標 targets 建立流、列印輸出形態——下輪或 M2 實作前補實測 | ⬜ |
| 71-R12-STRUCT1 | STRUCT | 🔴 **權限模型整代落差**：本尊 2026 已改 **RBAC 且使用者掛組織層**（`/settings/organization-account`，底下有 角色／安全性 兩子頁；橫幅原文「以角色為基礎的存取控制現已啟用」）＝**使用者↔（群組）↔角色↔權限** 四段模型；我方是商店級 staff checkbox（舊模型）。已在原型補角色目錄卡（10 角色/4 類別）與安全登入規定，但**資料模型改造排 M1 前必答**——角色是組織層資源可跨店，與鐵律 2「全表帶 shop_id」直接衝突 | ✅ **2026-08-14 裁定：§A G24 窄範圍豁免**——身分與權限表（8 張，逐表列舉）不帶 shop_id，白名單以外照舊；🔴 豁免的是「表有沒有 shop_id 欄」不是「查詢可不可以不帶」。展示層原型已補（角色目錄卡＋安全登入規定）。**RBAC 資料表實作仍在 M1**，但地基問題已解 |
| 71-R12-STRUCT2 | STRUCT | 品牌歸屬錯位：本尊在 **`/settings/general/branding`（一般的子頁）**，我方是頂層設定分頁。已在一般設定補「商店資產」卡建立正確進入路徑（中繼欄位／品牌），完整歸屬對齊排 M1 | ⬜ M1-B 邊做邊決定（84 §2 B-6：純導航，R12 已補正確進入路徑） |
| 71-R12-MISS1 | MISS | 商店活動記錄（`/settings/general/activity`）我方完全沒有。已補「資源」卡＋`storeActivityLog()` 彈窗，含三條硬約束（**最多 250 筆**／**唯讀不可展開·篩選·匯出**／執行者三型 人員·app·銷售管道） | ✅ |
| 71-R12-DOC1 | DOC | 🔴 **權限分組 help 19 群 ≠ 實測 17 群**（同一批權限、不同分組邊界：Inventory/Catalogs/Files/Companies/Apps 在實測是子標題不是群組）⇒ 裁定：**UI 照實測樹、語義照 help 描述**。已把原型 permCats 由 6 類彙總換成實測 17 群 115 權限全量 | ✅ |
| 71-R12-DOC2 | DOC | 🔴 **建立角色需 step-up auth（重新輸入密碼）——help 完全未載，實測發現**；移除使用者也需輸入自己的密碼。已入 `limits.users_and_roles.step_up_auth_required_for` | ✅ |
| 71-R12-DOC3 | DOC | **G13 再次複核維持**：Translate & Adapt 的 Adapt ＝「同語言的市場專屬覆寫」（Sweaters vs Jumpers，需 `en-GB` 這類 subtag 且該語言須已加入某 market）——它走「語言 × 市場」而非「翻譯表帶 market_id」，與 R10-DOC2 結論一致，**G13 仍成立** | ✅ |
| 71-R12-DOC4 | DOC | 🔴 81 號 teardown（實測＋help 雙源，433 行）：§0 架構（設定＝全螢幕覆蓋層／**組織+商店兩層側欄**／RBAC／設定樹映射表 本尊 20↔我方 23）／§1 使用者與權限（角色 10/4 類・權限 115/17 群/3 層・父子真連動・step-up auth・安全性頁）／§2 一般設定九卡／§3 通知 4 子區＋**11 組 47 範本**（help 未窮舉，實測補齊）／§4 語言與 Translate & Adapt／§5 CSS 三段式 8 條／§7 help 層 14 節含矛盾表與未載 12 項。limits.yml +7 節 63 鍵 | ✅ |
| 71-R12-V1 | V | 我方 `giftcards` 設定分頁在本尊設定樹**不存在**：到期日與 Apple Wallet 在**設定›付款**、自動出貨在**設定›一般**；但 help 權限表又把「Gift cards」列為 Settings 項目（**兩份官方文檔互相矛盾**）。已在該頁加註說明，歸屬待 M1 前裁定 | ⬜ M1-B 邊做邊決定（84 §2 B-5：純導航歸屬，設定頁重組時搬） |
| 71-R12-V2 | V | **角色 create→delete 全流程未走完**：儲存角色被 step-up auth（輸入密碼）擋下，我不輸入密碼。權限目錄本身已完整取得（新增角色表單即完整目錄）。下輪若要補，需使用者本人操作或授權其他驗證方式 | ⬜ |
| 71-R12-V3 | V | 🔴 **時區與語言是使用者層級不是商店層級**（本尊一般設定明文「若要變更您的使用者層級時區和語言，請前往您的帳號設定」）——我方做成商店級單一值。影響：訂單時間顯示會因人而異；需 `user.timezone`／`user.locale`。已在原型欄位加註 | ✅ **2026-08-14 隨 G24 migration 落地**：`staff_members.timezone`（預設 Asia/Hong_Kong）與 `.locale`（預設 zh-Hant）已建 |
| 71-R12-V4 | V | **通知範本集合受法域閘控**（實例：「已建立訂單層級退貨單（**僅限美國**）」）⇒ 47 個範本的清單要進 jurisdiction pack，不是固定表（鐵律 11） | ⬜ M2 前 |
| 71-R12-V5 | V | 翻譯編輯器在本尊是**獨立 app（Translate & Adapt，新增語言時自動安裝）**，不是內建畫面——與 R9-V1「線上商店＝內嵌 app」邊界同源。我方 70 號是自建內建面板，邊界待裁定 | ⬜ M2 前 |
| 71-R12-V6 | V | 🔴 **權限依賴是圖不是樹**（實測＋help 雙證）：授予往上補齊祖先鏈、撤銷往下連動移除；且 **Inventory/Catalogs 任一權限 → Products>View 且不可取消**。help 明載沒有任何互斥關係，唯一「不可組合」是角色不得跨類別混用權限 | ⬜ **M5**（84 §3 C-3：🔴 依賴圖是角色編輯器的邏輯不是權限表的結構——表只需 role_permissions(role_id, permission_key)） |
| 71-R12-V7 | V | **help 的 7 個 predefined roles**（線上商店編輯／客服／商品企劃／行銷＋POS×3）**實測角色清單未出現**（實測 10 列＝管理角色扣掉兩個擁有人角色）——顯示條件待查（方案？管道？需手動加入？） | ⬜ |
| 71-R12-V8 | V | **邀請有效期 7 天，且 help 未提供「重寄邀請」或「取消邀請」的獨立操作**（官方做法＝移除後重新新增）——我方要不要多做重寄鈕（多做即偏離，需入 §A） | ⬜ |
| 71-R12-V9 | V | **使用者群組 Groups 是 Plus 專屬的第四段**（使用者↔群組↔角色↔權限）：指派 group 即獲得其全部角色、可屬多個 group、刪 group 會從所有成員收回角色與商店指派。實測未出現（本店無 group）——我方是否實作這一層 | ⬜ **M5**（84 §3 C-4：G24 已預留 user_groups/user_group_roles 兩張表，建了不用不會錯） |
| 71-R12-V10 | V | 🔴 **品牌顏色的資料模型**：Liquid `shop.brand.colors.primary` 與 `secondary` **都是陣列，每個元素是 background/foreground 配對**（`primary[0].background`）——**不是「一主色一副色」**。另：品牌資產**不可依市場或語言本地化**（可引為 G13 佐證）；favicon 非獨立欄位（square logo 縮 32×32）；**字體欄位＝文檔未載** | ⬜ M2 前 |
| 71-R13-DOC1 | DOC | 🔴 82 號 teardown（實測＋help/shopify.dev 雙源）：§0 架構（**管道全部是 app**，路由 /apps/{handle}，線上商店為第一方特例走 /themes；**發布模型三層 AND** Publishable×Publication×Catalog）／§1 代理式全頁（4 個 AI 管道＋詳情浮卡的「發現來源 vs 結帳位置」兩軸＋2 個資料來源＋補充條款）／§2 **UCP 全貌**／§3 POS（Lite/Pro 完整對照＋權限 9 群組＋計價）／§4 app（4 型＋2026-01-01 分界＋protected data 三級）／§5 第一方管道清單／§6 CSS 三段式 7 條。另：`agentic_sales_channel` 這個識別字**官方文檔查無**，R11 是從實測維度清單取得——以實測為準 | ✅ |
| 71-R13-DOC2 | DOC | 🔴 **R12-V1 結案（實測直證）**：`/settings/gift_cards` **302 → `/settings/payments?hasMovedNavItem=true`**——query 參數自己講明「導航項目已搬家」。禮品卡設定（到期日／Apple Wallet）在**付款**底下，自動出貨在**一般**底下。我方 `giftcards` 設定分頁應拆併進付款（歸屬修正排 M1） | ✅ 結案 |
| 71-R13-V1 | V | 🔴 **POS 範圍需使用者裁定**（本輪最需要決定的一條）：本輪只做管道殼與分析，**POS 本體完全沒做**（smart grid／register session 現金追蹤／員工 PIN／班次／換貨／收據範本／小費）。help 的 **Lite vs Pro 對照表**是現成的分層原型——**Lite ≈ 收銀機**（能收錢·退款·改庫存數量）**／Pro ≈ 門市營運系統**（換貨·取消·履行·庫存追蹤·日報表·零售角色）。裁定要回答：①做不做 POS ②若做，做到 Lite 還是 Pro ③per-location 計價要不要照抄 | ✅ **2026-08-14 裁定：§A G26 不實作 POS**——理由是 POS 是第二個產品不是模組（硬體/離線/裝置/PIN/班次/現金抽屜＋權限模型完全不同）。**保留活口**：訂單來源標記、地點、員工歸屬三個欄位面。任何輪次不得因「本尊有 POS」建議補做 |
| 71-R13-V2 | V | 🔴 **資料模型：`App` 之下的 `Channel`**（帶 channel capability），不是兩張平行表。實測直證：管道與 app 的 `⋯` 選單完全相同【開啟應用程式／檢視詳情／解除安裝】，安裝流程同樣走 App Store，權限同樣是「管理和安裝應用程式與管道」一條。管道 app 只是多三項強制功能（帳號連接／商品發布／市集導航） | ⬜ M2 前 |
| 71-R13-V3 | V | 🔴 **主題引擎必須支援「受限 render context」**：`agents.md.liquid` 只有 `request` 與 `agents` 兩個物件可用（`shop`／`collections` 等全域物件**不可用**），且 `agents.md`／`llms.txt`／`llms-full.txt` 三個 template **不可為 JSON template**。`agents` 物件屬性：store_url／ucp_discovery_url／mcp_endpoint_url／ucp_versions／currency／sitemap_url。與現有 template context 不是同一套——M2/M6 前必須確認引擎支援 | ⬜ M2 前 |
| 71-R13-V4 | V | **發布模型三層 AND** 有四個掛載點要同步：商品頁的上架管道區塊／目錄（R10）／市場（R10）／代理式目錄。help 原文：商品必須**同時**「在該管道市場指派的目錄內」**且**「已發布到該管道」才會上架。另：新增管道時既有商品**預設全開**；排程發布需商品為 Active、不支援單一 variant、Shop 管道不支援；`publicationCreate/Update` 單次上限 50 個商品 | ⬜ **M1-A 動工前必答**（84 §1 A-5：三層 AND 是三張表的關係，不是布林欄） |
| 71-R13-V5 | V | **POS 設定頁未驗證**：快捷鍵清單有「前往『設定：銷售點 (POS)』**GST**」，但我猜的 `/settings/point_of_sale` 得 404，設定搜尋「銷售點」只回 地點／POS 通知／新增地點／顧客通知。依鐵律 12.1 **不寫「本尊沒有這頁」**——判定為條件閘控（需 POS Pro 或已設定地點），待有 POS 的店補實測 | ⬜ |
| 71-R13-V6 | V | 🔴 **POS 權限模型與 admin 完全不同**：①走 **organization role 而非 store permission** ②**只能指派角色，不能指派單一權限** ③粒度以**「裝置所在地點」為軸**（多條權限寫明 "for their location"）④POS Lite 地點 role 限制**不生效**（所有 admin user 皆 full access）。照 admin 的資源樹套 POS 會做不出「檢視裝置所在地點的分析」這種語義。補完 R12-STRUCT1 的權限模型全貌 | 🚫 **因 §A G26 不適用**（84 §3 C-5：已裁定不實作 POS，本條不再掛任何里程碑） |
| 71-R13-V7 | V | 🔴 **B-7／UCP 待決案有答案了**（技術面不再是未知）：UCP＝Shopify 與 Google 共同開發的開放標準，規格全文在 **ucp.dev**，開發者入口 shopify.dev/docs/agents。五個 MCP 端點（Global Catalog／Storefront Catalog／Cart／Checkout／Order）、能力協商用 platform profile（`meta.ucp-agent.profile`）、支援版本 2026-04-08·2026-01-23·draft、checkout 四態、**`update_cart`/`update_checkout` 是 PUT 語義（省略欄位會被移除）**、agent 只能查自己促成的訂單、擴充採 reverse-domain 命名無中央審批。**剩下的是產品決策**：我方要不要做 UCP 相容層 | ✅ **2026-08-14 裁定：§A G27 UCP 延後至 M6 後評估**——在有商店有商品前實作沒意義。但 `agents.md.liquid` 的**受限 render context 現在就要吃進主題引擎設計**（見 R13-V3，仍 M2 前必答） |
| 71-R13-V8 | V | 第一方管道清單的兩條事實影響我方管道規劃：①**Amazon 與 Walmart 已併入 Shopify Marketplace Connect**，不再是獨立第一方管道 ②社群商務只有 Facebook/Instagram·TikTok Shop·**Roblox**（無 Pinterest、Snapchat）。另 **Handshake 的退場官方無公告**（僅第三方來源），**官方不維護「已下架管道清單」** | ⬜ |
