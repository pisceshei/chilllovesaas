# frozen_string_literal: true

require "rails_helper"

# G6 步 8b：顧客合併（官方 customerMerge 對位；規則＝Customers::Merge 檔頭）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   G1 保留規則（殺：恆留 one——官方唯一明文「雙無 email 留 two」反向格）
#   G2 blockers（殺：待抹除者照合併——官方 PENDING_DATA_REQUEST hard blocker）
#   G3 統計重算（殺：兩邊快取相加——快取漂移被合併固化，鐵律 7）
#   G4 附屬搬移完整性（殺：漏搬 consent 事件——稽核軌跡斷鏈）
RSpec.describe Customers::Merge do
  let(:shop) { create(:shop, subdomain: "merge") }

  def build_customer(email: nil, phone: nil, note: nil, tags: [], orders: 0, spent_each: 1000)
    ActsAsTenant.with_tenant(shop) do
      c = Customer.create!(shop_id: shop.id, email:, phone:, note:, tags:,
                           first_name: "M", last_name: "C")
      orders.times do |i|
        Order.create!(
          shop_id: shop.id, customer_id: c.id, name: "#M#{c.id}#{i}",
          order_number: (c.id * 100) + i, currency: "HKD", presentment_currency: "HKD",
          subtotal_cents: spent_each, total_cents: spent_each,
          presentment_total_cents: spent_each, financial_status: "paid",
          fulfillment_status: "unfulfilled", status: "open",
          seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
          shipping_address: {}, billing_address: {}, processed_at: Time.current
        )
      end
      c
    end
  end

  def merge!(one, two)
    ActsAsTenant.with_tenant(shop) { described_class.call(shop:, customer_one: one, customer_two: two) }
  end

  it "🔴 G1 保留規則：恰一方有 email ⇒ 留有 email 者；雙無 ⇒ 留 two（官方唯一明文）" do
    with_email = build_customer(email: "keep@example.com")
    without = build_customer

    result = merge!(without, with_email)
    expect(result.customer.id).to eq(with_email.id)
    ActsAsTenant.without_tenant { expect(Customer.find_by(id: without.id)).to be_nil }

    bare_one = build_customer
    bare_two = build_customer
    result2 = merge!(bare_one, bare_two)
    expect(result2.customer.id).to eq(bare_two.id),
      "雙無 email 應留 customer_two（官方逐字）"
  end

  it "🔴 G2 blockers：待抹除／已抹除任一方 ⇒ INVALID_STATE 不動資料" do
    pending_erasure = build_customer(email: "p@example.com")
    ActsAsTenant.without_tenant do
      Customer.where(id: pending_erasure.id).update_all(redaction_scheduled_at: 5.days.from_now)
    end
    other = build_customer(email: "o@example.com")

    result = merge!(pending_erasure.reload, other)
    expect(result.error&.last).to eq("INVALID_STATE")
    ActsAsTenant.without_tenant do
      expect(Customer.where(id: [ pending_erasure.id, other.id ]).count).to eq(2)
    end
  end

  it "🔴 G3 統計由訂單重算（不是快取相加）：先污染快取再合併 ⇒ 得真相" do
    one = build_customer(email: "a@example.com", orders: 2, spent_each: 1000)
    two = build_customer(email: nil, orders: 1, spent_each: 500)
    # 污染快取（模擬漂移）：兩邊都灌錯值——相加式實作會固化 999900
    ActsAsTenant.without_tenant do
      Customer.where(id: one.id).update_all(orders_count: 99, total_spent_cents: 900_000)
      Customer.where(id: two.id).update_all(orders_count: 88, total_spent_cents: 99_900)
    end

    result = merge!(one.reload, two.reload)
    kept = result.customer
    expect(kept.orders_count).to eq(3)
    expect(kept.total_spent_cents).to eq(2500)
  end

  it "🔴 G4 附屬搬移：orders/checkouts/地址（轉非預設）/consent 事件全跟人走；note 串接 tags 聯集" do
    kept = build_customer(email: "kept@example.com", note: "甲", tags: [ "vip" ])
    gone = build_customer(note: "乙", tags: [ "vip", "old" ], orders: 1)
    ActsAsTenant.with_tenant(shop) do
      CustomerAddress.create!(shop_id: shop.id, customer_id: gone.id, address1: "1 Way",
                              city: "HK", country_code: "HK", default_address: true)
      Checkout.create!(shop_id: shop.id, customer_id: gone.id, token: SecureRandom.hex(24),
                       status: "open", currency: "HKD", line_items_snapshot: [])
      Customers::UpdateMarketingConsent.call(shop:, customer: gone.reload, channel: "sms",
                                             state: "SUBSCRIBED", source: "admin")
    end
    # gone 無 email 但有 phone？——SMS 前置需 phone；補 phone
    ActsAsTenant.without_tenant { Customer.where(id: gone.id).update_all(phone: "+85261230000") }
    ActsAsTenant.with_tenant(shop) do
      Customers::UpdateMarketingConsent.call(shop:, customer: gone.reload, channel: "sms",
                                             state: "SUBSCRIBED", source: "admin")
    end

    result = merge!(kept, gone.reload)
    expect(result.error).to be_nil
    kept_row = result.customer

    ActsAsTenant.without_tenant do
      expect(Order.where(customer_id: kept_row.id).count).to eq(1)
      expect(Checkout.where(customer_id: kept_row.id).count).to eq(1)
      address = CustomerAddress.find_by(customer_id: kept_row.id)
      expect(address).to be_present
      expect(address.default_address).to be(false) # 被併方地址全轉非預設
      expect(CustomerMarketingConsent.where(customer_id: kept_row.id, channel: "sms")).to exist
    end
    expect(kept_row.note).to eq("甲\n乙")
    expect(kept_row.tags).to contain_exactly("vip", "old")
    expect(kept_row.phone).to eq("+85261230000") # 空缺聯絡欄補值
  end

  it "自我合併 ⇒ INVALID" do
    solo = build_customer(email: "solo@example.com")
    result = merge!(solo, solo)
    expect(result.error&.last).to eq("INVALID")
  end
end
