# frozen_string_literal: true

module Types
  # 訂單行項（G6-6a；快照語義——title/sku/unit_price 定格於成單時點，
  # 商品其後改名改價不回寫；line_item.rb 檔頭同一契約）。
  class LineItemType < BaseObject
    graphql_name "LineItem"
    description "訂單行項（成單時點快照）"

    field :id, GraphQL::Types::ID, null: false
    field :title, String, null: false
    field :variant_title, String, null: true
    field :sku, String, null: true
    field :vendor, String, null: true
    field :quantity, Integer, null: false
    field :fulfillable_quantity, Integer, null: false,
      description: "還可出貨的數量（G6-8；官方 LineItem.fulfillableQuantity 對位）"
    field :requires_shipping, Boolean, null: false
    field :unit_price_set, MoneyBagType, null: false, description: "單價（快照）"
    field :total_set, MoneyBagType, null: false, description: "行小計（含行折扣後）"
    field :product_variant_id, GraphQL::Types::ID, null: true,
          description: "快照指回的變體 GID（變體已刪時 null——快照不是外鍵）"

    def id
      "gid://chilllove/LineItem/#{object.id}"
    end

    def unit_price_set
      { cents: object.unit_price_cents, currency: object.currency }
    end

    def total_set
      { cents: object.total_cents, currency: object.currency }
    end

    def product_variant_id
      object.product_variant_id && "gid://chilllove/ProductVariant/#{object.product_variant_id}"
    end
  end
end
