# 07. 折扣、禮品卡與儲值（Discounts / Gift Cards / Store Credit）

> 取證方法：shopify.dev（GraphQL Admin API 物件參考）＋ help.shopify.com（商家手冊），全部取證 2026-08-14。
> 倉庫對照：`docs/specs/17`（折扣引擎規格）、`docs/research/46b` §2（API 字典）、`docs/research/75`（R6 按鈕級實測）、`docs/specs/65`（金額契約）。
> 本文寫「本尊原貌」；與我方裁定的差異集中列在 §F，正文遇到裁定點以 ★ 標注。

---

## A. 領域物件模型

### A.1 折扣家族：4 型 × 2 method

折扣的第一維是 **method**（`CODE` 需輸碼／`AUTOMATIC` 自動套用），第二維是**型別**（決定 mutation 與輸入結構）。型別建立後**不可變更**（help FAQ，取證 2026-08-14）。

| 型別 | Automatic mutation | Code mutation | discountClasses |
|---|---|---|---|
| Basic（商品/訂單金額折） | `discountAutomaticBasicCreate` | `discountCodeBasicCreate` | PRODUCT 或 ORDER |
| BXGY（買 X 送 Y） | `discountAutomaticBxgyCreate` | `discountCodeBxgyCreate` | PRODUCT |
| FreeShipping（免運） | `discountAutomaticFreeShippingCreate` | `discountCodeFreeShippingCreate` | SHIPPING |
| App（Function 折扣） | `discountAutomaticAppCreate` | `discountCodeAppCreate` | 依 Function 宣告 |

- 本尊**沒有獨立的訂單折扣型別**：商品折與訂單折共用 `Basic`，靠 `customerGets.items`（`all: true` ＝全單）與 `discountClasses` 區分（46b §2①）。admin UI 呈現四張卡（扣減商品金額／買 X 送 Y／扣減訂單金額／免運費），是 UI 層的投影（75 §1）。
- 第五型不存在；階梯量價等進階邏輯官方口徑＝走 Shopify Functions app（75 §1）。
- `DiscountClass` enum 全集：`PRODUCT` / `ORDER` / `SHIPPING`（shopify.dev/enums/DiscountClass，取證 2026-08-14）。

### A.2 Discount node 關鍵欄位（以 `DiscountCodeBasic` 為代表）

| 欄位 | 型別 | 語意 |
|---|---|---|
| `title` | `String!` | 後台與顧客可見名稱（automatic 型顧客可見） |
| `status` | `DiscountStatus!` | 見 §B.1，全集 3 值 |
| `startsAt` / `endsAt` | `DateTime!` / `DateTime` | `endsAt: null` ＝ 無固定到期 |
| `usageLimit` | `Int` | `null` ＝ 不限總次數 |
| `appliesOncePerCustomer` | `Boolean!` | 每客限一次（以 email 或電話識別，見 §C.4） |
| `asyncUsageCount` | `Int!` | **非同步更新、可能低於實際值**（官方自承弱一致）★ |
| `codes` | `DiscountRedeemCodeConnection!` | 一個折扣節點可掛多個兌換碼 |
| `codesCount` | `Count` | |
| `customerGets` | `DiscountCustomerGets!` | value（percentage 0–1 Float 或 fixed amount）＋ items（all / products / collections） |
| `minimumRequirement` | `DiscountMinimumRequirement` | subtotal **XOR** quantity（同給回 `MINIMUM_SUBTOTAL_AND_QUANTITY_RANGE_BOTH_PRESENT`） |
| `combinesWith` | `DiscountCombinesWith!` | 三旗標，見 §C.3；免運型輸入只有 order/product 兩旗標 |
| `discountClasses` | `[DiscountClass!]!` | 複數版；單數 `discountClass` 已 deprecated |
| `context` | `DiscountContext!` | 買家資格：customerSegments **XOR** markets（2025-10 起取代 `customerSelection`） |
| `recurringCycleLimit` | `Int` | 訂閱扣款週期上限；`0` ＝ 無限期 |
| `summary` / `shortSummary` | `String!` | **系統產生**的人話描述（非使用者輸入） |
| `shareableUrls` | `[DiscountShareableUrl!]!` | 分享連結（`/discount/{code}` 路徑） |
| `totalSales` | `MoneyV2` | 該折扣帶動的銷售額 |
| `tags` | `[String!]!` | ≤5 個、每個 ≤255 字元 |
| `customerSelection` | — | **Deprecated**（被 `context` 取代） |

`DiscountRedeemCode`（子物件）：`id`、`code`（顧客結帳輸入值）、`asyncUsageCount`（同樣非同步）、`createdBy`（App）。（shopify.dev/objects/DiscountRedeemCode，取證 2026-08-14）

### A.3 BXGY 專屬結構（`DiscountAutomaticBxgyInput` / Code 同構）

- `customerBuys`：`items`（products/collections）＋ `value` ＝ **quantity（最低件數）XOR amount（最低消費金額）**。
- `customerGets`：`items` ＋ `value: DiscountOnQuantityInput`（quantity ＋ effect ＝ percentage 0–1 ／ 每件折抵金額 ／ 免費）。
- `usesPerOrderLimit: Int`：單筆訂單內最多套用次數（UI「設定每筆訂單的最高使用次數」勾選）。
- Code 版另有 `code`、`usageLimit`、`appliesOncePerCustomer`。

### A.4 FreeShipping 專屬結構

- `destination`：`all: Boolean` XOR `countries`（國家清單）。
- `minimumRequirement`：subtotal XOR quantity。
- `maximumShippingPrice: Money`：「排除超過特定金額的運費費率」——運費高於此值的選項不享免運。
- `appliesOnOneTimePurchase` / `appliesOnSubscription`（兩者不可同時 false，違者 `APPLIES_ON_NOTHING`）＋ `recurringCycleLimit`。
- `combinesWith` 輸入**只有 `orderDiscounts` / `productDiscounts` 兩旗標**——schema 級就不存在「免運疊免運」的開關（46b:197）。

### A.5 訂單側記帳物件（折扣如何落在訂單上）

**`DiscountApplication` interface**（每個生效折扣一筆，訂單快照）：

| 欄位 | 型別 | 語意 |
|---|---|---|
| `index` | `Int!` | 有序索引，標示求值優先序 |
| `allocationMethod` | `DiscountApplicationAllocationMethod!` | `ACROSS`（值分攤到所有 entitled 行）／`EACH`（每個 entitled 行各套一次）／`ONE`（deprecated） |
| `targetSelection` | `DiscountApplicationTargetSelection!` | `ALL`（全部行）／`ENTITLED`（符合資格的行）／`EXPLICIT`（明確指定的行） |
| `targetType` | `DiscountApplicationTargetType!` | 作用於 line items 或 shipping lines |
| `value` | `PricingValue!` | 百分比或金額 |

