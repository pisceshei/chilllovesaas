# 平台層的 authenticated administrator model（**一個 email 一個帳號，可進多間店**）。
#
# 🔴 2026-08-14（裁定 D8／§A G24）由商店級升為組織級：本表不再帶 `shop_id`，
# 「這個人能進哪些店、在該店是什麼角色」改由 {UserStoreAssignment} 回答。
# 原文是「只屬於一間 Shop 的 administrator model」——升級後那句話已經不成立，
# 照它理解會以為 `can?` 不需要 shop context（實際上沒有 shop 一律 false）。
#
# 密碼以 bcrypt digest 保存，active status 與 server-side role policy 共同
# 決定是否可登入／執行操作。見 docs/specs/12 F2/F3、docs/specs/85 §2。
class StaffMember < ApplicationRecord
  STATUSES = %w[invited active deactivated].freeze
  MINIMUM_PASSWORD_LENGTH = 10

  # invited staff 在接受邀請前刻意沒有密碼，因此改用狀態相關 validation。
  has_secure_password validations: false

  has_many :user_store_assignments, dependent: :destroy
  has_many :shops, through: :user_store_assignments
  has_many :sessions, dependent: :delete_all

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, :status, presence: true
  # 🔴 email 全平台唯一（原為 (shop_id, email) 店級唯一）——A 案要換到的正是這個：
  # 一個 email 一個帳號，透過 user_store_assignments 進入多間店（D8／docs/specs/85 §2）。
  validates :email, uniqueness: { case_sensitive: false }
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

  # 套用 server-authoritative role policy——判斷此 staff 在**目前 shop** 是否具備某權限。
  #
  # owner 永遠通過；一般 staff 必須在該店有指派、且該指派的角色持有這個 RolePermission。
  #
  # 🔴 角色改為逐店指派（D8）之後，`can?` 必須看「在哪一間店」——
  # 沒有 shop context 時一律 false（fail-closed），不得退回「用任一角色判斷」。
  #
  # @param permission_key [String] 權限鍵
  # @param shop [Shop, nil] 判定所在的店；預設取 Current.shop
  # @return [Boolean] 具備該權限時 true；無 shop context 或無指派時 false
  # @note 副作用：可能對 user_store_assignments 與 role_permissions 各執行一次 SELECT。
  # @see docs/specs/85-identity-tenancy-decision.md §4
  def can?(permission_key, shop: Current.shop)
    return true if owner?
    return false if shop.nil?

    assignment = user_store_assignments.find_by(shop_id: shop.id)
    assignment&.role&.allows?(permission_key) || false
  end

  private

  def password_present_for_active_staff
    return unless status == "active" && password_digest.blank?

    errors.add(:password, "不可空白")
  end
end
