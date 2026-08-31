# 58 — 物流商對接架構（Carrier Integration）

> **緣由**：使用者 2026-08-12 裁定逐字：「**順豐有專門的開發文檔.用來對接我們這個項目.我們會對接很多不同的物流商.進行訂單發貨和訂單運單打印等等.例如 順豐的開發文檔 https://qiao.sf-express.com/ 所以...這些都需要寫入開發文檔需求裡面.**」
> **本檔的全部價值在一句話**：**順豐是第一個實作，不是規格的主體。** 主體是 carrier adapter 這一層抽象——照 56 號 jurisdiction pack 的同一套設計哲學，把「物流商」抽成可插拔的 pack，順豐、DHL、UPS、FedEx、手動出貨全部是這層的實作。凡是寫成 `if carrier == 'sf'` 的分支，都是本檔要防的東西。
> **權威順序**（沿用 52／54／55／56／57）：官方開發文檔 ＞ 官方商家文檔 ＞ 實測 ＞ 我方既有規格。**我方與官方衝突時一律改我方。**
> **2026-08-12 第三輪：使用者裁定推翻了前兩輪的多條保守結論。** 使用者提供兩項決定性資訊：**①「順豐你理解錯了。香港地區可以作為發貨地。已經成功開發過。」②我方實際會用到的順豐 API 就 6 支**（逐字清單見 §0.4(e)）。
> 前兩輪由「官方文檔沒寫」推得的否定結論**不再成立**——**使用者的一手實作經驗屬「實測」級，權威性高於我方從文檔缺席推得的推論**（見 §0.3 新增的 `user-ruling` 等級）。逐條推翻清單見 **§0.5**。
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
   🟢 **（2026-08-12 第四輪）「順豐不計費」現在是使用者裁定的事實了（A-2，SF-30／B-23）——而本條依然一個字都不用改。**
   這正是第二輪換樑的價值：**本條的依據早在第二輪就已經從「有價」換成「不可回收」**，所以計費一問結案時，它不需要被重新論證，只需要把 §D.5(d) 的告警等級從**成本告警**降為**資料一致性告警**。**銷號帳仍是硬要求，不是選配。**
   🔴 **防回退**：任何人不得以「順豐已裁定不計費」為由，主張 §D.5 可以刪減或降級為選配。取號依然是**不可回收的外部副作用**（SF-14），這一條與錢無關。
4. **carrier ≠ fulfillment service。** 這兩個概念在 46a 的模型裡是不同的東西，混在一起會污染 `requestStatus` 這條軸。完整論證見 §C.3——**這是本檔最容易被實作者做錯的一條**。
5. **carrier pack 與 jurisdiction pack 正交。** 兩者都可插拔，但不是同一層，也不可互相繼承。物流商的**可用性**是法域的函數，物流商的**能力**不是。見 §H。

### 0.3 出處等級（在既有四級 dev／help／live／ours 之外新增三級）

| 等級 | 意義 | 可否據以寫死實作 |
|---|---|---|
| `carrier-official` | 物流商**官方**發布的文檔（官網 PDF／官方開發者入口頁）。URL 見 §附錄 B。 | ✅ 可 |
| `carrier-secondary` | 第三方來源（開源 SDK 的常數表、技術部落格、聚合商說明頁）**佐證**了某個介面名或行為。**可寫進規格作為「疑似值」，但一律同時登記 V 編號**，實作前須以官方文檔或實測覆核。 | ⚠️ 需覆核 |
| `carrier-unobtainable` | 本輪**確實取不到**：頁面需登入、或文檔未公開、或已窮盡下列取得手段仍無正文。**一律寫「未能取得」並登記 V 編號，不得推測補寫。** | ❌ 禁止 |
| `user-ruling`<br>**（2026-08-12 第三輪新增）** | **使用者的一手實作經驗或範圍裁定**（例：「香港地區可以作為發貨地，已經成功開發過」）。在權威順序上屬**實測**級。 | ⚠️ **只能據以推翻「因為文檔沒寫所以做不到」這類否定推論，或據以劃定對接範圍；不得據以填入任何具體參數值。** 使用者給的是**事實與範圍**，不是欄位表 |

> 🔴 **`user-ruling` 的邊界必須守住，否則它會變成新的猜測來源。**
> 它能做的：把「我方查不到 ⇒ 保守判為不可行」**降級為「我方查不到，但已知可行」**。
> 它不能做的：**替我方生出 `express_type` 的數值、面單模板代碼、欄位名。** 那些仍是 `carrier-unobtainable`，仍要登記 V 編號，只是**處置從「阻塞 pack」降為「實作期以帳號實測確認」**——因為已知那條路走得通，只是我方還沒親眼看到值。
> **判準一句話**：`user-ruling` 改變的是**可行性判斷**，不是**參數值**。

> **（2026-08-12 第四輪新增）`user-ruling` 的第二個合法用途：營運／合約裁定。**
> 上面那條邊界（「不得據以填入參數值」）針對的是**物流商的 API 事實**——`express_type` 的數值、面單模板代碼、`msgData` 的欄位名。那些東西使用者憑記憶說不出來，說出來也是猜的，所以擋掉是對的。
> **但有一類值不屬於「物流商的 API 事實」，而屬於「我方的商務與營運事實」**——典型就是 `billed_if_unused`（取號未使用是否計費）。它：
> - **不寫在任何 API 文檔裡**（SF-15 已經確認過這一點），所以再查一百個網頁也不會有答案；
> - 它的權威來源是**月結合約與商務關係**，而**合約的當事人是使用者本人，不是我方 agent**；
> - 使用者對它的裁定同時包含**一個事實斷言**（實際上不收）與**一個營運承諾**（若判斷有誤，成本由營運承擔）。
>
> ⇒ 這一類值**可以**由 `user-ruling` 填入，但必須同時滿足三個條件，缺一不可：
> 1. 該值已確認**不在 API 文檔的涵蓋範圍內**（否則就該去查文檔，不該問人）；
> 2. 填入後在規格與 `limits.yml` **兩處都標明依據為 `user-ruling`**，並在附錄 A 保留該 V 編號的完整脈絡（**結案不等於刪除**）；
> 3. 🔴 **填入的值只能影響「告警等級／營運姿態」，不得影響「機制存廢」**——因為使用者裁定的是成本，不是資料正確性。
>
> **反例（用來校準）**：使用者若說「順豐的 `mailno` 取消後會回收，可以重用」，**那不能填**。那是物流商的 API／系統行為，不是我方的合約條款，使用者不是它的權威來源，而且它會直接改變機制（重用識別）而不只是告警等級。

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
| SF-4 | 官方 SDK 提供的服務代碼（節錄，均為 `serviceCode` 的值）：`EXP_RECE_CREATE_ORDER`（下單）、`EXP_RECE_SEARCH_ORDER_RESP`（訂單結果查詢）、`EXP_RECE_UPDATE_ORDER`（訂單取消／確認——**名稱與我方用途的釐清見 SF-29：我方只用「取消」**）、`EXP_RECE_FILTER_ORDER_BSP`（訂單篩選）、`EXP_RECE_SEARCH_ROUTES`（路由查詢）、`EXP_RECE_GET_SUB_MAILNO`（子單號申請）、`EXP_RECE_QUERY_SFWAYBILL`（運費查詢）、`EXP_RECE_REGISTER_ROUTE`（路由註冊） | B-2 |
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
| SF-22<br>🟡 **部分被取代** | 雲打印面單的~~回傳檔案形態疑為 PDF~~——**形態一問已由 SF-26 結案且答案更精確**：順豐是**一種輸出一支介面**（`…PRINT_WAYBILLS`＝PDF、`…PRINT_HTML`＝HTML、`…PRINT_COMMAND`＝指令流），**不是同一支介面用參數切格式**。**仍未被取代的部分**：模板以「模板代碼」選定、尺寸為離散值域，疑似含 `100×150` / `100×180` / `100×210` / `76×130` 四種國內規格與 `100×150` / `100×210` 兩種國際規格；請求疑有 `fileType`、`masterWaybillNo`、`branchWaybillNo` 等欄位——**這些值一律不得寫進 pack** | B-17（第三方閘道商的順豐雲打印文檔，**標的為 1.0 版，非官方 2.0**）；形態部分 → SF-26 | **V-39（僅剩模板／尺寸／欄位）** |
| ~~SF-23~~<br>🔴 **本輪推翻** | ~~未見任何來源指出順豐雲打印介面本身會輸出 ZPL 指令流~~——**這句是錯的。** 順豐**確實有** `COM_RECE_CLOUD_PRINT_COMMAND`（雲打印面單轉**指令**接口），見 **SF-27**。原句成立的唯一理由是我方當時只掃到雲打印組的一部分。**仍然成立的部分**：聚合商 EasyPost 提供的 `ZPL`／`PNG`／`PDF` 三形態是**聚合商自己的轉檔輸出**，不等於順豐原生支援——但順豐原生**確實有指令流介面**，只是我方**範圍不含它** | → **SF-27**（B-22） | ~~V-40~~ 已結案（理由已改寫，見 §0.5 第 3 列）|
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
| ~~完整介面目錄（全部 `category` 分類名稱）~~ → **僅剩逐介面欄位表** | **2026-08-12 第三輪：目錄層已取得**（九大分類 ＋ 速運通用寄件類 ＋ 雲打印組，SF-28）——手段就是上一輪標為「未試而可行」的那一條：**用能執行 JS 的瀏覽器渲染**。**仍取不到**：逐介面的請求／回應**欄位表**（明細頁需逐頁渲染，且部分欄位表疑須登入）。**沒有欄位表就組不出任何一個請求** | **V-41（大幅縮小，仍在 gate）** |
| 雲打印面單的**請求／回應欄位、模板代碼與尺寸**的官方值域 | **格式一問已結案**（SF-26：PDF 與 HTML 各一支專屬介面）。**仍取不到**：欄位表、模板代碼、尺寸值域。第三方 1.0 版佐證（SF-22）**不可直接當 2.0 用** | **V-39（縮小，仍在 gate）** |
| 順豐**運單號**（`mailno`，非 `orderid`）取消後是否回收、~~未使用是否計費~~、銷號時間窗 | 官方兩份 PDF 逐節覆核後確認**通篇沉默**（SF-15）。取消動作本身與 `orderid` 的不可重用性已取得（SF-14）。**此項本質上是月結合約條款，不在 API 文檔的涵蓋範圍內**——這不是「文檔沒抓到」，是「這件事根本不寫在 API 文檔裡」。<br>🟢 **2026-08-12 第四輪：「未使用是否計費」已由使用者裁定 A-2 結案（不計費，SF-30／B-23）** ⇒ V-42 結案並移出 gate。**另外兩問（`mailno` 是否回收、銷號時間窗）仍無來源**，維持 `unknown`／`null`，⇒ **號碼一律不重用** | ~~**V-42**~~ **🟢 已結案（`user-ruling`，移出 gate）**；剩餘兩問改列**實作期／商務確認項**，仍登記於附錄 A |
| ~~**香港商戶**能否以香港為**寄件地**下單~~ **⇒ 已由使用者裁定結案** | 🟢 **本輪結案（`user-ruling`）**：使用者已實際開發過，香港可作為發貨地（SF-25）。**我方從「丰橋文檔全篇以中國內地為寄件地」推得的否定結論作廢**——那是文檔取樣的缺口，不是產品的缺口。**仍未取得**：香港 origin 的帳號開通路徑與服務代碼**數值** | **V-43（結案，改列實作期確認項；移出 gate）** |
| `express_type`（快件產品類別）的**數值值域** | 官方 PDF 明指值域在附錄《快件產品類別表》，而**該附錄未含於 PDF 內**，亦未給出獨立檔名或 URL（SF-19）。香港端的**服務名稱**已取得（標準快遞／國際特惠，B-19），但**名稱到數值代碼的對應仍缺**。**性質已改**：既然 origin 可行已確認（SF-25），這就從「不知道能不能做」降為「知道能做，還沒看到值」⇒ **實作期以帳號實測填入，不擋 pack**；在填入之前，lane 的 `service_code` 為 `null` 且**該 lane 不得對外可選**（§H.2） | **V-44（降級為實作期確認項；移出 gate）** |

> **對 §0.4(c) 的處置**：`carrier/sf_express` pack 在這些填值到手之前，其 `enable_gate` **不得為空**（見 §H.4）。也就是說——**順豐 pack 在本輪仍不可上線**，只能建骨架。這與 56 §A 對未定案 pack 的處置一致：能力沒宣告完，pack 就不准 enable。
>
> **但第三輪之後，gate 的長度與組成都變了，而且變化的方向值得記住**（完整前後對照見 §0.5 第 8 列、新 gate 見 §H.4）：
>
> | 變化 | 項目 | 為什麼 |
> |---|---|---|
> | **移出（使用者裁定）** | V-43、V-44 | 香港 origin 可行已由一手經驗確認（SF-25）。缺的只剩**數值**，而數值缺口的正確處置是「lane 的 `service_code` 為 `null` ⇒ 該 lane 不可選」，不是「整個 pack 不可 enable」——**用最小的鎖，鎖最小的範圍** |
> | **移出（範圍決策）** | V-47、V-48 | 6 支不含路由推送註冊、不含 COD ⇒ K7／K9 直接宣告 `supported: false` ＋ reason。**宣告完整就通過 §A.3**——V 編號的用途是擋「不知道會做錯事」，不是擋「我們決定不做這件事」 |
> | **移出（營運裁定，🟢 第四輪）** | **V-42** | 使用者裁定 A-2：**取號未使用不計費**（SF-30／B-23）。這正是 §D.5(g) 明文列出的第 ② 條出口——**上一輪把出口寫清楚，這一輪裁定一到就直接接上，不必重新論證**。⚠️ 移出的是 gate，不是問題：`mailno` 是否回收、銷號時間窗**兩問仍無來源** |
> | **留下（真阻塞）** | V-39、V-41、V-51 | 前兩項見上表；V-51 見下。**三項全是技術缺口，全部只有一條解法：拿到完整開發文檔** |
>
> 🔴 **V-51（`msgDigest` 演算法）第三輪一點都沒被碰到，第四輪也沒有。** 三輪拿到的全部是「有哪些介面、香港能不能寄」，四輪拿到的是一句營運裁定——**沒有任何一條資訊觸及簽章演算法**。它是本檔目前**唯一**不會因為「再多查一次文檔目錄」而縮小的缺口。
>
> 🔴 **V-42 的性質與它的結案方式（留著這段，因為方法論比結論值得記）**：它從「文檔沒抓到」變成「**這件事不寫在 API 文檔裡**」，所以它**永遠不會**因為多抓幾個網頁而結案——它只能由**順豐月結合約或商務窗口**回答，或由**合約當事人本人裁定**。把它留在 `enable_gate` 裡等網頁查證，等於讓 pack 永遠卡住。
> 🟢 **第四輪即以第二條路結案**（使用者裁定，§0.3 的「營運／合約裁定」類）。**gate：4 項 → 3 項 `[V-39, V-41, V-51]`。**
> ⚠️ **但 pack 仍不可 enable**，而且剩下的三項比移出的那項難——**gate 變短，第一號阻塞項一動也沒動**（這句話第三輪寫過一次，第四輪原封不動再成立一次）。

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

**(e) `user-ruling` ＋ 第三輪瀏覽器渲染實得（2026-08-12 第三輪）**

| # | 事實 | 出處等級 | 出處 |
|---|---|---|---|
| **SF-25** | **香港可以作為寄件地（origin）。** 使用者裁定逐字：「順豐你理解錯了。**香港地區可以作為發貨地。已經成功開發過。**你文檔、工程可以解決。」⇒ 這是**已實際開發過**的一手事實。**但使用者給的是可行性，不是參數**：香港 origin 對應的服務代碼／`express_type` 數值，我方**仍未親眼見到**。 | `user-ruling` | B-21 |
| **SF-26** | **我方實際會對接的順豐 API 就下列 6 支**（使用者提供，逐字抄錄；此為**範圍裁定**，不是順豐能力的全集）。 | `user-ruling` | B-21 |
| **SF-27** | 順豐**確實有**雲打印面單轉**指令**接口 `COM_RECE_CLOUD_PRINT_COMMAND`。⇒ **SF-23 的「未見任何來源指出順豐雲打印介面本身會輸出 ZPL 指令流」是錯的，本輪推翻。** 但使用者選定的是 PDF 與 HTML 兩支，**不含指令流**。 | `carrier-official` | B-22 |
| **SF-28** | **平台頂層分類共九類**：速運／基礎通用／冷運／快運／智能科技／解決方案／陸運／**國際件**／供應鏈科技。**速運API「通用寄件類」**含：`EXP_RECE_CREATE_ORDER`／`EXP_RECE_UPDATE_ORDER`／`EXP_RECE_SEARCH_ORDER_RESP`／`EXP_RECE_GET_SUB_MAILNO`（子單號申請）／`EXP_RECE_PRE_ORDER`（預下單）／`EXP_RECE_WANTED_INTERCEPT`（截單轉寄退回）／`EXP_RECE_DELIVERY_NOTICE`（派件通知）／`EXP_RECE_QUERY_SFWAYBILL`（**清單運費查詢**）／`COM_RECE_QUERY_ADDRESS_BOOK_NEW`（地址簿查詢）。**雲打印組**另有 `COM_RECE_CLOUD_PRINT_PARSEDDATA`／`COM_RECE_CLOUD_PRINT_CAINIAO`／`COM_RECE_CITYWIDE_PRINT_SUBMIT`／`_STATUS`／`COM_RECE_CLOUD_CUSTOMTEMPLATE_LIST｜SAVE｜DELETE`。**僅為介面名與分類，欄位表仍未取得。** | `carrier-official` | B-22 |
| **SF-29** | **`EXP_RECE_UPDATE_ORDER` 的名稱有兩個版本，且不衝突**：官方目錄頁作「**訂單確認/取消接口**」，使用者截圖作「**訂單取消接口**」。⇒ 同一支介面多用途（舊世代對應 `OrderConfirmService` 的 `dealtype ∈ {1 確認, 2 取消}`，SF-14）。**我方只用「取消」用途，不使用「確認」用途。** | `user-ruling` ＋ `carrier-official` | B-21、B-22 |
| **SF-30**<br>**（2026-08-12 第四輪新增）** | 🟢 **順豐取號未使用，不會被計費。** 使用者裁定：「**A2 不會計費。**」（對應 `docs/handoff/2026-08-12-open-decisions.md` 的 A-2）⇒ **V-42 的「是否計費」一問結案**，`sf_express.shipment_void.billed_if_unused = false`。<br>⚠️ **這條裁定只答了三問中的第一問。** 另外兩問——**銷號時間窗**（`window_hours`）與 **`mailno` 是否回收**（`frees_number`）——**使用者沒有裁定，官方仍沉默**，兩者維持 `null`／`unknown`，**一律不重用號碼**。<br>🔴 **本條屬 §0.3 新增的「營運／合約裁定」類**：計費與否是**月結合約條款**（SF-15 已確認不寫在 API 文檔裡），合約當事人是使用者，我方 agent 不是；且它只影響**告警等級**，不影響任何機制的存廢（§D.5(a0)）。 | `user-ruling`<br>（營運／合約裁定） | B-23 |

