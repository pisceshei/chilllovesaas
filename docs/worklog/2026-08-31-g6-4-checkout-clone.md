# 2026-08-31 G6-4a：結帳頁 1:1 複刻（87 號六層實測 → 整頁重構）

## 已完成的工作 (Done)

- **87 號 teardown**（`docs/research/87-checkout-page-full-teardown.md`）：對測試店
  chill.deals 真實 checkout 完成六層實測——骨架/逐字文案/欄位與值域窮舉/元件 CSS
  量測（字重經 `font-bolder-style` 消融取真值；dpr=1.75 邊框折算已還原宣告值）/
  版面幾何/三寬度 RWD（同源 iframe 法；雙欄斷點 **1006px**、表單併欄 **586px**
  皆雙向逼近釘死）/network 誠實登記。
- **結帳頁整頁重構**（`checkouts_controller.rb` page_html 線）：header 髮絲線＋logo
  對位、手機 `<details>` accordion 摘要、雙欄殼（左白右 #f5f5f5、分欄線
  calc(50%+50px)）、Contact（email 浮標欄＋? icon＋行銷勾選＋Sign in 連結）、
  Delivery 全地址表單（浮動 label；US=State select 63 值域＋ZIP、他國回落
  Postal code）、Shipping method 占位盒/選項盒、Payment 方法盒（選中藍環＋
  redirect 句/manual details 面板；單一方法無 radio）、Billing 兩列＋different
  展開表單、全寬藍 Pay now/Complete order 鈕、footer、側欄摘要（64px 縮圖＋
  數量 badge＋Subtotal/Shipping/Total＋HKD code 前綴＋幣別符號形）。
- **單表單提交制**：新 `POST /checkouts/:token/submit`（整頁一次送出＝本尊形）；
  select/radio 變更由 3 行 JS 帶 `refresh=1` 自動儲存重渲染；前進時 server 驗必填
  → 307 保 POST 接 `/pay`（psp）或 `/complete`（manual）。既有 /delivery /payment
  端點與重驗邏輯原樣保留。
- **落庫面**：`checkouts.buyer_accepts_marketing` 欄（migration 20260831300000；
  欄名對位 Order API）；shipping_address json 收全欄（first/last/address1/2/city/
  zone/postal_code/phone）；billing_address json 收 mode＋billing_ 前綴欄；
  `line_items_snapshot` 增 `image_url`（product 首圖；舊快照缺欄回落灰佔位）。
- **checkout.css 全面重寫**：87 號量測值自寫（--ck-* tokens 段內逐項註 §錨）；
  QR/卡/錢包/thank-you 四頁沿用類保留。
- **spec**：新 `storefront_checkout_page_clone_spec.rb`（C1–C4/C6）；O10 改寫為
  /submit 前進閘；delivery/payment/psp spec 文案斷言同步英文。突變輪
  MUT-A（段序）/B2（US 條件欄）/C（refresh 前進）/D（billing 欄丟失）/E（行銷恆
  false）全紅後復原全綠。
- 🔴 **裁定登記（2026-08-31 使用者指令）**：「你必須完全複製 shopify 結帳頁面的
  所有內容…包括 css、字體、顏色、ui 佈局，而不是自行發揮」⇒ 本頁 UI 文字
  **連字面對齊本尊 en 版**（功能性 UI 標籤；鐵律 10 繁中主檔在本頁讓位於此裁定，
  zh locale 隨多語言線回補）；CSS 依總方案合規式落法＝量測值 1:1、代碼自寫。

## 修改的檔案與核心邏輯 (Changes)

- `docs/research/87-checkout-page-full-teardown.md`：新增（六層量測基準＋V-87-1~6）。
- `app/controllers/storefront/checkouts_controller.rb`：`submit` action；page_html
  重構＋contact/delivery_form/address_fields/shipping_method/rates_box/rate_row/
  payment/payment_option_row/billing/pay_button/summary/money_str/text_field/
  country_select/zone_select（US_ZONES 62 值域）/icon svg×3/footer_links/
  autosave_js/persist_contact!/persist_billing!/address_params/
  missing_required_fields；persist_delivery! 增 `address:`；頁內錯誤文案轉英文。
- `app/services/checkouts/country_names.rb`：新增（ISO 3166 英文短名字典）。
- `app/services/checkouts/create_from_cart.rb`：快照增 image_url（首圖批撈）。
- `db/migrate/20260831300000_add_buyer_accepts_marketing_to_checkouts.rb`＋schema。
- `app/assets/stylesheets/checkout.css`：主頁段全重寫；四頁沿用段保留。
- `config/routes.rb`：/checkouts/:token/submit。
- spec：`storefront_checkout_page_clone_spec.rb` 新增；order_creation O10 改寫；
  delivery/payment/psp 三檔文案斷言更新。

## 尚未完成或需注意的風險 (Pending / TODO)

- **V-87-1** 非 US 地址格式未實測（店只開 US market）——他國現回落通用形
  （City＋Postal code）；使用者在測試店加國家後可補量測輪。
- **V-87-2** 錯誤態三層未取得（合成 blur 不觸發、Pay 鈕點擊被權限層擋）——
  現行為 banner 形＋HTML required；待使用者手動觸發一次供量測後改行內紅框形。
- **V-87-3/4/5/6**：hover 態／付款品牌 icon 資產（需官方 brand kit，本輪純文字列）／
  billing country combobox 與電話國碼鈕展開形／? tooltip 浮層——均登記於 87 §8。
- Sign in 連結指向 `/account/login`＝**404**（買家帳戶線未建；視覺對位優先，
  帳戶線接上時改真路由）。`save_shipping_information` 勾選現不落庫（無帳戶可存）。
- `buyer_accepts_marketing` 尚未隨訂單成立傳導到 Order（G6-6 契約對位時接）。
- QR/卡/錢包/thank-you 四頁仍 zh 舊形——87 號只涵蓋結帳主頁，四頁對位另開包。
- 幣別符號＝display 層最小字典（HKD/USD→$ 等 11 幣），全表隨 markets locale 包。
- 文字欄不做 JS 自動儲存（整頁 POST 會打斷輸入）——內容在 Pay now 時一併落庫；
  無 JS 時 `<noscript>` Update 鈕補位。
