# 由 permission-key records 組成的**組織層** staff role（可跨店重用）。
#
# 🔴 Role 與 RolePermission 已由商店級升為組織層（裁定 D8／§A G24）：
# 角色本身不綁店，逐店指派透過 {UserStoreAssignment}。原本的 acts_as_tenant 隔離
# 已移除——保護改由 {Current#accessible_shop_ids}（fail-closed）與 CI 檢查承擔，
# 見 docs/specs/85 §4。
#
# ⚠️ 本類別目前是 M0 的最小形態（角色↔權限兩層）。本尊 2026 的完整鏈是
# **使用者↔群組↔角色↔權限**四段（115 權限／17 群組／3 層級，71-R12-STRUCT1），
# 群組那一層排 M5（71-R12-V9）。
#
# 舊註記：docs/specs/12 F3/F4。
class Role < ApplicationRecord
  has_many :user_store_assignments, dependent: :nullify

  has_many :role_permissions, dependent: :destroy

  validates :name, presence: true

  # 判斷 role 是否授予一個 server-side permission。
  #
  # @param permission_key [String] canonical dotted permission key
  # @return [Boolean] permission 是否已授予
  # @note 副作用：執行一筆 existence SELECT，不寫入資料。
  #   🔴 **不再是 tenant-scoped**（D8 後 role_permissions 已無 shop_id）——
  #   呼叫端必須自己確定這個 role 是「該 staff 在該店的角色」，見 {StaffMember#can?}。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def allows?(permission_key)
    role_permissions.where(permission_key: permission_key).exists?
  end

  # 取得 policy 與 admin shell serialization 使用的 permission keys。
  #
  # @return [Array<String>] 已授予的 permission keys
  # @note 副作用：執行一筆 pluck SELECT，不寫入資料（同 {#allows?}，已非 tenant-scoped）。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def permission_keys
    role_permissions.pluck(:permission_key)
  end
end
