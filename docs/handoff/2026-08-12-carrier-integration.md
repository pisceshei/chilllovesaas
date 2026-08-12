# 2026-08-12 — 物流商對接架構（carrier integration）

## ① 我改了什麼

**新增** `docs/specs/58-carrier-integration.md`（1077 行）——物流商對接的核心規格。九個章節 ＋ 三個附錄：

| 節 | 內容 |
|---|---|
| §0 | 使用者裁定拆解、五條設計原則、**三級物流商出處等級**（`carrier-official` / `carrier-secondary` / `carrier-unobtainable`）、順豐研究實得逐項標等級 |
| §A | **carrier adapter 介面**——三個名詞分離（Pack／Account／Service）、十三項能力、逐項契約、`未宣告 ⇒ reject`、adapter 介面硬形狀 |
| §B | 能力矩陣（SF／DHL／UPS／FedEx／manual）＋ **能力缺席時 UI 顯示什麼**（逐項對照表） |
| §C | 與 FulfillmentOrder 的接合。**核心結論：沒有任何 FO 轉移會呼叫 carrier** |
| §D | 運單：取號與打印分離、格式與尺寸、批次、重印、**§D.5 銷號帳** |
| §E | 冪等：`required_for` ＋4 支、我方冪等 vs 物流商冪等的兩層區分 |
| §F | transaction 內禁外部 IO 的正確編排（intent → call → settle 三段式） |
| §G | 多租戶、憑證加密、金額轉換 |
| §H | 法域交互（carrier pack ≠ jurisdiction pack） |
| §I | GraphQL 契約 ＋ 8 個專屬 `userErrors.code` |
| §K | 七維度驗收 29 條 ＋ 5 條 CI 級 |
| 附錄 A | **V-37 ~ V-50** 待查證登記 |
| 附錄 B | 查過的 11 組 URL ＋ 各自取得了什麼 |
| 附錄 C | 與 46a／16／56／15／28／11／原型 的引用關係，逐項標「本檔有沒有改它」 |

**修改** `config/limits.yml`（純新增 ＋ 一處語義對齊，見 ②）：
- 新增 `carrier:` 區塊（16 個子鍵群：能力宣告契約、`capability_schema`、money、waybill、label、rate_quote、tracking、shipment_intent、節流熔斷、credentials、packs 註冊表）
- `idempotency.required_for` **22 → 26**：`shipmentIntentCreate` / `shipmentVoid` / `shipmentCancel` / `carrierPickupSchedule`
- `idempotency.business_unique_keys` **5 → 9**（對應上面四支）

**未改動**：`docs/design/*.html`（有別的 agent 在改）、`docs/specs/16`、`docs/specs/56`。未 commit。

## ② 為什麼這樣改（含被推翻的假設）

**被推翻的假設 1：「carrier 就是 fulfillment service」** —— §C.3。
一開始很自然會想把順豐掛成 `assigned_fulfillment_service_id`，這樣就能用現成的 `requestStatus` 軸 ＋ `REQUEST_CANCELLATION` 動作。**錯的。** 46a:247 逐字定義 `UNSUBMITTED` 是「the only valid request status for fulfillment orders **not assigned to a fulfillment service**」，而 16-F3.1(d) 已把它固化成 DB 不變量。判準是**誰持有庫存、誰決定接不接單**：3PL 兩者皆是，物流商兩者皆否——它只負責把已包好的箱子運走。
⇒ 「取消運單」**絕對不是** `fulfillmentOrderSubmitCancellationRequest`，而是新的 `shipmentVoid`，作用對象是 `waybills` 不是 `fulfillment_orders`。接錯會讓自營出貨的 FO 離開 `UNSUBMITTED`，直接違反不變量。

**被推翻的假設 2：「carrier 的外部連結可以用 `EXTERNAL`」** —— §C.3 後果 3。
46a:275 的 `EXTERNAL` 是配 fulfillment service 的 `externalUrl`。carrier 既然不是 fulfillment service 就不能借用；借了以後前端必須分辨「這個 EXTERNAL 是 3PL 的還是 carrier 的」，等於把 guard 邏輯漏回前端，違反 46a:372。**carrier 連結放運單卡的 `carrier_portal_url`，與 `supportedActions` 無關。十二個 enum 值一個都不新增。**

**被推翻的假設 3：「carrier 失敗就把 FO 設成失敗狀態」** —— §C.2 三條明令禁止。
`INCOMPLETE` 是 `fulfillmentOrderClose` 的結果（商家的決定），`CANCELLED` 會依 46a:236／354 產生替代單。用它們承載「API 逾時」會讓狀態失去意義，而且每次逾時多一張 FO。**正解：FO 狀態不變，錯誤掛在 `shipment_intents` 上。**

