# frozen_string_literal: true

require "rails_helper"

# G6-7 訂單成立 → 顧客建檔管線（16 §F6.1；Customers::UpsertFromCheckout）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）——每格點名要殺的實作：
#   K1 email upsert 去重（殺：恆建新列／大小寫不同建兩檔）
#   K2 統計增量（殺：orders_count 恆 0／total_spent 不累計／last_order_at 不推進）
#   K3 consent 只升不降（殺：未勾把已訂閱者退訂；勾選不記 source）
#   K4 關聯回寫（殺：order.customer_id／checkout.customer_id 恆 NULL）
#   K5 無 email 不建檔（殺：建出 email NULL 的殭屍檔）
#   K6 地址簿只在簿空時補（殺：每單覆寫地址簿）
RSpec.describe "Storefront order → customer pipeline（G6-7）", type: :request do
  let!(:shop) { create(:shop, subdomain: "cust-shop") }
  let!(:pay_method) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: "bank_deposit")
    end
  end
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 10_000, requires_shipping: true,
                 product: create(:product, shop:, status: "active", title: "顧客測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 50)
      v
    end
  end

  before do
    host! "cust-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def place_order!(email:, marketing: false, first_name: "測", city: "Central")
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    params = { email:, country_code: "HK", first_name:, last_name: "買",
               address1: "1 Queen's Road", city:, phone: "+85291234567",
               payment_method_id: pay_method.id, billing_mode: "same_as_shipping" }
    params[:buyer_accepts_marketing] = "1" if marketing
    post "/checkouts/#{token}/submit", params: params
    expect(response).to have_http_status(:temporary_redirect)
    post "/checkouts/#{token}/complete"
    expect(response).to have_http_status(:see_other)
    ActsAsTenant.with_tenant(shop) { Order.order(:id).last }
  end

  def customers = ActsAsTenant.with_tenant(shop) { Customer.where(shop_id: shop.id).to_a }

  it "K1+K4 首單建檔（email 正規化）＋order/checkout 掛 customer_id；" \
     "大小寫不同的第二單命中同一檔" do
    order1 = place_order!(email: "Buyer@Example.com ")
    expect(customers.size).to eq(1)
    customer = customers.sole
    expect(customer.email).to eq("buyer@example.com") # 正規化（16 §F6 ⚠️坑）
    expect(customer.first_name).to eq("測")
    expect(customer.phone).to eq("+85291234567")
    expect(order1.customer_id).to eq(customer.id)
    expect(ActsAsTenant.with_tenant(shop) { Checkout.find(order1.checkout_id) }.customer_id)
      .to eq(customer.id)

    place_order!(email: "BUYER@example.COM")
    expect(customers.size).to eq(1) # 不重複建檔
  end

  it "K2 統計三欄增量（鐵律 7 同源）：兩單後 orders_count=2、total_spent 累計、last_order_at 推進" do
    place_order!(email: "stats@example.com")
    t1 = customers.sole.last_order_at
    expect(customers.sole.orders_count).to eq(1)
    expect(customers.sole.total_spent_cents).to eq(10_000)

    place_order!(email: "stats@example.com")
    customer = customers.sole
    expect(customer.orders_count).to eq(2)
    expect(customer.total_spent_cents).to eq(20_000)
    expect(customer.last_order_at).to be >= t1
  end

  it "K3 consent 只升不降：勾選 ⇒ 訂閱＋source=checkout＋時間戳；後續未勾不退訂、不改時間戳" do
    place_order!(email: "consent@example.com", marketing: true)
    customer = customers.sole
    expect(customer.email_marketing_consent).to be(true)
    expect(customer.email_marketing_consent_source).to eq("checkout")
    stamp = customer.email_marketing_consent_updated_at
    expect(stamp).to be_present

    place_order!(email: "consent@example.com", marketing: false)
    customer = customers.sole
    expect(customer.email_marketing_consent).to be(true) # 未勾≠退訂
    expect(customer.email_marketing_consent_updated_at).to eq(stamp) # 最早同意時點保留

    # 訂單面快照照實（第二單未勾 ⇒ false）
    orders = ActsAsTenant.with_tenant(shop) { Order.order(:id).to_a }
    expect(orders.map(&:buyer_accepts_marketing)).to eq([ true, false ])
  end

  it "K6 地址簿：首單建預設地址（zone→province 對映）；第二單不同地址不覆寫" do
    place_order!(email: "addr@example.com", city: "Central")
    customer = customers.sole
    address = ActsAsTenant.with_tenant(shop) { customer.customer_addresses.sole }
    expect(address.city).to eq("Central")
    expect(address.default_address).to be(true)
    expect(address.country_code).to eq("HK")

    place_order!(email: "addr@example.com", city: "Kowloon")
    expect(ActsAsTenant.with_tenant(shop) { customer.customer_addresses.count }).to eq(1)
    expect(ActsAsTenant.with_tenant(shop) { customer.customer_addresses.sole }.city).to eq("Central")
  end

  it "K5 數位車無運送地址也可建檔；email 空白（快照重放形）不建檔" do
    # email 為鍵：正常單一定有 email（submit 必填閘），這格直接驗 service 邊界
    checkout = ActsAsTenant.with_tenant(shop) do
      Checkout.create!(shop_id: shop.id, token: SecureRandom.hex(24), email: "   ",
                       line_items_snapshot: [], status: "open")
    end
    order = ActsAsTenant.with_tenant(shop) do
      Order.create!(shop_id: shop.id, checkout_id: checkout.id, name: "#9001", order_number: 9001,
                    shipping_address: {}, billing_address: {}, processed_at: Time.current,
                    financial_status: "pending", fulfillment_status: "unfulfilled", status: "open",
                    seller_jurisdiction: "hk", buyer_jurisdiction: "hk")
    end
    result = ActsAsTenant.with_tenant(shop) { Customers::UpsertFromCheckout.call(checkout:, order:) }
    expect(result).to be_nil
    expect(customers).to be_empty
    expect(order.reload.customer_id).to be_nil
  end
end
