# 80 — 分析 按鈕級 teardown（R11，2026-08-14 實測＋help 雙工作流 495K）

> 六層標準（層⓪載入紀律／層①按鈕級／層②值域窮舉／層③架構分析／層④CSS 三段式／層⑤help 雙源／層⑥條件控件三源）。
> 雙源：**實測**（`chill-love-u5q5mnzq`，鐵律 12.2 全流程寫入：AI 生成→儲存→改名→切模式→刪除）
> ＋ **help 工作流** wf_7cd3e817-112（4 主題＋2 critic，6/6，403K）＋ **shopify.dev 工作流**（ShopifyQL 語言規格，92K）。

---

## §0 架構圖（層③）

### §0.1 路由樹（實測 href 收割，鐵律 12.1 禁猜）
```
分析 /analytics                      （總覽控制面板；導航區根）
├─ 報告   /analytics/reports          （報告清單；分頁 1-50）
│   ├─ 新增探索 /analytics/reports/explore        ← 未儲存態，標題「新探索」
│   └─ 具名報告 /analytics/reports/{numeric_id}   ← 儲存後（實測 450298091）
└─ 實況瀏覽 /analytics/live
```
🔴 **`?ql=` 是這個模組的第一等公民**：探索器／具名報告的**完整查詢狀態編碼在 URL query string**
（URL-encoded ShopifyQL 全文，含換行）。實測 `/analytics/reports/450298091?ql=FROM+sales%0A++SHOW+orders…`。
⇒ 具名報告 = **(id, 預設 ql)**，而 URL 的 `ql` 可覆寫它而不影響儲存值（改動後才出現「未儲存的變更」）。

### §0.2 🔴 探索器 ＝ ShopifyQL 編輯器，右側面板是它的雙向投影（本輪最重架構事實）
```
┌─ 快速篩選列 ──────────────────────────────────────────┐
│  期間 chip │ 比較基準 chip │ 幣別 chip │  註解 │ 控制項 │
├─ 主欄 ─────────────────────┬─ 控制面板（可摺疊）──────┤
│ AI 提示列「您想探索哪些資料？」│  ┌ 自由形式 │ 組別 ┐    │
│ ─────────────────────────  │  自由形式：4 槽          │
│ ● 查詢語法正確               │   指標／維度／視覺化圖表  │
│ ⌨ ? ↶ ↷ ▷ ^  （工具列 6 鈕）  │   ／篩選條件            │
│ 1 FROM sales                │  組別：5 槽              │
│ 2   SHOW orders             │   指標／組別定義／視覺化   │
│ 3   TIMESERIES day          │   ／間隔／篩選條件        │
│ 4   SINCE … UNTIL today     │                        │
│ 5 VISUALIZE orders          │                        │
│ ─────────────────────────  │                        │
│ 圖表 → 資料表                │                        │
└────────────────────────────┴────────────────────────┘
```
三者**同一份查詢的三種投影**，任一處改動同步其餘兩處：**QL 文字 ⇄ 右側槽位 ⇄ URL `?ql=`**。
- help 佐證：「Every default report has a pre-written query already displayed」、configuration panel
  的改動**即時反映到 query editor**。
- 🔴 我方原型現況是「ShopifyQL 進階模式」**彈窗**（`reportQL()`），這是**錯的結構**——
  本尊沒有「模式」，QL 編輯器**常駐主欄**。已登記 R11-V1。

### §0.3 🔴 自由形式 vs 組別是兩套不同的槽位集合，且切換會**清空查詢**
| | 自由形式 Freeform | 組別 Cohorts |
|---|---|---|
| 槽位 | 指標／維度／視覺化圖表／篩選條件（**4**） | 指標／**組別定義**／視覺化圖表／**間隔**／篩選條件（**5**） |
| schema | `FROM sales` 等 38 個 | 🔴 **`FROM customer_cohorts_{monthly\|weekly\|quarterly}`**（另一族 schema） |
| 指標目錄 | 365 個／10 類（分類抽屜） | **7 個平鋪**（無分類） |
| 視覺化 | **27** 種 | **2** 種（曲線／組別網格） |
| 預設期間 | 依來源（AI 生成給 `SINCE 2000-01-01`） | 🔴 `SINCE startOfMonth(-12m) UNTIL endOfMonth(-1m)`（過去 12 個月，**排除當月**） |
| 比較 chip | 無比較基準 | 「比較：個別組別」 |
- 實測切 tab 時 URL 變成 `?ql=`（**空**），三個 quick filter chip 全部轉禁用灰，
  頂欄從「捨棄／儲存」變成「**捨棄／另存新檔／儲存**」（編輯已儲存報告時多一顆另存新檔）。
- 🔴 **`TYPE retention_curve` 不在自由形式的 27 種清單裡**——視覺化型別是**依模式分池**的，
  不是單一 enum。實作若用一張 `visualization_type` 表會漏掉 cohort 專屬型別。已登記 R11-V2。

### §0.4 條件閘控三種形態（層⑥）
1. **槽位閘控**：未選指標前，維度／視覺化圖表／篩選條件三槽**全部禁用灰**；空態文案「請您先新增一項指標」。
   （help 佐證：「必須至少加入一個 metric 才能開始探索」。）
2. **類別閘控（依 dataset）**：`FROM sales` 下，維度選單的「工作階段與行為／庫存／財務與付款」
   三個類別**呈禁用灰**；但**篩選條件選單的同名 15 類全部可用**。
   ⇒ 🔴 維度與篩選走**不同的可用性規則**，不可共用一份 `available_fields`。已登記 R11-V3。
3. **項目閘控（類別內）**：每個維度類別內都有一個分組標題 **「根據現有選取項目無法使用」**，
   下面掛該類別中與當前查詢不相容的項目——**不隱藏、不移除，改為降級展示**。
   ⇒ 我方必須複製「顯示但不可選＋分組說明」而非過濾掉，否則使用者會以為欄位不存在。

### §0.5 說明文檔樹（層⑤，兩棵）
1. `help.shopify.com/manual/reports-and-analytics/shopify-reports`（總覽／報表／實況瀏覽／自訂報告）
2. `shopify.dev/docs/api/shopifyql/latest/*`（語言規格 38 schema）＋ `/admin-graphql/…/shopifyqlQuery`（API）
🔴 兩棵樹**互相矛盾處已逐條登記於 §6**（方案分層、Total sales 公式、歸因預設值、`app_events` schema）。

---

## §1 值域窮舉（層②）——探索器

### §1.1 指標目錄【窮舉：365 個／10 類，逐類點開實測】
> 抽屜式：搜尋框「搜尋指標」＋類別列表 → 點類別鑽入 → **checkbox 多選** ＋ 底部「清除／套用」。
> 返回＝點頂部帶 `←` 的同名標題列。左側常駐說明浮卡（縮圖＋「指標是計數與計算結果（例如顧客人數或毛利），可讓您追蹤關鍵業務指標。指標會顯示為資料表的「欄」。」）

