# 58 — 物流商對接架構（Carrier Integration）

> **緣由**：使用者 2026-08-12 裁定逐字：「**順豐有專門的開發文檔.用來對接我們這個項目.我們會對接很多不同的物流商.進行訂單發貨和訂單運單打印等等.例如 順豐的開發文檔 https://qiao.sf-express.com/ 所以...這些都需要寫入開發文檔需求裡面.**」
> **本檔的全部價值在一句話**：**順豐是第一個實作，不是規格的主體。** 主體是 carrier adapter 這一層抽象——照 56 號 jurisdiction pack 的同一套設計哲學，把「物流商」抽成可插拔的 pack，順豐、DHL、UPS、FedEx、手動出貨全部是這層的實作。凡是寫成 `if carrier == 'sf'` 的分支，都是本檔要防的東西。
> **權威順序**（沿用 52／54／55／56／57）：官方開發文檔 ＞ 官方商家文檔 ＞ 實測 ＞ 我方既有規格。**我方與官方衝突時一律改我方。**
> **但本檔的權威來源分兩支**，不可混用（見 §0.3）：
> - **Shopify 側**（FulfillmentOrder 語義、`supportedActions`、mutation 契約）＝ `46a` 是權威。
> - **物流商側**（順豐介面名、簽章、面單格式）＝ 物流商自己的官方文檔是權威。**46a 不可能是物流商規則的來源**，任何把物流商行為寫成「Shopify 這樣做」的段落一律是錯的。
> **金額鐵律**（CLAUDE.md 鐵律 3）：全程 **integer cents**。運費、COD 代收金額、保價金額、附加費全部適用。**物流商 API 回傳的十進位字串一律以字串解析成 cents，任何路徑上出現 `Float` 即 bug**（見 §G.3）。
> **法域鐵律**（CLAUDE.md 鐵律 11）：本檔為**核心規格**，因此**不得直接引用** `統一發票／字軌／超商取貨／統編／電支條例`。物流商的法域可用性一律走 §H 的介面，不寫死國別分支。
> **法律紅線**（CLAUDE.md 鐵律 9）：本檔**不轉貼**任何物流商文檔的內容。所有引用只描述**介面契約**與**我方的設計決策**，並在 §附錄 B 標明出處 URL。順豐文檔的欄位表、範例報文、錯誤碼全文**不進本倉庫**——要用時由實作者憑帳號自行取得。
> **盤點日**：2026-08-12。**可追溯性**：本檔對既有檔案的改動留 `<!-- 依 … 修正，原文：… -->`，格式沿用 52／54／55／56。

---

## 0. 決議、原則與出處等級

### 0.1 使用者裁定拆解成三條可驗收的要求

| # | 裁定原文的要點 | 本檔怎麼回應 | 驗收在哪 |
|---|---|---|---|
| a | **「我們會對接很多不同的物流商」** | §A 的 carrier adapter 介面 ＋ §B 能力矩陣。順豐降級為 `carrier/sf_express` pack 的素材，與 `dhl_express`／`manual` 平級 | §K CI-1／CI-2 |
| b | **「進行訂單發貨和訂單運單打印」** | §C 發貨（與 FulfillmentOrder 的接合）＋ §D 運單打印（取號／格式／批次／重印／**銷號**） | §K 3–14 |
| c | **「這些都需要寫入開發文檔需求裡面」** | 本檔即為該需求文檔；`config/limits.yml` 的 `carrier.*` 與 `idempotency.required_for` 已同步落鍵（§J） | §K CI-5 |

### 0.2 五條設計原則

1. **物流商是一層，不是一個欄位。** 加一個 `carrier` 字串欄位再到處 `if carrier == 'sf'` 是本檔要防的正是那件事。與 56 §0.2 原則 1 完全同一條——`if` 散落各處保證會漏，而物流商的漏法比法域更貴：漏一次就是多一張運單、多一筆運費。
2. **未宣告 ≠ 不支援。** 缺值時**不得靜默降級**。「這家物流商沒有運費試算 API」必須是 pack 裡**寫出來的一行** `rate_quote: { supported: false, reason: ... }`，不能是「沒填所以當作沒有」。理由與 56 §A.3 逐字同構，見 §A.3。
3. **取號是不可回收的外部副作用。** 這是本檔與其他規格最大的不同點——訂單、退款、庫存都可以在我方 DB 內回滾，**運單號不行**。因此 §D.5 的「銷號帳」是硬要求，不是選配。
   <!-- 依 2026-08-12 第二輪順豐查證修正，原文：「取號是不可回收的外部副作用，且是有價的。……運單號不行。取了不用，物流商照樣計費。因此 §D.5 的「銷號帳」是硬要求，不是選配。」 -->
   🔴 **但原文的「取了不用，物流商照樣計費」是把未查證的商業假設寫成了事實，本輪已推翻其事實地位。** 順豐官方兩份 PDF 對「未使用運單號是否計費」**完全沉默**（SF-15）——那屬月結合約條款，不屬 API 契約。**銷號帳並不因此廢除**，因為它的真正依據換成了官方明載的一條：**識別不可回收**（SF-14）。計費與否只決定**告警等級**（§D.5(d)），不決定帳要不要記。這條修正的完整論證見 §D.5(a)。
4. **carrier ≠ fulfillment service。** 這兩個概念在 46a 的模型裡是不同的東西，混在一起會污染 `requestStatus` 這條軸。完整論證見 §C.3——**這是本檔最容易被實作者做錯的一條**。
5. **carrier pack 與 jurisdiction pack 正交。** 兩者都可插拔，但不是同一層，也不可互相繼承。物流商的**可用性**是法域的函數，物流商的**能力**不是。見 §H。

### 0.3 出處等級（在既有四級 dev／help／live／ours 之外新增三級）

| 等級 | 意義 | 可否據以寫死實作 |
|---|---|---|
| `carrier-official` | 物流商**官方**發布的文檔（官網 PDF／官方開發者入口頁）。URL 見 §附錄 B。 | ✅ 可 |
| `carrier-secondary` | 第三方來源（開源 SDK 的常數表、技術部落格、聚合商說明頁）**佐證**了某個介面名或行為。**可寫進規格作為「疑似值」，但一律同時登記 V 編號**，實作前須以官方文檔或實測覆核。 | ⚠️ 需覆核 |
| `carrier-unobtainable` | 本輪**確實取不到**：頁面需登入、或文檔未公開、或已窮盡下列取得手段仍無正文。**一律寫「未能取得」並登記 V 編號，不得推測補寫。** | ❌ 禁止 |

> <!-- 依 2026-08-12 第二輪查證修正，原文本級的定義為：「頁面需登入、或頁面為 JS 前端渲染（WebFetch 只拿得到 meta 標籤）、或文檔未公開」 -->
> 🔴 **「頁面是 JS 渲染的 SPA」不構成 `carrier-unobtainable`——上一輪據此結案是錯的，本輪已推翻。**
> SPA 只代表**這一種抓法**失敗，不代表文檔不公開。順豐的 API 目錄**不需要帳號**即可閱讀。本輪從同一批「抓不到」的頁面上，改用下列手段仍取得了官方事實（SF-12～SF-21）：
>
> | 手段 | 本輪取得了什麼 | 為什麼算官方 |
> |---|---|---|
> | **靜態檔案路徑**（`doc/download/*.pdf`）| SF-13～SF-19 的全部內容 | 順豐自己發布的 PDF |
> | **搜尋引擎索引的頁面標題** | 介面名 ＋ 服務代碼 ＋ 所屬分類（SF-20） | 標題由順豐頁面自身輸出，索引只是搬運；**僅可據以確認「介面存在與其分類」，不可據以推斷欄位** |
> | **DNS 解析** | 端點網域正確寫法（SF-12） | 權威 DNS 是比 PDF 更硬的事實 |
>
> **由此新增一條方法論鐵則**：判定 `carrier-unobtainable` 前，**必須逐一試過並記錄**「靜態檔案路徑／搜尋引擎索引標題／DNS 或其他帶外事實」三條路徑。只試了 WebFetch 就結案，等同把「我沒查到」寫成「查不到」——那正是 CLAUDE.md「寫錯的事實比缺漏的事實傷害大」要防的東西。本輪試過的完整 URL 清單見 §附錄 B。

> **本檔對 `carrier-unobtainable` 的處理原則**（CLAUDE.md：「寫錯的事實比缺漏的事實傷害大」）：
> 抽象層（§A–§H）**不依賴**任何未查證的順豐細節就能成立。順豐的具體欄位缺失只影響 `carrier/sf_express` 這一個 pack 的填值，不影響介面設計。**這正是把它抽成 pack 的好處**——文檔拿不到，架構照樣往下做。

### 0.4 順豐研究實得（2026-08-12，逐項標出處等級）

**(a) `carrier-official` — 從順豐官方 PDF 直接取得**

| # | 事實 | 出處 |
|---|---|---|
| SF-1 | 順豐開放平台（丰桥）的**標準服務端點**：沙箱 `https://sfapi-sbox.sfexpress.com/std/service`、生產 `https://sfapi.sfexpress.com/std/service` | B-2（官方 SDK 指南 PDF，Java 常數 `CALL_URL_BOX` / `CALL_URL_PROD`） |
| SF-2 | **請求信封為固定六欄**：`partnerID`、`requestID`、`serviceCode`、`timestamp`、`msgData`、`msgDigest`。業務參數一律 JSON 放在 `msgData`，`msgDigest` 為簽章。 | B-2 |
| SF-3 | **憑證為兩件式**：`clientCode`（客戶編碼，即 `partnerID`）＋ `checkword`（校驗碼），由丰桥平台核發。 | B-2 |
| SF-4 | 官方 SDK 提供的服務代碼（節錄，均為 `serviceCode` 的值）：`EXP_RECE_CREATE_ORDER`（下單）、`EXP_RECE_SEARCH_ORDER_RESP`（訂單結果查詢）、`EXP_RECE_UPDATE_ORDER`（訂單取消／確認）、`EXP_RECE_FILTER_ORDER_BSP`（訂單篩選）、`EXP_RECE_SEARCH_ROUTES`（路由查詢）、`EXP_RECE_GET_SUB_MAILNO`（子單號申請）、`EXP_RECE_QUERY_SFWAYBILL`（運費查詢）、`EXP_RECE_REGISTER_ROUTE`（路由註冊） | B-2 |
| SF-5 | 舊版（V3.8，XML 世代）的服務清單另有 `OrderService`／`OrderSearchService`／`OrderConfirmService`／`OrderFilterService`／`RouteService`／`OrderZDService`／`PushOrderState`／`RoutePushService`／`RegisterRouteService`／`OrderReverseService`。**順豐存在兩個世代的 API**（XML 版與 JSON `/std/service` 版），對接時必須先確認帳號被開通的是哪一版。 | B-1（官方 API 規範 PDF V3.8） |
| SF-6 | 官方文檔明示查單介面的存在理由是**網路不可靠**（逐字要點：Internet 環境下網路不是絕對可靠，故提供訂單結果查詢介面）。 | B-1 |
| SF-7 | 官方文檔（B-1、B-2 兩份）**均未載明**限流／QPS、逾時重試建議、冪等機制。 | B-1、B-2 |
| SF-12 | **端點網域的正確寫法是 `sf-express.com`（有連字號）。** 官方 SDK PDF 印的 `sfapi.sfexpress.com` / `sfapi-sbox.sfexpress.com`（無連字號）**在權威 DNS 上沒有 A 記錄**，連 apex `sfexpress.com` 也沒有；`sfapi.sf-express.com` 與 `sfapi-sbox.sf-express.com` 皆正常解析。⇒ **官方 PDF 這一處是錯的／過期的，第三方寫法才對。** | B-12（本機 DNS 解析，2026-08-12） |
| SF-13 | **錯誤碼（節錄自官方錯誤碼表）**：`8016` 重複下單、`8019` 訂單已確認或已取消、`4001` 系統資料錯誤／執行期例外；RLS 側 `1000` 成功、`0000` 介面參數異常、`0001` XML 解析異常、`0002` 欄位校驗異常、`0003` 單號節點超過上限、`0004` 缺少必填欄位、`0010` 其他異常。 | B-1 |
| SF-14 | **識別不可回收**：取消走 `OrderConfirmService` 的 `dealtype=2`（`1`＝確認、`2`＝取消，值域僅此二值）；官方明載**訂單取消之後，客戶訂單號（`orderid`）不得重複使用**。文檔**未**述及順豐運單號（`mailno`）本身是否回收或可重發。二次取消回 `8019`。 | B-1 |
| SF-15 | **官方兩份 PDF 均未載明**：未使用之運單號是否計費、銷號時間窗、未使用運單號的有效期。**「取號未使用照樣計費」在官方文檔中無任何依據**（既未確認亦未否認）。 | B-1、B-2 |
| SF-16 | **路由推送（`RoutePushService`）官方未定義任何驗簽欄位。** 接收方須回 XML，且**結果只能為 `OK` / `ERR`**；回 `ERR` 或失敗時順豐「將重新推送此次交易的所有資訊」，但**未載明重送次數與間隔**。 | B-1 |
| SF-17 | **路由操作碼未在規範內列舉**（原文要求「可在文檔中心查看路由節點資訊操作碼」），文中僅出現示例 `50`（上門收件）、`922`（簽單返還單號）。 | B-1 |
| SF-18 | **官方明載的批次上限**：`OrderService` 不支援批次；`OrderFilterService` ≤ 5 個 `OrderFilter`；`RouteService` ≤ 10 個 `tracking_number`；`RoutePushService` ≤ 10 個 `WaybillRoute`；RLS 路由標籤批次 ≤ 100 個單號（超過回 `0003`）；`OrderZDService` 的 `parcel_quantity` ≤ 20 個新子單號。 | B-1 |
| SF-19 | **香港／國際件走同一支介面、同一個端點**：國際件與國內件同用 `OrderService`，以 `d_deliverycode` 標目的地（香港＝`852`）、`declared_value_currency` 支援 `HKD`，另有 `send_cert_type`／`order_cert_type` 等證件欄位。**`express_type`（快件產品類別）的值域在附錄《快件產品類別表》，而該附錄未含於本 PDF 內**，文中僅出現無圖例的示例值。 | B-1 |
| SF-20 | **雲打印面單介面確實存在且屬「面單類API」**：順豐官方頁面標題為「雲打印面單打印2.0接口-`COM_RECE_CLOUD_PRINT_WAYBILLS`」（`level3=317`）；同族另有「ISV刪除自定義模板接口-`COM_RECE_CLOUD_CUSTOMTEMPLATE_DELETE`」（`level3=320`，歸「基礎通用API-面單類接口」）。**僅確認介面名、服務代碼與分類；欄位表仍未取得。** | B-13、B-14（順豐官方頁面標題） |
| SF-21 | **API 目錄的 URL 參數語義**：目錄頁為 `/Api?category={業務線}&apiClassify={介面型態}`，明細頁為 `/Api/ApiDetails?...`；舊式明細頁另有扁平的 `level3={介面流水號}`。**已證實的值**：`category=1`＝速運類API、`category=4`＝冷運API；`apiClassify=1`＝請求／回應型介面、`apiClassify=2`＝推送型介面（`RoutePushService` 位於 `category=1&apiClassify=2`）。**其餘 `category` 值（含使用者提供的 `category=6`）的分類名稱未能取得**（V-41）。 | B-13、B-15、B-16 |

> **SF-6 是本檔 §F.4 的直接依據。** 順豐自己把「查單介面」定位成回應遺失時的補救手段——這等於官方承認 `EXP_RECE_CREATE_ORDER` 的回應**可能丟失但副作用已發生**。我方的 `UNKNOWN` 狀態與回查對帳流程不是我方多慮，是照著物流商自己的說明設計的。

**(b) `carrier-secondary` — 有第三方佐證但未經官方頁面確認**

| # | 疑似事實 | 佐證來源 | V 編號 |
|---|---|---|---|
| ~~SF-8~~ **已升級為官方** | 雲打印面單 2.0 介面與服務代碼 `COM_RECE_CLOUD_PRINT_WAYBILLS` **已由順豐官方頁面標題確認**，見 SF-20。**欄位表仍未取得**，V-39 只縮小不結案。 | → SF-20 | **V-39（部分）** |
| SF-22 | 雲打印面單的**回傳檔案形態疑為 PDF**，且模板以「模板代碼」選定、尺寸為離散值域，疑似含 `100×150` / `100×180` / `100×210` / `76×130` 四種國內規格與 `100×150` / `100×210` 兩種國際規格；請求疑有 `fileType`、`masterWaybillNo`、`branchWaybillNo` 等欄位 | B-17（第三方閘道商的順豐雲打印文檔，**標的為 1.0 版，非官方 2.0**） | **V-39** |
| SF-23 | **未見任何來源指出順豐雲打印介面本身會輸出 ZPL 指令流**；B-17 明列輸出為 PDF。聚合商 EasyPost 宣稱可提供順豐面單的 `ZPL` / `PNG` / `PDF` 三種形態，但那是**聚合商自己的轉檔輸出**，不等於順豐原生支援 | B-17、B-18 | **V-40** |
| SF-9 | 服務代碼另有 `EXP_RECE_VALIDATE_WAYBILLNO`（運單號合法性驗證）、`EXP_RECE_QUERY_GIS_DEPARTMENT`（網點查詢）、`EXP_RECE_QUERY_DELIVERTM`（時效與價格查詢）、`EXP_RECE_SEARCH_PROMITM`（預計送達時間）、`EXP_EXCE_CHECK_PICKUP_TIME`（取件時間校驗）、`EXP_RECE_CREATE_REVERSE_ORDER`（退貨下單）、`EXP_RECE_WANTED_INTERCEPT`（攔截） | B-5 開源 SDK 常數表 | **V-37** |
| ~~SF-10~~ **已結案** | 端點網域兩種寫法之爭**已由 DNS 解析判定**：`sf-express.com`（有連字號）才是對的，官方 SDK PDF 的無連字號寫法無法解析。見 SF-12。 | → SF-12 | ~~V-38~~ 已結案 |
| SF-11 | `msgDigest` 的計算疑為以 `msgData`＋`timestamp`＋`checkword` 為輸入，官方 SDK 只暴露方法簽名 `getMsgDigest(msgData, timeStamp, checkWord)`，**演算法本身（串接順序／雜湊／編碼）官方兩份 PDF 均未載明**（本輪再次覆核，仍未載明） | B-1、B-2 | **V-51** |
| SF-24 | 順豐憑證疑為**三件式**而非兩件式：聚合商 EasyPost 要求 `customer_code`、`customer_id`、`checkword` 三個欄位，與 SF-3（`clientCode` ＋ `checkword` 兩件式）不一致 | B-18 | **V-52** |

> **SF-11 的 V 編號原本標成 `V-40` 是錯的**——附錄 A 的 V-40 是「是否支援 ZPL」，msgDigest 演算法在附錄 A **從來沒有登記過**，等於一個沒有掛號的缺口。本輪改標 **V-51** 並補登記。
> <!-- 依 2026-08-12 第二輪查證修正，原文 SF-11 的 V 編號為 V-40（與附錄 A 的 V-40「ZPL」定義衝突，屬誤標） -->
> **這一條比它看起來重要**：`msgDigest` 算不出來 ⇒ **一個請求都送不出去**。它應該是 `sf_express` pack 的**第一號阻塞項**，卻因為誤標而在 `enable_gate` 裡完全不存在（原 gate 為 `[V-39, V-40, V-42, V-43, V-44, V-47, V-48]`，無任何一項對應簽章）。本輪已補進 gate。

**(c) `carrier-unobtainable` — 本輪確實取不到，已登記**

<!-- 依 2026-08-12 第二輪查證整表重寫。原表把「JS 渲染 SPA」當成取不到的理由，並據此把五項全列為 unobtainable；其中三項本輪已部分或全部取得。原表五列見 git 歷史。 -->

