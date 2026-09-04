# frozen_string_literal: true

require "rails_helper"

# 包 36：301 消費引擎＋後台重導管理（62 §B.5；HDL-8/HDL-9）。
# producer 側（handle 變更掛鉤）＝spec/requests/url_redirects_spec.rb（第 6 包）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   E1 前綴保留 301（殺：命中後丟回無前綴——英文使用者被踢回預設語言，HDL-9）
#   E2 活頁面先贏（殺：重導查在渲染之前——manual 列遮蔽現任頁）
#   G2 帶前綴輸入拒絕（殺：DOC-5 裁定被繞過——每語言一列的維護災難回歸）
#   G4 系統列不可改、可刪（殺：改壞鏈坍縮不變量／舊 handle 釋放不了）
RSpec.describe "URL redirect 引擎與管理（包 36）", type: :request do
  let(:shop) { create(:shop, subdomain: "redir-engine") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "redir-engine.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  describe "前台 301 引擎" do
    before do
      ActsAsTenant.with_tenant(shop) do
        Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                      source: "first_party", license_attested: true)
        UrlRedirect.create!(from_path: "/products/old", to_path: "/products/rose", source: "manual")
      end
      allow(ThemeEngine::Sources).to receive(:resolve).and_return(
        ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
      )
    end

    it "E1 🔴 404 命中查表 ⇒ 301 且保留 locale 前綴與 query（HDL-9）" do
      get "/products/old?a=1"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers["Location"]).to end_with("/products/rose?a=1")
    end

    it "E2 🔴 活頁面先贏：from_path 指向現任商品 ⇒ 照常 200，不重導" do
      ActsAsTenant.with_tenant(shop) do
        v = create(:product_variant, shop:,
                   product: create(:product, shop:, status: "active", title: "現任商品", handle: "live"))
        v.inventory_item.inventory_levels.order(:id).first.update!(available: 1)
        UrlRedirect.create!(from_path: "/products/live", to_path: "/products/rose", source: "manual")
      end
      get "/products/live"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("現任商品")
    end

    it "E3 manual 鏈跟到底（A→B→C ⇒ 301 至 C）；410 列 ⇒ gone" do
      ActsAsTenant.with_tenant(shop) do
        UrlRedirect.create!(from_path: "/pages/a", to_path: "/pages/b", source: "manual")
        UrlRedirect.create!(from_path: "/pages/b", to_path: "/pages/c", source: "manual")
        UrlRedirect.create!(from_path: "/products/dead", to_path: "/gone", source: "manual", status_code: 410)
      end
      get "/pages/a"
      expect(response.headers["Location"]).to end_with("/pages/c")

      get "/products/dead"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "後台 GraphQL 管理" do
    P36_CREATE = <<~GRAPHQL
      mutation urlRedirectCreate($path: String!, $target: String!) {
        urlRedirectCreate(path: $path, target: $target) {
          urlRedirect { id path target source }
          userErrors { field message code }
        }
      }
    GRAPHQL

    P36_DELETE = <<~GRAPHQL
      mutation urlRedirectDelete($id: ID!) {
        urlRedirectDelete(id: $id) { deletedUrlRedirectId userErrors { field message code } }
      }
    GRAPHQL

    before { login! }

    it "G1 建立→列表→刪除全鏈；path/target 對齊本尊欄名；自動補開頭斜線" do
      post_graphql(P36_CREATE, variables: { path: "products/old-x", target: "/products/new-x" })
      payload = response.parsed_body.dig("data", "urlRedirectCreate")
      expect(payload["userErrors"]).to eq([])
      expect(payload.dig("urlRedirect", "path")).to eq("/products/old-x")
      expect(payload.dig("urlRedirect", "source")).to eq("manual")
      gid = payload.dig("urlRedirect", "id")

      post_graphql("query { urlRedirects(first: 50) { nodes { id path target source } } }")
      nodes = response.parsed_body.dig("data", "urlRedirects", "nodes")
      expect(nodes.map { |n| n["path"] }).to include("/products/old-x")

      post_graphql(P36_DELETE, variables: { id: gid })
      expect(response.parsed_body.dig("data", "urlRedirectDelete", "deletedUrlRedirectId")).to eq(gid)
      expect(ActsAsTenant.with_tenant(shop) { UrlRedirect.count }).to eq(0)
    end

    it "G2 🔴 帶 locale 前綴的輸入 ⇒ PREFIXED_PATH_FORBIDDEN（DOC-5 裁定；D80：前綴＝本店真實存在的 /zh-hant，像前綴的 /faq 不擋）；自我迴圈 ⇒ SELF_REDIRECT" do
      ActsAsTenant.with_tenant(shop) do
        ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
        Market.find_by!(is_primary: true).market_web_presences.sole
              .market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
      end
      post_graphql(P36_CREATE, variables: { path: "/zh-hant/products/x", target: "/products/y" })
      expect(response.parsed_body.dig("data", "urlRedirectCreate", "userErrors").sole["code"])
        .to eq("PREFIXED_PATH_FORBIDDEN")
      post_graphql(P36_CREATE, variables: { path: "/products/x", target: "/en/products/y" }) # 預設語言的舊前綴形也不是本店前綴
      expect(response.parsed_body.dig("data", "urlRedirectCreate", "userErrors")).to eq([])
      post_graphql(P36_CREATE, variables: { path: "/faq", target: "/pages/faq" }) # 兩三字母段不是前綴
      expect(response.parsed_body.dig("data", "urlRedirectCreate", "userErrors")).to eq([])

      post_graphql(P36_CREATE, variables: { path: "/products/x", target: "/products/x" })
      expect(response.parsed_body.dig("data", "urlRedirectCreate", "userErrors").sole["code"])
        .to eq("SELF_REDIRECT")
    end

    it "G3 同路徑重複建立 ⇒ TAKEN（舊 handle 永不回收）" do
      2.times { post_graphql(P36_CREATE, variables: { path: "/products/dup", target: "/products/t" }) }
      expect(response.parsed_body.dig("data", "urlRedirectCreate", "userErrors").sole["code"]).to eq("TAKEN")
    end

    it "G4 🔴 系統列不可改（NOT_EDITABLE）、可刪（HDL-8 釋放舊 handle）" do
      row = ActsAsTenant.with_tenant(shop) do
        UrlRedirect.create!(from_path: "/products/sys", to_path: "/products/now", source: "handle_change")
      end
      gid = "gid://chilllove/UrlRedirect/#{row.id}"

      post_graphql(<<~GRAPHQL, variables: { id: gid, path: "/products/sys", target: "/products/other" })
        mutation urlRedirectUpdate($id: ID!, $path: String!, $target: String!) {
          urlRedirectUpdate(id: $id, path: $path, target: $target) {
            urlRedirect { id }
            userErrors { field message code }
          }
        }
      GRAPHQL
      expect(response.parsed_body.dig("data", "urlRedirectUpdate", "userErrors").sole["code"]).to eq("NOT_EDITABLE")

      post_graphql(P36_DELETE, variables: { id: gid })
      expect(response.parsed_body.dig("data", "urlRedirectDelete", "userErrors")).to eq([])
      expect(ActsAsTenant.with_tenant(shop) { UrlRedirect.exists?(row.id) }).to be(false)
    end
  end

  def login!(email: staff.email)
    post login_path, params: { email:, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end
end
