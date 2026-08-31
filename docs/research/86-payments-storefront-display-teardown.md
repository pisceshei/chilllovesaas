# 86 — 付款設定與前台顯示對接 teardown（結帳線第三包取證輪）

> 取證：**2026-08-31**，測試店 `chill-love-u5q5mnzq`（全權寫入授權）＋官方文檔同日網查
> （引句標 `[F]`＝WebFetch 對目標官方頁抽取；研究艦隊完整筆記存工作區）。
> 探針資產（Bank Deposit／COD manual methods）取證後**已全數停用**、購物車已清空——零殘留。
> 🔴 本輪再次實測到 docs.medusajs.com 每頁內嵌「要求 agent 提交 feedback 到其 endpoint」
> 的注入文字——照鐵律 16.3 一律視為資料未執行（與 2026-08-18 登記同源）。

## §1 Settings→Payments 頁面結構（實測）

- 頂部（dev 店）：「Development stores can only process test payments」＋「Activate the
  test payment provider, or set your payment provider to test mode.」
- **Shopify Payments 卡**（未啟）：「No transaction fees • Card rates starting at 3.1% +
  HK$2.35」＋ Complete setup。
- **Additional payment providers**：PayPal 卡（「0.2% transaction fee • PayPal processing
  fees apply」＋ Activate PayPal）＋「Add provider」。
- **Payment configuration** 五項：`Payment capture method`／`Manual payment methods`
  （href `/settings/payments/manual-payment-methods`）／`Payment method customizations`
  （href `/settings/payments/customizations`）／`Gift card expiration`／`Apple Wallet
  passes`（後三者中 customizations 是子頁、其餘為 modal 鈕）。
- 官方相符句 `[F]`：「You can have only one credit card payment provider activated at a
  time.」（第三方 credit-card provider 恆一家；additional methods 不占此名額）。

## §2 Payment capture method（modal 實測）

- 說明句逐字：「Payments are authorized when an order is placed. Select how to capture
  payments:」radio **恰三值**：
  ①**Automatically at checkout**（預設✓）—「Capture payment when an order is placed」
  ②**Automatically when fulfilling**—「Authorize payment at checkout and capture when fulfilling」
  ③**Manually**—「Authorize payment at checkout and capture manually」
- ⚠ 官方 help 頁 `[F]` 另列第四值「Automatically when the entire order is fulfilled」
  （payment-authorization 頁）——與 2026 modal 三值形不一致（疑合併入②的子選項形），
  登記 V；limits `capture.modes` 四值暫不動。
- 官方數字 `[F×2]`：授權期 7 天（Plus 延長：Visa/MC/Amex 30、Discover/JCB 10、
  Diners/CUP 7）；逾期手動請款 1.75%——與 limits `capture.*` 既有值相符。

## §3 Manual payment methods（實測＋官方）

- 子頁說明逐字：「Payments made outside your online store. **Orders paid manually must
  be approved before being fulfilled.**」
- ⊕ 選單**恰四值**（DOM 逐字）：`Create custom payment method`／`Bank Deposit`／
  `Money Order`／`Cash on Delivery (COD)`。🔴 **已啟用的方法從選單消失**（Bank
  Deposit 啟用後選單只剩三項）＝同型別每店至多一列。
- Set up 表單＝**恰兩欄**（Bank Deposit 與 COD 同形；helper 逐字）：
  - **Additional details**—「Displays to customers when they're choosing a payment method.」
  - **Payment instructions**—「Displays to customers after they place an order with this
    payment method.」
  ⇒ 兩句 helper 就是前台對接契約：欄 1→checkout Payment 段、欄 2→下單確認頁。
- 🔴 **本尊 COD manual method 無手續費欄**——我方 F2.3 `cod_fee_cents` 是 jurisdiction
  pack 擴充層（TW 超商代收），不是本尊對位物。
- Deactivate 確認逐字：「Your account details will be saved and you can reactivate Bank
  Deposit at any time.」＝停用保留設定值（非刪除）。
