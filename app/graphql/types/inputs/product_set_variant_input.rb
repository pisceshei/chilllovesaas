# frozen_string_literal: true

module Types
  module Inputs
    # `productSet` 的變體子輸入（v1＝隱含變體那一筆；具名選項屬後續包）。
    #
    # 🔴 金額欄位一律 **R4 十進位字串**（65 §B X12：主單位、恆兩位小數、無符號、
    # 無千分位），服務端經 `Money::Decimal` 轉 integer cents——**input 不收
    # Float／Int 金額**（鐵律 3：出現 float 即 bug）。
    #
    # B1-5（`product_input_forbidden_fields`）的射程是 Product 層 input——
    # 價格本來就住在變體層，經本型別進來不違反禁令（63 §B.1／§B.3：
    # `variant_price_write_mutations` 含 productSet）。
    #
    # @see docs/specs/65-money-unit-boundary.md §B X12
    class ProductSetVariantInput < GraphQL::Schema::InputObject
      graphql_name "ProductSetVariantInput"
      description "productSet 的變體輸入。"

      argument :id, ID, required: false,
        description: "更新既有變體時帶（primary match key，limits variant_identity_id_wins）；缺席＝以投影後 digest 比對或新建。"
      argument :option_values, [ Types::Inputs::VariantOptionValueInput ], required: false,
        description: "選項座標（有 options 樹時每選項恰一值）。"
      argument :initial_quantities, [ Types::Inputs::InitialQuantityInput ], required: false,
        description: "初始可售量（create-only；帶 id 時給它＝INVALID）。"
      argument :price, String, required: false,
        description: "售價（主單位十進位字串，恆兩位小數，例：128.00）。建立時必填。"
      argument :compare_at_price, String, required: false,
        description: "原價（劃線價），格式同 price。"
      argument :cost, String, required: false,
        description: "每品項成本，格式同 price；不對顧客顯示。"
      argument :sku, String, required: false, description: "SKU（軟唯一：重複警告不阻擋）。"
      argument :barcode, String, required: false, description: "條碼（ISBN／UPC／GTIN）。"
      argument :taxable, Boolean, required: false, description: "是否收取稅金（預設 true）。"
    end
  end
end
