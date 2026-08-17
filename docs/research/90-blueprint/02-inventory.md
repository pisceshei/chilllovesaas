# 02. 庫存（InventoryItem / InventoryLevel / Location / Transfers）

> 目的：對齊 Shopify 2026 春季版庫存領域的**官方文檔考掘**（shopify.dev Admin GraphQL 參考頁＋help.shopify.com），
> 產出可直接落地開發的業務邏輯。全部規則性斷言附來源（G 節，取證 2026-08-14）。
> 與倉庫既有裁定的關係：本文以「本尊原貌」為主體，凡與我方裁定（`docs/specs/13` F5、`docs/research/77`）不同處在 F 節逐條列差異；本文不推翻任何既有裁定。
> 來源代號 S1–S29 見 G 節；引句一律 ≤15 字。

---

## A. 領域物件模型

### A.1 物件總表與 cardinality

| 物件 | 是什麼 | 關係（cardinality） | 來源 |
|---|---|---|---|
| `ProductVariant` | 售賣單位（價格/選項） | 1:1 `inventoryItem`（`InventoryItem!` non-null）（S24） | S24 |
| `InventoryItem` | 變體的「庫存實體」：tracked、sku、unitCost、關務資料 | 1:N `InventoryLevel`（每個有庫存的 location 一筆） | S3 |
| `InventoryLevel` | InventoryItem × Location 的量化狀態集合 | N:1 `item`、N:1 `location`；唯一鍵＝`(shop_id, inventory_item_id, location_id)`（鐵律 2：業務資料複合索引以 shop_id 開頭（2026-08-17 更正，PR #52 第 11 輪）：原寫 (item, location)） | S4 |
| `Location` | 實體或邏輯地點（含 fulfillment app 地點） | 1:N `InventoryLevel`；每 shop 有一個 default location | S13, S22 |
| `InventoryAdjustmentGroup` | 一次 mutation 產生的調整批（ledger 群組） | 1:N changes（name/delta/quantityAfterChange） | S16 |
| `InventoryScheduledChange` | 排程狀態轉換（預告，不動數字） | 掛在 `InventoryLevel` 下；欄位 expectedAt/fromName/toName/quantity/ledgerDocumentUri | S5 |
| `InventoryTransfer` | 地點間（或對外部）移動庫存的單據 | 1:N `lineItems`、1:N `shipments`、origin/destination＝`LocationSnapshot`（快照＋可選連到活 Location） | S6 |
| `InventoryShipment` | 轉移下的一批出貨（獨立編號如 `T289-1`、獨立追蹤與狀態） | N:1 transfer | S8, S10 |
| `PurchaseOrder`（admin 功能，非公開 GraphQL 物件） | 對供應商的商業約定 | 可連結 InventoryTransfer 記錄實際收貨 | S11, S29 |

### A.2 InventoryItem 與 Variant 分離的理由

- **關注點分離**：變體承載售賣屬性（price/options/position），InventoryItem 承載庫存與物流屬性——`tracked`、`sku`、`unitCost`、`requiresShipping`、`countryCodeOfOrigin`、`harmonizedSystemCode`（6–13 位）、`provinceCodeOfOrigin`、`measurement`（包裝尺寸）、`countryHarmonizedSystemCodes`（分國 HS code，分頁 connection）（S3，取證 2026-08-14）。
- **多地點展開**：數量不在 item 上，而在 item×location 的 `InventoryLevel`；`inventoryLevel(locationId:)` 取單點、`inventoryLevels` 分頁取全部（S3）。
- **SKU 不強制唯一**：`duplicateSkuCount: Int!` 表示同 SKU 的 item 數（S3）——⚠️ 官方允許重複 SKU，我方驗證不得把 SKU 設 unique index。
- **`trackedEditable: EditableProperty!`**：tracked 開關可能被鎖（如由 fulfillment service 管理時），UI 需照 `canEdit/reason` 呈現（S3）。
- **bundle 父項不可調**：error code `NON_MUTABLE_INVENTORY_ITEM`＝「不允許經 API 調整，例：parent bundle」（S19）。

### A.3 InventoryLevel 關鍵欄位

| 欄位 | 型別 | 語義 |
|---|---|---|
| `quantities(names:[String!]!)` | `[InventoryQuantity!]!` | 按狀態名取量；合法名＝8 態（B.1） | 
| `scheduledChanges` | connection（**deprecated**） | 排程轉換清單，可按 id/expected_at/quantity_names 篩選 |
| `canDeactivate` | `Boolean!` | 該 item×location 可否解除連結（deactivate stocking） |
| `deactivationAlert` | `String` | 不能解除時的原因文案（如仍有量/在途） |
| `isActive` | `Boolean!` | 連結是否生效 |
| `item` / `location` | non-null | 所屬 | 

（S4，取證 2026-08-14）

### A.4 Location 關鍵欄位與上限

- 能力欄位（S22）：`isActive`、`fulfillsOnlineOrders`（可否履行線上訂單）、`hasActiveInventory`、`hasUnfulfilledOrders`、`isFulfillmentService`＋`fulfillmentService`、`shipsInventory`（legacy：「有有效地址即可出貨」）、`deactivatable`/`activatable`/`deletable`、`deactivatedAt`、`localPickupSettingsV2`。
- **各方案 active location 上限**（S13，取證 2026-08-14）：

| 方案 | 上限 |
|---|---|
| Starter | 2 |
| Basic | 10 |
| Grow | 10 |
| Advanced | 10 |
| Shopify Plus | 200 |

- 停用地點**不計入上限**；fulfillment app 地點（dropshipping/3PL/自訂履約服務）視為 location 但**不計入上限**（S13）。
- default location 不可直接停用，須先換 default（S13）。

### A.5 Transfer / Shipment / PO 欄位

- `InventoryTransfer`：`name`（單號）、`status`、`origin`/`destination`（LocationSnapshot 快照——**收單時地址凍結**）、`totalQuantity`、`receivedQuantity`（＝accepted＋rejected＋canceled 合計）、`referenceName`、`note`、`tags`、`lineItems`、`shipments`、`events`、`metafields`、`dateCreated`（S6）。
- 建立式欄位（實測補充見 77 §3）：日期、參考名稱、備註、標籤、**連結採購單**。
- PO 建立式欄位：供應商（可新建）、目的地、商品（手動/CSV/條碼）、每列 quantity/Supplier SKU/cost/tax（自動帶入歷史成本，可改）、參考編號、給供應商備註、付款條件、供應商幣別、標籤、成本摘要（S11）。⚠️ 參考編號 ≤255／備註 ≤5000 出自我方實測（77 §2），本次 help 頁未載明數字。

