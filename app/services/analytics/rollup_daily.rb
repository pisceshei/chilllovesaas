# frozen_string_literal: true

module Analytics
  # 日聚合計算（G6 步 10；19-F2）。
  #
  # ①口徑（80 §3／19-F1）：
  #   gross_sales＝Σ 訂單行小計（折前；orders.subtotal_cents＋discount_cents 之和
  #     即折前——我方 subtotal 存折後淨值 ⇒ 折前＝subtotal＋discount）
  #   discounts＝Σ orders.discount_cents（負向指標存正值，查詢端負號）
  #   returns＝Σ refunds.total_cents（**落退款日**，不回改訂單日——19-F1 必測②同構）
  #   net_sales＝gross − discounts − returns（同日各項相減；跨日由查詢端 Σ）
  #   total_sales＝net ＋ shipping ＋ taxes（🔴 可為負）
  #   aov_numerator/denominator＝成立日的 Σtotal 與單數（分子**不含**退款——紅線①）
  # ②日界線＝**shop 時區**（19-F2 坑；23:59:59/00:00 有測試釘住）。
  # ③冪等：整日重算 + upsert 覆蓋（不是累加——重跑同值）。
  class RollupDaily
    class << self
      # @param shop [Shop]
      # @param date [Date] shop 時區的日
      def call(shop:, date:)
        tz = ActiveSupport::TimeZone[shop.timezone] || Time.zone
        day_start = tz.local(date.year, date.month, date.day)
        day_range = day_start...(day_start + 1.day)

        orders = Order.where(shop_id: shop.id, processed_at: day_range)
                      .where.not(status: "deleted")
        refunds = Refund.where(shop_id: shop.id, status: %w[success pending],
                               processed_at: day_range)

        subtotal = orders.sum(:subtotal_cents)
        discounts = orders.sum(:discount_cents)
        shipping = orders.sum(:shipping_cents)
        taxes = orders.sum(:tax_cents)
        returns = refunds.sum(:total_cents)
        orders_count = orders.count
        totals = orders.sum(:total_cents)
        units = LineItem.joins(:order)
                        .where(orders: { shop_id: shop.id, processed_at: day_range })
                        .where(shop_id: shop.id).sum(:quantity)

        gross = subtotal + discounts # 我方 subtotal＝折後 ⇒ 折前＝加回 discount
        net = gross - discounts - returns
        values = {
          "gross_sales" => gross, "discounts" => discounts, "returns" => returns,
          "net_sales" => net, "shipping_charges" => shipping, "taxes" => taxes,
          "total_sales" => net + shipping + taxes,
          "orders_count" => orders_count, "units_sold" => units,
          "aov_numerator" => totals, "aov_denominator" => orders_count
        }
        upsert_all!(shop, date, values)
        values
      end

      private

      # upsert 覆蓋制（19-F2 坑：累加制重跑就翻倍）。
      def upsert_all!(shop, date, values)
        now = Time.current
        rows = values.map do |metric, value|
          { shop_id: shop.id, date:, metric:, dimension: "", value:,
            created_at: now, updated_at: now }
        end
        # MySQL 的 upsert_all 不收 :unique_by——ON DUPLICATE KEY 由 uq 索引驅動
        DailyRollup.upsert_all(rows, update_only: [ :value ])
      end
    end
  end
end