> **本表已於 2026-08-12 第二輪整表重寫。** 原表的共同理由是「頁面為 JS 渲染的 SPA ⇒ 取不到」，該判斷已被推翻（見 §0.3 的修正框）。下表是**改用三條替代路徑後仍然取不到**的部分，且逐列寫明**這一輪實際試過什麼**。

| 取不到的東西 | 本輪試過什麼、為什麼仍取不到 | V 編號 |
|---|---|---|
| 完整介面目錄（全部 `category` 分類名稱與逐介面欄位表） | ①`/Api?category=…&apiClassify=…` 與 `/Api/ApiDetails?…` 皆只回 `<meta>`；②**該站對任何未命中靜態檔的路徑一律回退 index.html**（連 `robots.txt`、`sitemap.xml` 都回 SPA 外殼），故無法用站內索引枚舉；③容器內直連受出口政策阻擋（CONNECT 403），無法自行渲染；④`web.archive.org` 亦被出口政策阻擋（403），無法用 CDX 枚舉歷史 URL。**已取得的部分見 SF-20／SF-21。** | **V-41（縮小）** |
| 雲打印面單 2.0 的請求／回應欄位、模板代碼與尺寸的**官方**值域 | 同上。介面名與分類已由官方頁面標題確認（SF-20）；欄位與尺寸僅有第三方 1.0 版佐證（SF-22），**不可直接當 2.0 用** | **V-39（縮小）** |
| 順豐**運單號**（`mailno`，非 `orderid`）取消後是否回收、未使用是否計費、銷號時間窗 | 官方兩份 PDF 逐節覆核後確認**通篇沉默**（SF-15）。取消動作本身與 `orderid` 的不可重用性已取得（SF-14）。**此項本質上是月結合約條款，不在 API 文檔的涵蓋範圍內**——這不是「文檔沒抓到」，是「這件事根本不寫在 API 文檔裡」 | **V-42（改性質）** |
| **香港商戶**能否申請丰橋帳號、以香港為**寄件地**下單 | 丰橋文檔全篇以中國內地為寄件地；香港站（`htm.` / `hk.sf-express.com`）為商用說明頁，本輪再查仍無開發文檔。**「香港作為目的地」已確認可行（SF-19），「香港作為寄件地」仍未確認**——這兩件事被原表混為一談 | **V-43（拆分後縮小）** |
| `express_type`（快件產品類別）的**數值值域** | 官方 PDF 明指值域在附錄《快件產品類別表》，而**該附錄未含於 PDF 內**，亦未給出獨立檔名或 URL（SF-19）。香港端的**服務名稱**已取得（標準快遞／國際特惠，B-19），但**名稱到數值代碼的對應仍缺** | **V-44（縮小）** |

> **對 §0.4(c) 的處置**：`carrier/sf_express` pack 在這些填值到手之前，其 `enable_gate` **不得為空**（見 §H.4）。也就是說——**順豐 pack 在本輪仍不可上線**，只能建骨架。這與 56 §A 對未定案 pack 的處置一致：能力沒宣告完，pack 就不准 enable。
>
> **但本輪 gate 的組成變了，且變得更誠實**：移除已結案的 V-38；新增本輪才發現的 **V-51（`msgDigest` 演算法）**——那是「連一個請求都送不出去」的第一號阻塞項，卻因誤標而原本不在 gate 裡（見 SF-11 下方的說明框）。**gate 從「湊了七項看起來很嚴」變成「七項各自對應一個真實的、會擋住實作的缺口」。**
>
> 🔴 **V-42 的性質變了，這一點影響最大**：它從「文檔沒抓到」變成「**這件事不寫在 API 文檔裡**」。所以它**永遠不會**因為多抓幾個網頁而結案——它只能由**順豐月結合約或商務窗口**回答。把它留在 `enable_gate` 裡等網頁查證，等於讓 pack 永遠卡住。正確處置見 §D.5(f)。

**(d) 對照組：其他物流商的對接形態（用來驗證抽象是否切對）**

| 物流商 | 認證 | 環境 | 操作分類（官方文檔用語） | 出處等級 |
|---|---|---|---|---|
| **順豐 SF** | `partnerID` ＋ `checkword`，每次請求帶 `msgDigest` 簽章 | 沙箱／生產**不同網域**，同一路徑 `/std/service` | 單一端點 ＋ `serviceCode` 分派（**RPC 風格**） | `carrier-official` |
| **DHL Express（MyDHL API）** | HTTP Basic（官方逐字：Authorization header 以 pre-emptive BasicAuth 設定） | 測試 `https://express.api.dhl.com/mydhlapi/test`、生產 `https://express.api.dhl.com/mydhlapi` | 依資源分路徑（**REST 風格**）：Rating／Product／Landed Cost／Shipment／Pickup／Tracking／Address／Identifier／Service Point／Get Image／Invoice | `carrier-official`（B-8） |
| **UPS** | OAuth 2.0（client credentials） | 測試／生產分離 | Rating／Shipping／Label Recovery／Void Shipment／Tracking／Pickup | `carrier-secondary`（B-9，未逐項覆核 → **V-45**） |
| **FedEx** | OAuth 2.0 | Sandbox／Production | Rate／Ship／Cancel Shipment／Track／Pickup／Open Ship | `carrier-secondary`（B-10 → **V-45**） |
| **香港本地／聚合商** | 香港市場實務上大量透過**聚合商**（如 ShipAny）接多家物流商，而非逐家直連 | — | 聚合商提供批次面單列印、多平台訂單同步、追蹤通知 | `carrier-secondary`（B-11 → **V-46**） |

**從對照組看出的三個共通抽象**（這是 §A 的設計依據，不是猜的）：

1. **四家全部有、且形態一致的操作**：建立運單／取消或作廢／查追蹤／取面單。**這四個進「必宣告能力」。**
2. **形態差異極大、不可假設的操作**：運費試算（順豐有 `EXP_RECE_QUERY_SFWAYBILL`，但語義是否等同 DHL 的 Rating 未經覆核）、預約取件、報關文件、服務點查詢。**這些進「可選能力」，且缺席時必須顯式宣告。**
3. **端點風格分兩派**：順豐是「單一端點 ＋ serviceCode 分派」的 RPC 風格，DHL/UPS/FedEx 是資源分路徑的 REST 風格。
   ⇒ **adapter 介面不得洩漏 HTTP 形狀**。介面上只能有 `create_shipment(request) -> result`，不能有 `service_code` 或 `path` 這種只有一派才有的概念。這條在 §A.4 落成硬規則。

---

## A. 抽象層：carrier adapter 的能力介面

### A.0 先把三個被混用的名詞分開

把這三者塞進同一張表是本架構最容易犯的錯，錯了以後「同一家物流商、同一個租戶、兩個帳號、三種服務」就表達不出來。

```
CarrierPack     ← 程式碼層。一家物流商的 adapter 實作 ＋ 靜態能力宣告。
                   不帶 shop_id，不帶任何憑證。跟 jurisdiction pack 一樣是「程式碼資產」。
                   例：carrier/sf_express、carrier/dhl_express、carrier/manual

CarrierAccount  ← 資料層。某個租戶在某家物流商的某一組月結帳號 ＋ 憑證 ＋ 環境。
                   **帶 shop_id**（鐵律 2）。同一租戶可有多組（不同月結帳號、沙箱與生產）。
                   例：(shop_id=7, carrier_code='sf_express', env='production', label='HK 主帳號')

CarrierService  ← 業務層。一個可販售的配送服務，是 (pack, account, service_code, lane) 的組合。
                   對外顯示成結帳頁的一列運費選項、後台出貨畫面的一個下拉選項。
                   例：順豐 · 香港本地 · 標準快遞
```

**三條硬要求**

1. **`CarrierPack` 不得持有狀態。** adapter 是無狀態的純函式集合，憑證由呼叫方注入。理由：同一 pack 要同時服務數千租戶，任何實例變數都是跨租戶污染的入口。
2. **`CarrierAccount` 的憑證欄位永不明文、永不進日誌。** 見 §G.2。
3. **`CarrierService` 的可用性是計算結果，不是設定值。** 由「pack 宣告的能力」∩「account 開通的服務」∩「法域可服務航線」三者交集算出（§H.2）。**不得**讓商家在後台手動勾選一個 pack 沒宣告的服務。

### A.1 十三項能力總表

| # | 能力鍵 | 中文 | 必宣告 | 缺席時核心怎麼降級 | 核心在哪裡呼叫它 |
|---|---|---|---|---|---|
| K1 | `rate_quote` | 運費試算 | 是 | 改用 15 的靜態運費表；**結帳頁不得出現「即時運費」字樣** | 15-F2 金額引擎（結帳期）、16 後台出貨預估 |
| K2 | `shipment_create` | 建立運單並取號 | 是 | 無法自動出貨 ⇒ 只能走 `manual` pack 手填單號 | §C.1 出貨編排 |
| K3 | `label_render` | 面單檔案產出 | 是 | 出貨後不提供「列印面單」按鈕，改顯示「請至物流商後台列印」 | §D.2 |
| K4 | `shipment_void` | **銷號**（把號還回去） | 是 | **不得靜默略過**——改記入銷號帳的 `manual_required` 佇列（§D.5） | §D.5 |
| K5 | `shipment_cancel` | 取消運送安排 | 是 | 出貨後不提供「取消運單」按鈕 | §C.2 |
| K6 | `tracking_pull` | 主動查詢路由 | 是 | 追蹤狀態只能靠 K7 推送；兩者皆無 ⇒ 追蹤時間軸顯示「本物流商不提供追蹤資料」 | 16 訂單時間軸、買家訂單狀態頁 |
| K7 | `tracking_push` | 路由推送（webhook） | 是 | 改為 K6 輪詢，輪詢間隔取 `limits.carrier.tracking.poll_interval_seconds` | §C.4 |
| K8 | `pickup_schedule` | 預約取件 | 否 | 出貨畫面不出現「預約取件」區塊 | §C.5 |
| K9 | `cod` | 貨到付款／代收貨款 | 否 | 該 carrier 的服務在結帳頁**不得**與 COD 付款方式併存（15 的付款×配送相容矩陣） | 15 付款方式、16-F4.4 COD 對帳 |
| K10 | `customs_doc` | 跨境報關文件 | 否 | 跨境航線在 §H.2 直接判為不可服務（**不是**允許出貨後再補件） | §H.2 |
| K11 | `service_point` | 服務點／自提點查詢 | 否 | 該 carrier 不參與 `pickup_networks` 的選點（§H.3） | 15-F3.1 結帳選點 |
| K12 | `address_validate` | 地址可服務性驗證 | 否 | 出貨前不做預檢，地址錯誤只能在 K2 失敗時才發現 | §C.2 |
| K13 | `billing_reconciliation` | 運費／代收對帳檔 | 否 | 運費差異只能人工核對；**銷號帳的閉環驗證改為人工**（§D.5） | 16-F4.4、37 清結算 |

> **K1–K7 為「必宣告」的判準**（呼應 §0.4(d) 結論 1）：對照組四家全部具備、且形態一致的操作。必宣告的意思**不是**「必須支援」，而是「**pack 必須就這一項寫出 `supported: true/false`，寫 false 也要給 `reason`**」。這是 §A.3 的核心。
>
> **K4 為什麼在必宣告裡而不是可選裡**：因為缺席它的後果是**財務性的**，不是功能性的。一家不支援線上銷號的物流商，我方仍然背著「取了沒用的號要付錢」這個負債；系統必須知道自己背著它，才能把它排進人工佇列。**「沒宣告」在這一項上等於「不知道自己在漏錢」。**

### A.2 逐項能力契約

每一項寫三件事，格式沿用 56 §A.2：**核心怎麼呼叫**、**pack 宣告後的行為**、**pack 未宣告時的 fallback**。以下只展開三個最容易做錯的；其餘十項的契約結構相同，值域見 §J 的 `limits.carrier.capability_schema`。

---

#### K2 `shipment_create`（本檔風險最高的一項）

**核心怎麼呼叫**——核心**不直接呼叫 adapter**。核心只寫一筆意圖，由編排層去呼叫（§F 的理由）：

```
ShipmentIntent = {
  shop_id, fulfillment_order_id, carrier_account_id, service_code,
  packages[ { weight_grams, length_mm, width_mm, height_mm } ],   # 整數，無浮點
  declared_value_cents, cod_amount_cents,                          # integer cents（鐵律 3）
  idempotency_key,                                                 # 鐵律 5，見 §E
  status ∈ { PENDING, IN_FLIGHT, SUCCEEDED, FAILED, UNKNOWN, ABANDONED }
}
```

`Carrier::Adapter#create_shipment(account:, intent:) -> ShipmentResult`

```
ShipmentResult = {
  outcome ∈ { success, business_rejected, transient_error, unknown },
  waybill_number, sub_waybill_numbers[],
  quoted_freight_cents,        # 可為 nil（多數物流商下單時不回實際運費）
  carrier_reference,           # 物流商側的訂單識別，回查用
  raw_error_code, raw_error_message,   # 原樣保留，供 V 編號覆核與客服
  retryable ∈ { true, false }
}
```

**四個 outcome 必須分開，不得合併成 success/failure 兩值**——這是本檔與一般實作最大的差異：

| outcome | 意思 | 號碼可能已產生？ | 系統怎麼處置 |
|---|---|---|---|
| `success` | 明確成功，拿到號 | 是 | 進 §F.3 的 settle |
| `business_rejected` | 物流商明確拒絕（地址不可服務、超材積、帳號無此服務） | **否** | intent → `FAILED`；FO **狀態不變**（§C.2） |
| `transient_error` | 明確的暫時性失敗（HTTP 5xx、連線被拒、限流） | **否** | 退避重試，重試帶**同一** `idempotency_key`（§E.2） |
| `unknown` | **逾時、連線中斷、回應無法解析** | **可能是** | intent → `UNKNOWN`，**禁止自動重試**，進 §F.4 回查對帳 |

> 🔴 **把 `unknown` 併進 `transient_error` 是本檔要防的最貴的一個 bug。** 逾時不代表沒發生——順豐官方自己就是這樣說的（SF-6）。自動重試一個可能已經成功的取號請求，結果是**兩張運單、兩筆運費，其中一張永遠不會被使用也不會被銷號**。

**已宣告的行為**

| 宣告 | 行為 |
|---|---|
| `supported: true` | 走上表 |
| `supported: false, reason: <字串>` | 該 carrier 只能作為「追蹤用」carrier：後台出貨畫面**隱藏**「向物流商下單」按鈕，只留手填單號欄位；`reason` 原樣顯示在 carrier 設定頁 |

**未宣告的 fallback**：`reject`。任何觸及該 carrier 的出貨路徑一律回 `userErrors{ code: CARRIER_CAPABILITY_UNDECLARED, field: ["carrierAccountId"] }`，**並且該 carrier pack 不得 enable**（§H.4 的 gate）。

---

#### K4 `shipment_void`（銷號，財務性的一項）

**核心怎麼呼叫**：`Carrier::Adapter#void_shipment(account:, waybill:) -> VoidResult`

```
VoidResult = { outcome ∈ { voided, refused, too_late, unknown }, frees_number ∈ { true, false, unknown } }
```

**已宣告的行為**

| 宣告欄位 | 意義 | 缺一不可的理由 |
|---|---|---|
| `supported` | 是否有線上銷號介面 | — |
| `window_hours` | 取號後多久內可銷 | 過期就不是「還沒去做」，是「做不到了」，兩者的人工處置不同 |
| `frees_number` | 銷號後號碼是否失效／可否回收 | 影響我方能否重用；`unknown` 時一律**不重用** |
| `billed_if_unused` | 取號未使用是否照樣計費 | **這一欄決定銷號帳的告警等級**。`true` ⇒ 逾時未銷是財務事故；`false` ⇒ 只是資料髒 |

**未宣告的 fallback**：`reject`——**但 reject 的對象不是銷號動作，是 carrier 的啟用**。理由見 §A.3 第二段。

---

#### K9 `cod`

**核心怎麼呼叫**：COD 不是 adapter 的一個方法，是 `shipment_create` 的一個欄位（`cod_amount_cents`）＋ 一條相容性宣告。

**已宣告的行為**：`{ supported, max_cents, currency, settlement_file_available, settlement_cycle_days }`。
`max_cents` 的比較口徑沿用既有的 `limits.cod.cap_compares_against: total_including_fee`——**不得**在本檔另立一套口徑。

**未宣告的 fallback**：`reject`。具體表現為 15 的付款×配送相容矩陣**直接排除**該組合，結帳頁不顯示；**不是**顯示了才在提交時報錯。

> **與法域的交界**：COD 的**上限**可能同時受物流商合約與法域規範拘束，取兩者的**較小值**。實作上：`effective_cod_max = min(carrier.cod.max_cents, jurisdictions.<buyer>.pickup_networks.cod_max_cents)`，任一為 `null`（未宣告）⇒ **reject**，不得當作無上限。

### A.3 為什麼「未宣告」一律 reject（本節是 §A 的核心，請勿簡化）

這條完全複製 56 §A.3 的論證，換成物流商的脈絡：

> **`supported: false` 與「沒填」在程式上長得一樣，但風險完全相反。**
> `supported: false` 代表**有人想過**這家物流商沒有這個能力，並且決定了降級行為。
> 「沒填」代表**沒人想過**——靜默當成 `false` 就是把「還沒設計」偽裝成「已經設計好的降級」。

物流商版本比法域版本更危險，因為多了一層：**法域缺值的後果多半是少開一張憑證（可事後補救）；物流商缺值的後果是每一單都在漏錢或漏貨，而且看起來一切正常。**

**兩種 reject 的對象不同，不可混為一談**：

| 缺的是什麼 | reject 什麼 | 為什麼 |
|---|---|---|
| **必宣告能力（K1–K7）任一未宣告** | **reject 整個 pack 的 enable**（開機期就 fail，不是執行期） | 一家連「能不能取消」都沒定義的物流商，不該有任何一單走它。這是 build/boot 期的 gate，比照 56 §F CI-1 |
| **可選能力（K8–K13）未宣告** | **reject 用到該能力的那條路徑**（執行期回 `userErrors`） | 沒宣告報關能力不影響本地單，只該擋跨境單 |

**凡是走了降級路徑（`supported: false` 的既定行為），一律落一列 `carrier_capability_skips`**（`shop_id`／`carrier_code`／`capability`／`fulfillment_order_id`／`reason`／`occurred_at`），不得靜默返回。這張表與 56 的 `jurisdiction_capability_skips` 同構同理由：**「什麼都沒做」必須看得見**，否則三個月後沒人知道有多少單走了降級路徑。

### A.4 adapter 必須實作什麼（介面的硬形狀）

```
module Carrier::Adapter          # 無狀態；所有方法為純函式，憑證由 account 注入
  # --- 靜態宣告（class 級，開機期讀取，不打網路）---
  def self.code            -> Symbol            # :sf_express
  def self.display_name    -> String
  def self.capabilities    -> Hash              # 十三項，K1–K7 必須齊全（§A.3 gate）
  def self.credential_schema -> Hash            # 這家需要哪些憑證欄位，各自是否 secret
  def self.serviceable_lanes -> [Lane]          # §H.2

  # --- 執行期（打網路，一律在 DB transaction 之外，見 §F）---
  def create_shipment(account:, intent:)        -> ShipmentResult
  def void_shipment(account:, waybill:)         -> VoidResult
  def cancel_shipment(account:, shipment:)      -> CancelResult
  def render_label(account:, waybill:, format:, size:) -> LabelResult
  def quote_rates(account:, quote_request:)     -> [RateQuote]
  def pull_tracking(account:, waybill:)         -> [TrackingEvent]
  def verify_push(account:, raw_request:)       -> PushVerification   # 驗簽，見 §C.4
  def parse_push(account:, raw_request:)        -> [TrackingEvent]
  # K8–K13 對應方法在 capability 宣告 supported: false 時，**不需實作**；
  # 基底類別的預設實作一律 raise Carrier::CapabilityNotDeclared——不得回 nil。
end
```