---

## B. 狀態機

### B.1 量化狀態（單位級，8 態全集）

官方 8 個量化狀態（S1，取證 2026-08-14）。🔴 **非八者互斥**：`on_hand` 是**聚合投影**
（＝available＋committed＋reserved＋damaged＋safety_stock＋quality_control 六個組成 bucket 之和，
互斥性只適用於這六個 bucket）；`incoming` 獨立於 on_hand 之外。照「八態互斥」建模會做成單一
enum 或把 on_hand 重複計數，與四聚合欄＋buckets 子表的 schema 要求直接矛盾。
<!-- 2026-08-17 更正（PR #52 Codex 第 2 輪）：原句「官方 8 個互斥狀態」語義錯誤。 -->

| 名稱 | 定義（改寫） | API 可寫性 |
|---|---|---|
| `incoming` | 在途（transfer/app 正送往地點）；**不計入 on_hand** | 唯讀（僅 transfer/PO/app 流程改動）（S2） |
| `on_hand` | 實體在店數量＝下列六態之和 | 可 set（inventorySetQuantities / inventorySetOnHandQuantities）（S2） |
| `available` | 可售；不含 committed 與任何保留 | 可 adjust/set/move（S2） |
| `committed` | 已成立未履行訂單占用 | **唯讀**：「只受訂單成立與履行影響」（S1/S2） |
| `reserved` | 暫時擱置的在店單位（draft/app 保留落點） | 可 adjust/move（S2） |
| `damaged` | 損壞不可售 | 可 adjust/move（S2） |
| `safety_stock` | 防超賣的安全庫存 | 可 adjust/move（S2） |
| `quality_control` | 品檢中不可售 | 可 adjust/move（S2） |

**單位狀態轉移表**（觸發動作／前置條件／副作用）：

| 轉移 | 觸發 | 前置條件 | 副作用 |
|---|---|---|---|
| `available → committed` | 訂單成立（含 draft 轉正式單） | tracked=true；DENY 時 available>0 | committed＋、available－；on_hand 不變（S12） |
| `committed → (出帳)` | fulfillment 建立 | 訂單已指派地點 | committed－、on_hand－（S12；46a） |
| `committed → available` | 訂單取消（`orderCancel.restock=true`）／未履行品項退款 `restockType=CANCEL`（06 §A.4） | `orderCancel.restock` 必填（46a）；新建退款**無** `RESTOCK` 值（S31） | 回補 available；on_hand 不變 |
| `committed 跨地點遷移` | `fulfillmentOrderMove`（FO 改派地點，09 §B.1-4） | 目的地必須備貨該 item（官方明文 move 失敗條件，S32）；已履約品項永遠留在原地點（S32） | origin committed−、destination committed＋；⚠️ 官方只寫前置與失敗條件，**未寫數量機制**——origin 是否同步 available＋、destination 是否 available− 為推定（committed 守恆＋C.1 恆等式反推），待實測 |
| `available ⇄ reserved/damaged/safety_stock/quality_control` | `inventoryMoveQuantities`（同一 location 內） | from/to 同 location；非 available 端須 `ledgerDocumentUri` | 兩態各±，on_hand 不變（S18） |
| `unavailable 子態互轉` | move（from/to 皆非 available 亦允許） | 合法 name 對＝{available, reserved, damaged, safety_stock, quality_control}（S2） | 同上 |
| `(外) → incoming` | transfer shipment 標記 In transit（S10）；app/PO 在途 | 有 destination | destination incoming＋ |
| `incoming → available` | 收貨 accept／「收到後**自動變 Available**」（S12） | shipment In transit | incoming－、available＋、on_hand＋ |
| `reserved → (外)`（origin 出帳） | transfer shipment 標記 IN_TRANSIT | shipment 含該品項且 transfer **已保留（READY_TO_SHIP 段）** | origin reserved−、on_hand−；同一動作 destination incoming＋（**destination 留空（外部目的地）＝無 incoming 記帳**，鏡像外部 origin 分支 2026-08-17 更正（PR #52 第 6 輪））——**扣減時點＝IN_TRANSIT，我方裁定**，論證見 B.2 裁定一；**DRAFT 直轉**（未經保留段）＝origin `available −`／`on_hand −`（reserved 從未加過，扣它會下溢 <!-- 2026-08-17 更正（PR #52 第 5 輪） -->）；origin 留空（外部供應商）＝無 origin 出帳；⚠️ 官方未逐字明文，列 parity 實測 |
| `available ⇄ (刪)` | adjust delta / set 絕對值 | reason 合法 | 寫入 adjustment history |

孤兒檢查：8 態皆有進出路徑；`incoming`／`committed` 僅系統流程可進出（API 不可直調，S1/S2）。

### B.2 InventoryTransfer 狀態機

狀態全集（`InventoryTransferStatus`，6 值，S7，取證 2026-08-14）：`DRAFT`／`READY_TO_SHIP`／`IN_PROGRESS`／`TRANSFERRED`／`CANCELED`／`OTHER`（前向相容佔位）。

| 轉移 | 觸發動作 | 前置條件 | 副作用（庫存） |
|---|---|---|---|
| （建立）→ DRAFT | Create transfer＋Save（`inventoryTransferCreate`） | 商品＋Move 數量；origin/destination **可留空**（外部供應商/外部目的地）（S9） | 「draft 轉移的庫存**不保留**」（S9） |
| DRAFT → READY_TO_SHIP | Mark as ready to ship（`inventoryTransferMarkAsReadyToShip`） | 有 origin | **origin 保留庫存**（reserved）（S9） |
| DRAFT/READY_TO_SHIP → IN_PROGRESS | Move to in transit（自動建/啟用 shipment） | — | destination 記 **incoming**（**留空/外部目的地＝不記** 2026-08-17 更正（PR #52 第 6 輪）），可開始收貨（S9/S10）；origin 出帳**分支**：自 READY_TO_SHIP＝`reserved−`／`on_hand−`；**自 DRAFT 直轉＝`available−`／`on_hand−`**（未經保留段；origin 留空＝無出帳）（裁定一＋2026-08-17 更正（PR #52 第 5 輪）） |
| IN_PROGRESS → TRANSFERRED | 全部品項收完（accept/reject/cancel 合計＝total） | 所有 shipment 收畢 | 「自動收貨並在目的地變可售」（Mark as transferred 直達）（S9/S10） |
| DRAFT/READY_TO_SHIP → CANCELED | Cancel | **僅 Draft 或 Ready to ship 可取消**（S9） | 「保留品項在 origin 恢復可售」（S9） |
| DRAFT →（刪除） | Delete | **僅 Draft 可刪**（S9） | 無庫存影響 |

