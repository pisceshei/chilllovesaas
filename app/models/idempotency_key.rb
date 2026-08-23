# frozen_string_literal: true

# 寫路徑冪等的 claim 記錄（docs/specs/11 §2.1）。
#
# 一列 ＝ 一次「以 (shop_id, key) 為身分的寫入嘗試」。搶佔靠
# `uq_idempotency_keys_key (shop_id, key)` 唯一索引：兩個並發請求同 key，
# 只有一個 INSERT 成功，另一個拿 `RecordNotUnique` 後改讀既有列分流。
#
# ## 欄名與規格的對照（11 §2.1(a)）
#
# | 規格欄名 | 本表欄名 | 備註 |
# |---|---|---|
# | params_fingerprint | params_fingerprint | 20260823 遷移由 request_digest 改名對齊 |
# | state | state | processing / succeeded / failed 三態 |
# | result_ref_type / result_ref_id | resource_type / resource_id | 語義相同（結果物件指標）；不改名理由見遷移註釋 |
#
# ## 狀態語義（11 §2.1(b) 逐字裁定，2026-08-23）
#
# - `succeeded`：依 resource_type/resource_id **重新載入物件、重跑 serializer**
#   產生回應——不存、也絕不回放任何快照（46a:791 官方逐字）。
# - `processing`：另一請求進行中 ⇒ `IDEMPOTENCY_CONCURRENT_REQUEST`，
#   呼叫端退避後**用同一把 key** 重試。
# - `failed`：**視為未執行，允許以同一把 key 重試**。
#   🔴 這與 90 號藍圖的「前次失敗須換 key ⇒ IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED」
#   **互相矛盾**——本專案遵循 11 §2.1（生產基線規格），該碼在本線**不發**；
#   矛盾已登記 docs/specs/91，庫存線落地前必須先解。
# - 過 `expires_at`（TTL 24h，`limits.idempotency.ttl_hours`）⇒ 視為全新操作。
#
# @see docs/specs/11-production-baseline.md §2.1
# @see docs/dev/m1-product-set-foundation.md
class IdempotencyKey < ApplicationRecord
  STATES = %w[processing succeeded failed].freeze

  acts_as_tenant :shop

  validates :key, presence: true
  validates :mutation_name, presence: true
  validates :params_fingerprint, presence: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :state, inclusion: { in: STATES }

  # @return [Boolean] 此列是否已過 TTL（過期＝視為全新操作）
  # @note 副作用：無。
  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
