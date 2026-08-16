# 09. 履約與物流（FulfillmentOrders / Shipping / Delivery）

> 考掘日：2026-08-14。來源＝shopify.dev（GraphQL Admin API 參考頁＋app 開發指南）與 help.shopify.com；全部斷言標「取證 2026-08-14」，URL 見 §G。
> 與倉庫既有文檔的關係：`docs/research/46a` §2/§3 已有 FulfillmentOrder／Fulfillment 狀態機逐字考掘、`docs/specs/16` F3 已落地為規格、`docs/specs/58` 已定 carrier pack 抽象。本章**不重抄**它們，而是補齊它們未覆蓋的面：**shipping profiles × zones × rates 的計價模型、rate 合併規則、carrier-calculated 回呼契約、local delivery／local pickup、delivery dates、packing slips**，並校正兩處與最新 API 版本的偏差（見 §F 差異表 D7／D8）。

---

## A. 領域物件模型

### A.1 履約側（誰出貨）

```
Order 1 ──< N FulfillmentOrder（訂單成立時由 order routing 自動建立，不可手建）
              │  assignedLocation（快照＋location 參照）
              │  deliveryMethod（SHIPPING / LOCAL / PICK_UP / PICKUP_POINT / RETAIL / NONE）
              │  1 ──< N FulfillmentOrderLineItem
              │  1 ──< N FulfillmentHold（2025-01 起可多個；每 app ≤10）
              │  1 ──< N FulfillmentOrderMerchantRequest（對 3PL 的請求史）
              └──< N Fulfillment（多對多的實際形態：一張 Fulfillment 可吃同 order＋同 location 的多張 FO）
                      │  1 ──< N FulfillmentTrackingInfo（多包裹多 tracking）
                      │  1 ──< N FulfillmentEvent（shipment status 事件流）
                      └── service → FulfillmentService（3PL 註冊實體，綁一個 Location）
```

**FulfillmentOrder 關鍵欄位**（取證 2026-08-14，shopify.dev objects/FulfillmentOrder）：

| 欄位 | 型別 | 語義 |
|---|---|---|
| `status` | `FulfillmentOrderStatus!` | 7 值，見 §B.1 |
| `requestStatus` | `FulfillmentOrderRequestStatus!` | 8 值，3PL 請求軸，見 §B.2 |
| `supportedActions` | `[FulfillmentOrderSupportedAction!]!` | 伺服器計算的可用動作（12 值，46a 已窮舉） |
| `assignedLocation` | `FulfillmentOrderAssignedLocation!` | **地址快照**＋`location` 參照（見下） |
| `destination` | `FulfillmentOrderDestination` | 收件目的地（digital 商品可為 null） |
| `deliveryMethod` | `DeliveryMethod` | 含 `methodType`（6 值，§A.3） |
| `fulfillAt` | `DateTime` | 排程履約時點；到點自動 SCHEDULED→OPEN |
| `fulfillBy` | `DateTime` | 最遲履約期限 |
| `fulfillmentHolds` | `[FulfillmentHold!]!` | 當前 active holds |
| `lineItems` / `fulfillments` / `merchantRequests` / `locationsForMove` / `fulfillmentOrdersForMerge` | connection | 均 cursor 分頁 |
| `orderId` / `orderName` / `orderProcessedAt` | — | 訂單反參照 |
| `remainingLineItemsWeight` | `Weight` | 未履約品項總重（給運費／面單用） |
| `channelId` | `ID` | deprecated |

**assignedLocation 是快照不是外鍵**（取證 2026-08-14）：`FulfillmentOrderAssignedLocation` 帶 `name!`、`countryCode!`、`address1/2`、`city`、`province`、`zip`、`phone`、`location`（可 null）。location 可 null 的原因：FO 進入不再改址的狀態後留的是**當時的地址快照**，原 Location 之後被刪除時參照失效但快照仍在。⇒ 我方 `fulfillment_orders` 表必須**內嵌地址快照欄位**，不得只存 `location_id`。

**assignedLocation 何時會變**（取證 2026-08-14）：①整張 FO 被 `fulfillmentOrderMove` 移走；②工作尚未開始（status ∈ OPEN/SCHEDULED/ON_HOLD）且商店對 location 屬性做了編輯。

**FulfillmentHold 欄位**（取證 2026-08-14）：`id!`、`reason!`（8 值 enum，46a 已窮舉）、`reasonNotes`、`displayReason!`（本地化顯示文案）、`heldByApp`（建立此 hold 的 app，可 null）、`heldByRequestingApp!`（bool）、`handle`（**同一 app 放多個 hold 時的識別符**）。

**Fulfillment 關鍵欄位**（取證 2026-08-14）：`status!`（4 現行＋2 deprecated，§B.3）、`displayStatus`（18 值，§B.5）、`trackingInfo!`（陣列）、`events`（connection）、`estimatedDeliveryAt`、`inTransitAt`、`deliveredAt`、`location`、`service`、`originAddress`、`requiresShipping!`、`totalQuantity!`、`fulfillmentLineItems`。

**FulfillmentTrackingInfo**：`company` / `number` / `url` 三欄。多包裹用 `numbers[]`＋`urls[]`（input 側），`company` 套用到全部號碼。company 命中官方支援清單時 Shopify **自動生成 tracking URL**；不命中但格式可辨識時會嘗試生成（可能生錯）；官方建議 company＋url 都給。支援清單（全球段，取證 2026-08-14，共 108 個字串）：4PX、AGS、Amazon、Amazon Logistics UK、An Post、Anjun Logistics、APC、Asendia USA、Australia Post、Bonshaw、BPost、BPost International、Canada Post、Canpar、CDL Last Mile、China Post、Chronopost、Chukou1、Colissimo、Comingle、Coordinadora、Correios、Correos、CTT、CTT Express、Cyprus Post、Delnext、Deutsche Post、DHL eCommerce、DHL eCommerce Asia、DHL Express、DPD、DPD Local、DPD UK、DTD Express、DX、Eagle、Estes、Evri、FedEx、First Global Logistics、First Line、FSC、Fulfilla、GLS、Guangdong Weisuyi Information Technology (WSE)、Heppner Internationale Spedition GmbH & Co.、Iceland Post、IDEX、Israel Post、Japan Post (EN)、Japan Post (JA)、La Poste Colissimo、La Poste Burkina Faso、Lasership、Latvia Post、Lietuvos Paštas、Logisters、Lone Star Overnight、M3 Logistics、Meteor Space、Mondial Relay、New Zealand Post、NinjaVan、North Russia Supply Chain (Shenzhen) Co.、OnTrac、Packeta、Pago Logistics、Ping An Da Tengfei Express、Pitney Bowes、Portal PostNord、Poste Italiane、PostNL、PostNord DK、PostNord NO、PostNord SE、Purolator、Qxpress、Qyun Express、Royal Mail、Royal Shipments、Sagawa (EN)、Sagawa (JA)、Sendle、SF Express、SFC Fulfillment、ShipBob、SHREE NANDAN COURIER、Singapore Post、Southwest Air Cargo、StarTrack、Step Forward Freight、Swiss Post、TForce Final Mile、Tinghao、TNT、Toll IPEC、United Delivery Service、UPS、USPS、Venipak、We Post、Whistl、Wizmo、WMYC、Xpedigo、XPO Logistics、Yamato (EN)、Yamato (JA)、YiFan Express、YunExpress。⚠️ 同頁另有 per-country 附加清單（澳、奧、保、加、中、捷、德、西、法、英、希、港、愛、印、義、日、荷、挪、波、土、美、南非），逐國字串未全量抄錄——實作時直接以該頁為 source of truth 生成 seed 資料。

