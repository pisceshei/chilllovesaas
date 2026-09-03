# frozen_string_literal: true

require "rails_helper"

# E9（2026-09-03 使用者實測）：編輯器全頁草稿改用「伺服器端 token ＋ iframe 真實 URL 重載」。
# 根因：原本 `draft_page` 回整頁 HTML、前端以 `iframe.srcdoc` 換入——srcdoc 文件**繼承 admin 頁的嚴格 CSP**
# （style-src 'self'／script-src nonce），主題的 inline `<style data-shopify>`、`style=""`、inline script 全被擋
# ⇒ 任何設定一改（600ms 後全頁刷新）預覽退化成無樣式（使用者截圖：Announcement bar 調 spacing 後整頁錯亂）。
# 改法：POST draft_page 只存草稿（cache，租戶＋主題定界、短 TTL）回 `{token}`；GET show 帶 `?editor=1&draft=token`
# 以主題面 CSP（ThemeCsp）正常載入。
#
# 🔴 假綠殺手：DT2 缺 token／錯 token ⇒ 不得套用任何草稿；DT3 另一主題的 token 不得跨用（cache key 含 theme id）；
#   DT4 非編輯器（無 editor=1）不套草稿。
RSpec.describe "Theme editor draft token（E9）", type: :request do
  let(:shop) { create(:shop, subdomain: "theme-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal Spec", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let!(:other_theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal Spec 2", version: "1.0", role: "draft",
                    source: "first_party", license_attested: true)
    end
  end

  before do
    host! "theme-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    # E9：草稿 token 存 Rails.cache；test 環境是 null_store ⇒ 換記憶體 store（每例獨立）
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(ThemeEngine::Sources).to receive(:resolve).and_wrap_original do |original, t|
      if t.name.start_with?("Minimal Spec")
        ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
      else
        original.call(t)
      end
    end
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_draft(target_theme, heading:)
    post "/admin/store/preview/#{target_theme.id}/draft_page",
         params: { path: "/", sections: { "hero" => { "type" => "hero", "settings" => { "heading" => heading } } },
                   settings: {} }.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).fetch("token")
  end

  it "DT1 🔴 POST draft_page 回 token（不回 HTML）；GET show?editor=1&draft=token 套用草稿並帶主題面 CSP" do
    token = post_draft(theme, heading: "草稿標題 DT1")
    expect(token).to match(/\A[\w-]{16,64}\z/)
    get "/admin/store/preview/#{theme.id}?editor=1&draft=#{token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h1>草稿標題 DT1</h1>")
    csp = response.headers["Content-Security-Policy"].to_s
    expect(csp).to include("style-src 'self' 'unsafe-inline'")
    expect(csp).to include("script-src 'self' 'unsafe-inline'")
  end

  it "DT2 🔴 無 token／錯 token ⇒ 照已存內容渲染，不套草稿" do
    post_draft(theme, heading: "草稿標題 DT2")
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("草稿標題 DT2")
    get "/admin/store/preview/#{theme.id}?editor=1&draft=no-such-token-0000000"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("草稿標題 DT2")
  end

  it "DT3 🔴 token 與主題綁定：另一主題的 token 不得套用" do
    token = post_draft(other_theme, heading: "草稿標題 DT3")
    get "/admin/store/preview/#{theme.id}?editor=1&draft=#{token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("草稿標題 DT3")
  end

  it "DT4 🔴 草稿只在 editor=1 生效（一般登入後預覽帶 draft 不套）" do
    token = post_draft(theme, heading: "草稿標題 DT4")
    get "/admin/store/preview/#{theme.id}?draft=#{token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("草稿標題 DT4")
  end
end
