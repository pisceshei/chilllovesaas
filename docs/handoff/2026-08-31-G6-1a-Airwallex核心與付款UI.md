# Handoff — G6-1a Airwallex 核心＋付款 UI（2026-08-31）

## ① 我改了什麼
branch `g6/airwallex-core`，base＝main `6228ec3`（#219 之後）。兩條使用者指示：
「先測試 Airwallex」（→client/intents/webhook/smoke-test＋憑證實測 401 回報）＋
「UI 和 Shopify 一樣」（→主頁照 86 §1 三區＋provider 詳情頁 toggle 形）。
清單見同名 worklog。外部狀態：使用者已在 Airwallex 後台建 webhook 訂閱指向
`https://demo.chilling.com.hk/webhooks/airwallex`（🔴 路徑已承諾不得改）。

## ② 為什麼這樣改
- 金額原文注入在 client 單點（不散落 adapter）：BigDecimal→JSON number 是 R7 的
  wire 契約（65 X7c），`to_json`/`to_f` 兩條錯路都在此擋。
- 整數去 `.0` 尾：JPY 等零小數幣別「帶小數即形不符」；A6c 保證 scale 合法 ⇒
  frac.zero? 判定即足。
- webhook 收件匣先行、消費後行：驗簽與冪等是安全邊界（先立），入帳走 F5 冪等
  入口（G6-1b）——避免在 webhook 請求內做外部 IO／複雜交易（鐵律 5）。
- 被推翻的假設：①lvh.me 可作本地預覽 host（窗格擋非 localhost 子資源）；
  ②json 收件匣重複投遞只會走 RecordNotUnique（模型層 uniqueness 先命中→
  RecordInvalid，雙 rescue）。

## ③ 還有什麼沒解決
worklog Pending 五項；核心阻塞＝使用者的 Airwallex 憑證無效（兩主機 401；
三檢查點已回報，等重貼後跑 SandboxSmokeTest）。

## ④ 下一個人要注意什麼
- 重測一鍵：bt3 上 `RAILS_ENV=production bundle exec rails runner
  'puts Psp::Airwallex::SandboxSmokeTest.run(Shop.find_by(subdomain: "demo"),
  amount: Money::Storage.from_cents(100, "HKD")).inspect'`（金額由呼叫端建——
  PSP 目錄禁 storage 建構，C1）。
- G6-1b 消費 webhook：讀 `psp_webhook_events`（received）→ 金額一律
  `Money.from_psp_amount`（Float 恆拒——JSON.parse 要 decimal_class: BigDecimal）→
  訂單入帳走 `Orders::CreateFromCheckout`／markAsPaid 補發 orders/paid。
- 本地 admin 預覽：`CHILLLOVE_BASE_HOST=localhost bundle exec rails s`＋
  `pnpm dev`＋`<subdomain>.localhost:3000`（lvh.me 會被窗格擋子資源）。
- 重跑：`bundle exec rspec spec/services/psp spec/requests/psp_webhook_airwallex_spec.rb
  spec/models/money_observability_spec.rb`＋`pnpm test`。
