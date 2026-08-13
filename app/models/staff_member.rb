# 只屬於一間 Shop 的 authenticated administrator model。
#
# 密碼以 bcrypt digest 保存，active status 與 server-side role policy 共同
# 決定是否可登入／執行操作。見 docs/specs/12 F2/F3。
class StaffMember < ApplicationRecord
  STATUSES = %w[invited active deactivated].freeze
  MINIMUM_PASSWORD_LENGTH = 10

  acts_as_tenant :shop
  # invited staff 在接受邀請前刻意沒有密碼，因此改用狀態相關 validation。
  has_secure_password validations: false

  belongs_to :role, optional: true
  has_many :sessions, dependent: :delete_all

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, :status, presence: true
  validates :email, uniqueness: { scope: :shop_id, case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, if: -> { password.present? }
  validate :password_present_for_active_staff

  # 判斷此 staff account 能否建立或恢復 admin session。
  #
  # @return [Boolean] active 且未標記 deactivated 的帳號回傳 true
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F2
  def active_for_authentication?
    status == "active" && deactivated_at.nil?
  end

  # 套用 server-authoritative role policy。
  #
  # owner 永遠通過；一般 staff 必須有持久化的 RolePermission。
  #
  # @param permission_key [String] canonical dotted permission key
  # @return [Boolean] staff 是否有權限
  # @note 副作用：一般 staff 可能執行 RolePermission existence SELECT，不寫入資料。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def can?(permission_key)
    owner? || role&.allows?(permission_key) || false
  end

  private

  def password_present_for_active_staff
    return unless status == "active" && password_digest.blank?

    errors.add(:password, "不可空白")
  end
end
