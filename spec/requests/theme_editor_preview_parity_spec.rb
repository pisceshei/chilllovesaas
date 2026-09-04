# frozen_string_literal: true

require "rails_helper"

# E13 主題編輯器預覽 computed 對表（鐵律 22.1「兩者皆是」；docs/dev/e13-theme-editor-preview-parity.md）。
# 用 scripts/computed-parity.mjs --cookie 量編輯器預覽 iframe 時抓到的兩個引擎缺口，各鎖一格：
#   PV1  預覽主題 .js 資產在 CSRF 防護開啟下仍 200——Rails cross-origin JS 防護（verify_same_origin_request）把
#        iframe 的每個 <script src> 打成 422 ⇒ 主題 JS 一支都不載（Ella 21 支）。test 環境 forgery 預設關 ⇒ 顯式開再打
#        （同 storefront S10）。
#   PV1b 跳過只限 asset：draft_page（POST、寫草稿 cache）在防護開啟下缺 token 仍被擋。
#   PV2  預覽以店預設市場語言渲染：<html lang>／Shopify.locale／Shopify.country 與公開店面同值（原本 lang=""）。
#   PV2b 跟的是 presence 預設語言，不是來源語言：預設切到 zh-Hant ⇒ 與 /zh-hant-hk/ 同值。
#   PV3  draft_section 片段同一語言真相：預設 zh-Hant ⇒ 片段出 zh-Hant 譯文。
RSpec.describe "Theme editor preview parity (E13)", type: :request do
  let(:shop) { create(:shop, subdomain: "e13-shop") }
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
    host! "e13-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def presence
    Market.find_by!(is_primary: true).market_web_presences.sole
  end

  # 預設語言切到 zh-Hant（發布＋進 presence 白名單＋設為 presence 預設；67 §C.8(b) 唯一入口）。
  def default_zh_hant!
    ActsAsTenant.with_tenant(shop) do
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
      presence.set_default_locale!("zh-Hant")
    end
  end

  # 語言真相探針取引擎層的 Shopify 全域（每個主題都輸出；minimal fixture 的 <html> 沒有 lang 屬性——Ella 的
  # `lang="{{ request.locale.iso_code }}"` 走同一個 @locale，E13 本機實測預覽 lang="zh-CN"）。
  def head_facts(html)
    { locale: html[/Shopify\.locale = "([^"]*)"/, 1],
      country: html[/Shopify\.country = "([^"]*)"/, 1] }
  end

  it "PV1 🔴 預覽主題 .js 資產在 CSRF 防護開啟下仍 200（cross-origin JS 防護 422 ⇒ 編輯器 iframe 主題 JS 全數不載）" do
    ActionController::Base.allow_forgery_protection = true
    get "/admin/store/preview/#{theme.id}/assets/site.js"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/javascript")
    expect(response.body).to include("console.log")
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "PV1b 🔴 CSRF 跳過只限 asset：draft_page 在防護開啟下缺 token 仍被擋（不得整個 controller 放行）" do
    ActionController::Base.allow_forgery_protection = true
    begin
      post "/admin/store/preview/#{theme.id}/draft_page",
           params: { path: "/", sections: {}, settings: {} }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    rescue ActionController::InvalidAuthenticityToken
      # test 環境 show_exceptions 關 ⇒ 直接 raise，同一事實（被擋）
    end
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "PV2 🔴 預覽以店預設市場語言渲染：Shopify.locale／Shopify.country 與公開店面同值（不再 locale=\"\"、Ella lang=\"\"）" do
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response).to have_http_status(:ok)
    preview = head_facts(response.body)

    get "/en-hk/"
    expect(response).to have_http_status(:ok)
    storefront = head_facts(response.body)

    expect(preview[:locale]).to be_present
    expect(preview[:country]).to be_present
    expect(preview).to eq(storefront)
  end

  it "PV2b 🔴 跟 presence 預設語言走（切到 zh-Hant ⇒ 與 /zh-hant-hk/ 同值），不是來源語言" do
    default_zh_hant!
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response).to have_http_status(:ok)
    preview = head_facts(response.body)

    get "/zh-hant-hk/"
    expect(response).to have_http_status(:ok)

    expect(preview[:locale]).to be_present
    expect(preview[:locale]).not_to eq("en")
    expect(preview).to eq(head_facts(response.body))
  end

  it "PV3 🔴 draft_section 片段與 show 同一語言真相：預設 zh-Hant ⇒ 片段出 zh-Hant 譯文" do
    default_zh_hant!
    post "/admin/store/preview/#{theme.id}/draft_section",
         params: { path: "/", section_id: "related-products",
                   entry: { type: "related-products", settings: {} } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("你好買家")
    expect(response.body).not_to include("Hello shopper")
  end
end
