# frozen_string_literal: true

module Refunds
  # 退款金額計算的**唯一產生處**（G6-8 步 5；16 §F5.1 公式的 v1 子集＋鐵律 7
  # 「returnCalculate 與 returnProcess 必須共用同一份計算程式碼」——本類即那一份：
  # `Order.suggestedRefund`（預覽）與 `Refunds::Create`（實際退款）都呼叫這裡，
  # 預覽與實退若能對不上就是 bug）。
  #
  # ## v1 射程（16 §F5.1 全式的落地子集，缺項逐條登記）
  # - 有：line_gross／訂單級折扣分攤（最大餘數法）／稅分攤（最大餘數法）／運費／
  #   maximum_refundable（= captured − refunded，limits.refund.cumulative_cap_formula）。
  # - 無（v1 無資料來源，dev doc 登記）：restocking fee（無退貨費設定）／換貨扣抵
  #   （無 exchange 線）／outstanding（manual 付款單未付時 refundable=false，走不到）。
  #
  # ## 🔴 捨入紀律（鐵律 3＋16 §F5.1）
  # 全程 integer cents、零 float；唯一的分攤法＝**最大餘數法**（Σ 分攤 == 原始總額，
  # 分完的分不多不少）。多次部分退款的一致性：分攤按**單位**切（per-unit 表），
  # 第 n 次退款取第 [已退量, 已退量+本次量) 個單位的分攤和 ⇒ 全部退完時
  # Σ 各次分攤 == 行分攤總額，精確無殘差。
  module Calculator
    Line = Data.define(:line_item_id, :quantity, :subtotal_cents, :tax_cents, :restock_type)
    Suggestion = Data.define(:lines, :subtotal_cents, :tax_cents, :shipping_cents,
                             :total_cents, :maximum_refundable_cents, :error)

    module_function

    # @param order [Order]
    # @param refund_line_items [Array<Hash>] [{line_item_id:, quantity:, restock_type:}]
    # @param shipping_cents [Integer, nil] 指定退運費額；nil 且 full_shipping=false＝不退運費
    # @param full_shipping [Boolean] 全退剩餘可退運費（官方 ShippingRefundInput.fullRefund 對位）
    # @return [Suggestion] error 非 nil 時其餘欄位為 0/[]
    # @note 副作用：數次 SELECT（行項／既有退款聚合）；不寫入。
    def suggest(order:, refund_line_items: [], shipping_cents: nil, full_shipping: false)
      rows = LineItem.where(shop_id: order.shop_id, order_id: order.id).order(:id).to_a
      by_id = rows.index_by(&:id)
      already = refunded_quantities(order)

      discount_by_line = allocate_proportional(order.discount_cents, rows.map { |r| [ r.id, r.total_cents ] })
      tax_by_line = allocate_proportional(order.tax_cents,
                                          rows.select(&:taxable).map { |r| [ r.id, r.total_cents ] })

      lines = []
      Array(refund_line_items).each do |req|
        row = by_id[req[:line_item_id].to_i]
        return failure("品項不屬於本訂單。", "NOT_FOUND") if row.nil?

        qty = req[:quantity].to_i
        refundable = row.quantity - already.fetch(row.id, 0)
        if qty <= 0 || qty > refundable
          return failure("「#{row.title}」的退款數量超過可退量（#{refundable}）。", "INVALID")
        end

        gross = row.unit_price_cents * qty
        disc = units_sum(discount_by_line.fetch(row.id, 0), row.quantity, already.fetch(row.id, 0), qty)
        tax = units_sum(tax_by_line.fetch(row.id, 0), row.quantity, already.fetch(row.id, 0), qty)
        lines << Line.new(line_item_id: row.id, quantity: qty,
                          subtotal_cents: gross - disc, tax_cents: tax,
                          restock_type: (req[:restock_type] || "no_restock").to_s)
      end

      shipping = resolve_shipping(order, shipping_cents, full_shipping)
      return shipping if shipping.is_a?(Suggestion) # 上限錯誤直接回

      subtotal = lines.sum(&:subtotal_cents)
      tax_total = lines.sum(&:tax_cents)
      Suggestion.new(
        lines:, subtotal_cents: subtotal, tax_cents: tax_total, shipping_cents: shipping,
        total_cents: subtotal + tax_total + shipping,
        maximum_refundable_cents: maximum_refundable(order), error: nil
      )
    end

    # 軟上限（16 §F5.1；官方語義錨＝RefundInput.allowOverRefunding 逐字「Whether to
    # allow the total refunded amount to surpass **the amount paid for the order**.」
    # ⇒ 上限基線＝已付額）。
    #
    # @return [Integer]
    def maximum_refundable(order)
      [ order.captured_total_cents - order.refunded_total_cents, 0 ].max
    end

    # 各行已退量（多次部分退款的 per-unit 游標）。
    # @return [Hash{Integer => Integer}]
    def refunded_quantities(order)
      RefundLineItem.joins(:refund)
                    .where(shop_id: order.shop_id, refunds: { order_id: order.id })
                    .where.not(refunds: { status: "failure" })
                    .group(:line_item_id).sum(:quantity)
    end

    # 已退運費合計（可退運費上限的分子）。
    # @return [Integer]
    def refunded_shipping(order)
      Refund.where(shop_id: order.shop_id, order_id: order.id)
            .where.not(status: "failure").sum(:shipping_cents)
    end

    # ── 內部：分攤原語 ──────────────────────────────────────────────────────

    # 把 total 按 weights（[[key, weight]]）比例分攤（最大餘數法：先按整數比例
    # floor，餘數依小數餘額大小遞減補 1，Σ == total 精確）。
    #
    # @return [Hash{key => Integer}]
    def allocate_proportional(total, weights)
      return {} if total.to_i.zero? || weights.empty?

      weight_sum = weights.sum { |_, w| w }
      return weights.to_h { |k, _| [ k, 0 ] } if weight_sum.zero?

      shares = weights.map do |key, w|
        exact_num = total * w                      # 整數分子（避免 float）
        base = exact_num / weight_sum              # floor
        [ key, base, exact_num % weight_sum ]      # 餘數＝小數部分的分子
      end
      remainder = total - shares.sum { |_, base, _| base }
      # 餘數大者優先補 1（平手依 key 升冪，確定性）
      shares.sort_by { |key, _, rem| [ -rem, key ] }.each_with_index.to_h do |(key, base, _), idx|
        [ key, base + (idx < remainder ? 1 : 0) ]
      end
    end

    # 行分攤額按單位切開後，取第 [offset, offset+count) 個單位的和。
    # per-unit 切分同為最大餘數法（前 remainder 個單位各多 1 分）⇒ 多次退款
    # 的分攤和恆等於一次退完的分攤（無殘差、與退款次序無關的總和）。
    #
    # @return [Integer]
    def units_sum(line_total, line_quantity, offset, count)
      return 0 if line_total.to_i.zero? || line_quantity.to_i.zero?

      base = line_total / line_quantity
      remainder = line_total % line_quantity
      (offset...(offset + count)).sum { |i| base + (i < remainder ? 1 : 0) }
    end

    # 運費退款（16 §F5.1：amount 與 fullRefund 二選一；退運費不得超過可退運費）。
    #
    # @return [Integer, Suggestion] 金額或錯誤結果
    def resolve_shipping(order, shipping_cents, full_shipping)
      available = [ order.shipping_cents - refunded_shipping(order), 0 ].max
      return available if full_shipping
      return 0 if shipping_cents.nil?

      amount = shipping_cents.to_i
      return failure("退運費不得為負數。", "INVALID") if amount.negative?
      if amount > available
        return failure("退運費不得超過可退運費（#{available}）。", "INVALID")
      end

      amount
    end

    # @return [Suggestion]
    def failure(message, code)
      Suggestion.new(lines: [], subtotal_cents: 0, tax_cents: 0, shipping_cents: 0,
                     total_cents: 0, maximum_refundable_cents: 0,
                     error: [ "refundLineItems", message, code ])
    end
  end
end
