# 14. 分析與報表（Metrics 正典 / 歸因 / 報表）

> 考掘日 2026-08-14。雙源：shopify.dev（ShopifyQL／Admin GraphQL）＋ help.shopify.com（報表手冊）。
> 倉庫對照：`docs/research/80`（R11 實測 teardown）、`docs/research/72`（首頁指標）、`docs/specs/19`（分析規格）、`docs/specs/86`（撤銷款項）。
> 本章定位：**業務邏輯正典**——指標恆等式、歸因語義、報表資料時效與狀態機，可直接落地開發。
> 凡「取證 2026-08-14」＝當日自官方文檔查證；⚠️＝官方文檔查不到或互相矛盾，已入 openQuestions，不得當事實實作。

---

## A. 領域物件模型

### A.1 核心物件

| 物件 | 關鍵欄位 | 說明 |
|---|---|---|
| `MetricDefinition`（指標正典） | name／formula／unit_kind(`money`,`count`,`rate`,`duration`)／dataset／date_attribution(`order_date`,`processing_date`)／attribution_variants | 指標辭典的一列。金額類指標必須標注「計入哪一天」（見 C.2）。歸因類指標是「基底指標 × 5 模型前綴」的展開（見 C.7） |
| `Dataset`（ShopifyQL schema） | name／metrics[]／dimensions[]／earliest_date | 本尊 38 個具名 schema（7 分類）＋實測另有 `customer_cohorts_{weekly\|monthly\|quarterly}`（不在官方清單，⚠️）。**沒有 `orders`／`products` schema**——商品與訂單資料以維度散在 `sales` 等。全清單＝80 §2.8 |
| `Report`（具名報告） | id／name／category／ql（ShopifyQL 全文）／creator(`Shopify`\|員工)／last_viewed_at | 具名報告＝ `(id, 預設 ql)`；URL `?ql=` 可臨時覆寫不影響儲存值（80 §0.1）。預設（Shopify 建）報告**不可改名**；類別實測 13 種（80 §4.1） |
| `Exploration`（未儲存探索） | ql（唯一狀態，編碼於 URL） | 探索器＝ShopifyQL 編輯器；QL 文字 ⇄ 右側槽位 ⇄ URL `?ql=` 三向投影（80 §0.2） |
| `SalesFactLine`（銷售事實列） | order_id／line_item_id／kind(`sale`\|`reversal`)／occurred_on／gross・discount・tax・duty・shipping・fee・**cost** 各分量＋`cost_recorded` 旗標 | 報表的最小事實粒度。`sale` 記**成立日**、`reversal` 記**處理日**（C.2）。`cost`＝售出當下 `InventoryItem.unitCost` **快照**（C.13；NULL＝售時未填 ≠ 0＝真實零成本）。「銷售報表不追蹤金流」——金流歸 finance reports 的 payments 面 |
| `Session` | token／started_at／ended_at／has_cart_add・reached_checkout・completed_checkout 旗標 | cookie 為基礎；30 分鐘無活動或 **UTC 午夜**即終止；未同意 cookie／ad blocker／bot 不計入（C.5） |
| `AttributionCredit` | session↔order 關聯 × channel × model | **查詢時計算，不落庫為單一模型**——同一筆訂單在 5 種模型下歸屬不同；ShopifyQL 以 `WITH *_ATTRIBUTION` 修飾子展開 `__first_click` 等欄（C.7） |
| `Rollup / 時效層` | dataset × freshness_class | 本尊無單一「rollup 表」概念，但有明確的**分層時效**（C.9 資料時效表），實作對應我方 19 §F2 兩層架構 |
| `LiveView` | 即時面 | 與報表分離的即時介面：5 分鐘活躍窗＋10 分鐘行為窗＋店鋪當地時區午夜重置（C.10） |
| `DashboardCard`（總覽卡片） | metric／per-user 佈局 | 總覽面板卡片可自訂；首頁另有 4 槽 × 16 指標池、**per-user**（72 §1） |

### A.2 關係與 cardinality

```
Shop 1 ── N Report（自訂報告清單頁一次最多顯示 250 份）
Report 1 ── 1 ql（查詢全文即報告本體；視覺化型別是 ql 的一部分，但 API 不回圖，只回表）
Order 1 ── N SalesFactLine（成立時 N 筆 sale；每次退款/取消/編輯/退貨產生 N 筆 reversal）
Customer 1 ── N Session；Session 0..N ── Order（一個 session 可含多筆訂單 ⇒ 完成結帳 sessions ≠ 訂單數）
Order N ── M Channel（經 AttributionCredit；ANY_CLICK 下 M ≥ 1 且加總＞訂單數，官方設計）
Cohort（首購期間）1 ── N Customer；Customer 恆屬且僅屬 1 個 cohort（依首筆訂單日期）
```

---

## B. 狀態機

### B.1 報告生命週期（實測 80 §4.3 ＋ help）

狀態全集：`exploring_unsaved`（新探索）／`saved_clean`（已儲存·無變更）／`saved_dirty`（已儲存·未儲存變更）／`deleted`。

