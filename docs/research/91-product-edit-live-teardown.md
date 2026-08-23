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
V-91.4 媒體 tile 深測｜V-91.5 檢視調整記錄頁｜V-91.6 包材選單值域｜V-91.7 原產地/HS 展開｜
V-91.8 類別樹 autocomplete｜V-91.9 handle 修改→301 redirect 對話框｜V-91.10 系列/標籤編輯對話框｜
V-91.11 佈景範本值域｜~~V-91.12 管理發布~~ **已測**（§13：channel 多對多 modal）｜V-91.13 多變體商品的變體表（本商品單變體測不到）｜
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
