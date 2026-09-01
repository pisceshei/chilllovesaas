# frozen_string_literal: true

require "rails_helper"

# G6 步 9b：結帳頁折扣輸入＋分享連結（17-F4.1 文案／官方連結形）。
#
# 🔴 假綠殺手：
#   S1 壞碼統一文案＋不落碼（殺：碼留在 checkout 上——下一步重算又報錯）
#   S3 分享連結 cookie 兌現（殺：cookie 沒清/沒套——重複套用或無效連結）
RSpec.describe "storefront discount UI", type: :request do
  let!(:shop) { create(:shop, subdomain: "dui") }
  let!(:pay_method) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: "bank_deposit")
    end
  end
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 10_000,
                 product: create(:product, shop:, status: "active", title: "UI 測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 20)
      v
    end
  end

  before do
    host! "dui.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Discount.create!(shop_id: shop.id, title: "九折", discount_class: "order",
                       method: "code", code: "SAVE10", value_type: "percentage",
                       percentage_basis_points: 1000, status: "active")
    end
  end

  def open_checkout!
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
  end

  it "S2 套碼 ⇒ 302 回結帳頁、金額更新、摘要出折扣列" do
    token = open_checkout!
    post "/checkouts/#{token}/discount", params: { code: "save10" }
    expect(response).to redirect_to("/checkouts/#{token}")

    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.discount_code).to eq("SAVE10")
    expect(checkout.discount_cents).to eq(1000)

    get "/checkouts/#{token}"
    expect(response.body).to include("Discount (SAVE10)")
    expect(response.body).to include("Discount code") # 輸入欄在頁上
  end

  it "🔴 S1 壞碼 ⇒ 統一文案＋碼不留在 checkout（金額還原）" do
    token = open_checkout!
    post "/checkouts/#{token}/discount", params: { code: "NOSUCH" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("折扣碼無效或不適用")

    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.discount_code).to be_nil, "壞碼殘留＝之後每次重算都報錯"
    expect(checkout.discount_cents).to eq(0)
  end

  it "空碼提交 ⇒ 移除既有碼" do
    token = open_checkout!
    post "/checkouts/#{token}/discount", params: { code: "SAVE10" }
    post "/checkouts/#{token}/discount", params: { code: "" }
    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.discount_code).to be_nil
    expect(checkout.discount_cents).to eq(0)
  end

  it "🔴 S3 /discount/:code ⇒ cookie → 建結帳自動帶碼＋cookie 清除" do
    get "/discount/save10"
    expect(response).to redirect_to("/")
    expect(cookies[:pending_discount_code]).to eq("SAVE10")

    token = open_checkout!
    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.discount_code).to eq("SAVE10")
    expect(checkout.discount_cents).to eq(1000)
    expect(cookies[:pending_discount_code]).to be_blank, "cookie 沒清＝下一張結帳又套"
  end
end
