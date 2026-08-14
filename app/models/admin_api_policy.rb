# 進入版本化 Admin GraphQL boundary 的授權規則。
#
# 此層只驗證 staff session；resource-level policy 仍在 resolver 內執行。
# 見 docs/specs/12 F3、docs/research/28 §0.2。
class AdminApiPolicy < ApplicationPolicy
  # 判斷 active staff 能否提交 Admin GraphQL document。
  #
  # @return [Boolean] boundary authorization 結果
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def execute?
    authenticated?
  end
end
