# 08. 顧客與 B2B（Customers / Segments / Companies）

> 考掘日 2026-08-14。雙源：shopify.dev Admin GraphQL 物件參考＋help.shopify.com 商家文檔；倉庫對照 `docs/research/74`（R5 實測）、`docs/research/46b` §6（B2B 文檔字典）。凡「取證 2026-08-14」＝本輪親自 fetch 官方頁面；凡引 74/46b＝倉庫既有取證。⚠️＝官方文檔查無明文或有出入。

## A. 領域物件模型

### A.1 Customer（核心）

| 欄位 | 型別 | 語義 |
|---|---|---|
| `id` / `legacyResourceId` | ID! / UnsignedInt64! | GID＋REST 數字 id |
| `firstName` / `lastName` / `displayName` | String / String / String! | displayName 派生：姓名 → email → phone 依序 fallback |
| `defaultEmailAddress` | CustomerEmailAddress | 主 email＋其 marketing state；**`email` 欄位已 deprecated** |
| `defaultPhoneNumber` | CustomerPhoneNumber | 主 phone；**`phone` 欄位已 deprecated** |
| `state` | CustomerState! | 帳號狀態四值（§B.1）；**僅 classic accounts 有意義** |
| `verifiedEmail` | Boolean! | admin／API 建立者預設 `true` |
| `emailMarketingConsent` | CustomerEmailMarketingConsentState | email 同意狀態機（§B.2）；欄位已標 deprecated，改法＝專用 mutation＋defaultEmailAddress |
| `smsMarketingConsent` | CustomerSmsMarketingConsentState | SMS 同意狀態機（§B.3）；同上 deprecated |
| `taxExempt` | Boolean! | 整體免稅開關 |
| `taxExemptions` | [TaxExemption!]! | 豁免類別清單（§C.5） |
| `amountSpent` | MoneyV2! | 終身消費總額 |
| `numberOfOrders` | UnsignedInt64! | 終身訂單數 |
| `lifetimeDuration` | String! | 人類可讀年資（如 "about 12 years"） |
| `productSubscriberStatus` | CustomerProductSubscriberStatus! | 訂閱合約派生態（§B.4） |
| `mergeable` | CustomerMergeable! | `isMergeable`/`reason`/`errorFields[]`/`mergeInProgress`（§C.2） |
| `canDelete` | Boolean! | **有訂單即 false** |
| `dataSaleOptOut` | Boolean! | 資料販售退出（美加隱私法） |
| `multipassIdentifier` | String | Multipass 登入 token（新版帳號不支援 Multipass） |
| `locale` / `note` / `tags` | String! / String / [String!]! | 通知語言／備註（≤5,000 字）／標籤（≤250 個） |
| `companyContactProfiles` | [CompanyContact!]! | B2B 聯絡人身分（§A.4） |
| `addresses`→`addressesV2` / `defaultAddress` | connection / MailingAddress | 地址簿；舊欄位 deprecated |
| `paymentMethods` / `storeCreditAccounts` / `subscriptionContracts` / `orders` / `events` / `metafields` | connections | 皆 cursor 分頁 |

來源：Customer 物件參考（取證 2026-08-14）。查詢入口：`customer(id)`、`customerByIdentifier(identifier)`（可用 email／phone 反查）、`customers(query…)`。

### A.2 Segment

| 欄位 | 型別 | 語義 |
|---|---|---|
| `id` | ID! | GID |
| `name` | String! | 名稱 |
| `query` | String! | Segmentation query（ShopifyQL 子集，§C.6） |
| `creationDate` / `lastEditDate` | DateTime! | 建立／最後編輯 |

- **membership 是動態求值，不落 membership 表**：「符合條件自動加入、不符自動移除」；人數計數在「開啟分群詳情頁」或「app（如 Shopify Messaging）使用該分群」時重估（取證 2026-08-14）。
- 成員讀取：`customerSegmentMembers`（同步，單頁 ≤1,000——**平台 cursor ≤250 通則的顯式登記例外** （2026-08-17 更正，PR #52 第 9 輪））；`customerSegmentMembersQueryCreate`（非同步 job，供大分群）。`segments` 查詢 first/last ≤250。
- 取代 SavedSearch（deprecated）；分群僅能含單店成員。

### A.3 B2B 三物件＋兩關聯

```
Company 1 ─── N CompanyLocation（≤10,000/company）
   │                 │
   │                 ├── catalogs（≤25/location；價格取最低）
   │                 ├── buyerExperienceConfiguration（checkoutToDraft/editableShippingAddress/paymentTermsTemplate/deposit）
   │                 └── taxSettings／currency／billing+shipping address／locale
   └── N CompanyContact（≤10,000/company）── 1 Customer（一個 customer 只能屬一家 company）
              │
              └── CompanyContactRoleAssignment ＝ contact × location × role（≤50 contacts/location）
```