實作型 4 種：`AutomaticDiscountApplication` / `DiscountCodeApplication` / `ManualDiscountApplication`（draft order 自訂折扣）/ `ScriptDiscountApplication`。（shopify.dev/interfaces/DiscountApplication，取證 2026-08-14）

**`DiscountAllocation`**（每行實際分到的金額）：`allocatedAmountSet: MoneyBag!`（shop＋presentment 雙幣別）＋ `discountApplication`。application 記「意圖與規則」，allocation 記「每行最終分到多少錢」——退款按 allocation 回推。

### A.6 GiftCard 物件

| 欄位 | 型別 | 語意 |
|---|---|---|
| `initialValue` | `MoneyV2!` | 面額（發卡時定死） |
| `balance` | `MoneyV2!` | 剩餘餘額 |
| `maskedCode` / `lastCharacters` | `String!` | 只露末 4 碼；**全碼建立後不可再讀**（卡碼視同貨幣） |
| `enabled` | `Boolean!` | 停用後 false |
| `deactivatedAt` | `DateTime` | 停用時間 |
| `expiresOn` | `Date` | 可為 null（永不過期）；**可事後編輯** |
| `customer` | `Customer` | 收卡顧客（可空、可後補） |
| `order` / `lineItem` | `Order` / `LineItem` | 商品型發卡的來源訂單/行；**手動簽發者為 null**——這兩欄位就是「發行路徑」的判別式 |
| `recipientAttributes` | `GiftCardRecipient` | 受贈人（message / preferredName / sendNotificationAt 排程） |
| `note` | `String` | 內部註記，顧客不可見 |
| `templateSuffix` | `String` | 前台禮品卡頁模板 |
| `crossCurrencyRedemptionStrategy` | enum | `MARKET_FX` / `SPOT_FX` / `NONE`，**建立後不可改**（§C.5） |
| `isRedeemable` | `Boolean!` | 是否可在任一 active market 幣別兌換 |
| `transactions` | connection | 收支流水（credit / debit） |

發行兩路徑：①**商品型**——顧客購買 gift card product（denomination ＝ variant），訂單付款後由 fulfillment 觸發發卡＋寄碼 email；②**手動型**——admin `giftCardCreate`（`initialValue` 必填；自訂 `code` 8–20 位英數，未給則系統產 16 位）。相關 mutation：`giftCardCreate` / `giftCardUpdate`（改 expiresOn/note/templateSuffix/customer）/ `giftCardDeactivate`（不可逆）/ `giftCardCredit` / `giftCardDebit`（調整餘額，走 `write_gift_card_transactions`）/ `giftCardSendNotificationToCustomer` / `...ToRecipient`。（shopify.dev/objects/GiftCard、mutations/giftCardCreate，取證 2026-08-14）

### A.7 StoreCreditAccount 物件

| 欄位 | 型別 | 語意 |
|---|---|---|
| `id` | `ID!` | |
| `balance` | `MoneyV2!` | 當前餘額 |
| `owner` | `HasStoreCreditAccounts!` | **Customer 或 CompanyLocation**（B2B） |
| `transactions` | connection | 可按 `type`（credit / debit / debit_revert / expiration）、`expires_at` 過濾 |

- **帳戶粒度 ＝ (owner, currency)**：同一 owner 可有多個不同幣別帳戶；credit 時若該幣別帳戶不存在**自動建立**。
- **`StoreCreditAccountTransaction` interface**：`account` / `amount` / `balanceAfterTransaction` / `createdAt` / `event` / `origin`。四個實作型：
  - `CreditTransaction`：＋`expiresAt`（可空）＋`remainingAmount`（被 debit 消耗遞減、debit_revert 回增；過期時刻的殘值即過期額）；
  - `DebitTransaction`；`DebitRevertTransaction`（付款失敗/void 回沖）；`ExpirationTransaction`（過期沖銷）。
- **`StoreCreditSystemEvent` enum 全 8 值**：`ADJUSTMENT`（後台手動調整）/ `ORDER_PAYMENT`（結帳抵付）/ `ORDER_REFUND`（退款入帳）/ `ORDER_CANCELLATION`（授權作廢返還）/ `PAYMENT_FAILURE`（他支付方式失敗回沖）/ `PAYMENT_RETURNED`（實際 capture 小於授權）/ `RECURRING_PAYMENT`（訂閱定期扣款）/ `TAX_FINALIZATION`（稅額定案調整）。（shopify.dev/enums/StoreCreditSystemEvent，取證 2026-08-14）
- Mutations：`storeCreditAccountCredit`（`creditAmount`＋可選 `expiresAt`；id 可傳帳戶/Customer/CompanyLocation）/ `storeCreditAccountDebit`（`debitAmount`）。

### A.8 Cardinality 總表

```
Shop 1—N Discount 1—N DiscountRedeemCode（Basic/BXGY/FS code 型）
Discount 1—1 combinesWith；1—N entitlements（products/collections）；1—0..1 context（segments XOR markets）
Order 1—N DiscountApplication 1—N DiscountAllocation（每行每 application 一筆）
Shop 1—N GiftCard N—0..1 Customer；GiftCard 0..1—1 LineItem（商品型）；GiftCard 1—N GiftCardTransaction
Customer|CompanyLocation 1—N StoreCreditAccount（每幣別一個）1—N StoreCreditAccountTransaction
```

---

## B. 狀態機

### B.1 Discount

**API enum `DiscountStatus` 全集 3 值**：`SCHEDULED`（未達 startsAt）/ `ACTIVE`（可用）/ `EXPIRED`（已過 endsAt）。**admin 顯示 4 態**：已排程 / 使用中 / 已過期 / **已停用（Deactivated）**——API enum 沒有 DEACTIVATED，停用是 admin 操作語意（把折扣提前終止），因此落地時必須另存 `deactivated_at` 才能區分「自然過期」與「人為停用」的顯示。⚠️ 本尊「已停用」在 API 對映到哪個 status 值，文檔未載明（推測 EXPIRED，未驗證）。