**FulfillmentService（3PL 註冊實體）**（取證 2026-08-14）：以 `fulfillmentServiceCreate` 建立（`name` 唯一、`callbackUrl` 必填），建立時 Shopify **同時生成一個綁定的 Location**。可選能力：tracking 支援（Shopify 每小時 POST `{callbackUrl}/fetch_tracking_numbers` 拉回單號）、庫存管理（POST `{callbackUrl}/fetch_stock`，回 `{"SKU123": 10}`，SKU 區分大小寫，商品設定變更時＋每小時觸發）。通知走 POST `{callbackUrl}/fulfillment_order_notification`，payload 只有 `{"kind": "FULFILLMENT_REQUEST"}` 或 `{"kind": "CANCELLATION_REQUEST"}`（**不含資料本體**，app 須自行回查 `assignedFulfillmentOrders`），驗簽用與 webhook 相同的 HMAC。

### A.2 計價側（收多少運費）

```
Shop 1 ── 1 general DeliveryProfile（default=true，所有商品預設歸屬）
     1 ──< ≤99 custom DeliveryProfile（per-product/variant 指派）
DeliveryProfile 1 ──< N DeliveryProfileLocationGroup（出貨地分組；per-location 費率的載體）
LocationGroup 1 ──< N Zone（DeliveryZone＝國家/地區集合）
Zone 1 ──< N DeliveryMethodDefinition（一條「可選運送方式」）
MethodDefinition 1 ── methodConditions: [DeliveryCondition!]!（0..N 條門檻）
              1 ── rateProvider: DeliveryRateDefinition（自訂價）| DeliveryParticipant（carrier-calculated）
```

（結構取證 2026-08-14：objects/DeliveryProfile、DeliveryMethodDefinition、DeliveryParticipant、DeliveryCondition。）

| 物件 | 關鍵欄位 |
|---|---|
| `DeliveryProfile` | `default!`、`name!`、`profileLocationGroups!`、`profileItems`（歸屬的商品）、`sellingPlanGroups`、`zoneCountryCount!`、`locationsWithoutRatesCount!`、`originLocationCount!`、`activeMethodDefinitionsCount!`、`unassignedLocations!`、`coversAllItems!`、`version!` |
| `DeliveryMethodDefinition` | `active!`、`name!`（**費率名稱＝合併規則的 key**，見 §C.2）、`description`（僅自訂費率有）、`methodConditions!`、`rateProvider!` |
| `DeliveryCondition` | `field`（enum 僅 2 值：`TOTAL_PRICE`、`TOTAL_WEIGHT`）、`operator`（enum 僅 2 值：`GREATER_THAN_OR_EQUAL_TO`、`LESS_THAN_OR_EQUAL_TO`）、`conditionCriteria`（union：`MoneyV2` 或 `Weight`） |
| `DeliveryRateDefinition` | `price`（MoneyV2 固定價） |
| `DeliveryParticipant` | `carrierService!`、`fixedFee`（MoneyV2 加價）、`percentageOfRateFee!`（百分比加價）、`participantServices!`（逐服務啟用開關）、`adaptToNewServicesFlag!`（新服務自動上架） |

min/max 條件的表達：一條 rate 的「最小值」＝一條 `GREATER_THAN_OR_EQUAL_TO` condition、「最大值」＝一條 `LESS_THAN_OR_EQUAL_TO` condition；**同一條 rate 的條件只能同 field**（admin UI 的 rate type 是單選：Flat／Order amount／Weight，價格條件與重量條件不能混在同一條 rate 上；取證 2026-08-14，help setting-up-shipping-rates）。

**CarrierService（app 提供即時費率）**：`carrierServiceCreate`（GraphQL）／REST 同名資源；欄位 `name`、`callbackUrl`、`supportsServiceDiscovery`（讓商家在 admin 測試連通）、`active`。回呼契約全文見 §C.3。

### A.3 DeliveryMethodType 值域（FO 的運送形態，6 值全）

（取證 2026-08-14，enums/DeliveryMethodType）

| 值 | 語義 |
|---|---|
| `SHIPPING` | 承運商寄送 |
| `LOCAL` | 本地配送（商家自送） |
| `PICK_UP` | 顧客到店自取 |
| `PICKUP_POINT` | 送到取貨點 |
| `RETAIL` | 門市現場銷售，無配送 |
| `NONE` | 非實體品項，無配送 |

---

## B. 狀態機

### B.1 FulfillmentOrder.status（7 值）與 B.2 requestStatus（8 值）

**值域與轉移表已由 `46a` §2① 逐字考掘、`16` F3.1 落為規格（7 status × 8 requestStatus × 12 supportedActions ＋ T1–T16 轉移表），本輪對 shopify.dev 復核結果＝一致**（取證 2026-08-14：fulfillment service 指南明列 status 7 值 `OPEN / IN_PROGRESS / SCHEDULED / CANCELLED / INCOMPLETE / ON_HOLD / CLOSED`）。本節只補本輪新證實的四條：

1. **3PL 流程的狀態聯動**（取證 2026-08-14，build-for-fulfillment-services）：
   - accept 請求 ⇒ `status: IN_PROGRESS` ＋ `requestStatus: ACCEPTED`
   - reject 請求 ⇒ `status: OPEN` ＋ `requestStatus: REJECTED`（**status 退回 OPEN**，商家可改派）
   - accept 取消請求 ⇒ `status: CANCELLED` ＋ `requestStatus: CANCELLATION_ACCEPTED`
   - reject 取消請求 ⇒ `status: IN_PROGRESS` ＋ `requestStatus: CANCELLATION_REJECTED`
   - 3PL 收單後做不下去 ⇒ `fulfillmentOrderClose` ⇒ `status: INCOMPLETE` ＋ `requestStatus: CLOSED`；商家重新提交會**產生新 FO**。