**裁定一（origin 扣減時點，2026-08-14 本章裁定，補 B.1 的 openQuestion）**：官方只寫 Ready to ship「origin 保留庫存」與收貨端效果，**從未明文 origin 何時出帳**。我方裁定：**shipment 標記 `IN_TRANSIT` 的同一 transaction 內，origin `reserved`−、`on_hand`−，destination `incoming`＋**（差額全整數，無 rounding——庫存無小數）。論證（皆由官方句反推）：
1. on_hand 定義＝該地點實際持有的全部單位（S12）——在途單位實體已不在 origin，繼續掛帳違反定義；
2. 收貨 reject＝「不改任何地點數量」（S10）——若 origin 仍持帳，reject 後 origin 帳上永久多出不存在的量；此句唯有 in-transit 已出帳才自洽；且該句僅對 on_hand／available 成立，**destination `incoming` 必須 −q**（見 B.3 收貨動作列 2026-08-17 更正）<!-- 2026-08-17 二次更正：原註記誤指「D 節轉移表」，被更正的收貨動作列在 B.3 -->；
3. 收貨階段 cancel＝「退回 origin 並恢復可售」（S10）——「退回（returned to）」語義預設已離帳，否則只需解除保留、無所謂退回。

⚠️ 官方未逐字明文，本裁定列 parity 輪實測驗證項；若實測證偽（扣減在收貨時點），須同步改下方期望值表與 F.3-1。

**恆等式全流程期望值（F.3-1 的測試基準；移 10 件，origin 初始 on_hand=50 全 available，destination 初始 0）**：

| 階段 | origin available/reserved/on_hand | destination incoming/available/on_hand |
|---|---|---|
| DRAFT（不保留，S9） | 50 / 0 / 50 | 0 / 0 / 0 |
| READY_TO_SHIP（origin 保留，S9） | 40 / 10 / 50 | 0 / 0 / 0 |
| IN_TRANSIT（裁定一） | 40 / 0 / 40 | 10 / 0 / 0 |
| 收貨 accept 7／reject 2／cancel 1 | 41 / 0 / 41 | 0 / 7 / 7 |

（cancel 1 件回 origin available **並沖回 destination `incoming −1`**（S10＋B.3 更正）；reject 2 件記入 transfer 的 `receivedQuantity` 並**沖回 destination `incoming −2`**、兩地點 **on_hand／available** 不記帳，實體損耗靠對帳吸收（C.9-3）。每一列每一地點皆須滿足 `on_hand = available + committed + Σunavailable`；incoming 永不入 on_hand。）

編輯限制：Draft 全可改；已處理（processed）後 **origin/destination 不可改**（S9）。Duplicate 任何狀態（含 Canceled）可複製成新 Draft（S9）。
相關 mutations：`inventoryTransferCreate` / `inventoryTransferSetItems` / `inventoryTransferRemoveItems` / `inventoryTransferEdit` / `inventoryTransferMarkAsReadyToShip` / `inventoryTransferCancel`（S6）。

### B.3 InventoryShipment 狀態機

狀態全集（`InventoryShipmentStatus`，5 值，S8）：`DRAFT`／`IN_TRANSIT`／`PARTIALLY_RECEIVED`／`RECEIVED`／`OTHER`。

| 轉移 | 觸發 | 副作用 |
|---|---|---|
| DRAFT → IN_TRANSIT | 標記在途（可附 tracking） | destination `incoming`＋（**留空/外部目的地＝不記**，同 B.2 轉移列分支 2026-08-17 更正（PR #52 第 7 輪））（S10） |
| IN_TRANSIT → PARTIALLY_RECEIVED | 收部分品項 | accepted：destination available＋；transfer 維持 In progress 直到收完（S10） |
| PARTIALLY_RECEIVED → RECEIVED | 剩餘品項全收 | transfer 檢查是否可轉 TRANSFERRED |
| （收貨動作三選）accept / reject / cancel | 逐列數量 | accept＝「目的地變可售」（`incoming −q`／`on_hand +q`／`available +q`）；reject＝記錄在轉移上＋**destination `incoming` −q**（出貨時已加入 incoming，拒收必須沖回，否則該量在 TRANSFERRED 後永久滯留在途；S10 原文「不改任何地點數量」僅對 **on_hand／available** 成立） <!-- 2026-08-17 更正（PR #52 Codex 第 2 輪）：照 S10 字面實作與本章 F.3-1 例證表（incoming 10→0）矛盾 -->；cancel＝退回 origin 並恢復可售（origin `on_hand +q`／`available +q`）＋**destination `incoming` −q**（收貨階段 cancel 的該件已在途、已入 incoming——F.3-1 例證表 incoming 10→0 需 accept 7＋reject 2＋cancel 1 三者各自沖回才成立；「未出貨品項」語境僅適用出貨前取消，該情境 incoming 尚未加、無需沖回） <!-- 2026-08-17 更正（PR #52 第 4 輪）：原僅寫「退回 origin」，cancel 分支漏 incoming 沖回，且「未出貨品項」標籤與收貨階段例證相抵 --> |

- transfer 建立時**自動附一張 shipment**；Ready to ship／In progress 下可 More actions → Add products 開第二批（S10）。
- 收錯可用 Manage received items 事後修改 accepted/rejected/canceled 數量（S10）。
- 事件面：本狀態機每個轉移都有對應 `INVENTORY_SHIPMENTS_*` topic（E 節表；如 DRAFT→IN_TRANSIT ⇒ `_MARK_IN_TRANSIT`、收貨 ⇒ `_RECEIVE_ITEMS`）（S23）。

### B.4 PurchaseOrder 狀態機

主狀態全集（**僅 2 態**，S11/S29，取證 2026-08-14）＋**一個正交封存旗標**：

| 狀態 | 語義 | 允許操作 |
|---|---|---|
| `Draft` | 建立/審核中 | 全欄可編；**可刪除** |
| `Ordered` | 已向供應商送出 | 可編**不可刪**——「Ordered 後需改用封存」（S11）；可**建立連結的 inventory transfer** 追蹤收貨 |