- `Company`：`name`/`externalId`/`note`/`mainContact`/`defaultRole`/`customerSince`/`totalSpent`/`ordersCount`（跨所有 location）。**catalog／payment terms／tax／checkout 設定全部掛 location，company 層只有身分與預設**（46b §6 表；company 頁的「套用到所有地點」是批次寫入每個 location，不是繼承）。
- `CompanyContact`：`customer!`/`company!`/`title`/`locale`/`isMainContact`/`roleAssignments`/`orders`/`draftOrders`；**無 state 欄位**（取證 2026-08-14）。聯絡人＝掛在 retail customer 上的角色，不是獨立帳號。
- `CompanyContactRoleAssignment`：`company!`/`companyContact!`/`companyLocation!`/`role!`（取證 2026-08-14，確認三元關聯）。
- 角色兩種（help，取證 2026-08-14）：**Ordering only**＝只能替被指派 location 下單＋看自己的訂單；**Location admin**＝下單＋看該 location 全部人訂單＋可編輯帳單/運送地址。

### A.4 Customer×B2B 的 cardinality 鐵表

| 關係 | 數量 | 來源 |
|---|---|---|
| customer : company | ≤1（可指派同 company 多個 location） | help adding-customers（取證 2026-08-14） |
| company : locations | ≤10,000 | 46b §6③ |
| company : contacts | ≤10,000 | help（取證 2026-08-14） |
| location : contacts | ≤50 | 46b §6③ |
| location : catalogs | ≤25（**同 specificity 層內**取最低價，層序見價格解析公式） | 46b §6③ |
| 非 Plus 全店啟用中 B2B catalogs | 3 | help b2b/catalogs（取證 2026-08-14 再證） |

## B. 狀態機

### B.1 CustomerState（帳號狀態；僅 classic accounts 有語義）

值域（取證 2026-08-14）：`ENABLED`（已建帳號）／`DISABLED`（無有效帳號；admin 可隨時停用）／`INVITED`（已寄開戶邀請）／`DECLINED`（拒絕邀請）。

| 現態 | 觸發 | 前置 | 次態 | 副作用 |
|---|---|---|---|---|
| DISABLED | admin 寄「帳號邀請」 | 有 email；classic accounts 啟用 | INVITED | 寄邀請信 |
| INVITED | 顧客點信完成開戶 | — | ENABLED | webhook `customers/enable` |
| INVITED | 顧客拒絕邀請 | — | DECLINED | — |
| DECLINED | admin 重寄邀請 | — | INVITED | 寄邀請信 |
| ENABLED | admin 停用帳號 | — | DISABLED | webhook `customers/disable` |
| DISABLED | 顧客自行註冊（storefront） | 商店允許註冊 | ENABLED | webhook `customers/enable` |

- **新版帳號（new customer accounts）沒有這個狀態機**：登入即用（email＋6 位一次性驗證碼），未註冊 email 首次登入**自動建立 profile**；**無「停用」語義**——刪除帳號後同 email 再登入即自動重建（74 §7）。session 最長 365 天（取證 2026-08-14）。
- 本尊 2026-02 已將 legacy（classic）accounts 標為 **deprecated**（sunset 日期未公告）；升級後 **30 天內可還原**，逾期永久；**Multipass 在新版不支援**，Plus 可改接 OAuth2/OIDC IdP（取證 2026-08-14，help upgrade 頁＋changelog 轉述）。
- 分群欄位 `customer_account_status` 即此 enum（help 明標「legacy account status」），四值不可自創。

### B.2 Email 行銷同意（CustomerEmailMarketingState）

值域六值（取證 2026-08-14）：`NOT_SUBSCRIBED`／`PENDING`／`SUBSCRIBED`／`UNSUBSCRIBED`／`REDACTED`／`INVALID`。**可由 mutation 寫入的只有 `SUBSCRIBED`/`UNSUBSCRIBED`/`PENDING`**；`NOT_SUBSCRIBED`（初始態）、`REDACTED`（個資已清除）、`INVALID` 為系統內部態，不可寫。

| 現態 | 觸發 | 前置 | 次態 | 副作用 |
|---|---|---|---|---|
| NOT_SUBSCRIBED | 顧客 storefront 訂閱 | double opt-in **關** | SUBSCRIBED | 記 `consentUpdatedAt`＋opt-in level=SINGLE_OPT_IN |
| NOT_SUBSCRIBED | 顧客 storefront 訂閱 | double opt-in **開** | PENDING | 自動寄確認信（Settings>Notifications 可自訂；信內不得含行銷內容） |
| PENDING | 點確認信連結 | — | SUBSCRIBED | opt-in level=CONFIRMED_OPT_IN |
| PENDING | （不點） | — | PENDING | **不過期**，永遠停在 pending |
| SUBSCRIBED | 點信中 Unsubscribe／標為垃圾郵件／顧客帳號內退出／商家在個檔取消勾選 | — | UNSUBSCRIBED | webhook `customers_email_marketing_consent/update` |
| UNSUBSCRIBED | 重新訂閱 | 同上兩分支 | SUBSCRIBED 或 PENDING | — |
| 任意態 | 個資清除完成 | — | REDACTED | 終態 |
| 任意態 | ⚠️ 系統內部設定（觸發條件官方未明文） | — | INVALID | 不可經 mutation 寫入；處置見下方「INVALID 孤兒態」條 |

