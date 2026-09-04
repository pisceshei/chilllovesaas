# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-12：店面主題預覽釘選（?preview_theme_id= sticky cookie）＋預覽列。
# 對位：83 §12.3 live 實測（sticky cookie／復位法＝帶正式主題 id，2026-08-31）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   TP1 sticky（殺：只看參數 ⇒ 第二個請求跳回正式主題，導航即掉預覽）
#   TP2 復位法（殺：釘上解不開＝83 §12.3 量測坑的使用者版）
#   TP4 資產跟主題（殺：預覽頁配正式 CSS——版面驗證全是假象；no-store 防同
#       URL 快取互汙）
#   TP5 預覽不進頁快取（殺：命中正式頁快取 ⇒ 預覽假象；寫入 ⇒ 汙染）
RSpec.describe "Storefront theme preview pinning", type: :request do
  let(:shop) { create(:shop, subdomain: "tp-shop") }
  let!(:live_theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Live", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let!(:draft_theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "DraftElla", version: "1.0", role: "draft",
                    source: "first_party", license_attested: true)
    end
  end

  before do
    # 兩主題各接不同 fixture：正式＝minimal-1.0、草稿＝preview-mini（帶標記）
    allow(ThemeEngine::Sources).to receive(:base_resolve) do |t|
      dir = t.id == draft_theme.id ? "preview-mini" : "minimal-1.0"
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/#{dir}"))
    end
    host! "tp-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    Rails.cache.clear
  end

  it "TP1 🔴 帶 preview_theme_id ⇒ 渲染草稿主題＋預覽列＋no-store/noindex；之後不帶參數仍 sticky" do
    get "/?preview_theme_id=#{draft_theme.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("PREVIEW-MINI-LAYOUT")      # 🔴 渲染的是草稿主題
    expect(response.body).to include("cl-preview-bar")           # 預覽列
    expect(response.body).to include("DraftElla")                # 列上主題名
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["X-Robots-Tag"]).to include("noindex")

    get "/" # 🔴 sticky：不帶參數照樣預覽（83 §12.3）
    expect(response.body).to include("PREVIEW-MINI-LAYOUT")
    expect(response.body).to include("cl-preview-bar")
  end

  it "TP2 🔴 復位法：帶正式主題 id ⇒ 解除釘選；之後回正式主題、無預覽列" do
    get "/?preview_theme_id=#{draft_theme.id}"
    expect(response.body).to include("PREVIEW-MINI-LAYOUT")

    get "/?preview_theme_id=#{live_theme.id}" # 復位
    expect(response.body).not_to include("PREVIEW-MINI-LAYOUT")
    expect(response.body).not_to include("cl-preview-bar")

    get "/" # 解除後不 sticky
    expect(response.body).not_to include("PREVIEW-MINI-LAYOUT")
  end

  it "TP3 無效 id／他店主題 id ⇒ 落回正式主題並清釘" do
    other_shop = create(:shop, subdomain: "tp-other")
    other_theme = ActsAsTenant.with_tenant(other_shop) do
      Theme.create!(shop_id: other_shop.id, name: "Foreign", version: "1.0",
                    role: "draft", source: "first_party", license_attested: true)
    end

    get "/?preview_theme_id=999999999"
    expect(response.body).not_to include("cl-preview-bar")

    get "/?preview_theme_id=#{other_theme.id}" # 跨租戶 ⇒ with_tenant 查無
    expect(response.body).not_to include("PREVIEW-MINI-LAYOUT")
    expect(response.body).not_to include("cl-preview-bar")
  end

  it "TP4 🔴 資產跟主題：釘選時 /theme-assets 供草稿主題檔＋no-store；未釘選＝正式檔＋max-age" do
    get "/theme-assets/site.css"
    expect(response.body).not_to include("PREVIEW-MINI-CSS")
    expect(response.headers["Cache-Control"]).to include("max-age=300")

    get "/?preview_theme_id=#{draft_theme.id}" # 釘上（cookie）
    get "/theme-assets/site.css"
    expect(response.body).to include("PREVIEW-MINI-CSS")         # 🔴 草稿主題的資產
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "TP5 🔴 預覽不進頁快取：預覽期間不寫入；解除後正式頁不含預覽痕跡" do
    get "/" # 正式頁進快取
    expect(response.body).not_to include("cl-preview-bar")

    get "/?preview_theme_id=#{draft_theme.id}"
    get "/" # sticky 預覽——若命中正式頁快取＝假象
    expect(response.body).to include("PREVIEW-MINI-LAYOUT")

    get "/?preview_theme_id=#{live_theme.id}" # 復位
    get "/"
    expect(response.body).not_to include("PREVIEW-MINI-LAYOUT")  # 快取未被預覽寫髒
    expect(response.body).not_to include("cl-preview-bar")
  end
end