| 現態 | 觸發 | 前置條件 | 次態 | 副作用 |
|---|---|---|---|---|
| —（不存在） | 建立（8 支 create mutation 之一） | 驗證通過；automatic 型 **startsAt/endsAt 全區間重疊 ≤25**（見 D.1 （2026-08-17 更正，PR #52 第 10 輪）） | SCHEDULED 或 ACTIVE（依 startsAt） | code 型建碼；automatic 型佔 25 額度 |
| SCHEDULED | 時間到達 startsAt | — | ACTIVE | 求值期開始收錄為候選 |
| ACTIVE | 時間到達 endsAt | endsAt 非 null | EXPIRED | 顧客輸碼回錯誤 |
| ACTIVE | 停用（單筆或批量） | — | 已停用 | 顧客見「Unable to find a valid discount matching the code entered」（取證 2026-08-14） |
| 已停用 / EXPIRED | 重新啟用 | — | ACTIVE | 🔴 **結束日期被清空**（官方行為：重啟後「no set end date」）——重啟 ≠ 回復原狀 |
| 任一態 | 刪除（單筆或批量） | — | 終結（自 admin 移除） | 一次性碼歷史消失；刪後重建同碼＝新折扣，once-per-customer 計數重來 |

不變量：**型別與 method 建立後不可變**；status 由時間欄位推導（本尊語意），無孤兒態——「已停用」可經重新啟用回 ACTIVE，EXPIRED 也可重啟。

### B.2 GiftCard

狀態全集（admin 列表）：**Active / Deactivated / Expired**；另有一個獨立維度「餘額狀態」：full / partially used / empty（這不是狀態機，是 `balance` 的投影）。

| 現態 | 觸發 | 前置條件 | 次態 | 副作用 |
|---|---|---|---|---|
| — | 商品型發卡：訂單 fulfillment | 訂單已付款；**medium/high risk 訂單不自動 fulfill** | Active | 產碼、寄 email 給買家或受贈人；`order`/`lineItem` 回填 |
| — | 手動型發卡：`giftCardCreate` | `initialValue` ∈ (0, $2,000 USD 等值]；自訂碼 8–20 英數 | Active | 可排程寄送（`sendNotificationAt`） |
| Active | 兌換（結帳抵付） | balance > 0；幣別相容（§C.5） | Active（balance 遞減） | debit transaction；balance=0 後仍是 Active（empty） |
| Active | `giftCardCredit` / `giftCardDebit` | 金額正 / 餘額足 | Active | 流水一筆 |
| Active | 時間過 `expiresOn` 當日 | expiresOn 非 null | Expired | 不可再兌換；**expiresOn 可編輯**（延後即回 Active——官方明示退款前可暫時延期再改回） |
| Active | `giftCardDeactivate` / admin 停用 | — | Deactivated | 🔴 **不可逆**：「can't be used for further purchases or re-enabled」；不可再加值 |
| Active | 其購買訂單被退款 | 商品型卡 | Deactivated | **自動停用**（官方行為）；手動型卡無付款、不可走退款 |
| 任一態 | 刪除 | — | ❌ 不存在此轉移 | 「You can't delete a gift card after it's created」 |

### B.3 Store credit（信用批次生命週期）

帳戶本身無狀態；有狀態的是**每筆 credit transaction 的 `remainingAmount`**：

| 現態 | 觸發 | 次態 / 副作用 |
|---|---|---|
| remainingAmount = 全額 | debit（結帳抵付 / 後台扣減） | 遞減；**永遠先吃 `expiresAt` 最早的 credit**（FIFO by soonest expiry，官方明文） |
| 已被 debit 消耗 | debit_revert（PAYMENT_FAILURE / ORDER_CANCELLATION） | remainingAmount 回增 |
| remainingAmount > 0 且到達 expiresAt | expiration transaction | 殘值沖銷歸零；「店家時區的當日結束」時刻生效 |

### B.4 批量產碼 job

`discountRedeemCodeBulkAdd`＝**非同步**：提交後回 `bulkCreation` id，用 `discountRedeemCodeBulkCreation` 查進度（有 done 與計數欄位）。單次 ≤250 碼。

---

## C. 業務規則與不變量

### C.1 值域與上限總表（全部官方數字，取證 2026-08-14）

| 項目 | 值 | 出處 |
|---|---|---|
| 同時 active 的 automatic 折扣（**含 app 折扣**） | 25 | help automatic-discounts＋`ACTIVE_PERIOD_OVERLAP` |
| 每店累計唯一折扣碼 | 20,000,000 | help discount-codes |
| 單一折扣碼可指定的顧客/商品/變體 | 各 100 | help discount-codes |
| 單次結帳可用碼數 | 5 個商品/訂單碼 ＋ 1 個運費碼 | help discount-combinations |
| `discountRedeemCodeBulkAdd` 單次 | 250 碼 | shopify.dev mutation 頁 |
| customer segments / 折扣 | automatic 5、code 100 | help（managing-discounts 系）＋46c |
| `percentage` 線上值域 | 0–1 Float | mutation 輸入頁 |
| Plus 同行疊加 tag 數 | ≤10 | `TOO_MANY_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE` |
| 折扣 tags | ≤5 個、每個 ≤255 字 | `TOO_MANY_TAGS` / `INVALID_TAG_LENGTH` |
| Function 折扣 | 25 / store | shopify.dev/docs/api/functions |
| 禮品卡**商品** denomination 上限 | $10,000 USD 等值（不可調升） | help add-update-gift-card-products |
| **簽發**禮品卡上限（2024-05-15 起） | $2,000 USD 等值 | changelog + help issue-gift-card |
| 禮品卡自訂碼長 | 8–20 英數 | admin API gift card 資源頁 |
| 系統產禮品卡碼 | 16 位英數；僅露末 4 碼 | shopify.dev/objects/GiftCard |
| 禮品卡匯出 | ≥50 張改寄 email；CSV 17 欄 | help manage-purchased-gift-cards |
| Store credit 每客上限 | < $15,000 USD 等值 | help store-credit（超限回「credit limit to be exceeded」） |
| `DiscountErrorCode` | 全 39 值 | 46b §2⑤ 已全抄，本文不重複 |

★ 落地時以上全部進 `config/limits.yml`（鐵律 6），不硬編碼。

### C.2 計算公式與 rounding

