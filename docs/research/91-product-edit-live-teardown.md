# 91 — 商品編輯頁 2026 實測 teardown（鐵律 12 六層，取證 2026-08-23）

> 起因：使用者 2026-08-23 裁定「商品編輯頁面你並沒有做到1:1的ui和功能對齊。你給我深度分析和體驗
> 整個商品編輯頁面，把所有的ui和功能補上」＋「你必須連css等等都要細緻到對齊……深度去體驗和點擊
> 他每一個按鈕，每一個欄位，每一個選單」。
> 方法：測試店 `chill-love-u5q5mnzq`（12.2 全權授權），商品 9907070533867
> （Frederic Malle Rose Tonnerre EDP Spray 100ml/3.4oz，單變體），使用者 Chrome 親自點擊；
> DOM 收割一律遞迴穿透 shadowRoot（2026 admin 幾乎全頁 shadow DOM，普通 querySelector 取不到）；
> popover 值域以截圖為準（部分選項不帶 `role=option`）。
> 差距表與實作包切分在 §18；未竟項（V）在 §17，逐項待補，**不得以「沒看到」當「沒有」**（鐵律 12.1）。

## 0. 版面骨架

- 兩欄：主欄約 856px 卡片流＋右側欄（狀態／發布／組織分類）；卡片白底、圓角、陰影，卡間距一致。
- 頂列（sticky）：返回箭頭＋商品標題＋狀態 badge｜右側 預覽／分享／更多動作▾／︿﹀上下商品導航。
- dirty 時頂列**整段被 SaveBar 取代**（含搜尋列消失）：「⚠ 未儲存的變更」＋捨棄＋儲存（黑底主鈕）。
  捨棄＝還原快照無確認框（本輪實測：開了選項編輯器→捨棄→直接回乾淨態）。
  ⇒ 與我方 44 §22.5 SaveBarContext 行為一致，已實作。

## 1. 頁首列

| 控件 | 實測 |
|---|---|
| 預覽 | 開前台商品頁（新分頁） |
| 分享 | **實測（2026-08-23 補測）**：商店有密碼保護時，點擊直接彈 dialog「移除密碼保護／若要分享商品，請移除您網路商店的密碼保護。」＋取消｜前往偏好設定（黑底）。⇒ 分享是**條件性控件**（三源判定：實測看得到鈕、行為由商店狀態決定），不是單純複製連結 |
| 更多動作▾ | menu：複製商品｜封存商品｜🗑刪除商品（紅字）｜✉建立電子郵件行銷活動｜Localize |
| ︿﹀ | 上一個／下一個商品（列表序） |
| 狀態 badge | 「啟用中」綠底 pill，緊貼標題右側 |

## 2. 狀態卡（右欄第一卡）

select 展開＝3 選項，**每項帶描述副行**（我方現行只有純文字 option，差距）：

| 值 | 主文 | 副行 |
|---|---|---|
| ACTIVE | ✓啟用 | 透過已選擇的銷售管道與市場進行銷售 |
| DRAFT | 草稿 | 不會顯示在已選擇的銷售管道或市場 |
| UNLISTED（2026 新） | 未刊登 | 僅能透過直接連結存取 |

- **封存不在 select 裡**——只能走「更多動作→封存商品」。⇒ 狀態機：select 三態＋封存單向動作。
- 我方**已裁定四態**（13 §F1.2 真值表＋`limits.yml` `product.status_values`＝ACTIVE/DRAFT/ARCHIVED/UNLISTED，
  purchasable/discoverable 雙 scope；GraphQL enum 已四值）——本項無需新裁定，V-91.2 改為
  「UNLISTED 的 admin picker＋storefront noindex 落地」追蹤項。

## 3. 標題＋說明（RTE）

- 標題 placeholder：「短袖 T恤」。
- RTE toolbar 全量（逐鈕實測）：產生文字(AI)｜格式設定(段落▾)｜粗體｜斜體｜底線｜顏色｜對齊方式｜
  連結｜插入圖片｜插入影片｜插入表格｜其他控制▾［項目符號清單｜編號清單｜減少縮排｜增加縮排｜
  清除格式設定］｜顯示HTML(`<>`)。
- **格式設定▾ 值域（補測）**：段落｜標題 1｜標題 2｜標題 3｜標題 4｜標題 5｜標題 6｜引言
  （選單內以各級實際字級渲染預覽，標題 1 最大遞減至標題 6 與內文同級；引言帶左側直線）。
- **顏色 值域（補測）**：popover 上方兩 tab「文字｜背景」，內容＝飽和度／明度方塊＋右側色相直條＋
  hex 輸入（現值 `#000000`）＋兩排色票（第一排 7 彩：紅橙黃綠藍靛紫；第二排 8 階灰：黑→白）。
- 對齊方式下拉值域仍未展開（V-91.3 餘項）。

## 4. 媒體卡

- 縮圖網格＋新增按鈕；tile 點開行為、alt 編輯、排序拖曳未實測（V-91.4）。

## 5. 定價卡

- 價格 input：**HK$ 前綴段**＋千分位顯示「2,606.00」（blur 後格式化）。
- pills 列（單一 chevron 在**列尾**，整列共用一個展開區）：
  `比較價格 HK$3,455.00`｜`單價`｜`收取稅金 否`｜`每品項成本` ＋ ˅
- 展開區＝「其他顯示價格」標題＋原價 HK$ input ⓘ＋單價 select（現值 `--`）＋
  ☐對此商品課稅 checkbox＋單列：成本[input] 利潤 `--` 利潤率 `--`（成本未填時利潤顯示 `--`）。
- ⇒ 我方現行把比較價／成本／taxable 做成平鋪欄位；本尊是 pills 摘要＋共用展開，UI 形態差距。

## 6. 庫存卡（單變體、追蹤中）

- per-location 表：`地點｜無法供貨｜已承諾｜可供貨｜現有庫存`，行「Shop location 0 / 0 / 1 / 1」，
  可供貨與現有庫存為可編輯數字欄。
- 「檢視調整記錄」link（未點，V-91.5）。
- pills：`存貨單位(SKU) 3700135018495`｜`條碼 3700135018495`｜`無庫存時繼續銷售 關閉`。
- ⇒ 四數語義＝11 §3 庫存四態（available/committed/on_hand/unavailable），與 ledger 規格對得上。

## 7. 運送卡

- 「實體商品」toggle 在卡右上。
- 包材 select：現值「商店預設 • 樣品箱：8.6 × 5.4 × 1.6 吋，0 lb」ⓘ（選單值域未展開，V-91.6）。
- 商品重量 `0.47`＋原生 select 單位＝**lb｜oz｜kg✓｜g**（全量）。
- pills：`原產地國家/地區`｜`HS 代碼`（展開未實測，V-91.7）。

## 8. 類別卡

- 「未分類」select＋hint 原文：「決定稅率並新增中繼欄位，以改善搜尋、顧選和跨管道銷售。」
- 選單值域（Shopify 分類樹 autocomplete）未展開（V-91.8）。

## 9. 子類（選項）——2026 新 flow，與原型不同

1. 點「⊕新增尺寸或顏色等選項」→ popover：搜尋 input＋「沒有可用的相容中繼欄位」＋「⊕建立自訂選項」。
   ⇒ **2026 版把「選項」跟 metafield 打通了**：優先建議掛相容 metafield，自訂選項是 fallback。
2. 點「建立自訂選項」→ 卡內 inline 編輯器：拖曳把手 ⠿＋右上 metafield 圖示｜
   選項名稱 input（placeholder 尺寸）｜選項值 input（輸入「中」後出現下一空列）｜
   `刪除`（紅字）｜`完成`（黑底）｜卡底「⊕新增其他選項」。
3. 開編輯器即 dirty（SaveBar 出現）；完成前捨棄＝整段還原。
- ⇒ 對應我方 63 §B.4 productSet options/variants 樹；UI 形態（popover→inline editor→完成）需照抄。

## 10. 商品中繼欄位卡

- 「檢視全部」「新增定義」按鈕＋既有欄位列（Fecify product ID＝131661，app 定義）＋「⊕Disclosures」。

## 11. SEO 卡（「搜尋引擎產品資訊」）

- 收合態＝SERP 預覽：站名（CHILL LOVE）→ 麵包屑 URL（`https://chill.deals › products › <handle>`）→
  藍色標題連結 → 描述兩行 → **價格列「HK$2,606.00 HKD」**（商品頁特有）。右上 ✏️ 展開。
- 展開態三欄位：
  - 頁面標題：計數器「已使用 60 / 70 個字元」。
  - Meta 描述：計數器「已使用 **203 / 160** 個字元」——**超限允許儲存，只變計數**，無錯誤態。
  - 網址控制代碼：`products/` 前綴段＋handle input＋下方完整 URL 預覽。
- ⇒ DB 已有 `seo_title`/`seo_description` 欄；handle 我方鎖定不可改（HandleChangePending 裁定），
  本尊可改（改 handle 觸發 301 redirect 選項——redirect 對話框未實測，V-91.9）。

## 12. 組織分類卡（右欄）

| 欄位 | 形態 | 值域／行為 |
|---|---|---|
| 產品類型 | search-or-create combobox | placeholder「搜尋或新增產品類型」；輸入「香」→「沒有結果」＋「⊕新增『香』」 |
| 廠商 | autocomplete | 既有廠商按字母排序清單 |
| 商品系列 | autocomplete 多值 | 未深測（V-91.10） |
| 標籤 | token 多值＋右上「編輯」 | 編輯開管理對話框（未點，V-91.10） |
| 佈景主題範本 | select | 現值「預設商品」；值域未展開（V-91.11） |

## 13. 發布卡／銷售卡

- 發布：「線上商店」列＋「管理發布」⚙ →**實測（補測）**：開 **modal**「管理〈商品名〉的發布」，
  左欄分類「銷售管道 3｜代理式 1」，右側搜尋框「搜尋銷售管道」＋群組主開關（半選態橫線）＋
  逐管道 toggle：線上商店（開）｜銷售點（關）｜Shop（關）；底部 取消｜完成（完成預設 disabled，
  無變更時不可按）。⇒ 發布是 **product × channel 的多對多**，不是商品上的布林欄位；
  我方發布卡現行三個 SwitchRow 是簡化形，正式實作要照這個 modal 形態（G11）。
- 銷售：「此商品近期無銷售紀錄」＋「檢視詳情」。

## 14. Localize → Translate & Adapt（多語言，配 109 號 SHOPLINE 研究對照）

- 更多動作→Localize＝進 T&A app（URL `/apps/translate-and-adapt/localize/product?id=…&shopLocale=zh-TW`）。
- 版面：左欄資源清單「顯示 13/10000 個項目」；主區 3 欄表：欄位名｜參考（來源：英文）｜繁體中文
  （可編輯，說明欄兩側皆 RTE）；列＝標題／說明／網址控制代碼／Product type。
- 頂列：「自動翻譯」按鈕＋locale 切換「正在翻譯 繁體中文▾」＋資源型別「商品▾」；首次進入 5 頁導覽 modal。
- ⇒ 本尊做法＝**獨立翻譯工作台**（資源×語言×欄位三維表），非 SHOPLINE Asia 的「編輯頁內嵌多語欄位」。
  兩案對照與我方 67 號的裁定影響全文見 `docs/research/109-shopline-multilingual.md`。

## 15. CSS 量測（getComputedStyle，shadow-walk）

> 🔴 **2026-08-28 引用守衛（G12b）：本節的 4 個 `500` 是污染值，未複驗前不得引用。**
> 污染源與機制＝`docs/design/111` §20。**本尊沒有 500 這一階** ⇒ 「字重 500」本身就是污染指紋。
> ⚠️ G12 的射程只點名「第 19 節」，**本節被漏掉了**。
> 🔴 **本節的 label 那一列另有一個已被證偽的結論**：「⚠ 字重差 50，我方 `64` §3 定 450 …
> **不改 token**，登記觀察」——本檔 **§19.6 row 2** 已量到該 label 的乾淨值就是 **450**，
> **與我方 token 一致、根本沒有差異** ⇒ 該條建議作廢，**不得依它去「登記觀察」或維持任何差異**。
> ✅ **2026-08-28 已完成乾淨重量 ⇒ 見本檔 §15.1**（4 列，**全部更正**）。
> 🔴 **兩項的錯不只字重**：pill 的單一「500」對應**兩個**真值（button 本體 **400**＝原生 UA 預設／
> 標籤文字 **450**）；狀態 badge **字級也錯**（13px→**12px**，量到不繪製的 host），字重 500→**550**。
> label 的乾淨值 **450** 已由本節與 §19.6 **兩條獨立路徑**各自量到。

