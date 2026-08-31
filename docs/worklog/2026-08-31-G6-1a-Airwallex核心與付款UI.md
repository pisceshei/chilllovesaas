# 2026-08-31 — G6-1a：Airwallex 核心（client／intent／webhook／可觀測）＋付款設定 UI 照 86 號重做

## 已完成的工作 (Done)

- **憑證實測（使用者已存 sandbox 憑證後）**：demo/正式兩主機皆 401 credentials_invalid
  ＝該組 Client ID＋API key 本身無效（長度 22／96、字元集正常）——已回報使用者三個
  檢查點（demo 與正式是獨立帳號體系／同組條目配對／重貼即覆蓋）。**sandbox 端到端
  實測待使用者修正憑證後以 `Psp::Airwallex::SandboxSmokeTest.run` 一鍵重跑。**
- **`Psp::Airwallex::Client`**：login→Bearer（expires_at 為準＋safety 提前重登）、
  host 依 environment（limits `psp_integration.airwallex.hosts`；sandbox host 已由
  401 實測證實 endpoint 正確）、x-api-version pin（帳號現值 2026-02-27，使用者截圖
  取證）、🔴 **金額 JSON number 原文注入**（BigDecimal 專收；整數值去 `.0` 尾——
  零小數幣別「帶小數即形不符」）、transport 可注入（不引 HTTP gem，鐵律 1）。
- **`PaymentIntents`**（create／get／`confirm_with_test_card`——production 一律 raise，
  PAN 只准 sandbox 走 API）＋`SandboxSmokeTest`（HKD 1.00 全鏈：Money 契約出口→
  create→官方測試卡 confirm→終態）。
- **Webhook 端點 `POST /webhooks/airwallex`**（🔴 URL 已對外承諾——使用者已在
  Airwallex 後台以此 URL 建訂閱）：HMAC-SHA256(secret, timestamp+raw) hex＋
  secure_compare fail-closed；`psp_webhook_events` 收件匣（event_id 冪等，重複投遞
  200；消費＝G6-1b）；模型層唯一性先於 DB 兜底命中時同樣回 200（實測踩中）。
- **65 §K.8–9 可觀測落地**（dev 篇章的既有 TODO 收口）：每次 X7/X8 轉換發
  `money.psp_conversion` 事件（psp/amount_format/currency/位數/storage_cents/
  wire_value/divisibility），失敗發 `money.psp_conversion_failure`（severity=P1）；
  subscriber 寫 JSON 日誌。
- **UI 照 86 §1 重做（使用者裁定「和 Shopify 一樣」）**：主頁三區（test-mode 橫幅／
  主收單 Airwallex 卡＋method chips／Additional providers PayPal 卡／Payment
  configuration 清單——manual/customizations 標「即將推出」保版面完整）＋
  **provider 詳情頁**（About／憑證／逐 method toggle——字典走新 query
  `pspMethodDictionary`＝limits `psp_method_dictionary` 平台層唯一來源）。
  `shopPaymentProviderSet` 增 `enabledMethods` 參數（⊆ 字典驗證——存顯示名會讓
  G6-1 webhook 白名單複驗永遠不命中）。
- **本地親眼驗證**：dev server＋預覽帳號實際登入走過兩頁（`*.localhost` host——
  瀏覽器窗格對非 localhost 網域擋子資源，lvh.me 不可用；量測坑記錄）。
- 測試：後端 32（client 5／intents 3／webhook W1–W6／觀測 3／provider P1–P9／model 6）
  ＋前端 294/294（payments 7 格）；突變 MUT-A~E 全紅（驗簽恆真／金額變字串／
  整數帶 .0 尾／拔 sandbox 守衛／拔 instrument）＋G6-3a 補的 P8 反向格。

## 修改的檔案與核心邏輯 (Changes)

- `app/services/psp/airwallex/{client,payment_intents,sandbox_smoke_test}.rb`（新）
- `app/controllers/webhooks/airwallex_controller.rb`＋`config/routes.rb`（webhook 路由）
- `db/migrate/20260831270000_create_psp_webhook_events.rb`＋`app/models/psp_webhook_event.rb`
- `app/models/money.rb`（instrument_conversion/instrument_failure＋兩處 rescue 接線）
  ＋`config/initializers/money_conversion_logging.rb`（新）
- `config/limits.yml`（`psp_integration.airwallex`＋`psp_method_dictionary` 兩區塊）
- `app/models/shop_payment_provider.rb`（method_dictionary＋enabled_methods ⊆ 字典）
  ＋`app/graphql/`（PspMethodDictEntryType＋query 註冊＋mutation enabledMethods 參數）
- `app/frontend/admin/pages/SettingsPaymentsPage.tsx`（重寫為 86 §1 主頁）＋
  `SettingsPaymentProviderPage.tsx`（新詳情頁）＋App 路由＋i18n 五語言＋admin.css
  （banner/provider-row/method-chip/config-list 系列，全 tokens）
- specs：`spec/services/psp/airwallex/*`＋`spec/requests/psp_webhook_airwallex_spec.rb`
  ＋`spec/models/money_observability_spec.rb`＋既有 provider spec 增 P8/P9

## 尚未完成或需注意的風險 (Pending / TODO)

- 🔴 **等使用者修正 Airwallex 憑證**（三檢查點已回報）→ 一鍵重跑 SandboxSmokeTest
  ＝V-132 沙箱實測收口＋webhook 簽章實投驗證。
- G6-1b：webhook 消費（payment_intent.succeeded→`Orders::CreateFromCheckout` 冪等
  入口＋markAsPaid 補發 orders/paid）＋結帳頁卡欄位/QR（components-sdk，G6-4 前奏）。
- capture method 列現值為靜態文案（真 modal 隨 G6-3 本體）；Deactivate／activation
  狀態機同。
- Airwallex `env` demo/sandbox SDK 參數矛盾＝待 sandbox 實測定值（V 維持）；
  x-api-version 以帳號現值 pin，官方版本語義頁未另查（登記）。
- 瀏覽器窗格量測坑：非 localhost 網域（含 lvh.me）子資源被擋——本地 admin 預覽
  一律 `CHILLLOVE_BASE_HOST=localhost`＋`*.localhost` host。