- **INVALID 孤兒態處置**（本輪補證 2026-08-14）：三個官方源皆**不載進入條件**——Admin GraphQL enum 頁對 INVALID 只寫「internally-set and read-only」；Customer Account API 的 `EmailMarketingState` 對 INVALID 的描述是循環定義（「狀態為 invalid」），同樣無觸發；REST Customer 資源的**範例回應中實際出現 `state: "invalid"`**（證明此值在本尊真實資料可達）但全頁無定義；2022 consent 改版 changelog 亦未列舉。help 的 subscriber-list-management 只載「退信 → 自動抑制（suppression）」，**未**說抑制會改 consent state ⇒ 「INVALID＝硬退信/無效地址」是社群通說，**官方未明文，待實測**（用真實店打一個必退信地址觀察 state 變化）。
  - **我方裁定（解 enum 六值 vs 轉移表無入口的矛盾）**：enum 收全六值（本尊資料匯入/同步相容必需），但狀態機**不產生** INVALID——它是「可儲存、不可由我方轉移產生」的隔離態，唯一合法落庫通道＝**資料匯入/外部同步**（記 source=import）。任何 mutation 寫 INVALID 一律 reject（同 NOT_SUBSCRIBED/REDACTED）；待實測定案後若證實「退信 N 次 → INVALID」再補內部轉移。離開 INVALID 的路徑（顧客重新訂閱是否覆蓋）官方同樣未載 ⚠️ 待實測，實測前我方 reject 對 INVALID 態的一切轉移請求。
  - INVALID 態顧客與 suppression 清單同效：**不得對其發送行銷信**（保守裁定，寬鬆無據）。
- 硬退信（bounce）＝**送信抑制（suppression）**，官方描述為抑制清單而非改變 consent 態（取證 2026-08-14）⚠️ 抑制與 UNSUBSCRIBED 的欄位級關係文檔未明說。
- `CustomerMarketingOptInLevel` 三值（取證 2026-08-14）：`SINGLE_OPT_IN`／`CONFIRMED_OPT_IN`（提交後需完成中間步驟）／`UNKNOWN`。依 M3AAWG 定義。
- **多筆 consent 記錄以 `consentUpdatedAt` 最新者為準**（CustomerEmailMarketingConsentState 物件頁，取證 2026-08-14）；未給時間戳則以提交時間代入。
- `customerEmailMarketingConsentUpdate` 前置：**customer 必須有 email**。

### B.3 SMS 行銷同意（CustomerSmsMarketingState）

值域五值（取證 2026-08-14）：`NOT_SUBSCRIBED`／`PENDING`／`SUBSCRIBED`／`UNSUBSCRIBED`／`REDACTED`（**無 INVALID**，與 email 不同）。轉移表同 §B.2 去掉 INVALID 分支。

- `customerSmsMarketingConsentUpdate` 前置：**customer 必須有 phone**；錯誤碼 `INCLUSION`/`INTERNAL_ERROR`/`INVALID`/`MISSING_ARGUMENT`（取證 2026-08-14）。
- SMS consent 多帶 `consentCollectedFrom`：`SHOPIFY`／`OTHER` 兩值（取證 2026-08-14）。
- WhatsApp 為第三通道：admin 列表欄／大量編輯／webhook `customers_whats_app_marketing_consent/update` 皆存在（74 §1、webhook enum 取證 2026-08-14）；⚠️ Admin API 的 Customer 物件無公開 WhatsApp consent 欄位——狀態機推定同 SMS，未證實。

### B.4 productSubscriberStatus（派生態，不可寫）

六值（取證 2026-08-14）：`ACTIVE`（≥1 個 active 合約）／`PAUSED`（≥1 paused 且無 active）／`CANCELLED`／`EXPIRED`／`FAILED`（皆＝最後一份合約的收尾方式且無 active/paused）／`NEVER_SUBSCRIBED`。純由 subscription contracts 推導，我方同樣做成計算欄。

### B.5 個資清除（redaction）生命週期

```
正常 ──customerRequestDataErasure──▶ 待清除（admin 顯示「已提交刪除要求」）
待清除 ──customerCancelDataErasure──▶ 正常          ★可取消窗＝10 天（74 §4 實測；API 頁未載明天數 ⚠️）
待清除 ──窗過──▶ REDACTED：姓名/email/phone/地址移除，個檔與訂單保留；請求同步發給已安裝 apps 與銷售通路
```
清除中／已清除的顧客：不可合併、不可再被邀請；行銷態轉 `REDACTED`。scope：`write_customer_data_erasure`（取證 2026-08-14）。

### B.6 B2B 訂單三態流（buyer 側，由 location 設定分岔）

| location 設定 | 結帳按鈕 | 結果狀態 |
|---|---|---|
| 無 payment terms（預設「付款到期日：無」） | Pay now（輸卡） | 訂單 paid |
| Net terms（7/15/30/45/60/90 天） | Submit | 訂單 **Payment pending**，帶到期日；到期後標 **Overdue** 但仍可付；**到期不自動扣款**，vaulted 卡需商家手動請款 |
| Net terms＋deposit（Plus） | Submit now＋當場付訂金 | 卡收訂金＝**Partially paid**；手動收款方式＝Payment pending 直到入帳 |
| `checkoutToDraft: true`（僅允許草稿） | **Submit for approval** | 落 admin Drafts；商家 Create order 或買家收 invoice 付款後成單 |