- **封存（archive）不是第 3 態，是正交旗標**：官方明文可 **Unarchive** 還原（S11，取證 2026-08-14）⇒ 我方建模 `status ∈ {draft, ordered}` ＋ `archived_at: datetime NULL`，**勿用 3 值 enum**——單向 enum 做不出 archive⇄unarchive 雙向轉移，也蓋不住「Draft 也可封存嗎」這一維（⚠️ Draft 可否封存官方未明文，待實測；我方暫僅允許 Ordered 封存）。
- **「open PO」判定式**（地點停用互鎖 `HAS_OPEN_PURCHASE_ORDERS_ERROR`＝「有 open purchase orders 不可停用」，S21）：官方**未定義 open**。⚠️ 我方裁定 `open ≙ status = ordered AND archived_at IS NULL`——Draft 不擋（尚無供應商承諾、無 incoming 效果）、已封存不擋（封存語義＝結案）；官方未明文，待實測。
- 「PO 記商業約定，連結的 transfer 記實際移動」（S11）——收貨、部分收貨、完成、關閉**全部在 transfer 側追蹤**（S29）。
- 列表預設檢視：All / Draft / Ordered（S29）。
- ⚠️ 77 §2 實測「標記已訂購後目的地記 Incoming」：與新模型「incoming 由 transfer shipment 產生」需再驗證是否為同一機制（openQuestion）。

### B.5 Location 與 InventoryLevel 連結

- Location：`active ⇄ deactivated`。停用：`locationDeactivate(locationId, destinationLocationId?)`——會把「庫存、待處理訂單、移動中轉移」搬到 destination；有 active inventory 而未給 destination ⇒ `HAS_ACTIVE_INVENTORY_ERROR`；有未結 PO ⇒ `HAS_OPEN_PURCHASE_ORDERS_ERROR`（S21；「open」判定式見 B.4）。停用不影響該點庫存數字，仍可：看數量／轉移進出／調整／退貨入庫（S13）。重啟用 `locationActivate` 後重新計入上限（S13）。
- InventoryLevel 連結（stocking）：啟停用走 `inventoryBulkToggleActivation`（S3）；可否解除看 `canDeactivate`＋`deactivationAlert`（S4）。對應 webhook：`INVENTORY_LEVELS_CONNECT`／`DISCONNECT`（S23）。

---

## C. 業務規則與不變量

### C.1 恆等式（全整數，無 rounding——庫存不存在小數）

```
API 層：  on_hand = available + committed + reserved + damaged + safety_stock + quality_control   （S1）
Admin 層：On hand = Available + Committed + Unavailable                                            （S12）
橋接：    Unavailable = reserved + damaged + safety_stock + quality_control（由上兩式導出）
反解：    Available = On hand − Committed − Unavailable
排除項：  incoming 不計入 on_hand；收貨後自動轉 Available（S12）
```

- 訂單成立：available−、committed+（on_hand 不變）；履行：committed−、on_hand−（S12）——兩式皆**僅 tracked 行**（untracked/digital 無 InventoryLevel，B.1 全域限定同源（2026-08-17 更正，PR #52 第 11 輪））。
- **草稿單保留＝Unavailable 不是 Committed**：「放入 **Unavailable** 狀態」、不保留則「留在 **Available**」（S25）；「draft 轉正式單前不算 committed」（S12）。
- ⚠️ 草稿保留在 API 8 態的落點推定為 `reserved`（reason 值 `reservation_*` 支持此推定），官方未逐字寫明。

### C.2 數值邊界（全部落 `config/limits.yml`）

| 界限 | 值 | 來源 |
|---|---|---|
| adjust delta 上下界 | ±2,000,000,000（`INVALID_QUANTITY_TOO_HIGH/TOO_LOW`） | S19 |
| set 絕對值總量上下界 | ±1,000,000,000；另有 `INVALID_QUANTITY_NEGATIVE`「數量不可為負」 | S20 |
| location 上限 | 依方案 2/10/10/10/200（A.4） | S13 |
| 調整歷史保留 | **180 天**（2024-11-08 由 90 天加倍；更早走報表） | S26/S27 |
| 同批 (inventoryItemId, locationId) 不可重複 | `NO_DUPLICATE_INVENTORY_ITEM_ID_GROUP_ID_PAIR` | S20 |
| 單次 mutation changes 數上限 | ⚠️ 未查到明文（受 GraphQL cost 間接約束） | — |

⚠️ `INVALID_QUANTITY_NEGATIVE` 與 TOO_LOW −1e9 並存：負值何時合法（超賣後 set available 為負？）官方未明文，進 openQuestions。

### C.3 Ledger（帳）規則

- 每次 adjust/set/move 產生 `InventoryAdjustmentGroup`：`createdAt`、`reason`、`referenceDocumentUri`、`changes[{name, delta, quantityAfterChange}]`（S16）。
- `referenceDocumentUri`＝「為什麼變動」的自由 URI；偏好 GID 格式 `gid://[namespace]/[entity]/[id]`，也收一般 URL 與自訂 id；會顯示在調整歷史與分析報表（S2）。
- `ledgerDocumentUri`（掛在 change/from/to 上）三鐵則（S19）：
  1. **調 `available` 不得帶**（`INVALID_AVAILABLE_DOCUMENT`）；
  2. **調非 available 必須帶**（`INVALID_QUANTITY_DOCUMENT`「except when adjusting available」）；
  3. 同批**只能一份** ledger URI（`MAX_ONE_LEDGER_DOCUMENT`）、**禁用 `gid://shopify/` 內部文件**（`INTERNAL_LEDGER_DOCUMENT`）。
- 語義：非 available 的量是「掛在某文件上的保留」，ledger 是它的 append-only 憑證——與我方 13-F5「一切變動走 `Inventory::Adjust`＋ledger 同 transaction」同構。

### C.4 併發要害：CAS ＋ 冪等（雙保險）

- **CAS**：`compareQuantity`／`changeFromQuantity` 帶「期望的當前值」，不符 ⇒ `COMPARE_QUANTITY_STALE`／`CHANGE_FROM_QUANTITY_STALE`；`inventorySetQuantities` **強制**逐筆帶 compareQuantity，除非 `ignoreCompareQuantity: true`（否則 `COMPARE_QUANTITY_REQUIRED`）；跳過檢查「可能導致數量不準」（S2/S17/S20）。
- **冪等**：2026-04 起 `@idempotent(key:)` **硬性必帶**（inventoryAdjust/Set/Move/SetOnHand、locationActivate/Deactivate、transfer/shipment 系列共 17 支，46a §9）；錯誤三態：`IDEMPOTENCY_CONCURRENT_REQUEST`（進行中重試）、`IDEMPOTENCY_KEY_PARAMETER_MISMATCH`（同 key 不同參數）、`IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED`（前次失敗須換 key）（S19/S20）。
- 完整 error code 值域：AdjustQuantities 20 值（S19）、SetQuantities 17 值（S20）——含 `ITEM_NOT_STOCKED_AT_LOCATION`、`INVALID_REASON`、`INVALID_QUANTITY_NAME`、`SERVICE_UNAVAILABLE`、`ADJUST_QUANTITIES_FAILED` 等，實作照抄全集。