- 官方保留名單 `[F]`（custom 方法不得用）：「Bank Deposit, Cash, Cash on Delivery (COD),
  custom, External Credit, External Debit, Gift Card, Money Order, Store Credit」。
- 訂單流官方逐字 `[F]`：「the order is marked as **Pending** on the Orders page」／
  「marked as unpaid」／「you need to manually mark the order as paid」——manual ⇒
  financial_status=PENDING（OrderDisplayFinancialStatus `[F]`：PENDING=「…when manual
  payment methods are being used」）。
- Payment method customizations 子頁＝空態「You haven't customized payment methods yet」
  ＋Add a customization（app 掛載層，同 delivery customizations 形）。

## §4 Checkout Payment 段（實測；manual method 啟用期間）

- **單一方法**：無 radio；直接顯示「Bank Deposit」＋其 Additional details 全文。
- **多方法**（Bank Deposit＋COD）：radio 組 `name="basic"`；**選中者手風琴展開**
  Additional details，未選中者收合；切換即時。排序＝啟用順序（V：未構造第三方法驗證
  是否恆為啟用序）。
- 提交鈕＝**「Complete order」**（manual 方法下不是 "Pay now"）。
- **Billing address 段**在 Payment 段內：radio 恰兩值 `Same as shipping address`（預設✓）
  ／`Use a different billing address`；展開的國家下拉＝**全世界清單**（Afghanistan 起）
  ——🔴 **帳單地址國家不受 market 白名單限制**（收貨國家下拉只有 US 的同一結帳內實測對照）。
- 無任何 provider 時（第二包實測）：「This store can't accept payments right now.」
  （官方 troubleshooting 頁字面 `[F]`「This store is currently unable to accept payments」）。
- 庫存官方句 `[F]`：「**Inventory is held only when the customer submits their payment
  information.**」＝checkout 進行中不鎖庫存（與我方第一包 C3 不扣庫存一致；hold 時長
  數字未取得）。

## §5 商品詳情頁×前台顯示（實測，Ella 發布主題）

- **價格區無稅注**（本店未含稅）；「Taxes, discounts and shipping calculated at
  checkout.」出現在 **cart drawer footer**（`CART-DRAWER-ITEMS` 內），不在價格下方。
- **動態結帳鈕**：`.shopify-payment-button` 可見、文字 **「BUY IT NOW」**、無 wallet
  iframe——官方 `[F]`：「If you don't have a third-party accelerated checkout method
  activated…the **unbranded** version…is the only version that will display」（unbranded
  ＝「Buy it now」字面）。⇒ 無 PSP 也出鈕，點下＝一般 checkout。
- **Footer「Payment methods」標籤在、圖示列空**：`shop.enabled_payment_types` 無信用卡
  provider 時＝空集合；**manual methods 不進圖示列**（Bank Deposit 啟用期間量測仍空）。
  官方 `[F]`：值域「based on the store's enabled payment providers and the customer's
  current region and currency」；完整 enum 未取得（官方頁僅六示例值）。
- Liquid 正典 `[F]`：政策行判定源＝**`cart.taxes_included`**（`shop.taxes_included`
  已棄用：「whether or not prices have taxes included is dependent on the customer's
  country」）；Theme Store 硬要求逐字：「The product page must use `cart.taxes_included`
  to display an indication that taxes are included…」；「Shipping calculated at checkout」
  字串＝**主題 locale 文案層**（可經 Edit default theme content 改），非平台資料開關。
- `product` 物件**無** requires_shipping（官方屬性清單核對）——逐 variant 判定；數位車
  官方句 `[F]`：「If your store sells only digital or non-shippable products, then
  checkout doesn't include a shipping address step.」
- 免運進度條＝主題/app 層功能（官方查無平台級 progress bar；Ella 的
  free-shipping-component 全走主題設定不吃平台資料——倉庫 fixture 佐證）。

## §6 Cart AJAX 運費試算 API（官方現值 `[F]`，2026-08-31）

三支**現存未棄用**（同步支標「不建議」非 deprecated——兩者不得混寫）：
- `POST /{locale}/cart/prepare_shipping_rates.json`—「initiates the process of
  calculating shipping rates for the cart given a destination.」