1. **percentage 的單位**：線上格式 0–1 Float。★ 我方存 basis points 整數（0–10000），序列化除以 10000（46b §2⑥-2、17-F2.1）。
2. **order 級多個百分比折扣＝同基數相加，不複利**（官方：兩個百分比皆以 original subtotal 計算；10%＋20% ＝ 30% off，非 28%）。基數 S₀ ＝ product 級折後小計；公式與鉗制見 17-F2.1：逐筆 `floor(S₀×bp/10000)`，合計 `min(Σ, S₀)`，可交換律成立。
3. **product 級固定金額、items=all 的分攤**：官方例——$50 折扣攤到 $50＋$100 兩件，分別折 **$16.50 / $33.50**。⚠️ 注意這**不是**純比例（純比例＝$16.67/$33.33）；官方未公布捨入算法，只給了這組數字。★ 我方裁定用最大餘數法（15-F2），與本尊示例有 ±數 cent 差異，屬已登記差異（§F）。
4. **product 級固定金額的兩種模式**：`appliesOnEachItem`——「每件各折」vs「整單只套一次」（UI「Only apply discount once per order」勾選）。每件各折時金額乘以件數；只套一次時按第 3 條分攤。
5. **BXGY**：觸發側 X ＝ 最低件數 XOR 最低消費金額（限定 items 集合內計數）；效果側 Y ＝ quantity 件 ×（percentage 0–1 ／ 每件折抵額 ／ 免費）。`usesPerOrderLimit` 限每單套用次數（官方定義轉述：該折扣可套用於一張訂單的最大次數，shopify.dev/objects/DiscountAutomaticBxgy，取證 2026-08-14；`null` ＝ 不限）。**X 與 Y 指向相同商品時，顧客所選較低價的那件作為被折的 Y**（官方轉述：重疊時由顧客所選中較低價的那件獲得折扣，help buy-x-get-y 頁）；一件商品不能同時計入 X 與 Y（先滿足 X 再算 Y）。**Y 永不自動加車**——「never automatically added to the cart」（code 與 automatic 皆然；automatic 版官方明示顧客必須自行把 X、Y 全加入購物車）。免費的 Y 仍佔庫存、仍是訂單行（金額 0＋application 標記）。

   **配對演算法（可實作規格）**——官方只明文 overlap 一句與 usesPerOrderLimit 一句定義，完整配對規則未公布；下列 ★ 為我方確定性定則（登記 §F-15），逐步標注官方可證／⚠️ 待實測：
   - **單元展開**：每個 cart line 依 quantity 展開為單件「資格單元」，單元價 ＝ 該行單價（Scripts 調整後、product 級折扣求值基準，同 §C.3）。X 池 ＝ 符合 `customerBuys.items` 的單元；Y 池 ＝ 符合 `customerGets.items` 的單元；overlap 時同一單元同屬兩池，但**每單元至多被消耗一次**。
   - **單組配對（一次 application）四步**：
     1. 觸發檢查：quantity 模式——X 池**未消耗**單元數 ≥ `buysQuantity`；amount 模式——X 池未消耗單元價合計 ≥ `buysAmount`（皆只計 items 集合內，§C.2-7 同義）。
     2. 選 X ★：未消耗 X 單元**按單價由高到低**取（quantity 模式取 `buysQuantity` 件；amount 模式取「累計 ≥ `buysAmount` 的最少件數」）。tie-break：同價取加入購物車序（line 建立序）較早者。
     3. 選 Y ★：未消耗 Y 單元**按單價由低到高**取 `getsQuantity` 件；不足 `getsQuantity` 件 → 本組不成立、本組已選 X 回滾（前面已成立的組保留）。tie-break 同上。
     4. 消耗標記：本組 X、Y 單元全部標記已消耗，不進後續組。
   - **多組迭代**：重覆四步直到觸發不滿足、Y 池枯竭、或已達 `usesPerOrderLimit`。超出門檻但湊不滿下一組的剩餘單元不獲折扣、不預留。
   - **正確性錨點**：步驟 2＋3 組合是能同時滿足「overlap 低價件作 Y」（官方明文）與「單元不重覆」的最簡確定性規則；「多件符合時折最低價件」另有社群多例商家實測佐證（Shopify 員工未證實演算法，非官方，見 §G）。
   - ⚠️ **官方未明文，待實測**（測試以 ★ 定則產生期望值並標記待驗）：① X 的選件順序（高價先 vs 加入序）——影響 application 的行歸屬與 allocation 落點，quantity 模式下不影響顧客折抵總額；② amount 模式多組時第二組是否須**重新**湊滿 `buysAmount`（★ 暫按「每組獨立重新滿足門檻」）；③ amount 模式下 X 選件順序會影響湊門檻件數，進而影響組數。
   - **Y 效果 rounding**（單位依鐵律 3，全程 integer cents）：FREE → 每件折抵 ＝ `unit_price_cents`；percentage（我方存 bp 0–10000，§C.2-1）→ 每件折抵 ＝ `floor(unit_price_cents × bp / 10000)`，**逐件計算後加總**（不得先加總組額再乘）；每件折抵額 A → 每件折抵 ＝ `min(A_cents, unit_price_cents)`（鉗制不變量 §C.2-8）。⚠️ 官方未公布 BXGY percentage 捨入方向；floor 為我方裁定（與 17-F2.1 同向），與本尊差異上限 1 cent/件。
6. **免運**：作用於運費行（targetType=shipping line）；`maximumShippingPrice` 之上的費率不折；運費折扣在配送選項生成後求值（46b §1 七步：運費折扣位於第 5 步）。
7. **最低門檻語意**：折扣限定特定商品/系列時，**只有相關品項計入**最低金額/件數；order 級門檻以 product 級折後小計判定（17-F2 已定）。
8. **鉗制不變量**：任何行折後金額 ≥ 0；`Σ 行分攤 == application 金額`；折扣不作用於 taxes（amount-off 明文 exclude shipping；稅在折扣後計算）。

### C.3 組合規則（2026 版矩陣）

| 組合 | 可否 | 附註 |
|---|---|---|
| Product ＋ Order | ✅ | 需雙向 `combinesWith` 同意＋資格閘門（下） |
| Product ＋ Product（不同 cart line） | ✅ | |
| Product ＋ Product（**同一** cart line） | ⚠️ 僅 Plus | `productDiscountsWithTagsOnSameCartLine` 雙向 tag 互配；前提 `productDiscounts: true`；百分比先於固定金額套用 |
| Order ＋ Order | ✅ | 同基數相加（§C.2-2） |
| Product/Order ＋ Shipping | ✅ | |
| Shipping ＋ Shipping | ❌ | **引擎級硬規則**，非旗標可控；免運型 combinesWith 根本沒有 shipping 旗標 |

- `combinesWith` 是「我允許與哪一類疊」的白名單，**必須雙向同意**才能共存；預設全 false（組合不自動發生，46c:705）。
- 不能組合時：**自動套「對顧客最有利」的折扣或組合**（best for customer）；被排擠的碼回「Discount couldn't be used with your existing discounts.」。
- 資格閘門（product×order / order×order 組合可用的前提）：無 `checkout.liquid` 客製＋未安裝 Licensify app（＝ Checkout Extensibility 店）。
- 求值順序固定：Product → Order（吃折後小計）→ Shipping；automatic 折扣在 Scripts 之後、以 Scripts 調整價計算；原生折扣不適用 post-purchase 頁。
- 錯誤碼：schema 級寫入非法旗標組合回 `INVALID_COMBINES_WITH_FOR_DISCOUNT_CLASS`；方案不足回 `PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_NOT_ENTITLED`。

