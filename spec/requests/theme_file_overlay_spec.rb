# frozen_string_literal: true

require "rails_helper"

# 步 16e1：主題檔案 DB 覆寫層（code editor 資料層）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   F2 AST cache 租戶隔離（殺：overlay 檔沿用共用鍵 ⇒ A 店編輯汙染 B 店編譯
#      ——15a 跨租戶汙染同軸，本包的存在理由）
#   F3 touch theme（殺：漏 touch＝前台頁快取永遠舊頁——步 2 紅字）
#   F4 白名單（殺：templates/ 雙真相源、路徑逃逸、未知頂層目錄入庫）
RSpec.describe "Theme file overlay", type: :request do
  let(:shop) { create(:shop, subdomain: "ovl-shop-a") }
  let(:shop_b) { create(:shop, subdomain: "ovl-shop-b") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  def build_theme(owner)
    ActsAsTenant.with_tenant(owner) do
      Theme.create!(shop_id: owner.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  let!(:theme) { build_theme(shop) }
  let(:gid) { "gid://chilllove/Theme/#{theme.id}" }

  before do
    host! "ovl-shop-a.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    # 🔴 stub base_resolve（不是 resolve）——讓真 resolve 的 overlay 包裝邏輯跑到
    allow(ThemeEngine::Sources).to receive(:base_resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def upsert(path:, content:, lock_version: nil)
    post admin_graphql_path, params: {
      query: <<~GQL,
        mutation($themeId: ID!, $path: String!, $content: String!, $lockVersion: Int) {
          themeFileUpsert(themeId: $themeId, path: $path, content: $content, lockVersion: $lockVersion) {
            path lockVersion userErrors { message code }
          }
        }
      GQL
      variables: { themeId: gid, path:, content:, lockVersion: lock_version }
    }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body.dig("data", "themeFileUpsert")
  end

  def render_home(owner, owner_theme)
    publication = ActsAsTenant.with_tenant(owner) { Publication.online_store! }
    ThemeEngine::PageRenderer.new(theme: owner_theme, shop: owner, publication:).render("/")
  end

  it "F1 upsert 建列；overlay 讀優先（渲染吃到編輯後 section）；list 併集含新檔" do
    result = upsert(path: "sections/hero.liquid",
                    content: %(<h1 data-ovl>{{ section.settings.heading }}</h1>{% schema %}{ "name": "Hero", "settings": [] }{% endschema %}))
    expect(result["userErrors"]).to eq([])
    expect(result["lockVersion"]).to eq(0)
    expect(render_home(shop, theme).html).to include("<h1 data-ovl>首頁英雄</h1>")

    upsert(path: "snippets/cl-extra.liquid", content: "extra")
    source = ThemeEngine::Sources.resolve(theme)
    expect(source.list).to include("snippets/cl-extra.liquid") # 新檔（base 沒有）入清單
    expect(source.read("snippets/cl-extra.liquid")).to eq("extra")
  end

  it "F2 🔴 AST cache 租戶隔離：A 店編輯 section 不汙染 B 店；A 再編輯即時生效" do
    theme_b = build_theme(shop_b)
    upsert(path: "sections/hero.liquid",
           content: %(<h1 data-ovl>{{ section.settings.heading }}</h1>{% schema %}{ "name": "Hero", "settings": [] }{% endschema %}))

    expect(render_home(shop, theme).html).to include("data-ovl")          # A 吃 overlay
    expect(render_home(shop_b, theme_b).html).not_to include("data-ovl")  # 🔴 B 必須是 base

    # A 再編輯 ⇒ 版本戳旋轉 ⇒ 不吃舊編譯（殺：stamp 不變／快取不失效）
    upsert(path: "sections/hero.liquid",
           content: %(<h1 data-ovl2>{{ section.settings.heading }}</h1>{% schema %}{ "name": "Hero", "settings": [] }{% endschema %}),
           lock_version: 0)
    expect(render_home(shop, theme).html).to include("data-ovl2")
  end

  it "F3 🔴 寫入 touch theme（頁快取鍵旋轉——步 2 紅字）" do
    before_touch = theme.reload.updated_at
    travel(2.seconds) { upsert(path: "snippets/cl-touch.liquid", content: "x") }
    expect(theme.reload.updated_at).to be > before_touch
  end

  it "F4 🔴 路徑白名單：templates/ 與 settings_data 雙真相源拒收；逃逸與未知頂層拒收" do
    [
      "templates/index.json",        # Template 覆寫層管
      "config/settings_data.json",   # ThemeSetting 覆寫層管
      "../evil.liquid",              # 逃逸
      "sections/a/b.liquid",         # 三段
      "secrets/x.liquid",            # 未知頂層
      "sections/.hidden"             # 符號開頭檔名
    ].each do |bad|
      result = upsert(path: bad, content: "x")
      expect(result.dig("userErrors", 0, "code")).to eq("INVALID"), "path #{bad} 應被拒"
    end
    expect(ActsAsTenant.with_tenant(shop) { ThemeFileOverlay.count }).to eq(0)
  end

  it "F5 單檔上限依型（Liquid 官方 256 KB）超限拒收" do
    cap = Limits.fetch(:theme_editor, :liquid_file_max_kb) * 1024
    result = upsert(path: "sections/big.liquid", content: "a" * (cap + 1))
    expect(result.dig("userErrors", 0, "code")).to eq("INVALID")
    expect(result.dig("userErrors", 0, "message")).to include("256")
  end

  it "F6 🔴 樂觀鎖：帶舊 lockVersion ⇒ STALE、內容不被覆蓋" do
    upsert(path: "snippets/cl-lock.liquid", content: "v0")
    upsert(path: "snippets/cl-lock.liquid", content: "v1", lock_version: 0)
    stale = upsert(path: "snippets/cl-lock.liquid", content: "v2", lock_version: 0)
    expect(stale.dig("userErrors", 0, "code")).to eq("STALE_OBJECT")
    row = ActsAsTenant.with_tenant(shop) { ThemeFileOverlay.find_by!(path: "snippets/cl-lock.liquid") }
    expect(row.content).to eq("v1")
  end

  it "F7 themeDuplicate 一併拷 overlay 列（零複製副本不得丟編輯）" do
    upsert(path: "snippets/cl-dup.liquid", content: "dup-me")
    post admin_graphql_path, params: {
      query: <<~GQL,
        mutation($id: ID!) { themeDuplicate(id: $id) { theme { id } userErrors { message } } }
      GQL
      variables: { id: gid }
    }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    copy_gid = response.parsed_body.dig("data", "themeDuplicate", "theme", "id")
    copy_id = copy_gid[%r{/(\d+)\z}, 1]
    copied = ActsAsTenant.with_tenant(shop) do
      ThemeFileOverlay.find_by(theme_id: copy_id, path: "snippets/cl-dup.liquid")
    end
    expect(copied&.content).to eq("dup-me")
  end
end