| 現態 | 觸發 | 前置條件 | 次態 | 副作用 |
|---|---|---|---|---|
| exploring_unsaved | 任何查詢改動 | — | exploring_unsaved | 頂欄出現「⚠ 未儲存的變更｜捨棄｜儲存」；`?ql=` 即時更新 |
| exploring_unsaved | 儲存 | 需 Advanced/Plus 方案 ⚠️（見 G 註） | saved_clean | 彈窗預設名 `{指標} (依 {維度})`；URL `/explore` → `/reports/{id}` |
| exploring_unsaved | 捨棄 | — | （回到空探索） | 查詢清空 |
| saved_clean | 改動查詢 | — | saved_dirty | 頂欄變「捨棄｜另存新檔｜儲存」（多一顆另存新檔） |
| saved_dirty | 儲存 | 非 Shopify 預設報告 | saved_clean | 覆寫 ql |
| saved_dirty | 另存新檔 | — | saved_clean（新 id） | 原報告不動 |
| saved_dirty | 捨棄 | — | saved_clean | 回存檔值 |
| saved_clean | 重新命名 | **非 Shopify 預設報告**（預設報告不可改名） | saved_clean | 僅改 name |
| saved_clean | 刪除 | 確認彈窗「此動作無法復原」 | deleted（終態） | 導回 `/analytics/reports` |
| exploring_unsaved | 切換 自由形式⇄組別 tab | — | exploring_unsaved | 🔴 **查詢清空**（`?ql=` 變空）——切模式＝放棄現有查詢（80 §0.3） |

無孤兒態：`deleted` 為唯一終態；所有狀態可經「捨棄」回到穩定態。

### B.2 撤銷欄位改名生命週期（returns → sales_reversals；取證 2026-08-14）

改名理由：舊名 `returns` 實際涵蓋 refunds／returns／order edits／cancellations 全部負向調整，與「實體退貨」混淆。新名把兩概念拆開：**`sales_reversals`＝廣義訂單調整**、**`quantity_returned`／`return line item reason`＝僅實體退回品項**。

| 階段 | 時點 | 狀態 |
|---|---|---|
| 公告 | 2026-03-13（changelog） | 新舊欄名**並存顯示**於銷售報表 |
| UI 下架舊名 | **2026-05-01** | 報表介面僅剩 reversals 系欄名 |
| API deprecated | GraphQL Admin API **2026-04** 版 | ShopifyQL 舊欄位標記棄用 |
| API 移除 | **2026-07** 版 | 舊欄位自新版移除 |
| 舊版可用迄 | **2027-04** | 釘住舊 API 版本仍可查舊欄名 |

11 組新舊欄名對照＝80 §3.1（`returns→sales_reversals`、`quantity_returned→reversed_quantity` 等），已驗證與 changelog 一致。我方裁定：**一步到位只用撤銷系命名，不做雙軌**（72 §2 註）。

### B.3 Session 與漏斗旗標

Session 狀態：`active` → `ended`（30 分鐘無活動 或 UTC 午夜，二者先到者）。終止後同訪客新活動＝新 session。
漏斗不是狀態機而是**單調旗標集**：`has_cart_add`／`reached_checkout`／`completed_checkout` 只會 false→true，不回退；各階段口徑見 C.5。

### B.4 退款在報表中的顯示過渡 ⚠️

sales-discrepancies 頁記載：待處理（pending）退款先以**正值**顯示，處理完成後轉為**負值**；退款與補貨落在不同日期時金額會呈現重複。精確欄位語義官方未展開——實作對帳測試時須覆蓋「pending→processed 跨日」情境，但不得自行腦補中間態規則（openQuestions）。

---

## C. 業務規則與不變量

### C.1 銷售指標恆等式（正典；取證 2026-08-14，sales-report＋analytics-fields）

```
gross_sales  = Σ (商品單價 × 數量)          -- 稅、運費、折扣、撤銷之前
discounts    = Σ (商品項目折扣 + 訂單層級折扣分攤)   -- 稅前套用
net_sales    = gross_sales − discounts − sales_reversals
shipping     = 運費 − 運費折扣 − 已退運費
total_sales  = gross_sales − discounts − sales_reversals + taxes + duties + shipping + fees
             = net_sales + taxes + duties + shipping + fees      -- 兩式官方皆載，等價
```

- `sales_reversals`＝refunds／returns／cancellations／order edits 造成的**全部負向調整**（含對運費·稅·費用·折扣的調整）。🔴 其**加總公式官方未載**（僅列舉式定義）——我方拆解＝86 §3.2（三項互斥），屬我方補完，須標注非官方。
- 🔴 **total_sales 可為負**（當日撤銷 > 銷售）。一致性測試不得假設非負。
- 🔴 **Live View 的 total_sales 是另一個公式**：`gross − discounts − reversals + shipping + taxes`——**少 duties 與 fees**（取證 2026-08-14，live-view 頁）。與報表版本並存＝本尊自身不同源（R11-DOC7）。

**計入範圍**（sales-report，取證 2026-08-14）：

| 計入 | 排除 |
|---|---|
| pending／canceled／unpaid 訂單 | test 訂單、已刪除訂單 |
| draft 轉正式的訂單 | 禮品卡**作為商品賣出**（記入負債與 `Net sales from gift cards`，不進銷售） |
| 以禮品卡**支付**的訂單（商品全額計入銷售） | 小費（tips 在 finance reports 的 `Tips by staff member`／`Tips over time`，不進 total_sales） |

### C.2 日期歸屬（date attribution）

- 銷售：**成立日**記正值。撤銷：**處理日**記負值。官方原句意譯：銷售以成立當天為正值、撤銷以處理當天為負值顯示。
- 🔴 訂單成立後編輯 → 該編輯在 `Total sales over time` **顯示為一筆獨立訂單**（幽靈訂單；官方行為）。我方裁定不復刻（F 節差異 #1）。
- 推論不變量：`AOV × Orders ≠ Total sales`（編輯/退款存在時本來就不等，測試不得斷言相等）。

### C.3 AOV（官方分子已驗證）

```
AOV = (gross_sales − discounts) / orders        -- 分子分母皆排除 post-order adjustments
```
- sales-report 頁原式：gross sales（excluding adjustments）− discounts（excluding adjustments）除以訂單數；analytics-fields 頁同式。兩源一致（取證 2026-08-14）。
- 🔴 因此 `AOV ≠ net_sales / orders`（net_sales 含撤銷）也 `≠ total_sales / orders`——鐵律 7「數字同源」的官方具名例外（已登記 §A G25）。

