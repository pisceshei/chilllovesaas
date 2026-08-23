# frozen_string_literal: true

# 把 idempotency_keys 對齊 docs/specs/11 §2.1(a) 的表形（claim/replay 落地的前置）。
#
# 三處偏差（docs/worklog/2026-08-15-冪等指紋.md 未決點 1，本輪裁定落地）：
#   ① 缺 `mutation_name` ⇒ 無法偵測「同一把 key 用在不同 mutation」，
#      也無法在錯誤訊息與稽核裡說明這把 key 屬於誰。
#   ② `request_digest` 改名 `params_fingerprint`（規格 §2.1(a) 的欄名）；
#      同時收緊 NOT NULL——claim 一定帶指紋，可空欄位只會讓比對邏輯多一個分支。
#   ③ 刪掉三個被 `replay_strategy: rebuild_from_current_state` 明文廢棄的欄
#      （response_body／response_digest／status_code）。回放由 result_ref
#      重新載入物件、重跑 serializer，**不存回應快照**（46a:791 官方逐字
#      「constructed from current database state」）。留著空欄位就是留著誘餌——
#      下一個人會把 body 存進去然後原樣回放，那正是 11 §2.1 修正前的 bug。
#
# `resource_type`／`resource_id` 不改名：規格叫 result_ref_type/result_ref_id，
# 但既有索引 `ix_idempotency_keys_resource_type_resource_id` 已按現名建立，
# 語義完全相同（存「結果物件的指標」）——改名只換字不換義，卻要重建索引。
# 規格與 schema 的對照關係記在 IdempotencyKey model 註釋。
#
# 安全性：本表在所有環境都是**空表**（claim/replay 從未落地、生產程式碼零寫入，
# 見 docs/plans/2026-08-18-總方案.md:136「idempotency_keys 表與 CanonicalJson 零連線」），
# rename/remove 不觸碰任何既有資料。
class AlignIdempotencyKeysWithSpec21 < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      change_table :idempotency_keys, bulk: true do |t|
        t.column :mutation_name, :string, limit: 255, null: false
        t.rename :request_digest, :params_fingerprint
        t.remove :response_body
        t.remove :response_digest
        t.remove :status_code
      end
      change_column_null :idempotency_keys, :params_fingerprint, false
    end
  end

  def down
    safety_assured do
      change_column_null :idempotency_keys, :params_fingerprint, true
      change_table :idempotency_keys, bulk: true do |t|
        t.rename :params_fingerprint, :request_digest
        t.remove :mutation_name
        t.column :response_body, :text, size: :long
        t.column :response_digest, :string, limit: 64
        t.column :status_code, :integer
      end
    end
  end
end
