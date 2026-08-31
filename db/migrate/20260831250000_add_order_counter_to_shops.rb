# frozen_string_literal: true

# G6-0(a) F5 訂單成立：每店連號計數器（15-F5 步 4）。
#
# 🔴 每店計數不用全域自增：全域序號會向所有租戶洩漏平台總單量（15-F5 ⚠️坑第 1 條，
#   經典多租戶錯誤）。取號＝transaction 內 `UPDATE shops SET order_counter=order_counter+1`
#   後讀回——這行 UPDATE 同時是本交易的**鎖序首位**（先 shop counter 後 inventory，
#   全專案固定，防跨入口死鎖——15-F5 步 2 第 7 輪更正）。
# 預設 1000 ⇒ 首單 #1001（本尊起始號同形）。
class AddOrderCounterToShops < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:shops, :order_counter)
      add_column :shops, :order_counter, :bigint, default: 1000, null: false,
                 comment: "每店訂單連號計數器（15-F5；取號＝交易內 +1 後讀回，鎖序首位）"
    end
  end
end
