# server-authoritative admin 授權使用的 Pundit policy 基底。
#
# policy 只信任目前 DB session 對應的 StaffMember，不採用 client 宣告的
# role/permission。見 docs/specs/12 F3。
class ApplicationPolicy
  # 取得此 policy 驗證的目前 staff。
  #
  # @return [StaffMember, nil] 目前 staff
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  attr_reader :staff

  # 取得此 policy 驗證的 resource。
  #
  # @return [Object] resource 或 policy symbol
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  attr_reader :record

  # 為一個 staff 與 resource 建立 policy。
  #
  # @param staff [StaffMember, nil] 目前 administrator
  # @param record [Object] resource 或 policy symbol
  # @return [ApplicationPolicy] policy instance
  # @note 副作用：只保存輸入參照，不查詢或修改資料。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def initialize(staff, record)
    @staff = staff
    @record = record
  end

  private

  def authenticated?
    staff&.active_for_authentication? || false
  end
end
