# frozen_string_literal: true

module Types
  # 訂單（G6-6a；契約對位 Admin API Order 的最小可用面——88 §7 官方取證＋
  # 90-blueprint/04/05 狀態機正典）。
  #
  # - 三狀態軸彼此獨立（order.rb 檔頭）：status／displayFinancialStatus／
  #   displayFulfillmentStatus 各自 enum。
  # - 金額欄一律 MoneyBag（鐵律 3 序列化層；v1 單幣兩腳同值）。
  # - lineItems／transactions v1＝list 非 connection（本尊 transactions/
  #   fulfillments 亦為 list；lineItems 本尊是 connection——我方單量級 v1 先 list，
  #   量級上來時換 connection，登記 ours）。
  # - customer 可 null（guest 無 email 單；G6-7 管線只在有 email 時歸戶）。
  class OrderType < BaseObject
    graphql_name "Order"
    description "訂單（結帳成立或後台建立）"

    implements Interfaces::Node

    field :legacy_resource_id, ID, null: false, method: :id
    field :name, String, null: false, description: "顯示單號（#1001 形）"
    field :order_number, Integer, null: false
    field :email, String, null: true
    field :buyer_accepts_marketing, Boolean, null: false
    field :status, String, null: false, description: "open/closed/cancelled（生命週期軸）"
    field :display_financial_status, OrderDisplayFinancialStatusEnum, null: false,
          method: :financial_status
    field :display_fulfillment_status, OrderDisplayFulfillmentStatusEnum, null: false,
          method: :fulfillment_status
    field :currency_code, String, null: false, method: :currency
    field :note, String, null: true
    field :tags, [ String ], null: false
    field :subtotal_price_set, MoneyBagType, null: false
    field :total_shipping_price_set, MoneyBagType, null: false
    field :total_tax_set, MoneyBagType, null: false
    field :total_discounts_set, MoneyBagType, null: false
    field :total_price_set, MoneyBagType, null: false
    field :line_items, [ LineItemType ], null: false
    field :transactions, [ OrderTransactionType ], null: false
    field :customer, CustomerType, null: true
    field :shipping_address, OrderAddressType, null: true
    field :billing_address, OrderAddressType, null: true
    field :processed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :canceled_at, GraphQL::Types::ISO8601DateTime, null: true
    field :archived_at, GraphQL::Types::ISO8601DateTime, null: true

    def id
      "gid://chilllove/Order/#{object.id}"
    end

    def tags
      Array(object.tags)
    end

    def line_items
      object.line_items.order(:id)
    end

    def transactions
      object.order_transactions.order(:id)
    end

    def shipping_address
      object.shipping_address.presence
    end

    def billing_address
      # billing json 帶 mode 鍵（same_as_shipping/different）：same 時出貨快照即帳單
      billing = object.billing_address
      return object.shipping_address.presence if billing.blank? || billing["mode"] != "different"

      # different 形的鍵帶 billing_ 前綴落庫（checkout persist 面）——出口剝前綴
      stripped = billing.transform_keys { |k| k.to_s.sub(/\Abilling_/, "") }
      stripped.except("mode").presence
    end

    { subtotal_price_set: :subtotal_cents, total_shipping_price_set: :shipping_cents,
      total_tax_set: :tax_cents, total_discounts_set: :discount_cents,
      total_price_set: :total_cents }.each do |field_name, column|
      define_method(field_name) do
        { cents: object.public_send(column), currency: object.currency,
          presentment_cents: field_name == :total_price_set ? object.presentment_total_cents : object.public_send(column),
          presentment_currency: object.presentment_currency }
      end
    end
  end
end