| 類別 | 數量 | 代表值（完整清單見 §1.1.1–§1.1.10） |
|---|---:|---|
| 工作階段與行為 | 103 | 工作階段數／轉換率／跳出率／**CLS·FCP·INP·LCP·TTFB × 分佈·良好·需改進·不佳·P50·P75·P90·P99**／Shop Mini 開啟次數 |
| 行銷 | 26 | 廣告支出／ROAS／不重複點擊／**Shop Campaign ×6** |
| 訂單 | 55 | 訂單數／**四種歸因前綴 ×（訂單數·平均訂單品項數·淨售出品項數·總銷售額·總平均訂單價值）**／運送標籤成本 |
| 庫存 | 39 | 售罄率／存貨天數／期末庫存價值（依地點）／驗收通過率 |
| 財務與付款 | 53 | 付款授權率／拒付率／**禮品卡 ×9**／**商店抵用金 ×6**／Managed Markets 費用 |
| 商店 | 4 | 平均回覆時間／正面意見回饋／負面意見回饋／對話輪次 |
| 產品 | 2 | Collective 點擊次數／Collective 曝光次數 |
| 詐騙預防 | 8 | 詐騙拒付率／決策規則影響的金額／結帳影響率 |
| 銷售營收 | 69 | 銷售總額／銷貨淨額／總銷售額／**撤銷款項 ×6**／毛利率／回頭客比率 |
| 顧客 | 6 | 每筆訂單平均消費金額／累計消費金額／距上次訂單天數／新顧客數／總訂單數／顧客百分比 |

#### §1.1.1 工作階段與行為（103）
工作階段數／加入購物車比率／平均工作階段時間／全域搜尋要求／多組搜尋查詢／有加入購物車的工作階段／有點擊的搜尋工作階段／有點擊的搜尋查詢／行銷活動工作階段／行銷活動工作階段（已加入購物車）／行銷活動加入購物車率／行銷活動平均工作階段長度／行銷活動完成結帳率／行銷活動到達結帳率／行銷活動相關每工作階段的頁面瀏覽次數／行銷活動頁面瀏覽次數／行銷活動結帳轉換率／行銷活動跳出次數／行銷活動跳出率／行銷活動網路商店訪客／行銷活動轉換率／含推薦商品的工作階段／含搜尋的工作階段／完成結帳比率／完成結帳的工作階段／完成結帳的行銷活動工作階段／每工作階段頁面瀏覽次數／到達並完成結帳的工作階段／到達並完成結帳的行銷活動工作階段／到達結帳比率／到達結帳頁面的工作階段／到達結帳頁面的行銷活動工作階段／協助的工作階段／表單提交數／表單瀏覽次數／表單轉換率／頁面載入次數／頁面載入百分比／頁面瀏覽次數／推薦商品工作階段（加入購物車）／推薦商品工作階段（含點擊）／推薦商品工作階段（完成結帳）／推薦商品加入購物車率／推薦商品成效落差／推薦商品低點擊率／推薦商品點擊率／推薦商品轉換率／結帳轉換率／搜尋工作階段 (有加入購物車)／搜尋工作階段 (完成結帳)／搜尋加入購物車率／搜尋次數／搜尋點擊率／搜尋轉換率／跳出次數／跳出率／對話／網路商店訪客／轉換率／**CLS**{分佈·良好檢視次數·表現不佳檢視次數·需改進檢視次數·P50·P75·P90·P99}／**FCP**{不佳載入次數·分佈·良好載入次數·需改進載入次數·P50·P75·P90·P99}／**INP**{不佳載入次數·分佈·良好載入次數·需改進載入次數·P50·P75·P90·P99}／**LCP**{分佈·良好檢視次數·表現不佳檢視次數·需改進檢視次數·P50·P75·P90·P99}／**TTFB**{不佳載入次數·分佈·良好載入次數·需改進載入次數·P50·P75·P90·P99}／Shop 售後優惠／Shop 商品曝光次數／Shop 評論轉換率／Shop Mini 開啟次數

🔴 **Web Vitals 是一等指標**（5 指標 × 8 變體 = 40 個），對應 `web_performance` schema。
我方 19 號 rollup 規格完全沒有這一族——已登記 R11-V4。

#### §1.1.2 行銷（26）
不重複點擊／不重複瀏覽／平均獲客成本／回頭客 (平台回報)／佣金／含廣告的頁面瀏覽次數／投遞失敗／取消訂閱／垃圾郵件檢舉／訂單數 (平台回報)／首次購買顧客 (平台回報)／產品網路點擊數／發送數／網絡訂單量／廣告支出／廣告曝光次數／銷售額 (平台回報)／獲得的 Shop Campaign 抵用金／點擊次數／曝光次數／Shop Campaign 平均訂單價值 (AOV)／Shop Campaign 訂單／Shop Campaign 廣告支出／Shop Campaign 廣告投資報酬率 (ROAS)／Shop Campaign 銷售營收／Shop Campaign 顧客

#### §1.1.3 訂單（55）
已送達訂單數／已寄出訂單數／已接收的 Collective 訂單／已履行的 Collective 訂單／出貨作業至運送的中位數天數／出貨作業至運送的中位數時數／平均託運單標籤調整成本／平均配送時獲利（不含退貨）／平均商店成本（不含退貨）／平均商店運送成本／平均商店關稅與進口稅／平均運送標籤成本／平均銷售稅額／平均銷貨成本／平均營收（不含退貨）／平均關稅與進口稅調整成本／含追蹤編號比率／完成出貨作業的訂單數／折扣後平均銷售額／訂單至出貨作業的中位數天數／訂單至出貨作業的中位數時數／訂單至送達的中位數天數／訂單至送達的中位數時數／訂單至運送的中位數天數／訂單至運送的中位數時數／訂單數／**首次點擊**{平均訂單品項數·訂單數·淨售出品項數·總平均訂單價值·總銷售額}／**最後非直接點擊**{平均訂單品項數·訂單數·淨售出品項數}／**最後點擊**{平均訂單品項數·訂單數·淨售出品項數}／**最終非直接點擊**{總平均訂單價值·總銷售額}／**最終點擊**{總平均訂單價值·總銷售額}／運送至送達的中位數天數／運送至送達的中位數時數／運送標籤／運送標籤成本／輔助訂單／**線性**{平均訂單品項數·訂單數·淨售出品項數·總平均訂單價值·總銷售額}／顧客平均運費／顧客平均價格調整／顧客平均關稅與進口稅／Collective 訂單

#### §1.1.4 庫存（39）
存貨天數／存貨天數 (依地點)／收貨數量／每日售出庫存件數／拒收率／拒收數量／訂購數量／庫存天數／庫存天數 (依地點)／庫存末日／庫存件數淨變動 (依地點)／庫存首日／庫存首日 (依地點)／庫存調整次數／庫存調整變動／缺貨天數 (依地點)／售出的庫存百分比／售出庫存件數／售罄率／寄送的獨立庫存商品數／寄送數量／貨件／最後在庫日 (依地點)／剩餘庫存天數／剩餘庫存天數 (依地點)／期末庫存件數／期末庫存件數 (依地點)／期末庫存零售價值／期末庫存零售價值 (依地點)／期末庫存價值／期末庫存價值 (依地點)／期初庫存件數／期初庫存件數 (依地點)／無庫存天數／轉移／轉移的獨立庫存商品數／轉移商品項目／驗收通過率／驗收通過數量

