# Handoff — G6-1b capability 自動讀取（2026-08-31）

## ① 我改了什麼
branch `g6/airwallex-capabilities`，base＝main `bc19d9a`。使用者裁定「Airwallex 配置
成功之後自動讀取已申請好的所有付款方式」的完整落點；清單見同名 worklog。
外部狀態：demo 店 airwallex 列的憑證已由使用者重貼（指紋 7f20faaef92d348b）、
**經正式主機驗證有效**；sandbox/demo 主機對其 401（不同帳號體系）。

## ② 為什麼這樣改
- enabled 不做鏡像：首次自動全開之後商家手動關閉必須存活（S2 釘死）——enabled 是
  白名單、available 是能力快取，兩欄分開。
- 自動同步掛在「存憑證成功後」而非查詢時：查詢面保持零外部 IO（settings 頁載入
  不能被 PSP 慢拖死）；手動「重新讀取」補即時性。
- 被推翻的假設：sandbox host＝api-demo（官方現值 api.sandbox；limits 已更正並記
  api-demo 為舊環境）。

## ③ 還有什麼沒解決
worklog Pending 三項；關鍵＝環境切 production＋真同步（部署後做）、付款端到端需
sandbox 帳號或使用者授權小額實付。

## ④ 下一個人要注意什麼
- 正式環境**絕不可**跑 confirm_with_test_card（已 raise 把關）；capability 同步是
  唯讀 GET，任何環境安全。
- 同步語義三條（首開／保留手動關／移除不可用）動任何一條前先看
  spec/services/psp/provider_capabilities_spec.rb 的 S1–S3。
- 重跑：`bundle exec rspec spec/services/psp spec/requests/shop_payment_provider_settings_spec.rb`
  ＋`pnpm vitest run app/frontend/admin/pages/SettingsPaymentsPage.test.tsx`。
