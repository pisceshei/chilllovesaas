# frozen_string_literal: true

require "rails_helper"

# 步 16d2：佈景設定整份寫回（樂觀鎖＋touch theme 紅線——與 template upsert 同構）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   TS2 STALE 衝突（殺：後存者靜默互蓋）
#   TS3 touch theme（殺：漏 touch＝前台頁快取永遠舊頁——步 2 紅字）
RSpec.describe "Theme settings upsert", type: :request do
  let(:shop) { create(:shop, subdomain: "tsettings-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let(:gid) { "gid://chilllove/Theme/#{theme.id}" }

  before do
    host! "tsettings-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def upsert(settings:, lock_version: nil)
    post admin_graphql_path, params: {
      query: <<~GQL,
        mutation($themeId: ID!, $settings: JSON!, $lockVersion: Int) {
          themeSettingsUpsert(themeId: $themeId, settings: $settings, lockVersion: $lockVersion) {
            lockVersion userErrors { message code }
          }
        }
      GQL
      variables: { themeId: gid, settings:, lockVersion: lock_version }
    }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body.dig("data", "themeSettingsUpsert")
  end

  it "TS1 首存建列（lockVersion 0）；再存真變更遞增；非 Hash 拒收" do
    first = upsert(settings: { "brand_color" => "#123456" })
    expect(first["userErrors"]).to eq([])
    expect(first["lockVersion"]).to eq(0)

    second = upsert(settings: { "brand_color" => "#654321" }, lock_version: 0)
    expect(second["userErrors"]).to eq([])
    expect(second["lockVersion"]).to eq(1)

    bad = upsert(settings: [ "not-a-hash" ])
    expect(bad.dig("userErrors", 0, "code")).to eq("INVALID")
  end

  it "TS2 🔴 樂觀鎖：帶舊 lockVersion ⇒ STALE、內容不被覆蓋" do
    upsert(settings: { "brand_color" => "#111111" })
    upsert(settings: { "brand_color" => "#222222" }, lock_version: 0) # → v1
    stale = upsert(settings: { "brand_color" => "#333333" }, lock_version: 0)
    expect(stale.dig("userErrors", 0, "code")).to eq("STALE_OBJECT")
    row = ActsAsTenant.with_tenant(shop) { ThemeSetting.find_by!(theme_id: theme.id) }
    expect(row.settings["brand_color"]).to eq("#222222") # 舊寫入未被蓋
  end

  it "TS3 🔴 寫入 touch theme（頁快取鍵旋轉——步 2 紅字）" do
    before_touch = theme.reload.updated_at
    travel(2.seconds) { upsert(settings: { "brand_color" => "#444444" }) }
    expect(theme.reload.updated_at).to be > before_touch
  end
end