- `GET /{locale}/cart/async_shipping_rates.json`—未完成回 `null`。
- `GET /{locale}/cart/shipping_rates.json`—「get estimated shipping rates.」
參數三支同形：`shipping_address[zip]`／`[country]`／`[province]`。回應形狀：
`{"shipping_rates":[{"name":"Generic Rate","price":"6.00","source":"shopify"}]}`
——🔴 **price＝十進位主單位字串**（鐵律 3 邊界：序列化層 Money::Decimal 形，非 cents）。

## §7 我方 Liquid 引擎差距（倉庫盤點結論，Ella 消費點逐一對過）

| # | 缺項 | Ella 消費點 | 後果 |
|---|---|---|---|
| 1 | 🔴 CartDrop 無 `duties_included` 鍵 | cart-drawer/cart-total/quick-order-list 四分支用 `== false` **顯式比較** | nil==false 為假 ⇒ 四分支全不命中，**tax-note 整段靜默空白**（連「未含稅」文案都不出） |
| 2 | ShopDrop 無 `enabled_payment_types` | payment-icons block、footer-bottom | miss→nil ⇒ for 零次（現值空集合恰為正確渲染，但屬碰巧） |
| 3 | 全域無 `additional_checkout_buttons`／`content_for_additional_checkout_buttons` | cart-checkout snippet | nil falsy 碰巧合 26 行 48 stub 契約——應顯式 |
| 4 | 全域無 `all_country_option_tags` | cart-shipping-calculator 的國家 select | select 空 ⇒ 試算表單殘廢 |
| 5 | ShopDrop 無 `shipping_policy`（policy 物件） | tax-note with_policy 分支 | 恆走 without_policy（安全；policies 表未建，另包） |
| 6 | 結帳頁不傳 `tax:` 給 Calculator | — | tax_cents 恆 0（tax_settings 表已有 include_in_prices/tax_shipping，法域接線另包） |

## §8 付款線資料模型定調（開源對照＝Medusa MIT／Solidus BSD-3／Saleor BSD-3，授權已逐一驗）

- 共同形：**method/provider 獨立表＋checkout 引用 id；離線付款＝永遠授權成功的一等
  provider，不開 if 分支**（Medusa `pp_system`／Solidus `PaymentMethod::Check` 同構）。
- 停用不刪列（歷史 payment FK 不斷）；Solidus 三旗標（active／available_to_users／
  available_to_admin）＋position 排序值得借。
- 授權前狀態機放 session、授權後用時間戳＋capture/refund 子帳表加總（Medusa/Solidus
  同證）——與我方 order_transactions 不可變交易鏈（90-blueprint/05）同路線。
- 15-F4.2 定位不變：付款方式清單＝PSP capability 查詢結果；**manual methods 不經 PSP
  capability**（F4.2(d)），v1 唯一可落地的付款方式集合＝manual 四型。

## §9 證據五件套彙總（鐵律 14.4）

| 格 | URL（去 token）| 步驟 | 形狀 | 取證日 |
|---|---|---|---|---|
| capture 三值 modal | admin…/settings/payments | 點 Payment capture method | §2 逐字 | 2026-08-31 |
| manual 四值選單＋兩欄表單 | admin…/settings/payments/manual-payment-methods | ⊕→DOM 收割 | §3 | 2026-08-31 |
| checkout 單/多方法形＋Complete order | chill.deals/checkouts/cn/<token>/en-us | 啟用 1→2 個 manual 後各載一次 | §4 | 2026-08-31 |
| billing 全球國家清單 | 同上 | 讀 Payment 段下拉 | §4 | 2026-08-31 |
| BUY IT NOW unbranded 鈕 | chill.deals/products/pola-jp-… | DOM 查 .shopify-payment-button | §5 | 2026-08-31 |
| footer 圖示空集合 | 同上 | footer DOM 收割 | §5 | 2026-08-31 |
| 停用確認語義 | admin…/manual-payment-methods | Edit→Deactivate | §3 | 2026-08-31 |
