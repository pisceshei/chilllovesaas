# 只由 request Host 選定的 tenant root model。
#
# Shop 本身不受 acts_as_tenant scope；所有租戶資料都透過其 shop_id 隔離。
# 見 docs/specs/12 F1/F4。
class Shop < ApplicationRecord
  SUBDOMAIN_FORMAT = /\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z/
  STATUSES = %w[active suspended closed].freeze

  has_many :staff_members, dependent: :restrict_with_error
  has_many :sessions, dependent: :delete_all
  has_many :products, dependent: :restrict_with_error
  has_many :roles, dependent: :restrict_with_error

  normalizes :subdomain, with: ->(value) { value.to_s.strip.downcase }
  normalizes :custom_domain, with: ->(value) { value.to_s.strip.downcase.delete_suffix(".").presence }

  validates :name, :subdomain, :status, presence: true
  validates :subdomain, format: { with: SUBDOMAIN_FORMAT }, uniqueness: { case_sensitive: false }
  validates :subdomain, exclusion: {
    in: Chilllove::TenantResolver::RESERVED_SUBDOMAINS,
    message: "為平台保留字"
  }
  validates :custom_domain, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  # 判斷 M0 是否可路由已持久化的 custom domain。
  #
  # M0 只在驗證完成後寫入此欄位；P1 的 custom_domains 表會保存明確的
  # verification timestamp。
  #
  # @return [Boolean] 只有 active 且有 custom domain 的商店回傳 true
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F1
  def custom_domain_verified?
    status == "active" && custom_domain.present?
  end
end
