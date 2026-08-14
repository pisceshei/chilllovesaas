# 每個 request 的 tenant、staff 與可撤銷 admin session context。
#
# Current 由 ActiveSupport::CurrentAttributes 提供 thread/fiber isolation；Rack
# tenant resolver 會在 ensure 清除它，避免跨 request 洩漏。見
# docs/specs/12 F1/F4。
class Current < ActiveSupport::CurrentAttributes
  # @!attribute [rw] shop
  #   目前 request 的 tenant root。
  #   @return [Shop, nil]
  #   @note 寫入只影響目前 thread/fiber；TenantResolver 會在 ensure 清除。
  #   @see docs/specs/12-spec-tenancy-auth-permissions.md F1, F4
  # @!attribute [rw] staff
  #   目前 DB session 已驗證的 staff。
  #   @return [StaffMember, nil]
  #   @note 寫入只影響目前 thread/fiber；TenantResolver 會在 ensure 清除。
  #   @see docs/specs/12-spec-tenancy-auth-permissions.md F2, F4
  # @!attribute [rw] admin_session
  #   目前 request 使用的可撤銷 DB session。
  #   @return [Session, nil]
  #   @note 寫入只影響目前 thread/fiber；TenantResolver 會在 ensure 清除。
  #   @see docs/specs/12-spec-tenancy-auth-permissions.md F2, F4
  attribute :shop, :staff, :admin_session

  resets do
    ActsAsTenant.current_tenant = nil
  end
end
