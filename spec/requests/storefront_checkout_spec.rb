# frozen_string_literal: true

require "rails_helper"

# 結帳線第一包：cart→checkout 快照＋token URL（15 F1 #3／F3／F5）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   C2 進入結帳＝重新快照**即時價**（殺：抄 cart 的 unit_price_cents——那是合併鍵快照）
#   C3 🔴 不扣庫存（殺：建結帳就扣——棄單變成永久佔庫存）
#   C5 token 查無 404（殺：枚舉）；跨店 token 不可讀（租戶隔離）
RSpec.describe "Storefront checkout（第一包）", type: :request do
  let!(:shop) { create(:shop, subdomain: "co-shop") }
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 14_800,
                 product: create(:product, shop:, status: "active", title: "結帳測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 9)
      v
    end
  end

  before do
    host! "co-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def add_to_cart!(quantity: 2)
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
  end

  it "C1 POST /checkout：建快照 ⇒ 303 /checkouts/<token>；GET 顯示總額；金額＝Calculator 同源" do
    add_to_cart!(quantity: 2)
    post "/checkout"
    expect(response).to have_http_status(:see_other)
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    expect(token).to be_present

    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.subtotal_cents).to eq(29_600)
    expect(checkout.total_cents).to eq(29_600)
    expect(checkout.status).to eq("active")
    expect(checkout.line_items_snapshot.sole["quantity"]).to eq(2)

    get "/checkouts/#{token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("296.00") # Money::Display 同一 cents 來源
    expect(response.headers["X-Robots-Tag"]).to include("noindex")
  end

  it "C2 🔴 進入結帳＝重新快照即時價（cart 行快照價是合併鍵，不是結帳價——F1 #3）" do
    add_to_cart!(quantity: 1)
    ActsAsTenant.with_tenant(shop) { variant.update!(price_cents: 20_000) } # 加車後漲價
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h+)}, 1]
    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.line_items_snapshot.sole["unit_price_cents"]).to eq(20_000)
    expect(checkout.total_cents).to eq(20_000)
    # 快照定格：此後再改價不影響本結帳（F2 坑 3）
    ActsAsTenant.with_tenant(shop) { variant.update!(price_cents: 30_000) }
    expect(checkout.reload.total_cents).to eq(20_000)
  end

  it "C3 🔴 建立結帳不扣庫存（訂單成立才扣——15 F5）" do
    add_to_cart!(quantity: 3)
    expect { post "/checkout" }.not_to(change do
      ActsAsTenant.with_tenant(shop) { variant.inventory_item.inventory_levels.sum(:available) }
    end)
  end

  it "C4 空車／無 cookie ⇒ 303 回 /cart，不建任何 checkout" do
    expect { post "/checkout" }.not_to change { ActsAsTenant.without_tenant { Checkout.unscoped.count } }
    expect(response).to redirect_to("/cart")
  end

  it "C5 🔴 token 查無 ⇒ 404；別店的 token 也 404（租戶隔離）" do
    get "/checkouts/#{SecureRandom.hex(24)}"
    expect(response).to have_http_status(:not_found)

    other_shop = create(:shop, subdomain: "co-other")
    other = ActsAsTenant.with_tenant(other_shop) do
      Checkout.create!(shop_id: other_shop.id, currency: "HKD", line_items_snapshot: [])
    end
    get "/checkouts/#{other.token}" # 在 co-shop host 上讀 co-other 的 token
    expect(response).to have_http_status(:not_found)
  end
end
