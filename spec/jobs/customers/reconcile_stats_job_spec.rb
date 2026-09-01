# frozen_string_literal: true

require "rails_helper"

# G6 步 8b：nightly 統計對帳（鐵律 7 守門員）。
#
# 🔴 假綠殺手：R1 漂移拉回真相（殺：job 只 log 不修／恆跳過）。
RSpec.describe Customers::ReconcileStatsJob do
  let(:shop) { create(:shop, subdomain: "reconc") }

  it "🔴 R1 漂移的快取被拉回訂單真相；無漂移者不動 updated_at" do
    drifted, clean = ActsAsTenant.with_tenant(shop) do
      d = Customer.create!(shop_id: shop.id, email: "d@example.com",
                           orders_count: 99, total_spent_cents: 999_999)
      c = Customer.create!(shop_id: shop.id, email: "c@example.com",
                           orders_count: 1, total_spent_cents: 2000,
                           last_order_at: Time.current.change(usec: 0))
      [ d, c ].each_with_index do |customer, index|
        next if index == 0 && false

        Order.create!(
          shop_id: shop.id, customer_id: customer.id, name: "#R#{customer.id}",
          order_number: customer.id + 5000, currency: "HKD", presentment_currency: "HKD",
          subtotal_cents: 2000, total_cents: 2000, presentment_total_cents: 2000,
          financial_status: "paid", fulfillment_status: "unfulfilled", status: "open",
          seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
          shipping_address: {}, billing_address: {},
          processed_at: customer.last_order_at || Time.current.change(usec: 0)
        )
      end
      [ d, c ]
    end

    described_class.perform_now

    ActsAsTenant.without_tenant do
      drifted.reload
      expect(drifted.orders_count).to eq(1)
      expect(drifted.total_spent_cents).to eq(2000)
      expect(clean.reload.orders_count).to eq(1) # 無漂移者維持
    end
  end
end