| 元件 | 本尊實測 | 我方 token | 判定 |
|---|---|---|---|
| pill（帶值按鈕） | h 28px、radius 8px、padding 4px 8px、透明底、13px/500 | --h-28 / --r-200 / --sp-100 --sp-200 / --fw-control | ✅ 逐格吻合 |
| text input | h 32px、13px/500、ink `#303030` | --h-32 / --t-sm | ✅ |
| label | 13px / **500** / lh 20px | --t-sm / **--fw-body 450** | ⚠ 字重差 50：2026 實測 label=500，我方 64 §3 定 450。**量測歸研究、實作走我方 tokens**（鐵律 12.3 第 4 層原則），不改 token，登記觀察 |
| 狀態 badge | 13px/500、綠底 pill（收合於標題旁） | badge tokens 既有 | ✅ |
| 主色 ink | `rgb(48,48,48)`＝#303030 | --text #1a1c1e | 我方自有識別（鐵律 8/9），不抄 |

## 16. 我方已對齊項（免重做）

SaveBar 取代搜尋列＋捨棄快照還原＋dirty 偵測；價格 HK$ 前綴＋兩位小數；狀態卡兩維
（badge＋可購買性）；handle 唯讀（編輯態）；STALE_OBJECT toast；空態卡；lockVersion 送回。

## 17. 未竟項登記（V-91.x，逐項待補實測；不得當「沒有」）

~~V-91.1 分享選單值域~~ **已測**（§1：密碼保護 dialog）｜V-91.2 UNLISTED 已裁定（13 §F1.2）——admin picker P1 已落地、storefront noindex 屬 G12｜V-91.3 RTE 下拉：格式設定與顏色**已測**（§3），對齊方式待補｜
V-91.4 媒體 tile 深測｜~~V-91.5 檢視調整記錄頁~~ **已測**（93 §3：180 天空態＋記錄列格式＋七原因）｜V-91.6 包材選單值域｜V-91.7 原產地/HS 展開｜
V-91.8 類別樹 autocomplete｜V-91.9 handle 修改→301 redirect 對話框｜V-91.10 系列/標籤編輯對話框｜
V-91.11 佈景範本值域｜~~V-91.12 管理發布~~ **已測**（§13：channel 多對多 modal）｜※V-91.13 見下行｜~~V-91.13 多變體變體表~~ **已測**（93 §1–2：親手建三變體品，建立態/編輯態/子頁全形態）｜
V-91.14 「產生文字」AI 面板。

## 18. 差距表 → 實作包（本輪起逐包部署 bt3）

| # | 差距 | 後端 | 前端 | 包 |
|---|---|---|---|---|
| G1 | 組織分類卡整卡缺（類型/廠商/標籤/範本） | products 已有 vendor/product_type/tags 欄；productSet 需收 | combobox＋token 欄 | **P1** |
| G2 | SEO 卡缺（SERP 預覽＋計數器＋handle 段） | seo_title/seo_description 欄既有；productSet 需收 | 收合預覽＋展開三欄 | **P1** |
| G3 | 狀態 select 無描述副行；封存不在 select | — | 自訂 listbox | **P1** |
| G4 | 定價 pills＋共用展開形態 | — | pills 列重構 | P2 |
| G5 | RTE（現為 textarea） | descriptionHtml 既收 | toolbar＋contenteditable | P2 |
| G6 | 庫存 per-location 表＋pills | 庫存 ledger（M1 里程碑項） | 表格 | P3 |
| G7 | 運送卡（重量/單位/包材） | 需欄位＋遷移 | | P3 |
| G8 | 頁首更多動作（複製/封存/刪除） | productDelete/duplicate mutation | menu | P3 |
| G9 | 媒體卡 | 媒體管線（M1 里程碑項） | | P4 |
| G10 | 子類選項編輯器 | 63 §B.4 options 樹已定 | inline editor | P4 |
| G11 | 類別/中繼欄位/發布卡（發布＝product×channel 多對多 modal，§13 補測） | taxonomy＋metafield＋publications 架構 | | P4 |
| G12 | SEO/GEO 前台落地（meta/JSON-LD/llms.txt） | storefront 渲染層 | — | 與 P1 同步開題 |

P1 驗收單位＝「組織分類＋SEO＋狀態 picker 三合一」，走 D40（分支→PR→雙 CI 綠→自合→bt3 部署）。

---

## 19 🔴 商品詳情頁表單與側欄的 CSS 量測（補 §15）（層④ CSS 三段式，2026-08-28）

> 🔴🔴 **2026-08-28 引用守衛：本節的全部 `font-weight` 值一律待複驗，未複驗前不得引用。**
>
> 本節量測時，使用者 Chrome 的一個擴充功能正在注入
> `body, body :not(svg)… { font-weight: 500 !important }`（全文＝`docs/design/111` §20）。
> 它把字重**雙向**改寫（450 拉高、550 壓低成同一個 500）⇒ **看到 500 無法回推真值**。
> 🔴 **shadow DOM 也不是無條件免疫**——`font-weight` 會沿 flattened tree 繼承進 shadow，
> 未自宣告它的繪製盒同樣被污染（`111` §20.3）。
>
> ⚠️ **font-size／line-height／color／letter-spacing／間距／圓角／陰影不受影響**，那些值仍可引用。
>
> ✅ **2026-08-28 已完成乾淨重量 ⇒ 見本檔 §19.6**（24 列：更正 9／一致 14／未取得 1）。
> **引用本節任何字重值前先對照 §19.6。** 同型元件另見 `docs/research/77` §7.6。


> 全域 token 值表、頁面骨架與視覺規律＝`docs/design/111-shopify-token-baseline.md`。
> 涵蓋排查與缺口＝`docs/design/110-css-measurement-coverage.md`。
> 🔴 **鐵律 9**：只記 `getComputedStyle` 算出來的值，不含本尊樣式表原始碼、選擇器定義或可執行片段。
> ⚠️ §15 已量過一部分；本節只補它沒涵蓋的，衝突逐條登記於 19.4。

### 19.0 量測環境

> 量測日期 2026-08-28。Chrome（Claude in Chrome），測試店 chill-love-u5q5mnzq。`window.innerWidth`＝**1024 CSS px**（`innerHeight` 551–607，同一輪內視窗高度有變動、寬度全程 1024）；`getComputedStyle(document.documentElement).fontSize`＝**16px**（瀏覽器預設，無 47 §F 記過的根字級污染）；`devicePixelRatio`＝1。所有數值取自 `getComputedStyle`（computed 值），未複製任何 Shopify 樣式表原始碼。DOM 為 Web Component ＋ open shadow root（`s-internal-*`），以遞迴 `el.shadowRoot.querySelectorAll('*')` 穿透；本頁未遇到 closed shadow root。🔴 **工具陷阱（影響後續量測輪）**：`mcp__claude-in-chrome__computer` 的 `zoom` 動作會把該分頁的 viewport **改成 region 尺寸且不還原**（本輪一次 zoom 後 innerWidth 由 1024 變 510 並鎖住，只能關掉分頁重開）；且 region 不得超出目前 viewport，故 zoom 無法用來放大 viewport。`ctrl+minus` 頁面縮放被工具明文拒絕，本 MCP 亦無 resize_window ⇒ **本輪無法在 1280 寬度量測**。

### 19.1 本畫面用到的 token 值

| 類別 | 量測值 | 取值選擇器 |
|---|---|---|
| 版面（page layout，:root computed） | --pg-navigation-width 15rem(240px)｜--pg-top-bar-height 3.5rem(56px)｜--pg-control-height 2rem(32px)｜--pg-layout-width-primary-min 30rem(480px)／-max 41.375rem(662px)｜--pg-layout-width-secondary-min 15rem(240px)／-max 20rem(320px)｜--pg-layout-width-inner-spacing-base 1rem(16px)｜--pg-layout-width-outer-spacing-min 1.25rem(20px)／-max 2rem(32px)｜--pg-layout-width-one-third-width-base 15rem｜--pg-layout-width-one-half-width-base 28.125rem｜--pg-bottom-bar-max-height 21.875rem | getComputedStyle(document.documentElement) |
| 間距階（--p-space-*） | 0｜025 .0625rem｜050 .125rem｜100 .25rem｜150 .375rem｜200 .5rem｜250 .625rem｜300 .75rem｜400 1rem｜500 1.25rem｜600 1.5rem｜700 1.75rem｜800 2rem｜1000 2.5rem｜1200 3rem｜1600 4rem｜2000 5rem｜2400 6rem｜2800 7rem｜3200 8rem。語義：--p-space-card-padding 1rem／--p-space-card-gap 1rem／--p-space-table-cell-padding .375rem／--p-space-button-group-gap .5rem／--p-space-badge-padding-inline .5rem／--p-space-choice-size 1rem | :root |
| 圓角階（--p-border-radius-*） | 0｜050 .125rem｜100 .25rem｜150 .375rem｜200 .5rem｜300 .75rem｜400 1rem｜500 1.25rem｜750 1.875rem｜full 624.9375rem。語義：container .75rem(12px)／control .5rem(8px)／control-inner .25rem／action .5rem／element .5rem／option-item .5rem／popover .75rem／dialog 1rem／focus .25rem／checkbox .25rem／tag .5rem／tag-inner .375rem／preview .25rem／media clamp(.25rem, round(25%,.125rem), .5rem) | :root |
| 邊框寬度階（--p-border-width-*） | 0｜0165 **.04125rem＝0.66px**｜025 .0625rem(1px)｜050 .125rem(2px)｜100 .25rem(4px)｜outline-input-focus `.125rem solid #005bd3` | :root |
| 字級階（--p-font-size-*） | 275 .6875rem(11)｜300 .75rem(12)｜325 .8125rem(13)｜350 .875rem(14)｜400 1rem｜450 1.125rem｜500 1.25rem｜550 1.375rem｜600 1.5rem｜750 1.875rem｜800 2rem｜900 2.25rem｜1000 2.5rem。語義：body-large .875rem／body-medium .8125rem／body-small .75rem／body-x-small .6875rem／heading-large .875rem／heading-medium .8125rem／heading-small .75rem／button-label .75rem／details-text .75rem／input-label .8125rem／input-label-small .75rem | :root |
| 字重階（--p-font-weight-*） | regular **450**｜medium **550**｜semibold **600**｜bold **650**｜button-label 550｜input-label 450｜input-label-small 450｜details-text 450｜heading-small/medium/large 600｜display-small 600／display-medium/large 650。🔴 **階梯裡沒有 500** | :root |
| 行高（--p-font-line-height-*） | 300 .75rem｜400 1rem｜500 1.25rem｜600 1.5rem｜700 1.75rem｜800 2rem｜1000 2.5rem｜1200 3rem。語義：body-medium 1.25rem(20px)／body-small 1rem／heading-medium 1.25rem／button-label 1rem／details-text 1rem／input-label 1.25rem／input-label-small 1rem | :root |
| 控件高度（--p-height-*） | 025 .0625rem｜050 .125rem｜100 .25rem｜150 .375rem｜200 .5rem｜300 .75rem｜400 1rem｜500 1.25rem｜600 1.5rem｜700 1.75rem｜800 2rem｜900 2.25rem｜1000 2.5rem｜1200 3rem｜1600 4rem｜2000 5rem｜2400 6rem｜2800 7rem｜3200 8rem。語義：**--p-height-field-min-block-size 2rem(32px)** | :root |
| 表單控件顏色（--p-color-input-*，本輪逐態實測全部吻合） | bg-surface #fdfdfd｜bg-surface-hover #fafafa｜bg-surface-active(focus) #f7f7f7｜bg-surface-error #fee8eb｜bg-surface-ai #f8f7ff｜border #8a8a8a｜border-hover #616161｜border-active #1a1a1a | :root |
| 底色 | bg-surface #fff｜-hover #f7f7f7｜-active #f3f3f3｜-secondary #f7f7f7｜-tertiary #f3f3f3｜-selected #f1f1f1｜-disabled #0000000d｜-inverse #303030｜-overlay #ffffffcc｜-critical #fee8eb｜-caution #fff8db｜-warning #fff1e3｜-success #cdfed4｜-info #eaf4ff｜-highlight #f0f2ff｜-ai #f8f7ff | :root |
| 文字色 | text #303030｜-secondary #616161｜-tertiary #616161｜-disabled #b5b5b5｜-inverse #e3e3e3｜-link #005bd3（hover #004299／active #002e6a）｜-critical #8e0b21（secondary #c70a24）｜-warning #5e4200｜-caution #4f4700｜-success #014b40｜-info #003a5a｜-highlight #005bd3｜-ai #5700d1 | :root |
| 描邊色 | border #e3e3e3｜-hover #ccc｜-secondary #ebebeb｜-tertiary #ccc｜-disabled #ebebeb｜-focus #005bd3｜-highlight #005bd3｜-critical #fec1c7（secondary #8e0b21）｜-caution #ffeb78｜-warning #ffc879｜-success #92fcac｜-info #a8d8ff｜-inverse #616161 | :root |
| 圖示色 | icon #4a4a4a｜-hover #303030｜-active #1a1a1a｜-secondary #8a8a8a｜-secondary-hover #616161｜-tertiary #8a8a8a｜-disabled #ccc｜-critical #e22c38｜-warning #b28400｜-caution #998a00｜-success #047b5d｜-info #0094d5｜-highlight #005bd3｜-ai #8051ff｜-inverse #e3e3e3 | :root |
| 陰影（卡片／區塊） | 卡片實際 computed 值（六層堆疊，最外層為 1px hairline，**沒有 CSS border**）：`rgba(0,0,0,0.03) 0 5px 5px -2.5px, rgba(0,0,0,0.02) 0 3px 3px -1.5px, rgba(0,0,0,0.02) 0 2px 2px -1px, rgba(0,0,0,0.03) 0 1px 1px -0.5px, rgba(0,0,0,0.04) 0 0.5px 0.5px 0, rgba(0,0,0,0.06) 0 0 0 1px`。對應 token 名＝--p-shadow-section／--p-shadow-container（兩者同值）。其他階：--p-shadow-100/200/300/400/500/600、-popover、-dialog、-toast、-banner、-control-knob 皆存在；--p-shadow-input* 全系列 computed 為**空字串**（輸入框改用 inset box-shadow 直接寫，見 §2） | s-internal-section::shadow > section |
| 商品頁專屬 token | --locations-table-cell-horizontal-padding .5rem｜--locations-table-cell-vertical-padding .75rem｜--locations-table-activator-icon-width 1.25rem | :root |

