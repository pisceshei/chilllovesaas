# frozen_string_literal: true

require "rails_helper"

# 購物車 Ajax 端點（specs/15 F1；真店契約 83 §3.3／§4／§12.5）。
#
# 🔴 假綠殺手：
#   R3 售罄 422 JSON 三鍵（殺：錯誤走 HTML 或 userErrors 形）
#   R5 `_cl_buyer` cookie **無 Domain 屬性**（殺：設 .主網域＝跨店共享，F1 ⚠️坑）
#   R6 sections 參數回 map（殺：bundled section rendering 掉線）
#   R7 兩形載體（JSON items ∥ FormData 裸鍵）都收（Ella 用 FormData——83 §4.2）
RSpec.describe "Storefront cart Ajax", type: :request do
  let(:shop) { create(:shop, subdomain: "cart-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 14_800,
                                   product: create(:product, shop:, status: "active", title: "端點測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 9)
      v
    end
  end

  before do
    host! "cart-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  it "R1 GET /cart.js：首訪建車、發簽名 _cl_buyer；空車 14 鍵；/cart.json 同形（83 §3.3）" do
    get "/cart.js"
    expect(response).to have_http_status(:ok)
    j = response.parsed_body
    expect(j.keys.length).to eq(14)
    expect(j["item_count"]).to eq(0)
    expect(cookies["_cl_buyer"]).to be_present
    get "/cart.json"
    expect(response.parsed_body.keys).to eq(j.keys)
  end

  it "R2 POST /cart/add.js（JSON items 形）⇒ 回被加入行（非整車——官方形）；同 cookie 車累積" do
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 2 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    j = response.parsed_body
    expect(j.keys).to eq([ "items" ])
    expect(j["items"].sole["quantity"]).to eq(2)
    expect(j["items"].sole["price"]).to eq(14_800)
    get "/cart.js"
    expect(response.parsed_body["item_count"]).to eq(2)
  end

  it "R7 🔴 裸 /cart/add（FormData 鍵形，Ella 載體）⇒ 同語義" do
    post "/cart/add", params: { id: variant.id, quantity: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["items"].sole["variant_id"]).to eq(variant.id)
  end

  it "R3 🔴 售罄 ⇒ 422 JSON {status,message,description}（真店 §12.5 同構）" do
    ActsAsTenant.with_tenant(shop) do
      variant.inventory_item.inventory_levels.update_all(available: 0)
    end
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unprocessable_content)
    j = response.parsed_body
    expect(j.keys).to eq(%w[status message description])
    expect(j["status"]).to eq(422)
  end

  it "R4 change（quantity=0 移除）→ update（note）→ clear（保留 note）鏈；全車回應" do
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 3 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    key = response.parsed_body["items"].sole["key"]
    post "/cart/change.js", params: { id: key, quantity: 1 }
    expect(response.parsed_body["item_count"]).to eq(1)
    post "/cart/update.js", params: { note: "留言" }
    expect(response.parsed_body["note"]).to eq("留言")
    post "/cart/clear.js"
    j = response.parsed_body
    expect(j["item_count"]).to eq(0)
    expect(j["note"]).to eq("留言")
  end

  it "R5 🔴 _cl_buyer cookie host-only：Set-Cookie 不帶 Domain 屬性（跨店共享防線）" do
    get "/cart.js"
    set_cookie = response.headers["Set-Cookie"].to_s
    expect(set_cookie).to include("_cl_buyer=")
    expect(set_cookie.downcase).not_to include("domain=")
    expect(set_cookie.downcase).to include("httponly")
  end

  it "R6 🔴 bundled section rendering：add 帶 sections ⇒ 回應含 sections map（#203 fragment 機制）" do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ],
                                   sections: "grouped_hero_Ab12Cd", sections_url: "/" }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    j = response.parsed_body
    expect(j["sections"]).to be_a(Hash)
    expect(j["sections"]["grouped_hero_Ab12Cd"]).to include("群組英雄")
  end
end
