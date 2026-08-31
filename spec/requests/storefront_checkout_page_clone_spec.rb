# frozen_string_literal: true

require "rails_helper"

# G6-4 結帳頁 1:1 複刻（87 號 teardown 對位）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）——每格點名要殺的實作：
#   C1 骨架五段序（殺：漏渲染任一 H2 段／accordion 拔掉）
#   C2 US 條件欄位（殺：State/ZIP 無條件渲染或無條件不渲染）
#   C3 refresh 只落庫不前進（殺：refresh 也 307 走付款）
#   C4 billing different 展開＋落庫（殺：mode 落庫但欄位丟失）
#   C6 行銷勾選落庫（殺：checkbox 永遠 false）
# （psp 選中 ⇒ Pay now＋307 /pay 的格＝storefront_psp_payment_spec Q2，不重覆）
RSpec.describe "Storefront checkout page clone（G6-4）", type: :request do
  let!(:shop) { create(:shop, subdomain: "clone-shop") }
  let!(:pay_method) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: "bank_deposit",
                                additional_details: "轉帳到 000-000")
    end
  end
  let(:variant) { variant_for(title: "複刻測品", price: 18_800) }

  def variant_for(title:, price:)
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: price, requires_shipping: true,
                 product: create(:product, shop:, status: "active", title:))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 9)
      v
    end
  end

  before do
    host! "clone-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def checkout!
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
  end

  it "C1 骨架（87 §1/§2）：Contact→Delivery→Shipping method→Payment 段序、accordion、" \
     "側欄 Subtotal/Total＋幣別 code 前綴、浮動 label 欄位、未填地址占位句" do
    checkout = checkout!
    get "/checkouts/#{checkout.token}"
    body = response.body
    %w[Contact Delivery Payment].each { |h| expect(body).to include(">#{h}</h2>") }
    expect(body).to include(">Shipping method</h2>")
    expect(body.index(">Contact</h2>")).to be < body.index(">Delivery</h2>")
    expect(body.index(">Delivery</h2>")).to be < body.index(">Shipping method</h2>")
    expect(body.index(">Shipping method</h2>")).to be < body.index(">Payment</h2>")
    expect(body).to include("data-summary-accordion").and include("Order summary")
    expect(body).to include("Subtotal").and include("ck-total-ccy\">HKD</span>")
    expect(body).to include("Enter your shipping address to view available shipping methods.")
    expect(body).to include("ck-flabel").and include('placeholder="First name"')
    expect(body).to include("Email me with news and offers")
      .and include("Save this information for next time")
    expect(body).to include("$188.00") # 幣別符號形（87 §4）
  end

  it "C2 條件欄位（87 §3／V-87-1）：US ⇒ State select＋ZIP code；HK ⇒ 無 zone、Postal code" do
    checkout = checkout!
    ActsAsTenant.with_tenant(shop) do
      checkout.update!(shipping_address: { "country_code" => "US" })
    end
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include('name="zone"').and include('placeholder="ZIP code"')
    expect(response.body).to include(">Alabama</option>").and include(">Washington DC</option>")

    ActsAsTenant.with_tenant(shop) do
      checkout.update!(shipping_address: { "country_code" => "HK" }, shipping_lines: [], shipping_cents: 0)
    end
    get "/checkouts/#{checkout.token}"
    expect(response.body).not_to include('name="zone"')
    expect(response.body).to include('placeholder="Postal code"')
  end

  it "C3 refresh=1 只落庫不前進（JS 自動儲存路徑）：303 回結帳頁＋email/地址已存" do
    checkout = checkout!
    post "/checkouts/#{checkout.token}/submit",
         params: { refresh: "1", email: "auto@example.com", country_code: "HK", city: "Kowloon" }
    expect(response).to have_http_status(:see_other)
    expect(response.headers["Location"]).to end_with("/checkouts/#{checkout.token}")
    checkout = ActsAsTenant.with_tenant(shop) { checkout.reload }
    expect(checkout.email).to eq("auto@example.com")
    expect(checkout.shipping_address).to include("country_code" => "HK", "city" => "Kowloon")
  end

  it "C4 billing different：展開帳單表單（billing_ 前綴欄）＋落 billing_address json" do
    checkout = checkout!
    post "/checkouts/#{checkout.token}/submit",
         params: { refresh: "1", billing_mode: "different", billing_first_name: "帳",
                   billing_address1: "8 Bill St", billing_country_code: "HK" }
    billing = ActsAsTenant.with_tenant(shop) { checkout.reload }.billing_address
    expect(billing).to include("mode" => "different", "first_name" => "帳",
                               "address1" => "8 Bill St", "country_code" => "HK")

    get "/checkouts/#{checkout.token}"
    expect(response.body).to include('name="billing_first_name"').and include("ck-billing-form")
  end

  it "C6 行銷勾選：勾 ⇒ true；下一次未勾 ⇒ 回 false（checkbox 缺席語義）" do
    checkout = checkout!
    post "/checkouts/#{checkout.token}/submit",
         params: { refresh: "1", email: "a@b.c", buyer_accepts_marketing: "1" }
    expect(ActsAsTenant.with_tenant(shop) { checkout.reload }.buyer_accepts_marketing).to be(true)
    post "/checkouts/#{checkout.token}/submit", params: { refresh: "1", email: "a@b.c" }
    expect(ActsAsTenant.with_tenant(shop) { checkout.reload }.buyer_accepts_marketing).to be(false)
  end
end