### 19.2 元件量測（27 項）

| # | 元件 | 量測 | 狀態樣式 |
|---:|---|---|---|
| 1 | **頁面兩欄容器（主欄／側欄）** | 🔴 **兩欄切換是 container query 不是 media query**：`s-internal-page::shadow > main` 的 computed `container-type: inline-size`、`container-name: s-internal-page`。本輪 container 寬＝**768px**（viewport 1024 − nav 240 − 16），此寬度下 `aside` 排在 main 之下＝**單欄**（aside y=1922，在主欄最後一張卡之後）。main 736px 內容欄＋左右各 16px（main w=768、padding 16px 0；卡片 x=256 w=736）。`#AppFrameScrollable` w=784、`main#AppFrameMain` w=1024、nav 240px、top bar 56px。aside 自身 display:flex／column／gap 16px。主欄卡片列 display:flex／column／**gap 16px**（逐張實測：112+721→849、849+137→1002…全部 16px；側欄 1948+92→2056、2056+126→2198… 亦全部 16px） | 單欄（container 768px）＝已實測；兩欄形態與主／側欄寬度比＝未取得（見 not_obtained） |
| 2 | **卡片（Section）容器** | bg #fff｜border-radius **12px**｜**border: 0px none**（hairline 由六層 box-shadow 的最外層 `rgba(0,0,0,0.06) 0 0 0 1px` 提供）｜box-shadow 見 §1｜寬 736px（1024 下主欄側欄同寬）。padding 兩制：①**16px**（Status／Publishing／Sales／Product organization／Theme templates／Variants／Metafields 空殼）②**0px**（Title+Description、Price、Inventory、Shipping、SEO — 這些卡自行管理內部區塊 padding，例如 Price 卡內層 `16px 16px 8px`、Title 卡內層 16px）。巢狀子 section（卡中卡，如 Theme template）：bg transparent、radius 0、padding 0、w 704（外卡內容寬） | hover／selected 無變化（卡片本身非互動元件） |
| 3 | **卡片標題（h2）與標題列** | h2：**13px / 600 / line-height 20px / rgb(48,48,48) / margin 0**（host `s-heading` 為 display:contents，host 上的 fw 是 450 或 500，**實際渲染值在 shadow 的 h2＝600**）。標題列：flex、gap 8px、高 20px；無尾端動作時列寬＝704（滿版），有尾端 icon 鈕時列寬 664（＝704 − 32 − 8）。Modal 級標題（s-internal-heading，如 Keyboard Shortcuts）＝14px / 600 / lh 20px | — |
| 4 | **文字輸入框（Title，s-internal-text-field）** | 欄位群組高 56px＝label 20px ＋ **gap 4px** ＋ 控件 32px。label：13px / **450** / lh 20px / #303030。控件盒：min-height **32px**、border-radius **8px**、padding **0 12px**、bg rgb(253,253,253)、**border: none**，hairline＝`rgb(138,138,138) 0 0 0 **0.66px** inset`。input：13px / 450 / lh 20px / #303030、bg 透明、padding 0。placeholder：13px / 450 / **rgb(97,97,97)**。輔助／錯誤文字容器 `#describedby`：12px / 450 / lh 16px / rgb(97,97,97)、與控件 gap 2px（無內容時 display:none）。transition: all | rest bg #fdfdfd＋inset ring #8a8a8a 0.66px｜**hover** bg **rgb(250,250,250)** ＋ inset ring **rgb(97,97,97)** 0.66px（真實滑鼠 hover 實測）｜**focus-visible**（真實點擊）bg **rgb(247,247,247)** ＋ inset ring **rgb(26,26,26) 1px** ＋ `outline: rgb(0,91,211) solid 2px`、`outline-offset: 1px`｜程式 `.focus()` **不會**觸發（需真實點擊或鍵盤）｜disabled／error 未取得 |
| 5 | **帶前綴的金額輸入（Price／Compare-at）** | 整欄寬 **224px**（固定寬，非滿版）×32px。外框＝**獨立的覆蓋 div**：bg rgb(253,253,253)、**border: 1px solid rgb(138,138,138)**、radius 8px。前綴「HK$」：13px / **500** / rgb(97,97,97)、左內縮 12px（x 284 vs 框 272）、寬 26.9px。input：x=344−… 起於 x=317（前綴右緣 310.9 → 約 **6px** 間隙）、padding `6px 12px 6px 0`、min-height 32px、13px / **500** / #303030、bg 透明。欄位群組：label 20px ＋ gap 4px ＋ 控件 32px，卡片內底部再留 8px | hover／focus 未逐態量（框在覆蓋層上，狀態色與 §1 input token 同源）；disabled／error 未取得 |
| 6 | **帶前綴的 URL handle 輸入（SEO 展開後）** | 框 **704×32**（滿版）、bg rgb(253,253,253)、**border 1px solid rgb(138,138,138)**、radius 8px。前綴（網域段）寬 60.1px、x=284（左內縮 12px）、13px / 500 / rgb(97,97,97)。input x=344（**與前綴零間隙**，與金額欄的 6px 不同）、寬 631.9、padding `6px 12px 6px 0`、13px / 500 / #303030 | 未逐態量 |
| 7 | **數字輸入（Shipping → Product weight）** | input 125.1×32、padding **6px 12px**（左右對稱，與金額欄不同）、min-height 32、13px / **500** / #303030、bg 透明。覆蓋框 div：bg rgb(253,253,253)、**border 1px solid rgb(138,138,138)**、radius 8px。無 spinner（appearance: none） | 未逐態量 |
| 8 | **Textarea（SEO meta description）** | 704×**90px**、padding **6px 12px**、min-height 32px、**resize: none**、13px / 500 / lh 20px / #303030、font-family `Inter, "Noto Sans Arabic"…`。覆蓋框 radius 8px。量測當下滑鼠停在其上，框為 hover 態：bg **rgb(250,250,250)**、border **1px solid rgb(97,97,97)**（rest 應為 #fdfdfd／#8a8a8a，見 input token） | hover 已實測（見上）；rest／focus／disabled 未逐態量 |
| 9 | **Select（s-internal-select，重量單位 lb/oz/kg/g）** | 視覺框：h **32px**、bg rgb(253,253,253)、radius 8px、padding **`6px 8px 6px 12px`**（右 8px 讓出 caret）、hairline `rgb(138,138,138) 0 0 0 0.66px inset`、內部 gap 8px。值文字 13px / 450；尾端 `s-icon` caret **20×20**。寬度隨內容（本例 54.9px）。label 13px / 450 / lh 20px（此例為視覺隱藏，w=1px） | 未逐態量；option 為原生 <option>（UA 樣式） |
| 10 | **單選 Picker 欄位（Status／Type／Vendor／Category／Theme template）** | 控件：h **32px**、bg rgb(253,253,253)、radius 8px、padding **`6px 8px 6px 10px`**（左 10px，**比文字輸入框的 12px 少 2px**）、hairline `rgb(138,138,138) 0 0 0 0.66px inset`、內部 gap 8px。值文字起於 x=282（左內縮 10px）；尾端 caret 容器 **20×20**、右內縮 8px。有可見 label 時群組高 **56px**（label 20 ＋ gap 4 ＋ 控件 32）；label 視覺隱藏時（Status／Theme template）群組高 32px。label 13px / 450 / lh 20px。Category 值旁另有 **16×16、radius 6px** 的清除鈕 | 未逐態量（popover 開啟態本輪未展開） |
| 11 | **多選 Picker 欄位（Collections／Tags）** | 群組高 **61.5px**＝label 列 21.5 ＋ gap 4 ＋ 控件 **36px**。控件：h **36px**（比單選 picker 高 4px）、padding **8px**、radius 8px、bg rgb(253,253,253)、同 0.66px inset hairline。label 列 padding-right 8px，右端另有 20×20 icon。placeholder 文字「Add collections」／「Add tags」 | 未逐態量 |
| 12 | **Switch（s-internal-switch：Inventory tracked／Physical product）** | 軌道＝input 本身：**32×16px**、border-radius **9999px**、padding `0 2px`、border 1px solid transparent；**checked 時 bg rgb(48,48,48)**。label 列：display flex、gap 8px、padding `4px 0`、高 24px。輔助文字容器 12px / 450 / lh 16 / rgb(97,97,97)、gap 2px | checked(on) 已實測；**off 態未取得**（本頁兩個 switch 皆為 on，且不得改資料） |
| 13 | **Pill（帶值按鈕：Compare-at／Unit price／Charge tax／Cost per item／SKU／Barcode／Sell when out of stock）** | button：h **28px**、radius **8px**、padding **4px 8px**、bg **transparent**、內部 gap **4px**、13px / 500 / lh 20px。**pill 標籤文字實際渲染在內層 `<p>`，色 rgb(97,97,97)**（外層 div 是 #303030，內層 p 明確覆蓋成次要色）。pill 之間水平間距 8px（例：Compare-at 272→448.7，Unit price 起 457） | hover／active 未逐態量 |
| 14 | **Pill 內的值徽章（s-internal-badge）** | chip：h **20px**、bg **rgba(0,0,0,0.06)**、radius **8px**、padding **2px 8px**；文字 **12px / 550 / lh 16px / rgb(97,97,97)**。chip 與 pill 標籤間距 4px（pill gap） | — |
| 15 | **富文本編輯器容器（Description，TinyMCE）** | 外框：**704×214**、**border 1px solid rgb(138,138,138)**（真 border，與文字輸入框的 0.66px inset 不同）、radius 8px、overflow hidden。內容區容器：bg rgb(253,253,253)、radius `0 0 8px 8px`、h 176。iframe：min-height **150px**、實際 176。**iframe 內 body：14px / 400 / line-height 19.6px（1.4）/ color rgb(48,48,48) / bg rgb(253,253,253) / margin `9.6px 12px` / font-family `-apple-system, BlinkMacSystemFont, "San Francisco"…`** — 與 admin 主體的 13px / 450 / Inter **完全不同**（TinyMCE content CSS 未接管理台 token） | 未逐態量 |
| 16 | **富文本工具列** | 工具列：**h 36px**、bg **rgb(247,247,247)**、padding **6px 8px**、radius `8px 8px 0 0`、**無下邊框／無分隔線**。內部按鈕列高 24px。圖示鈕：**24×24**、radius **4px**、padding 2px、bg transparent、色 rgb(74,74,74)、fs 12px。含下拉的鈕（Color／Alignment／Insert table）寬 **40px**（icon＋caret）；Paragraph 下拉寬 100px。**群組內按鈕 gap 4px、群組之間 gap 8px**（分組純靠間距，無 divider 線）；「Generate text」自成首組（後面群組 margin-left 8px），「Show HTML」以 padding-left 8px 分離於最右。 | **hover：bg rgba(0,0,0,0.05)**（真實滑鼠 hover 實測，Bold 鈕）；rest transparent；transition: all。active／selected 未取得 |
| 17 | **媒體區（Media）格線與 tile** | 格線：**grid-template-columns 112.328px ×6**（＝1fr×6）、**gap 6px**、總寬 704。主圖 tile 跨 2×2 ＝ **231×231**；一般 tile **112×112**。已上傳 tile：`button` border **1px solid rgb(204,204,204)**、radius **8px**、bg #fff；內層圖片容器 radius **7px**（8−1），`<img>` 229×229。骨架／佔位 tile：bg rgb(227,227,227)、radius 8px。**新增（+）tile**：112×112、bg **rgb(247,247,247)**、**border 1px dashed rgb(204,204,204)**、radius 8px、padding 8px、置中 icon 20×20。選取遮罩：bg **rgba(0,0,0,0.5)**、radius 8px；選取 checkbox 20×20、距 tile 角 **6px** | **拖放中（drop-active）覆蓋層**（DOM 內存在但 display:none）：bg rgb(247,247,247)、**border 1px solid rgb(26,26,26)**、radius 8px、padding 8px ⇒ 拖放態是「虛線變實線＋描邊變 #1a1a1a」。hover 未取得 |
| 18 | **Inventory per-location 表（本頁唯一可量的表格樣板）** | ARIA grid ＋ CSS grid，`grid-template-columns: **155px 149px 127px 134px 137px**`（合計 702，第一欄最寬、其餘數值欄近等寬）。表頭列 **h 36px**：bg **rgb(247,247,247)**、文字 **12px / 500 / lh 16px / rgb(97,97,97)**、padding **`6px 6px 6px 12px`**、**border-bottom 1px solid rgb(227,227,227)**。資料列 **h 48px**：bg #fff、文字 **12px / 500 / lh 16px / rgb(48,48,48)**、cell 本身 padding 0（內距在內層元素）。表格外框 radius `12px 12px 0 0`（下方接「View adjustment history」列）。相關 token：--locations-table-cell-horizontal-padding .5rem／-vertical-padding .75rem | 列 hover／selected 未取得 |
| 19 | **Metafield 列與卡片頁尾帶** | 列：`display grid`、**grid-template-columns 211.188px 484.812px**（≈30% / 70%）、**gap 8px**、padding `2px 0 2px 8px`、列高 36px、容器寬 712（**比卡片內容寬 704 多 8px，靠負邊距外溢**，x=264 vs 卡片內容 272）。label：13px / 500 / lh 20px / #303030。**卡片頁尾帶**：整卡寬 736、h **38px**、bg **rgb(247,247,247)**、padding **8px 12px**。頁尾內的「+ Disclosures」chip：h **21px**、bg **rgb(227,227,227)**、radius 8px、padding `0 6px`、13px / 500 / #303030 | 未逐態量 |
| 20 | **SEO SERP 預覽（Search engine listing）** | 站名：**14px / 450 / lh 20px / rgb(48,48,48)**｜URL 麵包屑：**12px / 450 / lh 16px / rgb(97,97,97)**｜標題連結：**18px / 500 / lh 24px / rgb(0,91,211)**｜描述：**13px / 450 / lh 20px / rgb(97,97,97)**（2 行，h 40）｜價格行：13px / 450 / lh 20px / rgb(97,97,97)。垂直節奏（實測 y）：站名 296(h20) → URL 316(h16) → 標題 341(h21) → 描述 370(h40) → 價格 416 ⇒ 段間約 0／9／8／6px | — |
| 21 | **字元計數器（SEO Page title／Description）** | **12px / 500 / lh 16px / rgb(97,97,97)**、寬滿版 704。實測值為「296 of 160 characters used」（**已超限**）而顏色**仍是 rgb(97,97,97)，未轉 critical 紅** | 超限態＝已實測（不變色） |
| 22 | **SaveBar（未儲存變更列）** | 🔴 **不是頁面底部或頂部另起的固定條，而是渲染在深色 top bar（bg rgb(10,10,10)、高 56px）內、取代搜尋框的膠囊**。容器：x=240、y=10、**w 518.1、h 36px**、bg **rgb(40,40,40)**、**border-radius 12px**、**box-shadow: none**、自身 `z-index: auto`（不另起層）。內列 padding `4px 4px 4px 8px`。左側「Unsaved changes」：13px / 500 / **rgb(238,238,238)**、圖示與文字 gap 8px、x=248。動作組 gap **4px**。**Discard**：h 28、radius 8、padding `6px 8px`、bg **rgba(255,255,255,0.12)**、文字 rgb(238,238,238) 13px/500。**Save**：h 28、radius 8、padding `6px 8px`、w 48、bg **rgb(252,252,252)**、文字 **rgb(18,18,18)** 13px/500。出現／消失有垂直滑移動畫（截圖捕捉到中間態） | **Discard hover：bg rgba(255,255,255,0.12) → rgba(255,255,255,0.15)**｜**Save hover：bg rgb(252,252,252) → rgb(238,238,238)**（皆為真實滑鼠 hover 實測）。dirty 期間頁首「Share」鈕轉 disabled（灰） |
| 23 | **表單底部 Save 按鈕列（supplementalEnd）** | 頁面最底另有一個 Save：button **h 28**、w 52.1、bg **rgb(48,48,48)**、文字 #fff、radius 8、padding `6px 12px`、min-height 28、內部 gap 2px；三層 inset 陰影 `rgba(0,0,0,0.8) 0 -1px 0 1px inset, rgb(48,48,48) 0 0 0 1px inset, rgba(255,255,255,0.25) 0 0.5px 0 1.5px inset`（＝primary button 立體樣式）。所在列：右對齊、寬 736、padding `16px 0`、列高 60px | — |
| 24 | **卡片右上 icon 動作鈕（SEO 鉛筆／Publishing 設定／Product organization 資訊）** | **28×28**、radius **8px**、padding **4px**、bg transparent、圖示色 **rgb(138,138,138)**、svg **16×16**、cursor pointer、fs 12px / fw 550 | hover 未取得 |
| 25 | **發布通路列（Publishing 卡：Online Store／All catalogs）** | 列：flex、gap 4px、icon 20×20、文字起於 x=294（＝列 x 270 ＋ 24）。🔴 **實測到 UA 預設外洩**：該 `<button>` 未重設字體，其子孫 computed **font-size 13.3333px、color rgb(0,0,0)**，而外層脈絡是 13px / rgb(48,48,48)。⇒ 這是本尊自身的樣式瑕疵，我方**不應照抄** | hover 未取得 |
| 26 | **Disabled 按鈕（primary，深色底）** | h 28、w 77、radius 8、padding `6px 12px`、bg **rgba(0,0,0,0.17)**、文字 **#fff**、fs 12px / fw 550、**opacity: 1**（不靠透明度）、**cursor: auto**（非 not-allowed）、box-shadow none | 註：此為離屏 modal 內的按鈕，非商品表單控件；**表單欄位的 disabled 態未取得** |
| 27 | **區塊說明段落（Sales 卡「No recent sales of this product」等）** | 13px / **450** / lh 20px / **rgb(97,97,97)**、margin 0。與「View adjustment history」列同型（13px / 450 / rgb(97,97,97)）。Media 區的「Media」文字是 **paragraph（13px / 450 / #303030）而非 s-heading** | — |