**四條介面級硬規則**

1. **介面上不得出現任何一家物流商特有的概念。** `service_code` 是通用的（每家都有服務分級），`serviceCode`（順豐的分派鍵）、`msgDigest`、`labelStockType` 這類**廠商私有欄位一律留在 adapter 內部**。判準：把 `sf_express` 換成 `dhl_express`，介面簽名一個字都不用改。
2. **回傳型別一律是我方定義的結構，不得是物流商的原始回應。** 但 `raw_error_code` / `raw_error_message` 兩欄**必須**原樣保留——客服要靠它跟物流商對話，V 編號要靠它覆核。
3. **所有金額欄位一律 `*_cents` 後綴且為 Integer。** adapter 內部負責把物流商回傳的十進位字串轉成 cents（§G.3），**轉換失敗一律 raise，不得回 0**。
4. **`verify_push` 失敗一律拒收，且不得回 200。** 見 §C.4。

---

## B. 能力矩陣

### B.1 矩陣（本輪可填的部分）

**填值規則**：`✅` ＝ 官方文檔確認支援；`❔` ＝ 疑似支援但未覆核（附 V 編號）；`❌` ＝ 官方確認不支援；`—` ＝ **本輪未查證，pack 不得 enable**。
**🔴 `—` 不是 `❌`。** 這張表本身就是 §A.3 原則的體現：空格代表「不知道」，不代表「沒有」。

| 能力 | `sf_express` | `dhl_express` | `ups` | `fedex` | `manual` |
|---|---|---|---|---|---|
| K1 `rate_quote` | ❔ V-37（`EXP_RECE_QUERY_SFWAYBILL` 語義未覆核） | ✅ Rating | ❔ V-45 | ❔ V-45 | ❌（宣告 false，改靜態運費表） |
| K2 `shipment_create` | ✅ `EXP_RECE_CREATE_ORDER` | ✅ Shipment | ❔ V-45 | ❔ V-45 | ❌（手填單號） |
| K3 `label_render` | ❔ **介面已確認** `COM_RECE_CLOUD_PRINT_WAYBILLS`（SF-20）；欄位／格式／尺寸待查 **V-39** | ✅ Shipment／Get Image | ❔ V-45 | ❔ V-45 | ❌ |
| K4 `shipment_void` | ❔ **動作已確認**（`dealtype=2`，SF-14）；`frees_number`／`billed_if_unused`／`window_hours` **官方沉默** **V-42** | — V-45 | ❔ Void Shipment V-45 | ❔ Cancel Shipment V-45 | ❌（無號可銷） |
| K5 `shipment_cancel` | ✅ `EXP_RECE_UPDATE_ORDER`／舊世代 `OrderConfirmService` `dealtype ∈ {1,2}`（**值域已結案**，SF-14） | ✅ Pickup 取消 | ❔ V-45 | ❔ V-45 | ❌ |
| K6 `tracking_pull` | ✅ `EXP_RECE_SEARCH_ROUTES`（批次上限 10，SF-18） | ✅ Tracking | ❔ V-45 | ❔ V-45 | ❌ |
| K7 `tracking_push` | ❔ 介面存在，但**官方確認無驗簽欄位**且事件碼值域未列舉（SF-16／SF-17）**V-47** | — V-45 | — V-45 | — V-45 | ❌ |
| K8 `pickup_schedule` | ❔ `EXP_EXCE_CHECK_PICKUP_TIME` V-37 | ✅ Pickup | ❔ V-45 | ❔ V-45 | ❌ |
| K9 `cod` | — **V-48**（香港可用性與上限未知） | — V-45 | — V-45 | — V-45 | ❌ |
| K10 `customs_doc` | ❔ 國際件與國內件**同一支介面**，有 `d_deliverycode`／證件欄位／`HKD` 幣別（SF-19）；`express_type` 值域仍缺 **V-44** | ✅ Invoice／Landed Cost | — V-45 | — V-45 | ❌ |
| K11 `service_point` | ❔ `EXP_RECE_QUERY_GIS_DEPARTMENT` V-37 | ✅ Service Point | — V-45 | — V-45 | ❌ |
| K12 `address_validate` | — | ✅ Address | — V-45 | — V-45 | ❌ |
| K13 `billing_reconciliation` | — V-42 | — V-45 | — V-45 | — V-45 | ❌ |

**這張表的兩個結論**

1. **本輪唯一能 enable 的 pack 仍是 `manual`。** 它十三項全部宣告完整（全 `false` ＋ reason），因此通過 §A.3 的 gate。
   <!-- 依 2026-08-12 第二輪查證更新計數，原文：「`sf_express` 有 5 個 `—`，`dhl_express` 有 5 個 `—` ⇒ 兩者皆不得 enable。」 -->
   `sf_express` 本輪由 **5 個 `—` 降到 3 個**（K9／K12／K13；K4 與 K10 升為 `❔`），`dhl_express` 仍 5 個 `—` ⇒ **兩者皆不得 enable**。這是規格刻意的結果，不是缺漏——沒查證完就上線才是缺漏。
   > **降到 3 個不代表接近可上線。** `❔` 一樣擋 gate（§A.3 要的是**非 null 的宣告**，`❔`＝疑似＝仍是 null）。真正的距離要看 `enable_gate` 的長度，而 `sf_express` 的 gate 本輪**從 7 項變成 8 項**（結案 V-38、新增 V-41／V-51）——**查得越細，已知的洞越多**。這是正常的，不是退步。
2. **`manual` pack 必須先做，而且它不是玩具。** 它是所有 carrier 尚未接通時的正式營運路徑（商家自己去物流商後台下單、回填單號），也是任何 carrier 故障時的降級目的地（§F.5）。

### B.2 能力缺席時 UI 顯示什麼（逐項，給前端照做）

**通則三條**（違反任一即為 UI bug）：

- **不得顯示點了會失敗的按鈕。** 能力缺席 ⇒ 按鈕**不渲染**，不是渲染成 disabled 後跳錯誤。
- **不得無聲消失。** 每一個因能力缺席而不渲染的區塊，**必須**在原位留一行說明文字，告訴商家「為什麼這裡沒有東西」以及「該去哪裡做」。這是 56「documented_no_op」原則在 UI 層的對應。
- **說明文字的內容取自 pack 的 `reason` 欄位**，不得在前端硬編。

| 缺席能力 | 畫面位置 | 顯示什麼 | 顯示什麼是錯的 |
|---|---|---|---|
| K1 `rate_quote` | 結帳頁運費區 | 靜態運費表的名稱與金額（`HK$` ＋ 兩位小數） | ❌ 顯示「即時運費」「預估運費」字樣 |
| K1 `rate_quote` | 後台出貨畫面 | 運費欄留空並註「本物流商不提供試算，實際運費以月結帳單為準」 | ❌ 顯示 `HK$0.00` |
| K2 `shipment_create` | FO 卡「建立出貨」對話框 | 只留「物流商」「追蹤號碼」「追蹤網址」手填欄 | ❌ 顯示灰掉的「向物流商下單」按鈕 |
| K3 `label_render` | 出貨完成後的運單卡 | 「本物流商不支援線上取單，請至物流商系統列印」＋ 物流商後台連結 | ❌ 顯示「列印面單」按鈕後回錯誤 |
| K4 `shipment_void` | 運單卡 | 「本物流商不支援線上銷號」＋ **「已記入待人工銷號清單」**（連到 §D.5 的佇列） | ❌ 什麼都不顯示 |
| K5 `shipment_cancel` | 運單卡 | 「已交寄的運單需聯繫物流商取消」 | ❌ 顯示「取消運單」按鈕 |
| K6＋K7 皆缺 | 訂單時間軸 | 「本物流商不提供追蹤資料，請以追蹤號碼至物流商官網查詢」＋ 官網連結 | ❌ 空白的時間軸 |
| K8 `pickup_schedule` | 出貨畫面 | **不渲染**「預約取件」區塊 ＋ 一行「本物流商未開通線上預約」 | ❌ 渲染空的預約表單 |
| K9 `cod` | 結帳頁 | COD 付款方式**不出現** | ❌ 出現後在提交時報「此配送方式不支援貨到付款」 |
| K10 `customs_doc` | 結帳頁 | 跨境地址下該配送方式**不出現**（§H.2 判不可服務） | ❌ 允許下單後在出貨時才卡住 |
| K11 `service_point` | 結帳頁選點地圖 | 該 carrier 不出現在選點來源清單 | ❌ 出現但地圖無資料 |
| K12 `address_validate` | 出貨畫面 | 不做預檢，不顯示任何「地址已驗證」標記 | ❌ 顯示未經驗證的綠勾 |
| K13 `billing_reconciliation` | 對帳頁 | 「本物流商未提供對帳檔，銷號閉環需人工核對」 | ❌ 顯示 0 筆差異的對帳報表 |

---

## C. 與 FulfillmentOrder 的接合

> **本節的一切以 46a 為權威。** 我方不得因為接了 carrier 就改動 FO 狀態機——carrier 是掛在狀態機**旁邊**的外部系統，不是狀態機的一部分。

### C.1 哪些 FO 轉移會呼叫 carrier

**答案：一個都沒有。** 這不是文字遊戲，是本節最重要的結論。

16-F3.1 的 T1–T16 全部是**我方 DB 內的狀態轉移**，全部在 transaction 內完成。carrier 呼叫**不掛在任何一條轉移上**，而是掛在轉移**之前**的一個獨立編排流程（§F.3 的 `ShipmentIntent`）。

正確的時序（以「商家按下建立出貨」為例）：

```
① 商家按「建立出貨」
       ↓  DB txn #1（極短，不打網路）
   shipmentIntentCreate → shipment_intents 落一列 status=PENDING
   FO 狀態：**不變**（維持 OPEN / IN_PROGRESS）
       ↓  txn 已提交，job 接手
② Solid Queue job 取出 intent → status=IN_FLIGHT
       ↓  **外部 IO，此時不持有任何 DB 鎖、不在 transaction 內**
   adapter.create_shipment(...) → ShipmentResult
       ↓
③ 依 outcome 分流（見 §C.2）
   success ⇒ DB txn #2：寫 waybills → 呼叫既有的 fulfillmentCreate service
             （FO 走 16-F3.1 的 T9/T10，庫存 committed−/on_hand−，訂單狀態重物化，outbox）
             → intent status=SUCCEEDED
```

**為什麼一定要這樣**：

1. **鐵律 5**：transaction 內禁外部 IO。若把 `create_shipment` 寫進 `fulfillmentCreate` 的 transaction，一次物流商逾時就會持有 FO 的行鎖 30 秒 ⇒ 連線池耗盡 ⇒ 全站掛。11 §2 已把這條列為「最常見的生產事故源」。
2. **語義**：`fulfillmentCreate` 的前提是「貨已經要走了、單號已經有了」。46a 的 `FulfillmentInput.trackingInfo` 是**輸入**不是輸出——先有號才有 fulfillment，順序不能顛倒。
3. **可恢復性**：把外部呼叫抽成有狀態的 intent，`UNKNOWN` 才有地方掛（§F.4）。若它只是 transaction 裡的一行，逾時之後系統對「到底取到號沒有」完全失憶。

### C.2 carrier 回傳失敗時 FO 進什麼狀態

**總則：FO 狀態由 46a 的狀態機決定，carrier 失敗不得發明新狀態，也不得借用語義不符的既有狀態。**

| carrier outcome | intent 狀態 | **FO 狀態** | 附帶動作 | 為什麼不是別的 |
|---|---|---|---|---|
| `success` | `SUCCEEDED` | 依 16-F3.1 **T9**（全部品項 ⇒ `CLOSED`）或 **T10**（部分 ⇒ 不變） | 建 `fulfillments`、扣庫存、outbox | — |
| `business_rejected`（地址類） | `FAILED` | **不變**，但**建議**商家執行 `fulfillmentOrderHold`，`reason = INCORRECT_ADDRESS` | 在 FO 卡顯示紅色錯誤條 ＋ 一鍵套用該 hold | `INCORRECT_ADDRESS` 是 46a 八個合法 hold reason 之一（16-F3.1(f)），**不需新增 enum 值** |
| `business_rejected`（庫存／材積／服務不符） | `FAILED` | **不變** | 錯誤條顯示 `raw_error_message` | 同上；材積不符對應不到 hold reason ⇒ **不 hold**，只報錯 |
| `transient_error` | 退避重試中，逾 `retry_max` 後 `FAILED` | **不變** | 重試期間 FO 卡顯示「處理中」但**動作列照常可用** | 暫時性失敗不是業務事實，不該污染 FO |
| `unknown` | `UNKNOWN` | **不變** | 進 §F.4 回查佇列；FO 卡顯示黃色「與物流商狀態確認中」；**`CREATE_FULFILLMENT` 動作暫時抑制**（見下方註） | 見 §F.4 |

**🔴 三條明令禁止**（每一條都是把 46a 語義用錯的典型）：

1. **carrier 失敗不得讓 FO 進 `INCOMPLETE`。** `INCOMPLETE` 是 `fulfillmentOrderClose` 的結果（46a:241 逐字「Marks in-progress order as incomplete」），語義是「商家決定這張履行單不做了」。物流商 API 報錯是**技術事件**，不是商家決定。混用會讓 `INCOMPLETE` 這個狀態失去意義。
2. **carrier 失敗不得讓 FO 進 `CANCELLED`。** `CANCELLED` 是終態，且依 46a:236／46a:354 會**產生一張替代 FulfillmentOrder**（16-F3.2）。一次 API 逾時就多一張 FO，訂單頁會被垃圾單淹沒，而且 16-F3.2 的數量不變量會被反覆擾動。
3. **carrier 失敗不得回滾已成功的 `fulfillmentCreate`。** 因為到那一步時貨與號都已經產生了，回滾 DB 不會把號收回來。要撤銷只能走 §D.5 的銷號流程。

> **關於 `UNKNOWN` 期間抑制 `CREATE_FULFILLMENT`**：這是 `supportedActions` 的**計算輸入多了一項**，不是多了一個 action 值。16-F3.1(e) 第 1 列的出現條件由
> 「`status ∈ {OPEN, IN_PROGRESS}` 且有剩餘量」
> 改為
> 「`status ∈ {OPEN, IN_PROGRESS}` 且有剩餘量 **且該 FO 無 `UNKNOWN` 狀態的 shipment intent**」。
> 理由：`UNKNOWN` 代表「可能已經有一張運單在路上了」，此時讓商家再按一次出貨就是製造第二張。這條與 46a:341 的慣例一致——`supportedActions` 本來就是「伺服器端的前置條件檢查」，把外部系統的未決狀態納入前置條件是它的正當用法。**十二個 enum 值一個都不新增。**

### C.3 carrier 不是 fulfillment service（本節請完整讀完再實作）

**這是最容易做錯的一條，而且做錯了要改 schema。**

46a 的模型裡，`requestStatus` 這條軸的存在前提是「這張 FO 被**指派**給了一個 fulfillment service」，而 46a:247 逐字定義 `UNSUBMITTED` 是「the only valid request status for fulfillment orders **not assigned to a fulfillment service**」。16-F3.1(d) 已經把它固化成不變量：

```
assigned_fulfillment_service_id IS NULL  ⟹  request_status = 'UNSUBMITTED'
```

**問題**：接了順豐之後，FO 算不算「指派給 fulfillment service」？

**裁定：不算。** 判準是**誰決定要不要履行、誰持有庫存**：

| | fulfillment service（3PL／代發倉） | carrier（物流商） |
|---|---|---|
| 誰持有庫存 | **它** | 我方 |
| 誰決定接不接這張單 | **它**（可 accept／reject） | 不決定——它只負責把已包好的箱子運走 |
| 我方角色 | 發出「請求」，等對方回應 | 自己出貨，只是叫車 |
| 對應 46a 軸 | `requestStatus` 全軸 | **恆 `UNSUBMITTED`** |

**四個直接後果（實作必須照做）**

1. **`carrier_accounts` 與 `fulfillment_services` 是兩張不同的表，不得合併，也不得讓 carrier 寫進 `assigned_fulfillment_service_id`。**
2. **`REQUEST_FULFILLMENT` 與 `REQUEST_CANCELLATION` 不會因為接了 carrier 而出現。** 16-F3.1(e) 第 2、4 列的出現條件（「已指派 service 且 requestStatus = UNSUBMITTED」／「requestStatus ∈ {SUBMITTED, ACCEPTED}」）**維持原樣**，carrier 不影響它們。
   ⇒ **「取消運單」絕對不是 `fulfillmentOrderSubmitCancellationRequest`。** 它是本檔新增的 `shipmentVoid` / `shipmentCancel`（§I），作用對象是 `waybills` 不是 `fulfillment_orders`。把兩者接在一起會讓自營出貨的 FO 離開 `UNSUBMITTED`，直接違反上面那條不變量。
3. **`EXTERNAL` 不得被 carrier 借用。** 46a:275 定義 `EXTERNAL` 是「Opens an external URL... paired with `FulfillmentOrderSupportedAction.externalUrl`」，16-F3.1(e) 第 12 列的出現條件是「由 fulfillment service 提供 `externalUrl` 時」。carrier 既然不是 fulfillment service，就**不得**把「開啟順豐運單頁」塞進 `EXTERNAL`。
   **carrier 的外部連結放哪裡**：放在**運單卡**（`waybills` 的渲染單元）的 `carrier_portal_url` 欄位，與 `supportedActions` 完全無關。
   **理由**：`supportedActions` 是伺服器計算、前端純渲染的契約（46a:372、16-F3.1(e) 鐵律）。往裡面塞語義不同的值，等於在這個契約上開後門；一旦開了，前端就必須知道「這個 EXTERNAL 是 3PL 的還是 carrier 的」，那就是把 guard 邏輯漏回前端。
4. **未來真的接 3PL 時，3PL 自己會有 carrier 選擇權**，那是 3PL 內部的事，我方**不**為其建 `carrier_accounts`。兩層不互相穿透。

### C.4 追蹤事件的接收（K6／K7）

**K7 推送路徑**（順豐屬此類，`EXP_RECE_REGISTER_ROUTE`）：

