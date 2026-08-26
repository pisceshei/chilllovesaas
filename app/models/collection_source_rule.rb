# frozen_string_literal: true

# typed-value 條件列（13 §F4.1 修訂形）。
#
# 🔴 金額規則值**只准** `value_cents`（鐵律 3）；`condition_type` 是**開放集**
#   （`condition_unknown_passthrough`：未知型別原樣保留、`raw_payload` 載原文，
#   引擎存而不編）。exclusion 區塊的型別白名單（6 值）在寫入層驗——單一 ENUM
#   表達不了「哪個區塊有哪些欄位」（limits `exclusion_condition_types` 註釋）。
class CollectionSourceRule < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :source, class_name: "CollectionSource", foreign_key: :collection_source_id,
             inverse_of: :rules

  validates :block, inclusion: { in: %w[inclusion exclusion] }
  validates :condition_type, presence: true, length: { maximum: 64 }
end
