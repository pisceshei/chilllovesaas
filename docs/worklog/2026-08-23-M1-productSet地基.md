# 2026-08-23 — M1：productSet 地基（claim/replay ＋ mutation root 掛載）

## 已完成的工作 (Done)

- **claim/replay 落地**（11 §2.1 逐字）：`Idempotency::Guard` 狀態機
  （processing/succeeded/failed／TTL／指紋比對／由 result_ref 重建回放）＋
  `idempotency_keys` 表形對齊遷移（補 mutation_name、request_digest→
  params_fingerprint、刪三個廢棄欄）＋ `IdempotencyKey` model。
  五個未決點：#1/#2/#5 本批裁定結案，#3/#4 照舊（見 dev doc §2）。
- **mutation root 掛載**＋第一支 mutation `productSet`（63 §B.4 v1＝建立態＋
  隱含變體）：input/error 型別、`Catalog::SaveProduct`（sanitize／金額 X12／
  handle 生成與衝突／outbox 事件，單一 transaction）、`Catalog::HandleGenerator`
  （limits handle 區塊全管線，六個裁定範例逐字元通過）、`ProductPolicy#create?`
  （products.edit）、`EventOutbox` model。
- guard spec 反轉＋新增 `mutation_idempotency_call_spec`（靜態掃描 resolve 呼叫，
  兌現 2026-08-15 worklog 承諾）＋ productSet request spec 19 例＋併發 claim spec。
- `docs/specs/65` §B 補 X12 列（admin 金額入向——封閉條款要求先改表）；
  `docs/specs/91` §3.7 登記三條；`docs/dev/m1-product-set-foundation.md` 全新。

## 修改的檔案與核心邏輯 (Changes)

- `db/migrate/20260823000000_align_idempotency_keys_with_spec_2_1.rb`：表形對齊。
- `app/services/idempotency/guard.rb`：claim 在業務 transaction 外（D-PS1）；
  failed 分流先於指紋比對＋指紋重置（D-PS3）；業務失敗記 failed（D-PS2）。
- `app/services/catalog/save_product.rb`／`handle_generator.rb`：見 dev doc §3。
- `app/graphql/mutations/product_set.rb`：建立態條件強制 key（D-PS5）；
  Guard 例外轉 CONCURRENCY 池 userErrors；回放物件已刪 → NOT_FOUND。
- `app/graphql/types/`：mutation_type 掛欄位；inputs/ 兩檔；errors/ 兩檔；
  product_type 加 lockVersion；chilllove_schema 掛 mutation root、移 orphan。
- `app/models/`：idempotency_key.rb／event_outbox.rb 新增；product_policy 加 create?。
- spec：product_set_spec（19）＋ idempotency_key_concurrency_spec（1）＋
  guard 反轉（4）＋靜態掃描（2）；全套 301 例 0 失敗（本機實跑）。

## 尚未完成或需注意的風險 (Pending / TODO)

- 更新態／多變體／初始庫存／auto_publish／translation base row／CDN 白名單
  ——全列 dev doc §5，各標依賴。
- 🔴 11-vs-90 的 `IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED` 語義矛盾（91 §3.7）：
  商品線遵循 11 不發此碼；**庫存線落地前必須先解**。
- 測試端算指紋的兩個坑已寫進 dev doc §3（snake_case＋類別 graphql_name），
  第一次就都踩過（實跑 MISMATCH 抓出）。