（help b2b/checkout＋payment-terms，取證 2026-08-14；46b §6① 同源互證。）

## C. 業務規則與不變量

### C.1 唯一性與識別

- **email 每店唯一**：「一個 email 只能被一個 customer 使用」（help b2b adding-customers 原則同適用 D2C；取證 2026-08-14）。phone 同樣唯一（community/答覆一致；`customerSet` 官方明列 email/phone 為 **upsert 的 unique key**，取證 2026-08-14）。重複建立回 userError「已被使用」。
- 一個 profile **只有一個 email、一個 phone**（可隨時改）；phone 格式 **E.164**（如 `+16465555555`）。
- 建立最低要求：**name、phone、email 至少一項**（customerCreate，取證 2026-08-14）。
- `customerCreate` **不自動寄邀請信**；invite 是 classic accounts 的獨立動作。
- 落地：`customers` 表 UNIQUE KEY `(shop_id, email)`、`(shop_id, phone)`（NULL 允許多筆；MySQL unique 索引天然放行 NULL）。

### C.2 合併（merge）規則

- **保留哪個 profile 的判定序**（customerMerge，取證 2026-08-14）：①`overrideFields.customerIdOfEmailToKeep` 有效 → 該方；②恰一方有 email → 有 email 方；③雙方都有 email → 以帳號狀態＋行銷同意裁定（ENABLED 優先，INVITED 在特定條件可勝）；④都無 email → `customerTwoId` 方。`resultingCustomerId` 為權威結果。
- **非同步**：回 `job{id,done}`，需輪詢；scope `write_customer_merge`；先用 `customerMergePreview` 預覽。
- **阻擋合併的 `CustomerMergeErrorFieldType` 11 值**（取證 2026-08-14）：`COMPANY_CONTACT`／`CUSTOMER_PAYMENT_METHODS`／`DELETED_AT`／`GIFT_CARDS`／`MERGE_IN_PROGRESS`／`MULTIPASS_IDENTIFIER`／`OVERRIDE_FIELDS`／`PENDING_DATA_REQUEST`／`REDACTED_AT`／`STORE_CREDIT`／`SUBSCRIPTIONS`。（help 版八條＝74 §4；API enum 是超集，兩源一致無矛盾。）
- 合併聚合的資料：訂單、草稿、地址、email、phone、姓名、備註、標籤、稅務設定、時間軸事件、信用卡、顧客帳號、禮品卡、折扣（help，取證 2026-08-14；＝74 的「14 類」）。
- 邊界：合併後備註 ≤**5,000 字**（超限擋）、標籤 ≤**250 個**；**不可復原**。
- 併發要害：merge 進行中（`mergeInProgress`）再發 merge → `MERGE_IN_PROGRESS`；我方以 per-customer advisory lock＋idempotencyKey 落地。

### C.3 刪除與清除

- `canDelete=false` 的四阻擋（74 §4＋help，取證 2026-08-14）：①待清除（redaction pending）②是尚未送達的禮品卡排程收件人 ③曾有訂閱合約 ④有訂單。有訂單者只能走「清除個資」（§B.5）保留訂單記錄。
- 匿名化範圍：name/email/phone/address 移除；profile 與 order history 保留。

### C.4 行銷同意不變量

- **consent 是 append-only 事實**：每次變更記 `(state, optInLevel, consentUpdatedAt, source)`；最新 `consentUpdatedAt` 勝出。我方落地為 `customer_marketing_consents` 事件表＋customer 上的快取欄，三通道（email/sms/whatsapp）各一組。
- 商家手改（個檔「編輯行銷設定」）與顧客自助（退訂連結／帳號退出）同權重，皆產生新事實。
- double opt-in 是**店級設定**（Settings>Notifications），切換不回溯：啟用前已 SUBSCRIBED 者不需補確認（取證 2026-08-14）。
- 買 email 名單違反 ToS（本尊規則；我方寫入服務條款層，非程式硬限）。

### C.5 稅務豁免

- 兩層：`taxExempt: Boolean`（全免開關）＋`taxExemptions[]`（類別清單，僅在特定稅區生效）。
- `TaxExemption` enum 值域（取證 2026-08-14）：**加拿大 22 值**（BC 5／MB 3／NL 1／NS 2／ON 1／PE 1／SK 7／全國 `CA_DIPLOMAT_EXEMPTION`+`CA_STATUS_CARD_EXEMPTION`）＋**EU 1 值**（`EU_REVERSE_CHARGE_EXEMPTION_RULE`）＋**美國 51 值**（50 州+DC 的 `US_{州}_RESELLER_EXEMPTION`）＝**74 值** ⚠️（fetch 摘要自稱 129 與其逐項清單自相矛盾，以逐項 74 為準，實作前 CI 對 enum 快照）。
- admin UI 三選項：收取／不收取／除非符合豁免否則收取＋豁免下拉（74 §4）。
- B2B：免稅掛 **company_location**（`companyLocationAssignTaxExemptions`），不是 company、也不是 contact 的 customer 個檔。

