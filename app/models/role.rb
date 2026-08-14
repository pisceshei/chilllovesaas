# 由 permission-key records 組成的 Shop-scoped staff role。
#
# Role 與 RolePermission 都由 acts_as_tenant fail-closed 隔離。見
# docs/specs/12 F3/F4。
class Role < ApplicationRecord
  acts_as_tenant :shop

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
