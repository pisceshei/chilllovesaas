# frozen_string_literal: true

module Types
  # 歷程頁單一數量欄的變動（delta ＋ 期後值）。
  #
  # 實測 94 §2.5 的儲存格格式是「increased by 1 for a total of 10 (+1)」
  # ——delta 與期後值**同格顯示**，所以兩個值必須一起回，前端不自行累加。
  class InventoryHistoryChangeType < BaseObject
    graphql_name "InventoryHistoryChange"
    description "歷程列中單一數量名的變動與期後值。"

    field :name, String, null: false, description: "數量名（unavailable/committed/available/on_hand/incoming）。"
    field :delta, Integer, null: false
    field :quantity_after_change, Integer, null: false,
      description: "該次調整後的數量（本尊 InventoryChange.quantityAfterChange）；" \
                   "🔴 由 running sum 算出且**在日期過濾之前開窗**——順序反了每列都會偏移。"

    def name = object.fetch(:name)
    def delta = object.fetch(:delta)
    def quantity_after_change = object.fetch(:after)
  end
end