2. **SCHEDULED 的來源**（取證 2026-08-14）：`fulfill_at` 有值且在未來（訂閱單＝下一 anchor 日；一般單＝建單時間；pre-order＝nil）。到點自動轉 OPEN；`fulfillmentOrderOpen` 可提前拉開。
3. **hold 疊加**（取證 2026-08-14，mutations/fulfillmentOrderHold）：2025-01 起**已在 ON_HOLD 的 FO 可以再放 hold**；`fulfillmentOrderReleaseHold` 支援 `holdIds` 選擇性釋放，**省略 holdIds ＝ 全部釋放**（文檔明示有誤放風險）；全部釋放完才離開 ON_HOLD。⇒ 16-F3 T5 的 guard 要從「status ∈ {OPEN, SCHEDULED}」放寬為「非終態即可疊加」（差異 D7）。
4. **move 的返回語義已改版**（取證 2026-08-14，mutations/fulfillmentOrderMove）：`remainingFulfillmentOrder` **已標 deprecated**；現行語義＝`movedFulfillmentOrder`（若原單無任何已履約品項→就是原單整張搬家；否則→目的地新建的 FO）＋`originalFulfillmentOrder`（原單終態）。move 的禁止條件（文檔明列）：FO 已 closed；曾手動 report progress（須先 mark as open）；目的地 location 不備該 inventory item；requestStatus ∈ {SUBMITTED, ACCEPTED, CANCELLATION_REQUESTED, CANCELLATION_REJECTED}（3PL 請求懸置中）。**已履約品項永遠留在原 location**。

### B.3 Fulfillment.status（4 現行＋2 deprecated）

46a §3 已考掘：現行 `SUCCESS` / `CANCELLED` / `ERROR` / `FAILURE`；`OPEN` / `PENDING` 為 deprecated（legacy API 世代的「pending fulfillment」概念，遷移文檔明言新世代直接建 successful fulfillment，取證 2026-08-14）。Fulfillment 無復活轉移：`SUCCESS → CANCELLED`（`fulfillmentCancel`）為唯一後續轉移，取消後要重出貨＝在（自動重開或新建的）FO 上再建一張新 Fulfillment。**`fulfillmentCancel` 的副作用**（取證 2026-08-14）：FO 若已整單出貨完畢而被關閉→自動重開處理；部分出貨→為被取消數量**建新 FO**；多地點庫存情境可能一次生多張新 FO。🔴 **庫存語義**（<!-- 2026-08-17 更正（PR #52 第 5 輪） -->，原文未定義）：取消時**同一 transaction 原子回補 `committed +q`／`on_hand +q`**（T2 出貨已扣的量；不回補則替代 FO 再出貨會二次扣減、或因無 committed 而失敗）；貨已實體寄出但記錄取消的案例以人工調整對帳（官方未明文，列 parity 實測 V）。

### B.4 FulfillmentEventStatus（11 值全，shipment 事件流）

（取證 2026-08-14，enums/FulfillmentEventStatus。事件由商家/app 以 `fulfillmentEventCreate` 寫入，或由 carrier 整合自動寫入。）

| 值 | 語義 |
|---|---|
| `CONFIRMED` | 已確認（**無其他資訊時的預設值**） |
| `LABEL_PURCHASED` | 面單已購買 |
| `LABEL_PRINTED` | 面單已列印 |
| `READY_FOR_PICKUP` | 待取貨 |
| `CARRIER_PICKED_UP` | 承運商已攬收 |
| `IN_TRANSIT` | 運送中 |
| `OUT_FOR_DELIVERY` | 派送中 |
| `ATTEMPTED_DELIVERY` | 投遞未成功 |
| `DELIVERED` | 已送達 |
| `DELAYED` | 延誤 |
| `FAILURE` | 履約請求失敗 |

`FulfillmentEventInput`：`fulfillmentId!`、`status!`、`happenedAt`、`estimatedDeliveryAt`、`message`、`address1`、`city`、`province`、`country`、`zip`、`latitude`、`longitude`。事件是 append-only 流；fulfillment 的 `inTransitAt`／`deliveredAt`／`estimatedDeliveryAt` 與 `displayStatus` 由事件流推導。

**狀態機（我方落地裁定）**：事件流本身**不設全序**（DELAYED／ATTEMPTED_DELIVERY 可穿插；官方未定義事件間合法順序）⚠️——但 displayStatus 為**三軸合成**（優先序**逐狀態**：異常/終態 CANCELLED/ERROR/FAILURE 覆蓋陳舊事件 → 事件流最新一筆——普通 SUCCESS 不搶先，否則事件分支永不可達 → 無事件時 SUCCESS→FULFILLED → label/pickup 態，B.5 合成序；取消已送達/在途的 fulfillment 不產生新事件，latest-event-only 會永遠顯示 DELIVERED/IN_TRANSIT <!-- 2026-08-17 更正（PR #52 第 5 輪） -->：原句「取最新一筆事件映射」與 B.5/總綱 S9 修正互斥）；`DELIVERED` 寫入時同步落 `deliveredAt`，`IN_TRANSIT` 首次寫入落 `inTransitAt`。

### B.5 FulfillmentDisplayStatus（18 值全，UI 顯示層）

（取證 2026-08-14，enums/FulfillmentDisplayStatus）`ATTEMPTED_DELIVERY`、`CANCELED`（⚠️ 單 L，與 FO 的 `CANCELLED` 雙 L 不同拼法）、`CARRIER_PICKED_UP`、`CONFIRMED`、`DELAYED`、`DELIVERED`、`FAILURE`、`FULFILLED`、`IN_TRANSIT`、`LABEL_PRINTED`、`LABEL_PURCHASED`、`LABEL_VOIDED`、`MARKED_AS_FULFILLED`、`NOT_DELIVERED`、`OUT_FOR_DELIVERY`、`PICKED_UP`、`READY_FOR_PICKUP`、`SUBMITTED`。
來源三軸合成：Fulfillment.status（FULFILLED/CANCELED/FAILURE）＋事件流（11 值映射）＋面單/自取狀態（LABEL_*、MARKED_AS_FULFILLED、PICKED_UP、SUBMITTED）。displayStatus 是**計算欄位**，不落 DB、不做轉移驗證。

### B.6 Local pickup 訂單流（fulfillment 維度的子狀態機）

