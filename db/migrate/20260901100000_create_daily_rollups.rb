# frozen_string_literal: true

# G6 步 10（分析地基；19-F2）：daily_rollups——查詢永遠打 rollup，
# 不對 orders 做大範圍即時聚合。upsert 冪等（uq 四欄）；金額指標存 cents、
# 計數指標存原值（單位在指標辭典 Analytics::Metrics 註明——鐵律 3 儲存尺度）。
class CreateDailyRollups < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:daily_rollups)
      create_table :daily_rollups,
                   comment: "分析日聚合（19-F2；upsert 冪等；金額=cents 計數=原值）" do |t|
        t.bigint :shop_id, null: false
        t.date :date, null: false, comment: "shop 時區的日界線（19-F2 坑：不是 UTC）"
        t.string :metric, limit: 64, null: false
        t.string :dimension, limit: 64, null: false, default: "",
                 comment: "維度值（如 product_id；無維度＝空字串——uq 需非 NULL）"
        t.bigint :value, null: false, default: 0
        t.timestamps

        t.index [ :shop_id, :date, :metric, :dimension ],
                unique: true, name: "uq_daily_rollups_key"
        t.index [ :shop_id, :metric, :date ], name: "ix_daily_rollups_metric_date"
      end
    end

    fk_missing = table_exists?(:daily_rollups) &&
                 foreign_keys(:daily_rollups).none? { |fk| fk.to_table == "shops" }
    if fk_missing
      safety_assured { add_foreign_key :daily_rollups, :shops }
    end
  end
end
