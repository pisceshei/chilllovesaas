# G6 步 8a：顧客模組寫入面（mutations＋consent 狀態機＋抹除鏈）

> 官方取證 2026-09-01（shopify.dev latest＝API 2026-07＋help；逐字引文見本檔各節）。
> 讀取面與管線地基＝G6-7（`docs/dev/g6-customer-pipeline.md`）；詳情頁與
> customerMerge＝步 8b。實測面（More actions 五值／marketing 三通道 modal／
> Manage addresses modal／Erase modal 逐字）：本檔 §5。

## 1. 行銷同意（事件表＋latest-wins 投影）

- **事實來源＝`customer_marketing_consents`（append-only；readonly? 機制擋 UPDATE）**；
  customers 的 `email/sms_marketing_state`＋legacy boolean 是投影快取
  （唯一寫入者＝`Customers::UpdateMarketingConsent`）。
- 官方狀態機：email 六值（`CustomerEmailMarketingState`——INVALID/NOT_SUBSCRIBED/
  PENDING/REDACTED/SUBSCRIBED/UNSUBSCRIBED）；SMS 五值（無 INVALID）。
  **可寫恰三值**（官方逐字 "Accepted values: SUBSCRIBED, UNSUBSCRIBED, and
  PENDING."）；NOT_SUBSCRIBED 官方明文 "This value cannot be set via the mutation"。
- **latest-wins**（官方逐字 "The customer's consent state reflects the consent
  record with the most recent consent_updated_at date."）：舊時間戳照 append
  （稽核）、不覆蓋快取；缺值＝當下（官方同規則）。
- 前置：email 線 "The customer must have an email address"；SMS 線 "must have a
  phone number"。opt_in_level 官方三值（single/confirmed/unknown）。
- checkout 生產端（UpsertFromCheckout）改走同一服務（source=checkout、
  single_opt_in；「只升不降」保留）。

## 2. 生命週期

- `customerCreate`：三擇一必填（官方底線 "Customer must have a name, phone number
  or email address"）；email/phone 唯一（撞名 ⇒ TAKEN，對位 REST 422 "has already
  been taken"）；consent 可隨建帶入（update 不收——官方導向專用 mutation）。
- `customerUpdate`：tags＝**覆寫**（官方逐字 "Updating tags overwrites any
  existing tags"）；已抹除者 NOT_EDITABLE。
- `customerDelete`：官方逐字 "You can only delete customers who haven't placed
  any orders."＋待抹除者擋下（help）。刪除連帶清 consent 事件與地址、
  checkout.customer_id 置 null。
- 地址四支（官方現行 mutation 面同名）：Create（`setAsDefault`；**首址自動預設**
  ＝ours 不變量，checkout 預填依賴）／Update／Delete（刪預設 ⇒ 讓給最舊存活者
  ——本尊行為未取證，ours 保守值）／UpdateDefaultAddress。

## 3. 個資抹除（排程制）

- `customerRequestDataErasure` ⇒ `redaction_scheduled_at`＝now＋
  `limits customer.erasure_cancel_days`（10；官方逐字 "you have 10 days to cancel
  the request"＋測試店 modal 實測 9/1→9/11 同值）。
- `customerCancelDataErasure`：窗內取消；已執行不可逆（官方 "Once the data is
  erased, it cannot be retrieved."）。
- `Customers::RedactDueJob`（recurring 每小時）：到點 ⇒ 姓名/email/電話/note 清空、
  地址簿刪除、兩通道 redacted 事件＋快取、anonymized_at 落戳；**顧客列與訂單保留**
  （官方 "the profile and order history remain in your Shopify admin."）。
  ⚪ order 層欄位遮蔽（orders.email/地址快照）＝91 §3.52。

## 4. 測試映射（20.2⑤）

`marketing_consent_spec`（C1 三值閘/C2 前置/C3 latest-wins/C5 append-only/
C6 checkout 首源）＋`redact_due_job_spec`（R1 全清+R2 訂單保留）＋
`customer_mutations_spec`（M1 TAKEN/M2 底線/M3 tags 覆寫/M4 訂單擋刪/
M5 預設讓渡/M6 抹除窗）。突變輪 MU1–MU9 全紅＋canary。

## 5. 實測面（2026-09-01 親點；詳情頁 UI 落地＝步 8b）

- KPI 四格：Amount spent／Orders／Customer since／**RFM group**（Active）。
- More actions 恰五值：Issue store credit／Merge customer／Request customer data／
  Erase personal data／Delete customer（紅）。
- Contact information「⋯」恰五值：Edit contact information／Manage addresses／
  Edit marketing settings／Edit tax details／Add to company。
- Edit marketing status modal：說明句逐字 "Indicate which marketing channels the
  customer has agreed to receive messages from:"；**三通道**（Email／SMS／WhatsApp），
  SMS/WhatsApp 無電話 ⇒ toggle disabled＋"Phone number not provided"。
- Erase personal data modal 逐字："Any information that can be used to identify
  this customer will be erased. Information includes: Name, address, email, IP
  address, credit card number."＋"The customer data will be erased on Friday,
  September 11, 2026. The customer's orders will still be visible for business
  reporting purposes. You can cancel the process until that date. Once the data
  is erased, it cannot be retrieved."（9/1 請求→9/11＝10 天窗）。
- Edit customer modal：First/Last Name＋Language（"This customer will receive
  notifications in this language."）＋Email＋Phone（國碼選擇器）。
  ⚪ notification language 欄（customers.locale）隨步 8b。
