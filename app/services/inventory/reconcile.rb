# frozen_string_literal: true

module Inventory
  # ledger ↔ 現值對帳（排程第 17 包；總裁定 §四-2 的八式中本包實作七式）。
  #
  # ①這是什麼：nightly 的漂移偵測。ledger 是唯一真相；現值（inventory_levels 的六個 leaf）
  #   必須等於 ledger 的 SUM(delta)。
  # ②本包實作**七式**＝六個 leaf 的 SUM 恆等 ＋ group.changes_count 恆等。
  #   🔴 總裁定 §四-2 的八式中缺的第八式＝「running-sum 期末值＝現值」——它與六 leaf SUM
  #   在 append-only 下**對期末值等價**，但 quantityAfterChange 的**逐列**正確性要靠它，
  #   該式屬第 18 包（歷程頁的 running-sum 讀取管線）一併實作，此處登記不實作。
  #   on_hand／unavailable 不在八式之列（STORED GENERATED，DB 恆成立，驗它等於驗 MySQL）。
  # ③🔴 前提：**所有**數量變動都走過 Inventory::Adjust。開帳前既有的現值
  #   （backfill 的 0、或任何繞過入口的直寫）沒有對應 ledger 列 ⇒ 會被本服務如實回報
  #   ——那不是誤報，是它存在的理由（cop 擋新增的繞過，對帳抓歷史的與 SQL 層的）。
  # ④跨功能影響：`rake inventory:reconcile` 給 cron；第 18 包的調整記錄頁以 ledger 為準，
  #   對不上的店會先在這裡冒出來。
  class Reconcile
    LEAVES = %w[available committed reserved damaged safety_stock quality_control].freeze

    Discrepancy = Data.define(:kind, :detail)

    # @param shop [Shop]
    # @return [Array<Discrepancy>] 空陣列＝帳平
    def self.call(shop:)
      discrepancies = []

      LEAVES.each do |leaf|
        rows = ActiveRecord::Base.connection.select_all(<<~SQL.squish)
          SELECT il.id AS level_id, il.#{leaf} AS current_value,
                 COALESCE(SUM(ia.#{leaf}_delta), 0) AS ledger_sum
          FROM inventory_levels il
          LEFT JOIN inventory_adjustments ia
            ON ia.shop_id = il.shop_id AND ia.inventory_level_id = il.id
          WHERE il.shop_id = #{shop.id.to_i}
          GROUP BY il.id, il.#{leaf}
          HAVING current_value <> ledger_sum
        SQL
        rows.each do |row|
          discrepancies << Discrepancy.new(
            kind: "leaf_mismatch",
            detail: "level=#{row['level_id']} #{leaf}: current=#{row['current_value']} ledger_sum=#{row['ledger_sum']}"
          )
        end
      end

      ActiveRecord::Base.connection.select_all(<<~SQL.squish).each do |row|
        SELECT g.id AS group_id, g.changes_count, COUNT(ia.id) AS actual
        FROM inventory_adjustment_groups g
        LEFT JOIN inventory_adjustments ia
          ON ia.shop_id = g.shop_id AND ia.inventory_adjustment_group_id = g.id
        WHERE g.shop_id = #{shop.id.to_i}
        GROUP BY g.id, g.changes_count
        HAVING g.changes_count <> actual
      SQL
        discrepancies << Discrepancy.new(
          kind: "changes_count_mismatch",
          detail: "group=#{row['group_id']} cached=#{row['changes_count']} actual=#{row['actual']}"
        )
      end

      discrepancies
    end
  end
end
