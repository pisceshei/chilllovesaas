# frozen_string_literal: true

module Inventory
  # 調整記錄頁的讀取（排程第 18 包；總裁定 §四-2 的**第八式落點**）。
  #
  # ①這是什麼：某個 (item, location) 的 ledger 歷程，每列＝一次調整（一個 group 對該 level 的子行），
  #   並帶每個數量欄的 **期後值**（本尊 `InventoryChange.quantityAfterChange`）。
  # ②值域：保留窗＝`limits.inventory.adjustment_history_retention_days`（180，help 明文
  #   「You can view only the last 180 days」）；顯示序＝新→舊。
  # ③怎麼做：**window function 的 running sum 必須在日期過濾之前算**——
  #   🔴 這是本檔唯一的要害：若先 `WHERE created_at >= 180 天前` 再算 running sum，
  #   期後值會從窗內第一列重新起算，於是每一列的「總數」都是錯的，而且**錯得很像對的**
  #   （差值仍然連續、只有絕對值偏移）。CTE 內先開窗、外層才過濾，順序反了測試抓不到，
  #   要靠「最後一列＝levels 現值」那條斷言（第八式）。
  #   🔴 期初庫存也是一列 ledger 事件（94 §2.5 實機：「Initial inventory (+9)」）——
  #   所以 running sum 從第一列起算就等於現值，不需要另存期初快照。
  # ④跨功能影響：`Inventory::Reconcile` 的七式驗「SUM(delta)＝現值」＝本檔期末值的等價式；
  #   兩者對不上時先看是不是有人繞過唯一入口寫過 level（cop 擋新的、對帳抓舊的）。
  class HistoryQuery
    Row = Data.define(
      :id, :group_id, :created_at, :reason, :mutation_kind, :client_source,
      :staff_member_id, :reference_document_uri, :ledger_document_uri,
      :deltas, :after
    )

    # 顯示欄（實測 94 §2.5 的 7 欄扣掉 Date/Activity/Created by 三個非數量欄）。
    # incoming 一併算出，由前端依「該品項是否曾有 incoming」決定顯不顯示（條件性欄）。
    QUANTITY_NAMES = %w[unavailable committed available on_hand incoming].freeze

    # @param shop [Shop]
    # @param level_id [Integer]
    # @param limit [Integer]
    # @return [Array<Row>] 新→舊
    def self.call(shop:, level_id:, limit: 50)
      retention = Limits.fetch(:inventory, :adjustment_history_retention_days).to_i
      rows = ActiveRecord::Base.connection.select_all(<<~SQL.squish, "Inventory::HistoryQuery")
        WITH ledger AS (
          SELECT ia.id, ia.inventory_adjustment_group_id, ia.created_at, ia.ledger_document_uri,
                 ia.available_delta, ia.committed_delta, ia.unavailable_delta,
                 ia.on_hand_delta, ia.incoming_delta,
                 SUM(ia.available_delta)   OVER (ORDER BY ia.created_at, ia.id) AS available_after,
                 SUM(ia.committed_delta)   OVER (ORDER BY ia.created_at, ia.id) AS committed_after,
                 SUM(ia.unavailable_delta) OVER (ORDER BY ia.created_at, ia.id) AS unavailable_after,
                 SUM(ia.on_hand_delta)     OVER (ORDER BY ia.created_at, ia.id) AS on_hand_after,
                 SUM(ia.incoming_delta)    OVER (ORDER BY ia.created_at, ia.id) AS incoming_after
          FROM inventory_adjustments ia
          WHERE ia.shop_id = #{shop.id.to_i}
            AND ia.inventory_level_id = #{level_id.to_i}
        )
        SELECT l.*, g.reason, g.mutation_kind, g.client_source,
               g.staff_member_id, g.reference_document_uri
        FROM ledger l
        INNER JOIN inventory_adjustment_groups g
          ON g.shop_id = #{shop.id.to_i}
         AND g.id = l.inventory_adjustment_group_id
        WHERE l.created_at >= NOW(6) - INTERVAL #{retention} DAY
        ORDER BY l.created_at DESC, l.id DESC
        LIMIT #{limit.to_i}
      SQL

      rows.map { |row| build_row(row) }
    end

    def self.build_row(row)
      Row.new(
        id: row.fetch("id"),
        group_id: row.fetch("inventory_adjustment_group_id"),
        created_at: row.fetch("created_at"),
        reason: row.fetch("reason"),
        mutation_kind: row.fetch("mutation_kind"),
        client_source: row["client_source"],
        staff_member_id: row["staff_member_id"],
        reference_document_uri: row["reference_document_uri"],
        ledger_document_uri: row["ledger_document_uri"],
        deltas: QUANTITY_NAMES.to_h { |name| [ name, row.fetch("#{name}_delta").to_i ] },
        after: QUANTITY_NAMES.to_h { |name| [ name, row.fetch("#{name}_after").to_i ] }
      )
    end
    private_class_method :build_row
  end
end