### C.4 顧客指標

| 指標 | 公式／定義 | 出處 |
|---|---|---|
| returning customer rate | `回頭客 ÷ 下單顧客` | analytics-fields |
| 回頭客 | 訂單史**含 2 筆以上訂單**（生涯口徑，非期間口徑） | customers-reports |
| 新顧客 | 首筆訂單在本店的顧客 | customers-reports |
| 一次性顧客 | 訂單史恰 1 筆 | customers-reports |
| cohort 歸屬 | 依**首筆訂單日期**分組（週/月/季）；顧客恆屬唯一 cohort | customers-reports |
| cohort 回購計數 | 例：2 月首購、同月再購＋6 月＋9 月再購 ⇒ 計入 Month 0、Month 4、Month 7（**Month 0 含同期回購**） | customers-reports |
| retention rate | 期間 N 有回購的 cohort 顧客 ÷ cohort 人數（實測欄 `customers_in_cohort`、`customer_retention_rate`；官方無獨立公式頁 ⚠️） | 80 §1.8 |
| RFM | R·F·M 各 1–5 分，**11 組**；Champions＝R5 且 F/M>3；Prospects＝尚無訂單 | customers-reports |
| 顧客報表時效 | 可能**不含過去 12 小時**活動；「新客與回頭客」開啟時即刻更新 | customers-reports |

Cohort 查詢定式（實測）：取 `BETWEEN -1 AND 11` 再 `HAVING >= 0` 濾掉第 -1 期——為讓 `_totals` 欄算出完整基期，**不可簡化**成 `BETWEEN 0 AND 11`（80 §1.8）。

### C.5 轉換漏斗（取證 2026-08-14，behaviour-reports＋analytics-updates）

四階段（Conversion rate breakdown）：`所有 sessions` → `有加入購物車的 sessions` → `到達結帳的 sessions` → `完成結帳的 sessions`。

- 🔴 **各階段轉換率的分母一律是總 sessions**（`該階段 sessions ÷ 總 sessions`），不是逐級相除。
- `conversion_rate = 完成結帳的 sessions ÷ sessions`。
- **到達結帳（2024-10 新法）**：checkout **開始載入**即計（含 storefront cart／checkout permalink／分享結帳 URL／cart·checkout API 各入口）；**排除** draft order invoice、order edit invoice、exchanges、POS、未同意 cookie、ad blocker。舊法（需在結帳內有輸入動作）已廢；新法**回填至 2022-10** 作基線。
- 完成結帳＝該 session 有購買；**一個 session 可含多筆訂單** ⇒ 完成結帳 sessions ≠ 訂單數。
- Session 定義：30 分鐘無活動或 **UTC 午夜**終止；bot 濾除；未同意 cookie 不計（分母內建偏低）。

### C.6 庫存指標（取證 2026-08-14，inventory-reports）

```
sell_through_rate    = 售出數量 ÷ (售出數量 + 期末庫存數量)        -- 期末量為負時以 0 計
days_of_inventory    = 期末庫存數量 ÷ 日均售出數量
日均售出數量          = 過去 28 天售出數量 ÷ 28                    -- 🔴 固定 28 天窗，不可自訂
percent_sold         = 期間售出數量 ÷ 期初數量 × 100
```
- days_of_inventory 邊界：期間內零銷售 ⇒ **N/A**（不足以預測）；期末量為負 ⇒ **0**。圖表分桶：0／0–30／…／91+ 天。
- ABC 分級（過去 28 天營收貢獻，**每日更新**）：A＝前 80%、B＝次 15%、C＝末 5%。
- 排除：committed（待出貨）、調撥在途、未追蹤庫存商品（禮品卡、數位商品）。
- 庫存類指標資料起算 **2023-10-01**；處理延遲約 **2 天**（UTC+14 等早時區最多 3 天）。

### C.7 歸因（取證 2026-08-14，marketing-performance＋marketing-reports）

**模型全集【5】**（ShopifyQL `WITH` 修飾子 → 欄位後綴）：

| 模型 | 定義 | 直接流量 | 後綴 |
|---|---|---|---|
| First click | 100% 給旅程第一個互動管道 | 含 | `__first_click` |
| Last click | 100% 給最後一個互動管道 | 含 | `__last_click` |
| Last non-direct click | 100% 給購買前最後一個**非直接**管道 | 排除 | `__last_non_direct_click` |
| Linear | 平均分給旅程中每次點擊 | 含 | `__linear` |
| Any click | 100% 給**每一個**被點擊的管道 | — | `__any_click` |

- 🔴 **預設值依介面而異，R11-DOC3 就此解決**：報告內歸因選單（當查詢同時含銷售指標＋行銷維度時出現）預設 **Last click**；行銷／Growth 頁預設 **Last non-direct click**。兩處文檔並非矛盾，是**兩個面各自的預設**。
- 🔴 **Any click 加總＞訂單總數是官方設計**（分派的 credit 多於實收訂單），官方建議只用於單一管道分析 ⇒ 任何「小計＝總計」檢查必須把 any_click 列白名單。
- 視窗：唯一官方數字＝**30 天**——session 後 30 天內未購買則 first interaction referrer 重置。各模型的完整 lookback 長度官方未載 ⚠️。
- 歸因資料起算 **2021-10-01**；跨裝置歸因自 **2023-03-01** 起納入全部 storefront 資料。
- 管道判定：referrer source（Direct／Search／Email／Social／Unknown）＋ referrer name（Google／Facebook…）；帶 `utm_campaign` 的流量自動歸為行銷歸因流量。
- 歸因分派的是 **credit（訂單歸屬）**，不是拆分營收比例（linear 亦然——官方未載金額拆分規則 ⚠️）。

