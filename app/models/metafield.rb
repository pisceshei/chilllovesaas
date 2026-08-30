# frozen_string_literal: true

# 租戶資源上的 typed custom value（讀取面；寫入 API 隨 metafields 功能線）。
# namespace／key／型別在 definition 列上；本表只有 definition_id ＋ value(json)。
class Metafield < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :metafield_definition

  validates :owner_type, :owner_id, presence: true
end
