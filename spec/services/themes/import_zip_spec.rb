# frozen_string_literal: true

require "rails_helper"
require "zip"

# G3 步 15a：主題 zip 匯入八步管線（99 §1–§3）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   I2 缺 layout/theme.liquid 拒收（殺：官方唯一硬要求被拔 ⇒ 壞主題入庫炸渲染）
#   I3 路徑逃逸拒收（殺：../ 條目寫出 storage 外＝任意寫檔）
#   I4 授權聲明 gate（殺：未聲明照收＝鐵律 9 破口）
#   I6 壓縮比炸彈（殺：10MB 零字節 ⇒ 解壓灌爆磁碟）
#   I7 內容定址（殺：同內容不同鍵 ⇒ AST 跨租戶防線失效）
RSpec.describe Themes::ImportZip do
  let(:shop) { create(:shop) }
  let(:tmp) { Pathname(Dir.mktmpdir) }

  after do
    FileUtils.rm_rf(tmp)
  end

  def build_zip(name, entries)
    path = tmp.join(name)
    Zip::File.open(path.to_s, create: true) do |zip|
      entries.each do |rel, content|
        zip.get_output_stream(rel) { |io| io.write(content) }
      end
    end
    path
  end

  VALID_ENTRIES = {
    "layout/theme.liquid" => "<html>{{ content_for_layout }}</html>",
    "sections/hero.liquid" => "<h1>{{ section.settings.title }}</h1>\n{% schema %}{ \"name\": \"Hero\" }{% endschema %}",
    "config/settings_schema.json" => '[{ "name": "theme_info", "theme_name": "Probe", "theme_version": "9.9.9" }]',
    "templates/index.json" => '{ "sections": {}, "order": [] }'
  }.freeze

  def import(path, name: "Probe Theme", license: true)
    described_class.call(shop:, zip_path: path, name:, license_attested: license)
  end

  it "I1 合法 zip：主題入庫（source=import、checksum、version 自 schema）＋落盤＋ok 報告" do
    result = import(build_zip("ok.zip", VALID_ENTRIES))
    expect(result).to be_success
    theme = result.theme
    expect(theme.source).to eq("import")
    expect(theme.content_checksum).to match(/\A\h{64}\z/)
    expect(theme.version).to eq("9.9.9")
    expect(theme.role).to eq("draft")

    dir = Rails.root.join("storage", "themes", theme.content_checksum)
    expect(File.read(dir.join("layout/theme.liquid"))).to include("content_for_layout")
    report = ActsAsTenant.with_tenant(shop) { ThemeImportReport.last }
    expect(report.status).to eq("ok")
    expect(report.report["files"]).to eq(4)
    # Sources：內容定址鍵＋storage 解析（AST 汙染根治的接線點）
    expect(ThemeEngine::Sources.key_for(theme)).to eq("sha256-#{theme.content_checksum}")
    expect(ThemeEngine::Sources.resolve(theme).read("layout/theme.liquid")).to include("content_for_layout")
  end

  it "I2 🔴 缺 layout/theme.liquid ⇒ MISSING_LAYOUT＋failed 報告、不建主題" do
    result = import(build_zip("nolayout.zip", VALID_ENTRIES.except("layout/theme.liquid")))
    expect(result).not_to be_success
    expect(result.error_code).to eq("MISSING_LAYOUT")
    expect(ActsAsTenant.with_tenant(shop) { Theme.where(source: "import").count }).to eq(0)
    expect(ActsAsTenant.with_tenant(shop) { ThemeImportReport.last }.status).to eq("failed")
  end

  it "I3 🔴 路徑逃逸整包拒收；非 zip 檔 ⇒ INVALID_ZIP（官方碼＋訊息形）" do
    evil = build_zip("evil.zip", VALID_ENTRIES.merge("layout/../../evil.rb" => "boom"))
    result = import(evil)
    expect(result.error_code).to eq("UNSAFE_PATH")
    expect(Dir.glob(Rails.root.join("evil.rb").to_s)).to eq([])

    notzip = tmp.join("fake.zip")
    File.write(notzip, "not a zip at all")
    result = import(notzip)
    expect(result.error_code).to eq("INVALID_ZIP")
    expect(result.error_message).to eq("Must be a zip file.")
  end

  it "I4 🔴 未聲明授權 ⇒ LICENSE_NOT_ATTESTED（鐵律 9 gate）" do
    result = import(build_zip("ok2.zip", VALID_ENTRIES), license: false)
    expect(result.error_code).to eq("LICENSE_NOT_ATTESTED")
    expect(ActsAsTenant.with_tenant(shop) { Theme.count }).to eq(0)
  end

  it "I5 單根 zip 剝根（ours——99 §3）；白名單外條目略過並入警告" do
    entries = VALID_ENTRIES.transform_keys { |rel| "my-theme/#{rel}" }
    entries["my-theme/README.md"] = "junk"
    result = import(build_zip("rooted.zip", entries))
    expect(result).to be_success
    dir = Rails.root.join("storage", "themes", result.theme.content_checksum)
    expect(File.exist?(dir.join("layout/theme.liquid"))).to be(true)
    expect(result.report["warnings"].join).to include("README.md")
  end

  it "I6 🔴 壓縮比炸彈拒收" do
    bomb = build_zip("bomb.zip", VALID_ENTRIES.merge("assets/bomb.dat" => "\0" * 20.megabytes))
    result = import(bomb)
    expect(result.error_code).to eq("COMPRESSION_BOMB")
  end

  it "I7 🔴 內容定址冪等：同內容兩次匯入＝同 checksum、目錄重用；相容掃描抓 Liquid 錯誤" do
    broken = VALID_ENTRIES.merge("snippets/bad.liquid" => "{% if x %}沒關")
    first = import(build_zip("a.zip", broken), name: "第一次")
    second = import(build_zip("b.zip", broken), name: "第二次")
    expect(first.theme.content_checksum).to eq(second.theme.content_checksum)
    expect(first.report["liquid_errors"].first["file"]).to eq("snippets/bad.liquid")
    # 🔴 反向：**同一組檔名**、僅內容一字之差 ⇒ 不同 checksum
    #   （equality-trap：檔名集也不同的對照組殺不掉「只摘要檔名」的退化）
    changed = broken.merge("snippets/bad.liquid" => "{% if y %}沒關")
    other = import(build_zip("c.zip", changed), name: "第三次")
    expect(other.theme.content_checksum).not_to eq(first.theme.content_checksum)
  end
end
