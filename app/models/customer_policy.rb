# frozen_string_literal: true

# 顧客線的 resource-level 授權（G6-7）。
#
# 權限鍵沿 12 F3 命名慣例＝`customers.view`／`customers.edit`——獨立於商品線
# （files 前例的同一理由：只給了商品權限的 staff 不該看到顧客 PII；
# 顧客資料是 PDPO/GDPR 射程，權限格必須可單獨收回）。
class CustomerPolicy < ApplicationPolicy
  # 授權讀取（customers／customer query 與後續顧客頁讀出端點）。
  #
  # @return [Boolean]
  # @note 副作用：一般 staff 可能執行 permission existence SELECT，不寫入資料。
  def index?
    authenticated? && staff.can?("customers.view")
  end

  # 授權寫入（customerCreate/Update 等——mutation 隨顧客模組全量包）。
  #
  # @return [Boolean]
  # @note 副作用：同上。
  def create?
    authenticated? && staff.can?("customers.edit")
  end

  # 寫入類（update/addresses/consent/erasure）與刪除共用 edit 鍵——
  # 細分（如 customers.erase 獨立權限格）隨 M5 RBAC 展開。
  def update? = create?
  def destroy? = create?
end
