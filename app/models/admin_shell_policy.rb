# 進入 merchant admin shell 的授權規則。
#
# resource 操作不由 shell 授權；仍須透過 GraphQL resolver policy。見
# docs/specs/12 F3、HANDOFF.md D5。
class AdminShellPolicy < ApplicationPolicy
  # 判斷目前 active staff account 能否進入 shell。
  #
  # @return [Boolean] shell authorization 結果
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
  def show?
    authenticated?
  end
end
