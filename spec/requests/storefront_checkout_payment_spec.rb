# frozen_string_literal: true

require "rails_helper"

# 結帳線第三包：checkout 付款段端到端（86 §4 實測形的我方對位）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   P2 快照含 payment_instructions（殺：只存名稱——確認頁與 F5 訂單包拿不到指示文）
#   P4 🔴 server 重驗 active（殺：收客戶端殘留 radio——商家停用後照舊落庫）
#   P6 跨店 method id（殺：只查 id 不綁 shop——租戶隔離）
RSpec.describe "Storefront checkout payment（第三包）", type: :request do
  let!(:shop) { create(:shop, subdomain: "cp-shop") }
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 10_000,
                 product: create(:product, shop:, status: "active", title: "付款測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 9)
      v
    end
  end

  before do
    host! "cp-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def method!(type, **attrs)
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: type, **attrs)
    end
  end

  def checkout!
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
  end

  def reload!(checkout) = ActsAsTenant.with_tenant(shop) { checkout.reload }

  it "P1 零付款方式 ⇒ 無法接受付款（86 §4 官方字面對位）；無 radio、無完成鈕以外表單" do
    checkout = checkout!
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("This store can't accept payments right now.")
    expect(response.body).not_to include('name="payment_method_id"')
  end

  it "P2 單一方法：無 radio、Additional details 直出；POST ⇒ 快照五鍵齊（含 instructions）" do
    m = method!("bank_deposit", additional_details: "轉帳至 000-000", payment_instructions: "24 小時內回傳收據")
    checkout = checkout!
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("Bank Deposit").and include("轉帳至 000-000")
    expect(response.body).not_to include('type="radio" name="payment_method_id"')
    expect(response.body).to include("Complete order")

    post "/checkouts/#{checkout.token}/payment", params: { payment_method_id: m.id }
    expect(response).to have_http_status(:see_other)
    snap = reload!(checkout).payment_method_snapshot
    expect(snap).to include("id" => m.id, "method_type" => "bank_deposit",
                            "name" => "Bank Deposit",
                            "additional_details" => "轉帳至 000-000",
                            "payment_instructions" => "24 小時內回傳收據")
  end

  it "P3 多方法：radio 組＋手風琴（只有選中者展開 details——86 §4）；改選第二個入快照" do
    method!("bank_deposit", additional_details: "銀行詳情")
    cod = method!("cash_on_delivery", additional_details: "COD 詳情")
    checkout = checkout!
    get "/checkouts/#{checkout.token}"
    expect(response.body.scan('name="payment_method_id"').size).to eq(2)
    expect(response.body).to include("銀行詳情") # 預設選第一個 ⇒ 展開
    expect(response.body).not_to include("COD 詳情") # 未選中 ⇒ 收合

    post "/checkouts/#{checkout.token}/payment", params: { payment_method_id: cod.id }
    expect(reload!(checkout).payment_method_snapshot["method_type"]).to eq("cash_on_delivery")
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("COD 詳情")
    expect(response.body).not_to include("銀行詳情")
  end

  it "P4 🔴 提交已停用的方法 ⇒ 422＋重選提示，不落庫（server 重驗）" do
    m = method!("bank_deposit")
    checkout = checkout!
    ActsAsTenant.with_tenant(shop) { m.update!(active: false) }
    post "/checkouts/#{checkout.token}/payment", params: { payment_method_id: m.id }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("The payment methods have changed")
    expect(reload!(checkout).payment_method_snapshot).to eq({})
  end

  it "P5 帳單地址 radio 兩值（86 §4）：預設 same_as_shipping；改選 different 入庫" do
    m = method!("money_order")
    checkout = checkout!
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("Same as shipping address").and include("Use a different billing address")

    post "/checkouts/#{checkout.token}/payment",
         params: { payment_method_id: m.id, billing_mode: "different" }
    expect(reload!(checkout).billing_address["mode"]).to eq("different")
    # 值域外 ⇒ 落回預設，不落任意字串
    post "/checkouts/#{checkout.token}/payment",
         params: { payment_method_id: m.id, billing_mode: "hacked" }
    expect(reload!(checkout).billing_address["mode"]).to eq("same_as_shipping")
  end

  it "P6 🔴 別店的 method id ⇒ 422（租戶隔離：只認本店 active 集合）" do
    other = create(:shop, subdomain: "cp-other")
    foreign = ActsAsTenant.with_tenant(other) do
      ShopPaymentMethod.create!(shop_id: other.id, method_type: "bank_deposit")
    end
    method!("money_order")
    checkout = checkout!
    post "/checkouts/#{checkout.token}/payment", params: { payment_method_id: foreign.id }
    expect(response).to have_http_status(:unprocessable_content)
    expect(reload!(checkout).payment_method_snapshot).to eq({})
  end
end
