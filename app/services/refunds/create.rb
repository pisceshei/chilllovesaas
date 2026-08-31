# frozen_string_literal: true

module Refunds
  # 退款的**唯一寫入入口**（G6-8 步 5；對位本尊 refundCreate——官方句「Creates a
  # refund for an order, allowing you to process returns and issue payments back to
  # customers.」，取證 2026-09-01）。
  #
  # ## 🔴 軟上限＝條件式 UPDATE（16 §F5.1 全契約；limits.refund.* 正典鍵群）
  # 上限檢查與累計寫入在**同一條 SQL**（`refunded_total_cents + amount <=
  # captured_total_cents` 進 WHERE）；affected==0 時**重讀一次只做分類**（回哪個
  # 錯誤碼），不得用重讀值做第二次寫入決策：
  # - 超上限 ⇒ `REFUND_EXCEEDS_MAXIMUM_REFUNDABLE`（前端顯示超額二次確認；
  #   `orders.over_refund` 權限才可續行）
  # - 上限其實夠（併發競爭）⇒ `REFUND_CONCURRENT_MODIFIED`（同鍵原樣重試）
  # 超額路徑**仍是條件式 UPDATE**（上界換成 captured + approved_over_refund，
  # 不是拿掉 WHERE——limits.refund.over_refund_uses_same_conditional_update）。
  # **不做 DB CHECK**（16 §F5.1(e)：擋掉合法超額退款）。
  #
  # ## 金流分流
  # - manual 系 gateway：退款交易列建立即 success、refund.status=success。
  # - PSP（airwallex）：交易列與 refund 落 pending，**交易外**由 ProcessPspRefundJob
  #   打 `/api/v1/pa/refunds/create`（鐵律 5：transaction 內禁外部 IO）。
  #
  # ## restock 的庫存語義（兩種 restock 動的欄不同）
  # - cancel（官方逐字「Use this when restocking unfulfilled line items.」）：
  #   行未出貨 ⇒ committed 還掛著 ⇒ committed−、available+（撤銷承諾）。
  # - return（「Use this when restocking line items that were fulfilled.」）：
  #   已出貨（committed 已在出貨時釋放）⇒ available+（貨回來了）。
  # - no_restock：不動庫存。
  # 直寫 available/committed＝訂單線既有先例（CreateFromCheckout 同形字串條件式
  # UPDATE）；restock 不產 ledger 列（訂單事件的庫存後果，非 adjustment——與
  # 建單扣減同紀律，dev doc 登記）。
  module Create
    Result = Data.define(:refund, :error)

    # 交易內失敗載體（rollback ＋ 外層轉 userError）。
    class Failure < StandardError
      attr_reader :code, :field

      def initialize(code, message, field: "input")
        @code = code
        @field = field
        super(message)
      end
    end

    module_function

    # @param shop [Shop]
    # @param order_id [Integer]
    # @param refund_line_items [Array<Hash>] [{line_item_id:, quantity:, restock_type:}]
    # @param shipping_cents [Integer, nil]
    # @param full_shipping [Boolean]
    # @param note [String, nil]
    # @param notify_customer [Boolean]
    # @param idempotency_key [String]
    # @param allow_over_refund [Boolean] 需 `orders.over_refund` 權限（mutation 層驗）
    # @param staff [StaffMember, nil]
    # @return [Result]
    # @note 副作用：UPDATE orders（條件式累計＋financial_status）；INSERT refunds／
    #   refund_line_items／order_transactions／events／event_outbox；restock 時
    #   UPDATE inventory_levels。PSP 單另 enqueue ProcessPspRefundJob（after commit）。
    def call(shop:, order_id:, refund_line_items: [], shipping_cents: nil, full_shipping: false,
             note: nil, notify_customer: true, idempotency_key:, allow_over_refund: false, staff: nil)
      refund = nil
      ActiveRecord::Base.transaction do
        order = Order.lock.find_by(shop_id: shop.id, id: order_id)
        raise Failure.new("NOT_FOUND", "找不到這張訂單。", field: "orderId") if order.nil?

        # 冪等：同鍵重放回既有結果（uq_refunds_idempotency_key DB 兜底）。
        existing = Refund.find_by(shop_id: shop.id, idempotency_key: idempotency_key)
        if existing
          refund = existing
          raise ActiveRecord::Rollback
        end

        if order.captured_total_cents.zero?
          # Order.refundable 官方逐字「Returns false for orders with no eligible
          # payment transactions.」——未入帳的單沒有可退的錢。
          raise Failure.new("INVALID_STATE", "這張訂單沒有已入帳的款項可退。", field: "orderId")
        end

        suggestion = Calculator.suggest(order:, refund_line_items:, shipping_cents:, full_shipping:)
        if suggestion.error
          field, message, code = suggestion.error
          raise Failure.new(code, message, field: field)
        end
        amount = suggestion.total_cents
        raise Failure.new("INVALID", "退款金額必須大於 0。") if amount <= 0

        apply_cumulative_cap!(shop, order, amount, allow_over_refund)

        gateway = detect_gateway(shop, order)
        psp = gateway == "airwallex"
        transaction = order.order_transactions.create!(
          shop_id: shop.id, kind: "refund", status: psp ? "pending" : "success",
          gateway: gateway, amount_cents: amount, currency: order.currency,
          parent_transaction_id: parent_sale_id(shop, order),
          idempotency_key: "refund-#{idempotency_key}"
        )
        refund = Refund.create!(
          shop_id: shop.id, order_id: order.id, order_transaction_id: transaction.id,
          status: psp ? "pending" : "success", total_cents: amount,
          shipping_cents: suggestion.shipping_cents, currency: order.currency,
          reason: note.presence, customer_notified: notify_customer,
          idempotency_key: idempotency_key, processed_at: Time.current
        )
        suggestion.lines.each do |line|
          RefundLineItem.create!(
            shop_id: shop.id, refund_id: refund.id, line_item_id: line.line_item_id,
            quantity: line.quantity, restock_type: line.restock_type,
            subtotal_cents: line.subtotal_cents, tax_cents: line.tax_cents,
            currency: order.currency
          )
        end

        restock!(shop, order, suggestion.lines)
        sync_financial_status!(order)

        Event.create!(shop_id: shop.id, order_id: order.id, kind: "order.refunded",
                      happened_at: Time.current, subject_type: "Refund", subject_id: refund.id,
                      staff_member_id: staff&.id,
                      metadata: { "amount_cents" => amount, "currency" => order.currency })
        EventOutbox.create!(
          event_id: SecureRandom.uuid, topic: Events::Topics::ORDER_REFUNDED,
          aggregate_type: "Order", aggregate_id: order.id,
          payload: { order_id: order.id, refund_id: refund.id, amount_cents: amount,
                     currency: order.currency, notify: notify_customer },
          available_at: Time.current, status: "pending"
        )
      end

      # PSP 退款在交易外派工（鐵律 5）；manual 已終結不派。
      if refund && refund.status == "pending"
        Refunds::ProcessPspRefundJob.perform_later(refund.shop_id, refund.id)
      end
      Result.new(refund:, error: nil)
    rescue Failure => e
      Result.new(refund: nil, error: [ e.field, e.message, e.code ])
    end

    # 🔴 16 §F5.1 的條件式 UPDATE（正常／超額兩路都是條件式，只換上界）。
    #
    # @note 副作用：UPDATE orders.refunded_total_cents（軟上限的唯一寫入點）。
    def apply_cumulative_cap!(shop, order, amount, allow_over_refund)
      cap_expr = allow_over_refund ? "refunded_total_cents + ? <= captured_total_cents + ?" :
                                     "refunded_total_cents + ? <= captured_total_cents"
      binds = allow_over_refund ? [ amount, amount ] : [ amount ]
      affected = Order.where(shop_id: shop.id, id: order.id)
                      .where(cap_expr, *binds)
                      .update_all([ "refunded_total_cents = refunded_total_cents + ?, updated_at = NOW(6)",
                                    amount ])
      return order.reload if affected == 1

      # affected==0 ⇒ 重讀一次**只做分類**（16 §F5.1(c)；不得用重讀值做第二次寫入決策）
      current = Order.find_by(shop_id: shop.id, id: order.id)
      if current && current.refunded_total_cents + amount > current.captured_total_cents
        raise Failure.new("REFUND_EXCEEDS_MAXIMUM_REFUNDABLE",
                          "退款金額超過可退上限（#{Calculator.maximum_refundable(current)} cents）。",
                          field: "input")
      end

      raise Failure.new("REFUND_CONCURRENT_MODIFIED",
                        "訂單金額剛被其他操作修改，請以同一把冪等鍵重試。", field: "input")
    end

    # restock（兩種 restock 的庫存語義見檔頭；level 選擇同建單規則；id 升冪鎖序）。
    #
    # @note 副作用：UPDATE inventory_levels。
    def restock!(shop, order, lines)
      to_restock = lines.reject { |l| l.restock_type == "no_restock" }
      return if to_restock.empty?

      priorities = Location.where(shop_id: shop.id).pluck(:id, :priority).to_h
      moves = to_restock.filter_map do |line|
        row = LineItem.find_by(shop_id: shop.id, id: line.line_item_id)
        variant = row&.product_variant_id && ProductVariant.find_by(shop_id: shop.id, id: row.product_variant_id)
        next unless variant && variant.inventory_item&.tracked

        level = variant.inventory_item.inventory_levels
                       .min_by { |l| [ priorities[l.location_id] || 0, l.id ] }
        next if level.nil?

        { level_id: level.id, quantity: line.quantity, cancel: line.restock_type == "cancel" }
      end

      moves.sort_by { |m| m[:level_id] }.each do |m|
        if m[:cancel]
          # cancel＝行未出貨：committed−、available+（撤銷承諾；committed 下界防禦）
          affected = InventoryLevel.where(shop_id: shop.id, id: m[:level_id])
                                   .where("committed >= ?", m[:quantity])
                                   .update_all([ "committed = committed - ?, available = available + ?",
                                                 m[:quantity], m[:quantity] ])
          if affected.zero?
            raise Failure.new("INVALID_STATE", "庫存承諾量不足，無法以「取消」方式重新上架。")
          end
        else
          # return＝已出貨：available+（貨回來了）
          InventoryLevel.where(shop_id: shop.id, id: m[:level_id])
                        .update_all([ "available = available + ?", m[:quantity] ])
        end
      end
    end

    # financial_status 推導（16 §F4.3：由交易/累計聚合推導；partially_refunded／
    # refunded 的分界＝官方 REFUNDED「退款額 == 已付額」語義——90-05 §A.6）。
    #
    # @note 副作用：UPDATE orders.financial_status。
    def sync_financial_status!(order)
      order.reload
      value = if order.refunded_total_cents >= order.captured_total_cents
        "refunded"
      elsif order.refunded_total_cents.positive?
        "partially_refunded"
      else
        order.financial_status
      end
      order.update!(financial_status: value) if order.financial_status != value
    end

    # v1 gateway 判定：訂單的成交交易 gateway（manual 系＝立即終結；airwallex＝PSP 流）。
    #
    # @return [String]
    def detect_gateway(shop, order)
      sale = order.order_transactions.where(kind: %w[sale capture], status: "success").order(:id).last
      gateway = sale&.gateway.to_s
      gateway.start_with?("airwallex") ? "airwallex" : (gateway.presence || "manual")
    end

    # 退款交易的父交易（官方 OrderTransactionInput.parentId 對位：
    # 「the authorization of a capture」同構——refund 的父＝成交列）。
    #
    # @return [Integer, nil]
    def parent_sale_id(shop, order)
      order.order_transactions.where(kind: %w[sale capture], status: "success").order(:id).last&.id
    end
  end
end
