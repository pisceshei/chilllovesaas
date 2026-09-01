# frozen_string_literal: true

require "rails_helper"

# G6 步 8a：行銷同意狀態機（官方取證 2026-09-01；事件表＝事實來源）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   C1 可寫三值閘（殺：收下 NOT_SUBSCRIBED——官方明文 "This value cannot be set
#      via the mutation"）
#   C2 通道前置（殺：無 email 寫 email 同意——官方 "must have an email address"）
#   C3 latest-wins（殺：舊時間戳覆蓋新快取——官方 "reflects the consent record
#      with the most recent consent_updated_at date"）
#   C5 append-only（殺：事件列可被 UPDATE——稽核軌跡可竄改）
#   C6 checkout 生產端走事件鏈（殺：退回裸 boolean 寫——事件表漏首源）
RSpec.describe Customers::UpdateMarketingConsent do
  let(:shop) { create(:shop, subdomain: "consent") }

  let(:customer) do
    ActsAsTenant.with_tenant(shop) do
      Customer.create!(shop_id: shop.id, email: "c@example.com", phone: "+85261234567",
                       first_name: "Con", last_name: "Sent")
    end
  end

  def call!(channel: "email", state: "SUBSCRIBED", **kw)
    ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, customer:, channel:, state:, **kw)
    end
  end

  it "🔴 C1 唯讀值（NOT_SUBSCRIBED/REDACTED/INVALID）⇒ INCLUSION 且零事件" do
    %w[NOT_SUBSCRIBED REDACTED INVALID].each do |state|
      result = call!(state:)
      expect(result.error&.last).to eq("INCLUSION"), "#{state} 應被拒（官方唯讀值）"
    end
    count = ActsAsTenant.without_tenant { CustomerMarketingConsent.count }
    expect(count).to eq(0)
  end

  it "🔴 C2 通道前置：無 email 的顧客寫 email 同意 ⇒ INVALID_STATE；無電話寫 SMS 同" do
    bare = ActsAsTenant.with_tenant(shop) do
      Customer.create!(shop_id: shop.id, first_name: "No", last_name: "Contact")
    end
    r1 = ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, customer: bare, channel: "email", state: "SUBSCRIBED")
    end
    r2 = ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, customer: bare, channel: "sms", state: "SUBSCRIBED")
    end
    expect(r1.error&.last).to eq("INVALID_STATE")
    expect(r2.error&.last).to eq("INVALID_STATE")
  end

  it "C4 訂閱 ⇒ 事件 append＋快取投影（state/legacy boolean/source/時間）" do
    result = call!(opt_in_level: "SINGLE_OPT_IN", source: "admin")
    expect(result.error).to be_nil

    customer.reload
    expect(customer.email_marketing_state).to eq("subscribed")
    expect(customer.email_marketing_consent).to be(true)
    expect(customer.email_marketing_consent_source).to eq("admin")
    event = ActsAsTenant.without_tenant { CustomerMarketingConsent.last }
    expect(event.state).to eq("subscribed")
    expect(event.opt_in_level).to eq("single_opt_in")
  end

  it "🔴 C3 latest-wins：較舊 consent_updated_at 照 append 但不降快取" do
    call!(state: "SUBSCRIBED", consent_updated_at: Time.current)
    stale = call!(state: "UNSUBSCRIBED", consent_updated_at: 2.days.ago)
    expect(stale.error).to be_nil

    customer.reload
    expect(customer.email_marketing_state).to eq("subscribed"),
      "舊事件覆蓋新快取＝官方 latest-wins 破約"
    count = ActsAsTenant.without_tenant { CustomerMarketingConsent.where(channel: "email").count }
    expect(count).to eq(2) # 稽核軌跡兩列俱在
  end

  it "🔴 C5 append-only：既有事件列 UPDATE ⇒ ReadOnlyRecord" do
    call!
    event = ActsAsTenant.without_tenant { CustomerMarketingConsent.last }
    expect { event.update!(state: "unsubscribed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "退訂 ⇒ 狀態 unsubscribed、boolean false（G6-7 消費者不斷鏈）" do
    call!(state: "SUBSCRIBED")
    call!(state: "UNSUBSCRIBED")
    customer.reload
    expect(customer.email_marketing_state).to eq("unsubscribed")
    expect(customer.email_marketing_consent).to be(false)
  end

  it "🔴 C6 checkout 生產端走事件鏈（UpsertFromCheckout 勾行銷框 ⇒ source=checkout 事件）" do
    checkout = ActsAsTenant.with_tenant(shop) do
      Checkout.create!(shop_id: shop.id, token: SecureRandom.hex(24), status: "open",
                       currency: "HKD", email: "buyer8@example.com",
                       buyer_accepts_marketing: true,
                       shipping_address: { "first_name" => "Buy", "last_name" => "Er" },
                       line_items_snapshot: [])
    end
    order = ActsAsTenant.with_tenant(shop) do
      Order.create!(
        shop_id: shop.id, name: "#9851", order_number: 9851, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 1000, total_cents: 1000,
        presentment_total_cents: 1000, financial_status: "pending",
        fulfillment_status: "unfulfilled", status: "open", email: checkout.email,
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
    end
    upserted = ActsAsTenant.with_tenant(shop) do
      Customers::UpsertFromCheckout.call(checkout:, order:)
    end

    event = ActsAsTenant.without_tenant do
      CustomerMarketingConsent.find_by(customer_id: upserted.id, channel: "email")
    end
    expect(event).to be_present, "checkout 同意沒進事件表＝首源漏記"
    expect(event.source).to eq("checkout")
    expect(upserted.reload.email_marketing_state).to eq("subscribed")
  end
end
