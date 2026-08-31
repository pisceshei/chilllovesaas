# frozen_string_literal: true

require "rails_helper"

# G6-8（步 5）：PSP 退款 job 的終態翻面與**失敗補償**。
#
# 🔴 假綠殺手：FAILED 不補償累計欄 ⇒ 錢沒退出去而 refunded_total_cents 虛高、
#   可退額度被永久佔用（M20 的守衛）。
RSpec.describe Refunds::ProcessPspRefundJob do
  let(:shop) { create(:shop, subdomain: "pspref") }

  let!(:provider) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentProvider.create!(shop_id: shop.id, provider: "airwallex", environment: "sandbox",
                                  status: "active", client_id: "cid", api_secret: "secret")
    end
  end

  let!(:order) do
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#9501", order_number: 9501, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 3000, total_cents: 3000,
        presentment_total_cents: 3000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 3000, refunded_total_cents: 1000
      )
      o.order_transactions.create!(shop_id: shop.id, kind: "sale", status: "success",
                                   gateway: "airwallex", amount_cents: 3000, currency: "HKD",
                                   provider_reference: "int_abc", idempotency_key: "sale-9501")
      o
    end
  end

  def build_refund(status: "pending")
    ActsAsTenant.with_tenant(shop) do
      transaction = order.order_transactions.create!(
        shop_id: shop.id, kind: "refund", status: "pending", gateway: "airwallex",
        amount_cents: 1000, currency: "HKD", idempotency_key: "refund-job-#{SecureRandom.hex(4)}"
      )
      Refund.create!(shop_id: shop.id, order_id: order.id, order_transaction_id: transaction.id,
                     status:, total_cents: 1000, shipping_cents: 0, currency: "HKD",
                     idempotency_key: "job-#{SecureRandom.hex(4)}", processed_at: Time.current)
    end
  end

  def stub_airwallex(response)
    fake = instance_double(Psp::Airwallex::Refunds)
    allow(Psp::Airwallex::Refunds).to receive(:new).and_return(fake)
    allow(fake).to receive(:create).and_return(response)
    fake
  end

  it "ACCEPTED ⇒ refund success、交易 success＋provider_reference" do
    refund = build_refund
    stub_airwallex({ "id" => "rfd_1", "status" => "ACCEPTED" })

    described_class.perform_now(shop.id, refund.id)

    ActsAsTenant.with_tenant(shop) do
      expect(refund.reload.status).to eq("success")
      transaction = OrderTransaction.find(refund.order_transaction_id)
      expect(transaction.status).to eq("success")
      expect(transaction.provider_reference).to eq("rfd_1")
      expect(order.reload.refunded_total_cents).to eq(1000) # 成功不補償
    end
  end

  it "🔴 FAILED ⇒ refund failure ＋ 累計欄補償回 0（額度釋放）" do
    refund = build_refund
    stub_airwallex({ "id" => "rfd_2", "status" => "FAILED" })

    described_class.perform_now(shop.id, refund.id)

    ActsAsTenant.with_tenant(shop) do
      expect(refund.reload.status).to eq("failure")
      expect(order.reload.refunded_total_cents).to eq(0)
    end
  end

  it "RECEIVED ⇒ 維持 pending（等後續對帳）、記 provider_reference" do
    refund = build_refund
    stub_airwallex({ "id" => "rfd_3", "status" => "RECEIVED" })

    described_class.perform_now(shop.id, refund.id)

    ActsAsTenant.with_tenant(shop) do
      expect(refund.reload.status).to eq("pending")
      expect(OrderTransaction.find(refund.order_transaction_id).provider_reference).to eq("rfd_3")
      expect(order.reload.refunded_total_cents).to eq(1000) # 額度仍佔用
    end
  end

  it "API 例外 ⇒ failure ＋ 補償 ＋ error_code 摘要（不無限重試打 PSP）" do
    refund = build_refund
    fake = instance_double(Psp::Airwallex::Refunds)
    allow(Psp::Airwallex::Refunds).to receive(:new).and_return(fake)
    allow(fake).to receive(:create).and_raise(StandardError, "connection reset")

    described_class.perform_now(shop.id, refund.id)

    ActsAsTenant.with_tenant(shop) do
      expect(refund.reload.status).to eq("failure")
      expect(order.reload.refunded_total_cents).to eq(0)
      expect(OrderTransaction.find(refund.order_transaction_id).status).to eq("error")
    end
  end

  it "冪等：已終結的 refund 直接 return（重複 enqueue 的收口）" do
    refund = build_refund(status: "success")
    expect(Psp::Airwallex::Refunds).not_to receive(:new)

    described_class.perform_now(shop.id, refund.id)
  end
end