#### §1.1.5 財務與付款（53）
已扣抵的商店抵用金／已到期的商店抵用金／已停用的禮品卡數量／已售出禮品卡金額／已發行的禮品卡數量／已發行禮品卡金額／已發放的商店抵用金／已調整的禮品卡數量／不重複的付款嘗試／內含稅額／支付款項金額／**支付款項金額（付款貨幣）**／付款毛額／付款授權率／付款授權率（原始）／付款淨額／付款淨額（不含禮品卡）／付款處理費用／付款嘗試總次數／四捨五入後的付款淨額／失敗的付款嘗試／平均付款處理費用／平均國際費用／平均幣別轉換費用／平均 Managed Markets 費用／交易金額／交易筆數／交易數量／成功付款／含交易的訂單數／定價調整金額／拒付／拒付金額／拒付率／退款金額／停用的禮品卡金額／商店抵用金餘額淨變動／國際費用／淨額／**現金進位原則**／期末商店抵用金餘額／期末禮品卡餘額／期初商店抵用金餘額／期初禮品卡餘額／幣別轉換費用／調整的禮品卡金額／銷售稅／總額／禮品卡兌換金額／禮品卡退款金額／禮品卡餘額淨變動／Managed Markets 稅額／Managed Markets 費用

🔴 **撞鐵律 3**：`支付款項金額（付款貨幣）` 與 `支付款項金額` **並存為兩個獨立指標**，
且另有 `幣別轉換費用`／`四捨五入後的付款淨額`／`現金進位原則`。
⇒ 本尊在報表層就把「店幣金額」與「付款幣別金額」當**兩個不同的欄**，不是一個欄加個幣別標籤。
這正面佐證 65 號「不同單位用不同型別」的設計。已登記 R11-V5。

#### §1.1.6 商店（4）
平均回覆時間／正面意見回饋／負面意見回饋／對話輪次

#### §1.1.7 產品（2）
Collective 點擊次數／Collective 曝光次數
（**產品層級銷售指標不在這裡**——`售出數量`／`淨售出品項數` 掛在「銷售營收」。這是本尊的分類反直覺處，抄錯會找不到欄位。）

#### §1.1.8 詐騙預防（8）
可接受的詐騙風險比率／成功交易／決策規則影響的金額／受決策規則影響的結帳次數／高詐騙風險比率／結帳影響率／詐騙拒付／詐騙拒付率

#### §1.1.9 銷售營收（69）
小費／已記錄成本的銷貨淨額／不含禮品卡的稅額／毛利／毛利率／平均訂單價值 (AOV)／未記錄成本的銷貨淨額／回頭客比率／回頭客數／折扣／折扣訂單數／**折扣撤銷款項**／每位顧客的訂單數／每位顧客的消費金額／每筆訂單的訂購數量／使用中的訂閱數／來自 app 的商品與訂單折扣／來自 app 的運送折扣／取消訂閱數／訂單層級折扣／訂單數 (回頭客)／訂單數 (首次購買)／訂單銷售協議／訂購套裝組合數／訂購數量／員工協助銷售比率／套用折扣金額／退貨費用／退貨數量／商品項目折扣／商品與訂單折扣／淨售出品項數／稅額／**稅額撤銷款項**／新增訂閱數／新顧客數／運送折扣／運費／運費折扣／運費稅額／**運費撤銷款項**／運費總計／**撤銷數量**／**撤銷數量比率**／**銷售撤銷款項**／銷售總額／**銷售總額撤銷款項**／銷貨成本／銷貨淨額／**銷貨淨額撤銷款項**／總銷售額／總銷售額 (回頭客)／總銷售額 (首次購買)／**總銷售額撤銷款項**／禮品卡折扣／禮品卡稅額／禮品卡銷售淨額／禮品卡銷售總額／額外商品與訂單折扣／額外費用／額外運送折扣／關稅／顧客數／Collective 收益／Collective 總銷售額／Shop 售後訂單／Shop 售後銷售額／Shop Mini 訂單／Shop Mini 銷售額

#### §1.1.10 顧客（6）
每筆訂單平均消費金額／累計消費金額／距上次訂單天數／新顧客數／總訂單數／顧客百分比

### §1.2 維度目錄【窮舉：299 個／16 類（`FROM sales` 下 13 類可用、3 類禁用）】
> 說明浮卡：「規格尺寸是資料的屬性（例如銷售管道或交易狀態），可讓您更精細地檢視業務的各個層面。規格尺寸會顯示為資料表的「列」。」
> 🔴 譯名不一致：浮卡用「規格尺寸」，槽位標題與選單用「維度」。同一概念兩個中文詞（本尊如此，照抄）。

**禁用類別（`FROM sales` 下）**：工作階段與行為／庫存／財務與付款
**可用類別（13）與內容**：

- **未指定（15）**：行銷平台／已歸屬的工作階段權杖／正規化的頁面網址／行銷活動 API 用戶端 ID／行銷活動 ID／是否為首次跨裝置工作階段／是否為最後一次工作階段／是否為最後一次非直接跨裝置工作階段／訂單處理時間／跨裝置線性歸因模型權重／點擊 ID 標籤／轉移 app 名稱／轉移 app ID／顧客重複訂單〔＋「根據現有選取項目無法使用」分組〕
- **地點（21）**：收件公司／帳單公司／帳單地址 ID／帳單郵遞區號／帳單開具地區／帳單開具城市／帳單開具國家/地區／運送地址 ID／運送地區／運送城市／運送國家/地區／運送郵遞區號／POS 地點名稱／記錄商家 (Merchant of Record) 地區／記錄商家 (Merchant of Record) 國家/地區／國家/地區／課稅地區／課稅城市／課稅國家/地區／顧客國家/地區〔＋不可用分組〕
- **行銷（42）**：代理程式轉介管道／行銷自動化 ID／行銷活動狀態／行銷活動項目 ID／行銷活動網址參數值／行銷活動網址參數鍵／行銷活動標題／行銷活動 ID／行銷傳遞管道／行銷管道代稱／是否為 Shop 轉介訂單／流量類型／頁面主機／頁面路徑／登陸頁面網址／轉介方／轉介平台／轉介媒介／轉介管道／Shop Campaign 目標名稱／Shop Campaign 名稱／Shop Campaign 控制代碼／Shop Campaign 幣別代碼／**UTM**{行銷活動內容·名稱·來源·媒介·關鍵字}〔不可用分組後〕外部行銷 ID／行銷活動平台網址／行銷活動建立日期／行銷活動啟用日期／行銷活動結束日期／行銷活動項目預覽網址／行銷活動預定結束日期／行銷活動管道／行銷預算／行銷預算類型／行銷 API 用戶端 ID／產品網路展示位置／產品網路類別
- **訂單（61）**：市場／是否為已取消訂單／訂單付款狀態／訂單出貨狀態／訂單包含關稅／訂單行銷活動目標／訂單行銷活動類型／訂單行銷活動 ID／訂單的銷售管道 ID／訂單登陸頁面路徑／訂單登陸頁面網址／**訂單結帳幣別**／訂單標籤／訂單銷售管道／訂單轉介名稱／訂單轉介來源／訂單轉介路徑／訂單轉介網址／訂單轉介網站／訂單轉介網域／訂單 ID／訂單 UTM{campaign·content·medium·source·term}／訂購名稱／首購流量類型／首購銷售管道／首購轉介管道〔不可用分組後〕出貨作業至運送(小時/天)／出貨作業事件(小時/天)／出貨作業 ID／出貨來源國家/地區／出貨服務供應商／出貨服務供應商 ID／出貨國家/地區／包裹{名稱·長度·重量·重量單位·高度·規格尺寸單位·寬度·類型}／到岸價格調整類型／訂單至出貨作業(小時/天)／訂單至送達(小時/天)／訂單至運送(小時/天)／**託運單標籤幣別**／貨運業者／運送至送達(小時/天)／運送服務／運費
- **時間（20）**：分鐘／日／月／年／年間月份／年間週別／季／時／週／週間日／當天時段／Shop Campaign 訂單計費時間〔不可用分組後〕交易日期／更新時間／秒／提交時間／對話建立時間／輪次更新時間／輪次建立時間
  🔴 對應 ShopifyQL 的 12 個時間維度（8 區間型＋4 循環型），見 §2.5。
