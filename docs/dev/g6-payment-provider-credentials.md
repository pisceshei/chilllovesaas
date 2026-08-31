# PSP provider 憑證層（G6-3 前半切片）

## 概述

商家後台「設定 › 付款」的最小可用面：兩個直連 provider（Airwallex／PayPal）的
憑證輸入＋test mode。**由使用者親手在網頁輸入 sandbox 憑證**（憑證紅線：執行方
不經手明文金鑰入庫），祕密欄 AR encryption 密文落庫、UI 只回 SHA-256 前 16 hex
指紋（37 §6.3）。86 號 §1 的完整 1:1 佈局與逐方法 toggle 隨 G6-3 本體落地。

## 規格出處

- `docs/specs/37` §6.3（金鑰不明文入庫三層；AR Encryption＝最低標，KMS 待使用者裁定）
- `docs/specs/15` F4.2（三條件交集；enabled_methods＝商家白名單、非真相來源）
- `docs/research/86` §1–§3（G6-3 目標形態；本切片不與其矛盾）
- `config/limits.yml` `psp_credentials:`（承 carrier.credentials 慣例）
- 總方案 G6-3 資料層既定形（provider＋憑證引用＋enabled_methods JSON）

## 架構與資料流

```
SettingsPaymentsPage（/admin/settings/payments）
  ├─ query shopPaymentProviders        ← 只回已落鍵列；祕密欄不存在於 type（P5 introspection 釘住）
  └─ mutation shopPaymentProviderSet   ← 宣告式 upsert；祕密 write-only：
       省略參數＝保持不變／空字串＝清空（前端留空一律「省略」，不提供清空 UI）
            ↓
ShopPaymentProvider（acts_as_tenant；(shop_id, provider) UNIQUE）
  encrypts :api_secret / :webhook_secret     ← 全倉第一個 AR encryption 使用點
  before_save 指紋（SHA-256 前 N hex，N＝limits psp_credentials.fingerprint_hex_chars）
            ↓
金鑰＝env 三鍵（ACTIVE_RECORD_ENCRYPTION_*；initializer production 缺鍵 boot 即 raise）
```

## 資料表

`shop_payment_providers`（migration 20260831260000）：provider／environment
（sandbox|production）／status（本切片恆 inactive）／client_id・webhook_id（非祕密，
可回讀）／api_secret・webhook_secret（密文）／兩個 fingerprint／enabled_methods json。

## 關鍵取捨

- **AR encryption 金鑰走 env 三鍵、不走 credentials.yml.enc**：120 §4 明文「credentials
  未使用」（無 master.key）；37 §6.3 成文時假設 credentials 載體，與現實衝突處以
  env 為準（部署雙通道 systemd EnvironmentFile＋deploy.sh set -a 都吃得到）。
- **KMS 信封加密不代決**（37 §6.3 逐字「待定，需使用者確認」）——本切片＝最低標。
- **provider 字典＝`Psp.registry.codes`**（平台層 pack 宣告；鐵律 6），不硬編。
- **status 恆 inactive、結帳線零讀取**：activation 狀態機（86 §1「一次只能一家
  credit-card provider」）與 pack `enabled:false` 閘門都不被本切片繞過。
- **json 表達式預設坑**：`(json_array())` 不進未存檔實例（Rails 不解析 expression
  default）⇒ model `after_initialize` 補 `[]`（實測踩中）。
- **`Limits.enum` 回大寫**：environment_enum 比對前 downcase（實測踩中）。

## 🔴 跨功能／跨頁／前端影響（鐵律 12.4 ④）

| 影響對象 | 什麼時候 | 要注意什麼 |
|---|---|---|
| G6-1/G6-2 adapter | 讀憑證 | 只帶 `shop_payment_provider_id` 進 job（limits `psp_credentials.job_payload_forbidden_keys`）；環境對映（sandbox→demo/sandbox base URL）在 adapter |
| G6-3 本體 | 86 §1 整頁 1:1 | 接手 status 狀態機＋enabled_methods toggle 清單；本頁擴建不重寫 |
| 結帳頁付款段 | G6-1 後 | 顯示＝enabled_methods ∩ PSP capability（15-F4.2）；本切片不接 |
| 部署 | 每台新機 | env 三鍵必備（120 §4）；缺鍵 boot 即 raise |
| 平台側（G6-5） | 平台收款 | 另有自己的憑證落點，不共用本表 |

## 測試

- `spec/models/shop_payment_provider_spec.rb`（6）：密文落庫／指紋明文基準／字典／環境／唯一／json 預設。
- `spec/requests/shop_payment_provider_settings_spec.rb`（P1–P7）：指紋回讀＋DB 密文／upsert／
  🔴 write-only（省略＝不變、空字串＝清空）／PROVIDER_UNKNOWN／🔴 introspection 無祕密欄／租戶隔離。
- `SettingsPaymentsPage.test.tsx`（5）：雙卡渲染／指紋提示／🔴 留空不送參數／送祕密＋重載清空／userError toast。
- 突變 MUT-1~5 全紅（拔 encrypts／拔指紋刷新／省略當清空／type 長祕密欄／拔字典檢查）。

## 已知限制與 TODO

- 清空祕密無 UI（協定存在：明送空字串）；輪換記錄（37 §520 rotated_at）未建——G6-3。
- 「Save 前測試連線」（carrier 的 accountTest 形）未做——G6-1 有 API client 後補。
- settings 細粒度權限沿用 `authorize_products!` 現況（M5 RBAC 展開時換）。
- 65 §K.8–9 可觀測（轉換日誌）不屬本切片，仍掛 G6-1 前置。
