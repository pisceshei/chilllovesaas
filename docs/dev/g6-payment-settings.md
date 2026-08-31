# G6-3（步 2）付款設定本體——capture 模式／manual 付款方式／provider 啟用狀態機

> 對位正典：`docs/research/86-payments-storefront-display-teardown.md` §1–§3（實測＋官方雙源）。
> 憑證與逐方法 toggle（G6-3 前半）＝`docs/dev/g6-payment-provider-credentials.md`；本篇是其續章。

## 1. Payment capture method（86 §2）

### ①這是什麼
Settings → Payments → Payment configuration 清單第一列。點開＝modal，radio **恰三值**
（86 §2 DOM 逐字）：Automatically at checkout（預設）／Automatically when fulfilling／
Manually。說明句逐字：「Payments are authorized when an order is placed. Select how to
capture payments:」。

### ②具體功能（值域・預設・條件）
- 儲存欄：`shops.payment_capture_method` string(40)，default `automatic_at_checkout`
  （migration `db/migrate/20260901030000_add_payment_capture_method_to_shops.rb`）。
- 值域正典＝`config/limits.yml` `capture.modes`（**四值**）；`capture.plus_only_modes`
  （`automatic_per_fulfillment`）在我方**誠實拒絕**（`FEATURE_NOT_ENABLED`）——我方無方案
  分層，靜默收下一個沒有行為的設定值比拒絕更糟。modal 只展示三值（與本尊 2026 modal 同形）。
- 讀端 `paymentCaptureMethod`（root query）；寫端 `paymentCaptureMethodUpdate`
  （`app/graphql/mutations/payment_capture_method_update.rb`）：值域外 ⇒ `INCLUSION`。

### ③怎麼做出來
單欄 update（無狀態機）；授權＝登入態（與 `shopPaymentProviderSet` 同門檻——settings
細粒度權限隨 M5 RBAC 展開）。

### ④跨功能影響（🔴 誠實登記）
G6-1 的 Airwallex 流是**即時 capture**（intent 直接 confirm，無 authorization 段）⇒
本欄目前**設定面完整、行為面待 authorization 流**。`capture.modes` 的行為消費者
（授權→請款兩段式、`authorization_days` 逾期）隨 orderCapture 完整版落地；在那之前
改這個設定不改變結帳行為。此缺口在 `docs/specs/91-pit-register.md` §3 登記。

## 2. Manual payment methods（86 §3）

### ①這是什麼
子頁 `/admin/settings/payments/manual-payment-methods`
（`app/frontend/admin/pages/SettingsManualPaymentMethodsPage.tsx`）。說明句逐字：
「Payments made outside your online store. Orders paid manually must be approved before
being fulfilled.」

### ②具體功能
- ⊕ 選單**恰四值**（86 §3 DOM 逐字序）：Create custom payment method／Bank Deposit／
  Money Order／Cash on Delivery (COD)。🔴 **已存在的內建型別從選單消失**（model
  `single_builtin_per_shop` 承載；含停用中的——那些走 Activate 不走新增）。
- setup 表單**恰兩欄**（helper 逐字＝前台對接契約）：`additional_details` → checkout
  Payment 段；`payment_instructions` → 下單確認頁。custom 另有 name 欄，擋官方保留
  名單九名（model `custom_name_not_reserved`，小寫正規化比對）。
- Deactivate＝`active=false` 不刪列（86 §3 確認句逐字「Your account details will be
  saved and you can reactivate … at any time.」）；隨時 Activate 還原。
- GraphQL：query `shopPaymentMethods`（含停用列）；mutations
  `shopPaymentMethodCreate/Update/Activate/Deactivate`
  （`app/graphql/mutations/shop_payment_method_*.rb`）。錯誤碼共用一組
  `ShopPaymentMethodUserError`（S1 publication 同線共用先例）。

### ③怎麼做出來
model 驗證是唯一真相（mutation 只翻譯 `record.errors` 首條為 userError）；
內建重複／保留名都在 model 層擋，DB `builtin_guard` 是第二道防線。

### ④跨功能影響
checkout Payment 段清單與 `payment_method_snapshot`（結帳線第三包既有）；manual 單
`financial_status=pending`（86 §3 官方逐字）；確認頁吃 `payment_instructions` 快照。

## 3. Provider activation 狀態機（G6-3 步 2 新裁定）

### ①這是什麼
`ShopPaymentProvider.status`（`inactive`/`active`）從「恆 inactive 的擺設」升格為
**結帳曝光的唯一真相**。

### ②具體功能
- `shopPaymentProviderActivate`：前置＝`api_secret_fingerprint` 非空（無憑證 ⇒
  `INVALID_STATE`；未落列 ⇒ `NOT_FOUND`）。
- `shopPaymentProviderDeactivate`：翻回 `inactive`，**憑證保留**（與 manual method 的
  deactivate 同語義）。
- 🔴 消費端同批改：`Storefront::CheckoutsController#configured_provider` 由
  「有指紋即啟用」改為 `status == "active"`（`app/controllers/storefront/checkouts_controller.rb`）
  ——admin 的停用鈕自此有真實效力。三個消費點（付款段選項／pay／pay_status）同一函式。

### ③部署遷移（🔴 一次性）
既有已設憑證的店在本包部署後 status 仍 `inactive` ⇒ 結帳頁 PSP 選項會消失。
部署後跑一次性生產腳本把「有指紋的列」翻 `active`（worklog 記指令與輸出）。

### ④跨功能影響
`shopPaymentProviderSet`（存憑證）不再隱式啟用；PayPal pack 落地時同一狀態機直接適用。

## 4. 測試映射（20.2⑤）

`spec/graphql/payment_settings_spec.rb`（S1–S6 逐格）＋
`spec/requests/storefront_psp_payment_spec.rb`（M4 守衛＋既有 Q1–Q10 setup 顯式
`status: "active"`）＋前端 `SettingsPaymentsPage.test.tsx`／
`SettingsManualPaymentMethodsPage.test.tsx`。突變輪 7/7 殺（M1–M7，含 canary），
證據＝worklog。