**被推翻的假設 4：「逾時就重試」** —— §A.2 K2、§E.2。
本檔最貴的一個坑。`unknown`（逾時／連線中斷）**不等於** `transient_error`。順豐官方自己把查單介面定位成回應遺失時的補救手段（§0.4 SF-6）——等於承認下單回應可能丟失但副作用已發生。自動重試 ⇒ 兩張運單、兩筆運費，多的那張永遠不會被使用也不會被銷號。所以 `ShipmentResult.outcome` 拆成**四值**不是兩值，且 `auto_retry_on_unknown_forbidden: true`。

**核心決策：三段式編排（§F.2）。**
鐵律 5 禁止 transaction 內外部 IO。但本檔多一層理由：若外部呼叫在 transaction 內成功、transaction 之後回滾，**號已經取了而 DB 沒有任何紀錄——這張運單從此不存在於系統中，永遠不會被銷號**。所以 `ShipmentResult` 必須在 settle 之前先以獨立短交易落地：外部已發生的事實先記，本地業務寫入後做。

**核心決策：§D.5 銷號帳。**
紙上談兵的規格寫「支援取消運單」就結束。真正會出事的是**沒有人去按取消**的單。取號＝向物流商借了有價資源，不還就計費。因此：七狀態運單狀態機、五個觸發銷號的場景（**場景 4「換物流商重取號」最隱蔽**）、閉環不變量、`billed_if_unused` 決定告警等級、以及一個「待銷號佇列」畫面——沒有那個畫面，上面所有規則都不會被執行。

**語義對齊（本輪唯一的非純新增改動）**：撰寫期間另一個 agent 同日新增了 `limits.currency_display`，把 `jurisdictions.<code>.currency_format.exponent` 的語義由「ISO 4217 minor unit」**改成「顯示位數」**（TWD 由 0 改為 2），並宣告 `storage_scale_unchanged: true`（儲存一律 ×100）。我原本寫的 `minor_unit_source: …currency_format.exponent` 因此**變成錯的**——拿它換算會在 zero-decimal 幣別上產生 **100 倍誤差**。已改為 `storage_multiplier: 100`，並在 §G.3 留下明確的「請勿改回」警告。原登記的 V-50 因此結案。

## ③ 還有什麼沒解決

**順豐文檔只拿到一半。** `qiao.sf-express.com` 與 `open.sf-express.com` 都是**前端 JS 渲染的 SPA**，抓取只回得到 `<meta>` 標籤；容器內直連受代理政策阻擋（CONNECT 403），無法以瀏覽器渲染取得。拿到的是兩份**官方 PDF**（端點、請求信封六欄、憑證兩件式、八個服務代碼），拿不到的是**面單介面、銷號機制、香港服務代碼、推送驗簽、限流、冪等**。

⇒ **V-37 ~ V-49 共 13 項待查證**，且結果是：**本輪唯一可 enable 的 pack 是 `manual`**。`sf_express` 的 `enable_gate` 有 7 個未結案編號，`dhl_express`／`ups`／`fedex` 各有 1 個。這是刻意的——沒查證完就上線才是缺漏。抽象層（§A–§H）不依賴任何未查證的順豐細節就能成立，這正是把它抽成 pack 的好處。

**取得剩餘文檔的唯一路徑**：申請丰桥帳號登入後由人工匯出，或申請沙箱後實測覆核。**不要再叫 agent 去抓那兩個站，抓不到。**

## ④ 下一個人要注意什麼

1. **`config/limits.yml` 目前有多個 agent 並行編輯。** 我的改動是純新增（`carrier:` 區塊 ＋ idempotency 兩處），但同檔已有 `currency_display` 與 `jurisdictions.*.address` 等他人改動。動這個檔前先 `git diff` 看清楚，別覆蓋別人的。
2. **🔴 `currency_format.exponent` 已不是 ISO minor unit，是顯示位數。** 任何金額換算一律 `×100`。看到 `BigDecimal(raw) * (10 ** exponent)` 就是 bug。
3. **有兩處既有規格與鐵律 11 衝突，我只標記沒有改**（需使用者裁定）：
   - `16-F3.3(a)` 的 `pickup_point_providers` 表把 `carrier` 欄位值域**直接列舉成四個特定法域的便利商店品牌**；
   - `16-F3(3)` 的 tracking URL 模板表同樣列舉了特定法域的物流商名稱。
   兩處都寫於 56／57 之前。建議處置寫在 58 §H.3 的警示框：併入 `carrier_accounts` ＋ `carrier_services`，品牌降級為 `carrier/tw_*` pack 素材、**一行不刪**（比照 56 對 tw pack 的處置）。**本輪未擅自改 16。**
4. **實作順序建議**：`manual` pack ＋ §F 的三段式編排 ＋ §D.5 的銷號帳先做。這三件不依賴任何物流商文檔，而且是所有 pack 共用的骨架。順豐 adapter 等 V-37~V-49 結案再說。
5. **合約測試（§K 21）是可插拔架構唯一的驗證方式**：一份測試對每個 pack 跑。沒有它，「可插拔」只是文件上的宣稱。
6. **V 編號結案時，附錄 B 要新增一列**標明「以什麼來源、什麼日期覆核」。不得只把編號從 `enable_gate` 拿掉而不留來源。
