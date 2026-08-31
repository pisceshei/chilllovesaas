# 2026-08-31 — G6-1b：配置成功後自動讀取帳號已開通的付款方式（使用者裁定）

## 已完成的工作 (Done)

- 🔴 **兩項外部事實更正（一手取證 2026-08-31）**：①官方 API 導覽頁現行逐字
  sandbox host＝`api.sandbox.airwallex.com`（api-demo＝舊 demo 環境）——limits 更正；
  ②capability 端點官方 schema 逐字（query：active/page_num 從 0/page_size 上限 1000/
  transaction_mode oneoff|recurring；回應：{has_more, items:[{active, flows, name,
  transaction_currencies, transaction_mode}]}；同名可因 mode 重複）。
- 🔴 **使用者憑證診斷破案**：重貼後 key（指紋 7f20fa…）在 sandbox/demo 仍 401、
  **正式主機 201 TOKEN-OK** ⇒ 憑證屬**正式帳號**且有效；sandbox 是獨立帳號體系。
- `Psp::Airwallex::PaymentMethodTypes.fetch`（分頁跟 has_more；active＋oneoff 雙重
  過濾；去重字母序）＋`Psp::ProviderCapabilities.sync!`（🔴 首次成功同步自動全開＝
  字典 ∩ 帳號可用；其後不覆蓋商家手動關閉；任何一次同步移除已不可用——F4.2 清單
  回退）；`available_methods`/`capabilities_synced_at` 兩欄快取（15-F4.2 條件 2）。
- `shopPaymentProviderSet` 存憑證後**自動同步**（外部 IO 在交易外，鐵律 5；失敗
  fail-soft 回 `capabilityWarning`，儲存不連坐）＋新 mutation
  `shopPaymentProviderSyncCapabilities`（NOT_CONFIGURED／UPSTREAM_UNAUTHORIZED／
  UPSTREAM_ERROR typed codes）。
- 詳情頁：同步狀態行＋「重新讀取可用方式」鈕＋**帳號未開通的方式 toggle disabled
  ＋提示**；儲存後 warning 走 toast。
- 測試：S1–S4／分頁格／P10–P12／FE 8 格；突變 MUT-1/2/3/5 全紅
  （覆蓋 enabled／不移除不可用／拔自動同步／無視 has_more）。

## 修改的檔案與核心邏輯 (Changes)

- `config/limits.yml`（hosts 更正＋capability 三鍵）；migration 20260831280000（兩欄）
- `app/services/psp/{provider_capabilities.rb,airwallex/payment_method_types.rb}`（新）
- `app/graphql/`（type 兩欄／set 的 finalize 自動同步＋capabilityWarning／sync mutation
  ＋註冊／code enum 三值）
- `app/frontend/admin/pages/SettingsPaymentProviderPage.tsx`＋i18n 五語言五鍵
- specs：provider_capabilities／payment_method_types／request P10–P12／FE 更新

## 尚未完成或需注意的風險 (Pending / TODO)

- 🔴 **使用者憑證＝正式帳號** ⇒ 部署後把 demo 店列 environment 切 production 並跑
  一次真 capability 同步（唯讀、零費用）；**付款端到端測試**需 sandbox 帳號另註冊
  （或使用者明示授權正式環境小額實付——費用紅線未授權前不做）。
- webhook 訂閱也在正式帳號 ⇒ 簽章 secret 屬 production；環境切換後一致。
- capability 同步無背景排程（僅存憑證時＋手動）；週期性刷新隨 G6-3。