### 19.3 觀察到的視覺規律

1. 🔴 **兩欄／單欄由 container query 決定，不是 viewport media query**：`s-internal-page::shadow > main` 帶 `container-type: inline-size; container-name: s-internal-page`。⇒ 我方 RWD 驗證若只掃 viewport 寬度會量錯斷點；正確的自變數是「頁面內容容器寬」＝viewport − 240(nav) − 16。1024 viewport → container 768 → 單欄。
2. 🔴 **同一頁存在兩套 hairline 技法**：新的 web-component 層（s-internal-text-field／select／picker）用 **`0 0 0 0.66px inset` box-shadow**（對應 --p-border-width-0165 .04125rem），舊的商品表單自製欄位（金額、重量、textarea、URL handle）用 **真 `border: 1px solid`＋一個絕對定位的覆蓋 div**。兩者靜態視覺接近但 focus／hover 行為與盒模型不同 ⇒ 我方應**只選一套**（建議 inset ring，因為不吃盒寬）。
3. 🔴 ~~**字重 500 不在 token 階梯裡**（階梯是 450／550／600／650）。凡量到 fw 500 的元素（金額輸入、pill、metafield label、SERP 標題、SaveBar 文字、表格 cell）都是**舊 React 表單層的硬編碼**；新 web-component 層一律 450／600。這正好解釋 91 §15 的字重矛盾。~~
   > 🔴🔴 **2026-08-28 撤回整條**：那些 500 **不是舊 React 層的硬編碼**，是**量測環境污染**（`docs/design/111` §20）。本尊**沒有 500 這一階**，乾淨直方圖 `450×981 / 550×187 / 600×4`。同型元件的乾淨值見 `docs/research/77` §7.6 與 `docs/design/113` §1.6。
4. 間距全部落在 4px 倍數上：卡片間距 16、卡片 padding 16、label↔控件 4、控件內距 6/8/10/12、pill 內距 4/8、工具列群組 4/8、媒體格線 6（**唯一的非 4 倍數**）。
5. 圓角只有三階在用：**12px（卡片／SaveBar 膠囊／表格外框）、8px（所有控件、pill、badge、媒體 tile、圖示鈕的 8px）、4px（RTE 工具列鈕）**；另有 7px（媒體 tile 內層＝8−1 border）與 6px（Category 清除鈕 16×16）兩個補償值。
6. 控件高度只有三階：**32px（輸入框／select／單選 picker，＝--p-height-field-min-block-size）、36px（多選 picker、RTE 工具列、SaveBar 膠囊）、28px（pill、SaveBar 按鈕、卡片 icon 鈕、通路列）**。表格：表頭 36 / 資料列 48。
7. 輸入框三態只改「底色＋描邊色」，**不改邊框寬度概念、不位移、不加陰影**：#fdfdfd/#8a8a8a → hover #fafafa/#616161 → focus #f7f7f7/#1a1a1a(1px)。focus 另加**外部 outline 2px #005bd3、offset 1px**（＝--p-border-width-outline-input-focus），不是 box-shadow ring。
8. 卡片沒有 border：hairline 是六層陰影堆疊的最後一層 `rgba(0,0,0,0.06) 0 0 0 1px`。⇒ 抄成 `border: 1px solid #e3e3e3` 會少掉上方四層柔和投影，且盒寬會差 2px。
9. 次要文字一律 rgb(97,97,97)（#616161）：placeholder、輔助文字、pill 標籤、表頭、SERP 描述／URL、字元計數器、前綴符號。主文字 rgb(48,48,48)（#303030）。
10. 「一列多個摺疊欄位」的 pill 列是本尊在商品頁的主要密度手段（Price／Inventory 卡各一列 ＋ 右端 chevron 展開），pill 本體透明、只有值以 6% 黑底的 12px/550 badge 呈現。
11. 卡片頁尾用一條 bg #f7f7f7、h 38px、padding 8px 12px 的滿寬帶（Metafields 卡）承載「新增」chip — 與卡片主體同一個 12px 圓角容器內、無分隔線。
12. RTE 是唯一沒有接上 admin token 的區域（iframe 內 14px/400/1.4/-apple-system），工具列則完全接上（#f7f7f7、24px 鈕、4px 圓角）。

### 19.4 🔴 與既有量測文件的衝突（照登記，未逕行覆寫）

1. 🔴 **與 `docs/research/91` §15「label 13px / **500**」衝突**：本輪量到 `s-internal-text-field` 的 label（Title）為 **13px / 450 / lh 20px**，且 `:root` token `--p-font-weight-input-label` ＝ **450**、`--p-font-size-input-label` ＝ .8125rem、`--p-font-line-height-input-label` ＝ 1.25rem，三者互相佐證。⇒ 91 §15 記的 500 應是量到**舊 React 表單層**的欄位標籤（金額欄／metafield label／pill 標籤確實是 fw 500），而不是 web-component 的 input label。**91 §15 的「⚠ 字重差 50，我方 64 §3 定 450」這個結論因此要翻案：我方的 450 與本尊新層一致，衝突的是本尊自己的兩層。** 建議 91 §15 那一列改記兩個值並標明各自的元件族。

2. 與 `docs/research/91` §15「pill h 28／radius 8／padding 4px 8px／透明底／13px 500」＝**本輪逐格複驗吻合**（無衝突），但 91 未記 pill 內部 gap 4px、標籤實際色 rgb(97,97,97)、以及值徽章的 `12px/550/rgba(0,0,0,0.06)/radius 8/padding 2px 8px` — 這三項是本輪新增。

3. 與 `docs/research/91` §15「text input h 32、13px/500、ink #303030」：高度與色吻合，**字重不同**（本輪 web-component input 實測 450）。同上翻案理由。

4. 與 `docs/research/91` §15「主色 ink rgb(48,48,48)＝#303030」＝吻合（token --p-color-text #303030）。