### C.8 報表幣別與時區

**幣別**：
- 總覽面板預設**店幣**，可經幣別選單改看其他幣別；換算採**交易當日歷史匯率**逐筆計，非期末單一匯率（取證 2026-08-14，overview-dashboard）。
- ShopifyQL `WITH CURRENCY '<code>'`＝顯示／換算幣別宣告。🔴 **不是單位宣告**——`MONEY` dataType 的序列化格式官方未載 ⚠️ ⇒ 不得把它當我方單位契約參照（鐵律 3 照舊，R11-V9）。
- 報表層「店幣金額」與「付款幣別金額」是**兩個獨立指標欄**（`支付款項金額` vs `支付款項金額（付款貨幣）`），佐證雙欄落庫（R11-V5）。

**時區（多鐘並存，本尊如此）**：
| 面 | 時鐘 |
|---|---|
| Session 切日 | **UTC 午夜** |
| Live View 當日重置 | **店鋪當地時區午夜** |
| ShopifyQL `WITH TIMEZONE '<IANA>'` | 指定顯示時區；未指定時預設 shop 時區（⚠️ 另一處對「相對日期引數」寫預設 UTC——兩說並存，openQuestions） |
| 報表整體使用的時區 | 🔴 sales-discrepancies 頁**明確未指明**；無單一官方明文 ⚠️ |

我方裁定：一切按日聚合統一 shop 時區（19 §F1），與本尊差異列 F 節 #5。

### C.9 資料時效表（rollup 更新頻率；取證 2026-08-14）

| 資料面 | 時效 |
|---|---|
| 總覽面板開啟時 | 最新至**約 1 分鐘**內 |
| 自動重新整理 | **每 60 秒**；🔴 僅當所選期間**含今天**時可開啟 |
| 銷售類報表 | 約 1 分鐘 |
| Sessions 類報表 | **數秒**內 |
| 顧客類報表 | 可能缺過去 **12 小時**（「新客與回頭客」例外：開啟即最新） |
| 庫存類報表 | 約 **2 天**（早時區至 3 天）；ABC 每日更新 |
| 搜尋／推薦類報表 | 延遲最多 **72 小時** |
| Live View | 即時（5 分鐘活躍窗／10 分鐘行為窗）；整體刷新頻率官方未載 ⚠️ |
| shopifyqlQuery API | 官方明載「資料非即時」；rate limit 依查詢複雜度，超限回 **429**、**60 秒**計時器重置（具體額度未載 ⚠️） |

**比較期規則**：新版分析一律 **like-for-like**——「本月至今」類範圍與比較期比**相同已經過時長**，百分比變化不與整月比（取證 2026-08-14，analytics-updates）。我方比較期實作必須同款，否則月中數字必然對不上。

**資料起算日**（平台級）：sessions 類 2022-10-01／庫存類 2023-10-01／歸因 2021-10-01。

### C.10 Live View 口徑（取證 2026-08-14）

- 即時訪客＝過去 **5 分鐘**內活躍。顧客行為卡（活躍購物車｜結帳中｜已購買）＝**10 分鐘**窗；「結帳中」＝進結帳**且已提交聯絡資訊**。
- 當日指標（銷售/工作階段/訂單/地點/商品）自**店鋪當地時區午夜**起算。
- 地圖：藍點＝近期 sessions、紫點＝訂單；IP 無法定位者落 **38°N 97°W**（美國地理中心，Kansas）。Streamer mode 隱藏數字（行動版無）。

### C.11 上限值（一律入 `config/limits.yml` 引用）

| 上限 | 值 | 出處 |
|---|---|---|
| 報表表格顯示列數 | **1,000**（總計仍反映全部資料） | help（80 §4.1） |
| 自訂報告清單一次顯示 | **250** 份（可建更多，需自存 URL） | help（80 §4.1） |
| 匯出格式 | 4：CSV／XML／JSONL／Parquet；範圍 2：全部結果／僅顯示結果 | 實測 80 §4.2 |
| ShopifyQL 分頁「報告」清單 | 每頁 50 | 實測 80 §4.1 |
| shopifyqlQuery 需求 | scope `read_reports` ＋ protected customer data **Level 2** ＋ API ≥ 2025-10 | shopify.dev |
| 每查詢 FROM | 1 個（可 `FROM a, b` join、`FROM ORGANIZATION` 跨店=Plus/Enterprise） | shopify.dev（80 §2.1） |

### C.12 ShopifyQL 併發／解析要害（全文＝80 §2，此處僅列會寫錯的）

- `!=`／`NOT IN`／`NOT CONTAINS` **不排除 NULL 列**（官方明列陷阱）——parser 不得照 SQL 三值邏輯直覺。
- 相對位移 `min`＝分鐘、`m`＝月。
- `GROUP BY day` 不回填空日期；要回填用 `TIMESERIES`。
- `VISUALIZE`/`TYPE` 只影響編輯器；**API 一律只回 tableData**；語法錯誤時 `parseErrors: [String!]!` 有值、`tableData` 為 null。
- 產品維度預設**當前** title/SKU/vendor；貼近歷史須用 `Product title at time of sale` 獨立維度（快照名＋當前名雙軌落庫，R11-V7）。

### C.13 利潤指標族（gross profit／COGS；取證 2026-08-14，profit-reports＋analytics-fields＋finances-report）

**報告全集【5】**（profit-reports 頁）：`Average profit margin by market`／`Gross profit by product`／`Gross profit by product variant`／`Gross profit by POS location`／`Profit margin by order`。

**恆等式**（analytics-fields：gross profit＝net sales − COGS、gross margin＝gross profit ÷ net sales；profit-reports 原式 `((net sales − cost) / net sales) × 100`，兩源一致）：

