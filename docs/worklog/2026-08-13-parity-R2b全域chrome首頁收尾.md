# Parity R2b：全域 chrome＋首頁全頁收尾

> 對應規格：docs/specs/71 §E R2b、§F（R0-MISS2 ✅／R1-V4 ✅／R2b-MISS1 ✅／R2b-V×2）｜
> 實測：CtrlK 搜尋框（類型 chips＋結果態分類計數＋footer 兩動作）、快訊 popover（標題＋篩選/已讀＋空態原文）、
> 「API 相關需求搜尋結果」點開驗明正身、首頁全內容抽取（setup guide 實為 7 卡）、所有管道/過去 30 天 scope 控制｜
> commit：見本檔所在 commit

## 已完成的工作 (Done)

- **實測補完**：①CtrlK 搜尋＝輸入前類型 chips（應用程式/顧客/訂單/產品/銷售管道）→輸入後分類計數 chips
  （設定 24/導覽 15）＋結果列（icon+標題+描述關鍵詞粗體）＋「再顯示 20 個」＋footer 兩動作（向 Sidekick 詢問/
  App Store 搜尋）；②快訊＝錨定 popover（篩選+全部已讀 icons＋空態「關於您商店與帳號的快訊將顯示於此處」）；
  ③**「API 相關需求搜尋結果」驗明正身＝釘選的 Sidekick 對話**（R0-MISS2 形態修正）；④首頁 setup guide 全 7 卡
  （各帶進度環+下一任務+CTA）；⑤問候語時段制兩行（晚安！/繼續拓展您的業務。）。
- **原型補齊（7 處）**：
  1. 期間控制正式版 `hmScopeDate()`（預設集＋過去 N 數值/單位/包含今天＋取消/套用）——**R1-V4 結案**，
     對標 `S-SHOPIFYQL-DATE-CONTROLS`，共用元件。
  2. 管道範圍 `hmScopeChannel()`（所有管道/線上商店/AI 代理/門市 POS）。
  3. 快訊改錨定 popover（外點關閉；未讀點/跳轉語義保留；原 modal 形態淘汰＋追溯註釋）。
  4. 搜尋 palette 升級：類型 chips 列＋footer 兩動作（向 AI 助理詢問/在應用程式市集搜尋——我方命名，
     品牌紅線不用本尊商標）。
  5. 側欄底部「AI 對話釘選」入口＋`aiOpenPinned()` 對話檢視（markdown 回答+追問建議+讚/倒讚）。
  6. 首頁問候語時段制（早安/午安/晚安/夜深了）＋副行「繼續拓展您的業務。」。
  7. ai-box：placeholder「請輸入您的問題…」＋附加 [+] 鈕；即時訪客改為連結→實況瀏覽（m-live）。
- **DOCS**：新增 6 條（hm-scope-date/hm-scope-channel/ai-pinned/search-chips/search-ai/hm-live 更新）。
- **驗證**：lint ERROR 0/WARN 13（=基線）；煙霧測試 7/7（時段問候/ai-box/兩 scope pop/快訊/palette/釘選）；
  console 零錯誤。途中抓到一個自己的 bug：palette 是靜態 HTML 卻寫了模板字串 `${}`——當場改純靜態
  （教訓：改檔前先確認該區塊是 HTML 還是 template literal）。

## 修改的檔案與核心邏輯 (Changes)

- `docs/design/chilllove-admin-v2.html`（renderPulse scope 控制＋hmScopeDate/hmScopeChannel＋openAlerts 改寫＋
  palette 兩處＋nav-foot＋aiOpenPinned＋hero-hello/ai-box＋DOCS 6 條）、`docs/specs/71`（§E R2b、§F 五條）。
- **為什麼快訊用 view-menu 類而非新 CSS**：z-index 已由既有類管理（lint 禁裸 z-index）；popover 錨定語義
  與本尊一致即可，視覺走我方 tokens（G10）。
- **為什麼「向 Sidekick 詢問」改成「向 AI 助理詢問」**：Sidekick 是本尊商標（鐵律 9）；結構與觸發時機 1:1，
  名稱用我方。

## 尚未完成或需注意的風險 (Pending / TODO)

- 71-R2b-V1：搜尋結果態富形態（分類計數/描述粗體/再顯示）待 M1 搜尋後端（14-F4）落地時實作——結構已入 DOCS。
- 71-R2b-V2：setup guide 卡集為商店狀態函數（實測 7 卡），我方 3 卡同構——低優先備查。
- 自訂範圍的雙月曆日曆面板仍簡化（選「自訂範圍…」目前僅選中態）——已在 hm-scope-date DOCS 註明。
- 商店切換器（store-chip）點擊行為未實測（單店 demo 無切換場景）——R12 設定輪帶查。