5. ⚠️ **未與 `docs/design/47`／`docs/design/64` 逐項比對**（本輪未讀該兩檔，指派只要求讀 91）。本輪測到的全域階梯（間距 4 倍數、圓角 12/8/4、控件高 32/36/28、根字級 16px）與 --p-* token 原值已完整列在 §1，請主控代理拿去與 47 §F／64 §3 對表；~~若 47／64 記的字重階含 500，同樣適用上面的「兩層並存」翻案。~~
   > 🔴🔴 **2026-08-28 撤回：方向正好相反。** 「兩層並存」翻案已被證明是污染造成的假象。`docs/design/110` 的 **G12** 明文：**未複驗前不得引用 `47`／`64` 的任何字重值**，更不得拿本節的結論去「翻案」它們。

### 19.5 未取得（鐵律 19.3）

- **兩欄佈局的實測寬度比與欄間距**：viewport 鎖在 1024（container 768）＝單欄。取得方式＝在 viewport ≥ 1280（container ≥ 1024）重量一次；工具面需要能設定視窗尺寸的能力（本 MCP 的 `zoom` 只能縮小且會鎖死 viewport，`ctrl+minus` 被拒）。**可用替代線索（token 值，非渲染量測）**：--pg-layout-width-primary-min/max 30rem/41.375rem、--pg-layout-width-secondary-min/max 15rem/20rem、--pg-layout-width-inner-spacing-base 1rem ⇒ 上限形態應為 662 : 320、欄間距 16px，但**這是 token 值不是實測比例，不得當成已驗證**。
- **container query 的臨界值**：Shopify 樣式表跨網域（cdn.shopify.com），`document.styleSheets[].cssRules` 不可讀；且本輪不得複製 CSS 原始碼。取得方式＝在多個 viewport 寬度下二分實測 aside 的 x/y 何時進入右欄。
- **變體表格（多變體商品的變體列表）**：本輪量測商品為單變體（卡片顯示「Add options like size or color」空態），無變體表可量。指派的五個保護商品含唯一的多變體測試品（9907126370539）故未碰。取得方式＝另找非保護的多變體商品，或參照 `docs/research/93` §1–2 已測形態。
- **表單欄位的 disabled 態**（bg／border／文字色／cursor）：本頁所有商品表單欄位皆可編輯，找不到 disabled 欄位。僅取到一顆離屏 modal 的 disabled primary button。取得方式＝進入變體子頁或封存態商品，或用 token（--p-color-bg-surface-disabled #0000000d／--p-color-text-disabled #b5b5b5／--p-color-border-disabled #ebebeb）對照。
- **表單欄位的 error／critical 態**：未觸發（觸發需提交非法值，且本輪唯讀不得按 Save）。token 側已知：--p-color-input-bg-surface-error #fee8eb、--p-color-border-critical #fec1c7、--p-color-text-critical #8e0b21；**渲染後的實際 ring 寬度與訊息列間距未取得**。
- **Switch 的 off 態顏色**：本頁兩個 switch（Inventory tracked／Physical product）皆為 on，且不得改資料。取得方式＝在唯讀的其他頁面找 off 態 switch。
- **Pill／多選 picker／卡片 icon 鈕／媒體 tile 的 hover 與 active 態**：本輪只對 Title 輸入框、RTE Bold 鈕、SaveBar 兩顆按鈕做了真實滑鼠 hover。
- **Picker popover（下拉面板）的量測**：未展開任何 picker（Status／Type／Vendor／Collections／Tags／Category）。popover 相關 token 已取（--p-border-radius-popover .75rem、--p-shadow-popover），但面板實際尺寸／選項列高／搜尋列未取得。
- **Price／Inventory 摺疊 pill 列展開後的完整欄位群組**：右端 chevron 未點開。
- **行動／平板寬度（390／768）下的商品表單形態**：本輪僅 1024 一個寬度（鐵律 13.1 的三裝置對比未做）。
- **Shopify 主題色以外的暗色模式**：admin 目前為淺色，未量暗色 token（:root 上未見 dark 覆寫值）。

---

## 19.6 🔴 乾淨環境重量（2026-08-28，G12 補完）

> 本節依**鐵律 19.5**追加，**上方原記載保留原文**。
> 觸發＝`docs/design/110` 的 **G12**：本檔的 `font-weight` 值曾在受污染的環境下量測。
> 污染源與機制＝`docs/design/111` §20。
>
> **全部數值以「停用污染源 → 讀 clean → 還原 → 讀 dirty」的同步配對取得**，
> 收工已還原成使用者原狀並複驗。
>
> ⚠️ 只有 `font-weight` 受污染；font-size／line-height／color 等在兩種環境下相同——
> 但本輪**一併複驗**了它們，因此下表也含非字重的更正（那些屬「量錯層」或原記載本身有誤）。

**本節結果：24 列（更正 9／複驗一致 14／未取得 1）**