### C.5 唯讀狀態

- `committed`：「不能用 Admin API 調整或移動」（S1）。⚠️ 官方句「只受訂單成立與履行影響」是「API 不可直調」的說明，**不是變動路徑的窮舉**——取消/退款回補（46a）與 `fulfillmentOrderMove` 改派（B.1「committed 跨地點遷移」列、09 §B.1-4）同樣改變**單一地點**的 committed（皆屬系統流程，非 API 直調，唯讀性不破）。照字面實作「僅兩條路徑」，move 後兩個地點的 committed 都會錯，且 F.3-1 的**單地點**恆等式對帳會炸（全店加總仍平，錯誤不可見）。
- `incoming`：不可直調；來源＝transfer shipment in transit／app／（舊模型 PO）（S2/S12）。
- 排程轉換 `inventorySetScheduledChanges`：**只寫預告不動數字**——「仍需其他 mutation 改數量」（S2）；物件欄位見 A.1（S5）。

### C.6 超賣防護

- 變體級 `inventoryPolicy`（2 值）：`DENY`＝售罄不可下單／`CONTINUE`＝售罄可下單（S24）。
- CONTINUE 前置：必須先開 tracked（S15）。生效後 available 可為**負**（「零或以下」仍可售）（S15）。
- **POS 例外**：CONTINUE「不適用於 POS 訂單」——POS 本來就允許售罄續賣，只在售前**警告**店員（S15）。
- **多地點顯示陷阱**：履行線上訂單的地點缺貨、其他地點有貨但 `fulfillsOnlineOrders=false` ⇒ 線上商店仍顯示售罄（S15）。
- DENY 下的防超賣屬結帳域職責（扣減時序見 D.1）；庫存域的職責是保證 available 原子遞減不落負（條件式 UPDATE）。

### C.7 調整 reason 值域（API 17 值全集，S2，取證 2026-08-14）

| reason | 用途（改寫） | 類型 |
|---|---|---|
| `correction` | 更正錯誤／一般調整（admin 預設） | 手動 |
| `cycle_count_available` | 盤點差異 | 手動 |
| `damaged` | 損壞出帳 | 手動 |
| `received` | 收到貨 | 手動 |
| `restock` | 退貨回補可售 | 手動 |
| `shrinkage` | 遭竊或遺失 | 手動 |
| `promotion` | 促銷或捐贈出帳 | 手動 |
| `quality_control` | 移入品檢 | 狀態移動 |
| `safety_stock` | 移入安全庫存 | 狀態移動 |
| `reservation_created` / `reservation_updated` / `reservation_deleted` | 保留的建/改/刪 | 系統/app |
| `movement_created` / `movement_updated` / `movement_received` / `movement_canceled` | transfer 或 PO 的建/改/收/取消 | 系統 |
| `other` | 其他 | 手動 |

- Admin UI 手動調整只露出 7 個（更正〔預設〕/盤點/已收件/退貨重新入庫/損壞/遭竊或遺失/促銷或捐贈——77 §1 實測＋help），與 API 17 值是**子集關係**：其餘 10 個由系統流程產生。`INVALID_REASON` 擋非法值（S19/S20）。

### C.8 其餘驗證規則

- 調整前提：item 必須已 stocked at location（`ITEM_NOT_STOCKED_AT_LOCATION`），否則先 connect（activation）（S19/S20）。
- move 僅限**同一 location 內**換狀態；跨地點一律走 Transfer（S18）。
- 合法 move 端點集合＝{available, reserved, damaged, safety_stock, quality_control}（S2）。
- CSV 匯入（77 §1，help 雙源）：19 欄、僅 4 欄可寫（On hand (new)/Bin name/HS Code/COO）、`not stocked` 表未備貨、整數限定、檔案 ≤15MB、On hand (current) 為防覆寫安全欄（匯出後有變動則整列跳過並 email）。
- 批量編輯器 13 欄直改**不寫調整歷史**（77 §1 實測）——與 ledger 唯一入口衝突，我方處置見 F。

### C.9 邊界案例

1. untracked（tracked=false）：不擋售、報表與庫存頁無數字（01 §2）。
2. CONTINUE＋退款回補：available 可能從負值回正，恆等式仍須成立。
3. transfer 收貨 reject：S10 字面「不改任何地點數量」**僅對 on_hand／available 成立**——destination `incoming` 必須 `−q`（見 B.3，2026-08-17 更正），否則拒收量永久滯留在途；on_hand 側的實體帳落差靠 `receivedQuantity` 對帳吸收（S10）。
4. 停用地點仍可調整/轉移/退貨入庫（S13）——「地點停用」≠「庫存凍結」。
5. 已付款訂單在停用地點取消且 restock=true ⇒ **失敗**；未付款成功但不回補（46a §7）。
6. 同址多地點 routing 平手 ⇒ 取**較舊**的 location（S14）。
7. LocationSnapshot：transfer 顯示的是**地址快照**，事後改地址不回寫舊單（S6）。

---

## D. 關鍵流程

### D.1 下單 → 履約（committed 的一生）

1. 顧客/店員成立訂單（操作者：buyer/staff）→ 系統按 routing 指派地點（D.7）→ 該地點 available−、committed+（S12；僅 tracked 行（2026-08-17 更正，PR #52 第 11 輪））。失敗分支：DENY 且 available 不足 ⇒ 結帳擋單；CONTINUE ⇒ 照常成單、available 落負（S15/S24）。
2. （可選）成單後改派：`fulfillmentOrderMove`（09 §B.1-4）⇒ committed 跨地點遷移（B.1 表對應列）；前置＝目的地備貨該 item（S32）；已履約品項不動。
3. 履行（staff/3PL）：fulfillment 建立 ⇒ committed−、on_hand−（S12）。部分履行按數量分次。
4. 取消/退款：`orderCancel` 的 `restock` 必填；refund 逐 line item 選 **4 值 `restockType`**——`CANCEL`（未履行→自訂單移除＋回補 available）/`RETURN`（已履行→回補 on_hand+available）/`NO_RESTOCK`/`LEGACY_RESTOCK`（deprecated，「新建退款不接受」）（S31；06 §A.4）；退貨走 disposition（RESTOCKED→指定 location 回補）（46a）。
5. 事件：我方 outbox 發 `inventory.adjusted`（reason=系統值）＋數字同源 rollup 更新（鐵律 5/7）。