```
cost_of_goods_sold = Σ (售出單位數 × 售出當下 cost per item 快照)     -- 僅計 cost_recorded=true 的事實列
gross_profit       = net_sales_with_cost_recorded − cost_of_goods_sold
gross_margin       = gross_profit ÷ net_sales_with_cost_recorded × 100
net_sales_without_cost_recorded + net_sales_with_cost_recorded = net_sales
                     -- 🔴 分桶恆等式「僅對 product line types 成立」（finances-report 原句）；
                     --    含運費/禮品卡等非商品列時不得斷言
```

- 🔴 **成本快照鐵則（官方明文）**：利潤只對「售出當下已填 cost」的品項計算（profit-reports：profit is reported only for products/variants that had cost recorded **at the time they were sold**）。售時未填成本 ⇒ 該筆 net sales 落 `without_cost_recorded` 桶，**排除**於 COGS 與 gross profit——**不是以 0 計**；因此 sales 報表與 profit 報表的 net sales **本來就可以不等**（官方明言 discrepancy，profit-reports）。
- 🔴 **事後補填/修改 cost per item 不回溯**：with/without 分桶依「at the time of the sale」判定（finances-report 原句），售時無成本的訂單**事後補填也永遠留在 without 桶** ⇒ 快照時點＝**T1（訂單成立）**：unitCost 當下凍結進訂單行／outbox payload，事實列生成（事件展開）**只讀該快照**——展開時讀現值會在事件滯留期間染到後改的成本 <!-- 2026-08-17 更正（PR #52 第 6 輪） -->，之後改 cost 只影響新銷售。⚠️「售時**有**成本、事後**改**成本」對歷史列的精確行為官方未逐字明文——我方裁定快照後不動（與快照語義一致），待實測本尊驗證。
- 折扣與退款影響 net_sales ⇒ 報表 gross_margin ≠ 商品詳情頁 margin（官方明言兩者不同：商品頁以定價計、未含折扣退款；商品頁公式本頁未載 ⚠️）。
- **rounding**：cost 快照與 COGS 全程 integer cents（鐵律 3），加總無捨入；gross_margin 顯示位數官方未載 ⚠️（19 §F1 定案前不硬編）。
- **退貨回沖** ⚠️：退款/退貨是否把該單位 cost 自 COGS 回沖（即 `reversal` 事實列是否帶負 cost 分量）官方未載（僅言 discounts and refunds affect your profit margin）——待實測。我方 schema 依對稱原則**保留** reversal 列的 cost 欄位，行為開關等實測定案。
- **日期歸屬**：cost 分量跟隨其事實列的 `occurred_on`（sale＝成立日）；reversal 的 cost 歸屬與回沖問題一併 ⚠️ 待實測。
- 🔴 **第三方流傳的「COGS＝net quantity × average cost」官方頁查無此式**——不得引用；官方僅有「total cost of the units sold during this time period」的列舉式描述。
- **落點**：`SalesFactLine` 自本章 A.1 起即含 `cost_cents`（可 NULL）＋`cost_recorded`；NULL≠0（NULL＝售時未填 ⇒ 排除；0＝真實零成本 ⇒ 計入）。成本來源鏈＝02 章 §D.5（`InventoryItem.unitCost`＋PO 成本回寫）→ 本章事實列快照，**開站即入 schema**，避免事後動事實表 migration。

---

## D. 關鍵流程

### D.1 訂單事件 → 銷售事實 → 報表

1. 【訂單域】訂單成立（含 pending/unpaid；draft 須先轉正式）→ 發事件。
2. 【分析域】展開為 `SalesFactLine(kind=sale, occurred_on=成立日)`，逐 line item 帶 gross/discount/tax/duty/shipping/fee 分量；**讀 T1（訂單成立）當下凍結進訂單行／outbox payload 的 `unitCost` 快照進 `cost_cents`＋`cost_recorded`（C.13，未填則 NULL）——展開時不得讀 `InventoryItem.unitCost` 現值：事件滯留佇列期間 cost 變更會污染歷史毛利** <!-- 2026-08-17 更正（PR #52 第 5 輪） -->；test 訂單標記排除。
3. 退款／取消（帶 refund）／訂單編輯（負向）／退貨 → `SalesFactLine(kind=reversal, occurred_on=處理日)`。互斥拆分依 86 §3.2（refunds 擁有「真的動了的錢」全部，其餘只補未走退款的部分）。
4. 訂單編輯正向增量：計入編輯日（我方口徑，19 §F1.1；本尊為幽靈訂單）。
5. rollup 依 shop 時區日界聚合；查詢層永遠打 rollup。
6. 失敗分支：事件重放（outbox 冪等）；rollup 可重算（`rake analytics:rebuild`）且重算後歷史日數字不變（歸屬日固定是這條的前提）。

### D.2 探索 → 儲存報告（操作者＝商家員工）

1. `/analytics/reports/explore` 開啟；可經 AI 提示列生成（產出＝QL＋自然語言說明＋quick filter 三件套）或手動選槽位。
2. 系統即時三向同步 QL ⇄ 槽位 ⇄ `?ql=`；語法狀態指示（●綠）。
3. 儲存 → 預設名 `{指標} (依 {維度})` → 建 `Report(id, ql)` → 導 `/reports/{id}`。
4. 失敗分支：語法錯 ⇒ 執行鈕擋下＋parseErrors 顯示；未填值的篩選列**不進查詢也不報錯**（草稿篩選列，R11-V8）。

### D.3 歸因計算（查詢時）