| # | 項 | 判定 | 原記載 | 🔴 乾淨值 | 污染值 | 實際量的節點 |
|---:|---|:--:|---|---|---|---|
| 1 | 3 卡片標題（h2）與標題列（§19.2 #3） | ✅ 一致 | h2 13px/600/lh20/#303030；host s-heading 的 fw「是 450 或 500」；Modal 級 s-internal-heading 14px/600/lh20 | **卡標題 h2 600 / 13px / lh 20px / rgb(48,48,48)；卡中卡 h3 600 / 13px / 20px；Modal h2.heading.size-large 600 / 14px / 20px** | h2／h3 皆 600（未變，shadow 內自宣告故免疫）。host 則分裂：s-heading（本身就在 shadow 內）450→450；s-internal-heading（在 light DOM）450→500 ⇒ 原文「host 上的 fw 是 450 或 500」這個雙值就是這個差異造成的，不是本尊有兩種值。 | 新層＝s-heading → shadow h2.heading（sh2，自宣告 600，免疫）；Price／Inventory／Shipping 三張卡改走 s-internal-heading → shadow h2.heading（sh1，同樣自宣告 600，免疫）；卡中卡為 h3.heading（sh2）。兩種 host 都是 display:contents（0×0），不產生繪製盒。 |
| 2 | 4 文字輸入框 Title（s-internal-text-field，§19.2 #4） | ✅ 一致 | label 13px/450/lh20；input 13px/450/lh20；placeholder 13px/450/rgb(97,97,97)；#describedby 12px/450/lh16 | **label／span.label-content 450 / 13px / 20px / rgb(48,48,48)；input 450 / 13px / 20px；::placeholder 450 / 13px / rgb(97,97,97)；div.field-details 450 / 12px / 16px / rgb(97,97,97)** | 四者全部與 clean 相同（免疫）。僅 host s-internal-text-field（light DOM，display:contents）450→500，但它不繪製文字。 | 全部在 shadow sh1：label.label.outside → span.label-content（葉，27×16，實際繪製）／input（葉，443×20）／input::placeholder／div.field-details（12px 容器，本例 display:none）。四者自身都不宣告 fw，但 shadow 根 div.internal-text-field 已宣告 450，阻斷了對被污染 host 的繼承 ⇒ 免疫。 |
| 3 | 5 帶前綴的金額輸入 Price／Compare-at（§19.2 #5） | 🔴 更正 | 前綴「HK$」13px/500/rgb(97,97,97)；input 13px/500/#303030 | **前綴 HK$ **450** / 13px / 20px / rgb(97,97,97)；price input **450** / 13px / 20px / rgb(48,48,48)；Compare-at input **450** / 13px / 20px；Compare-at 前綴 HK$ 450 / 13px / 20px；欄位 label 450 / 13px / 20px** | 以上五者一律 500 ⇒ 原記載的 500 全部是污染值 | 全部 light DOM（sh0）舊 Polaris 層，且**都不自宣告 font-weight**：div.Polaris-TextField__Prefix（葉，27×20）／input.Polaris-TextField__Input[name=price]（葉，100×32）／input[name=compareAtPrice]（葉，153×32，點 Compare-at pill 展開後取得，已還原）／label.Polaris-Label__Text「Price」（32×20） |
| 4 | 6 帶前綴的 URL handle 輸入（SEO 展開後，§19.2 #6） | 🔴 更正 | 前綴（網域段）13px/500/rgb(97,97,97)；input 13px/500/#303030 | **前綴 products/ **450** / 13px / 20px / rgb(97,97,97)；handle input **450** / 13px / 20px；seoTitle input **450** / 13px / 20px** | 三者一律 500 | light DOM（sh0），不自宣告 fw：div.Polaris-TextField__Prefix「products/」（60×20）／input.Polaris-TextField__Input[name=handle]（葉，395×32）。另同卡的 input[name=seoTitle]（葉，467×32）一併量。（SEO 卡以卡片右上 aria-label="Edit" 的鉛筆鈕展開，唯讀操作，收工重載已收合） |
| 5 | 7 數字輸入 Shipping → Product weight（§19.2 #7） | 🔴 更正 | input 13px/500/#303030 | ****450** / 13px / lh 20px / rgb(48,48,48)** | 500 | light DOM（sh0）input.Polaris-TextField__Input[name=weight]（葉，105×32），不自宣告 fw |
| 6 | 8 Textarea（SEO meta description，§19.2 #8） | 🔴 更正 | 13px/500/lh20/#303030 | ****450** / 13px / lh 20px / rgb(48,48,48)** | 500 | light DOM（sh0）textarea.Polaris-TextField__Input.Polaris-Scroll（葉，467×92），不自宣告 fw |
| 7 | 9 Select（s-internal-select，重量單位 lb/oz/kg/g，§19.2 #9） | ✅ 一致 | 值文字 13px/450；label 13px/450/lh20（此例視覺隱藏 w=1px） | **值文字 450 / 13px / 20px / rgb(48,48,48)；label 450 / 13px / 20px** | 兩者皆與 clean 相同（免疫） | shadow sh1：span.value（葉，8×20，實際繪製值文字）／span.visually-hidden（葉，1×1，label）。皆免疫（shadow 根已宣告 450） |
| 8 | 10 單選 Picker 欄位（Status／Type／Vendor／Category／Theme template，§19.2 #10） | ✅ 一致 | label 13px/450/lh20（值文字未記 fw） | **值文字（Active／Clinique／Default product）**450** / 13px / 20px / rgb(48,48,48)；label 450 / 13px / 20px** | 值文字 500；label 不變 | label＝shadow sh1 span.visually-hidden／div.label（免疫）；🔴 值文字的節點是 **s-internal-single-picker-field-value**，它在 **light DOM（sh0）且 display:contents（0×0）**——它被 slot 投射進 picker 的 shadow，但 CSS 選擇器是照 DOM 樹匹配的，所以擴充規則仍然打中它，其文字子節點再從它繼承 ⇒ 這一項不免疫。 |
| 9 | 11 多選 Picker 欄位（Collections／Tags，§19.2 #11） | ✅ 一致 | 原文此列未記任何 font-weight（只記高度／padding／radius／placeholder 文字） | **label 450 / 13px / lh 20px / rgb(48,48,48)；chip「Add collections」／「Add tags」 **550** / 12px / lh 16px / rgb(97,97,97)** | 兩者皆與 clean 相同（免疫） | label＝shadow sh1 span.small-text（葉，69×20 / 30×20，免疫）；placeholder chip＝s-clickable-chip → shadow sh2 span.content（89×16，免疫） |
| 10 | 12 Switch（Inventory tracked／Physical product，§19.2 #12） | ✅ 一致 | 輔助文字容器 12px/450/lh16/rgb(97,97,97) | **div.field-details 450 / 12px / 16px / rgb(97,97,97)（＝原記載，吻合）；可見標籤「Inventory tracked」／「Physical product」 **450 / 11px / lh 12px** / rgb(97,97,97)** | div.field-details 不變；可見標籤 450→500 | 原文所指的「輔助文字容器」＝s-internal-switch shadow sh1 的 div.field-details（本例 display:none）——免疫。🔴 另有一個原文未涵蓋的節點：畫面上真正看得到的開關標籤是 **light DOM** 的 span.Polaris-Text--bodyXs.Polaris-Text--subdued → div.Polaris-InlineStack（葉，92×12），它不免疫。 |
| 11 | 13 Pill（Compare-at／Unit price／Charge tax／Cost per item／SKU／Barcode／Sell when out of stock／Country of origin／HS Code，§19.2 #13） | 🔴 更正 | 13px/500/lh20；標籤文字實際在內層 <p>，色 rgb(97,97,97) | **pill 標籤 <p> **450** / 13px / lh 20px / rgb(97,97,97)（Compare-at／Charge tax／SKU／Barcode／Sell when out of stock／Country of origin／HS Code 逐個相同）；pill button 本體 400 / 13px / 20px** | 標籤 <p> 500；button 本體 400→500 | 標籤實際繪製盒＝light DOM p.Polaris-Text--root.Polaris-Text--block.Polaris-Text--start（葉），**自宣告 450**（其父 button 是 400）但被 !important 蓋掉；pill 本體 button._UnstyledButton_1ey1r_88._BasePillButton_1ey1r_43 自身 clean=400（原生 <button> 的 UA 預設，未被重設） |
| 12 | 14 Pill 內的值徽章（s-internal-badge，§19.2 #14） | ✅ 一致 | 文字 12px/550/lh16/rgb(97,97,97) | ****550** / 12px / lh 16px；pill 內徽章 rgb(97,97,97)、Status 卡 tone-success 徽章 rgb(1,75,64)** | pill 內徽章 550→**500**（🔴 這是「被壓低」方向的污染示範）；shadow 內的 div.badge／span.content 仍為 550（免疫） | 兩種投射形態都量了：①pill 內的徽章＝light DOM <span>（葉，如 16×15／83×15／18×15），**自宣告 550**；②Status 卡的「Active」徽章＝文字節點經 slot 投射，繪製盒是 shadow sh1 的 div.badge／span.content（53×20／37×16，550，免疫） |
| 13 | 15 富文本編輯器容器（Description，TinyMCE iframe，§19.2 #15） | ✅ 一致 | iframe 內 body 14px / 400 / line-height 19.6px(1.4) / rgb(48,48,48) | **400 / 14px / lh 19.6px / rgb(48,48,48)** | 400 / 14px（完全相同——因為 iframe 未被注入） | iframe#product-description-rie_ifr 的 contentDocument.body（同源可讀）。🔴 該 iframe 的 document 內**沒有** font-bolder-style，擴充只注入頂層文件 ⇒ 這一項本來就是乾淨值。本例 body 內無非空文字葉節點（描述為空），只量到 body 本身。 |
| 14 | 16 富文本工具列（§19.2 #16） | ✅ 一致 | 原文此列未記 font-weight（只記 fs 12px、24×24、色 rgb(74,74,74)） | ****550** / 12px / lh 12px / rgb(74,74,74)** | 550→500 | light DOM button._Button_ddsno_4（Paragraph 下拉，100×24）與 button._Button_ddsno_4._icon_ddsno_49（icon 鈕，24×24），**自宣告 550**（其父為 450）但被 !important 蓋掉 ⇒ 不免疫 |
| 15 | 18 Inventory per-location 表（§19.2 #18） | 🔴 更正 | 表頭 12px/500/lh16/rgb(97,97,97)；資料列 12px/500/lh16/rgb(48,48,48) | **表頭 **550 / 12px / lh 16px** / rgb(97,97,97)；資料列 **450 / 13px / lh 20px** / rgb(48,48,48)。🔴 附帶更正：資料列的 12px/16px 是 host（不繪製）的值，實際繪製的 span 是 13px/20px。** | 表頭 host 550→500、繪製盒 550（免疫）；資料列 host 450→500、繪製盒 450（免疫） | 🔴 兩者的繪製盒都在 s-internal-text 的 shadow 裡，原文量到的是 light DOM 的 host（display:contents，0×0）。表頭繪製盒＝shadow sh1 span.text.interest.interest-text-underline（class 含 weight-medium size-small，48×18，免疫）；資料列繪製盒＝shadow sh1 span.text.tone-auto.color-base（85×16 等，免疫）。 |
| 16 | 19 Metafield 列與卡片頁尾帶（§19.2 #19） | 🔴 更正 | metafield label 13px/500/lh20/#303030；頁尾「+ Disclosures」chip 13px/500/#303030 | **label **450** / 13px / 20px / rgb(48,48,48)；值 _ReadField **450** / 13px / 20px；頁尾 chip **450** / 13px / 20px / rgb(97,97,97)** | label 500；_ReadField 500；chip host 450→500 但繪製盒仍 450（免疫） | label＝light DOM p.Polaris-Text--root.Polaris-Text--bodyMd.Polaris-Text--breakAlways（葉，106×20），不自宣告；值＝light DOM div._ReadField_123bh_9（葉，317×24）；頁尾 chip 的繪製盒＝s-internal-text → shadow sh1 span.text.tone-auto.color-subdued（72×16，免疫） |
| 17 | 20 SEO SERP 預覽（Search engine listing，§19.2 #20） | 🔴 更正 | 站名 14px/450；URL 麵包屑 12px/450；**標題連結 18px/500/lh24/rgb(0,91,211)**；描述 13px/450；價格行 13px/450 | **站名 450 / 14px / 20px / rgb(48,48,48)；URL 450 / 12px / 16px / rgb(97,97,97)；**標題連結 450 / 18px / lh 24px / rgb(0,91,211)**；描述 450 / 13px / 20px / rgb(97,97,97)；價格行 450 / 13px / 20px / rgb(97,97,97)** | 站名／URL／描述／價格行皆不變（免疫）；標題連結 450→500 ⇒ 原記載的 500 是污染值（本列五個值裡只有這一個要改） | 站名／URL／描述／價格行的繪製盒都在 s-internal-paragraph 的 shadow sh1（p.paragraph.color-base／color-subdued，免疫）；🔴 標題連結不同——它是 light DOM 的 span._LinkPreview_1azdy_17（葉，390×22），父為 p.Polaris-Text--headingLg.Polaris-Text--regular，兩者都不自宣告 fw |
| 18 | 21 字元計數器（SEO Page title／Description，§19.2 #21） | 🔴 更正 | 12px/500/lh16/rgb(97,97,97)；超限仍不轉紅 | ****450** / 12px / lh 16px / rgb(97,97,97)（本例實測文字為「44 of 70 characters used」與「113 of 160 characters used」，均未超限，故本輪未複驗超限不變色那一句）** | 500 | light DOM p.Polaris-Text--root.Polaris-Text--bodySm.Polaris-Text--breakAlways（葉，467×16），不自宣告 fw |
| 19 | 22 SaveBar（未儲存變更列，§19.2 #22） | ⚠ 未取得 | 「Unsaved changes」13px/500/rgb(238,238,238)；Discard 13px/500；Save 13px/500 | **未取得（見 not_obtained 第 1 條，含已嘗試的方法與失敗證據；試改欄位已全部還原並複驗）** | 未取得 | 未取得。SaveBar 在表單乾淨時**整段不存在於 DOM**（本輪搜到的 5 個「Unsaved changes」葉節點經祖先鏈確認全部屬於 s-internal-modal 的 div.unsaved-changes 頁尾，不是頁面 SaveBar，且 dialog.modal 為 display:none） |
| 20 | 23 表單底部 Save 按鈕列（supplementalEnd，§19.2 #23） | ✅ 一致 | 原文此列未記 font-weight（只記 h28／w52.1／bg rgb(48,48,48)／radius 8／三層 inset 陰影） | **button 450 / 13px / 20px；實際繪製的標籤 span **600 / 12px / lh 16px** / rgb(255,255,255)** | button 450→500；標籤 span 600→**500**（又一個被壓低的例子） | button.Polaris-Button--variantPrimary（light DOM，52×28，不自宣告 fw）＋其內文葉 span.Polaris-Text--root.Polaris-Text--bodySm.Polaris-Text--semibold（葉，28×16，**自宣告 600**）。註：表單乾淨時此鈕為 disabled，原文記的 bg rgb(48,48,48) 是啟用態。 |
| 21 | 24 卡片右上 icon 動作鈕（SEO 鉛筆／Publishing 設定／Product organization 資訊，§19.2 #24） | ✅ 一致 | 28×28、fs 12px / fw 550、圖示色 rgb(138,138,138) | ****550** / 12px / lh 16px（SEO 鉛筆鈕圖示色 rgb(138,138,138)、其他同族鈕 rgb(48,48,48)／rgb(255,255,255) 依 variant）** | 550（未變，免疫） | s-internal-button → shadow button.button.size-base.tone-auto（28×28），**自宣告 550**，免疫 |
| 22 | 25 發布通路列（Publishing 卡：Online Store／All catalogs，§19.2 #25） | ✅ 一致 | 原文未記 fw；記「該 <button> 未重設字體，其子孫 computed font-size 13.3333px、color rgb(0,0,0)」並判為本尊樣式瑕疵、我方不應照抄 | **button 本體 **400** / 13.3333px / lh normal / rgb(0,0,0)（＝UA 預設外洩，複驗吻合）；「Online Store」 **550** / 13px / 20px / rgb(48,48,48)；「All catalogs」 **550** / 12px / 16px / rgb(48,48,48)。🔴 補充更正：13.3333px／rgb(0,0,0) 只停在 button 與 display:contents 的 s-internal-text host 上，**兩個真正繪製文字的節點都自己覆蓋掉了字級與顏色**，所以外洩值不會被使用者看見。** | button 400→500；「Online Store」550→500；「All catalogs」<strong> 仍 550（免疫） | button._Button_ax5zp_1（light DOM，475×28）；「Online Store」實際繪製盒＝light DOM span.Polaris-Text--bodyMd.Polaris-Text--medium（葉，76×16，自宣告 550）；「All catalogs」實際繪製盒＝s-internal-text → shadow sh1 **<strong>**.text（class 含 weight-medium size-small，67×15，自宣告 550，免疫） |
| 23 | 26 Disabled 按鈕（primary，深色底，§19.2 #26） | ✅ 一致 | h28／w77／bg rgba(0,0,0,0.17)／文字 #fff／fs 12px / fw 550／opacity 1／cursor auto | ****550** / 12px / lh 16px / rgb(255,255,255)；同時複驗 bg rgba(0,0,0,0.17)、opacity 1、cursor auto、77×28 全部吻合** | 550（未變，免疫） | s-internal-button → shadow button.button.size-base.tone-auto（77×28，disabled=true），**自宣告 550**，免疫。本輪找到的實例是 Sidekick「Generate」鈕（與原文那顆離屏 modal 鈕同型同尺寸）。 |
| 24 | 27 區塊說明段落（Sales 卡「No recent sales of this product」等，§19.2 #27） | ✅ 一致 | 13px/450/lh20/rgb(97,97,97)；「View adjustment history」同型；Media 文字為 paragraph 13px/450/#303030 | **450 / 13px / lh 20px / rgb(97,97,97)（Sales 空態、View adjustment history）；「Media」 450 / 13px / 20px / rgb(48,48,48)** | 繪製盒全部不變（免疫）；host 450→500 但不繪製 | s-internal-paragraph → shadow sh1 p.paragraph.color-subdued.tone-auto／p.paragraph.color-base.tone-auto（免疫）；host 在 light DOM、display:contents（0×0） |

> 🔴 **2026-08-28 G13 定案補記（#15 per-location 表頭詞）**：本項結論 **12px / 550 / lh 16px 正確**，
> `docs/research/77` §7.6.1 的「13px / 650」已撤回（它量到的是 tooltip 內文的粗體字）。
> 補上完整節點身分以免下次對不上：四個詞的 rect 依序為
> **Unavailable 67×18／Committed 63×18／Available 52×18／On hand 48×18**
> ——原記的「48×18」精確對應 **On hand** 那一格，**不要拿它當唯一指紋**。
> 🔴 **同一列有一個例外格**：`Locations` 欄表頭**沒有** `s-internal-text`，
> 文字節點直接掛在 light DOM 的 cell 上 ⇒ **不免疫**（clean 550／dirty 500）。
> 未停用污染源的量測會得到「Locations 500、其餘 550」的**假性不一致**。
> ⚠️ per-location 表頭在 DOM 中有**兩份副本**（sticky 可見副本 ＋
> `Polaris-Table-TableHeadingCell__Hidden` 版面量測副本）⇒ **節點計數要先除以 2**。

### 19.6.a 本次重量帶出的規律