1. 推送端點為 **per shop per carrier** 的獨立路徑，帶不可猜測的 token：`/carriers/:carrier_code/push/:endpoint_token`。**不得**用單一全域端點再靠 payload 裡的 shop 識別——那等於讓任何人都能對任意租戶灌事件。
2. **先驗簽，後解析。** `adapter.verify_push` 失敗一律回 **401**，不得回 200。
   <!-- 依 2026-08-12 第二輪查證改寫。原文：「順豐推送的驗簽方式本輪未取得（V-47）。在 V-47 結案前，sf_express 的 K7 宣告雖為 ✅（介面存在），但 push_verification 子欄位為 null ⇒ 依 §A.3 該 pack 不得 enable。禁止先上一個『不驗簽照收』的版本。」 -->
   > 🔴 **V-47 的答案比「查不到」更糟：查到了，而答案是「沒有」。**
   > 順豐官方規範對舊世代的 `RoutePushService` **完全沒有定義任何驗簽欄位**——接收方只被要求回一段 XML 且結果只能是 `OK` / `ERR`；失敗時順豐會重推全部資訊，但**未載明重送次數與間隔**（SF-16）。新世代 `EXP_RECE_REGISTER_ROUTE` 的推送是否附簽章，**仍未取得**。
   >
   > **這改變了處置方向，不是放寬。** 原文假設「等查到驗簽方式再實作」；現在必須假設**可能根本沒有驗簽方式可查**。因此：
   >
   > | 原處置 | 新處置 |
   > |---|---|
   > | `push_verification = null` ⇒ 等 V-47 | `push_verification` **改為必須明確二選一**：`{ mode: "carrier_signature", … }` 或 `{ mode: "none", compensating_controls: [...] }` |
   > | 「禁止不驗簽照收」 | **仍然禁止「裸接」，但允許「宣告無載體簽章 ＋ 補償控制」** |
   >
   > **`mode: "none"` 時的補償控制為必填，且至少要有這四項**（缺一即 pack 不得 enable）：
   > 1. **不可猜測的 per-shop-per-carrier 端點 token**（第 1 點已規定），且 token 可輪替；
   > 2. **來源 IP 允許清單**（值取 `limits.carrier.tracking.push_source_ip_allowlist_required`，清單本身屬 carrier account 設定，非本檔常數）；
   > 3. **運單號歸屬校驗**：推送的 `waybill_number` 必須已存在於**該 `shop_id` 的 `waybills`**，否則丟棄並記一列——這是防止他人對任意租戶灌事件的最後一道，也是**唯一一道不依賴任何外部秘密的**；
   > 4. **推送只能推進追蹤時間軸，不得觸發任何金流或狀態機躍遷**（不得據以標記已送達而觸發撥款）。
   >
   > **為什麼 (3) 是關鍵**：沒有簽章時，`waybill_number` 本身就是那個共享秘密——它由順豐發放、不可預測、且我方已知道它屬於哪個租戶。這不是強驗證，但它把攻擊面從「任何人可對任意租戶灌任意事件」縮到「必須先知道一個真實運單號才能對**該運單**灌事件」。**必須寫在規格裡，否則實作者在沒有簽章可用時只會直接放行。**
   >
   > ⚠️ 順豐的 `event_code_vocabulary` **仍未取得**：官方規範未列舉路由操作碼，只說「可在文檔中心查看」，文中僅出現示例 `50`（上門收件）、`922`（簽單返還單號）（SF-17）。⇒ `sf_express.tracking_push.event_code_vocabulary` 維持 `null`，**pack 仍不得 enable**（V-47 未結案）。**不得**拿這兩個示例值當值域。
3. **接收即入 outbox，不即時處理**（鐵律 5：事件走 outbox）。HTTP handler 只做：驗簽 → 寫 `carrier_push_events`（原始報文 ＋ `received_at`）→ 回 200。解析與狀態更新由 job 做。
4. **冪等**：以 `(shop_id, carrier_code, waybill_number, carrier_event_code, carrier_event_at)` 建唯一索引去重。物流商重送同一事件是常態，**不得**產生兩列時間軸。
5. **事件映射**：`TrackingEvent` 的 `status` 一律映射到我方既有的 fulfillment event 值域，**不得**把物流商的原始代碼直接顯示給買家。特別注意 16-F3.3(c) 已經定下的一條：**到店領取 ≠ 已送達**，需要 `READY_FOR_PICKUP` 這個獨立事件；carrier 的「已到達自提點」事件必須映到它，**不得**映到 `DELIVERED`。

**K6 輪詢路徑**：間隔取 `limits.carrier.tracking.poll_interval_seconds`，並在運單進入終態（已簽收／已退回）後**停止輪詢**——否則每張歷史運單都會永久佔用配額。

### C.5 預約取件（K8）

預約取件的對象是**批次**（一個地點、一個時間窗、多張運單），不是單張運單。因此它掛在 `carrier_pickups` 表而非 `waybills`，且：

- 預約成功後**不改變**任何 FO 狀態（取件是物流作業，不是履行事實）。
- 取消預約**不影響**已產生的運單號——取消取件不等於銷號，這兩件事分開（§D.5）。混淆這一點會導致「以為取消了取件就不用付運單費」。

---

## D. 運單（waybill／面單）

### D.1 取號與打印是兩件事，必須分開建模

多數實作把「下單」「取號」「印面單」當成一個動作，因為對某些物流商它們確實在同一支 API。**但它們的失敗模式與成本結構完全不同**：

| | 取號（K2 的產物） | 打印（K3 的產物） |
|---|---|---|
| 產生什麼 | 一個**全域唯一、由物流商發放**的號碼 | 一個檔案 |
| 可否重做 | **不可**——重做就是第二個號 | **可**——同一個號可重複產檔 |
| 有無成本 | **有**（見 §D.5） | 通常無 |
| 失敗的代價 | 財務性 | 可重試 |

⇒ **資料模型必須兩張表**：

```
waybills(shop_id, fulfillment_order_id, shipment_intent_id, carrier_code, carrier_account_id,
         waybill_number, sub_waybill_numbers JSON, service_code,
         status, allocated_at, handed_over_at, voided_at,
         carrier_reference, carrier_portal_url, billed_freight_cents, ...)
         -- 唯一索引 (shop_id, carrier_code, waybill_number)；複合索引以 shop_id 開頭（鐵律 2）

waybill_labels(shop_id, waybill_id, format, size_code, checksum, storage_key,
               rendered_at, reprint_seq, reprint_reason, rendered_by_staff_id)
         -- 一張運單多個 label 列＝重印歷史，見 §D.4
```

### D.2 面單格式與尺寸

**我方支援的格式值域**（`limits.carrier.label.formats_allowed`）：`pdf` / `zpl` / `png`。

| 格式 | 用途 | 我方處理 |
|---|---|---|
| `pdf` | 一般雷射／噴墨印表機、批次合併 | 直接存檔、可合併多頁（§D.3） |
| `zpl` | Zebra 熱感標籤機**指令流**（不是圖片） | **原樣位元組保存，禁止任何轉碼或字串正規化**——ZPL 是指令，改一個位元組就印歪 |
| `png` | 預覽、無驅動環境 | 只作預覽，**不得**作為正式交寄依據 |

**三條硬規則**

1. **格式支援度是 per carrier 宣告的**（`capabilities.label_render.formats`），不是全域假設。「有的物流商只給 PDF 不給 ZPL」正是本檔要處理的常態。商家在後台選了 ZPL 但 carrier 只宣告 `[pdf]` ⇒ **設定期就擋下**（回 `userErrors{code: LABEL_FORMAT_UNSUPPORTED}`），不是等到列印時才失敗。
2. **尺寸用代碼不用毫米數。** 尺寸是物流商定義的離散值域（各家代碼不同），我方存 `size_code` 字串 ＋ pack 宣告的 `sizes[]` 清單。**不得**讓商家自填任意毫米數——面單尺寸不對，物流商可拒收。
3. **面單檔案是 PII 載體**（含收件人姓名、地址、電話）。存 Active Storage 私有 bucket，取用一律簽名連結，有效期取 `limits.carrier.label.signed_url_ttl_seconds`；保存期取 `limits.carrier.label.retention_days`，到期由 purge 任務刪除（對應 11 §0 維度 7）。**簽名連結不得寫進日誌。**

<!-- 依 2026-08-12 第二輪查證改寫本警示框。原文：「順豐的面單格式本輪未取得（V-39）：……官方頁面為 JS 渲染取不到。是否支援 ZPL 亦未知。」 -->

> ⚠️ **順豐面單：介面已確認，欄位仍未取得（V-39 縮小，未結案）**
> **已確認（官方）**：介面名為「雲打印面單打印2.0接口」、服務代碼 `COM_RECE_CLOUD_PRINT_WAYBILLS`、歸類於「面單類API」；同族有「ISV刪除自定義模板接口」`COM_RECE_CLOUD_CUSTOMTEMPLATE_DELETE`，可知**模板是可自訂的資源**（SF-20）。
> **仍未取得（官方）**：請求／回應欄位、回傳形態（URL／base64／二進位）、模板代碼與尺寸的值域。
> **僅有第三方佐證（SF-22，且標的為 1.0 版）**：輸出為 PDF；尺寸疑為 `100×150`／`100×180`／`100×210`／`76×130`（國內）與 `100×150`／`100×210`（國際）。**這些值不得寫進 pack**，只作為「值域大概長什麼樣」的預期，供實作者拿到官方文檔時對照。
> ⇒ `sf_express` 的 `label_render.formats` 與 `sizes` 維持 `null`，pack 不得 enable。

> 🟢 **V-40（我方要不要接 ZPL 指令流）——本輪可以決策了，不必等 V-39 結案。**
> **證據**：沒有任何來源顯示順豐雲打印介面本身輸出 ZPL；第三方文檔明列輸出為 PDF；聚合商雖能給 ZPL，但那是**聚合商轉檔**的產物（SF-23）。
> **決策（我方架構決策，不是順豐事實）**：**`zpl` 留在 `limits.carrier.label.formats_allowed` 裡，但不為順豐建任何 ZPL 路徑。**
> 理由分兩層，必須分開看：
> 1. **抽象層**：ZPL 支援是 `label_render.formats` 的一個值，DHL／UPS／FedEx 普遍原生支援。為了一家不支援就把 `zpl` 從值域拿掉，等於讓抽象層遷就單一 pack——正是 §0.2 原則 1 要防的事。**上面「ZPL 原樣位元組保存」那條規則照留**，它是格式的性質，與哪家支援無關。
> 2. **順豐 pack**：`sf_express.label_render.formats` 依 §A.3 維持 `null`（**不是** `["pdf"]`，因為官方欄位表還沒到手；也**不是** `[]`）。
>
> **對「我方運單打印要不要接 ZPL 指令流」這個問題的直接回答**：**首發不接。** 首發物流商若為順豐，走 PDF 就夠；ZPL 的位元組級處理（不轉碼、串接以 `^XA`…`^XZ` 為單位）**規格先寫好、程式後做**，等到第一個原生輸出 ZPL 的 pack（DHL／UPS／FedEx）真的要上線時再實作。**不要為了一個沒有 pack 會用到的格式先寫熱感印表機驅動路徑。**

### D.3 批次打印

**規格**：

- 單次 API 呼叫的運單數上限：`limits.carrier.label.batch_max_per_call`（預設 50）。**超過即分批**，由編排層切，不得讓商家自己算。
- 單一批次作業的總上限：`limits.carrier.label.batch_max_per_job`（預設 500）。超過回 `userErrors{code: TOO_LONG}`（沿用 28 §通用碼，不自造新碼）。
- **批次是非同步的**：回傳 `job{id, done}`，比照 28 對 `orderCancel` 的既有慣例（28:116 已確立非同步 mutation 回 job 的形狀）。
- **部分失敗必須逐張回報。** 批次 20 張有 3 張失敗 ⇒ 17 張的檔案照給、3 張列在 `failures[{waybillId, code, message}]`。**不得**整批回滾——已經產出的檔案回滾也收不回號。
- **PDF 合併**在我方端做（同一批 → 一個多頁 PDF），**ZPL 串接**為原樣位元組相接（以 `^XA`…`^XZ` 為單位，中間不插任何字元）。
- **合併不得跨租戶**：批次的所有 waybill 必須同 `shop_id`，service 層驗證（鐵律 2）。這是把別家客戶的地址印給另一家的唯一入口，必須有測試。

### D.4 重印與作廢的規則

**重印（reprint）**：

| 規則 | 內容 | 理由 |
|---|---|---|
| 允許與否 | 由 pack 宣告 `label_render.reprint_allowed` | 有的物流商禁止重印或對重印計費 |
| 必填原因 | `limits.carrier.label.reprint_requires_reason: true` ⇒ 重印時必須選原因（列印失敗／標籤破損／換箱） | 重印是內控關注點；沒有原因就無法查「為什麼這個倉庫每天重印 200 張」 |
| 留痕 | 每次重印在 `waybill_labels` 新增一列（`reprint_seq` 遞增），**不得覆蓋原列** | 稽核要看得到第幾次印、誰印的 |
| 號碼 | **重印一律使用同一個 `waybill_number`** | 重印產生新號就不叫重印，叫重複取號（＝多付一次錢） |

**作廢／銷號（void）**：見 §D.5，因為它不只是一個動作，是一套帳。

### D.5 運單號是有成本的資源——銷號帳（本檔最容易被漏掉的一節）

<!-- 依 2026-08-12 第二輪順豐查證改寫本節的立論基礎。原立論：「取號＝向物流商借了一個有價的資源。借了不用，要還；不還，物流商照樣計費。」該句被當成事實陳述，但官方文檔對計費完全沉默（SF-15）。機制（(a)–(e)）全部保留，(a) 前新增立論說明，(f) 為新增。 -->

> **一句話（改寫後）**：**取號＝燒掉一個永不回頭的識別。識別一定回不來（官方明載）；錢會不會白花，看合約（官方沉默）。兩者都要記帳，但只有後者決定告警等級。**

**(a0) 本節的立論被換過，先讀這一段再往下（否則會誤判哪些規則可以放寬）**

原文的立論是「取了不用，物流商照樣計費」，並把它當**事實**。**本輪查證後這個事實地位被撤銷**：

| 命題 | 官方怎麼說 | 現在的地位 |
|---|---|---|
| 取消後客戶訂單號（`orderid`）**不得重複使用** | **明載**（SF-14） | ✅ **事實**，可據以寫死實作 |
| 取消動作存在，值域僅 `dealtype ∈ {1 確認, 2 取消}`；重覆取消回 `8019` | **明載**（SF-13、SF-14） | ✅ **事實** |
| 順豐**運單號**（`mailno`）取消後是否回收、可否重發 | **通篇未提**（SF-15） | ❓ 未知 ⇒ `frees_number: unknown` ⇒ **一律不重用** |
| **取號未使用是否照樣計費** | **通篇未提**（SF-15） | ❓ 未知，且**不會由 API 文檔回答**——屬月結合約 |
| 可銷號的時間窗 | **通篇未提**（SF-15） | ❓ 未知 ⇒ `window_hours: null` |

**所以這一節為什麼還在？** 因為它換了一根更硬的樑：

> **不是「號有價所以要記帳」，而是「號不可回收所以要記帳」。**
> 就算最後查明順豐對未使用的號**一毛都不收**，(b) 的五個場景、(c) 的閉環不變量、(e) 的待銷號佇列**一條都不能拿掉**——因為場景 4（換物流商／換箱重取號）造成的是**同一張 FO 掛著兩個都無法回收的識別**，那是**資料正確性事故**，與計費無關：出貨掃描時會有兩張面單對得上同一批貨，倉庫拿哪一張都「看起來對」。
> **計費與否只改變 (d) 的告警等級，不改變任何機制的存廢。** 這正是原文把 `billed_if_unused` 設計成 pack 級宣告（而非全域常數）的價值——**當初的機制設計是對的，錯的只是那句被寫成事實的旁白。**

🔴 **據此撤回一條全域斷言**：`limits.carrier.waybill.number_is_billable_resource: true` 原本是一句**跨所有物流商的事實斷言**，本輪改為 `policy_default`（我方保守**姿態**，不是物流商**事實**），權威一律回到 pack 級的 `capabilities.shipment_void.billed_if_unused`。理由：一個全域 `true` 會讓實作者以為「計費」這件事已經查證過了。

**(a) 運單狀態機**（`waybills.status`）

| 值 | 中文 | 進入條件 | 是否可能已計費 |
|---|---|---|---|
| `ALLOCATED` | 已取號 | K2 `success` | **是（風險期從這裡開始）** |
| `LABEL_RENDERED` | 已產面單 | K3 成功 | 是 |
| `HANDED_OVER` | 已交寄 | 收到第一筆「已收件」追蹤事件，或商家手動標記 | 是（正常計費，這是我們要的） |
| `VOIDED` | 已銷號 | K4 `voided` | 否（正常結果） |
| `VOID_FAILED` | 銷號失敗 | K4 `refused` / `too_late` | **是（需人工）** |
| `VOID_MANUAL_REQUIRED` | 待人工銷號 | carrier 未宣告 K4，或逾 `window_hours` | **是（需人工）** |
| `ABANDONED_UNRESOLVED` | 逾期未結 | 超過對帳寬限期仍未落到終態 | **是（財務事故，告警）** |

終態：`HANDED_OVER`、`VOIDED`、`ABANDONED_UNRESOLVED`。

**(b) 觸發銷號的五個場景**（每一個都必須有對應的程式路徑，缺一個就是漏錢的洞）

| # | 場景 | 觸發點 | 處置 |
|---|---|---|---|
| 1 | 訂單在出貨後、交寄前被取消 | `orderCancel`（16-F4.2） | 對該訂單所有 `ALLOCATED`／`LABEL_RENDERED` 的運單發起 void |
| 2 | FO 被取消 | `fulfillmentOrderCancel`（T13） | 同上，範圍限該 FO |
| 3 | 商家主動撤銷出貨 | 16-F3 第 4 點的「取消出貨」 | 同上 |
| 4 | 換物流商 / 換箱重取號 | 新的 `shipmentIntentCreate` 指向同一 FO 且舊運單未交寄 | **舊號必須 void**；不 void 就 reject 新的取號請求 |
| 5 | **逾時未交寄** | nightly job：`ALLOCATED` 且 `allocated_at < now - limits.carrier.waybill.unused_void_after_hours` | 自動 void（有 K4）或入人工佇列（無 K4） |

> **場景 4 是最隱蔽的一個。** 「重新取號」在 UI 上看起來只是再按一次按鈕，實際上是多借了一個資源。硬規則：**同一張 FO 在同一時間最多只能有一張非終態運單**，DB 以部分唯一索引兜底：
> `UNIQUE (shop_id, fulfillment_order_id) WHERE status IN ('ALLOCATED','LABEL_RENDERED')`
> （MySQL 8 無部分索引 ⇒ 以產生欄位 `active_waybill_key`（非終態時＝`fulfillment_order_id`，終態時＝`NULL`）＋唯一索引實作。這是 11 §2 第 1 點「業務唯一性用唯一索引兜底」的直接應用。）

**(c) 銷號帳的閉環不變量**（nightly 對帳 job 斷言，與 16-F3.2 第 2 點的數量不變量同性質）

```
對每個 (shop_id, carrier_account_id, 日期區間)：
  Σ status=ALLOCATED 起算的所有運單
    ==  Σ HANDED_OVER  +  Σ VOIDED  +  Σ 仍在寬限期內的未結  +  Σ ABANDONED_UNRESOLVED

且： Σ ABANDONED_UNRESOLVED  ==  0        ← 這一項不為 0 就告警（財務事故）
```

**有 K13（對帳檔）時再加一條外部閉環**：
```
物流商帳單上的計費運單數  ==  Σ HANDED_OVER  +  Σ VOID_FAILED  +  Σ ABANDONED_UNRESOLVED
```
差異一律逐筆列出，**不得只比總數**。比對的冪等鍵沿用既有的 `limits.cod.settlement_idempotency_key` 形狀（`carrier` / `statement_id` / `row_no`），不另立一套。

**(d) 告警等級由 `billed_if_unused` 決定**

| pack 宣告 | 逾期未銷的等級 | 通知對象 |
|---|---|---|
| `billed_if_unused: true` | **P1 財務事故** | 店主 ＋ 平台營運 |
| `billed_if_unused: false` | P3 資料清理 | 僅記錄 |
| `billed_if_unused: null`（未宣告） | **pack 不得 enable**（§A.3） | — |

> ⚠️ **順豐是哪一種，本輪仍未取得**（**V-42**），但**理由變了**：不是沒抓到網頁，是**這件事不寫在 API 文檔裡**（SF-15）。`sf_express` 的 `shipment_void.billed_if_unused` 維持 `null`。
> **不得**因為「官方沒說會收錢」就填 `false`——**沉默不是否認**。這正是 §A.3 全篇在講的那件事。

**(e) UI 必須有一個「待銷號」佇列**，位置在後台出貨相關頁面，顯示：運單號、取號時間、逾期時長、金額風險（若 pack 宣告了單張運單費率）、一鍵銷號／標記已人工處理。**沒有這個畫面，上面所有規則都不會被執行。**

**(f) 客戶側識別（`client_reference`）一律用後即棄——本輪新增，直接來自 SF-14**

順豐官方明載：**訂單取消之後，客戶訂單號不得重複使用。** 這條看似瑣碎，卻打穿了一個很自然的實作直覺：「這單失敗了，用同一個單號重試一次」。