### D.2 手動調整（admin）

- 三入口：庫存列表列上就地編輯 Available/On hand｜商品頁變體庫存卡｜CSV（77 §1）。
- 模式二：**Set**（絕對值→`inventorySetQuantities`，強制 CAS）／**Adjust by**（差值→`inventoryAdjustQuantities`）；狀態間移動（如移入安全庫存）→`inventoryMoveQuantities`（S2/S17/S18）。
- 必帶：reason（UI 7 選 1，預設更正）＋idempotency key；系統寫 AdjustmentGroup 入歷史（180 天可視）（S26/S27）。
- 失敗分支：CAS stale ⇒ 前端重讀再送；`ITEM_NOT_STOCKED_AT_LOCATION` ⇒ 先啟用該點 stocking。

### D.3 草稿單保留

1. staff 在 draft order ⋯ 選「Reserve inventory」＋到期時間（S25）。
2. 系統：units 進 **Unavailable**（我方 bucket＝`draft_reserved`），其他顧客不可購；不保留則留在 Available（S25）。
   - ⚠️ 保留落在**哪個 location** 官方未明文（S25 只寫狀態不寫地點）：draft 尚未 routing、無 assignedLocation。我方推定＝依 routing 規則（D.7）預演的首選地點；轉正式單時若 routing 實際結果不同，保留須原子遷移至實際地點。官方未明文，待實測（openQuestion）。
3. 到期/刪草稿 ⇒ 回補 available；轉正式單 ⇒ 保留轉 committed。⚠️ 轉單瞬間的原子語義官方未明文（openQuestion）。

### D.4 Transfer 全流程

1. staff 建立（origin/destination 可留空＝外部）→ Draft（不保留）（S9）。
2. Mark as ready to ship → origin 保留（reserved）；或直接 Move to in transit（S9）。
3. shipment 標 In transit（可附 tracking、多批次）→ destination incoming+（S10）。
4. 收貨逐列 accept/reject/cancel；部分收貨 ⇒ transfer 停在 In progress；全收 ⇒ TRANSFERRED（S10）。
5. 失敗/例外：僅 Draft/Ready to ship 可 Cancel（reserved 回 available）；僅 Draft 可刪；收錯用 Manage received items 改（S9/S10）。
6. 事件（本尊 webhook＝我方 outbox 對應）：transfer 級 `INVENTORY_TRANSFERS_READY_TO_SHIP`/`_UPDATED`/`_ADD_ITEMS`/`_REMOVE_ITEMS`/`_UPDATE_ITEM_QUANTITIES`/`_CANCEL`/`_COMPLETE`；shipment 級另有 `INVENTORY_SHIPMENTS_*` 8 topics（E 節表；`_MARK_IN_TRANSIT`/`_RECEIVE_ITEMS` 正是步驟 3/4 的事件面）（S23）。

### D.5 Purchase Order 流程

1. staff 建 Draft（供應商/目的地/品項/成本/稅/付款條件/幣別）（S11）。
2. Mark as ordered → 不可刪只可封存；**成本回寫 cost per item**（77 §2）。
3. 建立**連結 transfer** 收貨（「PO 記約定、transfer 記移動」）（S11）；收貨流程＝D.4 步驟 3–5。
4. 地點停用互鎖：有 open PO 的地點不可停用（`HAS_OPEN_PURCHASE_ORDERS_ERROR`）（S21）。

### D.6 地點停用

1. staff 發起停用；前置：非 default、處理完 pending 訂單/轉移（S13）。
2. `locationDeactivate(locationId, destinationLocationId?)`：搬移「庫存、待處理訂單、移動中轉移」；未給目的地且有庫存 ⇒ `HAS_ACTIVE_INVENTORY_ERROR`（S21）。
3. 事件：`LOCATIONS_DEACTIVATE`（重啟用發 `LOCATIONS_ACTIVATE`）（S23）。

### D.7 Order routing（committed 指派到哪個地點）

規則依序套用（S14，取證 2026-08-14）：

| 序 | 規則 | 行為 |
|---|---|---|
| 1 | Minimize split fulfillments | 「能出全單的地點優先」，最少包裹 |
| 2 | Stay within the destination market | 與收件地址同 market 的地點優先 |
| 3 | Ship from closest location | 直線距離最近優先；也是**平手決勝**；同址取較舊地點 |
| 可選 | Use ranked locations | 依商家自訂分組排序 |
| 可選 | Use location metafields | 依 boolean/numeric metafield 排序 |

- 需 ≥2 個 active locations 才有 routing（S30）。⚠️ 「無任何地點有貨」時的指派行為官方未明文（openQuestion）。

---

## E. 跨模組耦合

**依賴方向**：Products →（1:1）Inventory；Orders/Draft Orders/Returns → 消費並驅動 committed/available；Fulfillment（routing）→ 決定扣哪個地點，且 `fulfillmentOrderMove` ⇒ committed 跨地點遷移（B.1 對應列；與 09 §B.1-4 互引，move 前置「目的地備貨該 item」查的就是本域 stocking 狀態）；Markets → routing 規則 2；Analytics ← 調整歷史報表（>180 天唯一出口）；POS → 超賣例外；B2B/channels ← `sellableOnlineQuantity`（S24）。

**本尊 webhook topics（＝我方 outbox 事件面）**（S23，取證 2026-08-14）：

| 群 | Topics |
|---|---|
| inventory_items | `INVENTORY_ITEMS_CREATE` / `_UPDATE` / `_DELETE` |
| inventory_levels | `INVENTORY_LEVELS_CONNECT` / `_UPDATE` / `_DISCONNECT` |
| locations | `LOCATIONS_CREATE` / `_UPDATE` / `_DELETE` / `_ACTIVATE` / `_DEACTIVATE` |
| inventory_transfers（7） | `_ADD_ITEMS` / `_REMOVE_ITEMS` / `_UPDATE_ITEM_QUANTITIES` / `_CANCEL` / `_COMPLETE` / `_READY_TO_SHIP` / `_UPDATED`（官方描述＝該 transfer 下的 shipment 被建/改/刪時觸發） |
| inventory_shipments（8，與 13 §A.3 同源） | `INVENTORY_SHIPMENTS_ADD_ITEMS` / `_CREATE` / `_DELETE` / `_MARK_IN_TRANSIT` / `_RECEIVE_ITEMS` / `_REMOVE_ITEMS` / `_UPDATE_ITEM_QUANTITIES` / `_UPDATE_TRACKING`——B.3 shipment 狀態機的事件面；scope＝`read_inventory_shipments`（唯 `_RECEIVE_ITEMS` 要 `read_inventory_shipments_received_items`）（S23，取證 2026-08-14） |
| purchase orders | **無 webhook topic**（S23）——我方若需事件自行定義並標 ours |

