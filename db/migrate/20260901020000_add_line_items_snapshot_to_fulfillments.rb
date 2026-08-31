# frozen_string_literal: true

# G6-8（步 5）：fulfillments 補行項明細欄。
#
# M0 的 fulfillments 表沒有行項子表（本尊有 FulfillmentLineItem）；v1 以 json
# 快照承載 [{"line_item_id":…,"quantity":…}]——fulfillmentCancel 的官方語義要求
# 「取消的品項可再出貨」（fulfillmentCancel 描述逐字 "the system creates new
# fulfillment orders for the cancelled items so they can be fulfilled again."，
# 取證 2026-09-01）⇒ 不記行項明細就無法知道該回加多少 fulfillable_quantity。
# 日後多地點線把它升級成子表時，本欄是一次可讀的遷移來源。
class AddLineItemsSnapshotToFulfillments < ActiveRecord::Migration[8.1]
  def change
    add_column :fulfillments, :line_items_snapshot, :json, null: false,
      comment: "出貨行項明細 [{line_item_id, quantity}]（cancel 回加與 UI 顯示的依據）"
  end
end
