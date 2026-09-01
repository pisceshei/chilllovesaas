# frozen_string_literal: true

module Customers
  # nightly 統計對帳（G6 步 8b；74 §4 預告的對帳 job）。
  #
  # ①這是什麼：orders_count/total_spent_cents/last_order_at 是增量快取
  #   （G6-7 bump_stats! 唯一寫入端＋merge 重算）——本 job 每日全量重算，
  #   把任何漂移拉回真相（鐵律 7 的守門員，不是第二寫入端：發現漂移＝bug 訊號，
  #   log 一行）。
  # ②跨租戶平台 job（GROUP BY 一把算；小店量級 v1 夠用，分批隨量級再說）。
  class ReconcileStatsJob < ApplicationJob
    queue_as :background

    def perform
      ActsAsTenant.without_tenant do
        truth = Order.group(:customer_id).where.not(customer_id: nil)
                     .pluck(:customer_id, Arel.sql("COUNT(*)"),
                            Arel.sql("COALESCE(SUM(total_cents), 0)"),
                            Arel.sql("MAX(processed_at)"))
                     .to_h { |cid, count, sum, last| [ cid, [ count, sum, last ] ] }

        Customer.where(anonymized_at: nil).find_each do |customer|
          expected = truth[customer.id] || [ 0, 0, nil ]
          actual = [ customer.orders_count, customer.total_spent_cents, customer.last_order_at ]
          next if actual[0] == expected[0] && actual[1] == expected[1] &&
                  actual[2].to_i == expected[2].to_i

          Rails.logger.info(
            "customers.stats_drift customer_id=#{customer.id} " \
            "cached=#{actual.inspect} truth=#{expected.inspect}"
          )
          customer.update!(orders_count: expected[0], total_spent_cents: expected[1],
                           last_order_at: expected[2])
        end
      end
    end
  end
end