**與訂單域的契約點**（46a；restockType 已依 06 §A.4/§F.1 的 2026-08-14 實抓修正）：`refundCreate.restockType` **4 值** `CANCEL`（未履行→自訂單移除＋回補 available、committed 同步−）/`RETURN`（已履行→回補 on_hand+available）/`NO_RESTOCK`/`LEGACY_RESTOCK`（deprecated，「新建退款不接受」，只出現在歷史資料）——**沒有叫 `RESTOCK` 的值**（S31）；CANCEL/RETURN 之分同時決定庫存回補語義與報表歸類，M4 schema 用 4 值 enum；`orderCancel.restock` non-null；退貨 disposition `RESTOCKED`/`NOT_RESTOCKED`/`PROCESSING_REQUIRED` 等；停用地點×已付款×restock ⇒ 失敗。

**權限面**：讀庫存 `read_inventory`（levels）/`read_products`（items）；transfer 專屬 `read_inventory_transfers`；shipment 專屬 `read_inventory_shipments`＋收貨事件 `read_inventory_shipments_received_items`；locations `read_locations`（S23）。

---

## F. 落地對應

### F.1 對應倉庫文件

- `docs/specs/13` **F5/F5.1**：庫存帳模型、五態欄位、unavailable 子分類、調整服務、對帳 rake——本文 B.1/C.1/C.3 是其官方佐證與補全。
- `docs/research/77` §1–§3：admin 按鈕級實測（檢視/欄集/CSV/批量編輯器/PO/Transfer 建立式）。
- `docs/research/01` §2：模組總覽。`docs/research/46a`：訂單側 restock/冪等契約。`docs/specs/11` §0 七維度驗收。

### F.2 本尊 vs 我方裁定差異清單

| # | 主題 | 本尊 | 我方裁定 | 定性 |
|---|---|---|---|---|
| 1 | 量化狀態儲存 | 8 態扁平 quantities（reserved/damaged/qc/safety_stock 各自成態）（S1） | `inventory_levels` 四彙總欄（available/committed/unavailable/incoming）＋`inventory_unavailable_buckets` 子表（13-F5.1） | 結構不同、語義等價；序列化層須能還原 8 態名 |
| 2 | 草稿/app 保留 | 併入 reserved／Unavailable，非手動子狀態（S25；77 §1） | 獨立 bucket `draft_reserved`/`app_reserved`（13-F5.1c） | ours 加細，為到期回補精準定位 |
| 3 | 金額（unitCost/PO 成本） | `MoneyV2`（decimal）（S3） | 內部 integer cents ×100，序列化層才轉 MoneyV2（鐵律 3／specs/65） | ours 硬性 |
| 4 | 多租戶 | 單店概念，無 shop_id | 全表帶 `shop_id`＋複合索引開頭（鐵律 2） | ours 硬性 |
| 5 | 冪等 | `@idempotent(key:)` directive，2026-04 起 17 支硬性（S16/S17；46a S49） | mutation 參數 `idempotencyKey`（鐵律 5） | 傳輸形式不同，語義照抄（三種 IDEMPOTENCY_* 錯誤碼照收） |
| 6 | 事件 | webhook topics（S23） | outbox（鐵律 5），事件名 1:1 映射 E 節表 | 形式差異 |
| 7 | userErrors | 各 mutation 專屬 typed error（S19/S20） | 全 mutation typed code enum（鐵律 4，ours 加嚴） | 對齊且加嚴 |
| 8 | 上限值 | 散在文檔（±2e9、1e9、180 天、地點 2/10/200、CSV 15MB） | 一律進 `config/limits.yml`（鐵律 6）：`limits.inventory.*`、`limits.locations.*`；SaaS 方案配額由我方計費層定義，不照抄 Shopify 方案名 | ours 結構化 |
| 9 | 批量編輯器 | 直改絕對值、**無稽核歷程**（77 §1 實測） | ledger 唯一入口（13-F5.2）：批量路徑也必須落 ledger（reason=`correction`、reference=批量工作 GID）——衝突處置＝我方**不複製**本尊的稽核空洞（71 §F V2 登記） | ours 刻意偏離（更嚴） |
| 10 | 調整歷史保留 | 180 天＋更早走報表（S26/S27） | `limits.inventory.adjustment_history_retention_days=180`（13-F5.1g）；ledger 本體永久保留，180 天只是 UI 視窗 | 對齊＋澄清 |
| 11 | PO/Transfer 導航 | 獨立頁（77 STRUCT1） | 已對齊（R8 修正） | 對齊 |
| 12 | reason 值域 | admin 7（手動）⊂ API 17（S2） | ledger `reason` 收全 17 值；UI 只露 7；系統值僅內部產生 | 對齊 |
| 13 | 取貨/在地履約網路 | POS/local pickup 全球一套 | per-jurisdiction pack（鐵律 11）；庫存核心不引用任何法域特定取貨網路 | ours 硬性 |
| 14 | 數字同源 | 庫存頁/商品頁/報表各自查詢 | 同指標同 rollup（鐵律 7）；`totalInventory`/列表彙總/分析頁共用 | ours 硬性 |

### F.3 開發驗收要點

1. **恆等式測試**：任意操作序列後 `on_hand = available+committed+Σunavailable_buckets`；`incoming` 永不入 on_hand；nightly ledger 重放 `SUM(delta)=現值`（13-F5.3）。**transfer 全流程按 B.2 期望值表逐階段斷言**（含裁定一的 IN_TRANSIT 出帳）；對帳必須做到**單一地點層級**且重放含 `fulfillmentOrderMove` 事件——只驗全店加總會漏掉 move 造成的兩地點 committed 對錯互抵（C.5）。
2. **併發三件套**：超賣（DENY 條件式 UPDATE 不落負）、CAS stale 重試、同 idempotency key 重放不重複入帳——各須有失敗路徑測試（驗收基準「併發要害」）。
3. **committed 唯讀**：任何 public API/service 不得直改 committed/incoming；rubocop cop 掃 `update(available:)` 直寫（13-F5.2）。
4. **狀態機無孤兒**：Transfer 6 態/Shipment 5 態/PO 2 態×archived 旗標（含 archive⇄unarchive 雙向與 open 判定式）轉移表全覆蓋；`OTHER` 佔位須能反序列化不炸。
5. **ledger 三鐵則**（C.3）落驗證器：available 帶 ledger URI ⇒ reject；非 available 缺 ⇒ reject；`gid://chilllove/` 內部文件比照本尊禁 `gid://shopify/`。
6. **邊界矩陣**：負 available（CONTINUE）、reject 收貨、停用地點調整、同址 routing 平手、±2e9/1e9 界限、`not stocked` CSV 列。
7. **事件面**：E 節 outbox 事件逐一有 emit 測試（含 `INVENTORY_SHIPMENTS_*` 8 topics——shipment 狀態機 B.3 每條轉移各對應一發）；`inventory_levels.update` 對應我方低庫存通知鏈（13-F5.5）。

