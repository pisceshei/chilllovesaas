# frozen_string_literal: true

require "rails_helper"

# 步 16a：編輯器 bootstrap（templateJson DB 覆寫優先＋files.body＋design_mode 橋）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   E1 DB 覆寫優先（殺：只讀檔 ⇒ 編輯過的模板在編輯器裡看起來沒改）
#   E2 key 逃逸防線（殺：../ 讀出模板目錄外檔案）
#   E3 design_mode 才注入橋（殺：公開店面頁也帶編輯器 JS）
RSpec.describe "Theme editor bootstrap", type: :request do
  let(:shop) { create(:shop, subdomain: "editor-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  before do
    host! "editor-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    allow(ThemeEngine::Sources).to receive(:key_for).and_call_original
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
  end

  it "E1 🔴 templateJson：檔案版可讀；DB Template row 蓋過檔案版；files.body 出文字內容" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) {
        theme(id: $id) {
          templateJson(key: "index")
          layout: files(filenames: ["layout/*.liquid"]) { filename body }
        }
      }
    GQL
    data = response.parsed_body.dig("data", "theme")
    expect(data.dig("templateJson", "sections")).to have_key("hero")
    expect(data["layout"].first["body"]).to include("content_for_layout")

    ActsAsTenant.with_tenant(shop) do
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index",
                       template_type: "index",
                       content: { "sections" => { "custom" => { "type" => "hero", "settings" => {} } },
                                  "order" => [ "custom" ] })
    end
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { templateJson(key: "index") } }
    GQL
    overridden = response.parsed_body.dig("data", "theme", "templateJson")
    expect(overridden["order"]).to eq([ "custom" ]) # DB 覆寫贏
  end

  it "E4 sectionCatalog 只列帶 presets 的區段（24 §1.4）＋preset settings 帶出" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionCatalog } }
    GQL
    catalog = response.parsed_body.dig("data", "theme", "sectionCatalog")
    types = catalog.map { |entry| entry["type"] }
    expect(types).to include("promo")
    expect(types).not_to include("hero") # 無 presets ⇒ 不進 picker
    promo = catalog.find { |entry| entry["type"] == "promo" }
    expect(promo["name"]).to eq("促銷條")
    expect(promo.dig("preset", "settings", "text")).to eq("預設促銷文案")
  end

  it "E2 🔴 templateJson key 逃逸 ⇒ null" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { templateJson(key: "../config/settings_schema") } }
    GQL
    expect(response.parsed_body.dig("data", "theme", "templateJson")).to be_nil
  end

  it "E3 🔴 預覽 ?editor=1 才注入橋與 data-shopify-editor-section；公開店面頁不帶" do
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("cl:highlight")
    expect(response.body).to include("data-shopify-editor-section")

    get "/admin/store/preview/#{theme.id}"
    expect(response.body).not_to include("cl:highlight")
    expect(response.body).not_to include("data-shopify-editor-section")

    get "/en-hk/" # 公開店面（design_mode 恆 false）
    expect(response.body).not_to include("cl:highlight")
  end
end