**SF-26 的 6 支（逐字抄錄使用者提供的清單）**

| 接口分類 | 服務代碼 | 介面名稱 | 報文格式 | 狀態 | 關聯日期 | 對應我方能力 |
|---|---|---|---|---|---|---|
| 速運API | `EXP_RECE_CREATE_ORDER` | 下訂單接口 | JSON | 已上線 | — | **K2** `shipment_create` |
| 速運API | `EXP_RECE_SEARCH_ORDER_RESP` | 訂單結果查詢接口 | JSON | 已上線 | — | **§F.4 的 `UNKNOWN` 回查**（不是獨立能力鍵） |
| 速運API | `EXP_RECE_UPDATE_ORDER` | **訂單取消接口** | JSON | 已上線 | — | **K5** `shipment_cancel`（**只用取消用途**，SF-29） |
| 速運API | `EXP_RECE_SEARCH_ROUTES` | 路由查詢接口 | JSON | 已上線 | — | **K6** `tracking_pull` |
| 基礎通用API | `COM_RECE_CLOUD_PRINT_WAYBILLS` | 雲打印面單轉 **PDF** 接口 | JSON | 已上線 | 2024 | **K3** `label_render`（`pdf`） |
| 基礎通用API | `COM_RECE_CLOUD_PRINT_HTML` | 雲打印面單轉 **HTML** 接口 | JSON | 已上線 | **2026** | **K3** `label_render`（`html`）——**新介面**，見 §D.2 |

> **這張表是 §B.1 順豐那一欄的唯一依據。** 能力矩陣裡順豐宣告 `supported: true` 的每一項，都必須在這張表裡找得到支撐它的服務代碼；**找不到的一律宣告 `supported: false` ＋ reason**，理由寫「本次對接範圍不含 …」而**不是**「順豐沒有」——兩者的差別見 §0.5。
> ⚠️ **報文格式全部是 JSON** ⇒ 我方走新世代 `/std/service` 信封（SF-2 的六欄），**不是**舊世代 XML（SF-5）。舊世代的欄位名（`orderid`／`mailno`／`dealtype`／`d_deliverycode`／`express_type`）在本檔中只作為**語義說明**，**不得**直接當成新世代 JSON 的欄位名寫進實作——新世代欄位表仍未取得（V-41）。
> ⚠️ **金額邊界不因這 6 支而改變**（鐵律 3／65 號）：這 6 支若在實作期回傳任何運費或代收金額，一律依 **§G.3** 以十進位字串經 `BigDecimal` 解析成 `*_cents`（×100，不看幣別）。**物流商的十進位字串（R4 wire form）與 PSP 的任何一種格式——整數 minor unit（R5）或十進位主單位字串（R6）——都不是同一件事，不得合併成一個「對外轉換」。**🔴 特別注意 R6 與物流商字串**長得一模一樣**（都是十進位主單位）：主單位型 PSP 出現後，「PSP＝整數、物流商＝字串」這條捷徑判別法失效，判別依據只能是**去向**（psp pack vs carrier pack），型別上 `Money::PspDecimal` ≠ `Money::Decimal`（65 §A 第 3 點）。<!-- 2026-08-31 更正：本句的實證代表原是 Airwallex——其 wire form 已一手複驗為 JSON number（65 R7）；「與物流商字串同形」的現任實證代表＝PayPal（decimal_string）。警句本身不變。 -->
> <!-- 依 65 §J M-9（69 §V-188）修正（2026-08-13），原文末句：「物流商的十進位字串與 PSP 的整數 minor unit 不是同一件事，不得合併成一個『對外轉換』。」結論不變，但原文的字面反推（PSP=整數、物流商=字串）會在 Airwallex 型 PSP 上得出「可與物流商共用轉換」——正是 65 §A 要擋的 R4≠R6 陷阱。措辭對齊 CLAUDE.md 鐵律 3 現行文字。 -->
> ⚠️ **九大分類中「國際件」是獨立頂層分類**（SF-28），而舊世代 PDF 說「國際件與國內件同用 `OrderService`」（SF-19）。兩者可能是世代差異，也可能是分類差異——**本輪不需要解這個矛盾**，因為我方 6 支全部落在速運API／基礎通用API。**但要點亮 HK→海外 lane 之前必須先解**（新登記 **V-53**）。

### 0.5 第三輪推翻了前兩輪的哪幾條結論（逐條可追溯）

> **本節的存在理由**：CLAUDE.md「寫錯的事實比缺漏的事實傷害大」。前兩輪把「我方查不到」寫成了「做不到／沒有」，這一節逐條標出來，並寫清楚**新結論的依據**與**依然保留的誠實邊界**。

| # | 舊結論（前兩輪） | 新結論（本輪） | 依據 | 仍保留的誠實邊界 |
|---|---|---|---|---|
| 1 | 香港作寄件地未確認 ⇒ `serviceable_lanes = []` ⇒ **順豐不能作為 HK 首發物流商**，首發用 `manual` pack | **香港可以作為 origin。** `serviceable_lanes` 納入 HK origin；**V-43／V-44 從阻塞降為實作期確認項**，移出 `enable_gate` | **SF-25**（`user-ruling`，使用者已實際開發過） | 我方**未親眼見到**香港 origin 的服務代碼值 ⇒ lane 的 `service_code` 一律 `null`，**不得憑空編數值**；`service_code` 為 `null` 的 lane 不得對外可選（§H.2） |
| 2 | **「無任何證據顯示順豐雲打印介面本身輸出 ZPL 指令流」**（SF-23） | **錯的。順豐確實有 `COM_RECE_CLOUD_PRINT_COMMAND`（雲打印面單轉指令接口）。** | **SF-27**（`carrier-official`，瀏覽器渲染後的官方目錄） | — |
| 3 | 首發不接 ZPL 指令流，**理由＝「順豐沒有」** | 首發**仍然不接**指令流，但**理由改為「範圍決策」**：使用者選定的 6 支是 PDF 與 HTML，不含指令流 | SF-26 ＋ SF-27 | 🔴 **這個區別很重要**：「範圍決策」代表**隨時可以加**（加一支 `COM_RECE_CLOUD_PRINT_COMMAND` 即可）；「順豐沒有」會讓後人以為**技術上不可行**。同一個結論，兩種理由，維護成本差很多 |
| 4 | 順豐面單格式未知 ⇒ `label_render.formats = null` ⇒ 擋 gate | **格式已定：`[pdf, html]`**，各由一支專屬介面提供（介面名本身就宣告了輸出格式） | SF-26 | **模板代碼與尺寸值域仍未取得** ⇒ `sizes` 仍為 `null`（V-39 縮小但未結案） |
| 5 | `EXP_RECE_UPDATE_ORDER` ＝「訂單確認／取消」（我方寫法含糊，看不出用哪個用途） | 同一支多用途；**我方只用「取消」用途**，不使用「確認」用途 | **SF-29** | 「取消訂單」與「銷號（把號還回去）」**不是同一件事**——後者的**回收**效果官方仍沉默（**計費**一問已於第四輪由使用者裁定結案，SF-30），見 §D.5(h) |
| 6 | `EXP_RECE_QUERY_SFWAYBILL` 語義未覆核 ⇒ K1 `rate_quote` 標 `❔` | 官方目錄顯示它是「**清單運費查詢**」（對已產生的運單清單查費），**且不在使用者選定的 6 支內** ⇒ **K1 宣告 `supported: false`** | SF-28 ＋ SF-26 | 這是**範圍決策 ＋ 語義不符**兩層理由，不是「順豐沒有運費 API」 |
| 7 | 完整介面目錄取不到（V-41），且「下一輪最有效的一步＝用能執行 JS 的瀏覽器開目錄頁」 | **那一步走了，而且有效。** 目錄層已取得（SF-28）：九大分類 ＋ 速運通用寄件類 ＋ 雲打印組 | SF-28（B-22） | **逐介面欄位表仍未取得** ⇒ V-41 縮小為「欄位表」，**仍在 gate**——沒有欄位表連請求都組不出來 |
| 8 | `sf_express.enable_gate` ＝ 8 項 `[V-39, V-41, V-42, V-43, V-44, V-47, V-48, V-51]` | 第三輪 **4 項** `[V-39, V-41, V-42, V-51]`（移出 V-43／V-44 使用者裁定、V-47／V-48 範圍決策）；**🟢 第四輪再移出 V-42（營運裁定：取號未使用不計費，SF-30／B-23）⇒ 現行 3 項 `[V-39, V-41, V-51]`** | §0.5 各列 ＋ §H.4 ＋ §D.5(g) | **移出不等於問題消失**：V-43／V-44 變成實作期確認項，V-47／V-48 變成「未來要加時才需要回答」的問題，**V-42 剩下的兩問（`mailno` 是否回收、銷號時間窗）變成商務確認項**，全部仍登記在附錄 A |

> **（第三輪）兩條一個字都沒被推翻的**：**V-51（`msgDigest` 簽章演算法）** 與 **V-42（銷號計費，屬月結合約）**。第三輪的所有新資訊都沒有碰到它們——前者是「連一個請求都送不出去」，後者是「不會由任何網頁回答」。**它們才是真正的阻塞項**，見 §H.4。
> 🟢 **（第四輪更新）那兩條裡的 V-42 已結案**，走的正是「不會由任何網頁回答」所指向的那條路：**使用者裁定 A-2「不會計費」**（SF-30／B-23）。**V-51 仍原封不動**——第四輪同樣沒有一條資訊觸及簽章演算法，它現在是**唯一**的第一號阻塞項。

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
> 🔴 **（2026-08-12 第四輪補一句）K4 必宣告的理由不只財務，還有資料正確性——而後者不會因為「不計費」而消失。**
> 順豐已裁定不計費（SF-30／B-23），上面那個財務理由對它不成立了，**但 K4 對它依然是必宣告**：`shipment_void` 缺席時，我方背的另一個負債是**一個不可回收、卻沒被結掉的識別**（§D.5(a0) 場景 4）。**「沒宣告」在這一項上同時等於「不知道自己在漏錢」與「不知道自己有兩張面單對得上同一批貨」，後者與錢無關。**

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
| `billed_if_unused` | 取號未使用是否照樣計費 | **這一欄只決定銷號帳的告警等級，不決定銷號帳的存廢**（§D.5(a0)）。`true` ⇒ 逾時未銷是 **P1 成本／財務事故**；`false` ⇒ **P3 資料一致性事故**（🔴 **不是「只是資料髒」**——見下） |

> 🔴 **（2026-08-12 第四輪修正一句話）`false` 那一格原本寫「只是資料髒」，那個說法會害人。**
> <!-- 依 2026-08-12 第四輪使用者裁定 A-2 修正，原文：「`true` ⇒ 逾時未銷是財務事故；`false` ⇒ 只是資料髒」。
>      順豐是本專案第一個 `billed_if_unused: false` 的 pack（SF-30／B-23），所以這一格從此刻起會被真的讀到，
>      而「只是資料髒」會直接誤導實作者把 §D.5(b)/(c)/(e) 當成可以省略的東西。🔴 不得改回。 -->
> `false` 代表**不會被收錢**，**不代表沒有後果**：那個號仍然存在於物流商系統、仍然**不可回收**（SF-14）、仍然可能在 §D.5(b) 場景 4 變成**同一張 FO 的第二張有效面單**（倉庫拿哪一張都看起來對）。
> ⇒ **`false` 的 pack 一樣要跑 §D.5(c) 的閉環等式、一樣要有 (e) 的待銷號佇列。** 差的只是告警的急迫性與通知對象。

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

<!-- 依 2026-08-12 第三輪使用者裁定二（對接範圍＝6 支 API）整欄重寫 sf_express。原欄位值見 git 歷史。 -->

**（2026-08-12 第三輪新增第五個符號，因為前四個表達不了「我們決定不做」）**

| 符號 | 意義 | 對 gate 的影響 |
|---|---|---|
| `⛔` | **我方 pack 宣告 `supported: false` ＋ reason。** 理由可能是**範圍決策**（這次不接這支 API）或**合約未確認**。 | **不擋 gate**——`false` ＋ 非空 reason 是**合法宣告**（§A.3、§D.5(g)） |

> 🔴 **`⛔` 與 `❌` 必須分開，這是本輪最重要的一個表達修正。**
> `❌`＝**物流商沒有這個能力**（技術事實）；`⛔`＝**我方這次不接**（範圍決策）。
> 混用的後果是實作者以為「順豐做不到」，於是永遠不會回來加——而真相是**加一支服務代碼就有了**。ZPL 就是活生生的例子：前兩輪寫成「順豐沒有」，第三輪發現順豐有 `COM_RECE_CLOUD_PRINT_COMMAND`（SF-27）。**寫錯的事實比缺漏的事實傷害大。**

| 能力 | `sf_express`（**依 SF-26 的 6 支重新對照**） | `dhl_express` | `ups` | `fedex` | `manual` |
|---|---|---|---|---|---|
| K1 `rate_quote` | ⛔ **宣告 false**：6 支不含 `EXP_RECE_QUERY_SFWAYBILL`，**且它的官方名稱是「清單運費查詢」**（對已產生的運單清單查費），語義本就不等於下單前試算（SF-28）。降級走 15 的靜態運費表 | ✅ Rating | ❔ V-45 | ❔ V-45 | ❌（宣告 false，改靜態運費表） |
| K2 `shipment_create` | ✅ `EXP_RECE_CREATE_ORDER`（下訂單接口，JSON，已上線）。**欄位表仍缺 V-41** | ✅ Shipment | ❔ V-45 | ❔ V-45 | ❌（手填單號） |
| K3 `label_render` | ✅ **兩支專屬介面**：`COM_RECE_CLOUD_PRINT_WAYBILLS`（→PDF）、`COM_RECE_CLOUD_PRINT_HTML`（→HTML，**關聯 2026，新介面**）⇒ `formats: [pdf, html]`。**`sizes`／模板代碼／欄位表仍缺 V-39** | ✅ Shipment／Get Image | ❔ V-45 | ❔ V-45 | ❌ |
| K4 `shipment_void` | ⛔ **宣告 false（§D.5(g) 過渡，維持）**：6 支裡的 `EXP_RECE_UPDATE_ORDER` 取消的是**訂單**，它對 `mailno` 的**回收效果官方通篇沉默**（SF-15）⇒ 我方**不宣稱線上銷號能力**，一律進 `VOID_MANUAL_REQUIRED` 人工佇列。<br>🟢 **（第四輪）`billed_if_unused: false`**（使用者裁定 A-2，SF-30／B-23）⇒ 逾期未銷的告警由 P1 成本事故降為 **P3 資料一致性事故**，**V-42 已結案並移出 gate**（§D.5(d)(g)、§H.4）。⚠️ **`window_hours` 與 `frees_number` 仍為 `null`／`unknown`** ⇒ 號碼一律不重用，取消成功**仍不得**寫成 `VOIDED`（§D.5(h) 規則 1） | — V-45 | ❔ Void Shipment V-45 | ❔ Cancel Shipment V-45 | ❌（無號可銷） |
| K5 `shipment_cancel` | ✅ `EXP_RECE_UPDATE_ORDER`（**我方只用「取消」用途**；官方目錄名為「訂單確認/取消接口」、使用者截圖名為「訂單取消接口」，同一支多用途，SF-29）。二次取消回 `8019` ⇒ `too_late`（§E.2） | ✅ Pickup 取消 | ❔ V-45 | ❔ V-45 | ❌ |
| K6 `tracking_pull` | ✅ `EXP_RECE_SEARCH_ROUTES`（路由查詢接口，JSON，已上線）。舊世代批次上限 10（SF-18）；**新世代上限未確認 ⇒ 一律取舊世代的保守值** | ✅ Tracking | ❔ V-45 | ❔ V-45 | ❌ |
| K7 `tracking_push` | ⛔ **宣告 false**：6 支**不含**路由註冊／推送介面 ⇒ 追蹤一律走 K6 輪詢（`limits.carrier.tracking.poll_interval_seconds`）。**⇒ V-47 移出 gate**——沒接推送就沒有驗簽問題 | — V-45 | — V-45 | — V-45 | ❌ |
| K8 `pickup_schedule` | ⛔ **宣告 false**：6 支不含取件相關介面（`EXP_EXCE_CHECK_PICKUP_TIME` 本就只有 SDK 常數表佐證，V-37） | ✅ Pickup | ❔ V-45 | ❔ V-45 | ❌ |
| K9 `cod` | ⛔ **宣告 false**：6 支不含任何 COD 介面，且香港 COD 的可用性與上限屬合約（V-48，仍登記但**移出 gate**）⇒ COD × 順豐在結帳頁不出現 | — V-45 | — V-45 | — V-45 | ❌ |
| K10 `customs_doc` | ⛔ **宣告 false**：6 支不含報關文件介面；且「國際件」在新平台是**獨立頂層分類**（SF-28），與舊世代「國際件與國內件同用 `OrderService`」的敘述未對齊（**V-53**）⇒ 依 §H.2 關卡 1，**跨境 lane 判不可服務** | ✅ Invoice／Landed Cost | — V-45 | — V-45 | ❌ |
| K11 `service_point` | ⛔ **宣告 false**：6 支不含網點查詢（`EXP_RECE_QUERY_GIS_DEPARTMENT`，V-37） | ✅ Service Point | — V-45 | — V-45 | ❌ |
| K12 `address_validate` | ⛔ **宣告 false**：6 支不含地址驗證。**注意 `COM_RECE_QUERY_ADDRESS_BOOK_NEW` 是「地址簿查詢」不是「地址驗證」**（SF-28），語義不同，不得拿來充數 | ✅ Address | — V-45 | — V-45 | ❌ |
| K13 `billing_reconciliation` | ⛔ **宣告 false**：6 支不含對帳檔介面 ⇒ **§D.5(c) 的外部閉環驗證改為人工**（B.2 已規定該顯示什麼） | — V-45 | — V-45 | — V-45 | ❌ |

