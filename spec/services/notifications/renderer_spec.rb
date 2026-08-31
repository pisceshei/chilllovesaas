# frozen_string_literal: true

require "rails_helper"

# G6 步 6：通知渲染鏈（89 §5 官方變數契約）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   N1 攤平契約（殺：payload 包一層 order.*——官方逐字「The order object isn't
#      referenced by name in email templates」；巢狀後 {{ name }} 渲染成空）
#   N3 overlay 覆寫優先（殺：Renderer 恆讀平台預設——編輯器變裝飾）
#   N4 money filter 吃 cents（殺：payload 傳主單位）
RSpec.describe Notifications::Renderer do
  let(:shop) { create(:shop, subdomain: "notif") }

  let(:order) do
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#9001", order_number: 9001, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 16_800, shipping_cents: 2000,
        total_cents: 18_800, presentment_total_cents: 18_800, financial_status: "pending",
        fulfillment_status: "unfulfilled", status: "open", email: "buyer@example.com",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
      LineItem.create!(shop_id: shop.id, order_id: o.id, title: "護手霜",
                       quantity: 2, fulfillable_quantity: 2,
                       unit_price_cents: 8400, total_cents: 16_800, currency: "HKD")
      o
    end
  end

  def render(kind:, payload:)
    ActsAsTenant.with_tenant(shop) { described_class.render(shop:, kind:, payload:) }
  end

  it "🔴 N1 攤平契約：預設 subject 的 {{ name }} 取到訂單名（不是空字串）" do
    payload = Notifications::Payloads.order_confirmation(order:)
    result = render(kind: "order_confirmation", payload:)

    expect(result.subject).to eq("Order #9001 confirmed")
    expect(result.html).to include("護手霜")
  end

  it "🔴 N4 金額經 money filter＝cents 進、HK$ 兩位小數出" do
    payload = Notifications::Payloads.order_confirmation(order:)
    result = render(kind: "order_confirmation", payload:)

    expect(result.html).to include("HK$188.00") # total 18800 cents
    expect(result.html).to include("HK$168.00") # subtotal 16800 cents
  end

  it "🔴 N3 overlay 覆寫優先；刪列（revert）後回平台預設" do
    ActsAsTenant.with_tenant(shop) do
      NotificationTemplate.create!(shop_id: shop.id, channel: "email", key: "order_confirmation",
                                   name: "Order confirmation",
                                   subject: "自訂主旨 {{ name }}", body: "<p>自訂內文</p>")
    end
    payload = Notifications::Payloads.order_confirmation(order:)

    overridden = render(kind: "order_confirmation", payload:)
    expect(overridden.subject).to eq("自訂主旨 #9001")
    expect(overridden.html).to eq("<p>自訂內文</p>")

    ActsAsTenant.with_tenant(shop) { NotificationTemplate.delete_all }
    reverted = render(kind: "order_confirmation", payload:)
    expect(reverted.subject).to eq("Order #9001 confirmed")
  end

  it "shipping payload：fulfillment 帶前綴＋tracking 三件套（89 §5 官方形）" do
    fulfillment = ActsAsTenant.with_tenant(shop) do
      location = Location.create!(shop_id: shop.id, name: "主倉", address: {})
      fo = FulfillmentOrder.create!(shop_id: shop.id, order_id: order.id,
                                    status: "closed", location_id: location.id)
      Fulfillment.create!(shop_id: shop.id, fulfillment_order_id: fo.id,
                          status: "success", tracking_company: "SF Express",
                          tracking_numbers: [ { "number" => "SF123", "url" => "https://track.example/SF123" } ],
                          line_items_snapshot: [ { "line_item_id" => order.line_items.first.id, "quantity" => 2 } ])
    end
    payload = Notifications::Payloads.shipping_confirmation(order:, fulfillment:)

    expect(payload[:fulfillment][:tracking_company]).to eq("SF Express")
    expect(payload[:fulfillment][:tracking_numbers]).to eq([ "SF123" ])
    expect(payload[:fulfillment][:tracking_urls]).to eq([ "https://track.example/SF123" ])

    result = render(kind: "shipping_confirmation", payload:)
    expect(result.subject).to eq("A shipment from order #9001 is on the way")
    expect(result.html).to include("SF123").and include("SF Express")
  end

  it "abandoned payload：恢復連結＝裸 url（89 §5 官方形）＋快照行項" do
    checkout = ActsAsTenant.with_tenant(shop) do
      Checkout.create!(shop_id: shop.id, token: SecureRandom.hex(24), status: "open",
                       currency: "HKD", email: "steve@example.com",
                       line_items_snapshot: [ { "title" => "面膜", "quantity" => 3, "unit_price_cents" => 5000 } ])
    end
    payload = Notifications::Payloads.abandoned_checkout(checkout:, url: "https://x.example/r/abc")
    result = render(kind: "abandoned_checkout", payload:)

    expect(result.subject).to eq("Complete your Purchase")
    expect(result.html).to include('href="https://x.example/r/abc"')
    expect(result.html).to include("面膜").and include("HK$150.00")
  end
end
