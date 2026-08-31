# frozen_string_literal: true

module Fulfillments
  # 出貨（G6-8 步 5；對位本尊 fulfillmentCreate——官方句「Creates a fulfillment for
  # one or more FulfillmentOrder objects.」，取證 2026-09-01）。
  #
  # ## v1 形＝單 FO（每單一張，CreateFromCheckout 物化）
  # 本尊 input 是 lineItemsByFulfillmentOrder pairs（多 FO 形）；我方 GraphQL 層
  # 照收 pair 陣列（1:1），服務層 v1 只接受**恰一個 pair** 指向該單的可出貨 FO。
  #
  # ## 🔴 庫存：出貨＝committed−（訂單線獨佔——inventory/adjust.rb 檔頭明文
  # 「committed 由訂單線獨佔」；同 CreateFromCheckout 的字串條件式 UPDATE 形，
  # 不走 Inventory::Adjust 也不產 ledger 列——訂單事件的庫存後果不是 adjustment，
  # 與建單扣減同紀律）。level 選擇規則與建單一致（priority 最高）。
  #
  # ## 冪等與併發
  # - 行項扣減＝條件式 UPDATE（fulfillable_quantity >= q 進 WHERE）；affected 0
  #   ＝併發超量 ⇒ Failure 整批 rollback（16 §F1 驗收「雙 staff 併發 fulfill 不超量」）。
  # - order lock! 先行；鎖序＝order → line_items（id 升冪）→ levels（id 升冪），
  #   與建單同序不互咬。
  module Create
    Result = Data.define(:fulfillment, :error) # error = [field, message, code] | nil

    # 交易內部的失敗載體：raise 令整批 rollback，外層轉 userError（鐵律 4 ①）。
    class Failure < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    module_function

    # @param shop [Shop]
    # @param order_id [Integer]
    # @param fulfillment_order_id [Integer] 必須是該單的可出貨 FO
    # @param line_items [Array<Hash>] [{line_item_id:, quantity:}]；空＝全部 fulfillable
    #   （官方 FulfillmentOrderLineItemsInput 逐字「If left blank, all line items of
    #   the fulfillment order will be fulfilled.」）
    # @param tracking [Hash] { company:, numbers: [{number:, url:}] }
    # @param notify_customer [Boolean]
    # @return [Result]
    # @note 副作用：INSERT fulfillments；UPDATE line_items.fulfillable_quantity／
    #   inventory_levels.committed／fulfillment_orders.status／orders.fulfillment_status；
    #   INSERT events＋event_outbox（同交易，鐵律 5）。
    def call(shop:, order_id:, fulfillment_order_id:, line_items: [], tracking: {}, notify_customer: false)
      ActiveRecord::Base.transaction do
        order = Order.lock.find_by(shop_id: shop.id, id: order_id)
        next Result.new(fulfillment: nil, error: [ "id", "找不到這張訂單。", "NOT_FOUND" ]) if order.nil?
        if order.status == "cancelled"
          next Result.new(fulfillment: nil, error: [ "id", "已取消的訂單不能出貨。", "INVALID_STATE" ])
        end

        fo = FulfillmentOrder.find_by(shop_id: shop.id, order_id: order.id, id: fulfillment_order_id)
        if fo.nil?
          next Result.new(fulfillment: nil,
                          error: [ "fulfillmentOrderId", "找不到這張履約工作單。", "NOT_FOUND" ])
        end
        if fo.status == "on_hold"
          # 官方 ON_HOLD 逐字：「The fulfillment process can't be initiated until the
          # hold on the fulfillment order is released.」
          next Result.new(fulfillment: nil,
                          error: [ "fulfillmentOrderId", "此工作單保留中，先解除保留才能出貨。", "INVALID_STATE" ])
        end
        unless %w[open in_progress].include?(fo.status)
          next Result.new(fulfillment: nil,
                          error: [ "fulfillmentOrderId", "此工作單不在可出貨狀態。", "INVALID_STATE" ])
        end

        plan, plan_error = build_plan(shop, order, line_items)
        next Result.new(fulfillment: nil, error: plan_error) if plan_error
        if plan.empty?
          next Result.new(fulfillment: nil, error: [ "fulfillment", "沒有可出貨的品項。", "INVALID" ])
        end

        decrement_fulfillable!(shop, plan)
        release_committed!(shop, plan)

        fulfillment = Fulfillment.create!(
          shop_id: shop.id, fulfillment_order_id: fo.id, status: "success",
          tracking_company: tracking[:company].presence,
          tracking_numbers: Array(tracking[:numbers]).map { |n| { "number" => n[:number], "url" => n[:url] }.compact },
          line_items_snapshot: plan.map { |p| { "line_item_id" => p[:line_item_id], "quantity" => p[:quantity] } },
          shipped_at: Time.current, customer_notified: notify_customer
        )

        remaining = LineItem.where(shop_id: shop.id, order_id: order.id).sum(:fulfillable_quantity)
        fo.update!(status: "closed", closed_at: Time.current) if remaining.zero?
        Orders::FulfillmentStatus.sync!(order)

        Event.create!(shop_id: shop.id, order_id: order.id, kind: "order.fulfilled",
                      happened_at: Time.current, subject_type: "Fulfillment", subject_id: fulfillment.id,
                      metadata: { "items" => plan.sum { |p| p[:quantity] },
                                  "tracking_company" => tracking[:company].to_s.presence }.compact)
        EventOutbox.create!(
          event_id: SecureRandom.uuid, topic: Events::Topics::ORDER_FULFILLED,
          aggregate_type: "Order", aggregate_id: order.id,
          payload: { order_id: order.id, fulfillment_id: fulfillment.id,
                     line_items: fulfillment.line_items_snapshot, notify: notify_customer },
          available_at: Time.current, status: "pending"
        )
        Result.new(fulfillment:, error: nil)
      end
    rescue Failure => e
      Result.new(fulfillment: nil, error: [ "fulfillment", e.message, e.code ])
    end

    # 解析要出的行（先收集後執行——形態 A：任一筆不合法整批不寫）。
    #
    # @return [Array(Array<Hash>, Array, nil)] [plan, error]
    def build_plan(shop, order, line_items)
      rows = LineItem.where(shop_id: shop.id, order_id: order.id).order(:id).to_a
      by_id = rows.index_by(&:id)

      requested =
        if line_items.blank?
          rows.select { |r| r.fulfillable_quantity.positive? }
              .map { |r| { line_item_id: r.id, quantity: r.fulfillable_quantity } }
        else
          line_items.map { |li| { line_item_id: li[:line_item_id].to_i, quantity: li[:quantity].to_i } }
        end

      requested.each do |req|
        row = by_id[req[:line_item_id]]
        return [ [], [ "lineItems", "品項不屬於本訂單。", "NOT_FOUND" ] ] if row.nil?
        if req[:quantity] <= 0 || req[:quantity] > row.fulfillable_quantity
          return [ [], [ "lineItems",
                         "「#{row.title}」的出貨數量超過可出貨量（#{row.fulfillable_quantity}）。", "INVALID" ] ]
        end
      end
      [ requested, nil ]
    end

    # 條件式扣減 fulfillable（affected 0＝併發超量 ⇒ 整批 raise rollback）。
    #
    # @note 副作用：UPDATE line_items。
    def decrement_fulfillable!(shop, plan)
      plan.sort_by { |p| p[:line_item_id] }.each do |p|
        affected = LineItem.where(shop_id: shop.id, id: p[:line_item_id])
                           .where("fulfillable_quantity >= ?", p[:quantity])
                           .update_all([ "fulfillable_quantity = fulfillable_quantity - ?", p[:quantity] ])
        raise Failure.new("INVALID", "出貨數量已被其他操作佔用，請重新整理後再試。") if affected.zero?
      end
    end

    # 出貨釋放 committed（tracked 變體才動；level 選擇同建單規則；id 升冪鎖序）。
    # affected 0＝committed 不足＝不變量已破 ⇒ 誠實 raise，不靜默吞
    # （鐵律 20.2 第 5 類：fail-open 靜默是被擋的形態）。
    #
    # @note 副作用：UPDATE inventory_levels.committed（訂單線獨佔欄）。
    def release_committed!(shop, plan)
      priorities = Location.where(shop_id: shop.id).pluck(:id, :priority).to_h
      moves = plan.filter_map do |p|
        row = LineItem.find_by(shop_id: shop.id, id: p[:line_item_id])
        variant = row&.product_variant_id && ProductVariant.find_by(shop_id: shop.id, id: row.product_variant_id)
        next unless variant && variant.inventory_item&.tracked

        level = variant.inventory_item.inventory_levels
                       .min_by { |l| [ priorities[l.location_id] || 0, l.id ] }
        next if level.nil?

        { level_id: level.id, quantity: p[:quantity], title: row.title }
      end

      moves.sort_by { |m| m[:level_id] }.each do |m|
        affected = InventoryLevel.where(shop_id: shop.id, id: m[:level_id])
                                 .where("committed >= ?", m[:quantity])
                                 .update_all([ "committed = committed - ?", m[:quantity] ])
        raise Failure.new("INVALID_STATE", "「#{m[:title]}」的庫存承諾量不足，請先盤點庫存。") if affected.zero?
      end
    end
  end
end