### C.4 資格、用量與併發

- **customer eligibility 全集 4 選項**：所有顧客 ／ 特定顧客（逐一指定，≤100）／ 顧客群（segments）／ **市場**（markets）。API 層 `context` 的 markets 與 customerSegments **互斥**（「either markets OR customer segments, not both」）。2025-10 起 `context` 取代 `customerSelection`；**automatic 折扣首次支援客群限定**，且帶客群資格的 automatic 折扣在 2025-10 之前版本的查詢會被整個濾掉（相容陷阱）。
- **once per customer 的身分判定**：以**email 或電話號碼**追蹤，登入與否不影響（結帳有留 email/phone 即計）。官方無二次驗證，換信箱可繞過——防刷要靠正規化（★ 我方：小寫化＋gmail 加點變體歸一後 hash，17-F3）。
- **usageLimit 的一致性**：官方 `asyncUsageCount`「updated asynchronously… might be lower than the actual count」——**本尊自己是弱一致**，高併發下可能超發。★ 我方裁定強一致：訂單成立 transaction 內原子條件 UPDATE（17-F3），對外仍暴露 `asyncUsageCount` 欄位名以相容。
- **碼的字元與大小寫**：官方僅提醒「避免特殊字元」（碼會進結帳 URL `/discount/{code}`）。⚠️ 折扣碼大小寫不敏感是第三方共識＋普遍實測，**官方文檔無正面陳述**（openQuestion）；**禮品卡碼不分大小寫是官方明文**（redeem-gift-card 頁）。★ 我方：碼一律 upcase 正規化＋唯一索引（17-F1），行為上等價於不分大小寫。
- **刪除與重建**：刪掉 once-per-customer 折扣後重建同碼，**舊用戶可以再用一次**（官方 FAQ 明示）——用量記錄跟著折扣實體走，不跟碼字串走。
- **銷售管道**：「銷售管道存取權」只控**推廣展示**，不控兌換（碼在所有管道可兌換，75 §4）；automatic 折扣上 POS 僅 POS Pro 據點，且資格＝所有顧客或指派零售市場時才可勾。

### C.5 禮品卡規則（雙身份）

**身份一：作為商品（可被賣、可被折價）**
- 「Compare-at price 不應用來折禮品卡」——要折就用折扣（例：$100 卡賣 $80）：**售價被折、面額不變**（顧客付 $80、卡值 $100）。
- 「多數折扣不適用於禮品卡」，**唯一例外＝明確指定該禮品卡商品的商品級折扣**；系列（collection）折扣不涵蓋禮品卡商品。★ 我方 17-F2 現行寫「gift card 商品行排除在一切折扣外」——比本尊嚴，需複核（§F-9）。
- 商品型發卡時點＝**fulfillment**（預設付款後自動 fulfill；medium/high risk 訂單例外不自動）。

**身份二：作為支付工具（不是折扣）**
- 抵付對象＝**訂單總額（含稅、含運）**——在所有折扣求值完之後作用；可與折扣碼併用；**一單可用多張禮品卡**；餘額不足時提示補第二支付方式（可以再加一張卡）。
- **部分使用**：餘額可跨多單使用直到歸零；resend 只寄剩餘餘額。
- **幣別**：店幣卡（shop currency）可在任何結帳幣別兌換（按當時匯率轉換）；**當地幣別卡只能在結帳幣別相同時兌換**，除非 `crossCurrencyRedemptionStrategy` 允許（`MARKET_FX`＝用市場設定匯率、僅限店幣卡；`SPOT_FX`＝即期匯率；`NONE`＝僅原幣別）。該策略**建立後不可改**。⚠️ Markets 頁仍寫「禮品卡只能以店預設幣別建立」，與 API 的當地幣別發卡＋策略欄位不一致——判定為文檔新舊並存，以 API 物件為準（openQuestion 留底）。
- **餘額以發卡幣別記帳**，兌換時才換算。
- POS 與 online 卡互通（POS 買、online 兌換皆可）。

**退款互動（三條硬規則）**
1. 混合支付（禮品卡＋信用卡）退款時，**退款先回禮品卡，直到該卡可退額滿**，剩餘才回其他支付方式。
2. **退掉「購買禮品卡」的訂單 ⇒ 該卡自動停用**。
3. 手動簽發的卡沒有對應付款，**不可退款**（只能停用）。
- 已過期卡要退款：官方招式＝暫時把 expiresOn 延後→退款→改回。

### C.6 Store credit 規則

- **只能整額抵付**：「Only the full store credit amount can be applied」——顧客不能選部分金額（與禮品卡不同）。餘額大於訂單總額時抵到訂單歸零、殘額留帳（⚠️ 官方對「餘額>訂單」情境未逐字描述，此半句為推論）。
- **兌換前提＝已驗證身分**：new customer accounts 登入或 Shop Pay；適用 online checkout / POS / Shop channel；**不適用** draft orders、edited orders、其他管道；**不可付訂閱的續期帳款**（只能付首期）。
- **過期**：可設 expiresAt；到期時刻＝**店家時區的當日結束**；多筆不同到期日並存時**先扣最早到期**的（官方明文＝FIFO by soonest expiry）。設定過期前需自行確認當地法規。
- **幣別**：可發多幣別 credit，每幣別一個帳戶；結帳只顯示**與結帳幣別相同**的餘額。
- **發放上限**：每客 < $15,000 USD 等值；credit 金額必須為正。
- **退款入儲值**：可把全額/部分/退貨/取消退成 store credit；事後顧客可要求 **over-refund** 回原支付方式（不必先沖回已發的 credit）——對應獨立 staff 權限。
- 手續費：2025-05-12 後開店者，store credit 抵付部分會收第三方交易費（Plus＋Shopify Payments 豁免）——★ 我方無此商業條款，不落地，記錄供對照。
- 權限模型：檢視/發放/扣減＝「Store credit」＋「Edit store credit」；退款到儲值＝Orders 的「Refund to store credit」；over-refund 另有獨立權限。

### C.7 邊界案例清單（驗收測試素材）