（取證 2026-08-14，help pickup-in-store）`Unfulfilled → Ready for pickup → Picked up（=fulfilled）`。
- 「Ready for pickup」由 staff 按下時**自動寄「可取貨」通知信**；
- 「Mark as picked up」時**可選**勾「Send notification to customer」補寄取貨完成信；
- 庫存不足時掛「Transfer required」badge（從其他 location 調撥，就近優先；可排除 collection、不能排除單品）。

### B.7 Local delivery 訂單流

（取證 2026-08-14，help local-delivery-fulfillment）`Unfulfilled → Ready for delivery → Delivered`。
- 「Ready for delivery」涵蓋「即將配送／配送中／投遞未成」三種實況（**help 側只有這一個中繼態**；GraphQL 側可用 fulfillment events 的 `OUT_FOR_DELIVERY`／`ATTEMPTED_DELIVERY` 細分）；
- **carrier 追蹤事件驅動的「Out for delivery」「Delivered」通知信不適用於 local delivery**（無 carrier 事件）；
- 標記 Delivered ⇒ 自動寄送達確認信；不標記＝不寄。

---

## C. 業務規則與不變量

### C.1 費率條件與免運

（取證 2026-08-14，help setting-up-shipping-rates）
- 三種 rate type：**Flat**（無條件）、**Order amount**（價格條件）、**Weight**（重量條件）。條件＝`Minimum` ＋ `Maximum` 兩欄；「Maximum 留空＝無上限」。**單一 rate 不可同時掛價格與重量條件**（UI 為單選 rate type；GraphQL 的 `DeliveryConditionField` 也僅 TOTAL_PRICE/TOTAL_WEIGHT 二擇一per condition）。
- 免運兩形態：①價格欄「留空或填 0」＝該 rate 免費；②勾「Offer free shipping」＋門檻金額＝滿額免運（實質＝一條 price ≥ X 的 0 元 rate）。
- **條件判定的計算基礎是該 profile×location group 分攤到的品項小計／總重**，不是整張購物車（多 profile 合併時逐組判定後再合併，見 C.2）。

### C.2 多 profile／多地點的運費合併公式（結帳時）

（取證 2026-08-14，help combined-shipping-rates；規則窮舉，共 4 條）

| # | 情境 | 規則 | 例 |
|---|---|---|---|
| R1 | 跨 profile，rate **同名** | **同名相加**，顯示原名（每個同名組各出一條） | 衣 profile「Standard $3／Expedited $9」＋褲 profile「Standard $2／Expedited $6」⇒「Standard $5」＋「Expedited $15」兩條都顯示 |
| R2 | 跨 profile，rate 名稱**無一同名** | **各 profile 取其最便宜的一條相加**，顯示名固定為「Shipping」（原 rate 名全部丟棄，只出這一條） | 衣 profile「Standard $3／Expedited $9」＋褲 profile「Basic $2／Very fast $6」⇒ 僅「Shipping $5」（＝衣組最便宜 $3 ＋ 褲組最便宜 $2） |
| R3 | 同一 location group 內多 location 分攤同單 | **flat rate 只收一次**：取 priority 最高 location 的 rate，其他 location 的 rate 記 $0；weight-based／carrier-calculated／app rates 則算合併費率 | — |
| R4 | 跨 location group | **各 group 的 rate 相加** | US 倉 $5 ＋ CA 倉 $8 ⇒ $13 |

**R2 例勘誤（本輪回原頁復核，取證 2026-08-14）**：前稿只抄到「Standard $3」＋「Very fast $6」兩條，按規則推不出官方結果 $5、自承含糊——復核 help combined-shipping-rates，官方例的第二個 profile 實有**兩條** rate（Basic $2／Very fast $6），前稿漏抄 Basic $2；$5＝$3＋$2，「各組取最便宜者相加」成立，**R2 期望值可斷言（F.3 測試矩陣 R2 斷言＝$5）**。⚠️ **部分同名、部分不同名的混合情境**（如衣有 Standard、褲有 Standard＋Basic：Standard 組走 R1 相加後，褲的 Basic 是否再觸發 R2）官方頁無例，規則字面（"aren't named the same in both profiles"）只覆蓋「無一同名」——R1/R2 邊界官方未明文，待實測店驗證後補。

**無法關閉**：官方明言不提供停用合併的開關。⇒ 我方結帳運費引擎的單元測試矩陣必須含 R1–R4 四型。

### C.3 Carrier-calculated（CarrierService 回呼）契約

（取證 2026-08-14，admin-rest CarrierService 資源頁——GraphQL 世代回呼契約仍以此頁為權威）

**請求**（Shopify → app callbackUrl，POST JSON）：`rate.origin` 與 `rate.destination` 各含 `country`、`postal_code`、`province`、`city`、`name`、`address1/2/3`、`phone`、`fax`、`email`、`address_type`、`company_name`；`rate.items[]` 含 `name`、`sku`、`quantity`、`grams`、`price`、`vendor`、`requires_shipping`、`taxable`、`fulfillment_service`、`properties`、`product_id`、`variant_id`；外加 `rate.currency`、`rate.locale`。

**回應**：`{"rates": [...]}`，每筆必填 `service_name`、`service_code`、`total_price`、`currency`、`description`；選填 `phone_required`、`min_delivery_date`、`max_delivery_date`。**不能服務時回空陣列 rates ＋ 任一 20x**。

**🔴 金額單位（本章最重要的一條事實）**：官方逐字規則＝總價以 subunits 表達，**「若該幣別不用 subunits，值必須 ×100」——官方例：500 = 5.00 CAD，`100000` = 1000 JPY**。即 Shopify carrier 回呼的金額尺度是「**一律 ×100、不看 ISO exponent**」——與我方鐵律 3 的儲存尺度（一律 ×100 不看幣別）**同構**。這是外部證據第三次證實「單一尺度＋邊界宣告」優於「per-currency exponent」。⚠️ 但注意它與 58 §G.3「物流商 API 走十進位字串」是**不同介面**：C.3 是「平台↔費率 app」的契約（我方＝平台側，定義權在我方），58 是「我方↔外部物流商」的契約（定義權在物流商）。兩者不得合併成一個轉換函式。

**逾時（動態，依該 shop-app 對的 RPM）**：<1500 RPM＝10s；1500–3000＝5s；>3000＝3s。**無重試**——「必須第一次就在時間預算內成功」。
**快取**：成功回應快取 **15 分鐘**、錯誤 **30 秒**；cache key＝variant IDs＋箱規／重量＋數量＋carrier service ID＋origin＋destination＋品項重量。
**方案門檻**（取證 2026-08-14，help third-party-carrier-calculated-shipping）：Advanced／Plus 內建；Grow 加月費或轉年繳可加購。可接第三方帳號：UPS、FedEx、USPS、Canada Post、Australia Post（5 家）。

