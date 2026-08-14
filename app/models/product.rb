# 透過 Admin GraphQL API 公開的 Shop-scoped 商品 model。
#
# `acts_as_tenant` fail-closed 限制所有預設 query/write 在目前 Shop；API
# resolver 仍加明確 shop_id 作 defense in depth。見 docs/specs/12 F4。
class Product < ApplicationRecord
  STATUSES = %w[draft active archived].freeze

  acts_as_tenant :shop

  has_many :product_variants, dependent: :destroy
  # 多型：商品可獨立發布到各管道（docs/specs/88）。
  has_many :resource_publications, as: :publishable, dependent: :destroy

  validates :title, :handle, :status, presence: true
  validates :handle, uniqueness: { scope: :shop_id, case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }
end