1. 60%＋60% 兩張 order 碼：合計鉗制在 S₀，付 0，行金額不為負。
2. JPY／TWD／KRW 進金額矩陣（鐵律 3）：折扣分攤、禮品卡兌換、儲值過期沖銷全過 zero-decimal。
3. 5＋1 碼滿載＋第 6 張商品碼 → 拒收；兩張運費碼 → 只取一張（非旗標路徑）。
4. BXGY 配對（期望值一律依 §C.2-5 演算法推導）：
   - X=Y=同商品、buy 2 get 1 free、購物車**恰 2 件**（件數恰卡 X 門檻）→ 選 X 後 Y 池枯竭 → 整組不成立、無折扣（一件不得同時計 X 與 Y）；加第 3 件 → 成立，最低價件作 Y。
   - 同商品 3 件單價 30/20/10（cents ×100 後入引擎）→ X={30,20}、Y={10}；同價 3 件 → tie-break 取加入序。
   - 同商品 6 件、`usesPerOrderLimit=1` → 僅第一組成立，剩 3 件無折扣；`usesPerOrderLimit=null` → 兩組，第二組於剩餘單元重跑（Y ＝ 剩餘中最低價件）。
   - amount 模式（滿額送 1）多組：第二組須重新湊滿 `buysAmount`（⚠️ 待實測項，期望值標記待驗）。
5. 固定金額折扣 items=all 攤 3 件以上：Σ 分攤＝折扣額、無 1-cent 洩漏（最大餘數法）。
6. 停用碼→顧客結帳中輸入 → 統一錯誤；重啟後 endsAt 已被清空（測「不保留結束日期」）。
7. 禮品卡 balance=0 仍 Active；再收退款 → 餘額回增（refund 先回卡）。
8. medium/high risk 訂單：發卡被扣住，人工 fulfill 後才寄碼。
9. 儲值三筆不同到期日，debit 跨批次消耗 → 先耗最早到期；revert 回增到**原批次**。
10. 帶客群資格的 automatic 折扣＋舊版 API 查詢 → 被濾掉（若做多版本 API 需覆測）。

---

## D. 關鍵流程

### D.1 折扣建立與生命週期操作（操作者：商家）

1. 選型（4 擇 1，建立後不可改）→ 填表（method、值、entitlements、門檻、資格、用量、組合、時窗）。
2. 系統驗證：subtotal XOR quantity；markets XOR segments；automatic 型檢查 **startsAt/endsAt 全區間重疊 ≤25**（建立/更新/重啟用皆原子驗證——僅查當前 active 數會讓 26 支同未來區間全過再一起生效；違者 `ACTIVE_PERIOD_OVERLAP` （2026-08-17 更正，PR #52 第 9 輪））；免運型 combinesWith 無 shipping 旗標。
3. 寫入 → status 由時間推導 → 產 `summary`（描述產生器）。
4. 後續操作：停用/重啟（🔴 重啟清 endsAt）/刪除/複製/批量；分享連結與 QR（單折扣共用一個配額）。
5. 失敗分支：`DiscountErrorCode` 39 值之一落 `userErrors{field,code,message}`。

### D.2 結帳求值（操作者：買家；系統：Discounts::Engine）

1. 收集候選：全部 active automatic ＋ 已輸入的碼（≤5 商品/訂單 ＋ ≤1 運費）。
2. 過濾：時窗、status、eligibility（email/segment/market）、最低門檻（product 級折後小計）、用量**軟檢**。
3. 組合裁決：combinesWith 雙向同意 → 可共存集合；衝突 → 對顧客最有利者勝，被擠掉的碼回統一錯誤訊息。
4. 分級求值：Product（EACH/ACROSS 分攤）→ Order（同基數相加＋鉗制）→ 配送選項生成 → Shipping（maximumShippingPrice 過濾）。
5. 輸出 applications＋allocations 進 checkout 摘要；每步斷言行金額 ≥0。
6. 失敗分支：碼無效/停用/超量 → 「折扣碼無效或不適用」（★ 我方統一文案，枚舉防護）；限流：每 checkout 10 次/分、每 IP 30 次/分（★ 我方值）。

### D.3 訂單成立時的用量扣減（系統）

1. 訂單 transaction 內：`UPDATE … SET usage_count = usage_count + 1 WHERE usage_limit IS NULL OR usage_count < usage_limit`；affected 0 → 折扣失效 → 回結帳明確報「已被用完」。
2. `appliesOncePerCustomer`：redemption 表 `(shop_id, discount_id, customer_key)` 唯一索引，insert 衝突＝已用過。★ 鐵律 2：全表帶 `shop_id` 且複合索引以 `shop_id` 開頭——`discount_id` 雖已隱含租戶，索引仍必須以 `shop_id` 前綴，不登記例外。
3. applications/allocations 快照落單（退款依據）；outbox 發 `discount.redeemed`。
4. 本尊行為對照：Shopify 只有非同步計數（超發風險自認）★ 我方強一致，屬加嚴差異。

### D.4 禮品卡發行（商品型）

1. 買家購買 gift card product → 訂單付款。
2. 系統：自動 fulfillment（預設）→ 產卡（code 16 位）→ 綁 `order`/`lineItem` → email 寄碼給買家或 `recipientAttributes` 受贈人（可排程）。
3. 失敗分支：medium/high risk → 不自動 fulfill，人工放行後才發卡；退款該訂單 → 卡自動停用。
4. 事件：卡建立、寄送；財務上是**負債**（發卡不是銷售收入，兌換才是——finance reports 分開列）。

### D.5 禮品卡兌換（買家）

1. 結帳輸碼（不分大小寫）→ 驗 enabled/expiry/幣別策略 → 以餘額抵**總額（含稅運）**。
2. 不足 → 提示補支付方式（可再疊卡）；足 → 全額支付。
3. 成單：卡 debit transaction、餘額遞減；混付時記多筆 payment。
4. 失敗分支：Expired/Deactivated → 拒收；當地幣卡遇不同結帳幣別且策略 NONE → 拒收。

### D.6 退款互動（商家）

1. 混付訂單退款：**先回禮品卡**至其可退額滿，再回其他方式。
2. 退款到 store credit：建 credit transaction（event=ORDER_REFUND，可帶 expiresAt）；over-refund 需獨立權限、不沖回已發 credit。
3. 取消/授權作廢：ORDER_CANCELLATION 回沖；他支付方式失敗：PAYMENT_FAILURE → debit_revert。
4. 折扣用量預設**不返還**（★ 我方 17-F3；⚠️ 本尊退款/取消是否回沖 usage count 官方未載，openQuestion）。

### D.7 儲值發放與扣減（商家）

1. 顧客卡片 → Store credit → Edit → Credit/Debit ＋金額（＋credit 可設到期）。
2. 系統：該幣別帳戶不存在則自動建；credit 必須正數、總額 < $15,000；debit 餘額不足回「does not have sufficient funds」。
3. 顧客時間軸落一筆；事件 ADJUSTMENT。

### D.8 批量產碼（商家/行銷）

1. `discountRedeemCodeBulkAdd`（≤250/次）→ 非同步 job → 查 `discountRedeemCodeBulkCreation` 進度。
2. 我方落地：Solid Queue job＋唯一索引衝突忽略重試（17-F4）；產碼器排除 0/O、1/I/L。

