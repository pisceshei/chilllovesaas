# 由 permission-key records 組成的 Shop-scoped staff role。
#
# 🔴 Role 與 RolePermission 已由商店級升為**組織層**（裁定 D8／§A G24）：
# 角色可跨店重用，逐店指派透過 UserStoreAssignment。原本的 acts_as_tenant 隔離
# 已移除——保護改由 Current.accessible_shop_ids（fail-closed）與 CI 檢查承擔，
# 見 docs/specs/85 §4。舊註記：
# docs/specs/12 F3/F4。
class Role < ApplicationRecord
  has_many :user_store_assignments, dependent: :nullify

  has_many :role_permissions, dependent: :destroy

  validates :name, presence: true

  # 判斷 role 是否授予一個 server-side permission。
  #
  # @param permission_key [String] canonical dotted permission key
  # @return [Boolean] permission 是否已授予
  # @note 副作用：執行一筆 tenant-scoped existence SELECT，不寫入資料。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def allows?(permission_key)
    role_permissions.where(permission_key: permission_key).exists?
  end

  # 取得 policy 與 admin shell serialization 使用的 permission keys。
  #
  # @return [Array<String>] 已授予的 permission keys
  # @note 副作用：執行一筆 tenant-scoped pluck SELECT，不寫入資料。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def permission_keys
    role_permissions.pluck(:permission_key)
  end
end
