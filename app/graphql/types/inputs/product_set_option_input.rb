# frozen_string_literal: true

module Types
  module Inputs
    # productSet 的選項樹（第 22 包／B2：全走 productSet，宣告式全量——
    # 未列出的既有選項視為刪除；values 依陣列序決定 position）。
    class ProductSetOptionInput < GraphQL::Schema::InputObject
      argument :name, String, required: true, description: "選項名（同商品唯一）。"
      argument :values, [ String ], required: true,
        description: "選項值（陣列序＝position；同選項內唯一非空）。"
    end
  end
end