1. 🔴 **§19.3 第 3 條與 §19.4 第 1／3／5 條的撤回全部成立，而且比撤回註寫得更強。** 撤回註說那些 500 是污染；本輪進一步證明**本尊這頁根本沒有任何一個文字元素是 500**：1334 個葉節點的乾淨直方圖 450×975／550×187／600×9／400×13，500＝**0**；擴大到全部 7744 個元素也只有 1 個 500（見下條，非文字元素且是快取殘留）。所謂「舊 React 表單層硬編碼 500 vs 新 web-component 層 450／600」的兩層並存假說**不存在**——兩層用的是同一組階梯 450／550／600／650，差別只在**免疫與否**，不在值。
2. 🔴 **CSSOM 直接取證（回答『誰宣告的』）**：掃過 98 張全部可讀的樣式表、遞迴展開共 14042 個宣告區塊。設定 `font-weight: 500` 的宣告只有 8 條——1 條是擴充功能自己的 `!important` 規則，其餘 7 條全部落在 `pvi-*` 命名空間（分析圖表的 tooltip／legend／gauge／funnel／grid tooltip），**沒有任何一條能匹配商品詳情頁的元素，且該頁不含 pvi-* 元件**。本尊 admin 的字重宣告一律走 `var(--p-font-weight-regular|medium|semibold|bold)`（450／550／600／650，共 241 條）或字面 450／550／600／650／400／700／750。
3. 🔴 **唯一的乾淨 500 已排除，不構成反例。** `div._BottomBarBackground_ejstq_30`（light DOM、787×0、**textContent 為空、不繪製任何文字**、position:fixed）在停用擴充後仍讀到 500。逐項排查：①以 el.matches() 掃全部 14042 條規則，唯一命中它的 font-weight 規則就是擴充自己那條；②其父元素乾淨值 450；③強制 reflow、加減 class、切換 documentElement class 都不回退。④**決定性測試：把同一個節點 cloneNode 後插回同一個父層，在乾淨環境下解析得到 450。** ⇒ 這是原節點的樣式快取殘留（本輪未能取得 Chrome 端的機制證據，故只登記現象與反證，不推測原因）；它不是本尊宣告的 500，也與排版無關。
4. 🔴 **免疫的判準是「該元素或其 shadow 祖先有沒有自宣告」，不是「在不在 shadow 裡」——本輪逐項驗證了指派給的這條規則，並找到了機制。** 每個 `s-internal-*` 元件的 shadow 根元素（例：s-internal-text-field 的 div.internal-text-field）自己宣告了 font-weight（值＝token），於是整個 shadow 子樹與被污染的 host 斷開繼承 ⇒ 免疫。反之，**host 本身幾乎都在 light DOM 且是 `display:contents`（0×0）**，它們一律被污染成 500——`s-internal-heading`／`s-internal-paragraph`／`s-internal-text`／`s-internal-badge`／`s-internal-text-field` 的 host 全都如此。§19 的多數錯誤 500 就是量到了這些不繪製的 host（表格資料列連 font-size 都跟著錯，見 row 18）。
5. 🔴 **例外一：被 slot 投射的 light DOM 元素不免疫。** `s-internal-single-picker-field-value`（picker 值文字，row 10）雖然最終畫在 picker 的 shadow 裡，但它自己是 light DOM 元素，選擇器照 DOM 樹匹配得到它，`!important` 直接改寫，再由它（display:contents）傳給文字節點 ⇒ 乾淨 450／污染 500。**例外二：純文字節點的投射反而免疫**——Status 卡「Active」徽章的文字是 host 的文字節點，flat tree 的父是 slot，繼承自 shadow 內的 span.content（550），故不受 host 被污染影響。兩種投射方向相反，量測時必須逐個確認繪製盒。
6. 🔴 **雙向污染在本頁四種方向都實測到了**：450→500（Polaris 輸入框／前綴／pill 標籤／字元計數器／metafield label／SERP 標題連結／switch 可見標籤）、550→500（pill 值徽章、表格表頭、RTE 工具列鈕、Online Store 通路名）、600→500（底部 Save 的 semibold 標籤）、400→500（原生 <button> 的 UA 預設：pill 本體、發布通路列 button）。⇒ 「看到 500 無法回推真值」在這一節得到四種形態的佐證。
7. 🔴 **順帶抓到兩個 font-size／line-height 錯記（不是污染造成，是量錯節點）**：①§19.2 #18 資料列記 12px/lh16，實際繪製的 shadow span 是 **13px/lh20**（12px/16px 是 display:contents host 的值）；②§19.2 #12 的「輔助文字容器 12px/lh16」指的是 shadow 內的 div.field-details（本例 display:none），畫面上真正看得到的開關標籤是 light DOM 的 Polaris bodyXs＝**11px/lh12**。其餘所有列的 font-size／line-height 逐項複驗與原記載一致（13px/20px、12px/16px、14px/20px、18px/24px、13.3333px/normal 等），符合指派所述「只污染 font-weight」。
8. 🔴 **RTE iframe 完全在污染射程之外**：`product-description-rie_ifr` 的 document 內沒有 font-bolder-style（實測 extInside=false），其 body 400/14px/19.6px/rgb(48,48,48) 在兩種環境下逐位元組相同 ⇒ §19.2 #15 的 400 從一開始就是乾淨值，不需重量也不需修正。
9. §19.2 的第 1（兩欄容器）、2（卡片 Section 容器）、17（媒體格線與 tile）三列**原文不含任何 font-weight，也沒有文字繪製盒**，故不在本輪重量射程內；它們記的幾何／顏色／陰影值不受本次污染影響（指派已聲明），本輪未動。
10. 本輪量測寬度是 787px（§19.0 是 1024px）。字級階梯經逐項比對未隨寬度改變（h2 13/600、input 13/450、badge 12/550 等全部與 §19 一致），故 font-weight 結論不受寬度差異影響；但**幾何值（欄寬、grid-template-columns、卡片 padding）本輪一律未複驗、也不得拿本輪數字覆蓋 §19 的幾何記載**——例如 Inventory 表在 787px 下是 role=table 的 Polaris-Table sticky/scrollable 形態、grid-template-columns 為 none，與 §19 在 1024px 記的「ARIA grid＋155/149/127/134/137」不可直接比較。

### 19.6.b 仍未取得

- **§19.2 #22 SaveBar 的乾淨值（Unsaved changes 文字／Discard／Save）**。原因：表單乾淨時 SaveBar 整段不在 DOM（本輪搜到的 5 個「Unsaved changes」節點經祖先鏈確認全屬 s-internal-modal 的 footer，dialog 為 display:none，值 12px/rgb(2,38,34) 與原記載的 13px/rgb(238,238,238) 不同族，不得拿來充數）。已嘗試且失敗的兩條路：①**真實鍵盤輸入到不了這個離屏視窗**——JS 先 focus 到 input[name=seoTitle]，再用 computer 的 type 送出「 」與「Z」，兩次事後讀值都完全沒變（與指派已記的 screenshot 逾時、resize 無效同一組工具限制）；②改用 React 原生 setter＋_valueTracker 重置＋input/change 事件：欄位狀態確實更新了（字元計數器 44→45 可證），但頁面級 SaveBar 始終沒出現，推測 dirty 旗標不由該事件路徑驅動（未取得證據，不下定論）。兩次試改都已還原並複驗（值、計數器、Unsaved 數皆回原狀），全程未按儲存鍵。取得方式＝在鍵盤／滑鼠事件能真正送達頁面的瀏覽器工作階段做一次「改一欄 → 量 → Discard」。
- **1280／768／390 三裝置寬度下的重量**。本輪視窗鎖在 787×372，指派已明示 resize_window 無效故未重試。不影響本輪 font-weight 結論（字級階梯不隨寬度變），但幾何值仍缺 §19.5 原本就登記的 1280 量測。
- **變體表格（多變體商品的變體列表）的字重**。本輪商品 9907123716331 為單變體；店內唯一的多變體測試品 9907126370539 在禁止觸碰清單內，全程未導航。取得方式＝另找一個非保護的多變體商品，或沿用 docs/research/93 §1–2。
- **§19.2 #21 超限態字元計數器的乾淨值**。本輪兩個計數器都在限額內（44/70、113/160），原文記的「296 of 160（已超限）仍為 rgb(97,97,97) 不轉紅」這一句本輪無法複驗；只取到未超限態的 450 / 12px / 16px / rgb(97,97,97)。
- **表單欄位 disabled／error 態、Picker popover 面板、媒體 tile 與 pill 的 hover／active 態的字重**。本輪唯讀且未展開任何 popover，§19.5 原有的這幾條缺口照舊未補（其中 disabled primary button 一項已在 row 26 取得）。
- **`div._BottomBarBackground_ejstq_30` 為何在停用擴充後仍解析成 500 的瀏覽器端機制**。已用 clone 反證它不是本尊宣告（clone 乾淨解析為 450），但造成原節點值不回退的確切機制未取得證據，僅登記現象與反證，不作推測。

> 量測環境：量測日期 2026-08-28（本地時間），Claude in Chrome，測試店 chill-love-u5q5mnzq，自開分頁（收工時分頁群組已消失＝分頁已關閉）。window.innerWidth=787／innerHeight=372（🔴 與 §19.0 的 1024 不同，本輪視窗無法調整；resize_window 依指派說明不重試），devicePixelRatio=1.25，getComputedStyle(documentElement).fontSize=16px（無根字級污染）。  【污染源與停用聲明】頁面確認存在 <style id="font-bolder-style">，parentNode=HTML，位於 document.styleSheets[0]，唯一規則＝`body, body :not(svg):not(svg *):not(img):not(video):not(canvas)` 設 font-weight 500 並帶 !important。全部數值以 `ext.sheet.disabled = true`（clean）→ 讀值 →`= false`（dirty）→ 讀值的同步配對取得；只切 CSSOM 旗標，未動使用者的擴充功能設定。 【對照組驗證】html 根元素 clean=450／dirty=450（不在選擇器射程）；body clean=450／dirty=500。 【直方圖複驗】1334 個葉節點（childElementCount===0 且有非空文字）：clean 450×975／550×187／600×9／400×13／空字串×150，**500 為 0 個**；同一組 dirty 為 450×535／500×638／600×7／400×4。與指派提供的乾淨直方圖同型。 【全元素複驗】7744 個元素：clean 450×6471／550×485／600×87／650×12／400×212／500×1（該 1 個見 patterns 第 3 條，非文字元素且已證實為樣式快取殘

---

## 15.1 🔴 G12b 乾淨環境重量（2026-08-28）

> 依**鐵律 19.5**追加，**上方原記載保留原文**。
> 觸發＝`docs/design/110` 的 **G12b**：G12 的射程只點名`91` **第 19 節**，漏掉了本節。
> 污染源與機制＝`docs/design/111` §20。
>
> 全部數值以「停用污染源 → 讀 clean → 還原 → 讀 dirty」的**同步配對**取得，收工已還原並複驗。
> 有疑義處另以 **`Range` 實際繪製寬度 vs `canvas measureText`** 做獨立佐證（Δ ≤ 0.009px）。

**本節結果：4 列（更正 4／一致 0／未取得 0）**

