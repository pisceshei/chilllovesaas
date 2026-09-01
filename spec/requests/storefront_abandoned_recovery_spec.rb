# frozen_string_literal: true

require "rails_helper"

# G6 步 7：挽回連結端點（/checkouts/recover/:recovery_token）。
#
# 🔴 假綠殺手：
#   R1 路由序（殺：recover 放 :token 之後——"recover" 段被 :token 吃掉）
#   R2 已成單分流（殺：恆導回結帳頁——已下單顧客被帶回一個結不了的單）
RSpec.describe "storefront abandoned recovery", type: :request do
  let!(:shop) { create(:shop, subdomain: "recov") }

  let!(:checkout) do
    ActsAsTenant.with_tenant(shop) do
      Checkout.create!(shop_id: shop.id, token: SecureRandom.hex(24), status: "open",
                       currency: "HKD", email: "r@example.com",
                       line_items_snapshot: [ { "title" => "品", "quantity" => 1,
                                                "unit_price_cents" => 5000 } ])
    end
  end

  before do
    host! "recov.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "🔴 R1 有效 token ⇒ 302 回活結帳頁（快照還原）" do
    get "/checkouts/recover/#{checkout.recovery_token}"
    expect(response).to redirect_to("/checkouts/#{checkout.token}")
  end

  it "🔴 R2 已成單 ⇒ 302 到 thank-you 頁（不是回結帳頁）" do
    ActsAsTenant.with_tenant(shop) do
      Order.create!(
        shop_id: shop.id, checkout_id: checkout.id, name: "#9601", order_number: 9601,
        currency: "HKD", presentment_currency: "HKD", subtotal_cents: 5000,
        total_cents: 5000, presentment_total_cents: 5000, financial_status: "pending",
        fulfillment_status: "unfulfilled", status: "open", email: "r@example.com",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
    end

    get "/checkouts/recover/#{checkout.recovery_token}"
    expect(response).to redirect_to("/checkouts/#{checkout.token}/complete")
  end

  it "R3 不存在的 token ⇒ 404" do
    get "/checkouts/recover/#{SecureRandom.hex(24)}"
    expect(response).to have_http_status(:not_found)
  end
end
