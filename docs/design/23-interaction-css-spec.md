# 23 — UI Tokens 與交互邏輯完整規格（CSS 單一真相）

> 給接手工程的精確規格：**所有 CSS 值以本文件為準**（來源：我們自訂的 CHILL LOVE 設計系統，參數化自 02 號研究與 21 號實測的結構觀察；全部為自有原創值，不含任何第三方樣式代碼）。原型 `chilllove-admin-v2.html` 的 `<style>` 區塊是本規格的參考實作，兩者同步維護。

## 1. Admin Design Tokens（複製即用）

```css
:root{
  /* 表面與文字 */
  --bg:#f4f4f5;            /* 頁面底 */
  --surface:#fff;          /* 卡片 */
  --surface-2:#f7f7f8;     /* 次層（側欄、輸入底、hover）*/
  --surface-3:#fafafb;     /* 表頭 */
  --text:#1a1c1e;          /* 主文字（白底 16.1:1）*/
  --text-2:#6b6d71;        /* 次要（5.2:1）*/
  --text-3:#67696e;        /* 弱化（5.5:1；≥4.5 AA 為底線）*/
  --border:#e3e3e6; --border-2:#ececef;   /* 卡框 / 分隔線 */
  /* 品牌與互動 */
  --brand:#2b2c2e; --brand-hover:#1f2022; /* 主按鈕近黑 */
  --link:#2a5bd7; --focus:#2a78d6;
  /* 語意色（bg 配 text 成對使用）*/
  --success:#0a7a5c; --success-bg:#e2f1ea;
  --warning:#8a6116; --warning-bg:#fdf3dc;
  --critical:#b3172c; --critical-bg:#fdecee;
  --attention:#6d5f00; --attention-bg:#f9f1bc;
  --info:#155e8f; --info-bg:#e8f2fa;
  --ai:#6d28d9; --ai-bg:#f3efff;          /* AI 專用紫 */
  /* 圖表（已過對比/CVD 驗證）*/
  --chart:#2a78d6; --grid:#ececef;
  /* 形狀與陰影 */
  --r-card:12px; --r-btn:8px; --r-pill:999px;
  --sh:0 1px 2px rgba(26,28,30,.05),0 1px 6px rgba(26,28,30,.04);
  --sh-pop:0 12px 32px rgba(26,28,30,.16);
  --sh-modal:0 24px 64px rgba(26,28,30,.35);
  /* 動效 */
  --tr:150ms cubic-bezier(.2,.6,.3,1);      /* hover/focus/小狀態 */
  --tr-big:240ms cubic-bezier(.2,.8,.2,1);  /* drawer/savebar/toast */
}
```

- **字體**：`Inter,"Noto Sans TC",system-ui,sans-serif`；HTML 基準 `13px`。
- **字級 scale（只准用這些）**：11（kbd/hint/pal-foot）、12（badge/輔助/軸標）、13（正文/表格/按鈕）、14（強調正文/hero 副標）、16（保留）、20（頁標題 h1/圖表大數）、24（指標卡值/hero 標題）。行高 1.45–1.6；中文標題字距 0，數字用 `tabular-nums`。
- **間距**：4px 網格。慣用：卡 padding 16、卡間 gap 16、表格 cell `8px 12px`、listbar `8px 12px`、頁邊 32、區塊間 24。
- **z-index 階層**：content 0 < sticky listbar 3 < topbar/sidebar 40 < settings 50 < annot-bar 70 < overlay/modal 80 < toast 90 < doc-pop 95。
- **版寬**：Index 頁 max 1200；Home/Detail 998；settings 內容欄 660、側欄 270。
- **佈局常數**：topbar 高 52；sidebar 寬 220；按鈕高 32（sm 28）；輸入高 32；表格列高 ~40（8px cell 上下）。
- **Storefront 品牌 tokens**（另一套，見 20 §3b）：cream `#f6f1e9`、paper `#fffdf8`、ink `#221e1a`、clay `#a9502c`；serif=Fraunces/Noto Serif TC；按鈕方角 radius 2；區塊垂直 96–128px。

## 2. 佈局結構規格

- **App frame**：topbar（左 logo+版本徽章、中 搜尋 max-width 600、右 icon 群+商店 chip）＋左 sidebar＋捲動 main。sidebar 分四段：主導航（當前 section 才展開子項）→ 銷售管道群 → 應用程式群 → 底部固定（AI 對話、設定）。
- **導航行為**：nav-item 高 30（6px 上下 padding）；選中＝白底膠囊+600 字重+微陰影；hover `#ededee`；badge 計數靠右膠囊。子項縮排 36px。
- **設定框架**：全螢幕 overlay（非路由頁）；右上 ✕（Esc 可關）；左欄=組織區塊（組織/使用者）+商店區塊+分類清單；內容欄卡片流。開啟時焦點移入。
- **頁面模板**：Index（page-head → card[listbar+table+pagination]）；Detail（返回鈕+標題+badge+動作列 → 兩欄 grid：主欄 1fr 卡片流+側欄 300px）。

## 3. 元件交互規格（狀態×鍵盤×ARIA×動效）

