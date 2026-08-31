# frozen_string_literal: true

require "rails_helper"

# G6-8（步 5）：入帳路徑必須遞增 captured_total_cents（16 F5.1 軟上限的分母）。
#
# 🔴 存在理由：步 5 整合時抓到的缺口——步 4 的 MarkAsPaid 沒更新累計欄，
#   退款上限恆 0、refundable 恆 false。本檔是那個缺口的守衛（兩條入帳路徑各一格）。
RSpec.describe "captured_total_cents 累計" do
  let(:shop) { create(:shop, subdomain: "capacc") }

  def build_order(number:)
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "##{number}", order_number: number, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 5000, total_cents: 5000,
        presentment_total_cents: 5000, financial_status: "pending",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
      o.order_transactions.create!(shop_id: shop.id, kind: "sale", status: "pending",
                                   gateway: "manual_bank_deposit", amount_cents: 5000,
                                   currency: "HKD", idempotency_key: "sale-#{number}")
      o
    end
  end

  it "🔴 MarkAsPaid ⇒ captured_total_cents == 交易額（退款上限的分母就位）" do
    order = build_order(number: 9401)
    ActsAsTenant.with_tenant(shop) { Orders::MarkAsPaid.call(shop:, order_id: order.id) }

    expect(order.reload.captured_total_cents).to eq(5000)
    expect(Refunds::Calculator.maximum_refundable(order)).to eq(5000)
  end

  it "🔴 MarkPaidFromPsp ⇒ captured_total_cents 同步（PSP 路徑同格）" do
    order = build_order(number: 9402)
    ActsAsTenant.with_tenant(shop) do
      Orders::MarkPaidFromPsp.call(order: Order.lock.find(order.id), provider: "airwallex",
                                   provider_reference: "int_test_#{SecureRandom.hex(4)}")
    end

    expect(order.reload.captured_total_cents).to eq(5000)
  end

  it "MarkAsPaid 重複呼叫（已 paid）不重複累計" do
    order = build_order(number: 9403)
    ActsAsTenant.with_tenant(shop) do
      Orders::MarkAsPaid.call(shop:, order_id: order.id)
      Orders::MarkAsPaid.call(shop:, order_id: order.id) # INVALID_STATE 分支
    end

    expect(order.reload.captured_total_cents).to eq(5000)
  end
end