### C.6 Segmentation query 語言

- 文法：`FROM customers SHOW … WHERE <條件> ORDER BY …`；UI 只開放 WHERE 編輯（SHOW＝欄位選擇器 UI 化，74 §1）。
- **運算子全集**（取證 2026-08-14）：`=` `!=` `>` `<` `>=` `<=`／`BETWEEN v1 AND v2`／`CONTAINS` `NOT CONTAINS`／`MATCHES` `NOT_MATCHES`（僅函式）／`IS NULL` `IS NOT NULL`／`AND` `OR`＋括號。**優先序：AND 先於 OR**，括號可覆蓋。
- 值格式：單引號字串；日期＝`YYYY-MM-DD`、位移（`-7d`/`-4w`/`-3m`/`-1y`）、具名（`today`/`yesterday`）；金額十進位不帶千分位。
- **屬性 20 個**（help reference 取證 2026-08-14；74 §2 實測 18＋help 補 2）：`abandoned_checkout_date`、`amount_spent`、`companies`、`created_by_app_id`、`customer_account_status`、`customer_added_date`、`customer_cities`（值格式 `國-區-市`）、`customer_countries`（ISO α2）、`customer_email_domain`、`customer_language`（ISO 639-1）、`customer_regions`（ISO 3166-2）、`customer_tags`（不分大小寫）、`email_subscription_status`、`first_order_date`、`last_order_date`、`number_of_orders`、`predicted_spend_tier`（`HIGH/MEDIUM/LOW`；銷售 >100 筆啟用，74 §2）、`product_subscription_status`（值域＝§B.4 六值的字串形）、`rfm_group`、`sms_subscription_status`。
- **`rfm_group` 值域 11 值**（取證 2026-08-14）：`CHAMPIONS`／`LOYAL`／`ACTIVE`／`NEW`／`PROMISING`／`NEEDS_ATTENTION`／`AT_RISK`／`ALMOST_LOST`／`PREVIOUSLY_LOYAL`／`DORMANT`／`PROSPECTS`（=無購買）。
- **函式 7 族**（MATCHES/NOT_MATCHES＋具名參數，全部可選）：`anniversary(metafield路徑)`、`customer_within_distance(coordinates, distance_km|distance_mi)`、`orders_placed(app_id, location_id, count, amount, sum_amount, date)`、`products_purchased(id, quantity, sum_quantity, date, tag)`（**id ≤500 個**）、`shopify_email.{bounced,clicked,delivered,marked_as_spam,opened,unsubscribed}(activity_id, count, date)`、`storefront.{product_viewed,collection_viewed}(id, date, count, tag)`（id ≤500）、`store_credit_accounts(balance, currency, next_expiry_date, last_credit_date)`。
- **metafield 條件**：`customer.metafields` 形，僅四型：日期時間／數值／文字／true-false（取證 2026-08-14）。
- 事件族資料保留 **26 個月**；**測試訂單與已刪除訂單不計入**（取證 2026-08-14；74 §2 同）。
- 掛接：折扣四型（Amount off products／orders、Buy X get Y、Free shipping）的顧客資格可選 segments——**自動折扣 ≤5 個 segment、折扣碼 ≤100 個**（help，取證 2026-08-14 ⚠️ 數字建議實測複核）；Email 行銷活動以 segment 為受眾；Flow 觸發「顧客已加入區段」。
- 系統預設 5 群＋匯出 CSV 兩格式（74 §3）。⚠️ 每店 segment 總數上限官方未載明。

### C.7 B2B 商務規則

- **價格解析公式**：先依 **catalog 解析優先序**取最高 specificity 層（company-location 直連 ＞ company-location market（SPECIFIED＞ALL）＞ region market（SPECIFIED＞ALL）＞ App Catalog——11 章 §C 目錄層優先序，兩章同一張表），`effective_price = min(price in 該層 catalogs)`——**min 只在同層內取** <!-- 2026-08-17 更正（PR #52 第 5 輪） -->：原式對「各 applicable catalog」全域取 min，B2B 議價 $100 會被通用零售 $80 蓋掉、繞過合約價。前提「商品至少在一個 applicable publication 發佈」否則不可見（46b §6③）。volume pricing 級距 ≤10、門檻遞增；套用後固定、不疊 catalog 折扣；折扣（discount）可疊在 catalog 價上（74 §6）。
- 數量規則三欄：遞增倍數／最低／最高（74 §6）。
- Payment terms 值域（help，取證 2026-08-14）：**無（預設，立即付款）／Net 7、15、30、45、60、90／Due on fulfillment／Fixed date（僅 draft order 可用）**。API 型別 `PaymentTermsType`：`FIXED`/`FULFILLMENT`/`NET`(+`dueInDays`)/`RECEIPT`/`UNKNOWN`（46b §6②）。Deposit＝百分比、**Plus 限定**。
- **到期不自動請款**：overdue 只是顯示態；vaulted 卡要商家手動 charge（取證 2026-08-14）。
- 結帳地址鎖定：預填且不可改，例外＝該 contact 是 Location admin，或 location 開 editable shipping address／「允許一次性地址」（取證 2026-08-14；74 §6 建立式勾選同源）。
- PO number 是 B2B 結帳一級欄位；多 location 的 contact 結帳先選 location，價格隨之切換（取證 2026-08-14）。
- **B2B 強制新版帳號**：「B2B customers can't use legacy customer accounts」（取證 2026-08-14）。
- 本尊 B2B 為 **Plus 限定**（dev store 例外）；不支援 subscriptions／pre-orders／try-before-you-buy（46b §6③）。
- 店員權限：「限制在指派地址」只過濾顧客/訂單/草稿/公司四頁，分析與行銷不過濾（74 §6）。
- 抵用金（store credit）：per-customer 上限 <US$15,000；B2B 個檔發放僅限其 D2C 身分使用（74 §4）。