- **商店（5）**：商店名稱／商店 ID〔不可用分組後〕情境／買家意見回饋
- **推出（2）**：推出試驗變項 ID／推出 ID
  🔴 **與 R10 的「推出」（A/B 測試與排程）直接對接**——推出的成效在這裡量測。
  ⇒ 我方 `rollouts` 實作必須同時寫出 `rollout_id` 與 `rollout_variant_id` 兩個分析維度，否則 A/B 測試無法評估。已登記 R11-V6。
- **產品（23）**：一起購買的子類／一起購買的子類 (數量)／一起購買的商品／一起購買的商品數／子類名稱／是否為套裝組合／套裝組合名稱／套裝組合商品 ID／套裝組合 ID／商品系列／商品狀態／產品子類選項 ABC 等級／產品子類選項 ID／產品子類選項 SKU／產品名稱／產品廠商／產品標籤／產品類型／產品 ID／App（商品建立）〔不可用分組後〕供應商品牌／商品類別
- **詐騙預防（10）**：訂單已納入 Shopify Protect 保障範圍／訂單享有 Shopify Protect 完整保障／訂單取消原因／訂單風險等級／訂單符合 Shopify Protect 資格〔不可用分組後〕拒付原因／是否透過快速爭議解決服務結案／停用狀態下評估的決策規則／結帳規則 ID
- **零售／POS（8）**：協助銷售員工姓名／協助銷售員工 ID／是否為實體店面／員工姓名／員工 ID／POS 地點 ID〔不可用分組後〕POS 收銀機 ID
- **銷售營收（55）**：代理程式銷售管道／折扣方式／折扣代碼／折扣名稱／折扣前運送價格／折扣項目 ID／折扣標題／折扣類別／折扣類型／折扣 ID／折抵金額／明細類型／是否已記錄成本／是否為未經驗證的退貨／是否為折扣銷售／**是否為銷售撤銷**／是否為銷售調整／是否為 POS 銷售／**訂單或銷售撤銷款項**／訂閱或單次／退貨原因／退款 ID／**售出時的**{產品子類選項名稱·產品子類選項 SKU·產品名稱·產品廠商·產品類型}／商品項目 ID／排除訂單建立後的調整／產品子類選項比較售價／產品子類選項價格／運送折扣名稱／價格規則折扣金額／價格規則折扣標題／價格規則折扣類型／價格規則類型／銷售管道／銷售管道 ID／銷售管道 ID (多管道 app)／銷售 ID／Collective 供應商〔不可用分組後〕由管道申報／是否為未驗證的退貨商品項目／退貨名稱／退貨狀態／退貨商品項目原因／退貨商品項目 ID／退貨備註／退貨顧客註記／退貨 app 名稱／退貨 app ID／退貨 ID／銷售稅 ID／禮品卡 ID
  🔴 **「售出時的產品名稱」是獨立維度**（vs「產品名稱」＝當前值）。help 明載 2024 新分析平台改用**當前**
  product title/SKU/vendor，要貼近歷史須改用 `Product title at time of sale`。
  ⇒ 我方商品維度必須**雙軌落庫**（快照名 ＋ 當前名），已登記 R11-V7。
- **顧客（32）**：未完成結帳作業日期／建立者應用程式 ID／首購包含訂閱／距首次購買的{月·年·季·週}數／新客或回頭客／預測消費等級／顧客名稱／顧客訂單數／顧客首購日期／顧客帳號狀態／顧客累計消費金額／**顧客組別{月·季·週}**／顧客最近訂單日期／顧客新增日期／顧客電子郵件／顧客電子郵件行銷訂閱狀態／顧客電子郵件網域／顧客語言／顧客標籤／顧客 ID／顧客 SMS 行銷訂閱狀態／**RFM 群組**〔不可用分組後〕首筆訂單日期／最後一筆訂單日期／顧客地區／顧客城市
- **B2B（5）**：公司名稱／公司地址名稱／公司地址 ID／公司 ID／是否為 B2B 訂單

### §1.3 視覺化圖表【窮舉：自由形式 27 種＋組別 2 種】
> 選單上方另有「**排序方式**」下拉【2】：最近新增／名稱；以及「**建議**」開關（預設**開**，
> 說明「選取『推薦』，系統會依您選取的指標與規格尺寸動態更新視覺化呈現」）。

**自由形式（27）**：曲線／樹狀圖／瀑布圖／日曆熱點圖／氣泡圖／散佈圖／雷達圖／簡易垂直長條圖／分組垂直長條圖／簡易水平長條圖／分組水平長條圖／按指標列出／按維度列出／顯示指標／顯示表格／目標量表／環圈圖／細分長條圖／長條分析圖 (頻率)／旭日圖／長條圖與折線圖／堆疊區域圖／堆疊垂直長條圖／堆疊水平長條圖／RFM Grid／漏斗／熱點圖

**組別（2）**：曲線／組別網格

**曲線型附屬開關【2】**：顯示註解（預設關）／累計（預設關）
- 「累計」對應 ShopifyQL 的 `WITH CUMULATIVE_VALUES`；「顯示註解」對應 `ANNOTATE`。

**對應 ShopifyQL `TYPE` 值（23 種，shopify.dev）**：bar／grouped_bar／horizontal_bar／horizontal_grouped_bar／single_stacked_bar／stacked_bar／stacked_horizontal_bar／rfm_grid／bubble_chart／histogram／scatter_plot／funnel／waterfall／calendar_heatmap／heatmap／line／stacked_area／donut／sunburst／treemap／radar／single_metric／list／list_with_dimension_values／table
🔴 UI 27 種 vs 文檔 23 種 vs cohort 專屬 `retention_curve`——**三份清單都不相等**。已登記 R11-V2。

### §1.4 篩選條件【類別 15 全可用；運算子窮舉 7】
- 類別與維度同名 15 類，但**全部可用**（無禁用）；且**指標也可當篩選對象**
  （實測「訂單」類下列出的是「已送達訂單數」等**指標**）⇒ 對應 ShopifyQL 的 `WHERE`（維度）＋ `HAVING`（指標）兩個子句。
- **數值型運算子【窮舉：7】**：是／不是／介於／大於／小於／大於或等於／小於或等於
- 每條篩選列的控件：`{欄位名}` ＋ `{運算子下拉}` ＋ `新增值` ＋ 行尾 ⓘ 說明／⧉ 複製／✕ 移除
- 🔴 **未填值的篩選不會進入查詢**（實測加了「已送達訂單數 是 ⟨空⟩」後 `ql` 仍無 `WHERE`）。
  ⇒ 我方必須複製「草稿篩選列」概念：UI 有列、查詢無條件，且不得報錯。已登記 R11-V8。
- 說明浮卡：「篩選條件可用於縮小資料範圍，例如來自特定地區的訂單或高於特定金額的銷售額。您可以使用篩選條件來聚焦分析重點。」