**加價公式**（DeliveryParticipant）：官方逐字只給**運算順序**＝百分比先算、flat fee 後加（取證 2026-08-14，help setting-up-shipping-rates）。取整方向本輪回查 help third-party-carrier-calculated-shipping 與 objects/DeliveryParticipant 兩頁，⚠️ **皆無任何 rounding 字樣——本尊的取整方向官方未明文，待實測店以會產生小數 cents 的費率（如 $10.01 × 5.5%）驗證**。金額公式屬鐵律 3 轄區不得留白，故我方裁定**先落**（integer cents 形態、全程禁 float）：

```
percentage_bp     = percentageOfRateFee × 100 之整數 basis points（設定層落地時即存整數 bp，不存 Float）
markup_cents      = floor(carrier_rate_cents × percentage_bp / 10000)    # 唯一捨入點：floor
final_price_cents = carrier_rate_cents + markup_cents + fixed_fee_cents  # 其後純整數加法，無捨入
```

- **取整方向裁定＝floor**。依據：16 §F5.1 分攤公式的既有慣例「任何有小數的情況一律 floor」——同向對齊；且 floor 只會讓展示價低半分以內，不會多收顧客。banker's／half-up 落選：專案內沒有任何既有捨入點用它們，同倉庫混用兩種方向纔是事故源。
- 🔴 本點是 16 §F5.1「只有三個捨入點」清單**之外的新捨入點（carrier markup）**，須在 65 號捨入點登錄表增列（原 openQuestion 就地升級為 decision，待 65 收錄）；若日後 parity 實測本尊方向與 floor 不符，以本尊為準修訂並回寫 65。
- `carrier_rate_cents` 必須是已過 65 §B 轉換的 `Money::Storage`；`percentageOfRateFee` 在 GraphQL 是 `Float!`，只在序列化邊界出現，內部一律整數 bp（超過兩位小數的百分比 ⇒ 設定驗證 reject，不捨入）。

### C.4 Backup rates（保底費率）

（取證 2026-08-14，help backup-rates）觸發條件＝**「該 shipment 的所有 app／carrier-calculated rates 全部失敗，且無其他可用 rate」**——只要有任何一條 flat rate 活著就不觸發。前提＝該 zone 至少有一條 app／carrier rate。兩套體系：①Shopify-powered 預設（美=USPS、加=Canada Post、英=Evri 等承運商級；其他國家用歷史資料估價，因素＝出貨地、收件地、幣別、重量、訂單額）；②legacy 自訂 backup rate（可設價格／重量條件）。**重量缺值＝以 0 計**（會導致估價失真——我方應在商品驗收清單強制重量必填，見 §F）。

### C.5 Local delivery 規則與上限

（取證 2026-08-14，help local-delivery）
- 配送區二選一：**半徑**（km/mi，**上限 160 km / 100 mi**；可勾選延伸到鄰省/州；**不跨國界**）或 **郵遞區號清單**（逗號＋空格分隔，**上限 3,000 字元**，支援 `*` 萬用；UK 支援 outward code）。
- 每 location **≤10 個 delivery zones**；每 zone 可設**最低訂單額**＋配送費（0＝免費）＋**≤3 條額外的價格條件費率**。落在多 zone 重疊區＝取**最低**可用價。
- 結帳顯示條件（全部滿足才出現）：整單實體品項可由**單一** location 供給、庫存足、地址經 Google 驗證下拉選中、地址落在區內且同省/州或同國、**加速結帳（Apple Pay／Google Pay／Amazon Pay／PayPal）不支援**（Shop Pay 支援）。**不允許同單部分寄送＋部分本地配送**。B2B 結帳不支援（除非 draft order 預選）。

### C.6 Local pickup 規則

（取證 2026-08-14，help pickup-in-store）逐 location 啟用；「expected pickup time」從下拉選 processing time（⚠️ 選項值域官方頁未窮舉，社群佐證範圍「1 小時～1 週」——**待實測店窮舉**，見 openQuestions）；結帳 Delivery 段顯示「Ship／Pick up」二選；顧客只看得到**同國** location；自取免運費（無定價欄位）。庫存不足→store transfer（就近有貨優先；可排除 collections 不可排除單品）。

### C.7 Delivery dates（transit time）

（取證 2026-08-14，help transit-time）flat rate 可掛 transit time，展示於結帳費率名下方（例「Express (1 to 2 business days)」）。預置選項（依國別變動）：Economy（5–8 營業日）、Standard（2–9）、Express（1–4）、Economy International（6–60）、Standard International（2–12）、Express International（1–7）、Custom（自填文字）。**transit time 不含 processing time**（官方明言）；預置選項才會算出日期區間，custom 只顯示文字。DeliveryPromiseProvider API（第三方送達承諾）**限白名單合作夥伴**，不對一般 app 開放（取證 2026-08-14）——我方不對接。

### C.8 上限值彙總（落 `config/limits.yml`，鐵律 6）

| key | 值 | 出處 |
|---|---|---|
| `shipping.max_custom_profiles` | 99 | help shipping-profiles |
| `fulfillment_order.max_active_holds_per_app` | 10 | mutations/fulfillmentOrderHold |
| `local_delivery.max_radius_km` / `max_radius_mi` | 160 / 100 | help local-delivery |
| `local_delivery.max_zones_per_location` | 10 | 同上 |
| `local_delivery.max_conditional_rates_per_zone` | 3 | 同上 |
| `local_delivery.max_postal_codes_chars` | 3000 | 同上 |
| `carrier_service.timeout_seconds` | 10（RPM 分級 10/5/3） | REST CarrierService |
| `carrier_service.cache_ttl_success_minutes` / `cache_ttl_error_seconds` | 15 / 30 | 同上 |
| `carrier_service.third_party_accounts` | 5 家（UPS/FedEx/USPS/Canada Post/Australia Post） | help CCS |

### C.9 併發要害與不變量

1. **品項守恆**（16-F3.2 已規格化，本輪復核仍成立）：同一 order 的全部 FO（含 cancel 替代單、split 的兩半、move 的產物）對每個 line item 的數量總和 ≡ 訂單可履約數量。split「因狀態不可拆時**改建 replacement FO**」（官方行為，取證 2026-08-14）也必須維持此恆等式。
2. **fulfilled_quantity 條件式累加**：`fulfillmentCreate` 對 FO 剩餘量的扣減必須是 `WHERE fulfilled_quantity + ? <= quantity` 的條件 UPDATE，防兩 staff 同時全量出貨。
3. **hold 多重性**：ON_HOLD 判定＝`COUNT(active holds) > 0`，不是布林欄位；釋放走 holdIds 精準匹配；每 app 計數上限 10。
4. **運費快取鍵**：C.3 的 cache key 因子清單就是我方 rate cache 的 key 設計——少一個因子（如 origin）就會把 A 倉的報價給 B 倉用。
5. **`fulfillmentCreate` 多 FO 約束**：同 order ＋ 同 location 才能併單出貨（46a/16 已規格化；本輪復核一致）。
6. **assignedLocation 快照寫入時機**：FO 離開「可改址」狀態（OPEN/SCHEDULED/ON_HOLD）時固化快照。