## D. 關鍵流程

### D.1 建立顧客（admin）
操作者：staff。①填總覽（名/姓/語言/email+phone）→ ②行銷同意三通道勾選（需先取得顧客同意的提示文案）→ ③預設地址/稅務/備註/標籤 → 儲存。系統：唯一性驗證（email/phone 撞庫 → userError）→ 建檔（`verifiedEmail=true`）→ webhook `customers/create`。**不寄邀請**。失敗分支：email 已存在 → 引導開既有個檔。

### D.2 訂閱（storefront，double opt-in 開）
顧客提交 email → 系統建/找 profile → email consent `NOT_SUBSCRIBED→PENDING`＋寄確認信 → 顧客點連結 → `PENDING→SUBSCRIBED`（`CONFIRMED_OPT_IN`）→ webhook consent update → 進「Email subscribers」系統分群。失敗分支：不點＝永久 PENDING（不得對其發行銷信）。

### D.3 合併顧客
staff 於個檔「合併顧客」→ 選對象 → 系統 `customerMergePreview`（顯示保留方與衝突）→ 確認 → `customerMerge` 入 job queue → 完成後 webhook `customers/merge`＋被併方 id 失效（以 `resultingCustomerId` 為準）。失敗分支：任一方帶 §C.2 阻擋欄位 → `errorFields` 回列表，UI 顯示不可合併原因。

### D.4 個資清除
staff「清除個人資料」→ `customerRequestDataErasure` → 個檔掛「已提交刪除要求」→ 10 天窗內可 `customerCancelDataErasure` → 窗過執行匿名化 → 行銷態 `REDACTED`、apps/通路收到轉發請求。此後不可合併/邀請。

### D.5 建立與使用分群
staff 於編輯器寫 WHERE（autocomplete＋紅底線錯誤提示＋即時人數重估）→ 儲存（name+query）→ webhook `segments/create`。使用：Email 行銷活動受眾／折扣資格／Flow「顧客已加入區段」。成員數在詳情頁載入或 app 取用時重算；`customerSegmentMembers` 分頁讀取（≤1,000/頁，**≤250 通則登記例外** （2026-08-17 更正，PR #52 第 9 輪））。

### D.6 B2B 開通
①`companyCreate`（必填三塊：name＋首個 location＋主聯絡人）→ ②location 設 catalog/payment terms/tax/checkout（company 頁可批次落到每個 location）→ ③加 contact：選既有 customer 或新建 → 指派 role×location → 寄 B2B 開通信（可自訂；Flow 範本可自動化）→ ④顧客以新版帳號登入，見 B2B 價格與 location 切換。移除 contact：撤 location 權限或整體移除——**customer 個檔不刪，降回 D2C**（取證 2026-08-14）。

### D.7 B2B 下單（三路徑）
- **自助結帳**：登入 → 選 location → 加購（依 catalog 價與數量規則）→ 結帳（§B.6 分岔）。
- **submit for approval**：`checkoutToDraft=true` → 買家送審 → draft 落 Drafts → 商家改價/審核 → Create order 或寄 invoice；價格預設鎖定（bundles 不鎖）。
- **商家代下單**：Drafts>Create order → 選 B2B customer＋company location → **自動帶入該 location 的 catalog 價/payment terms/checkout 設定** → 加 PO number → 收款（輸卡／vaulted 卡／標記已付／寄 invoice 帶 terms）→ 成單。發出的事件：draft_orders/create → orders/create（含 purchasingEntity）。

## E. 跨模組耦合

### E.1 Webhook topics（值域，取證 2026-08-14）