---

## E. 跨模組耦合

**依賴方向（誰依賴誰）**
- Checkout/Cart（15）→ 依賴折扣引擎求值輸出；折扣引擎 → 依賴 Customer segments（顧客模組）、Markets（29，市場資格與幣別換算）、Products/Collections（entitlements 展開）。
- Orders（16）→ 快照 applications/allocations；Refunds → 依賴 allocations 反算＋禮品卡/儲值退款規則。
- 禮品卡發行 → 依賴 Fulfillment（發卡時點）與 Risk（風險擋發卡）；兌換 → 依賴 Payments（作為 payment method，OrderTransaction gateway=gift_card ⚠️ 未逐字驗證）。
- Store credit → 依賴 Customer accounts（登入驗證）、B2B（CompanyLocation owner）、Subscriptions（RECURRING_PAYMENT）、Tax（TAX_FINALIZATION）。
- 分析（80）→ 消費折扣 applications 聚合（totalSales、折讓額）；鐵律 7 同源。

**事件（我方 outbox 命名建議 ↔ 本尊 webhook topics）**
- `discount.created/updated/deleted` ↔ 本尊 webhook topics `discounts/create`、`discounts/update`、`discounts/delete`（⚠️ topic 字面未逐一取證，openQuestion）。
- `discount.redeemed`（訂單成立扣量時）——本尊無對應 topic，折扣使用要靠 orders/create 的 discount_applications 推導。
- `gift_card.issued/deactivated/debited/credited`——⚠️ 本尊是否有 gift card webhook topics 未查得，openQuestion；我方照 outbox 規格自發。
- `store_credit.credited/debited/expired`——同上。
- 稅務事件：兌換含稅訂單 → 只發稅務事件，由 jurisdiction pack 決定憑證（鐵律 11）。

---

## F. 落地對應

**倉庫對應**：`docs/specs/17`（引擎規格，本文 §C.2/C.3/D.2/D.3 與其一致）｜`docs/research/46b` §2（API 字典、39 錯誤碼）｜`docs/research/75`（R6 表單級實測）｜`docs/specs/65`（金額契約）｜`docs/specs/13-F1`（isGiftCard 旗標）｜`docs/specs/15-F2`（最大餘數法）｜`docs/specs/16-F5`（退款按 applications 分攤）｜`config/limits.yml`（§C.1 全表落鍵）。禮品卡/儲值尚無專屬 spec 檔（R8/R14 輪規劃中，75 §5）——本文 §A.6/A.7/B.2/B.3/C.5/C.6 即其素材。

**本尊 vs 我方裁定差異清單**

| # | 本尊 | 我方裁定 | 出處 |
|---|---|---|---|
| 1 | 金額走 decimal string / MoneyV2 | 內部 integer cents（×100 不看幣別），序列化層才轉 MoneyV2；zero-decimal 幣別進測試矩陣 | 鐵律 3、65 |
| 2 | `percentage` 0–1 Float | 存 basis points 整數，序列化除 10000 | 17-F2.1 |
| 3 | `asyncUsageCount` 非同步弱一致（自認會低估） | 訂單成立 transaction 內原子條件 UPDATE 強一致；對外保留欄位名 | 17-F3、46b §2⑥-3 |
| 4 | 錯誤訊息區分「找不到有效折扣」等 | 統一「折扣碼無效或不適用」＋限流（枚舉防護優先於 UX 精確，刻意差異） | 17-F4 |
| 5 | 固定金額分攤官方例 $16.50/$33.50（算法未公布） | 最大餘數法，Σ 分攤恆等；與本尊示例容許 cent 級差異 | 15-F2、17-F2 |
| 6 | admin 4 顯示態、API 3 enum；status 實體維護 | status 由時間欄位推導不落庫；另存 deactivated_at 供顯示「已停用」 | 17-F1 |
| 7 | 稅務／憑證內建 | 只發稅務事件，jurisdiction pack 落地；HK 基準 | 鐵律 11 |
| 8 | 禮品卡平台級（Shopify 卡碼跨店不通但平台無監管語意） | HK SVF 單一用途豁免 ⇒ 禮品卡**嚴格單租戶**，schema 與兌換路徑硬隔離 | 鐵律 11 |
| 9 | 指定禮品卡商品的商品級折扣**可以**折其售價（面額不變；系列折扣不涵蓋） | 17-F2 現行寫「gift card 行排除一切折扣」——**比本尊嚴，需按 75 §5 複核修正**（開發時以本文＋75 為準：僅放行「明確指定該禮品卡商品」的 product 折扣） | 75 §5、help discount-gift-card |
| 10 | 單次結帳 5＋1 碼 | M4 前單碼起步，`limits.yml` 已留 5＋1 鍵；多碼提前到 M4 | 17-F2 坑 3 |
| 11 | 折扣匯出 only、無匯入 | 若做匯入＝超集功能需標註 | 75 §4 |
| 12 | 四張獨立 node 型別 | 單表多型 `discounts` ＋ class/method 欄位＋子表 codes/combines_with/entitlements/contexts | 46b §2⑥-1、17-F1 |
| 13 | Store credit 抵付收第三方交易費（2025-05 後新店） | 無此商業條款，不落地 | §C.6 |
| 14 | Plus 限定「同 cart line 疊加」tag 機制 | 對應我方「進階方案」旗標；違者回同名錯誤碼 | 46b §2⑥-6 |
| 15 | BXGY 配對演算法未公布（官方僅明文 overlap 低價件作 Y＋usesPerOrderLimit 一句定義） | 確定性配對：單元展開、X 取高價先、Y 取低價先、同價按加入序、逐組消耗、amount 模式每組重新滿足門檻；⚠️ 三項待實測見 §C.2-5 | §C.2-5、help buy-x-get-y、shopify.dev DiscountAutomaticBxgy |

