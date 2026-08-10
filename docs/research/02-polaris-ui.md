# 02 — Polaris 設計系統與後台 UI 交互模式

> 本篇是「把後台做得像 Shopify」的視覺與交互規格書：design tokens、admin 佈局、列表頁/詳情頁兩大模式、回饋元件與互動細節。⚠️ 開頭先看授權注意事項。

## 1. Polaris 現況與授權（2025–2026，重要）

- Shopify 已把 Polaris 全面改建為 **Web Components**（`s-` 前綴自訂元素，如 `<s-page>`、`<s-button>`），隨 `2025-10` 版本線於 2025-10-01 正式發布，目標一套元件跨 App Home、Admin extensions、Checkout/POS extensions。元件由 Shopify CDN 載入、無框架依賴。
- **Polaris React（@shopify/polaris）已封存**：GitHub repo 進入 maintenance mode，最後大版 v13.x（小版待確認）；舊文件遷至 archive 站。polaris.shopify.com 已轉址到 shopify.dev/docs/api/polaris。
- **授權注意（對本專案是關鍵風險）**：Polaris 的 License **並非純 MIT**，而是 MIT 改寫版、附二擇一條款——應用須「與 Shopify 軟體/服務整合或互通」**或**「與 Shopify 產品明顯不同且視覺可區分」；做 Shopify 復刻品兩個分支都不符。icon 與插圖另受 Polaris Design Guidelines License 約束。結論：
  - ❌ 不要直接 `npm install @shopify/polaris` 拿來做獨立競品。
  - ✅ 可以參考其公開文件的設計規格（token 值、間距、模式），**自建同風格元件庫**——設計語言本身（顏色數值、間距規則、佈局慣例）不受著作權保護，但程式碼與圖示資產受授權約束。icon 改用 MIT 的替代品（如 Lucide）。
  - 正式產品階段應發展自己的品牌視覺（詳見 07）。

## 2. Design Tokens（自建元件庫的規格基準）

- **色彩**：語意化命名 `color-{category}-{intent}-{state}`；category 分 bg（頁面/surface/fill）、text、border、icon；intent 有 brand / info / success / warning / caution / critical / emphasis / magic（AI 紫）/ inverse；state 有 hover / active / selected / disabled。代表值：頁面底 `#F1F1F1`、卡片 surface `#FFFFFF`、次層 surface `#F7F7F7`、主按鈕 fill-brand `#303030`（近黑）、正文 text `#303030`、邊框 `#E3E3E3`、icon `#4A4A4A`；success 綠 `rgb(4,123,93)`、critical 紅 `rgb(199,10,36)`、warning 黃 `#FFB800`。**現行 Admin 為 light-only，無正式 dark mode**。
- **字體**：sans stack 以 **Inter** 為首（fallback 系統字體）；字級 token 11px–40px，常用 body 12–14px；字重採 Inter 可變字體的 450 / 550 / 650 / 700（regular/medium/semibold/bold）。
- **間距**：4px 基準；token 數字 = 值 × 25（`space-100`=4px、`space-200`=8px、`space-400`=16px … `space-3200`=128px，另有 1/2/6px 微階）。慣例：card padding 16px、card 間 gap 16px、按鈕群 gap 8px。
- **圓角與邊框**：radius 2px–30px + full；卡片 12px、按鈕/輸入框 8px；邊框寬 0.66/1/2/4px。陰影極淡，現行 admin 卡片以 1px 邊框 + 微陰影呈現平面感（確切值待確認）。

## 3. Admin 整體佈局（App Frame）

- **左側導航**：灰底 sidebar，選中項白底膠囊 + 粗體；結構見 00 的導航地圖。Sales channels 與 Apps 為獨立群組，app 可 pin；Settings 固定左下角，點入是獨立的設定框架（左欄換成設定分類）。
- **頂部列**：深色 top bar；中央全域搜尋框（顯示 ⌘K/Ctrl+K 提示）；右側通知鈴鐺（未讀數）、商店切換器（店名 + 頭像）。
- **行動版**：手機 app 用底部 tab + 抽屜選單；窄視窗時 sidebar 收合為漢堡選單、表格轉卡片列表。

## 4. 列表頁模式（Index Pages）——後台最重要的複合模式

核心組合：`Page` + `Card`（flush）+ `IndexFilters` + `IndexTable` + `Pagination`。

- **Tabs = saved views**：第一個 tab 固定為「All」，其後是使用者自訂檢視（儲存目前「篩選 + 排序」組合），可建立/改名/複製/刪除，尾端「+」新增。
- **篩選流程**：點搜尋/漏斗 icon 進入 filtering mode →「Add filter」挑欄位 → Popover 內用 ChoiceList/日期控件設值 → 已套用條件顯示為可移除的 **filter pills** → 可 Clear all → 改動後可 Save as 新 view。
- **搜尋**：同列的 query 輸入框即時過濾。**排序**：右側按鈕開 Popover 選欄位 + 升/降序。
- **批次操作**：每列 checkbox + 表頭全選；選取後表頭變 bulk actions 列（「已選 n 項」、Select all 50+、動作按鈕 + 更多選單）。
- **分頁**：底部置中，僅前/後箭頭（cursor-based，無頁碼）。
- **列內**：整列可點進詳情；狀態欄用 Badge；hover 顯示快捷動作或「…」選單。

## 5. 詳情/編輯頁模式（Resource Detail）