| 域 | topics |
|---|---|
| Customer 核心 | `customers/create`、`customers/update`、`customers/delete`、`customers/enable`、`customers/disable`、`customers/merge`、`customers_purchasing_summary` |
| 標籤 | `customer_tags_added`、`customer_tags_removed` |
| 行銷同意 | `customers_email_marketing_consent/update`、`customers_marketing_consent/update`（=SMS）、`customers_whats_app_marketing_consent/update` |
| 付款方式 | `customer_payment_methods/create`、`/update`、`/revoke` |
| 帳號設定 | `customer_account_settings/update` |
| 分群 | `segments/create`、`/update`、`/delete`、`customer_joined_segment`、`customer_left_segment`（另有舊制 `customer_groups/*`＝saved search） |
| B2B | `companies/create|update|delete`、`company_locations/create|update|delete`、`company_contacts/create|update|delete`、`company_contact_roles/assign|revoke` |
| 隱私 | GDPR 三件套（`customers/data_request`、`customers/redact`、`shop/redact`，apps 必接） |

### E.2 依賴方向

- **Orders → Customers**：`amountSpent`/`numberOfOrders`/`lastOrder`/RFM 由訂單域 rollup 餵入（消費端）；分群的 `orders_placed()`/日期屬性同源。測試/已刪訂單剔除。
- **Customers → Discounts**：segment 是折扣資格的輸入（自動 ≤5、碼 ≤100）；segment 刪除對折扣的行為官方未載明 ⚠️（我方裁定：禁刪仍被折扣引用的 segment，回 userError）。
- **Customers → Checkout**：consent 勾選採集、B2B 結帳分岔（§B.6）、地址鎖定、PO number。
- **Customers → Tax**：taxExempt/taxExemptions 進稅額計算；B2B 走 location taxSettings。
- **Customers ↔ Markets**：B2B 用 `COMPANY_LOCATION` 型 market 反向匹配 location（`CompanyLocation.market` 已 deprecated，不建正向外鍵；46b §6⑥）。
- **Customers → Marketing/Flow**：Email 活動吃 segment；Flow 觸發 customer_joined_segment。
- **Privacy pack**：erasure 流程發「隱私事件」，落地細節（保留期、憑證）歸 jurisdiction pack（鐵律 11）。

## F. 落地對應

### F.1 對應倉庫文檔
`docs/research/74`（顧客線按鈕級 teardown，UI/交互權威）｜`docs/research/46b` §6（B2B API 面）｜`docs/specs/12`（租戶/認證/權限——顧客帳號認證另立，不與 staff 混用）｜`docs/specs/65`（金額單位邊界）｜`docs/research/28`（API 契約）｜`config/limits.yml` customers（10 鍵）＋b2b（3 鍵）已存在（74 §8），本章新增值需補鍵。

### F.2 本尊 vs 我方裁定差異清單

| # | 本尊 | 我方裁定 |
|---|---|---|
| 1 | `amountSpent`/`totalSpent` 用 MoneyV2 十進位 | 儲存 **integer cents ×100**（鐵律 3／65），序列化層才轉 MoneyV2；分群 `amount_spent` 比較在查詢層做單位換算 |
| 2 | 顧客指標（消費總額/訂單數）各處各查 | **數字同源**（鐵律 7）：個檔 KPI、列表欄、分群求值同一 rollup；RFM/predicted_spend_tier 屬分析域產出 |
| 3 | 單店模型 | 全表帶 `shop_id`＋複合索引 shop_id 開頭（鐵律 2）：customers/segments/companies/company_locations/company_contacts/role_assignments/consent 事件表全部適用；email/phone 唯一性是 **per-shop** 不是全域 |
| 4 | TaxExemption enum＝CA/US/EU 硬編 | 豁免類別清單屬 **jurisdiction pack 資料**（鐵律 11）：HK 基準無銷售稅→空清單；CA/US 清單降級為對應 pack 素材；`taxExempt` 開關為核心欄 |
| 5 | 禮品卡/抵用金全球通用 | HK SVF 單一用途豁免 ⇒ **不得跨租戶通用**（鐵律 11）；US$15,000 上限入 limits.yml 並可被 pack 覆蓋 |
| 6 | classic＋new accounts 並存（classic 已 deprecated，30 天可回退） | **只做新版帳號模型**（74 §7 已同步）：無密碼 6 位碼、無停用語義、自動重建；`state` 四值 enum 仍建欄（分群 `customer_account_status` 與匯入相容需要）但轉移動作（邀請/停用）遞延；Multipass 不做 |
| 7 | B2B＝Plus 方案限定 | 方案分層待定（openQuestion）；功能面 1:1：三物件模型、role×location 指派、checkoutToDraft、payment terms 值域照抄 |
| 8 | 泛用 UserError 無 code | 全 mutation typed code enum（鐵律 4 ours）；本章錯誤碼至少含 `TAKEN`（email/phone 重複）、`MERGE_IN_PROGRESS`、`CANNOT_DELETE`、`INVALID_STATE_TRANSITION`、`SEGMENT_QUERY_SYNTAX_ERROR` |
| 9 | segment 求值引擎（ShopifyQL 子集）閉源 | 自建 parser：先支援 20 屬性＋運算子全集＋AND/OR/括號；7 函式族與 metafield 條件分期（函式先做 orders_placed/products_purchased）；**enum 值不得自創**（12.3 值域窮舉） |
| 10 | GID `gid://shopify/*` | `gid://chilllove/{Customer|Segment|Company|CompanyLocation|CompanyContact}/{id}`（鐵律 4） |
| 11 | 分群人數「開頁才重算」 | 同語義照抄（lazy 重估＋快取欄），但重算走 Solid Queue job，不做常駐物化 |

