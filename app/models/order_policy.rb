# frozen_string_literal: true

# 訂單線的 resource-level 授權（G6-6a）。
#
# 權限鍵沿 12 F3 命名慣例＝`orders.view`／`orders.edit`——獨立於商品/顧客線
# （訂單含金額與收件地址 PII，權限格必須可單獨授予收回；退款軟上限另有
# `orders.over_refund` 細格——16 §F5.1，隨退款包落）。
class OrderPolicy < ApplicationPolicy
  # 授權讀取（orders／order query 與訂單頁讀出端點）。
  #
  # @return [Boolean]
  # @note 副作用：一般 staff 可能執行 permission existence SELECT，不寫入資料。
  def index?
    authenticated? && staff.can?("orders.view")
  end

  # 授權寫入（orderMarkAsPaid/orderCapture 等——mutation 隨步 4 包）。
  #
  # @return [Boolean]
  # @note 副作用：同上。
  def create?
    authenticated? && staff.can?("orders.edit")
  end
end
