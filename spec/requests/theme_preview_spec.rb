# frozen_string_literal: true

require "rails_helper"

# 包 30（D77）：登入後主題預覽端點 ＋ themes query ＋ themePublish。
#
# 🔴 假綠殺手（鐵律 20.2⑤）:
#   P1 未登入 ⇒ redirect（拿掉 BaseController 繼承 ⇒ 轉紅）
#   P2 noindex 回應頭（拿掉 header ⇒ 轉紅——「登入牆後不需要」是錯的：
#      本尊預覽站同樣全域 noindex，82 §20.4 控制組）
#   P4 themePublish 對無檔案來源主題回 SOURCE_MISSING（拿掉 fail-closed ⇒ 轉紅）
RSpec.describe "主題預覽與發布", type: :request do
  let(:shop) { create(:shop, subdomain: "theme-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal Spec", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  before do
    host! "theme-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    # 測試主題來源：把 spec fixture 目錄掛到 Sources 的解析點（first_party 路徑）
    allow(ThemeEngine::Sources).to receive(:resolve).and_wrap_original do |original, t|
      if t.name == "Minimal Spec"
        ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
      else
        original.call(t)
      end
    end
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
  end

  it "P1 🔴 未登入 ⇒ 不渲染（redirect 到登入）" do
    get "/admin/store/preview/#{theme.id}"
    expect(response).to have_http_status(:redirect)
  end

  it "P2 🔴 登入後渲染首頁；X-Robots-Tag noindex；404 路徑回 404 status" do
    login!
    get "/admin/store/preview/#{theme.id}"
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    expect(response.body).to include("首頁英雄")

    get "/admin/store/preview/#{theme.id}/products/no-such"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("404 not found page")
  end

  it "P3 themes query 回主題清單（published 排前）＋ previewUrl" do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Draft Theme", role: "draft", source: "first_party")
    end
    login!
    post_graphql("query { themes { id name role previewUrl } }")
    themes = response.parsed_body.dig("data", "themes")
    expect(themes.length).to eq(2)
    expect(themes.first["role"]).to eq("published")
    expect(themes.first["previewUrl"]).to eq("/admin/store/preview/#{theme.id}")
  end

  it "P4 🔴 themePublish：無檔案來源 ⇒ SOURCE_MISSING（fail-closed）；有來源 ⇒ 轉場成功" do
    orphan = ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "No Source", role: "draft", source: "first_party")
    end
    login!
    mutation = <<~GRAPHQL
      mutation($id: ID!) { themePublish(id: $id) { theme { id role } userErrors { field message code } } }
    GRAPHQL

    post_graphql(mutation, variables: { id: "gid://chilllove/Theme/#{orphan.id}" })
    payload = response.parsed_body.dig("data", "themePublish")
    expect(payload.dig("userErrors", 0, "code")).to eq("SOURCE_MISSING")
    expect(orphan.reload.role).to eq("draft")

    post_graphql(mutation, variables: { id: "gid://chilllove/Theme/#{theme.id}" })
    payload = response.parsed_body.dig("data", "themePublish")
    expect(payload["userErrors"]).to eq([])
    expect(payload.dig("theme", "role")).to eq("published")
  end
end