| 規則 | 內容 |
|---|---|
| **識別絕不重用** | 送給物流商的客戶側識別（`client_reference`）**每次取號嘗試都必須是新的**，取 `shipment_intents.id`（§F.4 前提 1 已如此規定）。**同一個 intent 重試時沿用同一個識別；一旦該 intent 落到 `FAILED` 或該運單被 void，就必須開新 intent、換新識別。** 對應 `limits.carrier.shipment_intent.client_reference_reuse_forbidden: true` |
| **為什麼不能只靠冪等鍵** | 我方的 `idempotency_key` 擋的是「同一次請求被送兩遍」；這裡擋的是「**不同次**請求想借用同一個識別」。兩者是不同的東西，§E.2 的兩層模型必須各管各的 |
| **DB 兜底** | `waybills` / `shipment_intents` 對 `(shop_id, carrier_account_id, client_reference)` 建唯一索引。**重用即撞索引**，不是靠程式自律（11 §2「業務唯一性用唯一索引兜底」） |
| **對回查的影響** | 因為識別不重用，§F.4 的回查結果**沒有歧義**：查到就是這一次 intent 的結果，不可能撈到上一次的。**若識別可重用，整個 `UNKNOWN` 回查機制就是不可靠的**——這是 SF-14 意外替我方背書的一點 |

**(g) V-42 怎麼結案（它不會自己結）**

V-42 是本檔唯一一個**不可能由公開文檔結案**的 V 編號。處置：

| 動作 | 由誰 | 產出 |
|---|---|---|
| 向順豐商務／月結窗口以書面確認三件事：①未使用之運單號是否計費 ②可銷號的時間窗 ③銷號後 `mailno` 是否回收 | 商務 | 一封書面回覆，存檔並在 §附錄 B 補一列（來源＝合約／書面回覆，日期） |
| 在拿到書面回覆前的**營運上可行的過渡**：把 `sf_express` 的 `shipment_void` 宣告為 `supported: false` ＋ `reason: "銷號機制未經合約確認"`，讓所有順豐運單的逾期未交寄一律進 **`VOID_MANUAL_REQUIRED`** 人工佇列 | 實作 | pack 可通過 §A.3 的 gate（因為**宣告完整**），但銷號走人工 |

> **(g) 的第二列是本節唯一放寬的地方，且它並不違反 §A.3。** §A.3 要求的是「**宣告**完整」，不是「**支援**完整」——`supported: false` ＋ 非空 `reason` 是合法宣告。差別在於：`null`（沒人想過）⇒ 擋 pack；`false` ＋ reason（想過了，決定走人工）⇒ 放行，但必須有 (e) 的佇列接住。
> ⚠️ **但這條過渡只解 V-42。** `sf_express` 仍被 V-39／V-40／V-41／V-43／V-44／V-47／V-48／V-51 擋著，**本輪依舊不可 enable**。

---

## E. 冪等（鐵律 5）

### E.1 補進 `idempotency.required_for` 的四支 mutation

CLAUDE.md 鐵律 5 原本要求「訂單成立／退款／庫存調整」必帶 `idempotencyKey`，`config/limits.yml` 的 `idempotency.required_for` 已有 22 條。**本檔新增 4 條（共 26 條）**，理由是它們與既有 22 條**屬於同一類**：不可重試的外部副作用。

| 新增 mutation | 為什麼它必須有 key | 重試一次的代價 |
|---|---|---|
| `shipmentIntentCreate` | 觸發 K2 取號 | **多一張運單、多一筆運費**，且多出來的那張沒人會去銷 |
| `shipmentVoid` | 銷號是破壞性動作 | 若號碼已被物流商回收再發給別人，二次 void 可能作廢到不相干的單 |
| `shipmentCancel` | 取消運送安排 | 重覆取消在部分物流商會回錯誤碼，污染錯誤率指標與熔斷器 |
| `carrierPickupSchedule` | 預約取件 | **多一次上門取件**，部分物流商對空跑計費 |

**`business_unique_keys`**（沿用既有 `idempotency.business_unique_keys` 的形狀，作為 key 之外的第二道防線）：

| mutation | 業務唯一鍵 |
|---|---|
| `shipmentIntentCreate` | `fulfillment_order_id`, `carrier_account_id`, `service_code`, `package_fingerprint` |
| `shipmentVoid` | `waybill_id` |
| `shipmentCancel` | `waybill_id` |
| `carrierPickupSchedule` | `carrier_account_id`, `location_id`, `pickup_window_start`, `pickup_window_end` |

> `package_fingerprint` ＝ 對 `packages[]` 的正規化 JSON 取 SHA-256。**必須正規化欄位順序**——這是 11 §2.1(d) 已確立的規則（「Ensure consistent ordering of input fields to avoid fingerprinting mismatches」），對應 `limits.idempotency.fingerprint_normalize_field_order: true`。

### E.2 重試語義：我方冪等 vs 物流商冪等，是兩層

**必須分清楚，混在一起會漏。**

```
第一層：我方 API 的冪等（idempotency_keys 表，11 §2.1）
        擋的是：admin SPA 重送、使用者連點兩下、job 重排
        語義：同 key 同參數 ⇒ 回放（由當前 DB 狀態重建，非快照）
              同 key 異參數 ⇒ IDEMPOTENCY_KEY_PARAMETER_MISMATCH
              處理中     ⇒ IDEMPOTENCY_CONCURRENT_REQUEST

第二層：對物流商的請求冪等（各家機制不同，多數沒有）
        擋的是：我方 job 對物流商的重送
        順豐：以 orderid（客戶訂單號）去重，不是 requestID；且**去重的結果是報錯不是回放** —— 見下方 V-49
```

<!-- 依 2026-08-12 第二輪查證改寫。原文此處為：「⚠️ 順豐是否以 requestID 做伺服器端去重、重送同 requestID 的語義為何 —— 未取得（V-49）」 -->

> 🟢 **V-49 已實質結案，答案對我方的冪等策略是好消息也是壞消息。**
>
> | 問題 | 答案 | 出處 |
> |---|---|---|
> | `requestID` 是否被伺服器端去重？ | **沒有證據顯示是。** 官方 SDK 只把它示範成每次呼叫新產生的 UUID（`UUID.randomUUID()`），全篇**未賦予它任何去重語義**。⇒ **一律當作不去重** | SF-2、B-2 |
> | 那什麼被去重？ | **`orderid`（客戶訂單號）。** 官方明載 `orderid` 不唯一會導致下單失敗，錯誤碼 `8016` 重複下單 | SF-13、B-1、B-2 |
> | 重送同一 `orderid` 會回什麼？ | **回錯誤 `8016`，不回放原結果。** 文檔的錯誤範例只有錯誤報文，**沒有夾帶原本的 `mailno`** | SF-13 |
>
> **這三行決定了我方的重試策略，逐條說明後果：**
>
> 1. **`requestID` 不能當冪等鍵。** 把 `idempotency_key` 映到 `requestID` 送出去是無效的——順豐不看它。**我方的第一層冪等必須完全自理**，不得指望第二層。
> 2. **`orderid` 是我方唯一能用的第二層冪等載體**，且它就是 §F.4 的 `client_reference`（＝`shipment_intents.id`）。**這一點很值**：它讓「重送」在順豐側**天然安全**——重送最壞是拿到 `8016`，**不會**產生第二張運單。
> 3. **但 `8016` 不回放結果，所以「重送成功了嗎」問不出來。** 收到 `8016` **只證明「這個 `orderid` 已經被受理過」，不證明「上一次拿到了什麼號」。** ⇒ **`8016` 必須映射成 `unknown` 而非 `business_rejected`**，並走 §F.4 的回查取回 `mailno`。
>    🔴 **把 `8016` 當成 `business_rejected`（「重複下單，失敗」）是本輪最容易被實作者做錯的一步**——那會讓 intent 落到 `FAILED`，而順豐那邊其實**已經有一張運單**，且因為 `orderid` 不可重用（SF-14），這張運單再也接不回任何 intent，直接變成 §D.5 的 `ABANDONED_UNRESOLVED`。
> 4. **`8019`（訂單已確認或已取消）同理**：它是**狀態衝突**不是業務拒絕，映射到銷號／取消路徑的 `too_late`，不是 `refused`。
>
> ⇒ 沿用 §A.2 K2 的四值模型，`sf_express` 的原始碼映射表（pack 級，不進核心）：
>
> | 順豐原始碼 | 映射到 | 為什麼 |
> |---|---|---|
> | `8016` 重複下單 | `unknown` | 副作用可能已發生，且結果查不回來 ⇒ 必須回查 |
> | `8019` 訂單已確認或已取消 | `too_late`（K4／K5）| 狀態衝突，非拒絕 |
> | `4001` 系統資料錯誤／執行期例外 | `transient_error` | 對方系統面問題，可退避重試 |
> | `0000`／`0001`／`0002`／`0004` 參數／解析／校驗／缺欄位 | `business_rejected` | 我方報文有問題，重試無用 |
> | `0003` 單號節點超過上限 | `business_rejected` | 我方分批分錯，屬程式 bug，**不得重試**（分批上限見 `limits.carrier.packs.sf_express.documented_limits`）|
>
> **這張表必須有測試**（§K 維度 6）：每一列一個 case，特別是 `8016 → unknown` 那一列。

**第二層缺席時的規則（預設假設所有物流商都沒有第二層）**：

| 情況 | 動作 |
|---|---|
| 收到 `transient_error`（明確未送達或明確失敗） | **可**重試，且**必須沿用同一個** `carrier_request_id`（若該 pack 宣告支援去重）；重試次數與退避取 `limits.carrier.shipment_intent.poll_backoff_seconds` |
| 收到 `unknown`（逾時／連線中斷） | **禁止自動重試**。一律走 §F.4 回查。**這是本檔與一般重試邏輯最大的分歧點** |
| job 本身被重排（Solid Queue at-least-once） | 由 intent 的 `status` 擋：只有 `PENDING` 可被撿走；`IN_FLIGHT` 以 `claimed_at` ＋ 條件式 UPDATE 搶佔，逾 `settle_timeout_ms` 才可被接管，接管後**一律先回查再決定是否呼叫**，不得直接重打 |

> **`IN_FLIGHT` 的接管必須先回查**——這是把「job 重排」與「請求重送」分開的關鍵。Solid Queue 保證 at-least-once，所以同一個 intent 一定會有被跑第二次的時候；若第二次直接重打 API，就把「我方 job 的重試」變成了「對物流商的重複下單」。

### E.3 哪些**不**放進 `required_for`（以及為什麼）

| mutation | 為什麼不放 |
|---|---|
| `shipmentLabelRender` | 產檔可重做、通常無成本。**但若某 pack 宣告 `label_render.billable_per_render: true`，該 pack 的渲染路徑必須改走帶 key 的批次作業** —— 這是 pack 級的加嚴，不是全域規則 |
| `carrierRateQuotes` | 唯讀查詢，無副作用 |
| `carrierAccountTest` | 唯讀連線測試 |

---

## F. transaction 內禁外部 IO：正確的編排

### F.1 錯誤示範（會出現在 code review 裡，必須擋下）

```ruby
# 🔴 三重違規，一個都不能留
ActiveRecord::Base.transaction do
  fo = FulfillmentOrder.lock.find(id)            # ① 持有行鎖
  result = SfExpress.create_order(fo)            # ② transaction 內打外部 API（鐵律 5）
  Fulfillment.create!(tracking_number: result.mailno)
  NotificationMailer.shipped(fo).deliver_now     # ③ transaction 內寄信
end
```

失效模式（11 §2 第 2 點已列為「最常見的生產事故源」）：物流商延遲 30 秒 ⇒ 行鎖持有 30 秒 ⇒ 同一批訂單的請求排隊 ⇒ 連線池耗盡 ⇒ **全站掛，不只出貨掛**。
加碼一個本檔特有的失效模式：**若 ② 成功而 transaction 之後回滾，號已經取了，DB 卻沒有任何紀錄——這張運單從此不存在於系統中，永遠不會被銷號。**

### F.2 正確編排：三段式（intent → call → settle）

```
┌─ DB txn #1（毫秒級，無外部 IO）────────────────────┐
│ 驗證：FO 狀態、剩餘數量、carrier 能力、法域可服務    │
│ 寫入：shipment_intents(status=PENDING, idem_key)    │
│ 寫入：outbox(topic=carrier.shipment.requested)      │
│ FO 狀態：不變                                        │
└──────────────────────────────────────────────────┘
              ↓ commit 後，job 由 outbox 觸發
┌─ 無 transaction、無鎖 ────────────────────────────┐
│ 條件式 UPDATE 搶佔：PENDING → IN_FLIGHT（claimed_at）│
│ adapter.create_shipment(...)   ← 唯一的外部 IO 點     │
└──────────────────────────────────────────────────┘
              ↓ ShipmentResult
┌─ DB txn #2（毫秒級，無外部 IO）────────────────────┐
│ 寫入：waybills(status=ALLOCATED)                    │
│ 呼叫：既有的 Fulfillments::Create service           │
│       （FO 走 T9/T10、庫存 committed−/on_hand−、     │
│         訂單 fulfillment_status 重物化）             │
│ 寫入：intent status=SUCCEEDED                        │
│ 寫入：outbox(fulfillments/create)                    │
└──────────────────────────────────────────────────┘
              ↓ commit 後
        出貨通知信 job（transaction 外，沿用 16-F3 既有做法）
```

**三條硬要求**

1. **txn #2 內不得再打任何外部 API**——包括「順便把面單也印了」。面單渲染是**另一個** job（`carrier.label.requested`），由 txn #2 的 outbox 觸發。
2. **txn #2 必須是純本地寫入且可重入**。若 txn #2 因死鎖失敗，job 重試時 intent 仍是 `IN_FLIGHT` 且 `ShipmentResult` 已持久化在 `shipment_intents.result_payload`（txn #2 之前先以獨立短交易寫入），**重試時不重打 API，直接用已存的 result 再跑一次 settle**。
   > 這一點很容易漏：外部呼叫成功、本地寫入失敗，是最惡劣的組合。必須先把「外部已發生的事實」落地，再做本地業務寫入。
3. **補償只能向前，不能向後。** settle 失敗到重試耗盡 ⇒ intent 進 `UNKNOWN` 並告警，**不得**「回滾」——號已經取了，回滾 DB 只會讓它變成孤兒。向前補償＝把它交給 §D.5 的銷號流程。

### F.3 `shipment_intents` 狀態機

| 從 | 到 | 觸發 | 條件 |
|---|---|---|---|
| （建立） | `PENDING` | `shipmentIntentCreate` | txn #1 |
| `PENDING` | `IN_FLIGHT` | job 搶佔 | 條件式 UPDATE，設 `claimed_at` |
| `IN_FLIGHT` | `SUCCEEDED` | settle 完成 | `outcome=success` |
| `IN_FLIGHT` | `FAILED` | 業務拒絕 | `outcome=business_rejected` |
| `IN_FLIGHT` | `PENDING` | 退避重排 | `outcome=transient_error` 且 `attempts < max` |
| `IN_FLIGHT` | `FAILED` | 重試耗盡 | `outcome=transient_error` 且 `attempts >= max` |
| `IN_FLIGHT` | `UNKNOWN` | 逾時／不可解析 | `outcome=unknown` |
| `IN_FLIGHT` | `UNKNOWN` | job 逾 `settle_timeout_ms` 未回報 | 看門狗 |
| `UNKNOWN` | `SUCCEEDED` | 回查命中且已取號 | §F.4 |
| `UNKNOWN` | `FAILED` | 回查明確查無此單 | §F.4 |
| `UNKNOWN` | `ABANDONED` | 回查次數耗盡 | 告警 ＋ 人工佇列 |

**`UNKNOWN` 不是終態，`ABANDONED` 才是。** 系統必須持續嘗試把 `UNKNOWN` 解開——放著不管等於放著一張可能存在的運單不管。

### F.4 `UNKNOWN` 的回查對帳（順豐官方替我們背書的設計）

SF-6：順豐官方文檔明示訂單結果查詢介面的存在理由是網路不可靠。這正是回查流程的依據。

```
UNKNOWN 產生後，延遲 limits.carrier.shipment_intent.unknown_reconcile_after_seconds 開始回查：
  用「我方的 intent 識別」（我方下單時帶給物流商的 orderId／customer reference）
  呼叫 K2' 回查介面（順豐＝EXP_RECE_SEARCH_ORDER_RESP）
    → 查到且已取號  ⇒ 補走 settle（等同 success），intent → SUCCEEDED
    → 明確查無此單  ⇒ intent → FAILED（可安全重新發起）
    → 仍不確定      ⇒ 依 poll_backoff_seconds 退避重查，
                      逾 unknown_reconcile_max_attempts ⇒ ABANDONED ＋ P1 告警
```

**兩條前提條件（沒有它們回查就不可能）**

1. **下單時必須帶我方的唯一識別給物流商。** 這個識別＝`shipment_intents.id`（或其衍生字串），**不是** order name，**不是** FO id。理由：同一張 FO 可能有多個 intent（前一個 FAILED），用 FO id 回查會撈到舊的。
2. **該識別必須在物流商側唯一且可查。** 若某家物流商不支援以客戶自訂識別回查 ⇒ pack 必須宣告 `shipment_create.lookup_by_client_reference: false`，此時 `UNKNOWN` **一律直接進人工佇列**，不做自動回查。**不得**假設查得到。

### F.5 熔斷與降級

- 每個 `(shop_id, carrier_account_id)` 各自一個熔斷器（**不是** per carrier_code——一個租戶的憑證失效不該影響其他租戶）。
- 參數取 `limits.carrier.circuit_breaker.*`。
- **熔斷開啟時的行為**：`shipmentIntentCreate` 仍**可以**建立 intent（PENDING 會累積），但 job 不呼叫；後台顯示「物流商連線異常，已排入佇列」。
  **不得**在熔斷時自動改用另一家物流商——那是靜默 fallback，會產生商家沒同意的運費。要換必須商家明示（§B.2 通則）。

---

## G. 多租戶與憑證（鐵律 2）

### G.1 全表帶 `shop_id`

本檔新增的所有表一律帶 `shop_id`，且**複合索引以 `shop_id` 開頭**：

| 表 | 主要索引 |
|---|---|
| `carrier_accounts` | `(shop_id, carrier_code, environment)` 唯一 ＋ `(shop_id, enabled)` |
| `carrier_services` | `(shop_id, carrier_account_id, service_code)` 唯一 |
| `shipment_intents` | `(shop_id, status, created_at)`、`(shop_id, fulfillment_order_id)` |
| `waybills` | `(shop_id, carrier_code, waybill_number)` 唯一、`(shop_id, status, allocated_at)`、`(shop_id, active_waybill_key)` 唯一（§D.5(b)） |
| `waybill_labels` | `(shop_id, waybill_id, reprint_seq)` 唯一 |
| `carrier_pickups` | `(shop_id, carrier_account_id, pickup_window_start)` |
| `carrier_push_events` | `(shop_id, carrier_code, waybill_number, carrier_event_code, carrier_event_at)` 唯一 |
| `carrier_capability_skips` | `(shop_id, carrier_code, capability, occurred_at)` |
| `waybill_void_ledger` | `(shop_id, waybill_id)` 唯一 |

**跨租戶防線比照 56 §B.3 的作法**：`waybills` 對 `fulfillment_orders` 建**複合外鍵** `(shop_id, fulfillment_order_id)`，而非單欄 FK。理由與禮品卡那條完全相同——**繞過應用層直接寫 DB 也擋得住**。

### G.2 憑證怎麼存（絕不明文）