| 元件 | 規格 |
|---|---|
| Button | 四型：pri（近黑+內光暈+1px 投影）/sec（白+#c9cace 框）/ghost/sm。狀態：hover 變底、active 微沉、`:disabled{opacity:.45}`、loading=文字換「…中」+禁用。焦點環 2px `--focus` offset 1px（全元件一致） |
| 輸入框 | 高 32、框 `#c9cace`；hover 加深；focus=藍框+2px 光暈 `rgba(42,120,214,.18)`；錯誤=紅框+下方 12px 紅字；placeholder=--text-3 |
| Badge | 高 20、r-pill、12px/500；**pip 圓點語意**：空圈=未開始、半圈=進行中、實圈=完成；色=語意對（例：未出貨=attention+空圈、部分出貨=warning+半圈、已付款/已出貨=default 灰+實圈、已取消=critical）。文案用過去式單詞 |
| 檢視切換器 | chip「名稱 ⌄」→ 點開 view-menu（180ms 內 fade+pop）；選中項打勾+600 字重；點外關閉；未來：尾端「＋」另存目前篩選為新檢視 |
| Filterbar | 搜尋即時過濾（debounce 不需要，本地）；`#` 前綴與大小寫正規化；未來 filter pills 掛在輸入框內右側，可 ✕ 移除 |
| IndexTable | 表頭 surface-3+12px/600；列 hover `#fafafc`；選中列 `#f0f5ff`；**取消單整列 line-through（badge 豁免）**；checkbox 全選三態（checked/indeterminate）；整列可點進詳情（checkbox 格 stopPropagation） |
| BulkBar | 選取>0 時浮出（absolute 覆蓋表頭上方，深色 #1a1b1d，pop 160ms）；顯示「已選取 n」+動作組；清空選取即收 |
| SaveBar（表單） | 表單 dirty→浮出（v1 頂部橫列或 v2 右下浮動組，二選一全站一致——**定案：右下浮動**）；捨棄=還原 snapshot；儲存=按鈕 loading 450ms→收起+Toast；導航離開 dirty 頁→toast 阻擋 |
| Toast | 底部置中深色膠囊；進出 240ms `--tr-big`；停留 2.6s；同時只一則（新蓋舊）；`role="status" aria-live="polite"` |
| Modal | overlay `rgba(26,28,30,.4)`；點外/Esc/✕ 關；寬 520；destructive 確認=紅主鈕+「無法復原」說明。Esc 關閉順序：doc-pop → palette → modal → settings（一次關一層） |
| Popover/Menu | 觸發元下方 8px；fade+pop 120–150ms；點外關閉；項目 hover surface-2 |
| Command palette（CTRL K） | 置中 560 寬；輸入即過濾；↑↓ 移動高亮、Enter 開啟、Esc 關；分組標題 11px 大寫；`role="dialog"` |
| Skeleton | shimmer 1.2s 線性循環；列表首載 350ms 後換真列；換頁用 skeleton 不用整頁 spinner |
| EmptyState | 置中：粗體標題+一句說明+CTA；搜尋空結果必附「清除搜尋」 |
| 圖表 | 見 dataviz 規格：hover 十字+tooltip（跟隨最近點）；單系列無圖例；y 軸 5 檔清潔數；末端點 4px+白圈；表格視圖切換文字對應變化 |
| 開發註釋模式 | ⌗ 開關→body.annotate；`[data-doc]` 虛線紫框；capture 階段攔截點擊→popover 顯示 功能/邏輯/實作；Esc/點空白關 |

## 4. 全域交互原則

1. **回饋三件套**：任何寫入動作→按鈕 loading→成功 Toast／失敗紅 Banner（含重試）。無「默默成功」。
2. **數字同源**：同一指標在不同位置（pulse、列表 badge、分析卡）必須同一查詢口徑（rollup 服務統一供數）。
3. **鍵盤**：CTRL/⌘K 全域搜尋；Esc 分層關閉；**G 系列跳轉**（G→H 首頁、G→O 訂單、G→P 產品、G→A 分析、G→S 設定，1 秒窗口）；表格未來支援 j/k 移動（P2）。
4. **載入**：導航切頁即時（本地）；資料載入 skeleton；>1s 的操作必有進度回饋。
5. **樂觀更新**：僅限輕量玩具級操作（pin、勾選）；金流/庫存/訂單一律等伺服器回應。
6. **危險操作**：刪除/取消/停用一律二次確認 modal（紅主鈕）；不可復原者必須寫明。
7. **空/錯/載 三態**：每個列表與詳情頁都要有；錯誤 banner 提供動作（重試/回上頁）。
8. **a11y 底線**：文字對比 ≥4.5:1；焦點環永遠可見；icon-only 按鈕必有 aria-label；overlay `role="dialog" aria-modal`＋焦點移入；toast aria-live；觸控目標行動版 ≥44px。

## 5. 動效參數表

| 場景 | 時長/曲線 |
|---|---|
| hover/focus/按鈕 | 150ms `cubic-bezier(.2,.6,.3,1)` |
| drawer/savebar/toast 進出 | 240ms `cubic-bezier(.2,.8,.2,1)` |
| menu/popover | 120–160ms fade+4px 位移 |
| 頁面切換 | 180ms fade+3px 上移 |
| skeleton shimmer | 1.2s linear infinite |
| 條圖生長 | 500ms `cubic-bezier(.2,.8,.2,1)`（width transition） |
| 前台商品卡 hover | 圖 scale 1.03–1.04、600ms；快速加購浮現 150ms |
| prefers-reduced-motion | marquee/長動畫停用；位移動效改純 fade |

## 6. 與原型的對應（Codex 遷移指引）

- v2 的 CSS class 命名即元件命名基準：`.card/.badge/.btn-*/.listbar/.view-chip/.filterbar/.idx/.bulkbar/.tl-*/.set-*` → React 元件 `Card/Badge/Button/ListBar/ViewSwitcher/FilterBar/IndexTable/BulkBar/Timeline/Settings*`。
- 遷移順序：tokens.css（§1 原樣搬）→ 基礎元件（對照 §3 狀態表寫 storybook/測試）→ 兩個頁面模板 → 逐頁組裝（對照 22 號逐行）。
- 差異授權：任何偏離本規格的視覺/交互改動，先改本文件與原型，再改代碼（規格先行）。