1. Storefront 記 session（cookie 同意者）＋ referrer/UTM；跨裝置縫合（2023-03 起）。
2. session↔order 關聯落庫；30 天未購買則 first interaction referrer 重置。
3. 查詢帶 `WITH {模型}_ATTRIBUTION` 時，引擎對每筆訂單依模型分派 channel credit，輸出 `{metric}__{model}` 欄。
4. 不落庫單一模型結果——同資料多模型並存；報告介面預設 last click、Growth 面預設 last non-direct click。

### D.4 匯出報告

1. `⋯` → 匯出 → 彈窗選格式【4】＋範圍【2】→ 產檔。
2. 「全部結果」可超過 1,000 列（顯示上限不限制匯出）。失敗分支官方未載 ⚠️（大檔非同步寄送與否未文檔化）。

### D.5 Live View 資料流

即時事件（訪客/購物車/結帳/訂單）→ 5/10 分鐘滑動窗聚合＋自店鋪時區午夜累計 → 地圖與卡片。與報表層**不同源**（total_sales 公式亦不同）——本尊如此；我方是否統一見 F 節 #9。

---

## E. 跨模組耦合

### E.1 消費（分析域是匯總端，依賴方向：各業務域 → 分析）

| 上游域 | 事件／資料 | 用途 |
|---|---|---|
| 訂單（76） | 成立/取消/編輯/標籤 | sale facts、Orders、AOV 分母 |
| 退款退貨（86） | refund 處理、return 立案/收貨 | reversal facts（處理日）；實體退貨量另計 `reversed_quantity` vs `quantity_returned` 兩軌 |
| 金流（65/69） | 付款嘗試/成功/拒付/費用 | finance 面指標（payments 與 sales 分開，各記各的日期） |
| 庫存 | 進出/調整/調撥/收貨 | 庫存 39 指標；28 天窗計算 |
| 商品/庫存成本（02） | `InventoryItem.unitCost`（cost per item；PO 成本回寫＝02 §D.5） | COGS **售時快照**來源（C.13）——事實列生成時讀當下值，事後改值不回溯 |
| Storefront/主題 | pageview/cart/checkout 事件、Web Vitals | sessions、漏斗、`web_performance` schema（40 指標，R11-V4） |
| 行銷 | UTM、campaign、廣告平台回報 | 歸因維度與行銷 26 指標 |
| 折扣 | 套用明細 | discounts 分量（line item + 訂單級分攤） |
| 禮品卡/儲值 | 發行/兌換/停用 | 財務 9+6 指標；負債面（不進銷售） |
| Markets/推出（R10） | rollout_id／rollout_variant_id | A/B 成效維度（R11-V6） |
| POS | 地點/員工/收銀機 | 零售 8 維度；staff 歸屬口徑官方未載 ⚠️ |

### E.2 發出

- 分析域**不對外發業務事件**（sink）；輸出面＝報表查詢 API（我方走 28 號 GraphQL 契約）＋匯出檔。
- 🔴 本尊**沒有分析類 webhook topic**（訂閱不到「指標變動」）；我方也不設，數字拉取一律查詢制。
- 對內：rollup 重算任務、對帳告警（19 §F2 nightly 抽 3 天全量比對）。

### E.3 同源鐵律的耦合面

鐵律 7：同一指標在 pulse／列表 badge／分析頁同一 rollup。具名例外（官方佐證）：①AOV 獨立分子 ②total_sales 可負 ③any_click 加總＞總計 ④Live View 公式縮水版（我方處置見 F.4 #2）⑤profit 報表的 net sales 僅計 `with_cost_recorded` 桶，與 sales 報表 net sales **官方明言可不等**（C.13）。

---

## F. 落地對應

### F.1 對應倉庫文件

| 本章節 | 倉庫落點 |
|---|---|
| C.1–C.3 指標恆等式 | `docs/specs/19` §F1 指標辭典＋`docs/specs/86` §3.2（撤銷拆解） |
| C.5 漏斗／session | 19 §F3（/collect 第一方追蹤） |
| C.7 歸因 | 19 未覆蓋 → **需新增章節**；維度目錄＝80 §1.2 |
| C.8 幣別時區 | 19 §F1.2＋鐵律 3/10；65 號單位契約 |
| C.9 時效 | 19 §F2 rollup 兩層 |
| C.11 上限 | `config/limits.yml`（新增 analytics 段） |
| C.13 利潤指標族 | 19 §F1 **需新增 profit 指標段**；成本來源＝02 章 §D.5（`unitCost`＋PO 回寫）；`SalesFactLine` schema 含 cost 分量（本章 A.1，開站即入） |
| B.1 報告狀態機 | 原型 `/analytics` 畫面（R11-V1：QL 編輯器常駐非彈窗） |
| ShopifyQL 全語言 | 80 §2（勿重抄，本章只收業務規則） |

### F.2 本尊 vs 我方裁定差異清單