---

## D. 關鍵流程

### D.1 建單與路由（系統）
訂單成立 → order routing 決定各品項的履約 location → **自動**建 1..N 張 FO（不可手建）→ 每張發 `fulfillment_orders/order_routing_complete` webhook → `fulfill_at` 有值者建為 SCHEDULED，否則 OPEN。失敗分支：品項全 digital ⇒ deliveryMethod=NONE 照建 FO。

### D.2 商家自營出貨（merchant-managed location）
操作者＝staff。①（可選）split/move/hold 整備 → ②`fulfillmentCreate`（指定 lineItemsByFulfillmentOrder 的數量；不指定＝全量）＋ trackingInfo（company＋number(s)＋url(s)）＋ notifyCustomer → ③系統：建 Fulfillment(SUCCESS)、FO 累加 fulfilled_quantity（全量⇒CLOSED；部分⇒狀態不變）、庫存 committed−/on_hand−、訂單 fulfillment_status 重物化、事件＋outbox（`fulfillments/create`）→ ④transaction 外寄出貨通知信。失敗分支：數量超剩餘 ⇒ userError；ON_HOLD/SCHEDULED ⇒ 不可出貨（46a）。

### D.3 3PL 請求流（fulfillment service location）
①商家（或 OMS app）`fulfillmentOrderSubmitFulfillmentRequest`（requestStatus UNSUBMITTED→SUBMITTED；webhook `fulfillment_request_submitted`）→ ②Shopify POST `{callbackUrl}/fulfillment_order_notification` `{"kind":"FULFILLMENT_REQUEST"}` → ③3PL 回查 `assignedFulfillmentOrders(assignmentStatus: FULFILLMENT_REQUESTED)` 取單 → ④accept（→IN_PROGRESS/ACCEPTED）或 reject（→OPEN/REJECTED，reason ∈ 14 值 enum：`INCORRECT_ADDRESS`、`INCORRECT_PRODUCT_INFO`、`INELIGIBLE_PRODUCT`、`INTERNATIONAL_SHIPPING_UNAVAILABLE`、`INVALID_CONTACT_INFORMATION`、`INVALID_SKU`、`INVENTORY_OUT_OF_STOCK`、`MERCHANT_BLOCKED_OR_SUSPENDED`、`MISSING_CUSTOMS_INFO`、`ORDER_TOO_LARGE`、`OTHER`、`PACKAGE_PREFERENCE_NOT_SET`、`PAYMENT_DECLINED`、`UNDELIVERABLE_DESTINATION`；取證 2026-08-14）→ ⑤3PL `fulfillmentCreate` 出貨（可分多次）→ ⑥做不完＝`fulfillmentOrderClose`（→INCOMPLETE/CLOSED；webhook `fulfillment_service_failed_to_complete`）。
取消支流：商家 `submitCancellationRequest`（ACCEPTED→CANCELLATION_REQUESTED）→ 3PL accept（FO→CANCELLED）或 reject（FO 續作 IN_PROGRESS）。

### D.4 Hold／Release
任何有 scope 的 app／staff 可 `fulfillmentOrderHold`（reason 8 值＋reasonNotes＋handle＋可選部分品項→部分 hold 時拆出 `remainingFulfillmentOrder` 承接未 hold 品項）；webhook `placed_on_hold`。釋放 `fulfillmentOrderReleaseHold`（holdIds 精準／省略＝全放）；最後一個 hold 釋放時 FO 回 OPEN（若原為 SCHEDULED 期未到⚠️官方未明言回哪一態——我方裁定回 SCHEDULED，登記 V）；webhook `hold_released`。

### D.5 Move／Split／Merge
- Move：見 §B.1-4 前置條件；已履約品項不動；跨出 3PL 懸置請求時禁止。
- Split：`fulfillmentOrderSplit`（每筆 id＋quantity）→ 回 `fulfillmentOrderSplits[]{fulfillmentOrder(新), remainingFulfillmentOrder(原)}`；狀態不可拆時改建 replacement。
- Merge：同 order＋同 location＋同 status 的多張 FO 併一張（`fulfillmentOrdersForMerge` 給候選）。

### D.6 Local pickup（含通知）
下單（結帳選 Pick up＋location）→ FO deliveryMethod=PICK_UP → staff 備貨 → 按「Ready for pickup」⇒ **自動寄可取貨信**（含 location 的自訂取貨指示，蓋掉預設模板）→ 顧客到店 → 「Mark as picked up」（可選補寄確認信）⇒ fulfillment 完成（displayStatus=PICKED_UP）。庫存不足支流：Transfer required → 從來源 location 調撥 → 到貨後續流。

### D.7 Local delivery（含通知）
下單（結帳地址落區＋選 local delivery）→ FO deliveryMethod=LOCAL → 備貨 → 標記 Ready for delivery（=配送中；carrier 型「out for delivery/delivered」通知**不適用**）→ 送達 → 標記 Delivered ⇒ 自動寄送達信；投遞失敗＝停留 Ready for delivery 重試。

### D.8 結帳運費計算（系統）
①購物車品項按 profile×location group 分組 → ②每組選 zone（收件地命中）→ ③逐 method definition 驗 conditions（TOTAL_PRICE／TOTAL_WEIGHT 對該組小計/總重）→ ④rateProvider 取價：RateDefinition 直讀；Participant 併發打 carrier 回呼（逾時 10/5/3s、cache 15min）套加價公式 → ⑤全部 carrier/app 失敗且無其他 rate ⇒ backup rates → ⑥跨組合併（§C.2 R1–R4）→ ⑦顯示（附 transit time）。

### D.9 Tracking 事件流
出貨後：`fulfillmentTrackingInfoUpdate` 改單號（單/多包裹）；`fulfillmentEventCreate` 逐事件寫入（11 值）→ 推導 displayStatus／deliveredAt → 觸發對應顧客通知（shipping update / out for delivery / delivered）。3PL 開 tracking 支援時 Shopify 每小時拉 `fetch_tracking_numbers` 補號。

---

## E. 跨模組耦合