| 規則 | 內容 |
|---|---|
| 儲存 | Rails 8 Active Record Encryption（`encrypts`），密鑰走 Rails credentials，`RAILS_MASTER_KEY` 只在主機環境變數（11 §1 第 2 點） |
| 加密欄位 | 一律 **non-deterministic**（`encrypts :checkword`）。順豐的 `checkword`、DHL 的 password、UPS/FedEx 的 client secret 與 refresh token 全部屬此 |
| 可查詢欄位 | 需要用來查詢的識別（例如 `partner_id`）以 **deterministic** 加密，或另存不敏感的 `account_label` 供顯示。**顯示畫面一律只顯示 label 與末四碼** |
| 密鑰輪換 | `carrier_accounts.key_version` 欄位；輪換以背景 job 重加密，不停機 |
| 日誌 | `checkword` / `check_word` / `msg_digest` / `msgDigest` / `client_secret` / `api_secret` / `access_token` / `partner_id` 全部進 `config.filter_parameters`（鍵名清單落在 `limits.carrier.credentials.log_filter_keys`，**單一事實來源**） |
| 錯誤上報 | adapter 拋出的例外**不得**把請求 body 原樣帶進 Sentry——`msgData` 含收件人 PII，`msgDigest` 含簽章。上報前一律過濾 |
| 環境隔離 | `carrier_accounts.environment ∈ {sandbox, production}`。**生產環境的 shop 不得使用 sandbox 憑證，反之亦然**（`limits.carrier.credentials.cross_environment_use_forbidden: true`），service 層驗證 ＋ 測試 |
| 平台側可見性 | 平台管理端（35/36）**不得**有任何顯示或匯出租戶憑證明文的路徑；只可顯示 label、環境、最後成功時間、熔斷狀態 |

> **順豐的簽章特別提醒**：`msgDigest` 的計算需要 `checkword`（SF-3）。實作時 `checkword` 只能存在於 adapter 的區域變數，**不得**放進 job 參數（Solid Queue 的 job 參數會落 DB 明文）。job 只帶 `carrier_account_id`，由 adapter 在執行時自行解密取用。**這是很容易犯的錯：把憑證塞進 job payload，等於在 `solid_queue_jobs` 表裡存了明文憑證。**

### G.3 金額（鐵律 3）：物流商回傳的十進位字串怎麼變成 cents

物流商 API 幾乎都回十進位字串（`"12.50"`）或 JSON number（`12.5`）。**兩者都不得用 `to_f`。**

```ruby
# ✅ 唯一允許的轉換路徑
# 尺度一律 ×100，不看幣別（limits.carrier.money.storage_multiplier）。
def to_cents(raw)
  d = BigDecimal(raw.to_s) * 100                   # BigDecimal，全程不經 Float
  raise Carrier::MoneyPrecisionError unless d.frac.zero?
  d.to_i
end

# 🔴 禁止
raw.to_f * 100          # 12.5 * 100 == 1250.0000000000002 的家族
(raw.to_d * 100).round  # round 會把物流商的精度錯誤 silently 吞掉 —— 必須 raise
BigDecimal(raw) * (10 ** exponent)   # 見規則 3：exponent 已不是 ISO minor unit
```

**三條規則**

1. **`BigDecimal` 全程，出現 `Float` 即 bug。** adapter 的單元測試必須有一條斷言：對所有金額欄位 `assert_kind_of Integer`。
2. **小數位超過 2 位 ⇒ raise，不得 round。** 物流商回了 `"12.505"` 給 HKD 是**資料異常**，不是需要我方四捨五入的正常輸入。吞掉它會讓對帳永遠差幾分錢卻查不出來。
3. **🔴 換算尺度一律 ×100，不看幣別；不得用 `currency_format.exponent` 當換算基數。**
   同日（2026-08-12）另一份裁定新增了 `limits.currency_display`：`force_minor_unit_digits: 2`、`storage_scale_unchanged: true`、`iso4217_zero_decimal_overridden: [JPY, TWD]`，並把 `jurisdictions.<code>.currency_format.exponent` 的語義由「ISO 4217 minor unit」**改為「顯示位數」**（TWD 已由 `0` 改為 `2`）。
   ⇒ **儲存／換算**：一律 ×100（`limits.carrier.money.storage_multiplier`）。物流商回 JPY `"1000"` ⇒ `100000`。
   ⇒ **顯示**：一律兩位小數（`limits.carrier.money.display_decimals`，源自 `currency_display.force_minor_unit_digits`），符號由市場 locale 決定（`HK$1,480.00`，tabular-nums）。
   > ⚠️ **這是本檔在撰寫期間被同日裁定改掉的一條，請勿改回。** 若有人看到 `currency_format.exponent` 就拿去當換算基數，在 zero-decimal 幣別上會產生 **100 倍誤差**（JPY 1000 → 1000 而非 100000）。這正是 `currency_display` 區塊註解裡「下一個人請先讀這段」警告的同一個坑，在 carrier 側的具體後果。原登記的 **V-50 已由此裁定結案**（見附錄 A）。

---

## H. 法域交互：carrier pack ≠ jurisdiction pack

### H.1 兩者的關係，一句話講清楚

> **carrier 的「可用性」是法域的函數；carrier 的「能力」不是。**
> 順豐在香港能不能用，是法域問題。順豐支不支援 ZPL，跟法域一點關係都沒有。
> **把兩者合成一層，就會出現「為了在台灣支援超商取貨而在核心塞一個 carrier enum」這種設計——那正是 CLAUDE.md 鐵律 11 禁止的東西。**

| | jurisdiction pack（56） | carrier pack（本檔） |
|---|---|---|
| 回答什麼問題 | 這個法域**要求什麼／允許什麼** | 這家物流商**能做什麼** |
| 值域來源 | 法規 | 物流商的 API 文檔 |
| 誰決定 | 立法機關 | 物流商 |
| 變更頻率 | 年 | 季 |
| 解析輸入 | 賣方法域 ＋ 買方法域（56 §A.0） | carrier_code |
| **兩者的交點** | `pickup_networks`（買方能力）× `service_point`（carrier 能力）；`cod_max_cents` × `cod.max_cents` | |

**不得互相繼承、不得互相定義**：
- ❌ jurisdiction pack 裡列出「香港可用的物流商清單」——法規不決定哪家公司在營業。
- ❌ carrier pack 裡寫「本 carrier 僅限香港」——這是航線問題，用 §H.2 的 lane 表達。

### H.2 可服務性怎麼算（三方交集）

```
CarrierService 可用  ⟺  ① pack 宣告的 serviceable_lanes 命中 (origin_country, destination_country)
                    ∧  ② 該租戶的 carrier_account 已開通該 service_code
                    ∧  ③ 法域關卡通過（見下表）
```

**③ 法域關卡的三條**

| 關卡 | 條件 | 不通過的表現 |
|---|---|---|
| 跨境 ⇒ 需報關能力 | `origin_country != destination_country` ⇒ pack 必須宣告 `customs_doc.supported: true` | 該服務在結帳頁**不出現**（不是出現後才擋） |
| COD 上限取兩者較小 | `min(carrier.cod.max_cents, jurisdictions.<buyer>.pickup_networks.cod_max_cents)`；任一為 `null` ⇒ **reject** | COD 付款方式不出現 |
| 取件點模型須相符 | 見 §H.3 | 該 carrier 不出現在選點來源 |

**`Lane` 的形狀**（pack 靜態宣告）：

```
Lane = { origin_country, destination_country, service_code, display_name,
         cross_border ∈ {true,false}, requires_customs_doc ∈ {true,false} }
```

**origin/destination 用 ISO 3166-1 alpha-2**，**不得**用物流商自己的區域代碼（順豐的區域劃分與 DHL 不同，洩漏進核心就是廠商鎖定）。adapter 內部自行把 ISO 碼翻成廠商代碼。

<!-- 依 2026-08-12 第二輪查證改寫。原文：「順豐的香港／中港澳／國際服務代碼值域本輪未取得（V-44），且香港站與丰桥是否為同一套 API 亦未確認（V-43）。因此 sf_express 的 serviceable_lanes 目前為空陣列……」 -->

> ⚠️ **V-43／V-44：原本的問法把兩件事混在一起，本輪拆開後結論不同。**
>
> 原問題「香港站與丰橋是否同一套 API」其實包含兩個獨立的問題，答案不一樣：
>
> | 問題 | 答案 | 出處 |
> |---|---|---|
> | **香港作為「目的地」**：內地寄件到香港，走的是同一套丰橋 API 嗎？ | ✅ **是。** 國際件與國內件**同用 `OrderService`、同一個端點**，香港以 `d_deliverycode=852` 表達，`declared_value_currency` 支援 `HKD` | SF-19（`carrier-official`）|
> | **香港作為「寄件地」**：香港商戶能否申請丰橋帳號、以香港為 origin 下單？ | ❌ **仍未確認。** 丰橋文檔全篇以中國內地為寄件地；香港站無開發文檔 | V-43（仍開）|
> | 香港端有哪些**服務名稱**？ | ✅ 順豐香港官方價目表列出**標準快遞 / Standard Express** 與 **國際特惠 / Economy Express** 兩種，涵蓋 40＋ 目的地（含澳門、台灣）| B-19（`carrier-official`，順豐香港官網 PDF）|
> | 這些服務名稱對應的 **`express_type` 數值**？ | ❌ **仍未取得**（值域在未公開的附錄《快件產品類別表》內）| V-44（仍開）|
>
> 🔴 **對「順豐能不能當香港首發物流商」的直接影響（鐵律 11：基準法域＝香港）**：
> 我方首發需要的是 **HK → HK 本地** 與 **HK → 海外** 這兩條 lane，也就是**香港必須是 origin**。而本輪唯一拿到官方確認的，是**香港作為 destination**（內地寄出）。**兩者恰好互補，不能互相替代。**
> ⇒ **`sf_express.serviceable_lanes` 維持空陣列**，理由**不是**「不知道代碼」，而是更根本的一條：**連「香港商戶能不能用丰橋」都還沒確認**。這是正確的失效方向：不知道就不提供。
> ⇒ **順豐本輪不能作為香港首發物流商**，完整結論與替代方案見 §H.5。

### H.3 與 56 的 `pickup_networks` 的接縫（本節是正交性的具體證明）

`limits.yml` 的 HK pack 已宣告：`pickup_networks: { available: true, model: carrier_network_brand, providers: null, ... }`。

**`model: carrier_network_brand` 這個值本身就說明了兩層的分工**：

- **jurisdiction pack 說**：「在這個法域，取件點的**組織形態**是物流商自營品牌網路。」
  （對照另一種 model：某些法域的取件點是**便利商店通路**，是完全不同的商業與結帳模型。**核心規格不列舉那些通路名稱**——鐵律 11。）
- **carrier pack 說**：「本 carrier 有／沒有 `service_point` 能力，若有，值域長這樣。」

**兩者都為真，選點功能才會亮。** 缺任一：

| jurisdiction | carrier | 結果 |
|---|---|---|
| `available: true` | `service_point: supported` | ✅ 選點功能開啟 |
| `available: true` | `service_point: not supported` | 該 carrier 不出現在選點來源；**其他 carrier 仍可**。落一列 `carrier_capability_skips` |
| `available: false` | 任意 | 選點功能整體關閉（法域層決定） |
| `available: null`（未宣告） | 任意 | **reject**（56 §A.3 既有規則，本檔不改） |

> 🔴 **對既有規格的衝突警示**：16-F3.3(a) 的 `pickup_point_providers` 表把 `carrier` 欄位的值域**直接列舉成四個特定法域的便利商店品牌**，且 16-F3(3) 的 tracking URL 模板表同樣列舉了特定法域的物流商名稱。這兩處寫於 56／57 之前，與 CLAUDE.md 鐵律 11（核心規格不得直接引用超商取貨）及本檔 §H.1 衝突。
> **本檔的建議處置**（需使用者裁定，見回報 ④）：`pickup_point_providers` 併入 `carrier_accounts` ＋ `carrier_services`，`carrier` 欄位改為 `carrier_code`（值由 pack 註冊，不在核心枚舉）；原四個品牌降級為 `carrier/tw_*` pack 的素材，**一行不刪**（比照 56 對 tw pack 的處置）。**本檔不擅自改 16。**

### H.4 pack 的 enable gate

比照 56 §A 對未定案 pack 的處置，`carrier_packs` 的 enable 條件：

```
enabled ⟺ ① K1–K7 七項必宣告能力全部有非 null 的 supported 值
        ∧ ② 每一項 supported: false 都有非空的 reason
        ∧ ③ enable_gate 陣列為空（未結案的 V 編號會填進這裡）
        ∧ ④ credential_schema 非空且該租戶已通過 carrierAccountTest
```

**本輪各 pack 的 `enable_gate`**：

| pack | enable_gate | 可否 enable |
|---|---|---|
| `manual` | `[]` | ✅ |
| `sf_express` | `[V-39, V-41, V-42, V-43, V-44, V-47, V-48, V-51]` | ❌ |
| `dhl_express` | `[V-45]` | ❌ |
| `ups` / `fedex` | `[V-45]` | ❌ |

<!-- 依 2026-08-12 第二輪查證更新 sf_express 的 gate。原值：[V-39, V-40, V-42, V-43, V-44, V-47, V-48]
     變動：移除 V-38（DNS 已結案，且原本就不在 gate 裡）與 V-40（已由我方架構決策結案，見 §D.2）；
           新增 V-41（完整目錄，仍缺）與 V-51（msgDigest 演算法 —— 原本因誤標成 V-40 而完全不在 gate 裡）。 -->

> **本輪 gate 的兩項變動都值得記住**：
> - **移出 V-40**：它問的是「順豐支不支援 ZPL」，但我方**不需要這個答案**就能決策（§D.2）。**一個不影響任何決策的問題不該擋著 pack**——V 編號是用來擋「不知道會做錯事」的，不是用來收集知識的。
> - **移入 V-51**：`msgDigest` 演算法不明＝**一個請求都送不出去**。它原本因誤標而不在 gate 裡，意味著 gate 曾經**漏掉了最硬的那個阻塞項**。這是一個 gate 機制本身的教訓：**gate 的內容要定期對照「實作者第一天會卡在哪」重新檢查**，不能只累加。

### H.5 順豐能否作為香港首發物流商（鐵律 11 的直接結論）

**結論：不能。本輪不具備把順豐作為香港首發物流商的條件，且缺口不是靠再查文檔能補上的。**

| 首發需要什麼 | 現況 | 缺口性質 |
|---|---|---|
| HK → HK 本地 lane | ❌ 未確認香港商戶能否申請丰橋帳號、以香港為 origin | **商務問題**（V-43），需順豐香港窗口回答 |
| HK → 海外 lane | ❌ 同上；服務**名稱**已知（標準快遞／國際特惠，B-19），**代碼**未知 | 商務＋文檔（V-43／V-44）|
| 面單可印 | ❌ 雲打印欄位與格式未取得 | 文檔（V-39）|
| 能送出第一個請求 | ❌ `msgDigest` 演算法未取得 | 文檔（V-51）|
| 銷號帳可閉環 | ❌ 計費與時間窗屬合約 | **合約問題**（V-42）|
| COD（香港常見） | ❌ 香港可用性與上限未知 | 商務（V-48）|

**三條可執行的路，按建議順序：**

1. **首發用 `manual` pack。** 它已可 enable，是**正式營運路徑**而非過渡玩具（§B.1 結論 2）：商家自行在順豐香港系統下單、回填單號，我方負責追蹤展示與對帳。**這條路今天就能走，不阻塞任何里程碑。**
2. **同時啟動兩條非工程的問詢**（因為它們的前置期最長，且工程再努力也無法自解）：
   - 順豐香港商務窗口 → V-43 / V-44 / V-48；
   - 順豐月結合約 → V-42。
3. **不要為了「有一個真的 carrier」而先接內地丰橋。** 內地丰橋能做的是**內地寄出**，與我方香港首發需要的 origin 相反（§H.2 的表）。接了也點不亮任何一條首發需要的 lane，只會製造一個 enable 不了的 pack 和一堆維護成本。

> **這一節同時是對 §0.2 原則 5 的驗證**：carrier 的**可用性**是法域的函數。順豐作為一家公司在香港顯然有營業（B-19 是它自己的香港價目表），但**「公司在營業」與「我方能以 API 對接」是兩件事**——中間隔著帳號開通、寄件地支援、與合約。抽象層把這件事表達成 `serviceable_lanes` 為空，而不是「順豐不支援香港」，正是為了不把商務缺口誤記成技術事實。

---

## I. GraphQL 契約（對照 28 §0 慣例）

**命名一律 `resourceVerb`；業務錯誤走 `userErrors{field,message,code}`，HTTP 恆 200；GID 為 `gid://chilllove/{Type}/{id}`；分頁 cursor ＋ `pageInfo`（≤ `limits.api.pagination_max_page_size`）。**

| 分類 | 欄位／Mutation | 關鍵 input | 回傳 |
|---|---|---|---|
| 查詢 | `carrierPacks` | — | 全部 pack 的靜態能力宣告（供設定頁渲染 §B 矩陣） |
| 查詢 | `carrierAccounts(first, after)` | — | Connection；**憑證欄位不在 schema 中**，只有 `label`、`environment`、`lastVerifiedAt`、`circuitState` |
| 查詢 | `carrierRateQuotes(input)` | `destinationAddress`, `packages`, `carrierAccountIds` | `[CarrierRateQuote{ serviceCode, displayName, amount: MoneyV2, estimatedDays }]`；逾時依 `limits.carrier.rate_quote.on_timeout` 降級並落 skip 列 |
| 查詢 | `waybills(first, after, query, sortKey)` | 支援 `status:`／`carrier:`／`allocatedAt:` 過濾 | Connection（**待銷號佇列**即此查詢的一個預設過濾） |
| 帳號 | `carrierAccountCreate` / `carrierAccountUpdate` / `carrierAccountDelete` | 憑證欄位為 **write-only**（input 有、type 無） | `carrierAccount, userErrors` |
| 帳號 | `carrierAccountTest` | `carrierAccountId` | `ok, checkedCapabilities[], userErrors`（唯讀，不需 idempotencyKey） |
| 出貨 | **`shipmentIntentCreate`** | `fulfillmentOrderId!`, `carrierAccountId!`, `serviceCode!`, `packages!`, `codAmountCents`, **`idempotencyKey!`** | `shipmentIntent, userErrors` |
| 出貨 | `shipmentIntentRetry` | `shipmentIntentId!`, `idempotencyKey!` | 僅 `FAILED` 可重試；`UNKNOWN` **不可**（回 `INVALID_STATE`） |
| 運單 | **`shipmentVoid`** | `waybillId!`, `reason!`, **`idempotencyKey!`** | `waybill, userErrors` |
| 運單 | **`shipmentCancel`** | `waybillId!`, **`idempotencyKey!`** | `waybill, userErrors` |
| 運單 | `shipmentVoidMarkManual` | `waybillId!`, `note!` | 人工處理登記（`VOID_MANUAL_REQUIRED → VOIDED` 需二次確認） |
| 面單 | `shipmentLabelRender` | `waybillId!`, `format!`, `sizeCode`, `reprintReason` | `label{ url, format, sizeCode, reprintSeq }, userErrors` |
| 面單 | `shipmentLabelBatchRender` | `waybillIds!`（≤ `limits.carrier.label.batch_max_per_job`）, `format!` | **`job{id, done}`**（非同步，比照 28:116 慣例）＋ `failures[]` |
| 取件 | **`carrierPickupSchedule`** | `carrierAccountId!`, `locationId!`, `windowStart!`, `windowEnd!`, **`idempotencyKey!`** | `carrierPickup, userErrors` |
| 取件 | `carrierPickupCancel` | `carrierPickupId!` | `carrierPickup, userErrors` |

**`userErrors.code` 一律從 28 §通用碼取值**（`BLANK`／`TOO_LONG`／`NOT_FOUND`／`INVALID_STATE`…），本檔只新增下列**專屬碼**（沿用 28「不得各模組自造同義碼」的鐵律，故不新增 `EMPTY`／`MISSING` 這類同義詞）：