### §1.5 期間選擇器【窮舉：7 群組／25 值】
| 群組 | 值 |
|---|---|
| 今天 | （單值，直接選取） |
| 昨天 | （單值） |
| **過去**（11） | 過去 30 分鐘／過去 12 小時／過去 7 天／過去 30 天／過去 90 天／過去 365 天／上週／上個月／上季／過去 12 個月／去年 |
| **期初至今**（4） | 本週至今／本月至今／本季至今／今年至今 |
| **黑色星期五與網購星期一**（4） | BFCM 2025／BFCM 2024／BFCM 2023／BFCM 2022 |
| **季度**（4，滾動） | 2026 第 2 季／2026 第 1 季／2025 第 4 季／2025 第 3 季 |
| 自訂範圍 | 雙日期輸入（起→迄）＋ 🕐 時間圖示 ＋ 月曆（單月，前後箭頭）＋ 取消／套用 |
- 🔴 **BFCM 與季度是滾動窗**（BFCM 取最近 4 年、季度取最近 4 季）——**不是固定清單**，必須以當前日期推導。已登記 R11-DOC1。
- help 佐證 ShopifyQL 具名範圍 `bfcm2020`–`bfcm2025`（文檔比 UI 多兩年）。

### §1.6 比較基準選擇器【窮舉：4】
不進行比較（預設）／前一期間／自訂／**目標**
- 🔴 「目標」＝ ShopifyQL `COMPARE TO TARGETS`，且**僅在該 schema 支援時可用**。
- ⚠️ **實測與 help 不一致**：help 列「上一期間／去年／自訂／不比較」，實測是「不進行比較／前一期間／自訂／目標」——
  **實測沒有「去年」、help 沒有「目標」**。以實測為準（層⑤規定實測優先），差異登記 R11-DOC2。

### §1.7 幣別選擇器
- 探索器預設 **HKD HK$**（＝店幣，鐵律 11 基準法域）；**實況瀏覽預設 USD $**（🔴 兩頁預設不同源，見 §4）。
- 值域＝全 ISO 幣別清單（實測 255 項，格式 `中文名 (CODE 符號)`，例「港幣 (HKD HK$)」「日圓 (JPY ¥)」）。
- 對應 ShopifyQL `WITH CURRENCY '<code>'`。
- 🔴 **鐵律 3 判定**：`WITH CURRENCY` 是**顯示／換算幣別**宣告，**不是單位宣告**；
  help 對 `MONEY` dataType 的序列化格式（整數 minor unit vs 十進位字串）**完全沉默**。
  ⇒ **不得**把 Shopify 的 `MONEY`／`WITH CURRENCY` 當成我方單位契約的參照物；
  65 號四型別（`Money::Storage`／`PspMinor`／`PspDecimal`／`Decimal`）**照舊**。已登記 R11-V9。
- help 補充：總覽頁的幣別換算採「**交易日期的歷史匯率**」逐筆計，非期末單一匯率。

### §1.8 組別（Cohorts）專屬槽位
- **指標【窮舉：7，平鋪無分類】**：每位顧客的消費金額／平均訂單價值 (AOV)／顧客保留率／銷售總額／銷貨淨額／顧客數／總銷售額（與 help 列表完全一致）
- **組別定義【窮舉：5】**（標題「首筆訂單的篩選條件：」）：首購銷售管道／首購轉介管道／首購流量類型／首購包含訂閱／首購商品
  說明浮卡：「組別會將首筆訂單發生在同一期間的顧客歸為一組。您可以使用篩選條件進一步調整您的組別，例如首筆訂單來源為 Instagram 的顧客。」
  預設值顯示為 **「第一筆訂單」**＋右側篩選圖示。
- **間隔【窮舉：3】**：週／**月（預設）**／季
  說明浮卡：「您的組別資料的時間間隔 (週、月、季) 會決定顧客行為分析的細緻程度。」
  🔴 對應三個不同 schema：`customer_cohorts_weekly` / `_monthly` / `_quarterly`。
- **視覺化【窮舉：2】**：曲線（`TYPE retention_curve`）／組別網格（heatmap）
  說明浮卡：「使用組別網格比較顧客群組間的精確數值，或使用折線圖快速掌握隨時間變化的趨勢與模式。」
- 實測生成查詢（顧客保留率／月／曲線）：
```sql
FROM customer_cohorts_monthly
  SHOW customer_cohorts_monthly_customers,
    customer_cohorts_monthly_customers_customer_cohort_period_totals,
    customer_cohorts_monthly_customers_periods_since_first_purchase_totals,
    customer_cohorts_monthly_customers_totals,
    customer_cohorts_monthly_customer_retention_rate,
    customer_cohorts_monthly_customer_retention_rate_periods_since_first_purchase_totals,
    customer_cohorts_monthly_customer_retention_rate_totals,
    customer_cohorts_monthly_customers_in_cohort,
    customer_cohorts_monthly_customers_in_cohort_periods_since_first_purchase_totals,
    customer_cohorts_monthly_customer_retention_rate_customer_cohort_period_totals
  WHERE customer_cohorts_monthly_periods_since_first_purchase BETWEEN -1 AND 11
  GROUP BY month, customer_cohorts_monthly_periods_since_first_purchase
  HAVING customer_cohorts_monthly_periods_since_first_purchase >= 0
  SINCE startOfMonth(-12m) UNTIL endOfMonth(-1m)
  ORDER BY month, customer_cohorts_monthly_periods_since_first_purchase ASC
VISUALIZE customer_cohorts_monthly_customer_retention_rate TYPE retention_curve
```
  🔴 注意 `BETWEEN -1 AND 11` 搭配 `HAVING >= 0`——**取 13 期再濾掉第 -1 期**，
  這是為了讓 `_totals` 欄能算出完整基期。照抄時不可簡化成 `BETWEEN 0 AND 11`。

---

## §2 ShopifyQL 語言規格（層⑤，shopify.dev 全文）

### §2.1 子句與執行順序
`FROM` → `SHOW` → `WHERE` → `GROUP BY` → `TIMESERIES` → `WITH` → `HAVING` → `SINCE`/`UNTIL` 或 `DURING` → `COMPARE TO` → `ORDER BY` → `LIMIT` → `VISUALIZE`／`TYPE`〔→ `ANNOTATE`〕
- 必須有 `FROM`；必須有 `SHOW` 或 `VISUALIZE` 之一。一個 query 只能有一個 `FROM`。
- `FROM a, b` 多 schema join（共同維度）；`FROM ORGANIZATION schema` 跨店（Plus/Enterprise）。

### §2.2 `WHERE` 運算子（全集）
`=` `!=` `<` `<=` `>` `>=`／`IN` `NOT IN` `BETWEEN…AND` `NOT BETWEEN`／`STARTS WITH` `ENDS WITH` `CONTAINS` `NOT CONTAINS`／`IS NULL` `IS NOT NULL` `IS TRUE` `IS NOT TRUE` `IS FALSE` `IS NOT FALSE`／`AND` `OR` `NOT`（**`AND` 優先於 `OR`**）／`MATCHES`
🔴 **官方明列陷阱**：`!=` / `NOT IN` / `NOT CONTAINS` **不會排除 NULL 列**。
我方 parser 若照 SQL 直覺實作三值邏輯會與本尊不同——已登記 R11-V10。

