# frozen_string_literal: true

module Types
  # 分析總覽（G6 步 10；19-F2.3 單次往返全卡片）。
  class AnalyticsOverviewType < BaseObject
    graphql_name "AnalyticsOverview"
    description "期間指標卡（rollup 聚合；今日新鮮度 ≤ rollup 週期）"

    field :total_sales_cents, Integer, null: false, description: "🔴 可為負（80 §3）"
    field :net_sales_cents, Integer, null: false
    field :gross_sales_cents, Integer, null: false
    field :discounts_cents, Integer, null: false
    field :returns_cents, Integer, null: false
    field :shipping_cents, Integer, null: false
    field :taxes_cents, Integer, null: false
    field :orders_count, Integer, null: false
    field :units_sold, Integer, null: false
    field :aov_cents, Integer, null: false,
          description: "分子排除 post-order adjustments（官方例外；AOV×Orders≠Total sales）"
    field :series, [ AnalyticsSeriesPointType ], null: false, description: "逐日 total_sales"
  end
end
