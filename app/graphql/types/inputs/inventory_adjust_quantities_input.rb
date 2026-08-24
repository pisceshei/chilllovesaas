# frozen_string_literal: true

module Types
  module Inputs
    # inventoryAdjustQuantities 的輸入（差額模式）。
    class InventoryAdjustQuantitiesInput < GraphQL::Schema::InputObject
      graphql_name "InventoryAdjustQuantitiesInput"

      argument :reason, String, required: true,
        description: "17 值全集見 limits.inventory.adjustment_reasons（UI 手動下拉只露 7 值子集）。"
      argument :name, String, required: true,
        description: "可調：available/on_hand/reserved/damaged/safety_stock/quality_control。" \
                     "on_hand 的寫入語義＝翻譯成 available 的 delta。"
      argument :reference_document_uri, String, required: false,
        description: "答「為什麼動」；純稽核、不去重（本尊語義）。"
      argument :changes, [ Types::Inputs::InventoryChangeInput ], required: true

      # ⚠️ changeFromQuantity 的 required: :nullable 加嚴刻意**不在本包**（G28 只批了
      # idempotencyKey；該欄位語義是「可顯式傳 null 跳過檢查」，形態待使用者裁定）。
    end
  end
end