| 新增 code | 用在哪 |
|---|---|
| `CARRIER_CAPABILITY_UNDECLARED` | §A.3 未宣告能力 |
| `CARRIER_PACK_NOT_ENABLED` | §H.4 gate 未通過 |
| `CARRIER_LANE_NOT_SERVICEABLE` | §H.2 ① 或 ③ 不通過 |
| `LABEL_FORMAT_UNSUPPORTED` | §D.2 規則 1 |
| `WAYBILL_ALREADY_ACTIVE` | §D.5(b) 場景 4（同一 FO 已有非終態運單） |
| `WAYBILL_VOID_WINDOW_EXPIRED` | 逾 `window_hours` |
| `CARRIER_CIRCUIT_OPEN` | §F.5 熔斷中 |
| `CROSS_ENVIRONMENT_CREDENTIAL` | §G.2 環境隔離 |

**沿用既有碼、不重造**：`IDEMPOTENCY_CONCURRENT_REQUEST`、`IDEMPOTENCY_KEY_PARAMETER_MISMATCH`（11 §2.1）、`INVALID_STATE`（狀態機違規統一碼）。

---

## J. `config/limits.yml` 新增的鍵（已落檔）

**本檔不硬編任何數字**（鐵律 6）。下列鍵已寫入 `config/limits.yml`：

| 鍵 | 用在本檔哪一節 |
|---|---|
| `carrier.undeclared_capability_action` / `allowed_fallback_actions` / `silent_fallback_forbidden` | §A.3 |
| `carrier.required_capabilities` / `optional_capabilities` | §A.1 |
| `carrier.capability_skips_table` | §A.3 |
| `carrier.money.*`（`storage` / `parse_from_carrier` / `float_parsing_forbidden` / `display_decimals` / `minor_unit_source` / `round_forbidden`） | §G.3 |
| `carrier.waybill.*`（`number_is_billable_resource` / `unused_void_after_hours` / `void_attempt_max` / `void_ledger_table` / `reconcile_cron` / `unaccounted_alert_threshold` / `one_active_waybill_per_fulfillment_order`） | §D.5 |
| **（二輪改）** `carrier.waybill.number_is_billable_resource`：由 `true` 改為 **`policy_default`**，並新增 `number_is_billable_resource_authority` 與 `billed_if_unused_null_means` | §D.5(a0) |
| **（二輪新增）** `carrier.shipment_intent.client_reference_reuse_forbidden` / `client_reference_unique_key` | §D.5(f) |
| **（二輪新增）** `carrier.tracking.push_verification_modes` / `push_none_mode_required_controls` / `push_source_ip_allowlist_required` | §C.4 第 2 點 |
| **（二輪新增）** `carrier.packs.sf_express.endpoints.*` / `base_url_freeform_allowed` | §附錄 A V-38（已結案）|
| **（二輪新增）** `carrier.packs.sf_express.documented_limits.*`（順豐官方明載的六項分批上限）| §附錄 A V-46 |
| **（二輪新增）** `carrier.packs.sf_express.error_code_outcome_map`（原始錯誤碼 → 四值 outcome）| §E.2 |
| `carrier.label.*`（`formats_allowed` / `batch_max_per_call` / `batch_max_per_job` / `render_timeout_ms` / `reprint_requires_reason` / `retention_days` / `signed_url_ttl_seconds` / `zpl_byte_exact`） | §D.2–§D.4 |
| `carrier.rate_quote.*`（`checkout_timeout_ms` / `admin_timeout_ms` / `on_timeout` / `cache_ttl_seconds`） | §A.1 K1、§I |
| `carrier.tracking.*`（`poll_interval_seconds` / `stop_polling_on_terminal` / `push_dedupe_key`） | §C.4 |
| `carrier.shipment_intent.*`（`settle_timeout_ms` / `unknown_reconcile_after_seconds` / `unknown_reconcile_max_attempts` / `poll_backoff_seconds` / `auto_retry_on_unknown_forbidden`） | §E.2、§F.3、§F.4 |
| `carrier.client_qps_default` | §F.5（順豐未公布限流 ⇒ V-46） |
| `carrier.circuit_breaker.*` | §F.5 |
| `carrier.credentials.*`（`storage` / `plaintext_forbidden` / `log_filter_keys` / `environment_enum` / `cross_environment_use_forbidden` / `job_payload_forbidden_keys`） | §G.2 |
| `carrier.packs.*`（各 pack 的 `enabled` 與 `enable_gate`） | §H.4 |
| `idempotency.required_for` **＋4 條**（22 → 26） | §E.1 |
| `idempotency.business_unique_keys` **＋4 組** | §E.1 |

---

## K. 本篇驗收（對照 11 §0 七維度）

### 1 安全

1. `carrier_accounts` 的憑證欄位在 DB 中為密文——**直接 `SELECT` 取出的值不含明文子字串**（測試以已知 checkword 斷言）。
2. 應用日誌、job payload（`solid_queue_jobs`）、錯誤上報三處，grep `limits.carrier.credentials.log_filter_keys` 的每個鍵名對應的值，**命中數為 0**。
3. carrier 推送端點：偽造簽章的請求回 **401**，且**不落 `carrier_push_events`**。無 `endpoint_token` 的請求回 404。
3b. **（二輪新增）`push_verification.mode: "none"` 的 pack 專用**：①`push_none_mode_required_controls` 四項缺任一 ⇒ **開機期 fail**；②帶正確 `endpoint_token` 但 `waybill_number` **不屬於該 `shop_id`** ⇒ 丟棄、回 404、**不落庫**，且落一列稽核；③來源 IP 不在允許清單 ⇒ 401。**這三條是沒有簽章時唯一的防線（§C.4 第 2 點），缺測試等於沒有。**
4. 生產 shop 綁 sandbox 憑證 ⇒ `CROSS_ENVIRONMENT_CREDENTIAL`，**不得**送出任何外部請求。
5. 平台管理端 schema 快照測試：**不存在**任何回傳租戶憑證明文的欄位。

### 2 資料完整

6. 同一 FO 已有 `ALLOCATED` 運單時再次 `shipmentIntentCreate` ⇒ `WAYBILL_ALREADY_ACTIVE`；**繞過應用層直接 INSERT 亦被唯一索引拒絕**（§D.5(b)）。
7. `waybills` 的複合外鍵 `(shop_id, fulfillment_order_id)`：以 A 店的 shop_id 寫入 B 店的 FO ⇒ **DB 層拒絕**。
8. **銷號帳閉環**（§D.5(c)）：造 100 張運單（隨機交寄／銷號／逾期），nightly job 的等式成立，且 `ABANDONED_UNRESOLVED == 0` 時不告警、`> 0` 時告警。
9. 外部呼叫成功但 settle 的 txn #2 失敗 ⇒ 重跑 job **不重打 API**，用已存的 `result_payload` 完成 settle（§F.2 要求 2）。
10. 每個 `supported: false` 的能力被觸及 ⇒ `carrier_capability_skips` **恰增一列**且 `reason` 可讀。**靜默 return 即測試失敗。**
10b. **（二輪新增）`client_reference` 不得重用**（§D.5(f)，出處 SF-14）：對同一 FO 依序做「取號 → void → 再取號」，斷言兩次送給物流商的 `client_reference` **不相同**；並以直接 INSERT 重複值驗證 `(shop_id, carrier_account_id, client_reference)` 唯一索引會拒絕。
10c. **（二輪新增）銷號帳的立論已與計費脫鉤**（§D.5(a0)）：把 pack 的 `billed_if_unused` 設為 `false`，斷言 §D.5(b) 五個場景的程式路徑**全部照常執行**、待銷號佇列照常進列——**只有 (d) 的告警等級從 P1 降為 P3**。**若把 `billed_if_unused: false` 做成「跳過整套銷號帳」，此測試必須失敗。**

### 3 併發

11. 兩個 job 同時撿同一個 `PENDING` intent ⇒ 條件式 UPDATE 只有一個成功，**外部 API 只被呼叫一次**（以 mock 計數斷言）。
12. 同一 `idempotencyKey` 併發送兩次 `shipmentIntentCreate` ⇒ 一個成功、一個回 `IDEMPOTENCY_CONCURRENT_REQUEST`，**運單數為 1**。
13. 同 key 異參數 ⇒ `IDEMPOTENCY_KEY_PARAMETER_MISMATCH`（`package_fingerprint` 不同即算異參數）。
14. 兩個 staff 同時對同一運單按銷號 ⇒ 外部 void 只被呼叫一次。

### 4 效能

15. **`ActiveRecord::Base.transaction` 區塊內不得出現任何 adapter 呼叫**——靜態檢查（自訂 RuboCop cop 或 CI grep），命中即 fail。這是鐵律 5 的機械化檢查。
16. 結帳期 `carrierRateQuotes` 逾 `limits.carrier.rate_quote.checkout_timeout_ms` ⇒ 降級靜態運費表，**結帳頁 p95 仍在 11 §0 維度 4 的預算內**。
17. 待銷號佇列查詢（10 萬列運單）走 `(shop_id, status, allocated_at)` 索引，**無 N+1**。

### 5 可觀測

18. 每次 adapter 呼叫產生結構化日誌，帶 `request_id`、`shop_id`、`carrier_code`、`capability`、`outcome`、`duration_ms`；**不帶** `msgData`。
19. Dashboard 至少四個指標：各 carrier 的 `unknown` 率、待銷號張數、熔斷開啟次數、面單渲染 p95。
20. `ABANDONED_UNRESOLVED > 0` 與 `billed_if_unused: true` 的逾期未銷 ⇒ **P1 告警**（§D.5(d)）。

### 6 測試

21. **合約測試（contract test）套件對每個 pack 跑同一份測試**——這是可插拔架構唯一的驗證方式。至少涵蓋：十三項能力的 supported/unsupported 兩條路徑、四個 `outcome`、金額必為 Integer。
22. `manual` pack **必須全綠**（本輪唯一可 enable 的 pack）。
23. 金額路徑 100% 覆蓋（11 §0 維度 6）：`to_cents` 對 `"12.50"` / `"12.5"` / `12.5`(number) / `"12.505"`(應 raise) / `"0"` / 負值 各一條斷言。
24. **`Float` 掃描**：adapter 回傳的所有金額欄位 `assert_kind_of Integer`；`app/services/carrier/` 下 grep `to_f` 命中數為 0。
25. 快樂路徑 system test：建立出貨 → 取號 → 印面單 → 收到追蹤推送 → FO 轉 `CLOSED`。
25b. **（二輪新增）原始錯誤碼映射表逐列測試**（§E.2、`limits.carrier.packs.sf_express.error_code_outcome_map`）：八個碼各一條 case。
   🔴 **其中 `8016 → unknown` 那一列必須另加一條端到端斷言**：mock 順豐回 `8016` ⇒ intent 進 `UNKNOWN`（**不是 `FAILED`**）⇒ 觸發 §F.4 回查 ⇒ 回查取回 `mailno` ⇒ intent 轉 `SUCCEEDED` 且**運單數為 1**。
   **把 `8016` 當 `business_rejected` 是本檔第二容易犯的錯**（第一是把 `unknown` 併進 `transient_error`），後果是順豐側已有一張運單卻永遠接不回任何 intent，直接變成 `ABANDONED_UNRESOLVED`。

### 7 合規／隱私

26. 面單檔案（含 PII）：私有儲存、簽名連結有 TTL、逾 `retention_days` 由 purge 任務刪除，且**刪除有紀錄**。
27. PII 清單納入面單檔案與 `carrier_push_events` 的原始報文（後者含收件人資訊）；`carrier_push_events` 的保存期比照 38 的日誌分層。
28. **`app/` 下 grep `統一發票|字軌|折讓|統編|超商取貨|電支條例` 命中數為 0**（延續 56 §F CI-2，本檔新增的 carrier 程式碼一併納入掃描範圍）。
29. 核心（`app/services/carrier/` 除 `packs/` 外）grep 任一物流商品牌名，**命中數為 0**——品牌名只能出現在 pack 目錄內。這是 §H.1 正交性的機械化檢查。

### CI 級（build/boot 期，失敗即 build fail）

- **CI-1**：每個 `enabled: true` 的 pack，K1–K7 七項全部有非 null 的 `supported`，且 `false` 者有非空 `reason`。
- **CI-2**：`enable_gate` 非空的 pack，`enabled` 必須為 `false`。
- **CI-3**：`limits.carrier.packs` 的 pack 清單與 `app/services/carrier/packs/` 下的實作**一一對應**（不得有宣告無實作，或有實作無宣告）。
- **CI-4**：`idempotency.required_for` 中的每一支 mutation 在 schema 中都存在且 `idempotencyKey` 為必填（`!`）。
- **CI-5**：本檔引用的每個 `limits.*` 鍵在 `config/limits.yml` 中存在（防規格與設定漂移）。
- **CI-6（二輪新增）**：`carrier.packs.<code>.error_code_outcome_map` 的每個 value 必須落在四值 outcome 值域 `{success, business_rejected, transient_error, unknown}` ∪ `{too_late, refused, voided}`（後三者為 K4／K5 專用），**打錯字即 build fail**。映射錯一個碼的代價見 §E.2。
- **CI-7（二輪新增）**：`capabilities.tracking_push.push_verification.mode == "none"` 的 pack，其補償控制必須涵蓋 `limits.carrier.tracking.push_none_mode_required_controls` 的**全部四項**，缺一即 build fail（§C.4 第 2 點）。

---

## 附錄 A：待查證登記（V-37 起）

> 規則沿用 52 §附錄 A：**無明確出處一律不自補規則**。每一項寫「要查什麼」「去哪查」「沒查到的當前處置」。
> **當前處置一律是「保守失效」**——不是猜一個值上線。

**2026-08-12 第二輪查證後的狀態總表**（起因：使用者指出「文檔為 JS 渲染的 SPA 所以抓不到」的判斷是錯的，API 文檔不需要帳號）

| V | 狀態 | 一句話 |
|---|---|---|
| V-37 | ⏳ 仍開 | 官方仍只有 8 個服務代碼；SF-9 那七個的官方佐證仍為零 |
| V-38 | ✅ **結案** | **DNS 判定：`sf-express.com`（有連字號）才對，官方 SDK PDF 印錯了** |
| V-39 | 🟡 縮小 | 介面名／代碼／分類已官方確認；**欄位表仍缺** |
| V-40 | ✅ **結案（架構決策）** | 順豐無 ZPL 證據 ⇒ **首發不接 ZPL 指令流**；`zpl` 留在抽象層值域 |
| V-41 | 🟡 縮小 | `category`／`apiClassify` 語義與兩個值已知；完整目錄仍缺 |
| V-42 | 🔴 **性質改變** | **「取號不用會被計費」在官方文檔中無任何依據**；且這問題不會由文檔回答 ⇒ §D.5 已換立論 |
| V-43 | 🟡 拆分 | 香港作**目的地**＝同一套 API（已確認）；香港作**寄件地**＝仍未確認（**我方首發要的是後者**）|
| V-44 | 🟡 縮小 | 香港服務**名稱**已知；`express_type` **數值**仍缺 |
| V-45 | ⏳ 仍開 | 本輪未動（DHL／UPS／FedEx）|
| V-46 | 🟡 部分 | 速率上限仍無；**但取得六項官方分批上限**（已落 limits）|
| V-47 | 🟡 部分＋**處置改向** | **官方確認舊世代推送沒有驗簽機制** ⇒ 從「等值」改成「二選一＋補償控制」|
| V-48 | ⏳ 仍開 | 香港 COD 仍無任何來源 |
| V-49 | ✅ **結案** | **去重鍵是 `orderid` 不是 `requestID`，且回錯誤不回放** ⇒ `8016` 必須映射成 `unknown` |
| V-50 | ✅ 前輪已結案 | — |
| **V-51** | 🔴 **新登記** | `msgDigest` 演算法未載明——**第一號阻塞項**，原本因誤標而不在 gate 裡 |
| **V-52** | 🟡 新登記 | 憑證兩件式 vs 三件式有矛盾 |

