# 89 號：通知系統 teardown（Settings › Notifications；步 6 正典）

> 取證：2026-09-01。雙源＝測試店 chill-love-u5q5mnzq 親點實測（六層；本檔 §1–§3）
> ＋官方 help/shopify.dev 逐字（§4–§6；每句帶 URL）。help.shopify.com 對抓取端有
> Cloudflare 驗證，官方引文經 WebFetch 兩次獨立抓取比對，僅單次擷取者逐條標明。
> 抓取頁面未發現指令型注入文字（鐵律 16.3 掃過）。

## §1 頁面架構（實測）

- 路由（真實 href 導航取得）：
  - `/settings/notifications`——Sender email 欄（現值 eshop@chilling.com.hk；helper
    「The email your store uses to send and receive emails from your customers」）＋
    四入口列：Customer notifications／Staff notifications／Fulfillment request
    notification／Webhooks。
  - `/settings/notifications/customer`——模板清單（§2）；右上鈕「Customize email
    templates」（全店 logo／accent 外觀層）。
  - `/email_templates/{key}/preview`——模板預覽頁；header 動作恰三個：**Send test／
    Translate／Edit code**；預覽面板有語言下拉（English ⌄）＋Subject 行。
  - `/email_templates/{key}/edit`——編輯頁；表單恰兩欄：**Email subject**（單行）＋
    **Email body (HTML)**（Liquid 代碼編輯器）；底部 **Revert to default** 鈕
    （未修改時 disabled）；info 條「You can use liquid variables to customize your
    templates.」＋「You can customize the look and feel across all email notifications
    from the Customize email templates page.」

## §2 Customer notifications 模板清單（實測全量；2026-09-01 DOM 逐字）

分組與模板（〔T〕＝該列有 enable toggle；其餘無 toggle）：

| 分組 | 模板（副標逐字） |
| --- | --- |
| Order processing | Order confirmation（Sent when a customer places an order）／Draft order invoice／Shipping confirmation（Sent when you mark an order as fulfilled） |
| Local pick up | Ready for local pickup／Picked up by customer |
| Local delivery | Order out for local delivery〔T〕／Order locally delivered〔T〕／Order missed local delivery〔T〕 |
| Gift cards | New gift card／Gift card receipt |
| Store credit | Store credit issued |
| Order exceptions | Order invoice／Order edited／Order canceled／Order payment receipt／Order refund／**Abandoned checkout**（Sent when a customer doesn't finish checking out）／Order link／Fulfillment invoice |
| Payments | Payment error／Pending payment error／Pending payment success／Payment reminder |
| Point of Sale | POS abandoned checkout／POS email to customer／POS exchange receipt／Return receipt |
| Shipping updated | Shipping update／Out for delivery〔T〕／Delivered〔T〕 |
| Returns and cancellations | Return created／Order-level return label created（US only）／Return request approved／Return request declined／Request received／Cancellation request declined |
| Accounts and outreach | Customer account invite／Customer account welcome／Customer account password reset／Customer payment method add request／B2B access email／B2B location update payment method／Contact customer／Customer email address change confirmation |
| Marketing double opt-in | Customer marketing confirmation〔T〕＋Send to 勾選（New email subscribers／New SMS subscribers） |
| Remarketing with Shop | Cart reminder〔T〕／Back in Stock〔T〕／Price drop〔T〕／Browse abandonment〔T〕（Shop app 層，非模板列） |

- ⚠ V-236：官方 help 列可停用者含 Order canceled／Order refund／Shipping
  confirmation／Shipping update（§4 引文），但 2026 admin 清單這幾列**無 toggle**
  ——兩源不一致，登記 V 待複測；我方 v1 不做模板停用開關。

## §3 v1 三模板實測值（步 6 射程）

