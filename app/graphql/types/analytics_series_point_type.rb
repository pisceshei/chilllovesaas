# frozen_string_literal: true

module Types
  # 走勢點（date × total_sales）。
  class AnalyticsSeriesPointType < BaseObject
    field :date, GraphQL::Types::ISO8601Date, null: false
    field :total_sales_cents, Integer, null: false
  end
end
