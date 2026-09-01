# frozen_string_literal: true

require "rails_helper"
require "zip"

# 步 15b：主題 CRUD API（匯入 multipart 端點＋rename/duplicate/delete＋
# theme(id).files）。契約錨＝99 §1/§4。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   T2 已發布主題拒刪（殺：published 被刪 ⇒ 前台全店 500）
#   T3 duplicate 拷 DB 覆寫層（殺：漏拷＝複製後商家編輯全丟）
#   T4 files 萬用字元過濾（殺：filenames 被忽略 ⇒ 編輯器拿全量爆 payload）
RSpec.describe "Theme CRUD API", type: :request do
  let(:shop) { create(:shop, subdomain: "theme-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let(:tmp) { Pathname(Dir.mktmpdir) }

  before do
    host! "theme-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  after { FileUtils.rm_rf(tmp) }

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
  end

  def build_zip
    path = tmp.join("probe.zip")
    Zip::File.open(path.to_s, create: true) do |zip|
      zip.get_output_stream("layout/theme.liquid") { |io| io.write("<html>{{ content_for_layout }}</html>") }
      zip.get_output_stream("sections/hero.liquid") { |io| io.write("<h1>hi</h1>") }
      zip.get_output_stream("config/settings_schema.json") { |io| io.write('[{"name":"theme_info","theme_version":"1.2.3"}]') }
    end
    path
  end

  def import_theme!(name: "Imported Probe")
    post admin_theme_import_path, params: {
      file: Rack::Test::UploadedFile.new(build_zip, "application/zip"),
      name:, license_attested: "true"
    }
    expect(response).to have_http_status(:created), response.body
    response.parsed_body
  end

  it "T1 匯入端點：201＋theme GID＋報告；未聲明授權 ⇒ 422 LICENSE_NOT_ATTESTED" do
    body = import_theme!
    expect(body["theme_id"]).to match(%r{\Agid://chilllove/Theme/\d+\z})
    expect(body["checksum"]).to match(/\A\h{64}\z/)
    expect(body.dig("report", "files")).to eq(3)

    post admin_theme_import_path, params: {
      file: Rack::Test::UploadedFile.new(build_zip, "application/zip"),
      name: "沒授權", license_attested: "false"
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error_code"]).to eq("LICENSE_NOT_ATTESTED")
  end

  it "T2 🔴 rename＋published 拒刪＋draft 可刪（官方 delete an unpublished theme）" do
    gid = import_theme!["theme_id"]
    post_graphql(<<~GQL, variables: { id: gid })
      mutation($id: ID!) {
        themeRename(id: $id, name: "改名後") { theme { name } userErrors { code } }
      }
    GQL
    expect(response.parsed_body.dig("data", "themeRename", "theme", "name")).to eq("改名後")

    # 反向：超長名（官方 50 字上限）⇒ INVALID
    post_graphql(<<~GQL, variables: { id: gid, name: "長" * 51 })
      mutation($id: ID!, $name: String!) {
        themeRename(id: $id, name: $name) { theme { id } userErrors { code } }
      }
    GQL
    expect(response.parsed_body.dig("data", "themeRename", "userErrors", 0, "code")).to eq("INVALID")

    theme_row = ActsAsTenant.with_tenant(shop) { Theme.find(gid[%r{/(\d+)\z}, 1]) }
    ActsAsTenant.with_tenant(shop) { theme_row.publish! }
    post_graphql(<<~GQL, variables: { id: gid })
      mutation($id: ID!) { themeDelete(id: $id) { deletedThemeId userErrors { code } } }
    GQL
    expect(response.parsed_body.dig("data", "themeDelete", "userErrors", 0, "code"))
      .to eq("PUBLISHED_THEME_PROTECTED")

    ActsAsTenant.with_tenant(shop) { theme_row.update!(role: "draft") }
    post_graphql(<<~GQL, variables: { id: gid })
      mutation($id: ID!) { themeDelete(id: $id) { deletedThemeId userErrors { code } } }
    GQL
    expect(response.parsed_body.dig("data", "themeDelete", "deletedThemeId")).to eq(gid)
  end

  it "T3 🔴 duplicate：Copy of 命名＋同 checksum 零複製＋DB 覆寫層（templates/settings）一併拷" do
    gid = import_theme!(name: "原主題")["theme_id"]
    source_id = gid[%r{/(\d+)\z}, 1]
    ActsAsTenant.with_tenant(shop) do
      Template.create!(shop_id: shop.id, theme_id: source_id, key: "index",
                       template_type: "index", content: { "sections" => {}, "order" => [] })
      ThemeSetting.create!(shop_id: shop.id, theme_id: source_id, settings: { "brand" => "#123456" })
    end

    post_graphql(<<~GQL, variables: { id: gid })
      mutation($id: ID!) {
        themeDuplicate(id: $id) { theme { id name role } userErrors { code } }
      }
    GQL
    copy = response.parsed_body.dig("data", "themeDuplicate", "theme")
    expect(copy["name"]).to eq("Copy of 原主題")
    expect(copy["role"]).to eq("draft")

    copy_id = copy["id"][%r{/(\d+)\z}, 1]
    ActsAsTenant.with_tenant(shop) do
      expect(Theme.find(copy_id).content_checksum).to eq(Theme.find(source_id).content_checksum)
      expect(Template.where(theme_id: copy_id).pluck(:key)).to eq([ "index" ])
      expect(ThemeSetting.find_by(theme_id: copy_id).settings).to eq({ "brand" => "#123456" })
    end
  end

  it "T4 🔴 theme(id).files：清單＋filenames 萬用字元（官方 '*' 語義）＋importReport" do
    gid = import_theme!["theme_id"]
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) {
        theme(id: $id) {
          source licenseAttested importReport
          all: files { filename size }
          liquid: files(filenames: ["sections/*.liquid"]) { filename }
        }
      }
    GQL
    data = response.parsed_body.dig("data", "theme")
    expect(data["source"]).to eq("import")
    expect(data["licenseAttested"]).to be(true)
    expect(data.dig("importReport", "files")).to eq(3)
    expect(data["all"].map { |f| f["filename"] }).to eq(
      [ "config/settings_schema.json", "layout/theme.liquid", "sections/hero.liquid" ])
    expect(data["all"].first["size"]).to be > 0
    expect(data["liquid"].map { |f| f["filename"] }).to eq([ "sections/hero.liquid" ])
  end
end