| 模板 | template key（URL 實測） | 預設 subject | body 要素（預覽） |
| --- | --- | --- | --- |
| Order confirmation | `order_confirmation` | `Order {{name}} confirmed`（edit 頁 subject 欄逐字） | 店名＋ORDER #9999＋「Thank you for your order!」＋View your order／Track order with shop 鈕＋or Visit our store＋Order summary（行項圖＋名×量＋金額）＋Shipping items（Estimated delivery） |
| Shipping confirmation | `shipping_confirmation` | 預覽渲染「A shipment from order #9999 is on the way」 | 「Your order is on the way. Track your shipment to see the delivery status.」＋UPS tracking number: 連結＋Items in this shipment |
| Abandoned checkout | `abandoned_checkout_notification` | 預覽渲染「Complete your Purchase」 | 「You left items in your cart」＋「Hi Steve, you added items to your shopping cart and haven't completed your purchase. You can complete it now while they're still available.」＋Items in your cart 鈕＋or Visit our store＋Complete your purchase 行項＋「Don't want to receive cart reminders from us? Unsubscribe」 |

- Order confirmation 的 body 開頭實測（edit 頁）：`{% assign delivery_method_types =
  delivery_agreements | map: 'delivery_method_type' | uniq %}`——證實 body 上下文
  是**攤平變數**（`delivery_agreements` 裸名，無 `order.` 前綴；§5 官方句同）。

## §4 官方：清單與停用性（help 逐字；取證 2026-09-01）

- <https://help.shopify.com/en/manual/fulfillment/setup/notifications/customer-notifications>：
  - "Most customer notifications are sent automatically and can't be deactivated."
  - 可停用列舉：Order canceled／Order refund／Shipping confirmation／Shipping
    update／Out for delivery／Delivered。
  - "Notifications sent from the Shop app for tracking updates and order statuses
    can't be deactivated or edited by merchants."
- 編輯器（<https://help.shopify.com/en/manual/fulfillment/setup/notifications/customizing-notification-template>）：
  - "Edit the **Email subject** and **Email body (HTML)** of the email message."
  - "To preview your unsaved changes click **Preview**."
  - "To send the notification as a test email, click **Send test email**. The email
    is sent to the account that you used to log in to the Shopify admin."
  - "Before you can edit the body and the subject heading of your email
    notifications, you need to confirm your sender email address."
  - Revert 兩目標："You can revert to either your previous version or the default
    version of an email notification template."＋"When you revert to the previous
    or default version, you replace only the template's content. Any customizations
    that you made to the logo or color of your email notifications aren't changed."

## §5 官方：Liquid 變數（<https://help.shopify.com/en/manual/fulfillment/setup/notifications/email-variables>；取證 2026-09-01）

- 總則："All templates in the Shopify admin have access to the properties of their
  corresponding order. All variables are available to use in any notification
  template, but some variables might not be applicable if the data isn't yet
  available when the notification is sent."
- 🔴 **攤平規則**（渲染器核心契約）："The order object isn't referenced by name in
  email templates. For example, instead of using `{{ order.shipping_method.title }}`
  in your order confirmation email template, you should use
  `{{ shipping_method.title }}`."（SMS 模板才帶前綴。）
- Order 屬性（逐字描述）：`name`＝"Typically this is a pound symbol followed by the
  `order_number`."；`order_name`＝"Same as name."；`order_number`＝"Shop unique
  number of the order, without the pound # prefix…"；`subtotal_price`＝"Sum of the
  order's line-item prices after any line-item discount or cart discount has been
  deducted."；`total_price`＝"Total of the order (subtotal + shipping cost -
  shipping discount + tax)."；`order_status_url`＝"Returns the link to the order
  status page for this order."；`shop.name`＝"Name of your store."；`line_items`＝
  "List of all line items in the order."（單次擷取）。
- Fulfillment 屬性（shipping confirmation）：`fulfillment.tracking_company`＝"The
  company doing the tracking."；`fulfillment.tracking_numbers`＝"A list of tracking
  numbers."；`fulfillment.tracking_urls`＝"A list of tracking URLs."；
  `fulfillment.item_count`（單次擷取）。
