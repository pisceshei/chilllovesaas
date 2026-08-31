# frozen_string_literal: true

# 結帳線第二包：為既有商店回填預設運送鏈（General 檔＋primary market zone＋免運費率）。
#
# 🔴 薄呼叫端——實作只有 `Shipping::ProvisionDefaults` 一份（新店走 Shop#after_create
#   同一支；「callback 修未來、migration 修歷史」兩半缺一等於沒修）。
class BackfillDefaultShipping < ActiveRecord::Migration[8.1]
  def up
    say_with_time "backfill default shipping chain for existing shops" do
      Shipping::ProvisionDefaults.backfill_all!
    end
  end

  def down
    # 不可逆：無法區分「本次回填建的設定檔」與「商家後來自行調整過的設定檔」。
    raise ActiveRecord::IrreversibleMigration
  end
end
