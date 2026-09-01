# frozen_string_literal: true

require "rails_helper"

# 步 16b：模板整份寫回（樂觀鎖＋touch theme 紅線）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   U2 STALE 衝突（殺：後存者靜默互蓋＝兩個 staff 對編輯互相吃掉）
#   U3 touch theme（殺：漏 touch＝前台頁快取永遠舊頁——步 2 紅字）
#   U4 content 形閘（殺：壞 JSON 入庫 ⇒ 渲染整頁 fallback）
RSpec.describe "Theme template upsert", type: :request do
  let(:shop) { create(:shop, subdomain: "upsert-shop") }
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
    host! "upsert-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def upsert(content:, lock_version: nil, key: "index")
    post admin_graphql_path, params: {
      query: <<~GQL,
        mutation($themeId: ID!, $key: String!, $content: JSON!, $lockVersion: Int) {
          themeTemplateUpsert(themeId: $themeId, key: $key, content: $content, lockVersion: $lockVersion) {
            templateKey lockVersion userErrors { message code }
          }
        }
      GQL
      variables: { themeId: gid, key:, content:, lockVersion: lock_version }
    }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body.dig("data", "themeTemplateUpsert")
  end

  let(:valid_content) { { "sections" => { "hero" => { "type" => "hero", "settings" => {} } }, "order" => [ "hero" ] } }

  it "U1 首存建列（template_type 由 key 導出）；再存帶 lockVersion 遞增" do
    first = upsert(content: valid_content)
    expect(first["userErrors"]).to eq([])
    expect(first["lockVersion"]).to eq(0)
    row = ActsAsTenant.with_tenant(shop) { Template.find_by!(theme_id: theme.id, key: "index") }
    expect(row.template_type).to eq("index")

    second = upsert(content: valid_content.merge("order" => []), lock_version: 0)
    expect(second["userErrors"]).to eq([])
    expect(second["lockVersion"]).to eq(1)
  end

  it "U2 🔴 樂觀鎖：帶舊 lockVersion ⇒ STALE、內容不被覆蓋" do
    upsert(content: valid_content)
    # 🔴 第二寫必須是**真變更**——內容相同的 update 是 no-op、不進位 lock（本輪實錘）
    upsert(content: valid_content.merge("order" => []), lock_version: 0) # → v1
    stale = upsert(content: { "sections" => {}, "order" => [] }, lock_version: 0)
    expect(stale.dig("userErrors", 0, "code")).to eq("STALE_OBJECT")
    row = ActsAsTenant.with_tenant(shop) { Template.find_by!(theme_id: theme.id, key: "index") }
    expect(row.content["sections"]).to have_key("hero") # 舊寫入未被蓋
  end

  it "U3 🔴 寫入 touch theme（頁快取鍵旋轉——步 2 紅字）" do
    before_touch = theme.reload.updated_at
    travel(2.seconds) { upsert(content: valid_content) }
    expect(theme.reload.updated_at).to be > before_touch
  end

  it "U4 🔴 content 形閘＋key 逃逸拒收" do
    bad = upsert(content: { "order" => [] }) # 缺 sections hash
    expect(bad.dig("userErrors", 0, "code")).to eq("INVALID")

    escaped = upsert(content: valid_content, key: "../evil")
    expect(escaped.dig("userErrors", 0, "code")).to eq("INVALID")
    expect(ActsAsTenant.with_tenant(shop) { Template.count }).to eq(0)
  end
end