| # | 待查證項目 | 去哪查 | 當前處置 | 阻塞什麼 |
|---|---|---|---|---|
| **V-37**<br>⏳ **仍開（未縮小）** | 順豐服務代碼的**完整值域**與各自語義（本檔 SF-9 列出的 `EXP_RECE_VALIDATE_WAYBILLNO`／`EXP_RECE_QUERY_GIS_DEPARTMENT`／`EXP_RECE_QUERY_DELIVERTM`／`EXP_RECE_SEARCH_PROMITM`／`EXP_EXCE_CHECK_PICKUP_TIME`／`EXP_RECE_CREATE_REVERSE_ORDER`／`EXP_RECE_WANTED_INTERCEPT` 僅有開源 SDK 常數表佐證）；特別是 `EXP_RECE_QUERY_SFWAYBILL` 的語義是否等同「運費試算」<br>**2026-08-12 二輪**：官方 SDK PDF 覆核後**仍只列 8 個**服務代碼（SF-4），未擴充；另由官方頁面標題新增確認 `COM_RECE_CLOUD_PRINT_WAYBILLS` 與 `COM_RECE_CLOUD_CUSTOMTEMPLATE_DELETE` 兩個**面單類**代碼（SF-20），但那不屬本項所問的速運類清單。**SF-9 那七個代碼的官方佐證仍為零。** | 丰桥開發者入口的目錄頁（需以瀏覽器渲染，見 V-41）；或申請沙箱後以實測覆核 | `sf_express` 的 K1／K8／K11 標 `❔`，不得 enable | §B.1 |
| ~~**V-38**~~<br>✅ **已結案（2026-08-12）** | 順豐端點網域正確寫法：`sfapi.sfexpress.com`（官方 SDK PDF）vs `sfapi.sf-express.com`（第三方實作）<br>**答案：`sf-express.com`（有連字號）才是對的。** 權威 DNS 查詢顯示 `sfapi.sfexpress.com`、`sfapi-sbox.sfexpress.com` 乃至 apex `sfexpress.com` **皆無 A 記錄**；`sfapi.sf-express.com`／`sfapi-sbox.sf-express.com` 正常解析。**官方 SDK PDF 這一處是錯的或已過期。** | 已由 DNS 解析結案（B-12） | `base_url` 改為可填：沙箱 `https://sfapi-sbox.sf-express.com/std/service`、生產 `https://sfapi.sf-express.com/std/service`。**仍不自填**——設定期由下拉選單選，避免打錯字打到別人的主機 | 已無阻塞 |
| **V-39**<br>🟡 **已縮小，未結案** | 雲打印面單介面的**請求／回應欄位、回傳檔案形態、模板代碼、尺寸值域**<br>**2026-08-12 二輪已確認（官方）**：介面名「雲打印面單打印2.0接口」、服務代碼 `COM_RECE_CLOUD_PRINT_WAYBILLS`、分類「面單類API」；同族存在 `COM_RECE_CLOUD_CUSTOMTEMPLATE_DELETE`（可知模板可自訂）——SF-20。<br>**仍缺**：欄位表、回傳形態、模板代碼與尺寸的**官方**值域。第三方（1.0 版）佐證見 SF-22，**不得寫進 pack**。 | 目錄頁需瀏覽器渲染（見 V-41）；或申請沙箱後實測 | `sf_express.label_render.formats` / `sizes = null` ⇒ 不得 enable | §D.2 |
| ~~**V-40**~~<br>✅ **已結案（2026-08-12，以我方架構決策結案）** | 順豐**是否支援 ZPL 指令輸出**（熱感標籤機直印）<br>**查證結果**：無任何來源顯示順豐雲打印介面本身輸出 ZPL；第三方文檔明列輸出為 PDF；聚合商可提供 ZPL 但屬其自行轉檔（SF-23）。<br>**結案方式不是查到答案，而是判定「這個答案不影響決策」**：`zpl` 留在 `limits.carrier.label.formats_allowed`（DHL／UPS／FedEx 原生支援，屬抽象層值域），但 `sf_express.label_render.formats` 依 §A.3 維持 `null`，**且我方首發不建任何 ZPL 指令流路徑**。 | 已由 §D.2 決策結案 | `zpl` 的位元組級處理規則**先寫規格、後做程式**，等第一個原生輸出 ZPL 的 pack 上線時再實作 | 已無阻塞（**已移出 `enable_gate`**）|
| **V-41**<br>🟡 **已縮小，未結案** | 順豐開放平台的**完整介面目錄**（全部 `category` 分類名稱與逐介面欄位表）<br>**2026-08-12 二輪已確認**：URL 參數語義 ＋ 部分值域——`/Api?category={業務線}&apiClassify={介面型態}`，`category=1`＝速運類API、`category=4`＝冷運API、`apiClassify=1`＝請求／回應型、`apiClassify=2`＝推送型；舊式明細頁為 `level3={介面流水號}`（SF-21）。<br>**仍缺**：其餘 `category` 值的分類名稱（含使用者提供的 `category=6`）與逐介面欄位表。 | **本輪已試過且失敗的四條路**（勿重複）：①WebFetch 直取 → 只得 `<meta>`；②站內索引枚舉 → 該站對任何未命中靜態檔的路徑一律回退 index.html，`robots.txt`／`sitemap.xml` 亦然；③容器內直連 → 出口政策 CONNECT 403；④`web.archive.org` CDX → 出口政策 403。<br>**未試而可行的一條**：**以能執行 JS 的瀏覽器開啟該頁**（頁面不需登入，使用者已確認公開可讀） | 以本檔 §0.4(a)(b) 的部分清單為準，其餘不假設 | 全 pack |
| **V-42**<br>🔴 **性質已改變（見下方說明）** | 順豐**運單號未使用的計費與銷號機制**<br>**2026-08-12 二輪已確認（官方）**：取消動作存在，`dealtype ∈ {1 確認, 2 取消}`（值域**已結案**）；**取消後客戶訂單號不得重複使用**；二次取消回 `8019`（SF-13／SF-14）。<br>**仍缺，且不會由 API 文檔回答**：①未使用之運單號是否計費 ②可銷號時間窗 ③銷號後 `mailno` 是否回收——官方兩份 PDF **通篇沉默**（SF-15）。 | 🔴 **順豐月結合約條款／商務窗口書面回覆。不是文檔問題，再查網頁也不會有答案。** | `shipment_void.billed_if_unused` 等三欄維持 `null`。**過渡辦法見 §D.5(g)**：宣告 `supported: false` ＋ reason，走人工銷號佇列 | §D.5 |
| **V-43**<br>🟡 **已拆分並縮小** | 順豐**香港站與丰桥是否為同一套 API**；香港商戶要對接走哪個入口<br>**2026-08-12 二輪拆成兩問**：<br>✅ **香港作為「目的地」**＝同一套 API（國際件與國內件同用 `OrderService`、同一端點，`d_deliverycode=852`、支援 `HKD`）——SF-19。<br>❌ **香港作為「寄件地」**＝**仍未確認**。丰橋文檔全篇以中國內地為寄件地；香港站無開發文檔。**我方首發需要的正是後者。** | 順豐香港商務窗口（**商務問題，非文檔問題**） | `serviceable_lanes = []` ⇒ 無任何服務可用 | §H.2、§H.5 |
| **V-44**<br>🟡 **已縮小** | 順豐**香港／中港澳／國際的服務代碼值域**與各自可用性<br>**2026-08-12 二輪已確認**：香港端**服務名稱**為「標準快遞 / Standard Express」與「國際特惠 / Economy Express」，涵蓋 40＋ 目的地含澳門、台灣（B-19，順豐香港官網價目表）。<br>**仍缺**：名稱到 `express_type` **數值代碼**的對應——官方 PDF 明指值域在附錄《快件產品類別表》，**該附錄未含於 PDF 內，亦未給出檔名或 URL**（SF-19）。 | 順豐香港商務窗口；或索取《快件產品類別表》附錄 | 同上 | §H.2、§H.5 |
| **V-45** | **DHL Express／UPS／FedEx 的逐項能力值**：面單格式代碼與尺寸代碼、作廢／取消的時間窗與是否釋放號碼、推送 webhook 的驗簽方式 | DHL：`developer.dhl.com`（Reference Data Guide）；UPS：`developer.ups.com`；FedEx：`developer.fedex.com`。**本輪僅取得 DHL 的端點與操作分類**（B-8），UPS／FedEx 僅有第三方佐證 | 三個 pack 皆 `enable_gate: [V-45]`，不得 enable | §B.1 |
| **V-46**<br>🟡 **已部分結案** | 順豐的**限流（QPS／日配額）與逾時重試建議**<br>**2026-08-12 二輪**：QPS／日配額／重試建議——**再次覆核兩份官方 PDF，確認通篇未載明**（SF-7 維持）。**但取得了另一類真實的官方上限**：`OrderFilterService` ≤5、`RouteService` ≤10 個 `tracking_number`、`RoutePushService` ≤10 個 `WaybillRoute`、RLS 路由標籤批次 ≤100（超過回 `0003`）、`OrderZDService` 的 `parcel_quantity` ≤20（SF-18）。**這些是分批上限，不是速率上限——兩者不可互相替代。** | 丰桥控制台的配額頁；或與順豐技術窗口確認 | 速率：客戶端自我節流取 `limits.carrier.client_qps_default`（保守值），**不假設物流商端無限制**。<br>分批：一律取 `limits.carrier.packs.sf_express.documented_limits.*`，**不得硬編**（鐵律 6） | §F.5 |
| **V-47**<br>🟡 **部分結案，且答案改變了處置方向** | 順豐**路由推送**的**驗簽方式、重送策略、事件代碼值域**<br>**2026-08-12 二輪已確認（官方）**：舊世代 `RoutePushService` **沒有定義任何驗簽欄位**；接收方只能回 XML `OK`／`ERR`；失敗時順豐重推全部資訊但**未載明次數與間隔**（SF-16）。路由操作碼**未在規範內列舉**，僅示例 `50`／`922`（SF-17）。<br>**仍缺**：新世代 `EXP_RECE_REGISTER_ROUTE` 的推送是否附簽章；事件代碼完整值域。 | 同 V-41（目錄頁）；事件碼另需順豐「文檔中心」的操作碼表 | **處置已改**：`push_verification` 不再是「等一個值」，而是**必須明確二選一**（`carrier_signature` 或 `none` ＋ 四項補償控制，見 §C.4 第 2 點）。`event_code_vocabulary` 仍為 `null` ⇒ **不得 enable**。**不得**拿 `50`／`922` 兩個示例值當值域 | §C.4 |
| **V-48**<br>⏳ **仍開** | 順豐 **COD（代收貨款）在香港的可用性、上限、撥款週期與對帳檔格式**<br>**2026-08-12 二輪**：順豐香港官網價目表（B-19）與聚合商文檔（B-18）**均未提及** COD。仍無任何來源。 | 順豐香港商務窗口（屬合約值，非 API 文檔） | `cod` 整項為 `null`；COD × 順豐的組合在結帳頁不出現 | §A.2 K9 |
| **V-49**<br>✅ **已實質結案（2026-08-12）** | 順豐的**冪等機制**：`requestID` 是否被伺服器端去重、重送的語義<br>**答案**：①**`requestID` 沒有證據被去重**——官方 SDK 只把它示範成每次新產生的 UUID，未賦予任何去重語義 ⇒ **一律當作不去重**；②**真正被去重的是 `orderid`（客戶訂單號）**，重複會下單失敗並回 `8016`；③**`8016` 回錯誤、不回放原結果**（錯誤報文不夾帶 `mailno`）。 | 已由 B-1／B-2 官方 PDF 結案 | **三條實作後果**：①我方第一層冪等必須完全自理，不得指望第二層；②`orderid`＝`client_reference`＝`shipment_intents.id`，且**永不重用**（`client_reference_reuse_forbidden`）；③🔴 **`8016` 必須映射成 `unknown` 而非 `business_rejected`**，走 §F.4 回查。映射表與必要測試見 §E.2 | §E.2 |
| **V-51**<br>🔴 **新登記（本輪發現的誤標）** | 順豐 `msgDigest` **簽章演算法**：串接順序、雜湊演算法、編碼方式。官方 SDK 只暴露方法簽名 `getMsgDigest(msgData, timeStamp, checkWord)`，**兩份官方 PDF 均未載明演算法本身**（SF-11，二輪再次覆核仍未載明）。 | 丰桥開發者入口的簽章說明；或**直接讀官方 SDK 的 jar／zip**（SDK 指南提及 `SF-CSIM-EXPRESS-SDK-V2.1.6.jar` 但**未給下載 URL**，本輪亦無法下載二進位檔） | 🔴 **這是 `sf_express` 的第一號阻塞項——算不出簽章就一個請求都送不出去。** 原本因誤標成 V-40 而完全不在 `enable_gate` 裡，本輪已補入 | 全 pack 的連線 |
| **V-52**<br>🟡 **新登記（低優先）** | 順豐憑證究竟是**兩件式**（`clientCode` ＋ `checkword`，SF-3）還是**三件式**（`customer_code` ＋ `customer_id` ＋ `checkword`，聚合商 EasyPost 的要求，SF-24） | 丰桥控制台的憑證頁；或申請沙箱後實測 | `credential_schema` 以官方 SDK 的兩件式為準，但**設定頁預留第三欄位並標為選填**，待覆核 | §G.2 |
| ~~**V-50**~~ **已結案** | 「所有幣別顯示兩位小數」與 ISO 4217 minor unit 的關係 | **已由同日（2026-08-12）新增的 `limits.currency_display` 裁定解決**：`force_minor_unit_digits: 2`、`storage_scale_unchanged: true`、`iso4217_zero_decimal_overridden: [JPY, TWD]`，且 `currency_format.exponent` 語義改為「顯示位數」（TWD 0→2） | 本檔 §G.3 已依此改寫：**換算一律 ×100，不得用 `exponent`**；`limits.carrier.money.storage_multiplier: 100` | 已無阻塞 |

---

## 附錄 B：本輪查過的 URL（可追溯性）

| # | URL | 取得了什麼 | 出處等級 |
|---|---|---|---|
| B-1 | `https://qiao.sf-express.com/doc/download/SF-CSIM-API.pdf` — 丰桥平台 API 接口規範 V3.8（2021-01-14） | 舊世代（XML）服務清單（SF-5）；查單介面存在理由（SF-6）；**確認未載明限流／冪等**（SF-7） | `carrier-official` |
| B-2 | `https://qiao.sf-express.com/doc/download/laas/sdk/丰桥SF-CSIM-EXPRESS-SDK指南.pdf` — 官方 Java SDK 指南 | 端點 URL（SF-1）、請求信封六欄（SF-2）、憑證兩件式（SF-3）、八個服務代碼（SF-4）、`getMsgDigest` 方法簽名（SF-11） | `carrier-official` |
| B-3 | `https://qiao.sf-express.com/`、`https://qiao.sf-express.com/pages/developDoc/index.html` | **只取得 meta 標籤**（JS 渲染 SPA） | `carrier-unobtainable` |
| B-4 | `https://open.sf-express.com/Api`、`https://open.sf-express.com/Api/ApiDetails?level3=317&interName=雲打印面單2.0接口-COM_RECE_CLOUD_PRINT_WAYBILLS` | **只取得 meta 標籤**；介面名僅從搜尋結果標題得知（SF-8） | `carrier-unobtainable` |
| B-5 | `https://pkg.go.dev/github.com/yayiyo/sf-express-sdk` | 開源 SDK 的服務代碼常數表（SF-9）、`WithPartnerID` / `WithCheckWord` 佐證 SF-3 | `carrier-secondary` |
| B-6 | `https://www.cnblogs.com/lihao1017/p/17361972.html`、`https://www.psvmc.cn/article/2024-10-04-express-inquiry-sf.html` | 請求信封六欄的第三方佐證；端點網域的**不一致寫法**（SF-10） | `carrier-secondary` |
| B-7 | `https://htm.sf-express.com/hk/tc/…`、`https://hk.sf-express.com/hk/tc/waybill/list`、`https://www.wavecommerce.hk/blog-zh/shopify-sf-express-hk` | 香港站為商用說明頁；提及批次面單工具，**但無開發文檔** | `carrier-unobtainable` / `carrier-secondary` |
| B-8 | `https://developer.dhl.com/api-reference/dhl-express-mydhl-api` | DHL 操作分類（11 類）、測試／生產端點、BasicAuth；**格式代碼未在該頁列出** | `carrier-official` |
| B-9 | UPS 開發者文檔（搜尋結果，未逐頁覆核） | 操作分類（Rating／Shipping／Label Recovery／Void Shipment） | `carrier-secondary` |
| B-10 | `https://developer.fedex.com/api/en-us/catalog/ship.html`（搜尋結果，未逐頁覆核） | Ship／Cancel Shipment／Open Ship 分類存在 | `carrier-secondary` |
| B-11 | `https://www.shipany.io/…`、`https://apps.shopify.com/shipany-1` | 香港市場實務上以**聚合商**為主流接法（批次面單、多平台同步） | `carrier-secondary` |

**第二輪查證新增（2026-08-12）**

| # | URL／來源 | 取得了什麼 | 出處等級 |
|---|---|---|---|
| B-12 | **DNS 解析**（容器內 `getent ahostsv4`，2026-08-12）：`sfexpress.com`／`sfapi.sfexpress.com`／`sfapi-sbox.sfexpress.com`／`sfapi.sf-express.com`／`sfapi-sbox.sf-express.com` | **V-38 結案**：無連字號的三個**皆無 A 記錄**，有連字號的兩個正常解析（SF-12） | `carrier-official`（權威 DNS 優於 PDF）|
| B-13 | `https://open.sf-express.com/Api/ApiDetails?level3=317&interName=雲打印面單2.0接口-COM_RECE_CLOUD_PRINT_WAYBILLS` — **頁面標題**（正文仍為 JS 渲染，取不到） | 雲打印 2.0 的介面名、服務代碼、分類（SF-20） | `carrier-official`（標題由順豐頁面自身輸出）|
| B-14 | `https://open.sf-express.com/Api/ApiDetails?level3=320&interName=ISV刪除自定義模板接口-COM_RECE_CLOUD_CUSTOMTEMPLATE_DELETE` — 頁面標題 | 面單模板可自訂（SF-20） | `carrier-official` |
| B-15 | `https://open.sf-express.com/Api?category=4&apiClassify=1` — 頁面標題「冷運API」 | `category=4` 的分類名（SF-21） | `carrier-official` |
| B-16 | `https://open.sf-express.com/Api/ApiDetails?apiClassify=2&apiServiceCode=RoutePushService&category=1&interName=路由推送接口-RoutePushService`；`…level3=396…EXP_RECE_SEARCH_ORDER_RESP` — 頁面標題「…-速運類API」 | `category=1`＝速運類API、`apiClassify=2`＝推送型（SF-21） | `carrier-official` |
| B-17 | `https://doc.fw199.com/docs/h7b/sf-waybill-cloudprint` — 第三方閘道商的順豐雲打印文檔 | 雲打印**1.0** 的輸出形態（PDF）、模板代碼與尺寸的疑似值域（SF-22、SF-23） | `carrier-secondary`（**且版本不符，標的為 1.0 非 2.0**）|
| B-18 | `https://docs.easypost.com/carriers/sf-express-guide` — 聚合商 EasyPost 的順豐對接指南 | 面單可得 ZPL／PNG／PDF（**屬聚合商轉檔**，SF-23）；憑證疑為三件式（SF-24）；順豐服務層級含國際標快／國際特惠 | `carrier-secondary` |
| B-19 | `https://htm.sf-express.com/hk/tc/download/HKSEEX_TC.pdf` — **順豐香港官網**的國際服務價目表 | 香港端服務名稱＝標準快遞／國際特惠，涵蓋 40＋ 目的地含澳門、台灣；**未提及 COD、月結、API**（V-44 部分、V-48 仍開）| `carrier-official`（順豐香港官方文件）|
| B-20 | `https://apps.shopify.com/sf-express-elctronic-waybill` — 第三方 Shopify App | 香港／澳門／中國市場存在「順豐電子面單」對接方案，**要求順豐月結帳號**，支援批次建單與批次列印 | `carrier-secondary`（佐證香港對接在商業上可行，**不佐證任何介面細節**）|

**本輪試過但取不到的路徑（記錄下來以免下一輪重複）**

| 路徑 | 結果 |
|---|---|
| `https://qiao.sf-express.com/Api?category=1&apiClassify=1`、`?category=6&apiClassify=2`（使用者提供）| WebFetch 只得 `<meta>`；**正文由 JS 渲染** |
| `https://qiao.sf-express.com/robots.txt`、`/sitemap.xml` | **回 SPA 外殼**（該站對未命中靜態檔的路徑一律回退 index.html）⇒ 無法用站內索引枚舉 |
| 容器內 `curl` 直連 `qiao.sf-express.com` | 出口政策 **CONNECT 403** |
| `https://web.archive.org/cdx/search/cdx?url=open.sf-express.com/Api*` | 出口政策 **403**（該網域被阻擋），無法用 CDX 枚舉歷史 URL |
| 第三方渲染／代理服務（`r.jina.ai`、`api.microlink.io`、`api.codetabs.com`、`api.allorigins.win`）| 分別為 403／robots 禁止／robots 禁止／逾時 |
| GitHub 程式碼搜尋（找 SDK 常數表）| 本 session 僅允許 repo-scoped 端點，搜尋 API 回 403 |

> ⭐ **下一輪最有效的一步**：**用能執行 JS 的瀏覽器開 `https://qiao.sf-express.com/Api?category=1&apiClassify=1`**。使用者已確認該文檔**不需帳號**，缺的只是 JS 渲染能力。一次渲染即可同時結案 **V-37／V-39／V-41／V-47（事件碼）／V-51**——本輪剩下的技術性缺口幾乎全部集中在這一步。V-42／V-43／V-44／V-48 則**無論如何都不會由網頁回答**，那是商務與合約問題。

> **本附錄的用途**：V 編號結案時，實作者應在此表新增一列，標明「以什麼來源、什麼日期覆核」。**不得**只把 V 編號從 `enable_gate` 拿掉而不留來源。

---

## 附錄 C：本檔與既有規格的引用關係

| 既有規格 | 本檔怎麼用它 | 本檔**沒有**改它 |
|---|---|---|
| `46a`（官方 orders/returns 文檔） | FO 狀態機、`supportedActions` 十二值、`requestStatus` 不變量、hold reason 八值——**全部照抄不改** | ✅ 未改動任何 46a 語義 |
| `16`（訂單／履行／退款） | §C 接在 F3.1 的狀態機上；§C.2 只**增加** `supportedActions` 第 1 列的一個計算輸入（不新增 enum 值） | ⚠️ F3.3 與 F3(3) 有法域衝突，**本檔只提出、未改**（見 §H.3 警示與回報 ④） |
| `56`（法域架構） | §A.3 的 reject 原則、`capability_skips` 表形態、pack enable gate——**同構借用** | ✅ 未改 56；carrier 與 jurisdiction 保持正交 |
| `15`（購物車／結帳／付款） | §A.1 K1 降級到靜態運費表、K9 進付款×配送相容矩陣、§H.2 服務不可用時不出現在結帳頁 | ✅ 未改 15 的金額引擎 |
| `28`（API 契約） | §I 的命名、`userErrors`、cursor 分頁、非同步 job 形狀、通用錯誤碼複用鐵律 | ✅ 只新增 8 個專屬碼，不造同義碼 |
| `11`（生產級基線） | §K 七維度、§E.2 的冪等回放語義、§F.1 的 transaction 事故模型 | ✅ 未改 |
| `docs/design/chilllove-admin-v2.html` 的 `fo*` 系列 | §C.3 的三個後果直接約束了 `foActionBar` / `foDo` 的行為：**不新增 action、不借用 `EXTERNAL`**；carrier 的外部連結走運單卡 | ✅ **本檔未改動任何 `docs/design/*.html`** |