### §2.3 `WITH` 修飾子【窮舉：11】
結果欄位類【4】：`TOTALS`（`{metric}__totals`）／`GROUP_TOTALS`（`{metric}__{dims}_totals`）／`PERCENT_CHANGE`／`CUMULATIVE_VALUES`
設定類【2】：`CURRENCY '<code>'`／`TIMEZONE '<IANA tz>'`
歸因類【5】：`FIRST_CLICK_ATTRIBUTION`（`__first_click`）／`LAST_CLICK_ATTRIBUTION`（`__last_click`）／`LAST_NON_DIRECT_CLICK_ATTRIBUTION`（`__last_non_direct_click`）／`ANY_CLICK_ATTRIBUTION`（`__any_click`）／`LINEAR_ATTRIBUTION`（`__linear`）

### §2.4 日期
- 絕對：`yyyy-MM-dd`／`yyyy-MM-ddThh:mm:ss`
- 相對位移單位【8】：`s` `min` `h` `d` `w` `m` `q` `y`
  🔴 **`min`＝分鐘、`m`＝月**（不是慣例的 `m`＝分鐘）——parser 最易錯的一點。
- 日期函式【14＝7 對】：`startOf/endOf` × `Minute·Hour·Day·Week·Month·Quarter·Year`
- 具名範圍【19】：`now` `today` `yesterday`／`this_week` `this_month` `this_quarter` `this_year`／`last_week` `last_month` `last_quarter` `last_year`／`this_weekend` `last_weekend`／`bfcm2020`–`bfcm2025`
- `COMPARE TO` 具名運算子【10】：`previous_period` `previous_year` `previous_year_match_day_of_week` `previous_quarter` `previous_month` `previous_week` `previous_day` `previous_hour` `previous_minute` `previous_second`
  生成欄位命名：`comparison_{metric}__previous_year`／`__20230101`／`__last_week`／`__startOfQuarter_sub_3q`（**負號轉 `sub`**）

### §2.5 時間維度【12】
區間型【8】：`second` `minute` `hour` `day` `week` `month` `quarter` `year`
循環型【4】：`hour_of_day`(0–23) `day_of_week`(0–6) `week_of_year`(1–53) `month_of_year`(1–12)
🔴 `GROUP BY day` **不回填空日期**；要回填必須用 `TIMESERIES`。這是兩者的唯一實質差異。

### §2.6 語法細節
- 註釋：單行 `--`；多行 `/* … */`
- 引號：**字串值一律單引號**；**含空白的別名用雙引號**
- `GROUP BY` 支援 `[ONLY] TOP n dim [OVERALL]`（其餘歸「Other」列；`ONLY` 移除 Other；`OVERALL` 全域排名）
- Metafield 引用：`{entity}.metafields.{namespace}.{key}`
- 大小寫敏感規則＝**文檔未載**（我方假設：keyword 不敏感、識別字敏感，須在 PR 標假設）

### §2.7 GraphQL API
- `shopifyqlQuery(query: String!): ShopifyqlQueryResponse`
  - `tableData { columns { name, dataType, displayName }, rows }`／`parseErrors: [String!]!`（有錯時 `tableData` 為 null）
- scope `read_reports` ＋ **Level 2 protected customer data** ＋ Admin API ≥ 2025-10
- 🔴 **`VISUALIZE`/`TYPE` 只影響編輯器圖表；API 一律只回 table data**——
  ⇒ 我方 API 契約（28 號）也應把視覺化型別歸在**前端狀態**，不進 API 回應。已登記 R11-V11。
- 官方明載「Data isn't real-time」＋ complexity-based rate limits；**具體數字文檔未載**。

### §2.8 Schema 清單【38 個／7 分類】
- Customers(1)：`customers`
- Finance and payments(8)：`chargebacks` `fees` `gift_cards` `payment_attempts` `payments` `payouts` `store_credit_summaries` `store_credit_transactions`
- Inventory(5)：`inventory` `inventory_adjustment_history` `inventory_by_location` `inventory_shipments` `inventory_transfers`
- Marketing(5)：`campaign_products` `campaign_sales` `campaign_sessions` `marketing_engagements` `shop_campaign_insights`
- Orders(3)：`fulfillments` `profitability` `shipping_labels`
- Sales revenue(5)：`discounts` `returns` `sales` `sales_taxes` `subscriptions`
- Sessions and behavior(11)：`global_searches` `low_engagement_product_recommendations` `product_recommendation_conversions` `search_conversions` `search_queries` `searches` `sessions` `shop_post_purchase_offers` `shop_product_impressions` `shopify_forms` `web_performance`
🔴 **沒有 `orders` schema、沒有 `products` schema**（產品資料以維度散在 `sales` 等）。
🔴 `customer_cohorts_{weekly|monthly|quarterly}`（實測存在）**不在這 38 個清單裡**——文檔缺漏，以實測為準。

---

## §3 指標定義與公式（層⑤，🔴 三處文檔互相矛盾，全部登記）

| 指標 | 公式 |
|---|---|
| 銷售總額 gross sales | `商品價格 × 數量`（稅／運費／折扣／撤銷**之前**）；**含** pending·canceled·unpaid；**排除** test·deleted |
| 折扣 discounts | `商品項目折扣 + 訂單層級折扣分攤`；稅前套用；**不含** compare-at 價差 |
| 銷貨淨額 net sales | `銷售總額 − 折扣 − 撤銷款項`（**不含**稅、運費、關稅、費用） |
| 總銷售額 total sales | `銷售總額 − 折扣 − 撤銷款項 + 稅 + 關稅 + 運費 + 費用` |
| 運費 shipping | `運費 − 運費折扣 − 已退運費` |
| AOV | `(銷售總額 − 折扣) / 訂單數`，**兩項皆排除 post-order adjustments** |
| 轉換率 | `完成結帳的工作階段 / 工作階段` |
| 回頭客比率 | `回頭客數 / 顧客數` |

🔴 **三個必須複製的反直覺行為**：
1. **總銷售額可以是負數**（撤銷 > 銷售的日子）。官方原文明列。
   ⇒ 我方金額欄位與 UI badge **必須允許並正確顯示負值**（tabular-nums 對齊）。已登記 R11-V12。
2. **AOV 不可由 `net_sales / orders` 推導**——分子刻意排除 post-order adjustments。
   ⇒ 這是**鐵律 7「數字同源」的官方例外**：AOV 必須有自己的 rollup 分子，不能共用 net_sales。已登記 R11-V13。
3. **`ANY_CLICK` 歸因各通路加總會超過 metric 本身**（官方註明）。
   ⇒ 任何「小計＝總計」的一致性測試必須把此模型列白名單例外。

### §3.1 🔴 「撤銷款項 sales reversals」＝ 2026 正式改名（本輪重大術語變更）
- 定義：refunds／returns／cancellations／edits 造成的**所有負值調整**，含對運費·稅·費用·折扣的調整。
- 改名理由（官方原文）：釐清「**廣義訂單調整（sales reversals）**」與「**實體退貨（returns）**」的區別。
- 時程：**2026-03-05 生效** → 2026-04 標記 deprecated → **2026-07 移除** → 舊版 API 可用至 2027-04。
- 欄位對照（11 組）：

| 舊 | 新 |
|---|---|
| `returns` | `sales_reversals` |
| `net_returns` | `net_sales_reversals` |
| `gross_returns` | `gross_sales_reversals` |
| `total_returns` | `total_sales_reversals` |
| `discounts_returned` | `discount_reversals` |
| `shipping_returned` | `shipping_reversals` |
| `taxes_returned` | `tax_reversals` |
| `quantity_returned` | `reversed_quantity` |
| `returned_quantity_rate` | `reversed_quantity_rate` |
| `is_return_related` | `is_reversal` |
| `order_or_return` | `order_or_sales_reversal` |