**這張表的三個結論**

1. **`sf_express` 的十三項本輪全部有非 null 的宣告**（3 個 `✅` ＋ 10 個 `⛔`）⇒ **§H.4 的條件 ①② 已通過**。這是第三輪最實質的進展：從「一半的格子是問號」變成「每一格都有人想過」。
   <!-- 依 2026-08-12 第三輪裁定二更新。第二輪原文：「`sf_express` 本輪由 5 個 `—` 降到 3 個（K9／K12／K13；K4 與 K10 升為 ❔）……gate 本輪從 7 項變成 8 項」 -->
   > 🔴 **但「宣告完整」不等於「可以 enable」。** gate 的條件 ③（`enable_gate` 為空）**仍未通過**：**`[V-39, V-41, V-51]`**（第四輪：4 項 → 3 項，移出 V-42）。**能宣告，是因為我方決定了要不要做；不能 enable，是因為決定要做的那三項（K2／K3／K5）還缺欄位表與簽章演算法。** 這兩件事互相獨立，不得互相抵銷。
   > <!-- 依 2026-08-12 第四輪使用者裁定 A-2 更新 gate，原文：「`[V-39, V-41, V-42, V-51]`」。V-42 已結案（SF-30／B-23）。 -->
   > **移出 V-42 之後，剩下的三項全是「拿到完整開發文檔就能結案」的技術缺口**——這也讓 `docs/handoff/2026-08-12-open-decisions.md` A-4（丰橋帳號文檔中心）的投報率變成本 pack 最高的一步：**三條阻塞一次解掉，gate 直接歸零。**
   > **K1 這一格要講清楚「reject 什麼」，否則實作會做成兩種完全不同的東西**（§A.3 的兩種 reject 對象）：
   > | 情形 | 對「向順豐要即時報價」這條路徑 | 對結帳頁 |
   > |---|---|---|
   > | **未宣告**（`null`） | reject ＋ `CARRIER_CAPABILITY_UNDECLARED`，**且擋 pack enable** | — |
   > | **宣告 `false` ＋ reason**（順豐本輪） | **一律不呼叫、不得有任何路徑向順豐要報價**；被觸及即 reject 並落一列 `carrier_capability_skips` | **降級走 15 的靜態運費表**，且**不得出現「即時運費」「預估運費」字樣**（§B.2） |
   >
   > **兩者對那條路徑的結果相同（不准打），對 pack 的結果不同（前者擋 enable、後者放行）。** 把「宣告 false」做成「靜默回 0 元」或「顯示 HK$0.00」是 §B.2 明令的 UI bug——**運費顯示 0 比不顯示更糟，因為它會被當成真的**。
2. **本輪唯一能 enable 的 pack 仍是 `manual`**（十三項全 `false` ＋ reason）。`dhl_express` 仍 5 個 `—`。
3. **`manual` pack 必須先做，而且它不是玩具。** 它是所有 carrier 尚未接通時的正式營運路徑（商家自己去物流商後台下單、回填單號），也是任何 carrier 故障時的降級目的地（§F.5）。
   > **但它的角色本輪降級了**：第二輪把 `manual` 寫成「香港首發**只能**走它」；第三輪香港 origin 已確認可行（SF-25），`manual` 回到它應有的位置——**過渡與降級用**，不再是唯一的首發選項。見 §H.5。

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

<!-- 依 2026-08-12 第三輪裁定二修正。原文起首為：「**K7 推送路徑**（順豐屬此類，`EXP_RECE_REGISTER_ROUTE`）：」
     使用者選定的 6 支不含路由註冊／推送 ⇒ 順豐本輪不走推送路徑，改走 K6 輪詢。 -->

> 🟢 **（第三輪）順豐本輪不走 K7 推送。** 使用者選定的 6 支不含路由註冊／推送介面 ⇒ `sf_express.tracking_push` 宣告 `supported: false` ＋ reason，追蹤一律走 **K6 輪詢**（`EXP_RECE_SEARCH_ROUTES` ＋ `limits.carrier.tracking.poll_interval_seconds`）。
> ⇒ **V-47 移出 `enable_gate`**：沒接推送，就沒有「驗簽方式不明」的問題。**本節以下的推送規格一條都不刪**——它是抽象層的規格，服務於任何要走推送的 pack（也服務於未來把 `EXP_RECE_REGISTER_ROUTE` 加進順豐範圍的那一天）。
> ⚠️ **但輪詢有它自己的代價，必須一起看**：①追蹤延遲上限＝輪詢間隔（推送是秒級，輪詢是小時級）；②每張未終態運單都在消耗配額，而順豐的 QPS／日配額**官方未載明**（SF-7，V-46 仍開）⇒ `stop_polling_on_terminal` 這條規則從「最佳化」升級為**必要條件**，沒有它會在運單量成長後撞上未知的限流。

**K7 推送路徑**（抽象層規格；**順豐本輪不適用**，見上方說明框）：

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
   > ⚠️ 順豐的 `event_code_vocabulary` **仍未取得**：官方規範未列舉路由操作碼，只說「可在文檔中心查看」，文中僅出現示例 `50`（上門收件）、`922`（簽單返還單號）（SF-17）。**不得**拿這兩個示例值當值域。
   >
   > <!-- 依 2026-08-12 第三輪修正。原文末句：「⇒ `sf_express.tracking_push.event_code_vocabulary` 維持 `null`，**pack 仍不得 enable**（V-47 未結案）。」 -->
   > 🔴 **第三輪的修正，而且方向與直覺相反：不接推送，事件碼的問題並沒有消失。**
   > `tracking_push` 宣告 `false` 之後，`event_code_vocabulary` 這個**欄位**確實不再適用（它掛在 K7 的宣告下）——但**問題本身跑到 K6 去了**：`EXP_RECE_SEARCH_ROUTES` 拉回來的路由事件同樣帶操作碼，同樣要映射到我方的 fulfillment event 值域（本節第 5 點）。**把 V-47 從 gate 移出時，若不把這一條寫下來，事件碼問題就會靜靜地換一個入口回來。**
   >
   > ⇒ **fail-safe 規則（適用所有 pack，不只順豐）**：`limits.carrier.tracking.unknown_event_code_action: timeline_only_no_state_change`。
   > 未在 pack 映射表內的事件碼 ⇒ ①**照樣入時間軸**（顯示物流商回傳的原始文字說明，不丟事件）；②**不得**映射到任何終態；③**絕對不得**推導出 `DELIVERED` 或 `READY_FOR_PICKUP`——本節第 5 點的「到店領取 ≠ 已送達」在**未知碼**上更危險，因為猜錯的方向通常是「看起來像送達」；④未知碼比例進 §K 維度 5 的 dashboard，**比例上升代表順豐改了值域**。
   > ⚠️ 這條 fail-safe **不是**把 V-47 結案，是讓它**不必擋著 pack**：值域仍未知（附錄 A 的 V-47 仍開），但未知的後果已經被一條明文規則接住了。
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
| 有無成本 | **看 pack 宣告的 `billed_if_unused`**（順豐＝`false`，SF-30）。**但「不可回收」是無條件的**（見 §D.5） | 通常無 |
| 失敗的代價 | **資料正確性**（必然）＋ 財務（若該 pack 計費） | 可重試 |

<!-- 依 2026-08-12 第四輪使用者裁定 A-2 修正，原文：「| 有無成本 | **有**（見 §D.5） | 通常無 |」
     ＋「| 失敗的代價 | 財務性 | 可重試 |」。
     原文把取號的代價只寫成財務性，那是 §D.5 換樑之前的說法。順豐已裁定不計費（SF-30／B-23），
     若維持原文，讀者會推出「順豐取號沒有代價 ⇒ K2 失敗可以重試 ⇒ 重取一個號就好」——那正是 §D.5(b) 場景 4。
     🔴 **防回退**：「可否重做＝不可」那一列與本列的「資料正確性（必然）」不得因為任何 pack 不計費而放寬。 -->

> 🔴 **本表最重要的一列是「可否重做」，不是「有無成本」。** 成本可以是 `false`，**「重做就是第二個號」永遠是 `true`**（SF-14）。

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

**我方支援的格式值域**（`limits.carrier.label.formats_allowed`）：`pdf` / `html` / `zpl` / `png`。

<!-- 依 2026-08-12 第三輪裁定二新增 `html`。原值域為 [pdf, zpl, png]，寫於「順豐面單格式未知」的時期；
     使用者選定的兩支面單介面是 COM_RECE_CLOUD_PRINT_WAYBILLS（→PDF）與 COM_RECE_CLOUD_PRINT_HTML（→HTML），
     HTML 因此成為**第一個 pack 真的會宣告**的非 PDF 格式。 -->

| 格式 | 用途 | 我方處理 |
|---|---|---|
| `pdf` | 一般雷射／噴墨印表機、批次合併 | 直接存檔、可合併多頁（§D.3） |
| `html`<br>**（第三輪新增）** | 瀏覽器直接列印、後台內嵌預覽 | **原樣存檔，禁止改寫 DOM／注入樣式或腳本**——面單內容一經改寫就不是物流商發出的那張面單。渲染由瀏覽器負責，我方只負責存與送 |
| `zpl` | Zebra 熱感標籤機**指令流**（不是圖片） | **原樣位元組保存，禁止任何轉碼或字串正規化**——ZPL 是指令，改一個位元組就印歪 |
| `png` | 預覽、無驅動環境 | 只作預覽，**不得**作為正式交寄依據 |

**`html` 的四條專屬規則**（新格式，且它與 `pdf` 的差異不只是副檔名）

1. **原樣保存、不得改寫。** 與 `zpl` 的「位元組級不可變」同一個理由，只是載體不同：ZPL 改一個位元組印歪，HTML 改一個節點就是**竄改面單內容**。`limits.carrier.label.html_dom_rewrite_forbidden: true`。
2. **內嵌顯示一律沙箱化。** HTML 面單來自外部系統，直接塞進 admin 的 DOM 等於把第三方 HTML 當自己的頁面執行。一律走 `sandbox` 的 iframe ＋ 不繼承 admin 的 session（`limits.carrier.label.html_render_sandboxed: true`）。這是 `pdf` 沒有的風險，**新增格式就要新增這條防線**。
3. **批次不得合併成單一檔案。** `pdf` 可以合併多頁（§D.3），`html` **不行**——DOM 合併會破壞分頁與樣式，印出來的東西與物流商產出的不同。批次要 HTML ⇒ 逐張輸出；要單檔 ⇒ 走 `pdf`。`limits.carrier.label.html_batch_merge_forbidden: true`。
4. **它同樣是 PII 載體**，與 `pdf` 適用完全相同的私有儲存／簽名連結／保存期規則（下方規則 3）。**不得**因為「HTML 只是預覽」就放寬——它是可正式列印的面單，不是 `png` 那種預覽件。

**三條硬規則**

1. **格式支援度是 per carrier 宣告的**（`capabilities.label_render.formats`），不是全域假設。「有的物流商只給 PDF 不給 ZPL」正是本檔要處理的常態。商家在後台選了 ZPL 但 carrier 只宣告 `[pdf]` ⇒ **設定期就擋下**（回 `userErrors{code: LABEL_FORMAT_UNSUPPORTED}`），不是等到列印時才失敗。
2. **尺寸用代碼不用毫米數。** 尺寸是物流商定義的離散值域（各家代碼不同），我方存 `size_code` 字串 ＋ pack 宣告的 `sizes[]` 清單。**不得**讓商家自填任意毫米數——面單尺寸不對，物流商可拒收。
3. **面單檔案是 PII 載體**（含收件人姓名、地址、電話）。存 Active Storage 私有 bucket，取用一律簽名連結，有效期取 `limits.carrier.label.signed_url_ttl_seconds`；保存期取 `limits.carrier.label.retention_days`，到期由 purge 任務刪除（對應 11 §0 維度 7）。**簽名連結不得寫進日誌。**

<!-- 依 2026-08-12 第三輪裁定二整框改寫。第二輪原文：「⚠️ 順豐面單：介面已確認，欄位仍未取得（V-39 縮小，未結案）……
     ⇒ sf_express 的 label_render.formats 與 sizes 維持 null，pack 不得 enable。」
     被推翻的部分：formats 不再是 null —— 使用者已選定 PDF 與 HTML 兩支專屬介面（SF-26）。 -->

> 🟢 **順豐面單：格式已定案（`[pdf, html]`），模板與尺寸仍未取得（V-39 縮小，未結案）**
>
> **已確認（`user-ruling` ＋ 官方目錄）**——順豐是**一種輸出一支介面**，不是同一支介面用參數切格式：
>
> | 服務代碼 | 介面名稱 | 輸出 | 報文格式 | 狀態 | 關聯日期 | 我方是否採用 |
> |---|---|---|---|---|---|---|
> | `COM_RECE_CLOUD_PRINT_WAYBILLS` | 雲打印面單轉 **PDF** 接口 | `pdf` | JSON | 已上線 | 2024 | ✅ **採用**（正式交寄主格式） |
> | `COM_RECE_CLOUD_PRINT_HTML` | 雲打印面單轉 **HTML** 接口 | `html` | JSON | 已上線 | **2026** | ✅ **採用**（後台預覽／瀏覽器直印） |
> | `COM_RECE_CLOUD_PRINT_COMMAND` | 雲打印面單轉**指令**接口 | 指令流 | — | — | — | ⛔ **不採用（範圍決策，非技術限制）** |
>
> 🔴 **`COM_RECE_CLOUD_PRINT_HTML` 的關聯日期是 2026 ⇒ 這是一支新介面**，實作上必須當「新介面」對待：
> - **不得假設它與 2024 的 PDF 那支同構**——同一族不代表同一份欄位表；請求參數、模板代碼、錯誤碼都要各自覆核。
> - **沙箱可用性要單獨驗證**：新介面在沙箱的開通狀態常晚於目錄上的「已上線」標示。`carrierAccountTest`（§I）必須**逐格式各測一次**，不得測了 PDF 就認定 HTML 也通。
> - 若實作期發現 HTML 那支未對我方帳號開通 ⇒ **`label_render.formats` 縮回 `[pdf]`**（這是**宣告變更**，不是靜默降級），並落一列 `carrier_capability_skips`。
>
> **仍未取得（V-39 未結案）**：兩支的請求／回應**欄位表**、回傳形態（URL／base64／二進位）、**模板代碼與尺寸值域**。第三方 1.0 版的尺寸疑似值（SF-22）**不得寫進 pack**。
> ⇒ `sf_express.label_render.formats = [pdf, html]`（**可以填了**）、`sizes = null`（**仍是 null**）。**pack 仍不得 enable**，但擋住它的已經不是「格式不明」而是「欄位表與尺寸不明」——**縮小的是問題，不是標準。**

<!-- 依 2026-08-12 第三輪裁定二改寫 V-40 的**理由**（結論不變）。第二輪原文的證據段為：
     「沒有任何來源顯示順豐雲打印介面本身輸出 ZPL；第三方文檔明列輸出為 PDF；聚合商雖能給 ZPL，
       但那是聚合商轉檔的產物（SF-23）。」—— 該證據段已由 SF-27 推翻。 -->

