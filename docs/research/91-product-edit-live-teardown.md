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
3. 🔴 **字重 500 不在 token 階梯裡**（階梯是 450／550／600／650）。凡量到 fw 500 的元素（金額輸入、pill、metafield label、SERP 標題、SaveBar 文字、表格 cell）都是**舊 React 表單層的硬編碼**；新 web-component 層一律 450／600。這正好解釋 91 §15 的字重矛盾。
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

5. ⚠️ **未與 `docs/design/47`／`docs/design/64` 逐項比對**（本輪未讀該兩檔，指派只要求讀 91）。本輪測到的全域階梯（間距 4 倍數、圓角 12/8/4、控件高 32/36/28、根字級 16px）與 --p-* token 原值已完整列在 §1，請主控代理拿去與 47 §F／64 §3 對表；若 47／64 記的字重階含 500，同樣適用上面的「兩層並存」翻案。

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