- 🔴 `sales_reversals` **本身的加總公式＝文檔未載**（只給列舉式定義）。
- ⇒ 我方 19 號 rollup 與 76 號訂單線的「退款/退貨」欄名必須改用**撤銷款項語義**，
  且**保留 `returns` 作為「實體退貨」的獨立概念**（兩者不可合併）。已登記 R11-V14。

### §3.2 歸因模型【5，官方；實測 UI 只見 4】
| 模型 | 定義 | 直接流量 |
|---|---|---|
| 首次點擊 | 100% 給第一個互動管道 | **含** |
| 最後點擊 | 100% 給最後一個互動管道 | **含** |
| 最後非直接點擊 | 100% 給購買前最後一個非直接管道 | **排除** |
| 線性 | 平均分給旅程中每次點擊 | **含** |
| **任一點擊 any click** | 100% 給**每個**被點擊的管道 | — |
- 🔴 **實測指標清單只有 4 種前綴，官方文檔有 5 種**（多 `ANY_CLICK`）。實作 spec 應涵蓋 5 種。
- **預設模型：兩處文檔互相矛盾**——marketing activity 頁說預設 `last non-direct click`，
  一般報告頁說 `last click`。**判定未決**，登記 R11-DOC3。
- 歸因視窗：官方唯一數字是「**session 後 30 天內未購買則 first interaction referrer 重置**」；
  各模型視窗長度＝文檔未載。歸因資料起算日 **2021-10-01**。

### §3.3 資料保留與起算日（平台級，與方案無關）
| 類 | 起算日 |
|---|---|
| Sessions-based 指標（14 個，含 轉換率·跳出率·工作階段） | **2022-10-01** |
| Inventory-based 指標 | **2023-10-01** |
| Attribution（成長區） | **2021-10-01** |
- 更新頻率：總覽頁「約 1 分鐘內」；自動重新整理每 **60 秒**（僅當期間**含今天**時生效）。
- 🔴 **各方案的保留期限差異＝文檔未載**。

---

## §4 報告清單頁與實況瀏覽（實測）

### §4.1 `/analytics/reports`
- 版面：`報告` 標題 ＋ 右上 **「新增探索」** 主按鈕（🔴 不是「建立自訂報告」）
- 搜尋列「搜尋報告」＋ 右側**排序**圖示鈕
- **篩選【2】**：建立者／類別（🔴 **沒有 tab 家族**——我方原型自創了 4 個 tab，已登記 R11-V15）
- **欄【4】**：名稱／類別／上次檢視時間（預設排序，可切）／建立者（值：`Shopify` 或員工名）
- 分頁：`1-50` ＋ 前/後箭頭
- **類別值域【實測窮舉 13】**：利潤率／商店／庫存／成效／獲客／行為／行銷／訂單／詐騙／財務／銷售／零售銷售／顧客
  ⚠️ help 英文版列 11 類（Acquisition·Behavior·Customers·Finance·Fraud·Inventory·Marketing·Order·Profit·Retail sales·Sales），
  **實測多出「商店」與「成效」**。以實測為準（R11-DOC4）。
- 硬上限（help）：**表格最多顯示 1,000 列**（但**總計反映全部資料**）；
  **報告頁一次最多顯示 250 份自訂報告**（可建更多，需自存 URL）。
- 報告 slug 實測 33 個，含 `total_sales_reversals_by_order`（2026 術語已進 slug）、`customer_cohort_analysis`、`pos_staff_sales_total`、`conversion_rate_breakdown`。

### §4.2 具名報告的動作選單【窮舉：4】
`⋯` → 重新命名／匯出／列印／刪除
- **重新命名**：彈窗「重新命名」＋單行輸入（帶現值）＋取消／儲存。🔴 **預設 Shopify 報告不可改名**。
- **匯出**：彈窗「匯出報告 ⓘ」，兩組單選——
  - **格式【4】**：逗號分隔值 (CSV)〔說明「最適合匯入試算表」，預設〕／可延伸標記語言 (XML)／JSON Lines (JSONL)／**Apache Parquet**
  - **範圍【2】**：資料查詢的所有結果〔說明「可能超過 1,000 列」，預設〕／僅限報表中顯示的結果
  - ⇒ 🔴 我方原型只有一顆「匯出」toast，缺整個彈窗與 4 種格式。已登記 R11-V16。
- **刪除**：彈窗「刪除報告？」／內文「此動作無法復原」／取消 ＋ **紅色破壞性「刪除」**；
  刪除後**導回 `/analytics/reports`**（實測）。

### §4.3 儲存流程（實測全鏈）
1. 未儲存態標題＝「新探索」，頂欄無儲存列
2. 任何改動 → 頂欄出現 **⚠ 未儲存的變更｜捨棄｜儲存**（編輯已儲存報告時為 **捨棄｜另存新檔｜儲存**）
3. 點儲存 → 彈窗「儲存報告」，**預設名自動生成 `{指標} (依 {維度})`**（實測「訂單數 (依 日)」）＋ 取消／儲存
4. 儲存後 URL 由 `/explore` 變 `/reports/{numeric_id}`，標題換成報告名，`?ql=` 保留
🔴 **自動命名規則 `{指標} (依 {維度})` 必須照抄**——這是使用者不改名時的預設值。已登記 R11-DOC5。

### §4.4 AI 提示列（實測，本輪意外收穫）
- 未查詢態：整行輸入框「您想探索哪些資料？」＋ 右側展開 chevron
- 送出後：**列位下移成「調整搜尋範圍」**（追問列），主欄換成 QL 編輯器＋圖表
- 實測輸入「訂單數」→ 生成：
```sql
FROM sales
  SHOW orders
  TIMESERIES day
  SINCE 2000-01-01 UNTIL today
VISUALIZE orders
```
  並自動附一行自然語言說明「每日訂單量趨勢，用於掌握長期需求波動與成長幅度。」
  同時把期間 chip 設為 `2000年1月1日–2026年8月14日`、右側槽位填好 指標=訂單數／維度=日／視覺化=曲線。
- ⇒ AI 產出的是 **QL ＋ 說明文字 ＋ quick filter 狀態**三件套，不只是查詢字串。已登記 R11-V17。

### §4.5 QL 編輯器工具列【窮舉：6 鈕＋1 狀態】
狀態指示：● **查詢語法正確**（綠點；語法錯時應為錯誤態，本輪未觸發）
鈕：⌨ 鍵盤快捷鍵／? 說明／↶ 復原／↷ 重做／▷ 執行／^ 摺疊編輯器
（行號 gutter；關鍵字著色：`FROM`/`SHOW`/`TIMESERIES`/`SINCE`/`UNTIL`/`VISUALIZE` 深藍粗、字串值紫、識別字黑）

### §4.6 `/analytics/live`（實況瀏覽）
- 標題列：`⊙ 實況瀏覽` ＋ **● 剛剛**（更新時戳，藍點）；a11y live region 播報「實況瀏覽。頁面已載入完成」
- 圖例【2】：● 訂單（紫）／● 目前訪客（藍）
- 控件：`搜尋地點` 輸入框 ＋ 右側 **地圖/地球儀切換**圖示鈕
- **幣別 chip 預設 `USD $`**（🔴 與報告頁的 `HKD HK$` 不同源——同一店兩頁兩個預設幣別。已登記 R11-DOC6）
- **卡片【窮舉：8】**：即時訪客／總銷售額／工作階段（含 sparkline ＋ 變化率 `↘100%`）／訂單／
  **顧客行為**（三欄：活躍購物車｜結帳中｜已購買）／依地點分列的工作階段／新客與回頭客／依商品的總銷售額