| # | 主題 | 本尊 | 我方裁定 |
|---|---|---|---|
| 1 | 訂單編輯 | 跨日編輯→報表**幽靈訂單**（Orders/AOV 分母被污染，不可逆） | **不復刻**：編輯不產生新訂單；增量記編輯日（19 §F1.1）。差異僅在**分母**，分子口徑與本尊一致 |
| 2 | 金額表示 | 報表 `MONEY` dataType，序列化格式未載 | 全程 integer cents（`Money::Storage`），序列化層才轉；`WITH CURRENCY` 不得當單位參照（鐵律 3） |
| 3 | 撤銷術語 | 2026-03→05 新舊並存過渡 | **一步到位**只用撤銷系命名；`returns` 保留為實體退貨獨立概念 |
| 4 | 時區 | 多鐘並存（session=UTC、LiveView=店時區、報表未明文） | **統一 shop 時區**做日界（19 §F1）；session 切日是否跟 UTC ⚠️ **待裁定＝F.4 #1（M2 前，未裁定不得動工日界函式）** |
| 5 | Session 追蹤 | cookie 同意制、bot 濾除、口徑內建偏低 | 第一方 `/collect`；IP 不落庫；同 30 分鐘滑動 session |
| 6 | 稅務面 | taxes 報表全球一體 | 稅務憑證走 jurisdiction pack（鐵律 11）；分析只發稅務事件 |
| 7 | 幣別換算 | 交易日歷史匯率 | 同（採納）；但店幣＋付款幣別**雙欄落庫**（R11-V5） |
| 8 | 視覺化型別 | 三份清單不等（27/23/cohort 2） | `visualization_type` 帶 mode 維度，不可單表（R11-V2） |
| 9 | Live View 公式 | 縮水版 total_sales（少 duties/fees） | ⚠️ **待裁定＝F.4 #2**：建議我方 Live View 用完整公式（同源優先），需使用者拍板——**不得靜默照抄縮水版，也不得靜默採建議值** |
| 10 | 方案分層 | custom reports 疑似 Advanced+（help 兩說矛盾，R11-DOC8） | 我方 SaaS 方案分層獨立設計，不受本尊矛盾影響；M3 前定案 |
| 11 | 預設幣別不同源 | 報告頁店幣 vs Live View USD（R11-DOC6） | 我方兩頁一律店幣 |
| 12 | 報表資料保留 | 起算日平台級（2021/2022/2023-10-01） | 我方自開站起全量；無需復刻起算日，但**遷移商家**匯入資料須標記口徑斷點 |
| 13 | 未填成本商品的利潤口徑 | **排除**（不以 0 計），拆 with/without cost recorded 兩桶（C.13） | **採納同口徑**：`cost_cents NULL ⇒ 排除`，禁止以 0 計入 COGS；遷移商家匯入的歷史訂單無成本快照 ⇒ 一律 NULL（落 without 桶），不得拿當前 cost 反填 |

### F.3 開發驗收要點

1. **恆等式測試**：`total = net + taxes + duties + shipping + fees` 逐日成立；`net = gross − discounts − reversals`；允許 total < 0。
2. **AOV 獨立分子**：測試**直接斷言實際公式**（分子＝gross/discounts 皆 excl. adjustments，見總綱 A-3）；兩條不等式（`AOV ≠ net/orders`、`AOV × Orders ≠ Total sales`）只在 fixture 滿足前提時追加斷言——前提＝含至少一筆 reversal **且** reversal 金額 ≠ taxes+shipping+duties+fees 合計（否則兩式可能數值巧合相等，無條件不等式會把合法 rollup 打紅）。 <!-- 2026-08-17 更正（PR #52 第 4 輪）：同總綱 A-3；原無條件形是 Codex 指出的誤紅形態 -->
3. **日期歸屬**：跨日退款/編輯後，原訂單日歷史數字不變；rollup 重算冪等。
4. **zero-decimal 幣別**：JPY/TWD/KRW 進金額測試矩陣（65 §H）；報表顯示兩位小數與儲存 ×100 分離。
5. **any_click 白名單**：小計=總計檢查排除 `__any_click` 欄。
6. **漏斗分母**：四階段全部 ÷ 總 sessions；一 session 多訂單案例（completed sessions < orders）。
7. **28 天固定窗**：days_of_inventory／ABC 不可自訂期間；零銷售→N/A、負期末→0 邊界各一測。
8. **like-for-like 比較期**：月中「本月至今 vs 上月」比相同已過時長。
9. **報告狀態機**：切 tab 清空查詢、預設報告不可改名/覆寫、刪除終態導回清單。
10. **cohort 定式**：`BETWEEN -1 AND 11`＋`HAVING >= 0` 模式；Month 0 含同期回購。
11. **草稿篩選列**：未填值不進查詢不報錯。
12. **上限引用**：1,000 列顯示/250 報告/匯出 4 格式，一律 `config/limits.yml`。
13. **成本快照不回溯**：改 cost per item 後，歷史日 `gross_profit`／`cost_of_goods_sold` 不變；`cost_cents` NULL vs 0 語義各一測（NULL 排除、0 計入）。
14. **利潤分桶恆等式**：`without + with = net_sales` **僅對 product line types 斷言**；含運費調整/禮品卡等非商品列的案例不得斷言（官方明文限定）。
15. **margin 分母**：`gross_margin` 分母＝`net_sales_with_cost_recorded`，存在未填成本商品時不得誤用全量 `net_sales`（兩者此時必不等，反向斷言入測試）。

### F.4 開工前必決事項（裁定機制；2026-08-14 登記）

本檔 ⚠️ 分兩級：**G 節 openQuestions＝官方查不到，靠實測補**；**本節＝我方必須拍板才能開工的裁定**。每條列裁定人／期限／預設建議／阻塞範圍；裁定結果回寫本檔（F.2 對應列去 ⚠️＋C 節正文）與 `docs/specs/19`，並在當日 worklog 記錄。**未裁定前，阻塞範圍內的模組不得動工。**

| # | 待決 | 裁定人 | 期限 | 預設建議（僅供拍板，非決議） | 阻塞範圍 |
|---|---|---|---|---|---|
| 1 | session 切日跟 **UTC 午夜**（本尊，C.5）還是跟 **shop 時區**（我方報表統一鐘，F.2 #4） | 使用者 | **M2 rollup 日界函式動工前** | 統一 shop 時區（單一鐘、對帳簡單）；代價＝sessions 類數字與本尊存在永久跨日偏差，裁定後須在 F.2 #4 登記為已知差異 | rollup 聚合核心的日界函式、19 §F1、C.5 漏斗分母、轉換率日序列 |
| 2 | Live View `total_sales` 用**縮水版**（本尊，少 duties/fees，C.1）還是**完整公式**（F.2 #9） | 使用者 | **Live View 畫面動工前**（依 HANDOFF §5 該里程碑 kickoff 為限） | 完整公式（同源優先，符合鐵律 7）；代價＝與本尊 Live View 數字可比性下降 | Live View 卡片（C.10）、D.5 資料流 |