### F.3 開發驗收要點

1. **唯一性併發**：同 email 並發建立兩顧客 → 恰一成功一 `TAKEN`（DB unique 兜底，非只靠應用層檢查）。
2. **consent 狀態機測試**：非法轉移（寫 `NOT_SUBSCRIBED`/`REDACTED`/`INVALID`）一律 reject；`consentUpdatedAt` 較舊的更新不得覆蓋較新事實；double opt-in 開關切換不回溯。**INVALID 隔離態專測**（§B.2 裁定）：①匯入通道（source=import）可落 INVALID、mutation 通道不可；②INVALID 態顧客不進任何行銷發送名單；③對 INVALID 態的一切轉移請求 reject（含重新訂閱，⚠️ 官方未載離開路徑，實測定案前保守擋）。
3. **merge**：11 阻擋條件各一 fixture；merge 中再 merge 擋；job 冪等（同 idempotencyKey 重放不重複合併）；合併後備註 >5,000／標籤 >250 擋。
4. **erasure**：10 天窗內 cancel 可復原；窗過後個檔匿名化但訂單金額 rollup 不變。
5. **分群**：AND/OR 優先序、括號、日期位移、`IS NULL`；測試訂單/已刪訂單不入計算；`products_purchased` >500 id 擋。
6. **B2B**：多 catalog **同層取最低價、跨層 specificity 優先**（含同 variant 三 catalog case，其中一 catalog 更特定的分支必測）；`checkoutToDraft` 轉向（不是擋）；Net+deposit 的 Partially paid 金額走 integer cents（**JPY/TWD/KRW 進矩陣**，65 §H）；contact 一 company 硬限；role 是 contact×location 指派（**不是 contact 全域屬性**——46b §6⑥ 點名易錯）。
7. **webhook/outbox**：E.1 全表 topic 經 outbox 發出，orders 域事件不得在 transaction 內直發。

## G. 來源

- https://shopify.dev/docs/api/admin-graphql/latest/objects/Customer（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerState（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/CustomerEmailMarketingConsentState（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerEmailMarketingState（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/CustomerSmsMarketingConsentState（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerSmsMarketingState（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerMarketingOptInLevel（取證 2026-08-14）
- https://shopify.dev/docs/api/customer/latest/enums/EmailMarketingState（取證 2026-08-14；INVALID 描述為循環定義，無觸發條件）
- https://shopify.dev/docs/api/admin-rest/latest/resources/customer（取證 2026-08-14；範例回應可見 `state: "invalid"`，無定義）
- https://shopify.dev/changelog/new-email-marketing-consent-for-customers-and-deprecated-fields（取證 2026-08-14；未列舉 state 值域）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerConsentCollectedFrom（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/customerEmailMarketingConsentUpdate（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/customerSmsMarketingConsentUpdate（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/TaxExemption（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerProductSubscriberStatus（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/customerMerge（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/CustomerMergeable（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerMergeErrorFieldType（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/customerCreate（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/customerSet（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/customerRequestDataErasure（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/customerCancelDataErasure（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/Segment（取證 2026-08-14）
- https://shopify.dev/docs/apps/build/marketing-analytics/customer-segments（取證 2026-08-14）
- https://shopify.dev/docs/apps/build/marketing-analytics/customer-segments/manage（取證 2026-08-14，經搜尋摘要）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyContact（取證 2026-08-14）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyContactRoleAssignment（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/manage-customers（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/customer-accounts（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/customer-accounts/new-customer-accounts（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/customer-accounts/upgrade（取證 2026-08-14）
- https://help.shopify.com/en/manual/promoting-marketing/create-marketing/shopify-messaging/email/subscriber-list-management（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/customer-segmentation/reference-guide/shopify-segments（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/customer-segmentation/reference-guide/components（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/customer-segmentation/reference-guide/metafield-segments（取證 2026-08-14，經搜尋摘要）
- https://help.shopify.com/en/manual/customers/customer-segmentation/create-customer-segments（取證 2026-08-14）
- https://help.shopify.com/en/manual/customers/customer-segmentation/manage-customer-segments（取證 2026-08-14）
- https://help.shopify.com/en/manual/discounts/discount-types/percentage-fixed-amount（取證 2026-08-14，經搜尋摘要）
- https://help.shopify.com/en/manual/b2b/companies-and-customers/adding-customers（取證 2026-08-14）
- https://help.shopify.com/en/manual/b2b/checkout（取證 2026-08-14）
- https://help.shopify.com/en/manual/b2b/checkout-and-orders/payment-terms（取證 2026-08-14）
- https://help.shopify.com/en/manual/b2b/checkout-and-orders/draft-orders（取證 2026-08-14）
- https://help.shopify.com/en/manual/b2b/catalogs（取證 2026-08-14）
- 倉庫：`docs/research/74-admin-customers.md`（2026-08-13 實測）、`docs/research/46b-shopify-docs-discounts-markets-b2b.md` §6
