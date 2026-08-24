# frozen_string_literal: true

module Types
  # 一次庫存異動呼叫的批次頭（＝本尊 InventoryAdjustmentGroup；總裁定 §一）。
  class InventoryAdjustmentGroupType < BaseObject
    graphql_name "InventoryAdjustmentGroup"
    description "一次庫存異動呼叫的結果批次；changes 為每個受影響數量名一筆的投影。"

    field :id, ID, null: false
    field :reason, String, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :changes_count, Integer, null: false,
      description: "ledger 子行數（快取欄；Reconcile 驗它）。"
    field :changes, [ Types::InventoryChangeType ], null: false,
      description: "每個受影響數量名一筆（含衍生的 on_hand／unavailable）——" \
                   "儲存層一列＝(group, level) 六 delta 欄，本欄位是讀取期投影（總裁定 §一）。"

    def id
      "gid://chilllove/InventoryAdjustmentGroup/#{object.id}"
    end

    # 投影：每列 ledger 子行展開為「非零 leaf delta ＋ 非零 generated delta」各一筆——
    # 與本尊語義一致（調 available 回 available＋on_hand 兩筆；狀態間移動 on_hand_delta=0 不出現）。
    def changes
      object.inventory_adjustments.order(:position).flat_map do |row|
        entries = []
        %w[available committed reserved damaged safety_stock quality_control].each do |leaf|
          delta = row.public_send("#{leaf}_delta")
          entries << { name: leaf, delta:, row: } unless delta.zero?
        end
        entries << { name: "unavailable", delta: row.unavailable_delta, row: } unless row.unavailable_delta.zero?
        entries << { name: "on_hand", delta: row.on_hand_delta, row: } unless row.on_hand_delta.zero?
        entries
      end
    end
  end
end