🔴 共同紀律：**不得靜默照抄本尊，也不得靜默採預設建議**——建議欄只為拍板省時，採納與否都要留下裁定紀錄。

---

## G. 來源

| # | URL | 內容 | 取證 |
|---|---|---|---|
| 1 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/sales-report | gross/discounts/net/total/shipping 公式、AOV、計入排除、日期歸屬、幽靈訂單 | 2026-08-14 |
| 2 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/analytics-fields | 指標欄位定義（AOV/回頭客率/轉換率/total=net+…） | 2026-08-14 |
| 3 | https://help.shopify.com/en/manual/promoting-marketing/analyze-marketing/marketing-performance | 歸因 5 模型、30 天視窗、2021-10-01、跨裝置 2023-03-01、Growth 預設 last non-direct | 2026-08-14 |
| 4 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/marketing-reports | 報告內歸因選單出現條件＋預設 last click、session 30min/UTC 午夜、時效（秒/分鐘） | 2026-08-14 |
| 5 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/inventory-reports | sell-through/days remaining/ABC 公式、28 天窗、邊界值、2023-10-01、延遲 2–3 天 | 2026-08-14 |
| 6 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/behaviour-reports | 漏斗四階段、分母=總 sessions、72h 延遲、2022-10-01 | 2026-08-14 |
| 7 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/new-analytics/analytics-updates | reached checkout 新法＋排除清單、回填 2022-10、當前商品名 vs 售出時名、like-for-like | 2026-08-14 |
| 8 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/customers-reports | 顧客報表清單、回頭客=2+ 訂單、cohort 計數例、RFM 11 組、12h 時效 | 2026-08-14 |
| 9 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/overview-dashboard/using-the-overview-dashboard | 1 分鐘時效、60 秒自動刷新（含今天才可開）、交易日歷史匯率 | 2026-08-14 |
| 10 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/live-view | 5 分鐘/10 分鐘窗、店時區午夜、縮水版 total、Kansas 座標、streamer mode | 2026-08-14 |
| 11 | https://help.shopify.com/en/manual/reports-and-analytics/discrepancies/sales-discrepancies | pending 退款顯示、報表 vs 匯出差異、時區未明文 | 2026-08-14 |
| 12 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/finances-report | finance 四區、gross/net payments、禮品卡負債、tips 落點、sales vs payments 對帳、**Gross profit breakdown 卡（with/without cost recorded 分桶＋僅 product line types 限定句）** | 2026-08-14 |
| 13 | https://shopify.dev/docs/api/admin-graphql/latest/queries/shopifyqlQuery | 簽名、回應結構、scope/Level 2/版本需求 | 2026-08-14 |
| 14 | https://shopify.dev/docs/api/shopifyql ＋ /latest/syntax | 語言規格（必要子句、GROUP BY vs TIMESERIES、WITH 修飾子）；全文抽取＝80 §2 | 2026-08-14 |
| 15 | https://changelog.shopify.com/posts/returns-metrics-renamed-to-reversals ＋ https://shopify.dev/changelog/shopifyql-returns-fields-deprecated-and-replaced-with-sales-reversals-fields | 改名時程：2026-03-13 公告／UI 2026-05-01／API 2026-04 棄用→2026-07 移除→2027-04 舊版迄 | 2026-08-14 |
| 16 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/profit-reports | 利潤報告 5 種、gross margin 原式 `((net sales − cost)/net sales)×100`、成本快照鐵則（cost at time of sale）、未填成本**排除**、與商品頁 margin 不同 | 2026-08-14 |

### openQuestions（官方查不到／互相矛盾，不得腦補實作）

1. `sales_reversals` 官方只有列舉式定義，**無加總公式**——我方 86 §3.2 拆解屬自建，需標注非官方。
2. 五種歸因模型**各自的 lookback 視窗長度**未載（僅有 30 天 referrer reset 一個數字）；linear 模型的金額拆分規則未載。
3. **報表整體使用的時區無單一官方明文**（session=UTC 午夜、Live View=店時區、ShopifyQL 預設 shop 時區但另一處對相對日期寫 UTC）。
4. `shopifyqlQuery` 的具體 rate limit 額度、最大列數、timeout、分頁機制未載（僅知 429＋60 秒計時器、複雜度制）。
5. 方案分層兩說矛盾（help「所有方案皆可用主要功能」vs Advanced 方案頁 custom reports 需 Advanced+）——R11-DOC8 未決。
6. `MONEY` dataType 的序列化格式（整數 minor unit vs 十進位字串）未載。
7. pending 退款「先正後負」顯示的精確欄位語義未展開。
8. `customer_cohorts_{weekly|monthly|quarterly}` schema 不在官方 38 清單（實測存在）；retention rate 無官方獨立公式頁。
9. Live View 整體刷新頻率、POS「依員工」歸屬口徑（收銀 vs 協助）未載。
10. 匯出大檔的非同步行為（是否寄信、逾時）未文檔化。
11. **利潤族（C.13）三缺**：①退款/退貨是否回沖 COGS（reversal 是否帶負 cost 分量）未載；②「售時有成本、事後改成本」對歷史列的精確行為未逐字明文（僅能由 at-time-of-sale 語義推定不回溯）；③reversal 的 cost 日期歸屬未載——皆待實測。
12. gross_margin 顯示位數、商品詳情頁 margin 公式未載；第三方流傳「COGS＝net quantity × average cost」官方查無此式，不得引用。
