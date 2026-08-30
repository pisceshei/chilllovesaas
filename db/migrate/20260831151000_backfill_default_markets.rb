# frozen_string_literal: true

# 包 32：為既有商店回填預設市場鏈（primary market HK ＋ primary domain ＋ presence ＋ 語言白名單）。
#
# 🔴 薄呼叫端——實作只有 `Markets::ProvisionDefaults` 一份（新店走 Shop#after_create 同一支；
#   「callback 修未來、migration 修歷史」兩半缺一等於沒修，同 20260826060000 檔頭教訓）。
class BackfillDefaultMarkets < ActiveRecord::Migration[8.1]
  def up
    say_with_time "backfill default market chain for existing shops" do
      Markets::ProvisionDefaults.backfill_all!
    end
  end

  def down
    # 不可逆：無法區分「本次回填建的市場」與「商家後來自行調整過的市場」。
    raise ActiveRecord::IrreversibleMigration
  end
end
