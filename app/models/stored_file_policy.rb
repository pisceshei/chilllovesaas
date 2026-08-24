# 檔案庫的 resource-level 授權規則（第 25 包）。
#
# 檔案掛在內容線；權限鍵沿 12 F3 命名慣例＝`files.view`／`files.edit`
# （owner 經 StaffMember#can? 恆通過；細分授予屬 M5 RBAC 展開）。
class StoredFilePolicy < ApplicationPolicy
  # 授權讀取（files query／檔案讀出端點）。
  #
  # @return [Boolean]
  # @note 副作用：一般 staff 可能執行 permission existence SELECT，不寫入資料。
  def index?
    authenticated? && staff.can?("files.view")
  end

  # 授權 stagedUploadsCreate／fileCreate 等寫入。
  #
  # @return [Boolean]
  # @note 副作用：同上。
  def create?
    authenticated? && staff.can?("files.edit")
  end
end