> 🟢 **V-40（我方要不要接指令流／ZPL）——結論不變，但理由整段換掉，這個區別很重要。**
>
> | | 第二輪（**已作廢**） | 第三輪（現行） |
> |---|---|---|
> | 事實認定 | ~~順豐沒有指令流輸出~~ | **順豐有** `COM_RECE_CLOUD_PRINT_COMMAND`（雲打印面單轉指令接口，SF-27） |
> | 結論 | 首發不接指令流 | **首發不接指令流**（不變） |
> | 理由 | 「順豐沒有」 | **「範圍決策」**：使用者選定的 6 支是 PDF 與 HTML |
>
> 🔴 **為什麼理由非改不可**：兩種理由指向完全不同的未來動作。
> **「順豐沒有」** ⇒ 後人讀到會以為**技術上不可行**，於是永遠不會回來加，甚至可能為此去接聚合商轉檔。
> **「範圍決策」** ⇒ 後人讀到會知道**加一支服務代碼就有了**，這是純粹的範圍問題，隨時可以重新決定。
> 這正是 CLAUDE.md「寫錯的事實比缺漏的事實傷害大」的具體形態：**錯的不是結論，是理由；而理由才是下一個人拿來做決定的東西。**
>
> **我方架構決策（不變）**：`zpl` 留在 `limits.carrier.label.formats_allowed` 裡（DHL／UPS／FedEx 原生支援，屬抽象層值域），但**不為順豐建任何指令流路徑**。
> 1. **抽象層**：「ZPL 原樣位元組保存」那條規則照留，它是格式的性質，與哪家支援無關。
> 2. **順豐 pack**：`sf_express.label_render.formats = [pdf, html]`——**不含 `zpl`，也不含順豐的指令流**。日後要加，加的是 `COM_RECE_CLOUD_PRINT_COMMAND` 這支服務代碼，並同步加進 `limits.carrier.packs.sf_express.api_scope`（§J）。
> 3. ⚠️ **順豐的「指令流」不必然等於 ZPL。** 介面名只說「指令」，未載明是 ZPL 還是其他熱感指令方言（TSPL／CPCL 等）。**不得假設它是 ZPL**——真要接之前先確認方言，登記為 **V-54**。
>
> **對「我方運單打印要不要接指令流」這個問題的直接回答**：**首發不接。** PDF（正式交寄）＋ HTML（預覽／直印）已經夠用；指令流的位元組級處理（不轉碼、串接以 `^XA`…`^XZ` 為單位）**規格先寫好、程式後做**，等第一個真的要用熱感標籤機的 pack 上線時再實作。**不要為了一個沒有 pack 會用到的格式先寫熱感印表機驅動路徑。**

### D.3 批次打印

**規格**：

- 單次 API 呼叫的運單數上限：`limits.carrier.label.batch_max_per_call`（預設 50）。**超過即分批**，由編排層切，不得讓商家自己算。
- 單一批次作業的總上限：`limits.carrier.label.batch_max_per_job`（預設 500）。超過回 `userErrors{code: TOO_LONG}`（沿用 28 §通用碼，不自造新碼）。
- **批次是非同步的**：回傳 `job{id, done}`，比照 28 對 `orderCancel` 的既有慣例（28:116 已確立非同步 mutation 回 job 的形狀）。
- **部分失敗必須逐張回報。** 批次 20 張有 3 張失敗 ⇒ 17 張的檔案照給、3 張列在 `failures[{waybillId, code, message}]`。**不得**整批回滾——已經產出的檔案回滾也收不回號。
- **PDF 合併**在我方端做（同一批 → 一個多頁 PDF），**ZPL 串接**為原樣位元組相接（以 `^XA`…`^XZ` 為單位，中間不插任何字元）。
- **`html` 不得合併**（第三輪新增，`limits.carrier.label.html_batch_merge_forbidden: true`）：DOM 合併會破壞分頁與樣式，印出來的東西與物流商產出的不同 ⇒ **等同竄改面單**。批次要 HTML ⇒ **逐張輸出**（一張一檔）；要單檔 ⇒ **走 `pdf`**。
  > **給實作者的提醒**：順豐的 PDF 與 HTML 是**兩支不同的服務代碼**（SF-26），所以「同一批用 PDF、預覽用 HTML」是**兩次外部呼叫**，不是同一次呼叫的兩種輸出。批次作業的呼叫計數與 `limits.carrier.label.batch_max_per_call` 要各自計。
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
| **取號未使用是否照樣計費** | **通篇未提**（SF-15） | 🟢 **已結案（2026-08-12 使用者裁定 A-2：「不會計費」，SF-30／B-23）** ⇒ `billed_if_unused: false`。**依據是 `user-ruling`（營運／合約裁定），不是官方文檔**——它本來就不會由 API 文檔回答（屬月結合約），合約當事人是使用者 |
| 可銷號的時間窗 | **通篇未提**（SF-15） | ❓ 未知 ⇒ `window_hours: null`（**使用者未裁定此項**） |

**所以這一節為什麼還在？** 因為它換了一根更硬的樑：

> **不是「號有價所以要記帳」，而是「號不可回收所以要記帳」。**
> 就算最後查明順豐對未使用的號**一毛都不收**，(b) 的五個場景、(c) 的閉環不變量、(e) 的待銷號佇列**一條都不能拿掉**——因為場景 4（換物流商／換箱重取號）造成的是**同一張 FO 掛著兩個都無法回收的識別**，那是**資料正確性事故**，與計費無關：出貨掃描時會有兩張面單對得上同一批貨，倉庫拿哪一張都「看起來對」。
> **計費與否只改變 (d) 的告警等級，不改變任何機制的存廢。** 這正是原文把 `billed_if_unused` 設計成 pack 級宣告（而非全域常數）的價值——**當初的機制設計是對的，錯的只是那句被寫成事實的旁白。**

> 🔴 **（2026-08-12 第四輪）上面那句「就算最後查明順豐一毛都不收」已經從假設變成事實了——本節依然一條都沒拿掉。**
> 使用者裁定 **A-2：「不會計費。」**（SF-30／B-23）⇒ `sf_express.shipment_void.billed_if_unused: false`，**V-42 結案並移出 `enable_gate`**（§H.4）。
> **本輪改的只有 (d) 的一格**：順豐「逾期未銷」的告警從 **P1 成本／財務事故** 降為 **P3 資料一致性事故**。
> **(b) 五個場景、(c) 閉環不變量、(e) 待銷號佇列、(f) 識別不重用、(h) 五條實作規則——一條都沒有拿掉，一個字都沒有放寬。**
>
> **為什麼「不計費」不能拿來拆掉這一節**（這是本節最容易被下一輪誤讀的地方，所以講到不能再白）：
> **場景 4「換物流商／換箱重取號」造成的是同一張 FO 掛著兩個都無法回收的識別。** 順豐官方明載**訂單號取消後不可重複使用**（SF-14），所以舊的那個號**不會消失、也收不回來**，它只是沒有被登記為已結。後果是**倉庫會有兩張面單對得上同一批貨，拿哪一張都看起來對**——
> - 掃錯那張 ⇒ 貨與追蹤號對不上，買家查到的是一張永遠不會動的運單；
> - 兩張都掃 ⇒ 同一批貨被記成兩次出貨；
> - 對帳時 (c) 的等式**表面上是平的**，因為兩個號都還在「未結」那一格互相抵銷。
>
> **這是資料正確性事故，不是成本事故。** 它跟順豐收不收錢**完全無關**——順豐一毛不收，倉庫照樣拿錯面單。
> ⇒ **判準一句話**：`billed_if_unused` 是**告警等級的輸入**，不是**銷號帳存廢的輸入**。任何人拿「反正不計費」當理由來刪 (b)／(c)／(e)，都是把兩個不同的失效模式混成一個。

🔴 **據此撤回一條全域斷言**：`limits.carrier.waybill.number_is_billable_resource: true` 原本是一句**跨所有物流商的事實斷言**，本輪改為 `policy_default`（我方保守**姿態**，不是物流商**事實**），權威一律回到 pack 級的 `capabilities.shipment_void.billed_if_unused`。理由：一個全域 `true` 會讓實作者以為「計費」這件事已經查證過了。

**(a) 運單狀態機**（`waybills.status`）

| 值 | 中文 | 進入條件 | 是否可能已計費 |
|---|---|---|---|
| `ALLOCATED` | 已取號 | K2 `success` | **是（風險期從這裡開始）** |
| `LABEL_RENDERED` | 已產面單 | K3 成功 | 是 |
| `HANDED_OVER` | 已交寄 | 收到第一筆「已收件」追蹤事件，或商家手動標記 | 是（正常計費，這是我們要的） |
| `VOIDED` | 已銷號 | K4 `voided` | 否（正常結果） |
| `VOID_FAILED` | 銷號失敗 | K4 `refused` / `too_late` | **是（需人工）** |
| `VOID_MANUAL_REQUIRED` | 待人工銷號 | carrier **未宣告 K4**，或 **宣告 K4 `supported: false`**（§D.5(g) 過渡，順豐屬此），或逾 `window_hours` | **是（需人工）** |
| `ABANDONED_UNRESOLVED` | 逾期未結 | 超過對帳寬限期仍未落到終態 | **是（財務事故，告警）** |

終態：`HANDED_OVER`、`VOIDED`、`ABANDONED_UNRESOLVED`。

**(b) 觸發銷號的五個場景**（每一個都必須有對應的程式路徑，**缺一個就是一個漏掉的識別**——在計費的 pack 上它同時是漏錢的洞）

<!-- 依 2026-08-12 第四輪使用者裁定 A-2 修正標題括號，原文：「（每一個都必須有對應的程式路徑，缺一個就是漏錢的洞）」。
     順豐已裁定不計費（SF-30／B-23），若維持原文，讀者會直接推出「不漏錢 ⇒ 這五個場景對順豐可以不做」。
     🔴 五個場景一條都沒拿掉：漏掉的**識別**才是主因，漏錢只是計費 pack 上附帶的第二個後果（見 (a0)）。 -->

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

**(d) 告警等級由 `billed_if_unused` 決定——🔴「等級」是這一欄唯一能決定的東西**

| pack 宣告 | 逾期未銷的等級 | 告警**類別** | 通知對象 |
|---|---|---|---|
| `billed_if_unused: true` | **P1** | **成本／財務事故**（每一張都在燒錢） | 店主 ＋ 平台營運 |
| `billed_if_unused: false` | **P3** | 🔴 **資料一致性事故**（**不是**「資料清理」——見下方警語） | 平台營運（記錄 ＋ 進 (e) 的佇列），**不通知店主** |
| `billed_if_unused: null`（未宣告） | **pack 不得 enable**（§A.3） | — | — |

<!-- 依 2026-08-12 第四輪使用者裁定 A-2（SF-30／B-23）改寫本小節。原文：

     「**(d) 告警等級由 `billed_if_unused` 決定**
       | `billed_if_unused: true` | **P1 財務事故** | 店主 ＋ 平台營運 |
       | `billed_if_unused: false` | P3 資料清理 | 僅記錄 |
       | `billed_if_unused: null`（未宣告） | **pack 不得 enable**（§A.3） | — |
       > ⚠️ **順豐是哪一種，本輪仍未取得**（**V-42**），但**理由變了**：不是沒抓到網頁，是**這件事不寫在 API 文檔裡**（SF-15）。
       >    `sf_express` 的 `shipment_void.billed_if_unused` 維持 `null`。
       > **不得**因為「官方沒說會收錢」就填 `false`——**沉默不是否認**。這正是 §A.3 全篇在講的那件事。
       > **（第三輪補一列）** `supported: false`（(g) 過渡）＋ `billed_if_unused: null` ⇒ **P1（取保守側）**、僅平台營運、不通知店主。
       > **這一列是過渡，不是常態**：它存在的前提是 §D.5(g) 的人工佇列真的有人在看（(e) 的畫面）。」

     本輪只改兩件事，其餘一字未動：
       ① 順豐的 `billed_if_unused` 由 `null` 填為 `false`（依據＝使用者裁定，屬 §0.3 第四輪新增的「營運／合約裁定」類）
          ⇒ 第三輪那一列（`supported: false` ＋ `null` ⇒ P1 保守側）的**前提消失**，整列移除：已經沒有 `null` 的順豐了。
          ⚠️ 上一輪那句「**不得**因為官方沒說會收錢就填 false——沉默不是否認」**現在依然成立**，一個字都沒被推翻：
             我方填 `false` 的依據**不是**「官方沉默」，是**使用者這個合約當事人的明示裁定**。兩者是完全不同的依據等級。
             🔴 下一個人若看到 `false` 就以為「原來沉默可以當否認」，那是誤讀——請回頭讀 §0.3 的第二類 user-ruling。
       ② `false` 那一格的告警**類別**由「資料清理」正名為「**資料一致性事故**」，**等級維持 P3**。

     🔴 **防回退（兩個方向都要擋）**：
       - 不得因為「已裁定不計費」就把 `false` 那一格降成「僅記錄／不告警」，或把 (b)/(c)/(e) 當成可以拿掉 —— 理由見 (a0) 的場景 4。
       - 不得把順豐改回 `null` —— 那會讓 pack 重新被 §A.3 擋住，而依據（B-23）是有的。
       - 若日後取得順豐**書面**回覆與本裁定不符：改的是這一格的值與告警等級，**不是** (b)／(c)／(e)／(f) 的存廢。 -->

> 🔴 **`false` ≠「不用管」。這一格叫「資料一致性事故」，不叫「資料清理」。**
> 舊寫法「P3 資料清理／僅記錄」會讓人以為那是一堆可以批次刪掉的髒資料。**不是。** 一張逾期未銷的運單代表**一個真實存在於物流商系統、我方卻沒有結掉的識別**；在 (b) 場景 4 下它會變成**同一張 FO 的第二張有效面單**——**倉庫拿哪一張都看起來對**（完整論證見 (a0)）。**它不能被「清理」掉，只能被「結案」掉**，而結案要有人確認那張運單究竟出了什麼事。
> ⇒ **`false` 降的是急迫性（不燒錢、可以排隊處理），不是必要性。** (c) 的閉環等式對 `false` 的 pack **照樣要跑**，`Σ ABANDONED_UNRESOLVED == 0` **照樣是硬斷言**。

> 🟢 **順豐＝`false`（2026-08-12 第四輪，使用者裁定 A-2 逐字「不會計費」，SF-30／B-23）。**
> ⇒ 順豐逾期未銷 ＝ **P3 資料一致性事故**，**僅平台營運，不通知店主**。
> **告警等級一律引鍵不硬編**（鐵律 6）：`limits.carrier.packs.<code>.capability_declarations.shipment_void.unbilled_overdue_alert`，順豐現值 **`p3_data_consistency_platform_ops_only`**（第三輪值為 `p1_platform_ops_only`）。
> **不通知店主的理由沒變，而且從頭到尾與計費無關**：我方尚未提供線上銷號（K4 `supported: false`，見 (g)(h)），**店主收到也無從處置**，而**無法行動的告警只會訓練人忽略告警**。要通知店主，前提是先給他一個能按的按鈕。
>
> ⚠️ **這一格的成立條件仍是 (e) 的畫面真的有人在看。** P3 ＋ 沒有畫面 ＝ 把風險藏起來，比什麼都不記還糟——因為 (c) 的等式會一直「表面上是平的」。
> ⚠️ **V-42 三問只結了第一問。** `window_hours`（可銷號時間窗）與 `frees_number`（`mailno` 是否回收）**使用者未裁定、官方仍沉默** ⇒ 維持 `null`／`unknown`，**號碼一律不重用**（(f)）。使用者裁定的是**我方的成本**，不是**順豐系統的行為**——這條界線見 §0.3。

**(e) UI 必須有一個「待銷號」佇列**，位置在後台出貨相關頁面，顯示：運單號、取號時間、逾期時長、金額風險（若 pack 宣告了單張運單費率）、一鍵銷號／標記已人工處理。**沒有這個畫面，上面所有規則都不會被執行。**

> 🔴 **（第四輪）`billed_if_unused: false` 的 pack（順豐即是）：這個畫面照做，一格都不能省。**
> 唯一的差別是「金額風險」那一欄對順豐**顯示不適用**（不計費，SF-30），**其餘欄位與那顆「標記已人工處理」的按鈕全部保留**。
> **這個畫面在 `false` 的 pack 上不是成本管控工具，是資料一致性工具**——它是 (c) 閉環等式唯一的人工輸入口（(h) 規則 5），也是唯一能讓「同一張 FO 掛著兩個識別」被看見的地方。
> ⚠️ **把「金額風險」欄拿掉之後，不要順手把整個畫面降級成一張唯讀清單。** 沒有「標記已人工處理」，`VOID_MANUAL_REQUIRED` 就永遠出不去，(c) 的 `Σ ABANDONED_UNRESOLVED == 0` 會在寬限期後全數轉紅——那時候的告警是真的，只是沒人能處理。

**(f) 客戶側識別（`client_reference`）一律用後即棄——本輪新增，直接來自 SF-14**

順豐官方明載：**訂單取消之後，客戶訂單號不得重複使用。** 這條看似瑣碎，卻打穿了一個很自然的實作直覺：「這單失敗了，用同一個單號重試一次」。

| 規則 | 內容 |
|---|---|
| **識別絕不重用** | 送給物流商的客戶側識別（`client_reference`）**每次取號嘗試都必須是新的**，取 `shipment_intents.id`（§F.4 前提 1 已如此規定）。**同一個 intent 重試時沿用同一個識別；一旦該 intent 落到 `FAILED` 或該運單被 void，就必須開新 intent、換新識別。** 對應 `limits.carrier.shipment_intent.client_reference_reuse_forbidden: true` |
| **為什麼不能只靠冪等鍵** | 我方的 `idempotency_key` 擋的是「同一次請求被送兩遍」；這裡擋的是「**不同次**請求想借用同一個識別」。兩者是不同的東西，§E.2 的兩層模型必須各管各的 |
| **DB 兜底** | `waybills` / `shipment_intents` 對 `(shop_id, carrier_account_id, client_reference)` 建唯一索引。**重用即撞索引**，不是靠程式自律（11 §2「業務唯一性用唯一索引兜底」） |
| **對回查的影響** | 因為識別不重用，§F.4 的回查結果**沒有歧義**：查到就是這一次 intent 的結果，不可能撈到上一次的。**若識別可重用，整個 `UNKNOWN` 回查機制就是不可靠的**——這是 SF-14 意外替我方背書的一點 |

**(g) V-42 怎麼結案（它不會自己結）——🟢 2026-08-12 第四輪：已結案，走的是第二條路**

V-42 是本檔唯一一個**不可能由公開文檔結案**的 V 編號。它的兩條出口與實際走法：

