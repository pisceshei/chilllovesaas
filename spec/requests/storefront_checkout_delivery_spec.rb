# frozen_string_literal: true

require "rails_helper"

# 結帳線第二包：買家前台運送段端到端（85 §5 實測形的我方對位）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   D2 選國即預選最便宜並入 Total（殺：運費算了不進總額——鐵律 7 同源）
#   D3 split per-shipment 獨立選擇（殺：多檔仍併成一列）
#   D5 🔴 server 重驗（F3-3；殺：收客戶端提交價——改價後照舊價收款）
#   D6 國家白名單＝market ∩ 有費率 zone（殺：只看 market 或只看 zone 單邊）
RSpec.describe "Storefront checkout delivery（第二包）", type: :request do
  let!(:shop) { create(:shop, subdomain: "cd-shop") }
  let!(:custom_profile) do
    ActsAsTenant.with_tenant(shop) { ShippingProfile.create!(shop_id: shop.id, name: "Probe") }
  end
  let!(:general_rate) do
    ActsAsTenant.with_tenant(shop) do
      zone = ShippingProfile.general.sole.shipping_zones.sole
      zone.shipping_rates.sole.update!(name: "標準", price_cents: 2_000)
      zone.shipping_rates.sole
    end
  end
  let(:variant) { variant_for(title: "一般品", price: 14_800) }
  let(:probe_variant) { variant_for(title: "探針品", price: 9_900, profile: custom_profile) }

  def variant_for(title:, price:, profile: nil, ship: true)
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: price, requires_shipping: ship,
                 product: create(:product, shop:, status: "active", title:, shipping_profile: profile))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 9)
      v
    end
  end

  before do
    host! "cd-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def checkout!(variants)
    items = variants.map { |v| { id: v.id, quantity: 1 } }
    post "/cart/add.js", params: { items: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
  end

  def reload!(checkout)
    ActsAsTenant.with_tenant(shop) { checkout.reload }
  end

  it "D1 未選國：頁面出國家下拉（值域＝sellable_countries）＋提示，無費率 radio" do
    checkout = checkout!([ variant ])
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include('<select name="country_code">')
    expect(response.body).to include('<option value="HK">')
    expect(response.body).to include("請先選擇配送地區")
    expect(response.body).not_to include('type="radio"')
  end

  it "D2 選國 ⇒ 預設選最便宜、入庫 shipping_lines、Total＝Calculator 同源（85 §5.2 行為）" do
    checkout = checkout!([ variant ])
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "HK" }
    expect(response).to have_http_status(:see_other)

    checkout = reload!(checkout)
    expect(checkout.shipping_address["country_code"]).to eq("HK")
    expect(checkout.shipping_cents).to eq(2_000)
    expect(checkout.shipping_lines.sole).to include("name" => "標準", "price_cents" => 2_000,
                                                    "rate_id" => general_rate.id)
    expect(checkout.total_cents).to eq(14_800 + 2_000)

    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("checked")
    expect(response.body).to include("168.00") # 鐵律 7：頁面總額與落庫同一 Result
  end

  it "D3 split（雙檔、開關預設 On）：per-shipment radio、各自獨立選、運費＝兩件相加" do
    ActsAsTenant.with_tenant(shop) do
      zone = ShippingZone.create!(shop_id: shop.id, shipping_profile: custom_profile,
                                  name: "Probe HK", country_codes: [ "HK" ])
      ShippingRate.create!(shop_id: shop.id, shipping_zone: zone, name: "標準", price_cents: 500,
                           rate_type: "flat", currency: "HKD")
      ShippingRate.create!(shop_id: shop.id, shipping_zone: zone, name: "快遞", price_cents: 5_000,
                           rate_type: "flat", currency: "HKD")
    end
    checkout = checkout!([ variant, probe_variant ])
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "HK" }
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("將分 2 件出貨")
    expect(response.body).to include('data-shipment="0"').and include('data-shipment="1"')

    # 第二件改選快遞（第一件維持 標準）⇒ 2000 + 5000
    post "/checkouts/#{checkout.token}/delivery",
         params: { country_code: "HK", selections: { "0" => "標準|2000", "1" => "快遞|5000" } }
    expect(response).to have_http_status(:see_other)
    checkout = reload!(checkout)
    expect(checkout.shipping_cents).to eq(7_000)
    expect(checkout.shipping_lines.map { |l| l["name"] }).to eq(%w[標準 快遞])
    expect(checkout.total_cents).to eq(14_800 + 9_900 + 7_000)
  end

  it "D4 split 開關 Off ⇒ 46c 合併單列（同名相加 2000+500=2500）" do
    ActsAsTenant.with_tenant(shop) do
      shop.update!(split_shipping_enabled: false)
      zone = ShippingZone.create!(shop_id: shop.id, shipping_profile: custom_profile,
                                  name: "Probe HK", country_codes: [ "HK" ])
      ShippingRate.create!(shop_id: shop.id, shipping_zone: zone, name: "標準", price_cents: 500,
                           rate_type: "flat", currency: "HKD")
    end
    checkout = checkout!([ variant, probe_variant ])
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "HK" }
    checkout = reload!(checkout)
    expect(checkout.shipping_cents).to eq(2_500)
    expect(checkout.shipping_lines.sole["name"]).to eq("標準")

    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("data-shipping-options")
    expect(response.body).not_to include("data-shipment=")
  end

  it "D5 🔴 server 重驗（F3-3）：提交過期價 ⇒ 422＋重選警示＋落回當前最便宜，絕不收舊價" do
    checkout = checkout!([ variant ])
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "HK" }
    ActsAsTenant.with_tenant(shop) { general_rate.update!(price_cents: 3_000) } # 商家改價

    post "/checkouts/#{checkout.token}/delivery",
         params: { country_code: "HK", option: "標準|2000" } # 客戶端拿著舊價提交
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("運送選項已變更")
    checkout = reload!(checkout)
    expect(checkout.shipping_cents).to eq(3_000) # 🔴 落當前價，不是提交價
    expect(checkout.total_cents).to eq(14_800 + 3_000)
  end

  it "D6 白名單單邊不放行：不在 market 的國家 422（zone 有無費率都一樣）" do
    checkout = checkout!([ variant ])
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "US" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("此地區目前無法配送")
    expect(reload!(checkout).shipping_cents).to eq(0)
  end

  it "D7 某件商品無費率可用 ⇒ 422 整車擋（Rates(p)=∅，不當 0 元）" do
    checkout = checkout!([ variant, probe_variant ]) # custom_profile 無 zone
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "HK" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("部分商品目前無法配送")
    expect(reload!(checkout).shipping_lines).to eq([])
  end

  it "D9 completed 的結帳不可再讀寫（find 只認 open——三值 enum 的消費面）" do
    checkout = checkout!([ variant ])
    ActsAsTenant.with_tenant(shop) { checkout.update!(status: "completed") }
    get "/checkouts/#{checkout.token}"
    expect(response).to have_http_status(:not_found)
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "HK" }
    expect(response).to have_http_status(:not_found)
  end

  it "D8 全數位車（requires_shipping=false）：無運送段、運費 0、可設國家" do
    digital = variant_for(title: "數位品", price: 8_000, ship: false)
    checkout = checkout!([ digital ])
    post "/checkouts/#{checkout.token}/delivery", params: { country_code: "HK" }
    expect(response).to have_http_status(:see_other)
    checkout = reload!(checkout)
    expect(checkout.shipping_cents).to eq(0)
    expect(checkout.total_cents).to eq(8_000)
    get "/checkouts/#{checkout.token}"
    expect(response.body).not_to include('type="radio"')
  end
end
