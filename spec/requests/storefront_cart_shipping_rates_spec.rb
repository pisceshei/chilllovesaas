# frozen_string_literal: true

require "rails_helper"

# 結帳線第三包：cart 運費試算三支（86 §6 官方現值形）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   R1 price＝十進位主單位**字串**（殺：cents 裸值直出 JSON——"2000" vs "20.00"，
#      鐵律 3 序列化層邊界；官方形逐字 {"name","price","source"}）
#   R2 白名單外國家空陣列（殺：跳過 market guard 直查 zone）
RSpec.describe "Storefront cart shipping rates（第三包）", type: :request do
  let!(:shop) { create(:shop, subdomain: "sr-shop") }
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      zone = ShippingProfile.general.sole.shipping_zones.sole
      zone.shipping_rates.sole.update!(name: "標準", price_cents: 2_000)
      zone.shipping_rates.create!(shop_id: shop.id, name: "快遞", price_cents: 5_050,
                                  rate_type: "flat", currency: "HKD")
      v = create(:product_variant, shop:, price_cents: 10_000,
                 product: create(:product, shop:, status: "active", title: "試算測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 9)
      v
    end
  end

  before do
    host! "sr-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
  end

  it "R1 GET /cart/shipping_rates.json：官方形 {name, price 十進位字串, source}；按價升冪" do
    get "/cart/shipping_rates.json", params: { shipping_address: { country: "HK" } }
    expect(response).to have_http_status(:ok)
    rates = response.parsed_body.fetch("shipping_rates")
    expect(rates).to eq([
      { "name" => "標準", "price" => "20.00", "source" => "chilllove" },
      { "name" => "快遞", "price" => "50.50", "source" => "chilllove" }
    ])
  end

  it "R2 不在 market 的國家 ⇒ 空陣列（zone 有無費率都一樣——交集白名單）；缺參數同" do
    get "/cart/shipping_rates.json", params: { shipping_address: { country: "US" } }
    expect(response.parsed_body).to eq("shipping_rates" => [])
    get "/cart/shipping_rates.json"
    expect(response.parsed_body).to eq("shipping_rates" => [])
  end

  it "R5 🔴 shipping_address[country] 收本尊 value 形（英文國名）與國碼同義（Ella 試算表單 POST 的是 all_country_option_tags 的 value）" do
    get "/cart/shipping_rates.json", params: { shipping_address: { country: "Hong Kong" } }
    expect(response.parsed_body.fetch("shipping_rates").map { |r| r["price"] }).to eq([ "20.00", "50.50" ])
    get "/cart/shipping_rates.json", params: { shipping_address: { country: "United States" } }
    expect(response.parsed_body).to eq("shipping_rates" => []) # 不在 market ⇒ 空（同 R2）
  end

  it "R3 prepare／async 兩支（官方三支現值——同步引擎恆已完成）＋帶前綴形" do
    post "/cart/prepare_shipping_rates.json", params: { shipping_address: { country: "HK" } }
    expect(response.parsed_body["shipping_rates"].map { |r| r["price"] }).to eq(%w[20.00 50.50])
    get "/cart/async_shipping_rates.json", params: { shipping_address: { country: "HK" } }
    expect(response.parsed_body["shipping_rates"].size).to eq(2)
    get "/cart/shipping_rates.json", params: { shipping_address: { country: "HK" } }
    expect(response.parsed_body["shipping_rates"].size).to eq(2)
  end

  it "R4 合併形單源（鐵律 7）：與結帳頁同一 RateResolver——重量制條件也生效" do
    ActsAsTenant.with_tenant(shop) do
      zone = ShippingProfile.general.sole.shipping_zones.sole
      zone.shipping_rates.delete_all
      zone.shipping_rates.create!(shop_id: shop.id, name: "重量制", price_cents: 3_000,
                                  rate_type: "weight", currency: "HKD",
                                  minimum_weight_grams: 5_000, maximum_weight_grams: 99_000)
    end
    # 車重 0g 不落級距 ⇒ 無可用費率 ⇒ 空（不是 0 元）
    get "/cart/shipping_rates.json", params: { shipping_address: { country: "HK" } }
    expect(response.parsed_body).to eq("shipping_rates" => [])
  end
end