| 出口 | 由誰 | 產出 | 本輪狀態 |
|---|---|---|---|
| ① 向順豐商務／月結窗口以**書面**確認三件事：❶未使用之運單號是否計費 ❷可銷號的時間窗 ❸銷號後 `mailno` 是否回收 | 商務 | 一封書面回覆，存檔並在 §附錄 B 補一列（來源＝合約／書面回覆，日期） | ⏳ **未走**（仍建議併行；它能一次答完三問，本輪的裁定只答了❶） |
| ② **明示接受人工銷號營運成本的裁定** | **使用者／營運**（工程不得自決） | 一句裁定 ＋ (e) 畫面與 (h) 人工登記流程到位的確認 | 🟢 **已走。2026-08-12 使用者裁定 A-2：「不會計費。」**（SF-30／B-23） |
| （不變）在銷號機制未經確認前的工程側過渡：`sf_express.shipment_void` 宣告 `supported: false` ＋ reason，逾期未交寄一律進 **`VOID_MANUAL_REQUIRED`** 人工佇列 | 實作 | pack 通過 §A.3 的 gate（因為**宣告完整**），但銷號走人工 | ✅ **維持**（❷❸ 仍未知，過渡不撤） |

> **上表第三列（工程側過渡）是本節唯一放寬的地方，且它並不違反 §A.3。** §A.3 要求的是「**宣告**完整」，不是「**支援**完整」——`supported: false` ＋ 非空 `reason` 是合法宣告。差別在於：`null`（沒人想過）⇒ 擋 pack；`false` ＋ reason（想過了，決定走人工）⇒ 放行，但必須有 (e) 的佇列接住。
> <!-- 依 2026-08-12 第三輪更新。原文末句：「⚠️ 但這條過渡只解 V-42。sf_express 仍被 V-39／V-40／V-41／V-43／V-44／V-47／V-48／V-51 擋著，本輪依舊不可 enable。」 -->
> **（第三輪）該過渡已經是 `sf_express` pack 的現行宣告**，不再只是「建議的過渡」——見 §B.1 的 K4 格與 `limits.carrier.packs.sf_express`。

<!-- 依 2026-08-12 第四輪使用者裁定 A-2（SF-30／B-23）改寫 (g)。原文為「V-42 怎麼結案（它不會自己結）」＋兩列表格，
     且末段為：「⚠️ **但這條過渡只解 §H.4 的條件 ①②（宣告完整），不解條件 ③（`enable_gate` 為空）。**
                `sf_express` 仍被 **V-39／V-41／V-42／V-51** 擋著，**依舊不可 enable**。V-42 要從 gate 移出，
                需要的是書面合約回覆（上表第一列），或**一個明示接受人工銷號營運成本的裁定**——後者是營運決定，工程不得自決。」
     🔴 **上一輪把出口寫清楚是對的，本輪就是照那兩條出口的第 ② 條走完的**——這正是「明文寫下出口」的價值：
        裁定一到，不需要重新論證，只要把它接上去。
     🔴 **防回退**：不得把 V-42 加回 `enable_gate`。它的結案依據是使用者裁定（B-23），不是我方推論，
        也不是「查不到就當沒有」。若日後書面回覆推翻本裁定，正確做法是**新登記一個 V 編號**並改 (d) 的等級，
        **不是**把 V-42 復活——V 編號一旦以明示裁定結案就不再重開，否則 gate 會變成一本永遠翻不完的舊帳。 -->

> 🟢 **結果：V-42 已從 `enable_gate` 移出，`sf_express` 的 gate 由 4 項降為 3 項 `[V-39, V-41, V-51]`**（§H.4、附錄 A）。
> ⚠️ **但 pack 依然不可 enable**——條件 ③ 仍未通過，剩下的三項全是技術缺口，其中 **V-51（`msgDigest` 簽章演算法）仍是第一號阻塞項：算不出簽章，一個請求都送不出去。**
> ⚠️ **V-42 移出 gate 不等於三問都有答案。** ❶已答（不計費）；**❷可銷號時間窗、❸`mailno` 是否回收，兩問仍無來源**，處置不變：`window_hours: null`、`frees_number: unknown` ⇒ **號碼一律不重用**、順豐運單**永遠不自動進 `VOIDED`**（(h) 規則 1）。
> 🔴 **這條裁定換來的是一個人力承諾，不是一個技術結論**：接受「順豐運單一律人工銷號」意味著**每天要有人去看 (e) 那張佇列**。V-42 之所以結得掉，靠的就是這個承諾——**承諾沒有兌現（畫面沒做／沒人看）的話，結案是假的**，而 (c) 的等式會替它掩護，因為它會一直是平的。

**(h) `EXP_RECE_UPDATE_ORDER`（取消）與「銷號」的關係——第三輪新增，這是最容易被合併成一件事的兩件事**

使用者選定的 6 支裡有 `EXP_RECE_UPDATE_ORDER`（**訂單取消接口**，SF-26／SF-29）。**有了取消介面，不等於有了銷號能力。** 三個概念必須分開：

| 概念 | 是什麼 | 順豐側 | 我方能力鍵 | 我方宣告 |
|---|---|---|---|---|
| **取消訂單** | 告訴順豐「這一單不要來收、不要繼續運」 | `EXP_RECE_UPDATE_ORDER` 的**取消**用途（舊世代＝`OrderConfirmService` `dealtype=2`，SF-14） | **K5** `shipment_cancel` | ✅ `supported: true` |
| **確認訂單** | 順豐的訂單確認流程（`dealtype=1`） | 同一支介面的另一個用途 | — | **我方不使用**（SF-29） |
| **銷號** | 把**運單號**（`mailno`）還回去，使它不再計費／可被回收 | **官方通篇沉默**（SF-15）——取消訂單對 `mailno` 的效果未載明 | **K4** `shipment_void` | ⛔ `supported: false` ＋ reason（(g) 過渡） |

**由此推出的五條實作規則**

1. **§D.5(b) 的五個場景，順豐一律走「先 K5、後人工」**：呼叫 `EXP_RECE_UPDATE_ORDER` 取消（讓順豐不要來收件），**呼叫成功後運單進 `VOID_MANUAL_REQUIRED`，不是 `VOIDED`**。
   > **為什麼不能進 `VOIDED`**：`VOIDED` 在 (a) 的狀態表上明載「**否**（正常結果）」——它是一個**斷言「這張運單不會被計費」**的狀態。我方沒有任何官方依據可以做這個斷言（SF-15）。**把取消成功寫成 `VOIDED`，等於用一個技術事實（訂單取消了）冒充一個財務事實（不會被收錢）**，而 §D.5(c) 的閉環等式正是靠這個狀態在對帳——寫錯它，對帳表面上永遠是平的。
   >
   > 🔴 **（2026-08-12 第四輪）本規則不變，但支撐它的理由換了一半，請讀完再判斷能不能放寬。**
   > 使用者裁定 A-2「不會計費」（SF-30）之後，上一段那個**財務**理由確實鬆了——`VOIDED` 所斷言的「不會被計費」現在有依據了。**但規則照舊，因為它還有另一半理由，而且那一半一點都沒鬆**：
   > `VOIDED` 同時也是一個**「這個識別已經確定結掉了」**的斷言，而 **`mailno` 取消後究竟怎麼樣，官方仍然通篇沉默**（SF-15 的❸，使用者未裁定）⇒ `frees_number: unknown`。我方**能**確定的只有「順豐不會來收件」，**不能**確定「這個號已經死透」。
   > **兩者的差別會在 (b) 場景 4 上炸開**：換箱重取號時，若舊運單已被寫成 `VOIDED`，(c) 的等式就認為它結清了，於是**同一張 FO 掛著的第二個識別再也不會出現在 (e) 的佇列裡**——倉庫那兩張都印得出來的面單，就此從系統視野中消失一張。**這是資料正確性事故，不是成本事故，所以「不計費」救不了它。**
   > ⇒ **判準**：`VOIDED` 需要**兩個**斷言同時成立（不計費 ✅ 已由裁定取得、識別已結 ❌ 仍未知）。缺一個就只能停在 `VOID_MANUAL_REQUIRED`，由 (e) 的人工登記把第二個斷言補上（(h) 規則 5）。
   > <!-- 依 2026-08-12 第四輪使用者裁定 A-2 補寫。原文只有上一段（財務事實那一段），一字未刪。
   >      🔴 **防回退**：不得因為「已裁定不計費」就讓 K5 取消成功直接寫 `VOIDED`。
   >      那正是本註記要擋的那一步——它看起來像是裁定的自然結果，實際上跳過了另一個仍然未知的斷言。 -->
2. **`8019`（訂單已確認或已取消）不是失敗**：映射到 `too_late`（§E.2 既有規則）。對 K5 而言它代表「順豐側已是終態」，我方運單**同樣進 `VOID_MANUAL_REQUIRED`**（若尚未交寄）。**不得**因為回了錯誤碼就把運單留在 `ALLOCATED` 不管。
3. **取消之後絕不重用識別**：`orderid` 取消後不得重複使用（SF-14）⇒ 換箱／改派要重新取號時，**必須開新 intent、換新 `client_reference`**（(f) 已規定，`limits.carrier.shipment_intent.client_reference_reuse_forbidden`）。這一條與本節的關係是：**取消動作本身就是「這個識別燒掉了」的那一刻。**
4. **冪等**：`shipmentCancel` 帶 `idempotencyKey`（§E.1），業務唯一鍵為 `waybill_id`。兩個 staff 同時按取消 ⇒ 外部只呼叫一次（§K 14）。
5. **對帳的直接後果**：因為順豐運單永遠不會自動進 `VOIDED`，(c) 的閉環等式在順豐上**依賴人工登記**（`shipmentVoidMarkManual`：`VOID_MANUAL_REQUIRED → VOIDED` 需二次確認，§I）。**這是 K13 `billing_reconciliation` 宣告 false 的直接代價**，必須寫在 (e) 的畫面說明裡，讓營運知道這個人工步驟不是可選的。

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
| `shipmentLabelRender` | 產檔可重做、通常無成本。**但若某 pack 宣告 `label_render.billable_per_render: true`，該 pack 的渲染路徑必須改走帶 key 的批次作業** —— 這是 pack 級的加嚴，不是全域規則。<br>**（三輪補一條）`billable_per_render` 為 `null`（未知）時一律「比照 `true` 處置」**——順豐正是這一格（V-39 未結案）。**沉默不是否認**：若順豐對每次雲打印計費而我方當它免費，成本會以「後台每按一次預覽就一筆」的形態出現，且**帳單來之前完全看不見** |
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
   > **順豐宣告 `lookup_by_client_reference: true`（三輪）**，依據有三：①回查介面 `EXP_RECE_SEARCH_ORDER_RESP` 就在使用者選定的 6 支內（SF-26）；②順豐的去重鍵就是 `orderid`（V-49 已結案），而 `orderid` ＝ 我方 `client_reference` ＝ `shipment_intents.id`；③`orderid` 取消後不可重用（SF-14）⇒ 回查結果**沒有歧義**（§D.5(f) 末列）。
   > ⚠️ **但這條宣告的欄位表仍未取得（V-41）**：知道「可以用什麼回查」不等於知道「回查請求怎麼組」。這也是 V-41 仍在 gate 的原因之一。

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

<!-- 依 2026-08-12 第三輪使用者裁定一整框改寫。第二輪原文的結論為：
     「⇒ sf_express.serviceable_lanes 維持空陣列，理由不是『不知道代碼』，而是更根本的一條：
       連『香港商戶能不能用丰橋』都還沒確認。⇒ 順豐本輪不能作為香港首發物流商。」
     🔴 該結論已作廢：使用者已實際以香港為發貨地開發過（SF-25）。 -->

> 🟢 **V-43 已由使用者裁定結案：香港可以作為寄件地（origin）。**
>
> 使用者裁定逐字：「順豐你理解錯了。**香港地區可以作為發貨地。已經成功開發過。**你文檔、工程可以解決。」
> **我方前兩輪的否定結論是怎麼來的**：丰橋公開文檔全篇以中國內地為寄件地、香港站無開發文檔 ⇒ 我方**從「文檔沒寫」推出「做不到」**。
> **為什麼要推翻**：使用者是**已經做過**的一手事實，屬「實測」級（§0.3 `user-ruling`）；我方那條是**從缺席推得的否定推論**，等級最低。**文檔取樣的缺口不等於產品的缺口。**
>
> | 問題 | 第二輪 | **第三輪（現行）** | 出處 |
> |---|---|---|---|
> | 香港作為**目的地** | ✅ 同一套 API（`d_deliverycode=852`、支援 `HKD`） | ✅ 不變 | SF-19 |
> | 香港作為**寄件地** | ❌ 仍未確認 ⇒ 順豐不能當 HK 首發 | 🟢 **可以。已成功開發過。** | **SF-25**（`user-ruling`）|
> | 香港端的服務**名稱** | ✅ 標準快遞／國際特惠（40＋ 目的地含澳門、台灣） | ✅ 不變 | B-19 |
> | 服務名稱對應的 `express_type` **數值** | ❌ 未取得 ⇒ 阻塞 | ⚠️ **仍未取得，但降級為實作期確認項**（V-44 移出 gate） | V-44 |
>
> 🔴 **這裡有一條界線必須守住：可行性被推翻了，參數值沒有。**
> 我方**仍未親眼見到**香港 origin 的服務代碼值。因此：
> - `sf_express.serviceable_lanes` **不再是空陣列**——HK 作為 origin 的 lane 要寫進去（值見 `limits.carrier.packs.sf_express.serviceable_lanes`）；
> - 但每條 lane 的 **`service_code` 一律 `null`**，**不得憑空編一個數值**（憑空編的代價：下單被拒是好的情況，**下成別的產品類別、按別的費率計費才是壞的情況，而且看起來一切正常**）；
> - **新增一條硬規則**：`limits.carrier.packs.<code>.lane_requires_service_code: true` ⇒ **`service_code` 為 `null` 的 lane 不得對外可選**（結帳頁不出現、後台下拉不出現），觸及時回 `CARRIER_LANE_NOT_SERVICEABLE`。
>
> **這條規則就是「可行性已確認、參數未確認」的正確表達方式**：事實照寫（HK 可作 origin），但**閘門開在最小的範圍**（單一 lane），而不是把整個 pack 鎖死。對照第二輪——當時是用「整個 pack 不可 enable」去表達「一個參數不知道」，鎖得太大，也把一個**錯的事實**（HK 不能當 origin）藏在一個**對的動作**（保守不上線）後面。
>
> **HK → 海外 lane 另外還有兩道獨立的閘門**（缺一即不可服務，且與 `service_code` 無關）：
> 1. **報關能力**：§H.2 關卡 1 要求跨境 lane 的 pack 宣告 `customs_doc.supported: true`，而順豐本輪宣告 **false**（6 支不含報關介面）⇒ 跨境 lane 判不可服務；
> 2. **目的地未逐一登錄**：B-19 稱 40＋ 目的地，但我方未取得完整清單 ⇒ lane 的 `destination_country` 為 `null`，而 **`null` 不是萬用字元、不命中任何目的地**（正確的失效方向）。
>
> ⇒ **順豐首發能點亮的是 `HK → HK` 本地這一條**（且仍待 `service_code` 與 §H.4 的 gate）。**HK → 海外要等報關與目的地清單**，見 §H.5。

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
| `sf_express` | **`[V-39, V-41, V-51]`**（第三輪 8→4；**第四輪 4→3**，移出 V-42） | ❌ |
| `dhl_express` | `[V-45]` | ❌ |
| `ups` / `fedex` | `[V-45]` | ❌ |

<!-- 依 2026-08-12 第三輪使用者裁定更新 sf_express 的 gate。第二輪值：[V-39, V-41, V-42, V-43, V-44, V-47, V-48, V-51]
     移出 V-43／V-44（裁定一：香港可作發貨地 ⇒ 降為實作期確認項，改由 lane 級的 service_code=null 閘門處理）；
     移出 V-47／V-48（裁定二：6 支不含推送與 COD ⇒ K7／K9 宣告 supported:false ＋ reason，屬合法宣告）。 -->
<!-- 依 2026-08-12 **第四輪**使用者裁定 A-2 更新。第三輪值：[V-39, V-41, V-42, V-51]（4 項）。
     移出 V-42 —— 使用者裁定「取號未使用不會被計費」（SF-30／B-23），走的是下方原表所列兩條出口的**第 ② 條**
     （明示的營運裁定），而不是第 ① 條（書面合約回覆）。
     🔴 **防回退**：不得把 V-42 加回 gate。它是以**明示裁定**結案的，不是以推論結案的；
        若日後書面回覆與裁定不符，正確做法是新登記 V 編號並改 §D.5(d) 的告警等級，**不是**復活 V-42。 -->

**三項留下來的，逐項寫明「它到底擋住什麼」**（gate 的內容必須通得過這個問法，通不過的就該移出）

| V | 缺什麼 | 擋住的是什麼 | 缺口性質 | 誰能結案 |
|---|---|---|---|---|
| **V-51** | `msgDigest` **簽章演算法**（串接順序／雜湊／編碼）。官方 SDK 只暴露方法簽名 `getMsgDigest(msgData, timeStamp, checkWord)`，兩份 PDF 均未載明演算法本身（SF-11） | 🔴 **一個請求都送不出去。** 不是某個能力不能用，是**整個 pack 連不上線**——K2／K3／K5／K6 一起卡死 | 文檔／SDK 二進位 | 丰橋開發者入口的簽章說明；或直接讀官方 SDK jar；或申請帳號後由平台提供 |
| **V-41** | **逐介面欄位表**（目錄層已於第三輪取得，SF-28） | 組不出任何一個請求的 `msgData`。**知道有哪些介面 ≠ 知道怎麼呼叫** | 文檔（**明細頁需逐頁渲染，部分疑須登入**） | 同上 |
| **V-39** | 雲打印兩支的**欄位表、模板代碼、尺寸值域**（格式已於第三輪定案為 `[pdf, html]`） | K3 面單：印不出來，或印出尺寸不對被物流商拒收（§D.2 規則 2） | 文檔 | 同上 |
| ~~**V-42**~~<br>🟢 **已結案（第四輪，移出 gate）** | ~~未使用之運單號**是否計費**~~ **已答（不計費，SF-30／B-23）**；**銷號時間窗**、`mailno` **是否回收** 仍缺 | ~~不擋技術，擋財務閉環~~ ⇒ **現在什麼都不擋**：告警等級已定（P3 資料一致性），(c) 的閉環改由 (e) 的人工登記閉合 | **合約**——不寫在任何 API 文檔裡（SF-15）；已由**合約當事人本人**裁定 | 已結案。剩餘兩問改列**商務確認項**（附錄 A 保留完整脈絡） |

