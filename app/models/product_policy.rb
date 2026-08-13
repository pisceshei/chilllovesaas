# Shop products 的 resource-level 授權規則。
#
# resolver 必須通過此 policy 才能查詢商品；owner 或具 products.view 的
# staff 才能讀取。見 docs/specs/12 F3。
class ProductPolicy < ApplicationPolicy
  # 授權 GraphQL resolver 列出 products。
  #
  # @return [Boolean] owner 或具有 `products.view` 的 staff 回傳 true
  # @note 副作用：一般 staff 可能執行 permission existence SELECT，不寫入資料。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def index?
    authenticated? && staff.can?("products.view")
  end
end
