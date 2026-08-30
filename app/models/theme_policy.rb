# frozen_string_literal: true

# 主題面的 resource-level 授權規則（包 30／D77）。
#
# 權限鍵沿 12 F3 命名慣例＝`themes.view`／`themes.edit`
# （owner 經 StaffMember#can? 恆通過；細分授予屬 M5 RBAC 展開）。
class ThemePolicy < ApplicationPolicy
  # 授權讀取（themes query／主題清單／登入後預覽）。
  # @return [Boolean]
  def index?
    authenticated? && staff.can?("themes.view")
  end

  # 授權發布轉場（themePublish）。
  # @return [Boolean]
  def update?
    authenticated? && staff.can?("themes.edit")
  end
end