> 🟢 **V-42 已於第四輪結案，走的是下面原本就寫明的第 2 條路。**
> 🔴 **這一段保留原文，因為方法論比結論值得留下**：V-42 是唯一一個「不會自己結」的，**因此它需要一個明文的出口，否則 pack 永遠卡在 gate 上**。§D.5(g) 提供了工程側的過渡（`shipment_void` 宣告 `supported: false` ＋ reason ＋ 人工佇列），`sf_express` 第三輪已照此宣告 ⇒ gate 條件 ①② 過了，卡住的只剩條件 ③。
> **當時寫明的兩條出口**：
> 1. **拿到書面回覆**（商務向順豐月結窗口確認三件事）⇒ 正常結案，附錄 B 補一列來源；
> 2. **一個明示的營運裁定**：接受「順豐運單一律人工銷號」的營運成本，並確認 §D.5(e) 的待銷號畫面與 (h) 的人工登記流程已到位。
> ⚠️ **第 2 條是營運決定，工程不得自決**——因為它換來的不是技術風險，是**每天要有人去看那張佇列**的人力承諾。
> 🟢 **2026-08-12 第四輪：使用者裁定 A-2「不會計費」，第 2 條成立**（SF-30／B-23）。**教訓**：上一輪沒有硬結、而是把出口寫清楚，所以這一輪裁定一到就直接接上，不必重新論證——**「誠實地卡著」與「寫明怎麼解卡」要一起做，只做前者會讓 pack 永遠卡住。**
> ⚠️ **仍未兌現的那一半**：第 2 條的前提是 (e) 的畫面與 (h) 的人工登記流程**到位**。**兩者目前都還是規格，不是程式。** 裁定換來的人力承諾在畫面做出來之前是空的——這一點列入回報 ④。
> ⚠️ **書面回覆（第 1 條）仍建議併行取得**：它能一次答完三問，而本輪的裁定只答了「是否計費」一問。

> **第三輪 gate 變動的方法論教訓**（比 gate 本身更值得留下）：
> - **移出 V-43／V-44（可行性已確認、參數未確認）**：正確處置是**把閘門下移到 lane 級**（`service_code: null` ⇒ 該 lane 不可選），不是留在 pack 級。**用最小的鎖，鎖最小的範圍**——鎖太大會讓「一個參數不知道」看起來像「整家物流商不能用」，而後者是**錯的事實**。
> - **移出 V-47／V-48（範圍決策）**：V 編號是用來擋「**不知道**會做錯事」的，不是用來擋「**我們決定不做**這件事」。決定不做 ⇒ 宣告 `supported: false` ＋ reason，§A.3 明文放行。
>   ⚠️ **但移出時必須檢查問題有沒有換一個入口回來**：V-47 的「事件碼值域」就是——不接推送，K6 輪詢照樣要映射事件碼。處置見 §C.4 的 `unknown_event_code_action` fail-safe。**這一步是本輪最容易漏掉的一步。**
> - **留下 V-51（第二輪才補進來的那項）**：它到今天仍是第一號阻塞項。第二輪的教訓（**gate 要定期對照「實作者第一天會卡在哪」重新檢查，不能只累加**）在本輪反過來又驗證了一次：**gate 從 8 項減到 4 項，第一號阻塞項一動也沒動。** 長度不代表嚴謹度。

### H.5 順豐作為香港首發物流商（鐵律 11 的直接結論）

<!-- 依 2026-08-12 第三輪使用者裁定一整節重寫。第二輪原文的結論為「不能」，三條建議中的第 3 條為
     「不要為了『有一個真的 carrier』而先接內地丰橋。內地丰橋能做的是內地寄出，與我方香港首發需要的
       origin 相反。接了也點不亮任何一條首發需要的 lane。」
     🔴 該結論與該建議的前提（香港不能作 origin）已被 SF-25 推翻，整節作廢重寫。 -->

**結論（第三輪改判）：可以，而且應該是首發目標。** 擋住它的不再是「香港能不能寄」這個**方向性**問題，而是四個**填值性**缺口（§H.4 的 gate）。**這是性質完全不同的兩種阻塞：前者要換路，後者只要把值拿到。**

| 首發需要什麼 | 第二輪 | **第三輪（現行）** | 缺口性質 |
|---|---|---|---|
| **香港可作 origin** | ❌ 未確認 ⇒ 整條路走不通 | 🟢 **可以（已成功開發過，SF-25）** | — |
| HK → HK 本地 lane | ❌ | ⚠️ lane 已宣告，**待 `service_code` 數值** | 實作期（V-44）：拿到帳號即可實測 |
| HK → 海外 lane | ❌ | ⛔ **本輪不點亮**：報關能力宣告 false ＋ 目的地未逐一登錄（§H.2） | 範圍決策 ＋ 文檔（V-53） |
| 能送出第一個請求 | ❌ | ❌ **`msgDigest` 演算法仍未取得** | 🔴 **文檔（V-51）——第一號阻塞項，本輪一動也沒動** |
| 下單／取消／查路由可用 | — | ⚠️ 介面已定（3 支），**欄位表仍缺** | 文檔（V-41） |
| 面單可印 | ❌ 格式未知 | ⚠️ **格式已定 `[pdf, html]`**，模板與尺寸仍缺 | 文檔（V-39） |
| 銷號帳可閉環 | ❌ | 🟢 **（第四輪）已可閉環——但靠人工**：計費一問已由使用者裁定結案（不計費，SF-30／B-23）⇒ **V-42 移出 gate**；(c) 的等式由 §D.5(e) 的**人工登記**閉合，不是由 K13 對帳檔閉合 | ✅ **不再擋 gate**。⚠️ 代價是**每天要有人看待銷號佇列**（人力承諾，非技術結論） |
| COD（香港常見） | ❌ 未知 | ⛔ **本輪不接**（範圍決策；香港可用性仍屬合約，V-48） | 範圍決策 |

**四條可執行的路，按建議順序：**

1. **把「拿到丰橋帳號」當成第一優先的非工程動作。** 🟢 **第四輪之後這一步的投報率更高了**：gate 只剩 **三項（V-39／V-41／V-51）**，而**三項全部**都是「文檔在牆後面」而不是「答案不存在」⇒ **拿到帳號與文檔中心存取權的第一天，gate 可以直接歸零。** 這是目前投資報酬率最高的一步（對應 `docs/handoff/2026-08-12-open-decisions.md` 的 A-4）。
2. **工程側先做能做的**：adapter 骨架、§F 的三段式編排、`shipment_intents` 狀態機、待銷號佇列（§D.5(e)）、`manual` pack 全綠。這些**不依賴任何順豐填值**——這正是把它抽成 pack 的價值（§0.3 末段）。
   🔴 **（第四輪升級）§D.5(e) 的待銷號佇列從「先做能做的」變成「必須先做的」**：V-42 的結案依據是「接受人工銷號的營運成本」（使用者裁定 A-2），而**人工銷號沒有畫面就不存在**。⇒ **這個畫面現在是 V-42 結案的兌現條件，不再只是一個工程項目。**
3. **同時啟動一條非工程的問詢**（前置期最長，工程再努力也無法自解）：**順豐月結合約／商務窗口 → ~~V-42~~ V-42 的剩餘兩問**（❷銷號時間窗、❸`mailno` 是否回收；❶是否計費**已由使用者裁定結案**）。順帶可問 V-48（香港 COD）與 V-44（`express_type` 數值）。**這四項現在都不擋 gate**——問它們是為了把 `window_hours`／`frees_number` 從 `null` 變成值，好讓順豐運單有機會自動進 `VOIDED`（目前一律人工，§D.5(h) 規則 1）。
4. **首發期間 `manual` pack 照樣要在。** 它不再是「唯一的首發路徑」，但仍是：①順豐 gate 未清完之前的正式營運路徑；②任何 carrier 故障時的降級目的地（§F.5）；③非順豐航線（例如 HK → 海外）的唯一出口。**不得因為順豐可行就砍掉 `manual`。**

> 🔴 **第二輪那條「不要為了有一個真的 carrier 先接內地丰橋」的建議，前提已經不成立，整條作廢。**
> 它的推理是：「內地丰橋只能內地寄出 ⇒ 與香港首發需要的 origin 相反 ⇒ 接了點不亮任何 lane」。
> **第一個前提就是錯的**——丰橋**可以**以香港為發貨地（SF-25）。所以不存在「內地丰橋 vs 香港順豐」這個選擇題，**它們是同一套平台**；要接的就是它，不是別的東西。
> **這條錯誤建議的成本值得記下來**：它不只給了錯的結論，還**給了一個聽起來很有道理的理由**（「不要為了有一個真 carrier 而做無用功」）。**一個有說服力的理由架在一個錯誤的事實上，比單純寫錯結論更難被發現**——因為讀的人會被理由說服，不會回頭去查前提。
>
> **這一節同時是對 §0.2 原則 5 的再驗證，只是驗證的方向反過來了**：carrier 的**可用性**是法域的函數——但「可用性」必須以**事實**判定，不能以**文檔取樣的完整度**判定。第二輪把「丰橋文檔沒寫香港寄件」當成「香港不能寄」，等於用我方的查證邊界去定義物流商的產品邊界。**抽象層沒有錯（`serviceable_lanes` 這個表達方式是對的），錯的是填進去的值。**

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
| 帳號 | `carrierAccountTest` | `carrierAccountId` | `ok, checkedCapabilities[], userErrors`（唯讀，不需 idempotencyKey）。**`checkedCapabilities` 對 `label_render` 必須逐 `format` 各回一列**——順豐的 PDF 與 HTML 是**兩支不同的服務代碼**，且 HTML 那支關聯日期為 2026（新介面），**測了 PDF 不代表 HTML 也通**（§D.2） |
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
| **（三輪改）** `carrier.label.formats_allowed`：新增 **`html`**（值域由 `[pdf, zpl, png]` → `[pdf, html, zpl, png]`） | §D.2 |
| **（三輪新增）** `carrier.label.html_dom_rewrite_forbidden` / `html_render_sandboxed` / `html_batch_merge_forbidden` | §D.2 `html` 四條專屬規則、§D.3 |
| **（三輪新增）** `carrier.tracking.unknown_event_code_action` | §C.4（V-47 移出 gate 後的 fail-safe） |
| **（三輪新增）** `carrier.packs.sf_express.api_scope`（使用者裁定的 6 支服務代碼 ＋ 名稱 ＋ 分類 ＋ 對應能力鍵） | §0.4(e)、§B.1 |
| **（三輪新增）** `carrier.packs.sf_express.serviceable_lanes`（HK origin 兩條，`service_code` 皆為 `null`）／`lane_requires_service_code` | §H.2、§H.5 |
| **（三輪新增）** `carrier.packs.sf_express.capability_declarations`（十三項的 `supported` ＋ reason 摘要，供 CI-1／CI-8 對照） | §B.1 |
| **（四輪改）** `carrier.packs.sf_express.enable_gate`：**4 項 → 3 項** `[V-39, V-41, V-51]`（移出 V-42） | §H.4、§D.5(g) |
| **（四輪改）** `carrier.packs.sf_express.capability_declarations.shipment_void.billed_if_unused`：`null` → **`false`**（使用者裁定 A-2，SF-30／B-23）。**`window_hours` 與 `frees_number` 維持 `null`** | §D.5(a0)(d)(g) |
| **（四輪改）** `carrier.packs.sf_express.capability_declarations.shipment_void.unbilled_overdue_alert`：`p1_platform_ops_only` → **`p3_data_consistency_platform_ops_only`**（成本告警 → 資料一致性告警；等級 P1 → P3，通知對象不變） | §D.5(d) |
| **（四輪不變，明文登記）** `carrier.waybill.number_is_billable_resource` **維持 `policy_default`** ——順豐的裁定是**單一 pack 的合約事實**，不是跨物流商斷言；**不得**因此把全域改成 `false` | §D.5(a0) |
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
10c. **（二輪新增；🔴 四輪起不再是假設情境）銷號帳的立論已與計費脫鉤**（§D.5(a0)）：把 pack 的 `billed_if_unused` 設為 `false`，斷言 §D.5(b) 五個場景的程式路徑**全部照常執行**、待銷號佇列照常進列——**只有 (d) 的告警等級從 P1 降為 P3**。**若把 `billed_if_unused: false` 做成「跳過整套銷號帳」，此測試必須失敗。**
   🟢 **（四輪）`sf_express` 現在就是 `billed_if_unused: false`**（使用者裁定 A-2，SF-30／B-23）⇒ **本條從「假設一個 false 的 pack」變成「用真實的 sf_express fixture 跑」**，且必須加一條斷言：**場景 4（換物流商／換箱重取號）在 `false` 下仍然 reject 新的取號請求**（舊號未 void ⇒ `WAYBILL_ALREADY_ACTIVE`，同第 6 條）。
   🔴 **這一條是本節防回退的主力**：二輪寫下它的時候還沒有任何 `false` 的 pack，它擋的正是「日後有人拿到『不計費』的答案就去拆銷號帳」——四輪那一天到了，而測試在。**任何人不得因為順豐不計費而放寬或刪除本條。**
10d. **（三輪新增）取消 ≠ 銷號**（§D.5(h)）：pack 宣告 `shipment_cancel.supported: true` ＋ `shipment_void.supported: false` 時，對一張 `ALLOCATED` 運單走取消流程 ⇒ 斷言 ①外部確實呼叫了取消介面；②運單狀態為 **`VOID_MANUAL_REQUIRED`**（**不是 `VOIDED`**）；③待銷號佇列 ＋1；④物流商回 `8019` 時結果**相同**（`too_late` 不得讓運單留在 `ALLOCATED`）。
   🔴 **把取消成功寫成 `VOIDED` 是本節最容易犯的錯**：那是用一個技術事實（訂單取消了）冒充一個財務事實（不會被計費），而 §D.5(c) 的閉環等式正是靠這個狀態在對帳——寫錯它，**對帳表面上永遠是平的**。
   🔴 **（四輪）順豐已裁定不計費，本條測試照跑，一個斷言都不能拿掉。** `VOIDED` 需要**兩個**斷言同時成立：「不會被計費」（✅ 已由裁定取得）與「**這個識別已經確定結掉**」（❌ `frees_number` 仍 `unknown`，使用者未裁定）。缺一個就只能停在 `VOID_MANUAL_REQUIRED`。完整論證見 §D.5(h) 規則 1 的第四輪補註。

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
20b. **（四輪新增）`billed_if_unused: false` 的 pack（順豐）**：逾期未銷 ⇒ **P3「資料一致性」告警**，`unbilled_overdue_alert` 讀到的值必須是 `p3_data_consistency_platform_ops_only`，且**通知對象不含店主**。
   🔴 **同時斷言 `ABANDONED_UNRESOLVED > 0` 仍然告警**——它與 `billed_if_unused` **無關**（第 8 條的閉環等式對所有 pack 一視同仁）。**若有人把 `false` 實作成「不告警」，第 8 條與本條必須紅。**

### 6 測試

21. **合約測試（contract test）套件對每個 pack 跑同一份測試**——這是可插拔架構唯一的驗證方式。至少涵蓋：十三項能力的 supported/unsupported 兩條路徑、四個 `outcome`、金額必為 Integer。
22. `manual` pack **必須全綠**（本輪唯一可 enable 的 pack）。
23. 金額路徑 100% 覆蓋（11 §0 維度 6）：`to_cents` 對 `"12.50"` / `"12.5"` / `12.5`(number) / `"12.505"`(應 raise) / `"0"` / 負值 各一條斷言。
24. **`Float` 掃描**：adapter 回傳的所有金額欄位 `assert_kind_of Integer`；`app/services/carrier/` 下 grep `to_f` 命中數為 0。
25. 快樂路徑 system test：建立出貨 → 取號 → 印面單 → 收到追蹤推送 → FO 轉 `CLOSED`。
25b. **（二輪新增）原始錯誤碼映射表逐列測試**（§E.2、`limits.carrier.packs.sf_express.error_code_outcome_map`）：八個碼各一條 case。
   🔴 **其中 `8016 → unknown` 那一列必須另加一條端到端斷言**：mock 順豐回 `8016` ⇒ intent 進 `UNKNOWN`（**不是 `FAILED`**）⇒ 觸發 §F.4 回查 ⇒ 回查取回 `mailno` ⇒ intent 轉 `SUCCEEDED` 且**運單數為 1**。
   **把 `8016` 當 `business_rejected` 是本檔第二容易犯的錯**（第一是把 `unknown` 併進 `transient_error`），後果是順豐側已有一張運單卻永遠接不回任何 intent，直接變成 `ABANDONED_UNRESOLVED`。
25c. **（三輪新增）能力宣告不得超出 `api_scope`**（CI-8 的執行期對應）：以 mock 攔截所有外部呼叫，跑完整條快樂路徑 ＋ 十三項能力的 supported/unsupported 兩條路徑，斷言**被呼叫過的服務代碼集合 ⊆ `limits.carrier.packs.sf_express.api_scope`**。多打一支就 fail。
25d. **（三輪新增）面單雙格式**：①`format: pdf` 與 `format: html` 各能取得檔案，且**呼叫的是兩支不同的服務代碼**；②`format: zpl` ⇒ `LABEL_FORMAT_UNSUPPORTED`（順豐 pack 未宣告，且是**設定期就擋**，不是列印時才失敗）；③HTML 批次 ⇒ 逐張輸出，**不得**產生合併檔；④HTML 內容原樣保存（存進去與取出來的位元組相同，**不得**有 DOM 正規化）。

