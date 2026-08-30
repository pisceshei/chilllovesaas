# frozen_string_literal: true

# metafield 的 namespace/key/型別定義（每 shop × owner_type × namespace × key 唯一）。
class MetafieldDefinition < ApplicationRecord
  acts_as_tenant :shop

  has_many :metafields, dependent: :restrict_with_error

  validates :namespace, :key, :name, :owner_type, :value_type, presence: true
end
