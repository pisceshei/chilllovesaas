# frozen_string_literal: true

# 顧客可重用地址（08 §C.2 地址簿；表自 M0 就在 schema，G6-7 起有寫入者）。
#
# ①這是什麼：customer 的地址簿列；`default_address` 標記預設（列表「地點」欄
#   與詳情 cd-address 卡讀它）。
# ②與訂單快照的關係（06 §2）：訂單上的 shipping/billing address 是 **JSON 快照**
#   ——本表變更不回寫歷史訂單；結帳→訂單成立時反向把快照「補進」地址簿
#   （首單且簿空才建，`Customers::UpsertFromCheckout`）。
# ③鍵名對映（87 §3 checkout JSON → 本表欄）：zone→province、postal_code→postal_code、
#   country_code→country_code；其餘同名。
class CustomerAddress < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :customer

  validates :address1, :city, presence: true
  validates :country_code, presence: true, length: { is: 2 }
end