### 7 合規／隱私

26. 面單檔案（含 PII）：私有儲存、簽名連結有 TTL、逾 `retention_days` 由 purge 任務刪除，且**刪除有紀錄**。**`html` 與 `pdf` 適用完全相同的規則**（三輪新增）——測試必須**逐格式各跑一次**，不得只測 PDF。**不得**因為「HTML 只是預覽」就放寬：它是可正式列印的面單，不是 `png` 那種預覽件。
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
- **CI-8（三輪新增）——能力宣告不得超出對接範圍**：對每個宣告了 `api_scope` 的 pack，①能力宣告為 `supported: true` 的每一項，其實作**只能**呼叫 `api_scope` 內的服務代碼；②`api_scope` 內的每一支都必須被至少一項能力（或 §F.4 的回查流程）引用——**宣告了一個我方根本沒接的能力，與接了一支沒人用的介面，兩者都是 build fail**。
  > **這條 CI 就是使用者裁定二的機械化**：SF pack 的能力只能由那 6 支撐起來。沒有它，下一個人很容易「順手」多接一支，於是規格與實作再度分家。
- **CI-9（三輪新增）——lane 的 `service_code` 為 `null` ⇒ 該 lane 不得對外可選**：`lane_requires_service_code: true` 的 pack，任何 `service_code` 為 `null` 的 lane **不得**進入結帳頁的運費選項或後台的服務下拉；違反即 fail（§H.2）。
  > **這條擋的是「可行性已確認、參數未確認」被誤讀成「可以上了」**——香港 origin 可行是事實，但沒有服務代碼就送不出正確的下單請求，而**下錯產品類別會按別的費率計費，且看起來一切正常**。
- **CI-10（三輪新增）——`html` 面單的兩條**：①`html` 格式的 label 在批次作業中**不得**被合併成單一檔案（`html_batch_merge_forbidden`）；②admin 內嵌 HTML 面單的元件必須是 sandbox iframe（`html_render_sandboxed`）。前者防竄改面單、後者防第三方 HTML 在 admin 的 session 下執行。

---

## 附錄 A：待查證登記（V-37 起）

> 規則沿用 52 §附錄 A：**無明確出處一律不自補規則**。每一項寫「要查什麼」「去哪查」「沒查到的當前處置」。
> **當前處置一律是「保守失效」**——不是猜一個值上線。

**2026-08-12 第三輪後的狀態總表**（起因：使用者提供兩項決定性資訊——①香港可作發貨地、已成功開發過；②實際對接範圍就 6 支 API）

> **讀法**：`gate` 欄是**唯一**決定 pack 能不能 enable 的欄。**「仍開」不等於「擋著」**——一個問題可以是開著的、被登記的、而且不影響任何決策（例如 V-48：我們決定不接 COD，那 COD 上限是多少就不再擋任何事）。**把兩者混為一談，正是第二輪 gate 湊到 8 項的原因。**

| V | 狀態 | 在 `sf_express` 的 gate 裡？ | 一句話 |
|---|---|---|---|
| V-37 | 🟡 **三輪縮小** | ❌ | 目錄層已取得（SF-28）：**`EXP_RECE_QUERY_SFWAYBILL` 的官方名稱是「清單運費查詢」**、`EXP_RECE_WANTED_INTERCEPT`／`EXP_RECE_GET_SUB_MAILNO` 確認存在；SF-9 其餘代碼的官方佐證仍為零 |
| V-38 | ✅ 二輪結案 | ❌ | DNS 判定：`sf-express.com`（有連字號）才對，官方 SDK PDF 印錯了 |
| V-39 | 🟡 **三輪再縮小** | ✅ **在** | **格式已定案 `[pdf, html]`**（SF-26）；**欄位表／模板代碼／尺寸值域仍缺** |
| V-40 | ✅ **結案（架構決策）＋ 三輪換理由** | ❌ | 🔴 **二輪的「順豐無 ZPL 證據」是錯的**——順豐有 `COM_RECE_CLOUD_PRINT_COMMAND`（SF-27）。**結論不變**（首發不接指令流），**理由改為範圍決策** |
| V-41 | 🟡 **三輪大幅縮小** | ✅ **在** | **目錄層已取得**（九大分類＋通用寄件類＋雲打印組，SF-28）；**逐介面欄位表仍缺 ⇒ 組不出請求** |
| **V-42** | 🟢 **四輪結案（`user-ruling`，營運／合約裁定）** | ❌ **已移出** | 🟢 **「未使用之號是否計費」＝否**（使用者裁定 A-2，SF-30／B-23）⇒ `billed_if_unused: false`，告警降為 **P3 資料一致性**。⚠️ **銷號時間窗與 `mailno` 是否回收兩問仍無來源** ⇒ `null`／`unknown`，號碼一律不重用。**三輪的新資訊完全沒碰到它，四輪是靠裁定結的，不是靠查證** |
| V-43 | 🟢 **三輪結案（`user-ruling`）** | ❌ **已移出** | **香港可以作為寄件地，使用者已成功開發過**（SF-25）。二輪「仍未確認 ⇒ 順豐不能當 HK 首發」作廢 |
| V-44 | 🟡 **三輪降級** | ❌ **已移出** | `express_type` 數值仍缺，但性質從「不知道能不能做」變成「知道能做、還沒看到值」⇒ 實作期實測；閘門下移到 lane 級（`service_code: null` ⇒ 該 lane 不可選） |
| V-45 | ⏳ 仍開 | （DHL／UPS／FedEx 的 gate）| 三輪未動 |
| V-46 | 🟡 部分 | ❌ | 速率上限仍無；六項官方分批上限已落 limits。**三輪新增一個理由讓它更重要**：不接推送 ⇒ 追蹤全走輪詢 ⇒ 配額壓力上升（§C.4） |
| V-47 | 🟡 **三輪處置再改** | ❌ **已移出** | 6 支不含推送 ⇒ K7 宣告 false ⇒ 驗簽問題不再適用。⚠️ **但事件碼值域的問題換到 K6 去了**，以 `unknown_event_code_action` fail-safe 接住（§C.4） |
| V-48 | ⏳ 仍開 | ❌ **已移出** | 6 支不含 COD ⇒ K9 宣告 false。香港 COD 的可用性與上限仍無任何來源，**但它不再擋任何事**——要接的那天再問 |
| V-49 | ✅ 二輪結案 | ❌ | 去重鍵是 `orderid` 不是 `requestID`，且回錯誤不回放 ⇒ `8016` 必須映射成 `unknown` |
| V-50 | ✅ 前輪已結案 | ❌ | — |
| **V-51** | 🔴 **不變** | ✅ **在** | `msgDigest` 演算法未載明——**第一號阻塞項**。**三輪的所有新資訊一條都沒碰到它** |
| V-52 | 🟡 二輪新登記 | ❌ | 憑證兩件式 vs 三件式有矛盾（設定頁預留第三欄位並標選填） |
| **V-53** | 🟡 **三輪新登記** | ❌ | **HK → 海外走哪一類介面？** 新平台把「國際件」列為**獨立頂層分類**（SF-28），與舊世代 PDF「國際件與國內件同用 `OrderService`」（SF-19）未對齊；跨境所需的報關欄位亦未取得。**不擋本地 lane** |
| **V-54** | 🟡 **三輪新登記** | ❌ | **順豐「指令流」是哪一種方言？** `COM_RECE_CLOUD_PRINT_COMMAND` 只說「指令」，**未載明是 ZPL 還是 TSPL／CPCL**。**不得假設是 ZPL**；本輪不接，不擋任何事 |

**三輪 gate 的淨變化：8 項 → 4 項**（移出 V-43／V-44／V-47／V-48，其餘不變）。**縮短的四項沒有一項是「查到答案」得來的**：兩項來自使用者裁定（可行性），兩項來自範圍決策（我們不做）。**真正靠查證縮小的 V-39／V-41 反而都還在 gate 裡。**

**四輪 gate 的淨變化：4 項 → 3 項 `[V-39, V-41, V-51]`**（移出 V-42，其餘不變）。**這一項同樣不是查到的**——它來自使用者裁定 A-2「取號未使用不會被計費」（SF-30／B-23），屬 §0.3 新增的**營運／合約裁定**類。
🔴 **統計一下這件事本身就是結論**：`sf_express` 的 gate 從 8 項縮到 3 項，**五項移出裡沒有任何一項是靠讀文檔讀出來的**（兩項使用者可行性裁定、兩項範圍決策、一項營運裁定）。**剩下的三項全部、且只能，由「拿到完整開發文檔」解決**——這正是 `docs/handoff/2026-08-12-open-decisions.md` A-4（丰橋帳號的文檔中心）投報率最高的原因：**三條阻塞一次解掉，gate 直接歸零。**
⚠️ **而 V-51 依然一動也沒動。四輪了。**「gate 的長度不代表嚴謹度」這句話，這是第三次成立。