**開發驗收要點（增量，對 17 既有清單之外）**
1. `DiscountStatus` 推導＋`deactivated_at` 分流顯示；**重啟清 endsAt** 有測試（75 §4 已落 limits 鍵）。
2. 禮品卡狀態機：停用不可逆、無刪除、退購自動停用、expiry 可編輯——四條各有測試；餘額維度與狀態維度分離。
3. 儲值 FIFO：三批次到期消耗順序＋revert 回原批次＋到期沖銷（店時區日終）property test。
4. 混付退款「先回禮品卡」的分配演算法測試（含多卡）。
5. once-per-customer 的 customer_key＝email/phone 正規化 hash；刪除重建折扣後舊客可再用（對齊本尊語意）＝redemption 綁折扣實體不綁碼字串；唯一索引 `(shop_id, discount_id, customer_key)`（鐵律 2，§D.3-2）。
6. BXGY「Y 不自動加車」「低價件作 Y」「usesPerOrderLimit」三規則進組合矩陣測試；配對演算法（§C.2-5）另需 property test：單元不重覆消耗、組數 ≤ usesPerOrderLimit、Σ折抵 ≤ Y 池單價和、C.7-4 四子案例全過；⚠️ 待實測三項的測試以 ★ 定則為期望值並打待驗標記。
7. 固定金額折扣與門檻**只存店預設幣別**，結帳期匯率換算（Markets）；percentage 直接作用當地價——跨幣別測試含 zero-decimal。
8. `context` 的 markets XOR segments 互斥驗證＋segments 上限（5/100）引 limits.yml。
9. 儲值只能整額抵付＋登入前提＋draft/edited order 禁用——checkout 端三個閘門測試。
10. 限流與統一錯誤文案（我方差異 #4）不得被後續「對齊本尊」輪誤改回——已登記為刻意差異。

---

## G. 來源（全部取證 2026-08-14）

**shopify.dev（GraphQL Admin API / Functions）**
- https://shopify.dev/docs/api/admin-graphql/latest/objects/GiftCard — GiftCard 欄位全集、16 位碼、停用不可逆
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/giftCardCreate — 建卡輸入、$2,000 上限語境、回傳 giftCardCode
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/giftCardCredit — 卡餘額調增、write_gift_card_transactions
- https://shopify.dev/docs/api/admin-graphql/latest/enums/GiftCardCrossCurrencyRedemptionStrategy — MARKET_FX/SPOT_FX/NONE
- https://shopify.dev/docs/api/admin-graphql/latest/objects/StoreCreditAccount — 帳戶模型、owner、query filters
- https://shopify.dev/docs/api/admin-graphql/latest/interfaces/StoreCreditAccountTransaction — 交易 interface 六欄位
- https://shopify.dev/docs/api/admin-graphql/latest/objects/StoreCreditAccountCreditTransaction — expiresAt、remainingAmount、FIFO
- https://shopify.dev/docs/api/admin-graphql/latest/enums/StoreCreditSystemEvent — 8 事件全集
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/storeCreditAccountCredit — 自動開帳戶、多幣別、credit limit
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/storeCreditAccountDebit — insufficient funds
- https://shopify.dev/docs/api/admin-graphql/latest/interfaces/DiscountApplication — application 五欄位＋4 實作型
- https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountApplicationAllocationMethod — ACROSS/EACH/ONE(deprecated)
- https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountApplicationTargetSelection — ALL/ENTITLED/EXPLICIT
- https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountStatus — ACTIVE/EXPIRED/SCHEDULED
- https://shopify.dev/docs/api/admin-graphql/latest/objects/DiscountRedeemCode — code 子物件、asyncUsageCount
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountRedeemCodeBulkAdd — 250/次、非同步 job
- https://shopify.dev/docs/api/admin-graphql/latest/objects/DiscountAllocation — allocatedAmountSet
- https://shopify.dev/docs/api/admin-graphql/latest/objects/DiscountAutomaticBxgy — `usesPerOrderLimit` 官方定義（每單最多套用次數）、customerBuys/customerGets 欄位語意；**配對演算法未載**
- https://shopify.dev/docs/api/admin-rest/latest/resources/gift-card — 自訂碼 8–20 英數
- https://shopify.dev/changelog/discount-eligibility-management — context 取代 customerSelection（2025-10）
- https://shopify.dev/changelog/target-discounts-to-specific-markets — markets 資格（2026-07）

**help.shopify.com**
- https://help.shopify.com/en/manual/discounts/discount-combinations — 矩陣、5＋1、best-for-customer、錯誤文案、原始小計相加
- https://help.shopify.com/en/manual/discounts/discount-methods/discount-codes — 20M、100 entities、特殊字元
- https://help.shopify.com/en/manual/discounts/discount-methods/automatic-discounts — 25 上限含 app、Y 需自行加車、Scripts 後執行、無 post-purchase
- https://help.shopify.com/en/manual/discounts/discount-types/buy-x-get-y — X/Y 配置、永不自動加車、低價件作 Y、每單次數上限
- https://help.shopify.com/en/manual/discounts/discount-types/percentage-fixed-amount — 固定金額分攤例、once per order、門檻語意、資格四選項、email/phone 追蹤
- https://help.shopify.com/en/manual/discounts/managing-discounts — 4 顯示態、停用錯誤文案、重啟清結束日、批量操作
- https://help.shopify.com/en/manual/discounts/discounts-faq — 型別不可改、禮品卡折扣例外、碼欄顯示條件
- https://help.shopify.com/en/manual/discounts/discount-gift-card — 折禮品卡售價、面額不變
- https://help.shopify.com/en/manual/products/gift-card-products/overview — fulfillment 寄碼、店幣/當地幣兌換、POS 互通、法規自查
- https://help.shopify.com/en/manual/products/gift-card-products/add-update-gift-card-products — $10,000 denomination
- https://help.shopify.com/en/manual/products/gift-card-products/issue-gift-card — $2,000 簽發上限、幣別選項、寄送
- https://help.shopify.com/en/manual/products/gift-card-products/manage-purchased-gift-cards — 狀態、停用不可逆、無刪除、退款先回卡、退購自動停用、匯出
- https://help.shopify.com/en/manual/products/gift-card-products/modify-gift-card-settings — 預設不過期、預設 5 年可調、風險單不自動 fulfill、Apple Wallet
- https://help.shopify.com/en/manual/products/gift-card-products/redeem-gift-card — 抵總額含稅運、多卡、不足補付、卡碼不分大小寫
- https://help.shopify.com/en/manual/customers/store-credit — 整額抵付、登入前提、$15,000、日終過期、先扣最早到期、over-refund、權限
- https://help.shopify.com/en/manual/markets/discounts-and-gift-cards — 固定折扣店幣建立結帳換算、percentage 不換算、（⚠️ 禮品卡段落疑舊）
- https://changelog.shopify.com/posts/new-maximum-value-for-gift-cards — $2,000（2024-05-15 起）

**社群（非官方，僅作 ⚠️ 項佐證，不作規格依據）**
- https://community.shopify.com/c/shopify-discussions/buy-x-get-y-choosing-lowest-price-items/m-p/1241612 — 商家實測「多件符合時折最低價件」；Shopify 員工回覆未證實演算法，僅建議第三方 app（取證 2026-08-14）

**倉庫（非官方，但已對本尊雙源取證）**
- `docs/research/46b` §2 — DiscountErrorCode 39 值、輸入型別全文、Functions 執行語意
- `docs/research/75` — R6 表單實測、銷售管道存取、草稿訂單限制、POS 行為、多幣別
