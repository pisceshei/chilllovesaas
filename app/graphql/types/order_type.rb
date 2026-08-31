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
    field :item_count, Integer, null: false,
          description: "行項數量合計（列表 Items 欄；88 §2）"
    field :transactions, [ OrderTransactionType ], null: false
    # G6-8（步 5）：官方 Order.fulfillments 與 Order.refunds 都是 **list 非 connection**
    #（ord-4 §7 逐字，取證 2026-09-01）——我方同形。
    field :fulfillments, [ FulfillmentType ], null: false,
      description: "出貨清單（含已取消）"
    field :fulfillment_orders, [ FulfillmentOrderType ], null: false,
      description: "履約工作單（v1 每單一張）"
    field :refunds, [ RefundType ], null: false, description: "退款清單"
    field :suggested_refund, SuggestedRefundType, null: true,
      description: "退款金額預覽（與 refundCreate 實退共用同一份計算——鐵律 7）" do
      argument :refund_line_items, [ Inputs::RefundLineItemInput ], required: false
      argument :refund_shipping, Boolean, required: false, default_value: false,
        description: "全退剩餘可退運費（官方 refundShipping 對位）"
      argument :shipping_amount_cents, Integer, required: false,
        description: "指定退運費額（integer cents；官方 shippingAmount 對位——覆蓋 refundShipping）"
    end
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

    def item_count
      object.line_items.sum(&:quantity)
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

  # ── G6-8：履約與退款讀出 ─────────────────────────────────────────────────

  def fulfillments
    Fulfillment.joins(:fulfillment_order)
               .where(shop_id: object.shop_id, fulfillment_orders: { order_id: object.id })
               .order(:id)
  end

  def fulfillment_orders
    object.fulfillment_orders.order(:id)
  end

  def refunds
    object.refunds.order(:id)
  end

  # 預覽與實退同一份計算（Refunds::Calculator；鐵律 7）。
  def suggested_refund(refund_line_items: [], refund_shipping: false, shipping_amount_cents: nil)
    lines = Array(refund_line_items).map do |li|
      numeric = li[:line_item_id].to_s[%r{\Agid://chilllove/LineItem/(\d+)\z}, 1]
      return nil if numeric.nil?

      { line_item_id: numeric.to_i, quantity: li[:quantity], restock_type: li[:restock_type] }
    end
    suggestion = Refunds::Calculator.suggest(
      order: object, refund_line_items: lines,
      shipping_cents: shipping_amount_cents, full_shipping: refund_shipping && shipping_amount_cents.nil?
    )
    return nil if suggestion.error

    { suggestion:, currency: object.currency }
  end
  end
end