**發出的 webhook topics（履約域四家族共 26 支，取證 2026-08-14，enums/WebhookSubscriptionTopic）**——前稿寫「全 15 支」是**漏列**：FO 家族實有 20 支（前稿只列 13 支，漏了 split/move/merge 等 7 支——§D.5 明明寫了這三個流程，照 15 支落地它們將發不出對應事件），且漏了 fulfillment_events／fulfillment_holds 兩家族：

- **fulfillment_orders（20 支）**：`order_routing_complete`、`fulfillment_request_submitted`、`fulfillment_request_accepted`、`fulfillment_request_rejected`、`placed_on_hold`、`hold_released`、`scheduled_fulfillment_order_ready`、`rescheduled`、`cancellation_request_submitted`、`cancellation_request_accepted`、`cancellation_request_rejected`、`cancelled`、`fulfillment_service_failed_to_complete`（以上 13＝前稿已列）＋**本輪補列 7 支**：`split`、`moved`、`merged`（對應 §D.5 三流程）、`progress_reported`、`manually_reported_progress_stopped`（手動進度回報；後者即 §B.1-4 move 前置條件裡「曾 report progress 須先 mark as open」對應的回轉事件）、`line_items_prepared_for_pickup`、`line_items_prepared_for_local_delivery`（對應 §B.6/§B.7 的 ready 中繼態）。⚠️ 13 章 A.3 表頭記 fulfillment_orders「21 支」，但其實列名單與本輪兩次獨立點算 enum 頁的結果是**同一份 20 支**——「21」疑為計數誤植，最終數以 introspection 實測為準（13 章表頭待同步修正）。
- **fulfillments（2 支）**：`fulfillments/create`、`fulfillments/update`。
- **fulfillment_events（2 支）**：`fulfillment_events/create`、`fulfillment_events/delete`——§D.9 事件流寫入的對外出口。
- **fulfillment_holds（2 支）**：`fulfillment_holds/added`、`fulfillment_holds/released`。⚠️ 與 FO 家族的 `placed_on_hold`／`hold_released` **粒度不同**：enum 描述字面＝holds 家族是 per-hold（"each time that a hold is added/released"），FO 家族是狀態轉移（"transitions to ON_HOLD"／"no longer on hold"）——推論：疊加 hold（§B.1-3）時第二個 hold 只觸發 `fulfillment_holds/added` 不再觸發 `placed_on_hold`；此為描述字面推導，精確觸發次數官方未明文，待實測。

我方 outbox 事件面照此 **26 支**對齊（命名照 topic）；驗收斷言＝§D.5 的 split/move/merge 各自發得出 `split`／`moved`／`merged`。

**依賴方向**：
- **← Orders（16）**：FO 由訂單建立；fulfillment_status 物化回訂單；order edit 增刪品項會動 FO line items。
- **← Inventory（13）**：出貨扣 committed/on_hand；move 前置「目的地備貨」查 inventory item 的 stocked 狀態；pickup 的 store transfer。
- **← Payments**：hold reason `AWAITING_PAYMENT`；3PL 拒單 reason `PAYMENT_DECLINED`。
- **← Returns（46a §4/5）**：換貨 hold `AWAITING_RETURN_ITEMS`；逆向履約 ReverseFulfillmentOrder 獨立成域不混入本章。
- **→ Notifications**：出貨信、ready for pickup、picked up、delivered、shipping update——各有觸發點（§D），local delivery 不觸發 carrier 型通知。
- **→ Storefront/Liquid**：order status page 的 tracking 顯示；packing slip 模板（Liquid 渲染，變數群＝shop/shop_address/order/customer/shipping_address/billing_address/`line_items_in_shipment`（含 `shipping_quantity`、`includes_all_line_items_in_order` 部分出貨旗標）；⚠️ 官方 packing slip 變數表**無價格/重量/配送方式**欄——但預設模板含價格，變數表疑不全，待實測；模板入口＝Settings→Shipping 的 Documents 段，可 Revert to default）。
- **→ carrier pack（58）**：C.3 的回呼契約是我方「rate provider 介面」的形狀參考；面單/取號走 58 §D，不在本章。
- **→ jurisdiction pack（鐵律 11）**：取貨網路（超商取貨＝`PICKUP_POINT` 的法域實作）、地址格式、Google 地址驗證的可用性。

---

## F. 落地對應

**對應倉庫檔**：`docs/research/46a` §2/§3（FO/Fulfillment 狀態機字典）｜`docs/specs/16` F3（履約規格）｜`docs/specs/58`（carrier pack）｜`docs/specs/13`（庫存）｜`docs/research/28`（API 契約）｜`config/limits.yml`（§C.8 新 key）。

**本尊 vs 我方裁定差異表**：

| # | 本尊原貌 | 我方裁定 | 依據 |
|---|---|---|---|
| D1 | 金額對外＝MoneyV2 十進位字串；carrier 回呼＝subunits 一律 ×100 | 內部一律 integer cents（×100 不看幣別）；序列化層才轉 MoneyV2。**carrier 回呼的 ×100 規則與我方儲存尺度同構，可直通，但仍須走 `Money::Storage` 型別、禁裸 Integer** | 鐵律 3／65 |
| D2 | 超商取貨、pickup point 網路＝內建（按市場） | `PICKUP_POINT` 核心只留 enum 與介面，取貨網路落 jurisdiction pack（TW 素材降級進 `jurisdiction/tw`） | 鐵律 11 |
| D3 | 第三方 CCS 綁方案（Advanced/Plus/Grow 加費） | 方案分層我方自訂；**不複製** Shopify 的計費門檻，但 feature flag 介面照建 | 商務裁定待定 ⚠️ |
| D4 | Shopify Shipping（平台代購面單）＋ Shop Promise（平台擔保送達） | **不做**——面單走 58 號 carrier pack（順豐第一實作）；delivery promise 只做 transit time 顯示層 | 58／本章 C.7 |
| D5 | 泛用 UserError 無 code | 我方全 mutation typed code enum（刻意加嚴） | 鐵律 4 |
| D6 | tracking company 清單=Shopify 維護的百餘承運商 | 清單做成 seed 資料表（per-carrier URL 模板），SF Express 在官方清單內；未知 company 允許自填 url（http(s) 白名單） | 16-F3；本章 A.1 |
| D7 | **2025-01 起 hold 可疊加、上限「每 app 10 個 active holds」** | 16-F3 T5 寫的是「active hold 數 < 10」全域計數且 guard 限 OPEN/SCHEDULED——**需修**：計數按 app 維度、已 ON_HOLD 仍可再 hold | 本章 B.1-3（取證 2026-08-14） |
| D8 | **`fulfillmentOrderMove.remainingFulfillmentOrder` 已 deprecated**，返回語義改為 moved/original 二元 | 16-F3 T14 仍列三返回值——**需修**：對齊新語義，部分移動的「剩餘」由 originalFulfillmentOrder 承載 | 本章 B.1-4（取證 2026-08-14） |
| D9 | 費率合併規則 R1–R4 不可關閉 | 照抄本尊（1:1 對齊），四型全進測試矩陣 | 本章 C.2 |
| D10 | backup rates 有 Shopify-powered 智慧估價 | 我方只做 legacy 型（自訂條件 backup rate）；估價型無資料基礎，宣告 `supported: false` | 本章 C.4 |