- 空態文案：**「此日期範圍無資料」**
- 口徑（help）：即時訪客＝**近 5 分鐘**；工作階段/訂單＝**店鋪當地時區午夜起**；顧客行為窗＝**10 分鐘**；
  總銷售額＝`銷售總額 − 折扣 − 撤銷 + 運費 + 稅`（🔴 **少了關稅與費用**，與報告頁的總銷售額公式不同——
  第三個版本，已登記 R11-DOC7）
- 地圖已知特性：無法定位的美國訪客落在**美國地理中心（Kansas）**；Streamer mode 可隱藏數字。

---

## §5 CSS 三段式（層④）

| # | 部位 | 本尊量測（實測） | 我方 token 映射（23 號） |
|---|---|---|---|
| 1 | 快速篩選 chip | 高 32px、圓角 8px、邊框 1px `#E3E3E3`、內距 8/12、圖示 16px＋間距 6px、字 13px/500 | `--h-chip:32px` `--r-200` `--bd` `--sp-200/--sp-300` `--fs-100` |
| 2 | 控制面板槽位卡 | 卡寬 226px、圓角 12px、標題列高 40px、標題 13px/600、項目列高 36px、`+` 鈕 20px | `--r-300` `--h-row-sm:36px` `--fs-100` `--fw-600` |
| 3 | 抽屜選單 | 寬 264px、最大高 320px（內捲）、搜尋框高 36px、選項列高 36px、checkbox 16px、左圖示 16px＋12px 間距 | `--w-menu:264px` `--h-row-sm` `--sp-300` |
| 4 | 選單說明浮卡 | 寬 220px、縮圖 168×96、內距 16px、標題 13px/600、正文 12px/1.5 `#616161` | `--fg-subdued` `--fs-75` `--lh-150` |
| 5 | QL 編輯器 | 行高 18px、字 13px 等寬、gutter 寬 24px 右對齊 `#8A8A8A`、狀態列高 40px、工具列圖示 20px/間距 4px | `--font-mono` `--fs-100` `--lh-140` |
| 6 | 圖表卡 | 卡內距 20px、標題 13px/600、軸標籤 11px `#616161`、格線 1px `#ECECEF`、曲線 2px | `--sp-500` `--fs-75` `--bd-subdued` |
| 7 | 資料表 | 列高 36px、表頭 40px/600、右對齊數值 tabular-nums、分隔線 1px | `--h-row` `--num-tabular` |
| 8 | 破壞性彈窗 | 寬 620px、標題 16px/600、內文 14px、按鈕列高 64px、刪除鈕背景 `#E51C00` | `--w-modal-md` `--bg-critical` |
🔴 只做**映射**，實作一律用我方 token（鐵律 8/9），不得取用本尊色值。

> 🔴 **2026-08-28 起本段的處置已被 `docs/DECISIONS.md` **D54** 推翻**（使用者裁定「整體 UI 必須和 Shopify 完全 1:1，完全跟隨他的 CSS」）。
> **原文保留備查**（文檔分層：不抹除歷史）。現行處置＝採用量測色值，本尊完整 token 值表見 `docs/design/111`，逐項差異見 `docs/design/110` §7。


---

## §6 兩棵文檔樹的矛盾點（層⑤ critic 結論，全部登記為待判）

| # | 主題 | help.shopify.com | shopify.dev | 實測 | 處置 |
|---|---|---|---|---|---|
| 1 | 方案分層 | 「所有方案皆可用主要功能」 | — | Plus 店（無法驗證分層） | 🔴 Advanced 方案頁另說 custom reports 需 Advanced ⇒ **矛盾**，R11-DOC8 |
| 2 | Total sales 公式 | 兩處等價（含關稅+費用） | — | — | Live View 頁**少關稅與費用** ⇒ 三版本，R11-DOC7 |
| 3 | 歸因預設 | marketing 頁：last non-direct｜報告頁：last click | — | 未觸發 | 矛盾，R11-DOC3 |
| 4 | `app_events` schema | 有記載 | **不在 38 個清單** | 未測 | 以 38 清單為準，R11-DOC9 |
| 5 | 比較基準值域 | 上一期間/去年/自訂/不比較 | `COMPARE TO TARGETS` | 不進行比較/前一期間/自訂/**目標** | 以實測為準，R11-DOC2 |
| 6 | 報告類別數 | 11 | — | **13** | 以實測為準，R11-DOC4 |
| 7 | 視覺化型別數 | — | 23 | **27**＋cohort 2 | 三份不等，R11-V2 |
| 8 | `WITH CURRENTLY_UNAVAILABLE` | 無記載 | 無記載 | 未見 | 我方**不得**自創此修飾子 |

**文檔未載清單（21 項）**：`WITH CURRENTLY_UNAVAILABLE`／大小寫敏感規則／`LIMIT` 最大值與 `OFFSET` 語法／
`HAVING` 支援的彙總函式／`ANNOTATE` 合法參數／`shopifyqlQuery` rate limit·最大列數·timeout·分頁·快取／
`MONEY` 序列化格式／`sales` schema 起算日／總覽頁方案與權限／逐方案功能對照表／`sales_reversals` 加總公式／
五種歸因各自視窗／歸因預設模型／Live View 刷新間隔／Live View 方案要求／逐方案保留期限／
自訂報告對外分享機制／「不可篩選·編輯·複製」的報告清單／11 分類下的個別報告名／`customer_cohorts_*` schema 文檔。

---

## §7 對我方的裁定面（→ 71 §F）

1. **R11-V1 探索器結構**：QL 編輯器**常駐**非彈窗模式；三向同步（QL ⇄ 槽位 ⇄ `?ql=`）。**M2 前必答**：
   我方是否也把查詢字串當第一等狀態（影響路由設計、分享連結、報告儲存格式）。
2. **R11-V2 視覺化型別分池**：freeform 27 / cohort 2 / API `TYPE` 23，**三份不等** ⇒ 建模時
   `visualization_type` 必須帶 `mode` 維度，不可單表。
3. **R11-V3 維度 vs 篩選可用性不同源** ⇒ 不可共用 `available_fields`。
4. **R11-V4 Web Vitals 40 個指標**未在我方 19 號 rollup 規格中 ⇒ 補或明確裁定不做。
5. **R11-V5 付款幣別金額是獨立欄** ⇒ 佐證鐵律 3；我方 rollup 需同時存店幣與付款幣別兩欄。
6. **R11-V9 `WITH CURRENCY` ≠ 單位宣告** ⇒ 鐵律 3 四型別**維持不變**，不得因 Shopify 的 `MONEY` 放寬。
7. **R11-V12 總銷售額可為負** ⇒ UI 金額元件與 badge 必須支援負值。
8. **R11-V13 AOV 是鐵律 7 的官方例外** ⇒ 需在鐵律 7 條文加註例外，否則實作會「同源」到錯。
9. **R11-V14 撤銷款項術語** ⇒ 19/76 號欄名改造（11 組對照），且保留 `returns`＝實體退貨。
10. **R11-V6 推出維度** ⇒ R10 的 rollouts 必須輸出 `rollout_id` / `rollout_variant_id` 到分析層。