| # | 項 | 判定 | 原記載 | 🔴 乾淨值 | 污染值 | 實際量的節點 |
|---:|---|:--:|---|---|---|---|
| 1 | pill（帶值按鈕）——§15 表格第 154 行 | 🔴 更正 | h 28px、radius 8px、padding 4px 8px、透明底、13px/500 | **🔴 一個「500」對應兩個不同真值，必須分開記：①pill **button 本體** = 400 / 13px / lh 20px / rgb(48,48,48)（＝原生 <button> 的 UA 預設，從未被重設）；②畫面上看得到的 **pill 標籤文字** = 450 / 13px / lh 20px / rgb(97,97,97)。附帶：pill 內的值徽章 <span> = 550 / 12px / lh 16px / rgb(97,97,97)。原記載的幾何（h 28px／radius 8px／padding 4px 8px／背景 rgba(0,0,0,0) 透明）逐格複驗吻合，未變。** | button 400→500；標籤 <p> 450→500；值徽章 550→500（壓低方向）。三者在污染下全部塌成同一個 500 | ①button._UnstyledButton_1ey1r_88._BasePillButton_1ey1r_43（**light DOM，sh=0**，rect 176.79×28）——自宣告解析為 `unset`，等於不宣告，**不免疫**。②標籤實際繪製盒＝p.Polaris-Text--root.Polaris-Text--block.Polaris-Text--start（**light DOM，sh=0**，葉，rect 74.29×20）——它**有**自宣告（解析為 450），但擴充規則帶 !important，light DOM 的自宣告擋不住，**不免疫**。③值徽章＝light DOM 的裸 <span>（sh=0，rect 66.5×15.2），經 s-internal-badge 的 slot 投射，同樣**不免疫**。三者皆無 shadow 祖先。【獨立佐證】對標籤文字節點建 Range：clean 實測 74.288px、dirty 74.712px；同字體同 13px 的 canvas measureText＝450→74.276／500→74.709／400→73.855 ⇒ clean 命中 450（Δ0.012px）、dirty 命中 500（Δ0.003px），可排除 400。 |
| 2 | text input——§15 表格第 155 行 | 🔴 更正 | h 32px、13px/500、ink `#303030` | ****450** / 13px / lh 20px / rgb(48,48,48)（＝#303030，ink 部分原記載正確、未變；h 32px 亦複驗吻合）** | 500 | input.Polaris-TextField__Input[name="price"]（**light DOM，sh=0**，葉，rect 100.31×32 clean／100.16×32 dirty）。以 input[name="weight"]（100.68×32）複驗同結果（clean 450／dirty 500）。該 input **有**自宣告（解析為 450），但被擴充的 !important 蓋掉 ⇒ **不免疫**；無 shadow 祖先。🔴 **節點身分的排除法**：本頁另一個輸入框家族是 s-internal-text-field 的 shadow 內 input（sh=1，rect 443.2×20），實測 clean 450／**dirty 也是 450**（免疫）——既然 §15 記到 500，它**不可能**量的是那一個；且 §15 明記「h 32px」，只有 Polaris 這一族的控件盒是 32px（s-internal 那族 32px 的是 div.input-wrapper，不是繪製文字的 input）。兩族的乾淨值**同為 450**，故本項結論不受節點歧義影響。【獨立佐證】clean→dirty 寬度由 100.31→100.16 位移，證明 CSSOM 旗標確實觸發重繪，非讀到快取。 |
| 3 | label（🔴 原記載附帶結論「⚠ 字重差 50，我方 64 §3 定 450 …不改 token，登記觀察」）——§15 表格第 156 行 | 🔴 更正 | 13px / **500** / lh 20px | ****450** / 13px / lh 20px / rgb(48,48,48)。🔴 **與我方 token `--fw-body 450` 完全一致，根本不存在「字重差 50」** ⇒ 該列的「登記觀察／不改 token」結論**作廢**，不得再依它維持或登記任何差異。** | 450（**不變**——本項免疫，dirty 環境下讀到的也是 450） | span.label-content（**shadow 內，sh=1**，host＝s-internal-text-field[name="title"]，葉，rect 26.81×16，實際繪製「Title」）；其父 label.label.outside（sh=1，rect 467.2×20）亦為 450。🔴 **免疫，且是雙重免疫**：①label.label.outside **自宣告** font-weight（token 解析 450）；②shadow 根元素 div.internal-text-field **自宣告**（token 解析 450），阻斷來自被污染 host 的繼承。span.label-content 自身宣告 `unset`（回落繼承）。對照：host s-internal-text-field 本身＝light DOM、display:contents、rect 0×0、dirty 500、fs 13px，**不繪製任何文字**。🔴 **關鍵推論**：本節點 clean 與 dirty 皆為 450，因此 §15 記到的 500 **不可能出自這個繪製節點**——只可能來自量到了那個 0×0 的 host。【獨立佐證】Range 實測「Title」寬度 clean 26.813／dirty 26.813（逐位元組相同）；canvas measureText 13px＝450→26.812（Δ0.001px）／500→27.110／550→27.401 ⇒ 排他性命中 450。【與 §19.6 row 2 的關係】本輪在**不同商品**（9907158778091 vs 9907123716331）上獨立取得同一結論、同一節點身分與同一免疫機制（24.81×16 對其記的 27×16，同一個 26.81 四捨五入），構成獨立複驗而非照抄。 |
| 4 | 狀態 badge——§15 表格第 157 行（並見同檔第 28 行「『啟用中』綠底 pill，緊貼標題右側」） | 🔴 更正 | 13px/500、綠底 pill（收合於標題旁） | **🔴 **550 / 12px / lh 16px** / rgb(1,75,64)。**本列有兩個錯，不只字重**：字重 500→**550**，字級 13px→**12px**（原記載量到的是不繪製的 host，屬「量錯層」，與 §19.6 row 15／18 同型）。綠底 pill 形態複驗吻合：background rgb(175,254,191)、border-radius 8px、padding 2px 8px、div.badge rect 52.51×20。位置亦複驗吻合「收合於標題旁／緊貼標題右側」：badge 在 x=368.2, y=76，與頁面標題 h1.heading.has-breadcrumbs（x=294, y=74，18px/600，sh=1）同一列；本頁無另外的 Status select。** | 550（繪製盒**不變**，免疫）；被污染成 500 的是 host s-internal-badge（其 fs 恰為 13px）——原記載的「13px/500」正好就是這個 host 的那一組值 | 實際繪製盒在 **shadow 內（sh=1）**：div.badge（rect 52.51×20，12px/550/lh16，**自宣告** font-weight，token 解析 550）與其內 span.content（rect 36.51×16，12px/550，自身宣告 `unset` 回落繼承）。🔴 原記載量到的是 **host s-internal-badge[tone="success"]**：**light DOM（sh=0）**、display:contents、**rect 0×0、不繪製任何文字**、font-size 13px（頁面繼承值）、本身無自宣告、dirty fw 500。🔴 **投射方向的分辨**：「Active」是 host 的**純文字節點**，經 <slot> 投射進 shadow，其 flat-tree 父是 slot（sh=1、display:contents、computed 12px/550）⇒ 文字從 shadow 內的 span.content 繼承，**免疫**；這與同頁 pill 內值徽章那種「light DOM **元素**被投射 ⇒ 不免疫」方向相反，兩者在本輪同一頁都實測到了。【獨立佐證】對該文字節點建 Range：clean 36.513px／dirty 36.513px（相同）；canvas measureText 12px＝550→36.505（Δ0.008px）／500→36.167／600→36.831／450→35.811 ⇒ 排他性命中 550，明確排除 500。 |

### 15.1.a 本次重量帶出的規律

1. 🔴 **四項全部是污染值；§15 沒有任何一個 500 在乾淨環境下存活** ⇒ 本輪無「重大發現」型的殘留 500，不需追查宣告者。四項的乾淨真值分別是 **400／450／450／550**——同一個記下來的「500」在同一張四列的表裡就對應到三個不同真值，是「看到 500 無法回推真值」最緊湊的一組實證。
2. 🔴 **獨立複驗了「本尊沒有 500 這一階」**：在**與 §19.6 不同的商品**上重跑直方圖，1334 個葉節點的乾淨分布＝450×974／550×188／600×9／400×13／空字串×150，**500 為 0 個**；同一集合 dirty 為 450×5115→500×1850（全元素口徑）。§19.6 在另一商品得到 450×975／550×187／600×9／400×13，兩組幾乎逐格相同 ⇒ 該結論不是單一商品的巧合。全部 7798 個元素中乾淨 500 只有 **1** 個，且正是 §19.6.a 第 3 條已登記的 `div._BottomBarBackground_ejstq_30`（787.2×0、textContent 空、不繪製文字）——在不同商品上復現，證明它不是該頁面實例的偶發，與該條「樣式快取殘留」的登記一致。
3. 🔴 **免疫判準必須加一句限定：light DOM 的「自己宣告」根本不是防線。** 本輪兩個反例：price input **有**自宣告（解析 450）、pill 標籤 <p> **也有**自宣告（解析 450），兩者照樣被污染成 500——因為擴充規則帶 `!important`，會蓋過 light DOM 的一般作者宣告。真正的免疫只來自**樹範圍**：document 樣式表不匹配 shadow tree 內的任何元素，所以只有 shadow 內的自宣告（badge 的 div.badge 550、text-field 的 div.internal-text-field 450）才擋得住。指派免疫表「該元素自己宣告 ✅」這一格，只在 shadow tree 內成立；寫回規範時建議補上這個限定詞。
4. 🔴 **兩個 slot 投射方向在同一頁同時出現、結果相反，必須逐個確認繪製盒**：①pill 內的值徽章是 light DOM 的 <span> **元素**被投射進 s-internal-badge 的 shadow ⇒ 選擇器照 DOM 樹打中它，**不免疫**（550→500）；②狀態 badge 的「Active」是 host 的**純文字節點**被投射 ⇒ flat-tree 父是 slot、繼承自 shadow 內的 span.content，**免疫**（550 不變）。同一個 s-internal-badge 元件，兩種投射載體命運相反。
5. 🔴 **四項裡至少一項（badge，確定）、可能兩項（pill，視原節點而定）量到的是不繪製的 `display:contents` host；而量錯層會連 font-size 一起錯。** badge 的 host 是 13px、繪製盒是 12px，所以 §15 該列的「13px」也要改。這讓「只有 font-weight 受污染，其餘可照引」這條前提必須加條件：**它只在量對節點的前提下成立**——量錯層的列，非字重值同樣不可信。
6. 🔴 **canvas measureText 對比達到了指派預期的分辨力，且是本輪唯一能排除相鄰階的手段**：badge「Active」實測 36.513 vs 550→36.505（Δ0.008px）而 500→36.167；pill「Compare-at」clean 74.288 vs 450→74.276（Δ0.012px）、dirty 74.712 vs 500→74.709（Δ0.003px）；label「Title」26.813 vs 450→26.812（Δ0.001px）。相鄰字重階之間的寬度差僅約 0.3–0.4px，靠 getComputedStyle 單讀無法交叉驗證，Range 寬度是必要的第二來源。
7. 🔴 **clean/dirty 切換使不免疫節點的繪製寬度位移（price input 100.31→100.16、pill 標籤 74.288→74.712），這本身就是「旗標確實生效、不是讀到快取」的內建證據。** 反過來，label 與 badge 的 Range 寬度在 clean/dirty 下逐位元組相同，正是免疫的獨立佐證，不必只依賴 computed 值相等這一個讀數。
8. 🔴 **§15 的四列判定欄也跟著錯了**：pill／text input／badge 三列原寫「✅ 逐格吻合」，但它們是拿污染值去對我方 token（--fw-control／--t-sm／badge tokens）得出的吻合；label 一列則反過來拿污染值判出一個**不存在的差異**。⇒ 污染不只會製造假陰性（假差異），也會製造假陽性（假吻合）；回寫時四列的**判定欄都需重新導出**，不能只換數字。

### 15.1.b 仍未取得

- §15 pill 那一列（L154）**原記載究竟量的是哪一個節點，無法從記錄判定** ⇒ 未取得單一判定，本項以雙值並列交付。理由：該列同時寫了幾何（h 28px／radius 8px／padding 4px 8px／透明底——逐格只吻合 button 本體）與「13px/500」（button 與標籤 <p> 的 font-size 都是 13px，dirty 下也都讀到 500）。兩個候選的乾淨值**不同**（button 400／標籤 450），不能合併成一個數字。回寫 §15 時必須把節點身分一併寫進去，否則同一個歧義會再發生一次。
- 1280／768／390 三裝置寬度下的複驗——未取得。本輪視窗鎖在 787×372；依指派說明 resize_window 為假成功（視窗離屏、渲染面凍結）、screenshot 會逾時，故未重試。字重階梯不隨寬度改變（本輪 13px/450、12px/550、18px/600、13px/400 與 §19／§19.6 逐項一致），故四項 font-weight 結論不受影響；但**幾何值不得以本輪 787px 數字覆蓋 §15／§19 在其他寬度的記載**。
- pill 的 hover／active 態、text input 的 disabled／error 態、badge 其他 tone 的字重——未取得。全程唯讀、未觸發任何互動態（未 hover、未聚焦、未展開 popover、未開 modal），依硬約束不試。
- `div._BottomBarBackground_ejstq_30` 在停用擴充後仍解析為 500 的瀏覽器端機制——未取得（沿襲 §19.6.b 同一條缺口）。本輪只**復現了現象本身**（見 patterns 第 2 條），未做機制取證，不推測原因。它不屬於本次指派的四項，也不繪製任何文字。

> 量測環境：量測日期 2026-08-28（本地時間），Claude in Chrome，自開分頁（收工已 tabs_close，未動使用者原有分頁）。測試店 chill-love-u5q5mnzq，商品 **9907158778091**（CHOICE Urate 120 capsules，Active、單變體）——🔴 **刻意選用與 §19.6 不同的商品**（§19.6 用 9907123716331），使 label 那一項成為真正的獨立複驗而非同頁重讀；導航全程從真實 href 取得（先於 admin 首頁取 Products 的 href `/store/chill-love-u5q5mnzq/products`，再從商品列表取該商品 href），未猜任何 URL。逐一比對五個禁止 id（9907126370539／9911273160939／9913006162155／9913007767787／9913009438955），本商品不在其中，且全程未導航至任何禁止 id。window.innerWidth=787／innerHeight=372，devicePixelRatio=1.25，getComputedStyle(documentElement).fontSize=16px（無根字級污染）。  【污染源確認】頁面存在 <style id="font-bolder-style">，parentNode=HTML，位於 document.styleSheets[0]，唯一規則對 `body, body :not(svg):not(svg *):not(img):not(video):not(canvas)` 設 font-weight:500 !important（同一條並帶 text-shadow 與 -webkit-font-smoothing，兩者不影響 advance width）。  【已停用污染源後量測】全部數值以 `ext.sheet.disabled=true`（clean）→ 讀值 → `=false`（dirty）→ 讀值的同步配對取得；只切 CSSOM 旗標，未動使用者的擴充功能設定。對照組每輪複驗：html clean=450／dirty=450（不在選擇器射程）、body clean=450／dirty=500。CSSOM 索引涵蓋全部樣式表＋shadow adopted/inline sheets，共 2664 條含 font-weight 的規則，**unreadableSheets=0**（無不可讀表