- **版面**：預設窄版容器；兩欄 grid——主欄約 2/3（資源本身的表單卡片）、側欄 1/3（狀態、發布、組織/分類等 metadata 卡片）；卡片依重要性排序、相關欄位同卡。
- **頁首**：返回箭頭 + 資源標題（旁掛狀態 Badge）+ 次要動作（Duplicate/Archive/Delete 收進選單）+ 上一筆/下一筆切換。
- **Contextual save bar**：表單變 dirty 時頂部出現深色橫列（「Unsaved changes」+ Discard / Save）；Save 成功後收起 + Toast。這是 Shopify 後台「不用按編輯模式、改了就存」心智模型的核心，必復刻。
- **離開攔截**：有未儲存變更時導航離開會跳確認 modal。
- **驗證與錯誤**：submit 時欄位下方 inline error（紅字 + icon）+ 頁頂 critical Banner 彙總 + 焦點移到第一個錯誤欄位。

## 6. 回饋與狀態元件

- **Toast**：底部置中黑色膠囊，約 5 秒自動消失，支援 error 樣式與單一 action（如 Undo）。
- **Banner**：四種 tone——info 藍 / success 綠 / warning 黃 / critical 紅；頁級或卡片內，含標題、內文、動作、dismiss。
- **Badge**：tone 有 default 灰 / info 藍 / success 綠 / attention 黃綠 / warning 橘黃 / critical 紅 / new / magic 紫，另有 progress 屬性（incomplete 空圈 / partiallyComplete 半圈 / complete 實圈）。訂單慣例：Paid = 灰 + complete、Payment pending = 橘黃、Unfulfilled = attention 黃 + 空圈、Fulfilled = 灰 + complete、Partially fulfilled = warning + 半圈；badge 文案用過去式單詞。
- **EmptyState**：插圖 + 標題 + 說明 + 主/次動作（零資料首屏）。
- **Skeleton**：換頁載入用 SkeletonPage/BodyText/DisplayText，不用整頁 spinner；Spinner 留給局部。
- **Modal**：destructive confirm 慣例——標題問句（"Delete 3 products?"）、說明不可復原、紅色主按鈕 + Cancel。
- **Popover + ActionList**：「…」選單、下拉動作清單，支援分組與紅色 destructive 項。

## 7. 常用複合元件

- **Resource picker**：選商品/變體/collection 的 modal，內建搜尋、篩選、單/多選、預選；（顧客選擇器非標配，多為自建搜尋，待確認）。
- **Date range picker**（Analytics 慣用）：Popover 內三區——左側預設區間清單（Today / Yesterday / Last 7 days / Last 30 days…）、起訖輸入框、雙月曆；底部 Cancel / Apply；行動版收成單欄。
- **Autocomplete / Combobox + Listbox**；**Tag input** = 多選 Combobox + 可移除 Tag（商品 tags 即此模式）。
- **DropZone**：拖放上傳，多檔、格式驗證、上傳進度縮圖。
- **Rich text editor**：商品描述/Pages/Blog 用，屬 admin 內部元件、不在公開元件庫（復刻可用 TipTap 等自組）。

## 8. 元件庫分類總覽（自建元件庫的 roadmap）

- Actions：Button、ButtonGroup
- Layout：Page、Layout、Card、Box、BlockStack、InlineStack、InlineGrid、Grid、Divider、FormLayout、EmptyState、CalloutCard、MediaCard
- Forms：TextField、Select、Checkbox、RadioButton、ChoiceList、Combobox、Autocomplete、Tag、DatePicker、ColorPicker、RangeSlider、DropZone、Filters、IndexFilters、InlineError、Form
- Feedback：Badge、Banner、ProgressBar、Spinner、Skeleton 系列、ExceptionList
- Typography：Text（單一元件吃 variant/tone）
- Tables/Lists：IndexTable、DataTable、ResourceList/ResourceItem、ActionList、OptionList、Listbox、DescriptionList
- Navigation：Tabs、Pagination、Link
- Overlays：Popover、Tooltip
- Images：Avatar、Icon、Thumbnail、KeyboardKey
- Frame 級（官方已改由 App Bridge 承接、獨立復刻需自製）：Modal、Toast、Frame、Navigation、TopBar、ContextualSaveBar、Loading

## 9. 互動細節

- **鍵盤**：⌘K/Ctrl+K 全域搜尋（輸入後可分類過濾：Orders、Products、Customers、Apps…，先列最近搜尋）；`?` 開快捷鍵總覽；Esc 關閉 overlay；⌘S 儲存與 G 系列跳轉 (待確認)。
- **載入慣例**：導航切頁 = Skeleton page + 頂部細進度條；表單送出 = 按鈕 loading + 禁用；完成 = Toast。樂觀更新非預設慣例，重要寫入等待伺服器回應（官方無明文，屬觀察）。
- **a11y**：目標 WCAG 2.1 AA；overlay focus trap；表單錯誤主動移焦；文字對比 4.5:1；icon-only 按鈕必附 accessibilityLabel；觸控目標 ≥44px (待確認確切數值)。

## 10. 復刻要點 Checklist（本篇 → 工程）

1. 先做 **design tokens 檔**（CSS variables：色彩/字級/間距/圓角/陰影），再做元件——順序不能反。
2. 第一批元件（撐起 80% 後台畫面）：Page、Card、Button、TextField、Select、Checkbox、Badge、Banner、Toast、Modal、Tabs、IndexTable + IndexFilters、Popover/ActionList、SaveBar、EmptyState、Skeleton。
3. 兩大頁面模式（Index / Detail）做成**頁面級模板元件**，所有模組頁共用。
4. Contextual save bar + 離開攔截 + Toast 是「Shopify 手感」的靈魂，優先做對。
5. 全域 ⌘K 搜尋可後置，但 top bar 位置先留。
6. icon 用 MIT 授權庫（如 Lucide）替代 Polaris icons；插圖（EmptyState 用）自製或用開源插圖庫。
