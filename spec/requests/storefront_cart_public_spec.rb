# frozen_string_literal: true

require "rails_helper"

# A1 收口（包 33 後半）：cart 端點的公開載體——host 解析、匿名可用。
# 既有 spec/requests/storefront_cart_spec.rb（staff 登入態）續留＝預覽面同端點的對照組。
#
# 🔴 假綠殺手：
#   R8 匿名（零 staff session）可加購（殺：staff 閘沒摘乾淨——公開店面 cart 全掛）
#   R9 平台 host 404（殺：無租戶時 Current.shop nil 直接 NoMethodError 或跨租戶）
RSpec.describe "Storefront cart（公開載體）", type: :request do
  let(:shop) { create(:shop, subdomain: "pub-cart") }
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 9_900,
                 product: create(:product, shop:, status: "active", title: "公開測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 50)
      v
    end
  end

  before do
    host! "pub-cart.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "R8 🔴 匿名買家（無任何登入）：建車、加購、取車全通；_cl_buyer host-only" do
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 2 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["items"].sole["quantity"]).to eq(2)

    set_cookie = response.headers["Set-Cookie"].to_s
    expect(set_cookie).to include("_cl_buyer=")
    expect(set_cookie.downcase).not_to include("domain=")

    get "/cart.js"
    expect(response.parsed_body["item_count"]).to eq(2)
  end

  it "R9 🔴 平台 host（無租戶）⇒ 404，不建任何車" do
    host! "lvh.me"
    expect { get "/cart.js" }.not_to change { ActsAsTenant.without_tenant { Cart.unscoped.count } }
    expect(response).to have_http_status(:not_found)
  end

  it "R10 A2：cart_item_limit 總件數上限——超限 422；關閉開關即放行" do
    shop.update!(cart_item_limit: 3, cart_item_limit_enabled: true)
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 4 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["message"]).to include("3")

    shop.update!(cart_item_limit_enabled: false)
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 4 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
  end
end
