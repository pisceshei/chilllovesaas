# frozen_string_literal: true

require "rails_helper"

# G6 步 8a：到點抹除（官方射程：個資清除、訂單保留）。
#
# 🔴 假綠殺手：
#   R1 全 PII 清除＋地址刪除（殺：漏刪地址簿——PDPO/GDPR 射程殘留）
#   R2 訂單保留（殺：連訂單刪——官方 "order history remain"）
RSpec.describe Customers::RedactDueJob do
  let(:shop) { create(:shop, subdomain: "redact") }

  def build_customer(due:)
    ActsAsTenant.with_tenant(shop) do
      c = Customer.create!(shop_id: shop.id, email: "r#{SecureRandom.hex(3)}@example.com",
                           phone: "+8526#{rand(1_000_000..9_999_999)}",
                           first_name: "Re", last_name: "Dact", note: "秘密",
                           redaction_scheduled_at: due ? 1.hour.ago : 5.days.from_now)
      CustomerAddress.create!(shop_id: shop.id, customer_id: c.id, address1: "1 Way",
                              city: "HK", country_code: "HK")
      c
    end
  end

  it "🔴 R1 到點者：PII 清空＋地址刪除＋狀態 redacted＋事件 append；未到點者不動" do
    due = build_customer(due: true)
    pending_one = build_customer(due: false)

    described_class.perform_now

    ActsAsTenant.without_tenant do
      due.reload
      expect(due.first_name).to be_nil
      expect(due.email).to be_nil
      expect(due.phone).to be_nil
      expect(due.note).to be_nil
      expect(due.anonymized_at).to be_present
      expect(due.email_marketing_state).to eq("redacted")
      expect(CustomerAddress.where(customer_id: due.id).count).to eq(0)
      expect(CustomerMarketingConsent.where(customer_id: due.id, state: "redacted").count).to eq(2)

      pending_one.reload
      expect(pending_one.email).to be_present
      expect(pending_one.anonymized_at).to be_nil
    end
  end

  it "🔴 R2 訂單保留（官方：profile 與訂單史留存、個資遮蔽）" do
    due = build_customer(due: true)
    order = ActsAsTenant.with_tenant(shop) do
      Order.create!(
        shop_id: shop.id, customer_id: due.id, name: "#9801", order_number: 9801,
        currency: "HKD", presentment_currency: "HKD", subtotal_cents: 1000,
        total_cents: 1000, presentment_total_cents: 1000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
    end

    described_class.perform_now

    ActsAsTenant.without_tenant do
      expect(Order.find(order.id)).to be_present
      expect(Customer.find(due.id).anonymized_at).to be_present
    end
  end
end