| # | 待查證項目 | 去哪查 | 當前處置 | 阻塞什麼 |
|---|---|---|---|---|
| **V-37**<br>⏳ **仍開（未縮小）** | 順豐服務代碼的**完整值域**與各自語義（本檔 SF-9 列出的 `EXP_RECE_VALIDATE_WAYBILLNO`／`EXP_RECE_QUERY_GIS_DEPARTMENT`／`EXP_RECE_QUERY_DELIVERTM`／`EXP_RECE_SEARCH_PROMITM`／`EXP_EXCE_CHECK_PICKUP_TIME`／`EXP_RECE_CREATE_REVERSE_ORDER`／`EXP_RECE_WANTED_INTERCEPT` 僅有開源 SDK 常數表佐證）；特別是 `EXP_RECE_QUERY_SFWAYBILL` 的語義是否等同「運費試算」<br>**2026-08-12 二輪**：官方 SDK PDF 覆核後**仍只列 8 個**服務代碼（SF-4），未擴充；另由官方頁面標題新增確認 `COM_RECE_CLOUD_PRINT_WAYBILLS` 與 `COM_RECE_CLOUD_CUSTOMTEMPLATE_DELETE` 兩個**面單類**代碼（SF-20），但那不屬本項所問的速運類清單。**SF-9 那七個代碼的官方佐證仍為零。** | 丰桥開發者入口的目錄頁（需以瀏覽器渲染，見 V-41）；或申請沙箱後以實測覆核<br>**2026-08-12 三輪**：目錄層已由瀏覽器渲染取得（SF-28）——**`EXP_RECE_QUERY_SFWAYBILL` 的官方名稱是「清單運費查詢」**（⇒ 語義**不等於**下單前試算，K1 據此宣告 false）；`EXP_RECE_WANTED_INTERCEPT`／`EXP_RECE_GET_SUB_MAILNO` 確認存在於官方目錄；另見 `EXP_RECE_PRE_ORDER`／`EXP_RECE_DELIVERY_NOTICE`／`COM_RECE_QUERY_ADDRESS_BOOK_NEW` | **不再擋 gate**：K1／K8／K11 已依範圍決策宣告 `supported: false` ＋ reason（§B.1）。本項降為「未來要擴充範圍時再查」 | §B.1 |
| ~~**V-38**~~<br>✅ **已結案（2026-08-12）** | 順豐端點網域正確寫法：`sfapi.sfexpress.com`（官方 SDK PDF）vs `sfapi.sf-express.com`（第三方實作）<br>**答案：`sf-express.com`（有連字號）才是對的。** 權威 DNS 查詢顯示 `sfapi.sfexpress.com`、`sfapi-sbox.sfexpress.com` 乃至 apex `sfexpress.com` **皆無 A 記錄**；`sfapi.sf-express.com`／`sfapi-sbox.sf-express.com` 正常解析。**官方 SDK PDF 這一處是錯的或已過期。** | 已由 DNS 解析結案（B-12） | `base_url` 改為可填：沙箱 `https://sfapi-sbox.sf-express.com/std/service`、生產 `https://sfapi.sf-express.com/std/service`。**仍不自填**——設定期由下拉選單選，避免打錯字打到別人的主機 | 已無阻塞 |
| **V-39**<br>🟡 **已縮小，未結案** | 雲打印面單介面的**請求／回應欄位、回傳檔案形態、模板代碼、尺寸值域**<br>**2026-08-12 二輪已確認（官方）**：介面名「雲打印面單打印2.0接口」、服務代碼 `COM_RECE_CLOUD_PRINT_WAYBILLS`、分類「面單類API」；同族存在 `COM_RECE_CLOUD_CUSTOMTEMPLATE_DELETE`（可知模板可自訂）——SF-20。<br>**仍缺**：欄位表、回傳形態、模板代碼與尺寸的**官方**值域。第三方（1.0 版）佐證見 SF-22，**不得寫進 pack**。<br>**2026-08-12 三輪**：🟢 **格式一問結案**——順豐是**一種輸出一支介面**：`COM_RECE_CLOUD_PRINT_WAYBILLS`（→PDF，關聯 2024）、`COM_RECE_CLOUD_PRINT_HTML`（→HTML，**關聯 2026，新介面**）、`COM_RECE_CLOUD_PRINT_COMMAND`（→指令流，**我方不接**）。**仍缺欄位表／模板代碼／尺寸值域。** | 目錄頁需瀏覽器渲染（見 V-41）；或申請沙箱後實測 | `sf_express.label_render.formats = [pdf, html]`（**已可填**）、`sizes` 仍為 `null` ⇒ **仍不得 enable**。⚠️ HTML 那支是 2026 新介面，`carrierAccountTest` 必須**逐格式各測一次**（§D.2） | §D.2 |
| ~~**V-40**~~<br>✅ **已結案**<br>🔴 **但 2026-08-12 三輪推翻了它的事實前提，理由整段換掉** | 順豐**是否支援指令流輸出**（熱感標籤機直印）<br>~~**二輪查證結果**：無任何來源顯示順豐雲打印介面本身輸出 ZPL~~ ⇒ **這句是錯的。** 三輪以瀏覽器渲染官方目錄，掃到 **`COM_RECE_CLOUD_PRINT_COMMAND`（雲打印面單轉指令接口）**（SF-27）。<br>**結論不變、理由更換**：首發不接指令流，理由從「**順豐沒有**」改為「**範圍決策**」——使用者選定的 6 支是 PDF 與 HTML。<br>⚠️ 順豐的「指令」**未載明是 ZPL 還是 TSPL／CPCL** ⇒ 新登記 **V-54**。 | 已由 §D.2 決策結案（三輪換理由） | `sf_express.label_render.formats = [pdf, html]`，**不含指令流**；`zpl` 仍留在抽象層值域，位元組級處理規則**先寫規格、後做程式**。**日後要加，加的是 `COM_RECE_CLOUD_PRINT_COMMAND` 這支服務代碼 ＋ 同步更新 `api_scope`** | 已無阻塞（不在 `enable_gate`）|
| **V-41**<br>🟡 **已縮小，未結案** | 順豐開放平台的**完整介面目錄**（全部 `category` 分類名稱與逐介面欄位表）<br>**2026-08-12 二輪已確認**：URL 參數語義 ＋ 部分值域——`/Api?category={業務線}&apiClassify={介面型態}`，`category=1`＝速運類API、`category=4`＝冷運API、`apiClassify=1`＝請求／回應型、`apiClassify=2`＝推送型；舊式明細頁為 `level3={介面流水號}`（SF-21）。<br>~~**仍缺**：其餘 `category` 值的分類名稱與逐介面欄位表~~<br>**2026-08-12 三輪：目錄層已取得**（SF-28，B-22）——**九大頂層分類**（速運／基礎通用／冷運／快運／智能科技／解決方案／陸運／**國際件**／供應鏈科技）、**速運API 通用寄件類**九支、**雲打印組**八支。<br>**仍缺（本項現在只剩這一件）**：**逐介面的請求／回應欄位表。** | ✅ **二輪標為「未試而可行」的那一條路走通了**：**以能執行 JS 的瀏覽器渲染**（頁面不需登入）。<br>**剩下的欄位表**：明細頁需**逐頁**渲染，且部分疑須登入 ⇒ 最快的路是**申請丰橋帳號後看文檔中心**，不是繼續爬公開頁 | **仍擋 gate**：`msgData` 的欄位表沒有 ⇒ 組不出任何一個請求。**「知道有哪些介面」≠「知道怎麼呼叫」** | 全 pack |
| ~~**V-42**~~<br>🟢 **已結案（2026-08-12 四輪，`user-ruling`＝營運／合約裁定）**<br>❌ **已移出 `enable_gate`** | 順豐**運單號未使用的計費與銷號機制**<br>**2026-08-12 二輪已確認（官方）**：取消動作存在，`dealtype ∈ {1 確認, 2 取消}`（值域**已結案**）；**取消後客戶訂單號不得重複使用**；二次取消回 `8019`（SF-13／SF-14）。<br>**仍缺，且不會由 API 文檔回答**：①未使用之運單號是否計費 ②可銷號時間窗 ③銷號後 `mailno` 是否回收——官方兩份 PDF **通篇沉默**（SF-15）。<br>**2026-08-12 三輪**：使用者選定的 6 支**含** `EXP_RECE_UPDATE_ORDER`（訂單取消）⇒ **取消動作我方拿得到，但「取消訂單」對 `mailno` 的計費／回收效果仍然無解**（§D.5(h)）。**該輪的新資訊完全沒有觸及這一項。**<br>🟢 **2026-08-12 四輪：①已答——使用者裁定 A-2 逐字「不會計費」**（SF-30／B-23）。**②③ 仍無來源，使用者未裁定。** | ~~🔴 順豐月結合約條款／商務窗口書面回覆~~ ⇒ **①已由合約當事人（使用者）裁定結案**；**②③ 仍須順豐商務窗口的書面回覆**，建議併行取得（它能一次答完三問） | 🟢 **`billed_if_unused: false`**；逾期未銷的告警由「保守側 P1」降為 **P3 資料一致性事故、僅通知平台營運**（§D.5(d)）。<br>**其餘處置一律不變**：`shipment_void` 維持 `supported: false` ＋ reason（§D.5(g) 過渡）、`window_hours: null`、`frees_number: unknown` ⇒ 號碼一律不重用；順豐運單一律進 `VOID_MANUAL_REQUIRED`，**取消成功仍不得寫成 `VOIDED`**（§D.5(h) 規則 1——另一半理由「識別是否已結」仍未知）。<br>**§D.5 的 (b) 五場景／(c) 閉環不變量／(e) 待銷號佇列／(f) 識別不重用：一條都沒拿掉**（(a0)） | §D.5 |
| ~~**V-43**~~<br>🟢 **已結案（2026-08-12 三輪，`user-ruling`）** | 順豐**香港站與丰桥是否為同一套 API**；香港商戶要對接走哪個入口<br>~~**二輪答案**：香港作為「寄件地」＝仍未確認，丰橋文檔全篇以中國內地為寄件地 ⇒ 順豐不能當 HK 首發~~<br>🟢 **三輪答案：香港可以作為發貨地（origin）。使用者已成功開發過**（SF-25，逐字：「香港地區可以作為發貨地。已經成功開發過。」）。<br>🔴 **我方前兩輪的錯在方法不在資料**：從「公開文檔沒寫」推出「做不到」——**文檔取樣的缺口不等於產品的缺口**。 | 已由使用者一手實作經驗結案（B-21）。**帳號開通路徑**仍建議向順豐香港窗口確認 | `serviceable_lanes` **不再是空陣列**：納入 `HK→HK`（本地）與 `HK→(未登錄)`（出境）兩條，**`service_code` 皆為 `null`**；`lane_requires_service_code: true` ⇒ **`null` 的 lane 不得對外可選** | 已無阻塞（**已移出 `enable_gate`**）|
| **V-44**<br>🟡 **三輪降級為實作期確認項** | 順豐**香港／中港澳／國際的服務代碼值域**與各自可用性<br>**二輪已確認**：香港端**服務名稱**為「標準快遞 / Standard Express」與「國際特惠 / Economy Express」，涵蓋 40＋ 目的地含澳門、台灣（B-19）。<br>**仍缺**：名稱到 `express_type` **數值代碼**的對應——官方 PDF 明指值域在附錄《快件產品類別表》，**該附錄未含於 PDF 內，亦未給出檔名或 URL**（SF-19）。<br>**三輪性質改變**：origin 可行已確認（SF-25）⇒ 從「不知道能不能做」變成「**知道能做、還沒看到值**」。 | 申請丰橋帳號後**實測**（最快）；或向順豐香港窗口索取《快件產品類別表》 | 🔴 **不得憑空編數值。** lane 的 `service_code` 維持 `null`，該 lane 不對外可選（CI-9）。**憑空編的代價不是被拒單，是下成別的產品類別、按別的費率計費，而且看起來一切正常** | §H.2、§H.5（**已移出 `enable_gate`**）|
| **V-45** | **DHL Express／UPS／FedEx 的逐項能力值**：面單格式代碼與尺寸代碼、作廢／取消的時間窗與是否釋放號碼、推送 webhook 的驗簽方式 | DHL：`developer.dhl.com`（Reference Data Guide）；UPS：`developer.ups.com`；FedEx：`developer.fedex.com`。**本輪僅取得 DHL 的端點與操作分類**（B-8），UPS／FedEx 僅有第三方佐證 | 三個 pack 皆 `enable_gate: [V-45]`，不得 enable | §B.1 |
| **V-46**<br>🟡 **已部分結案** | 順豐的**限流（QPS／日配額）與逾時重試建議**<br>**2026-08-12 二輪**：QPS／日配額／重試建議——**再次覆核兩份官方 PDF，確認通篇未載明**（SF-7 維持）。**但取得了另一類真實的官方上限**：`OrderFilterService` ≤5、`RouteService` ≤10 個 `tracking_number`、`RoutePushService` ≤10 個 `WaybillRoute`、RLS 路由標籤批次 ≤100（超過回 `0003`）、`OrderZDService` 的 `parcel_quantity` ≤20（SF-18）。**這些是分批上限，不是速率上限——兩者不可互相替代。** | 丰桥控制台的配額頁；或與順豐技術窗口確認 | 速率：客戶端自我節流取 `limits.carrier.client_qps_default`（保守值），**不假設物流商端無限制**。<br>分批：一律取 `limits.carrier.packs.sf_express.documented_limits.*`，**不得硬編**（鐵律 6） | §F.5 |
| **V-47**<br>🟡 **部分結案，且答案改變了處置方向** | 順豐**路由推送**的**驗簽方式、重送策略、事件代碼值域**<br>**2026-08-12 二輪已確認（官方）**：舊世代 `RoutePushService` **沒有定義任何驗簽欄位**；接收方只能回 XML `OK`／`ERR`；失敗時順豐重推全部資訊但**未載明次數與間隔**（SF-16）。路由操作碼**未在規範內列舉**，僅示例 `50`／`922`（SF-17）。<br>**仍缺**：新世代 `EXP_RECE_REGISTER_ROUTE` 的推送是否附簽章；事件代碼完整值域。<br>**2026-08-12 三輪**：使用者選定的 6 支**不含**路由註冊／推送 ⇒ K7 宣告 `supported: false` ＋ reason，**驗簽一問對我方不再適用**。⚠️ **但事件碼值域的問題換到 K6 去了**——`EXP_RECE_SEARCH_ROUTES` 拉回來的事件同樣要映射。 | 同 V-41（目錄頁）；事件碼另需順豐「文檔中心」的操作碼表 | **三輪處置**：①K7 宣告 false ⇒ **移出 `enable_gate`**；②**事件碼以 fail-safe 接住**：`limits.carrier.tracking.unknown_event_code_action: timeline_only_no_state_change`——未知碼照樣入時間軸、**不得**映到終態、**絕對不得**推導出 `DELIVERED`／`READY_FOR_PICKUP`，未知碼比例進 dashboard；③**不得**拿 `50`／`922` 兩個示例值當值域 | §C.4 |
| **V-48**<br>⏳ **仍開，但不再擋任何事** | 順豐 **COD（代收貨款）在香港的可用性、上限、撥款週期與對帳檔格式**<br>**2026-08-12 二輪**：順豐香港官網價目表（B-19）與聚合商文檔（B-18）**均未提及** COD。仍無任何來源。<br>**三輪**：6 支不含任何 COD 介面 ⇒ **範圍決策**，K9 宣告 `supported: false` ＋ reason。 | 順豐香港商務窗口（屬合約值，非 API 文檔） | `cod.supported: false` ＋ reason ⇒ COD × 順豐的組合在結帳頁**不出現**（15 的付款×配送相容矩陣直接排除）。**移出 `enable_gate`**——「我們決定不做」不需要 V 編號來擋。<br>⚠️ 未來要接時，`max_cents` 一律 integer cents，且 `effective_cod_max = min(carrier, jurisdiction)`，任一為 `null` ⇒ reject（§A.2 K9、鐵律 3／65） | §A.2 K9 |
| **V-49**<br>✅ **已實質結案（2026-08-12）** | 順豐的**冪等機制**：`requestID` 是否被伺服器端去重、重送的語義<br>**答案**：①**`requestID` 沒有證據被去重**——官方 SDK 只把它示範成每次新產生的 UUID，未賦予任何去重語義 ⇒ **一律當作不去重**；②**真正被去重的是 `orderid`（客戶訂單號）**，重複會下單失敗並回 `8016`；③**`8016` 回錯誤、不回放原結果**（錯誤報文不夾帶 `mailno`）。 | 已由 B-1／B-2 官方 PDF 結案 | **三條實作後果**：①我方第一層冪等必須完全自理，不得指望第二層；②`orderid`＝`client_reference`＝`shipment_intents.id`，且**永不重用**（`client_reference_reuse_forbidden`）；③🔴 **`8016` 必須映射成 `unknown` 而非 `business_rejected`**，走 §F.4 回查。映射表與必要測試見 §E.2 | §E.2 |
| **V-51**<br>🔴 **二輪新登記（發現於誤標）；三輪一動也沒動** | 順豐 `msgDigest` **簽章演算法**：串接順序、雜湊演算法、編碼方式。官方 SDK 只暴露方法簽名 `getMsgDigest(msgData, timeStamp, checkWord)`，**兩份官方 PDF 均未載明演算法本身**（SF-11，二輪再次覆核仍未載明）。<br>**2026-08-12 三輪**：目錄頁渲染取得的是**介面名與分類**，**簽章說明不在目錄頁上** ⇒ 本項**完全未被觸及**。 | 丰桥開發者入口的簽章說明；或**直接讀官方 SDK 的 jar／zip**（SDK 指南提及 `SF-CSIM-EXPRESS-SDK-V2.1.6.jar` 但**未給下載 URL**，本輪亦無法下載二進位檔）；**最快的路是申請帳號後看文檔中心** | 🔴 **這是 `sf_express` 的第一號阻塞項——算不出簽章就一個請求都送不出去。** 它擋的不是某一項能力，是 **K2／K3／K5／K6 一起卡死**。<br>**三輪 gate 從 8 項減到 4 項，這一項紋風不動——gate 的長度不代表嚴謹度** | 全 pack 的連線 |
| **V-52**<br>🟡 **新登記（低優先）** | 順豐憑證究竟是**兩件式**（`clientCode` ＋ `checkword`，SF-3）還是**三件式**（`customer_code` ＋ `customer_id` ＋ `checkword`，聚合商 EasyPost 的要求，SF-24） | 丰桥控制台的憑證頁；或申請沙箱後實測 | `credential_schema` 以官方 SDK 的兩件式為準，但**設定頁預留第三欄位並標為選填**，待覆核 | §G.2 |
| **V-53**<br>🟡 **三輪新登記** | **HK → 海外的跨境件走哪一類介面，以及跨境所需的報關欄位**<br>新平台把**「國際件」列為獨立頂層分類**（SF-28），而舊世代 PDF 說「國際件與國內件同用 `OrderService`」（SF-19）——**兩者未對齊**，可能是世代差異也可能是分類差異。另：香港出境的**目的地清單**（B-19 稱 40＋）我方未逐一取得。 | 丰橋目錄的「國際件」分類頁（需渲染）；或申請帳號後看文檔中心；目的地清單可由 B-19 價目表逐一登錄 | **跨境 lane 本輪不點亮**，有**兩道獨立閘門**兜住：①`customs_doc.supported: false`（§H.2 關卡 1 判不可服務）；②lane 的 `destination_country` 為 `null`，而 **`null` 不是萬用字元、不命中任何目的地**。<br>**不擋本地 lane，不進 `enable_gate`** | §H.2、§H.5 |
| **V-54**<br>🟡 **三輪新登記（低優先）** | **順豐「雲打印面單轉指令接口」（`COM_RECE_CLOUD_PRINT_COMMAND`）輸出的是哪一種指令方言**——ZPL？TSPL？CPCL？介面名只說「指令」（SF-27）。 | 該介面的明細頁（需渲染／帳號）；或實測 | **本輪不接（範圍決策）** ⇒ 不擋任何事。🔴 **要接的時候先確認方言，不得因為我方值域裡有 `zpl` 就假設它是 ZPL**——猜錯的結果是印出一堆亂碼標籤，而且是在倉庫現場才發現 | §D.2 |
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

**第三輪新增（2026-08-12）**

| # | URL／來源 | 取得了什麼 | 出處等級 |
|---|---|---|---|
| **B-21** | **使用者裁定（2026-08-12，含其提供的丰橋控制台截圖，逐字抄錄於 §0.4(e)）** | ①**香港可作為發貨地，已成功開發過**（SF-25）；②**我方對接範圍＝6 支服務代碼**（含名稱／分類／報文格式／狀態／關聯日期，SF-26）；③`EXP_RECE_UPDATE_ORDER` 在截圖中的名稱為「訂單取消接口」（SF-29） | **`user-ruling`**（一手實作經驗 ＋ 範圍裁定）<br>⚠️ **可據以推翻否定推論、可據以劃定範圍；不可據以填入參數值** |
| **B-22** | `https://open.sf-express.com/Api?...` — **以能執行 JS 的瀏覽器渲染後的官方目錄頁**（二輪標為「下一輪最有效的一步」的那一條路） | ①**九大頂層分類**（速運／基礎通用／冷運／快運／智能科技／解決方案／陸運／國際件／供應鏈科技）；②**速運API 通用寄件類**九支服務代碼；③**雲打印組**八支（含 **`COM_RECE_CLOUD_PRINT_COMMAND`** ⇒ 推翻 SF-23）；④`EXP_RECE_QUERY_SFWAYBILL` 的官方名稱是「**清單運費查詢**」（SF-27／SF-28） | `carrier-official`（順豐官方頁面渲染後的正文）<br>⚠️ **僅介面名與分類，欄位表仍未取得**（V-39／V-41 仍開）|

**第四輪新增（2026-08-12）**

| # | URL／來源 | 取得了什麼 | 出處等級 |
|---|---|---|---|
| **B-23** | **使用者裁定（2026-08-12，逐字：「A2 不會計費。」）**，對應 `docs/handoff/2026-08-12-open-decisions.md` 的 **A-2**（「順豐銷號成本：接受人工銷號，還是等順豐書面回覆？」） | **取號未使用不會被順豐計費**（SF-30）⇒ V-42 的第一問結案，`sf_express.shipment_void.billed_if_unused = false`，V-42 移出 `enable_gate` | **`user-ruling`**（**營運／合約裁定**，§0.3 第四輪新增的第二類）<br>⚠️ **只答了三問中的第一問**：`window_hours` 與 `frees_number` 使用者未裁定、官方仍沉默 ⇒ 維持 `null`／`unknown`<br>🔴 **不是書面合約回覆。** 若日後取得順豐書面文件，應在此補一列 `carrier-official` 級來源覆核本條 |

**本輪試過但取不到的路徑（記錄下來以免下一輪重複）**

| 路徑 | 結果 |
|---|---|
| `https://qiao.sf-express.com/Api?category=1&apiClassify=1`、`?category=6&apiClassify=2`（使用者提供）| WebFetch 只得 `<meta>`；**正文由 JS 渲染** |
| `https://qiao.sf-express.com/robots.txt`、`/sitemap.xml` | **回 SPA 外殼**（該站對未命中靜態檔的路徑一律回退 index.html）⇒ 無法用站內索引枚舉 |
| 容器內 `curl` 直連 `qiao.sf-express.com` | 出口政策 **CONNECT 403** |
| `https://web.archive.org/cdx/search/cdx?url=open.sf-express.com/Api*` | 出口政策 **403**（該網域被阻擋），無法用 CDX 枚舉歷史 URL |
| 第三方渲染／代理服務（`r.jina.ai`、`api.microlink.io`、`api.codetabs.com`、`api.allorigins.win`）| 分別為 403／robots 禁止／robots 禁止／逾時 |
| GitHub 程式碼搜尋（找 SDK 常數表）| 本 session 僅允許 repo-scoped 端點，搜尋 API 回 403 |

<!-- 依 2026-08-12 第三輪更新。二輪原文：「⭐ 下一輪最有效的一步：用能執行 JS 的瀏覽器開 …Api?category=1&apiClassify=1。
     一次渲染即可同時結案 V-37／V-39／V-41／V-47（事件碼）／V-51。」 -->

> ✅ **二輪的「⭐ 下一輪最有效的一步」已經執行，而且有效**：以能執行 JS 的瀏覽器渲染官方目錄，取得九大分類、通用寄件類與雲打印組（SF-27／SF-28，B-22）。
> **但它沒有結案二輪預期的那麼多**：目錄頁只給**介面名與分類**，**欄位表在明細頁**（需逐頁渲染，部分疑須登入），`msgDigest` 演算法更不在目錄頁上。⇒ **V-37 縮小、V-41 大幅縮小，但 V-39／V-41／V-51 仍開。**
> **這件事本身是個教訓**：「一次渲染就能結案五項」是**對未見頁面的內容做的樂觀假設**——與「因為文檔沒寫所以做不到」是同一類錯誤的鏡像。**對還沒看到的東西，樂觀與悲觀都是猜。**
>
> ⭐ **下一輪最有效的一步（已改）**：**申請丰橋帳號，取得文檔中心存取權**。
> 理由：~~剩下的四項 gate 有三項~~ 🟢 **（第四輪）剩下的 gate 就是那三項**（**V-39 面單欄位與尺寸／V-41 逐介面欄位表／V-51 `msgDigest` 演算法**），**全部**是「文檔在牆後面」，帳號到手當天即可**全數**結案、**gate 歸零**；而爬公開頁已經爬到盡頭。
> ~~**V-42 例外**：它是合約問題，**無論如何都不會由任何網頁或文檔中心回答**——必須走順豐月結／商務窗口，且要書面。~~
> 🟢 **V-42 已於第四輪由使用者裁定結案**（不計費，SF-30／B-23），**已不在 gate 內**。上面那句「它是合約問題，不會由任何網頁或文檔中心回答」**判斷完全正確，只是出口不只書面回覆一條**——合約當事人本人的明示裁定也算（§0.3 的「營運／合約裁定」類）。
> ⚠️ **但 V-42 的剩餘兩問（銷號時間窗、`mailno` 是否回收）仍然只有商務窗口能答**，且**它們不在文檔中心裡**——拿到帳號也不會結案。要一起解，得走商務。

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