---

## G. 來源（全部取證 2026-08-14）

| 代號 | URL | 支撐內容 |
|---|---|---|
| S1 | https://shopify.dev/docs/apps/build/orders-fulfillment/inventory-management-apps | 8 態定義、on_hand 公式、committed 不可調 |
| S2 | https://shopify.dev/docs/apps/build/orders-fulfillment/inventory-management-apps/manage-quantities-states | reason 17 值、各 mutation 可寫狀態、referenceDocumentUri、CAS、scheduled changes |
| S3 | https://shopify.dev/docs/api/admin-graphql/latest/objects/InventoryItem | InventoryItem 欄位、duplicateSkuCount、inventoryBulkToggleActivation |
| S4 | https://shopify.dev/docs/api/admin-graphql/latest/objects/InventoryLevel | quantities(names)、canDeactivate、deactivationAlert |
| S5 | https://shopify.dev/docs/api/admin-graphql/latest/objects/InventoryScheduledChange | expectedAt/fromName/toName/quantity/ledgerDocumentUri |
| S6 | https://shopify.dev/docs/api/admin-graphql/latest/objects/InventoryTransfer | Transfer 欄位、LocationSnapshot、mutations |
| S7 | https://shopify.dev/docs/api/admin-graphql/latest/enums/InventoryTransferStatus | 6 值全集 |
| S8 | https://shopify.dev/docs/api/admin-graphql/latest/enums/InventoryShipmentStatus | 5 值全集 |
| S9 | https://help.shopify.com/en/manual/products/inventory/inventory-transfers/creating-and-managing-transfers | Transfer 各狀態庫存效果、取消/刪除/編輯限制、外部地點 |
| S10 | https://help.shopify.com/en/manual/products/inventory/inventory-transfers/creating-and-managing-shipments | shipment 流程、accept/reject/cancel 效果、部分收貨 |
| S11 | https://help.shopify.com/en/manual/products/inventory/purchase-orders/creating-purchase-orders | PO 欄位、Draft/Ordered、連結 transfer 收貨 |
| S12 | https://help.shopify.com/en/manual/products/inventory/fundamentals/inventory-states | Admin 五態定義、On hand 公式、incoming 排除、draft≠committed |
| S13 | https://help.shopify.com/en/manual/fulfillment/setup/locations/setup | 地點上限表、停用前置、停用後可執行操作 |
| S14 | https://help.shopify.com/en/manual/fulfillment/setup/order-routing/understanding-order-routing | routing 規則全集與順序、平手規則 |
| S15 | https://help.shopify.com/en/manual/products/inventory/setup/selling-when-out-of-stock | CONTINUE 前置、負庫存、POS 例外、多地點顯示陷阱 |
| S16 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/inventoryAdjustQuantities | input/payload、@idempotent 時間線 |
| S17 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/inventorySetQuantities | 僅 available/on_hand、CAS 語義 |
| S18 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/inventoryMoveQuantities | 同 location 限制、from/to 結構 |
| S19 | https://shopify.dev/docs/api/admin-graphql/latest/enums/InventoryAdjustQuantitiesUserErrorCode | 20 值全集、±2e9、ledger 三鐵則、bundle 父項 |
| S20 | https://shopify.dev/docs/api/admin-graphql/latest/enums/InventorySetQuantitiesUserErrorCode | 17 值全集、1e9、COMPARE_QUANTITY_REQUIRED |
| S21 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/locationDeactivate | destinationLocationId、HAS_ACTIVE_INVENTORY / HAS_OPEN_PURCHASE_ORDERS |
| S22 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Location | 能力布林欄位、deactivatable/deletable |
| S23 | https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic | inventory/locations/transfers/**shipments（8 topics）** 全集、權限 scope（2026-08-14 復抓補 shipments 家族） |
| S24 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ProductVariant | inventoryItem 1:1、inventoryPolicy 2 值、sellableOnlineQuantity |
| S25 | https://help.shopify.com/en/manual/fulfillment/managing-orders/create-orders/create-draft | 草稿保留 → Unavailable、到期時間 |
| S26 | https://changelog.shopify.com/posts/increase-inventory-adjustment-history-from-90-days-to-180-days | 90→180 天（2024-11-08） |
| S27 | https://help.shopify.com/en/manual/products/inventory/adjusting-inventory/adjustment-history | 180 天視窗、更早走調整報表 |
| S28 | https://help.shopify.com/en/manual/products/inventory/inventory-transfers | Transfers 總覽、外部地點用例 |
| S29 | https://help.shopify.com/en/manual/products/inventory/purchase-orders | PO 僅 Draft/Ordered、收貨在 transfer 側 |
| S30 | https://help.shopify.com/en/manual/fulfillment/setup/order-routing | routing 需 ≥2 active locations |
| S31 | https://shopify.dev/docs/api/admin-graphql/latest/enums/RefundLineItemRestockType | 4 值全集（CANCEL/RETURN/NO_RESTOCK/LEGACY_RESTOCK）、無 RESTOCK 值、LEGACY_RESTOCK 新建不接受 |
| S32 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/fulfillmentOrderMove | move 失敗條件（目的地未備貨該 item／FO closed／3PL 請求懸置）、已履約品項留原地點 |

（S11 於 2026-08-14 復抓補：Ordered 後不可刪只能封存、Unarchive 可還原。）

倉庫內部來源：`docs/specs/13`（F5/F5.1）、`docs/research/77`（§1–§3 實測）、`docs/research/01`（§2）、`docs/research/46a`（restock/冪等）、`CLAUDE.md` 鐵律 2/3/5/6/7/11。同輪藍圖互引：`06-returns-refunds.md` §A.4/§F.1（restockType 4 值實抓）、`09-fulfillment-shipping.md` §B.1-4（fulfillmentOrderMove 語義）、`13-platform-events.md` §A.3（INVENTORY_SHIPMENTS_* 家族）。
