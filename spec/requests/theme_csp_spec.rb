# frozen_string_literal: true

require "rails_helper"

# Ella 整合修復 PR-1：主題渲染面 CSP（concern 檔頭＝完整理由）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   C1 storefront 放行 inline style/script（殺：CSP 回退全域嚴格＝前台退化
#      Times New Roman 無圖無互動——2026-09-01 生產實錘）
#   C2 script-src 無 nonce（殺：帶 nonce 則 'unsafe-inline' 被瀏覽器忽略，
#      inline event handler 仍死——CSP 規範行為）
#   C3 admin 維持嚴格（殺：放寬外溢到第一方 SPA＝XSS 面擴大）
RSpec.describe "Theme-surface CSP", type: :request do
  let(:shop) { create(:shop, subdomain: "csp-shop") }
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    allow(ThemeEngine::Sources).to receive(:base_resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    host! "csp-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "C1+C2 🔴 storefront：style/script 帶 unsafe-inline、script-src 無 nonce、img 帶 https" do
    get "/"
    expect(response).to have_http_status(:ok)
    csp = response.headers["Content-Security-Policy"].to_s
    expect(csp).to include("style-src 'self' 'unsafe-inline'")
    expect(csp).to include("script-src 'self' 'unsafe-inline'")
    expect(csp[/script-src[^;]*/]).not_to include("nonce-") # 🔴 有 nonce 則 unsafe-inline 失效
    expect(csp).to include("img-src 'self' data: https:")
  end

  it "C2b 編輯器 iframe 預覽同為主題面 CSP" do
    post login_path, params: { email: staff.email, password: "long-password-123" }
    get "/admin/store/preview/#{theme.id}"
    csp = response.headers["Content-Security-Policy"].to_s
    expect(csp).to include("style-src 'self' 'unsafe-inline'")
    expect(csp[/script-src[^;]*/]).not_to include("nonce-")
  end

  it "C3 🔴 admin 維持嚴格：無 unsafe-inline、script-src 帶 nonce" do
    post login_path, params: { email: staff.email, password: "long-password-123" }
    get admin_root_path
    csp = response.headers["Content-Security-Policy"].to_s
    expect(csp).not_to include("unsafe-inline")
    expect(csp[/script-src[^;]*/]).to include("nonce-")
  end
end
