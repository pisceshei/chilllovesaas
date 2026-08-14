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

  # 目前 staff 可存取的 shop id 集合（fail-closed）。
  #
  # 🔴 **這個方法是 A 案安全網的核心**（裁定 D8／§A G24；兩案評估 docs/specs/85）。
  #
  # 背景：身分表（staff_members／roles／role_permissions／sessions）已升為組織層、
  # 不再帶 `shop_id`，因此**資料庫層不再保證「這個 staff 屬於這間店」**——
  # 原本那是由複合外鍵 `["shop_id","id"]` 擋住的。豁免只針對「表有沒有 shop_id 欄」，
  # **不豁免「查詢要不要帶 shop_id」**，所以那道保證必須在應用層原地補回來。
  #
  # fail-closed 的定義：**任何無法明確證明有權限的情況一律回空集合**，
  # 而不是回 nil 或丟例外讓呼叫端自己決定——後者一旦有人忘記處理就是越權。
  #
  # @return [Array<Integer>] 可存取的 shop id；未登入或無指派時為 `[]`
  # @note 副作用：可能對 user_store_assignments 執行一次 SELECT（每 request 記憶化）。
  # @see docs/specs/85-identity-tenancy-decision.md §4
  def accessible_shop_ids
    return [] if staff.nil?

    @accessible_shop_ids ||= UserStoreAssignment
      .where(staff_member_id: staff.id)
      .pluck(:shop_id)
  end

  # 目前 staff 是否可存取指定 shop。
  #
  # @param shop_id [Integer, nil] 目標 shop id
  # @return [Boolean] 有權限時 true；`shop_id` 為 nil 或無指派時一律 false
  # @note 副作用：同 {#accessible_shop_ids}。
  # @see docs/specs/85-identity-tenancy-decision.md §4
  def can_access_shop?(shop_id)
    return false if shop_id.nil?

    accessible_shop_ids.include?(shop_id)
  end

  # 目前 staff 在**目前 shop** 的角色（角色改為逐店指派，見 D8）。
  #
  # @return [Role, nil] 該店的角色；未登入、無 shop context 或未指派時為 nil
  # @note 副作用：可能對 user_store_assignments 執行一次 SELECT。
  # @see docs/specs/85-identity-tenancy-decision.md §2
  def role_for_current_shop
    return if staff.nil? || shop.nil?

    @role_for_current_shop ||= UserStoreAssignment
      .includes(:role)
      .find_by(staff_member_id: staff.id, shop_id: shop.id)
      &.role
  end

  resets do
    ActsAsTenant.current_tenant = nil
    @accessible_shop_ids = nil
    @role_for_current_shop = nil
  end
end