**開發驗收要點**：
1. FO 狀態機測試覆蓋 T1–T16＋本章 D7/D8 修正；無孤兒狀態斷言（每個非終態至少一條出邊）。
2. 品項守恆 nightly 對帳（§C.9-1）＋ split-in-bad-state 改建 replacement 的行為測試。
3. 運費引擎：R1–R4 合併四型 × 條件邊界（min=max、Maximum 留空、重量 0）× zero-decimal 幣別（JPY/TWD/KRW 進矩陣，鐵律 3）。R2 斷言值＝官方例 $3＋$2＝$5（§C.2 勘誤後可斷言）；R1/R2 混合邊界（部分同名）標 pending 待實測，測試先寫 skip 註明。
4. carrier 回呼：逾時 10s 斷路→backup rate 兜底；cache key 全因子；空 rates+200 ＝「無服務」不是錯誤。markup 公式測 floor 方向（§C.3 裁定）：`carrier_rate_cents=1001, 5.5% ⇒ markup=55`（55.055 floor）＋ zero-decimal 幣別入矩陣。
5. local delivery/pickup：C.5/C.6 上限全落 limits.yml 並引用；通知觸發點照 §D.6/D.7（Delivered 不標記＝不寄信）。
6. 併發測試：同 FO 雙 staff 全量出貨只成一單；hold 疊加至 per-app 上限第 11 個回 userError。
7. outbox 事件面覆蓋履約域全 26 支 topic（§E 清單，四家族）；split/move/merge 流程測試各斷言發出 `split`／`moved`／`merged`；疊加 hold 情境斷言 `fulfillment_holds/added` 與 `placed_on_hold` 的觸發次數（粒度差異見 §E，實測前先照描述字面落）。

---

## G. 來源（全部取證 2026-08-14）

| 主題 | URL |
|---|---|
| FulfillmentOrder 物件 | https://shopify.dev/docs/api/admin-graphql/latest/objects/FulfillmentOrder |
| Fulfillment 物件 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Fulfillment |
| FulfillmentOrderAssignedLocation | https://shopify.dev/docs/api/admin-graphql/latest/objects/FulfillmentOrderAssignedLocation |
| FulfillmentHold | https://shopify.dev/docs/api/admin-graphql/latest/objects/FulfillmentHold |
| FulfillmentTrackingInfo（承運商清單） | https://shopify.dev/docs/api/admin-graphql/latest/objects/FulfillmentTrackingInfo |
| FulfillmentDisplayStatus enum | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentDisplayStatus |
| FulfillmentEventStatus enum | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentEventStatus |
| FulfillmentOrderRejectionReason enum | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentOrderRejectionReason |
| WebhookSubscriptionTopic enum（§E 四家族 26 支窮舉） | https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic |
| DeliveryMethodType enum | https://shopify.dev/docs/api/admin-graphql/latest/enums/DeliveryMethodType |
| DeliveryConditionField / Operator enums | https://shopify.dev/docs/api/admin-graphql/latest/enums/DeliveryConditionField ／ .../DeliveryConditionOperator |
| fulfillmentOrderHold / ReleaseHold / Move / Split | https://shopify.dev/docs/api/admin-graphql/latest/mutations/fulfillmentOrderHold ／ fulfillmentOrderReleaseHold ／ fulfillmentOrderMove ／ fulfillmentOrderSplit |
| fulfillmentCreate / fulfillmentEventCreate / fulfillmentTrackingInfoUpdate | https://shopify.dev/docs/api/admin-graphql/latest/mutations/fulfillmentCreate ／ fulfillmentEventCreate ／ fulfillmentTrackingInfoUpdate |
| 3PL 建置指南（request/accept/reject＋callback＋webhooks） | https://shopify.dev/docs/apps/build/orders-fulfillment/fulfillment-service-apps/build-for-fulfillment-services |
| FO 遷移緣由 | https://shopify.dev/docs/apps/build/orders-fulfillment/migrate-to-fulfillment-orders ；https://www.shopify.com/partners/blog/fulfillment-orders-api-migration |
| DeliveryProfile / MethodDefinition / Participant | https://shopify.dev/docs/api/admin-graphql/latest/objects/DeliveryProfile ／ DeliveryMethodDefinition ／ DeliveryParticipant |
| CarrierService 回呼契約（單位/逾時/快取） | https://shopify.dev/docs/api/admin-rest/latest/resources/carrierservice |
| Shipping profiles（99 上限） | https://help.shopify.com/en/manual/fulfillment/setup/shipping-profiles |
| 費率設定（條件/免運/加價順序） | https://help.shopify.com/en/manual/fulfillment/setup/shipping-rates/setting-up-shipping-rates |
| 費率合併規則 | https://help.shopify.com/en/manual/fulfillment/setup/shipping-profiles/combined-shipping-rates |
| 第三方 CCS（方案/5 家承運商） | https://help.shopify.com/en/manual/fulfillment/setup/shipping-rates/third-party-carrier-calculated-shipping |
| Backup rates | https://help.shopify.com/en/manual/fulfillment/setup/shipping-rates/backup-rates |
| Transit time | https://help.shopify.com/en/manual/fulfillment/setup/shipping-rates/transit-time |
| Local delivery（半徑/郵遞區號/上限） | https://help.shopify.com/en/manual/fulfillment/setup/delivery-methods/local-delivery |
| Local delivery 履約流 | https://help.shopify.com/en/manual/fulfillment/fulfilling-orders/local-delivery-fulfillment |
| Local pickup | https://help.shopify.com/en/manual/fulfillment/setup/delivery-methods/pickup-in-store |
| Packing slip 列印/模板/變數 | https://help.shopify.com/en/manual/fulfillment/managing-orders/printing-orders/packing-slips/printing-packing-slips ／ .../variable-reference |
| DeliveryPromiseProvider（白名單限定） | https://shopify.dev/docs/api/admin-graphql/latest/objects/deliverypromiseprovider |
