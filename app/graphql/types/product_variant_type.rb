# frozen_string_literal: true

module Types
  # 商品變體（admin 編輯頁讀取面；v1＝隱含變體，具名選項屬變體包）。
  #
  # 🔴 金額欄位一律 **R4 十進位字串**出向（65 §B X2：cents/100 恆兩位小數）——
  # 走 `Money::Storage#to_decimal`，不得在 GraphQL 層手算除法。
  class ProductVariantType < BaseObject
    graphql_name "ProductVariant"
    description "商品變體。"

    field :id, ID, null: false, description: "gid://chilllove/ProductVariant/{id}"
    field :legacy_resource_id, ID, null: false
    field :title, String, null: false,
      description: "變體標題；隱含變體恆為 Default Title（Liquid 硬相容契約）。"
    field :price, String, null: false, description: "售價（主單位十進位字串，恆兩位小數）。"
    field :compare_at_price, String, null: true, description: "原價（劃線價），格式同 price。"
    field :cost, String, null: true, description: "每品項成本，格式同 price；不對顧客顯示。"
    field :sku, String, null: true
    field :barcode, String, null: true
    field :taxable, Boolean, null: false
    field :position, Integer, null: false
    # 第 21 包：本尊 SelectedOption 形（name/value 扁平對；隱含變體＝空陣列）。
    field :selected_options, [ Types::SelectedOptionType ], null: false,
      description: "選中的選項（選項 position 序；隱含變體為空）。"

    # @return [String] GID
    def id
      "gid://chilllove/ProductVariant/#{object.id}"
    end

    # @return [String] 十進位主鍵字串
    def legacy_resource_id
      object.id.to_s
    end

    # @return [String] R4 字串
    def price
      Money::Storage.from_cents(object.price_cents, object.currency).to_decimal.string
    end

    # @return [String, nil]
    def compare_at_price
      cents = object.compare_at_price_cents
      cents && Money::Storage.from_cents(cents, object.currency).to_decimal.string
    end

    # @return [String, nil]
    def cost
      cents = object.cost_cents
      cents && Money::Storage.from_cents(cents, object.currency).to_decimal.string
    end

    # @return [Array<Hash>] 座標展開為 {name:, value:}（依選項 position 排序）。
    #   關聯已由 ProductType#variants preload——這裡只走記憶體。
    def selected_options
      object.product_variant_option_values
            .sort_by { |pvov| pvov.product_option.position }
            .map { |pvov| { name: pvov.product_option.name, value: pvov.option_value.value } }
    end
  end
end
