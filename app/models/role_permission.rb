# 授予 Shop-scoped Role 的一個 canonical permission record。
#
# `(shop_id, role_id, permission_key)` 保持 tenant 內唯一；policy 只信任
# server-side persisted record。見 docs/specs/12 F3/F4。
class RolePermission < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :role

  validates :permission_key, presence: true,
    uniqueness: { scope: %i[shop_id role_id], case_sensitive: true }
end