- 棄單恢復連結＝裸 `{{ url }}`——逐字錨（折扣頁預設模板片段，
  <https://help.shopify.com/en/manual/discounts/discounts-for-abandoned-checkout-recovery-emails>）：
  `<a href="{{ url }}" class="button__text">Items in your cart</a>`。
  變數參考頁上裸 `url` 的描述行＝未取得；`unsubscribe_url`＝未取得。
- 全店外觀屬性（單次擷取）：`shop.email_logo_url`／`shop.email_logo_width`／
  `shop.email_accent_color`（Customize email templates 層）。

## §6 官方：sender email／棄單語義／API 面（取證 2026-09-01）

- Sender email（<https://help.shopify.com/en/manual/intro-to-shopify/initial-setup/setup-your-email>）：
  ＝"the customer-facing address that's listed in **Settings** > **Notifications**"，
  作為 "**From** email address when your customers receive automatic notification
  emails, order confirmation emails, and any marketing emails sent from your store"。
  未認證網域改寫（<https://help.shopify.com/en/manual/intro-to-shopify/initial-setup/email-rewrites>）：
  "If you take no action, then your sender email will be rewritten to
  `store+123@shopifyemail.com`"；CNAME 認證 "configure both DKIM and SPF
  authentication for your sender email"；DMARC 需另設（最低 "v=DMARC1; p=none"）。
- 棄單（<https://help.shopify.com/en/manual/promoting-marketing/create-marketing/abandoned-checkouts>）：
  - 判定："A checkout is considered abandoned if it remains incomplete for more
    than ten minutes after the customer has provided their email information."
  - 連結："Each email contains a link to the customer's abandoned cart, allowing
    them to complete their checkout if they choose."
  - 自動寄送已遷 Messaging automation（Send after 可配置；migrate 頁見
    "a 10 hour wait time before the email is sent to customers"；值域枚舉＝未取得）；
    模板本體仍在 Settings > Notifications（"Under **Orders**, click **Abandoned
    checkout**."）。六種抑制情形見原頁（付款錯誤／不可運送／只留電話／無可購商品／
    全免費且無運費／寄送前已完成）。
- API 面：Admin GraphQL **無 notificationTemplate 型別**（shopify.dev 全站搜尋陰性；
  官方明文聲明＝未取得）。翻譯層例外：TranslatableResourceType `EMAIL_TEMPLATE`＝
  "An email template. Translatable fields: `title`, `body_html`."
  （<https://shopify.dev/docs/api/admin-graphql/latest/enums/TranslatableResourceType>）
  ⇒ 我方 notificationTemplates API 是 ours 加嚴（admin SPA 唯一客戶端，鐵律 4 同理）；
  ML 線日後把模板納 RESOURCE_TYPES 時以 EMAIL_TEMPLATE 對位。
  棄單資料另有 `AbandonedCheckout.abandonedCheckoutUrl`＝"The URL for the buyer to
  recover their checkout."（步 7 對位）。

## §7 我方 v1 裁定（步 6 射程；差異登記）

1. **三模板先行**：order_confirmation／shipping_confirmation／abandoned_checkout
   （key 對位本尊 URL key；棄單 key 我方去 `_notification` 尾綴＝ours 簡化）。
2. **預設模板自寫**（鐵律 9：不抄本尊模板代碼；變數名照 §5 官方契約攤平）。
3. **DB＝customization overlay**：無列＝平台預設（隨版本部署）；notificationTemplateUpdate
   upsert；revertToDefault ⇒ 刪列（官方 Previous 版本目標＝⚪ 後置）。
4. **寄送鏈**：outbox 消費者（orders/create→訂單確認；order.fulfilled 且 notify=true
   →出貨通知）→ Solid Queue job → mailer（鐵律 5 交易外 IO）。棄單觸發器＝步 7。
5. ⚪ 後置：模板停用開關（V-236）／Send test／per-template Translate／全店
   logo+accent 外觀層／sender email 確認流（官方前置）／unsubscribe 連結。
