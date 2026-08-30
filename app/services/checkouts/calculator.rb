# frozen_string_literal: true

# 命名對映：15 F2 的規格名 Checkout::Calculator——Checkout 已是 AR model 類
# （module 與 class 同名不能並存），服務命名空間取複數 Checkouts::
# （倉內 UrlRedirects::／Translations:: 同慣例）；功能契約不變。
module Checkouts
  # 金額引擎（15 F2；結帳線第一包）。
  #
  # ①純函式 PORO：輸入（行快照／運費選擇／折扣／稅設定）→ 不可變 Result，
  #   **全程 integer cents**（鐵律 3）。🔴 任何 Float 輸入 ⇒ TypeError（比率用
  #   Integer／Rational／BigDecimal；「出現 float 即 bug」）。
  # ②🔴 一處實作、四處重用（F2-2）：checkout 預覽／訂單成立／draft order／退款
  #   全吃同一 Result——頁面上任何金額都來自它，杜絕兩處總計不一致。
  # ③分攤（F2-3）：訂單級折扣按行金額比例、**最大餘數法**補差——
  #   `Σ 行分攤 = 折扣總額` 恆等；餘數依（餘數大→行金額大→行序）決定去向（確定性）。
  # ④稅（F2-4）：未稅＝行級 `round(taxable × rate)` 加總；含稅＝行級反推
  #   `taxable - round(taxable / (1+rate))` 加總。🔴 **行級進位、全域一致**——
  #   退款查行級分攤不得按比例重算（F2 坑 2）。運費 v1 不課稅（HK 基準法域無銷售稅，
  #   鐵律 11；法域 pack 接上時由呼叫端把運費稅列入 tax 輸入，登記）。
  # ⑤設定變更不回溯（F2 坑 3）：本引擎無任何 DB 讀取——快照進、Result 出。
  class Calculator
    Line = Data.define(:key, :quantity, :unit_price_cents, :line_total_cents)
    Result = Data.define(:currency, :lines, :subtotal_cents, :discount_total_cents,
                         :discount_allocations, :shipping_cents, :tax_included,
                         :tax_total_cents, :tax_lines, :total_cents)

    class << self
      # @param lines [Array<Hash>] `{key:, quantity:, unit_price_cents:}`（快照值，不讀 DB）
      # @param currency [String] ISO 4217（Result 攜帶；引擎本身不看幣別——儲存尺度一律 ×100）
      # @param shipping_cents [Integer] 已選運費（合併運費解析＝F2.1 的 ShippingRateMerger，另包）
      # @param discount [Hash, nil] `{type: "percentage", value: Integer|Rational}` ∥
      #   `{type: "fixed_amount", value_cents: Integer}`；訂單級（行級折扣另包）
      # @param tax [Hash, nil] `{rate: Rational|BigDecimal|Integer, included: true|false}`
      # @return [Result] 不可變；全 Integer cents
      # @raise [TypeError] 任何金額為 Float／比率為 Float（鐵律 3）
      # @raise [ArgumentError] 數量非正、金額為負、折扣型別未知
      def call(lines:, currency:, shipping_cents: 0, discount: nil, tax: nil)
        built = build_lines(lines)
        shipping = money!(shipping_cents, "shipping_cents")
        raise ArgumentError, "shipping_cents 不得為負" if shipping.negative?

        subtotal = built.sum(&:line_total_cents)
        discount_total = discount_total_for(discount, subtotal)
        allocations = allocate(discount_total, built)
        tax_lines, tax_total, included = tax_for(tax, built, allocations)

        total = subtotal - discount_total + shipping + (included ? 0 : tax_total)
        Result.new(
          currency: currency.to_s.upcase, lines: built.freeze,
          subtotal_cents: subtotal, discount_total_cents: discount_total,
          discount_allocations: allocations.freeze, shipping_cents: shipping,
          tax_included: included, tax_total_cents: tax_total, tax_lines: tax_lines.freeze,
          total_cents: total
        )
      end

      # 最大餘數法（F2-3；規格碼形的確定性版）。
      # @param total_cents [Integer] 要分攤的總額
      # @param weighted [Array<Line>] 權重＝行金額
      # @return [Hash{String => Integer}] key → 分攤 cents；`Σ = total_cents` 恆等
      def allocate(total_cents, weighted)
        weight_sum = weighted.sum(&:line_total_cents)
        return weighted.to_h { |line| [ line.key, 0 ] } if total_cents.zero? || weight_sum.zero?

        base = weighted.map { |line| total_cents * line.line_total_cents / weight_sum } # 整數除法向下
        remainder = total_cents - base.sum
        order = weighted.each_index.sort_by do |i|
          [ -(weighted[i].line_total_cents * total_cents % weight_sum), # 餘數大者先
            -weighted[i].line_total_cents,                              # 再看行金額大者（F2-3 prose）
            i ]                                                         # 最後行序（確定性）
        end
        order.first(remainder).each { |i| base[i] += 1 }
        weighted.each_with_index.to_h { |line, i| [ line.key, base[i] ] }
      end

      private

      def build_lines(lines)
        raise ArgumentError, "至少要有一行" if lines.nil? || lines.empty?

        lines.each_with_index.map do |raw, index|
          quantity = raw.fetch(:quantity)
          unit = money!(raw.fetch(:unit_price_cents), "unit_price_cents")
          raise ArgumentError, "quantity 必須為正整數" unless quantity.is_a?(Integer) && quantity.positive?
          raise ArgumentError, "unit_price_cents 不得為負" if unit.negative?

          key = (raw[:key] || index.to_s).to_s
          Line.new(key:, quantity:, unit_price_cents: unit, line_total_cents: unit * quantity)
        end
      end

      # 🔴 Float 即 bug（F2 坑 1）：整條金額路徑的型別閘。
      def money!(value, label)
        raise TypeError, "#{label} 必須是 Integer cents，實得 #{value.class}（鐵律 3）" unless value.is_a?(Integer)

        value
      end

      def rate!(value, label)
        case value
        when Integer then Rational(value)
        when Rational then value
        when BigDecimal then value.to_r
        else
          raise TypeError, "#{label} 必須是 Integer／Rational／BigDecimal，實得 #{value.class}" \
                           "（Float 的十進位表示不穩定——鐵律 3）"
        end
      end

      # 折扣總額（🔴 上限＝小計：折扣大於小計 ⇒ 收斂，總計非負不變量）。
      def discount_total_for(discount, subtotal)
        return 0 if discount.nil?

        total = case discount.fetch(:type).to_s
        when "percentage"
          percent = rate!(discount.fetch(:value), "discount.value")
          raise ArgumentError, "百分比折扣值域 0..100" if percent.negative? || percent > 100

          (subtotal * percent / 100r).round # 半數進位；進位策略全域一致（F2-4 同款紀律）
        when "fixed_amount"
          amount = money!(discount.fetch(:value_cents), "discount.value_cents")
          raise ArgumentError, "固定折扣不得為負" if amount.negative?

          amount
        else
          raise ArgumentError, "未知折扣型別 #{discount[:type].inspect}"
        end
        [ total, subtotal ].min
      end

      # 行級稅（F2-4）：課稅基礎＝行金額 − 該行折扣分攤（先折後稅）。
      # @return [Array(Hash, Integer, Boolean)] [每行稅, 稅總額, 是否內含]
      def tax_for(tax, built, allocations)
        return [ {}, 0, false ] if tax.nil?

        rate = rate!(tax.fetch(:rate), "tax.rate")
        raise ArgumentError, "稅率不得為負" if rate.negative?

        included = tax.fetch(:included)
        tax_lines = built.to_h do |line|
          taxable = line.line_total_cents - allocations.fetch(line.key)
          cents = if included
            taxable - (Rational(taxable) / (1r + rate)).round # 反推：total − total/(1+rate)
          else
            (Rational(taxable) * rate).round
          end
          [ line.key, cents ]
        end
        [ tax_lines, tax_lines.values.sum, included ]
      end
    end
  end
end
