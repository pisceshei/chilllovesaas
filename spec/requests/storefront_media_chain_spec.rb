# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-2：真圖鏈（六軸診斷 image 軸；根因 A＋B）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   M1 媒體端點租戶隔離（殺：跨店 id 可拉檔＝檔案庫外洩）
#   M2 ImageDrop#url 接端點（殺：回退恆 nil＝0 <img> 根因 A 復發）
#   M3 settings resolver 解引用真檔（殺：非空值恆佔位＝根因 B 復發）
#   M4 空值維持 nil（殺：改成佔位 drop 會翻轉全主題 `!= blank` gate——
#      官方契約，除零軸取證）
RSpec.describe "Storefront media chain", type: :request do
  let(:shop) { create(:shop, subdomain: "media-shop") }
  let(:other_shop) { create(:shop, subdomain: "media-other") }
  let(:png) { "\x89PNG\r\n\x1a\n".b + ("x" * 64).b } # 帶 CRLF 位元的假 PNG（binread 對照）

  def make_file(owner, filename)
    key = "shops/#{owner.id}/files/#{SecureRandom.uuid}.png"
    Storage::LocalDisk.write(key, StringIO.new(png))
    ActsAsTenant.with_tenant(owner) do
      StoredFile.create!(shop_id: owner.id, filename:, content_type: "image/png",
                         byte_size: png.bytesize, checksum: Digest::SHA256.hexdigest(png),
                         storage_key: key, status: "ready", width: 1200, height: 800)
    end
  end

  let!(:file) { make_file(shop, "hero.png") }

  before do
    host! "media-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "M1 🔴 媒體端點：本店 200＋型別＋快取頭＋位元組完整；跨店 id＝404；查無＝404" do
    get "/media/#{file.id}/hero.png"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Cache-Control"]).to include("public")
    expect(response.body.b).to eq(png) # binread 完整性（CRLF 位元不被譯壞）

    foreign = make_file(other_shop, "steal.png")
    get "/media/#{foreign.id}/steal.png"
    expect(response).to have_http_status(:not_found)

    get "/media/999999/none.png"
    expect(response).to have_http_status(:not_found)
  end

  it "M2 🔴 ImageDrop/FileImageDrop 的 url＝媒體端點路徑（非 nil）" do
    media = instance_double(Media, id: 7, position: 1, stored_file: file)
    drop = ThemeEngine::ImageDrop.new(media)
    expect(drop.url).to eq("/media/#{file.id}/hero.png")
    expect(ThemeEngine::FileImageDrop.new(file).url).to eq("/media/#{file.id}/hero.png")
    expect(ThemeEngine::FileImageDrop.new(file).aspect_ratio).to be_within(0.01).of(1.5)
  end

  it "M3 🔴 settings image_picker：shopify://shopify/files/{name} 命中 ⇒ 真圖 drop；未命中 ⇒ 佔位；M4 空值 ⇒ nil" do
    ActsAsTenant.with_tenant(shop) do
      theme = Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                            source: "first_party", license_attested: true)
      allow(ThemeEngine::Sources).to receive(:base_resolve).and_return(
        ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
      )
      publication = Publication.online_store!
      runtime = ThemeEngine::Runtime.new(shop:, theme:, publication:)

      expect(runtime.resolve_settings_file("shopify://shopify/files/hero.png")).to eq(file)
      expect(runtime.resolve_settings_file("hero.png")).to eq(file) # 裸檔名同解
      expect(runtime.resolve_settings_file("shopify://collections/x")).to be_nil # 其他資源形不解
      expect(runtime.resolve_settings_file("missing.png")).to be_nil
    end

    # drop 層（liquid context 注入 runtime register 的形）：命中真圖／未命中佔位／空值 nil
    types = { "img" => "image_picker" }
    drop = ThemeEngine::SettingsDrop.new(
      { "img" => "shopify://shopify/files/hero.png", "empty" => "", "miss" => "nope.png" },
      types.merge("empty" => "image_picker", "miss" => "image_picker"))
    fake_runtime = ActsAsTenant.with_tenant(shop) do
      theme = Theme.find_by!(name: "Minimal")
      ThemeEngine::Runtime.new(shop:, theme:, publication: Publication.online_store!)
    end
    ctx = Liquid::Context.new
    ctx.registers[:runtime] = fake_runtime
    drop.context = ctx

    hit = drop.liquid_method_missing("img")
    expect(hit).to be_a(ThemeEngine::FileImageDrop)
    expect(hit.url).to eq("/media/#{file.id}/hero.png")
    expect(drop.liquid_method_missing("miss")).to be_a(ThemeEngine::PlaceholderImageDrop)
    expect(drop.liquid_method_missing("empty")).to be_nil # 🔴 M4 官方契約
  end

  it "SR1 🔴 媒體端點變體選擇：?width= 取最小 ≥ 請求的 fit 變體；超原圖回原圖；衍生缺檔回落原圖" do
    thumb = "THUMB".b
    key = "shops/#{shop.id}/files/#{SecureRandom.uuid}-thumb.webp"
    Storage::LocalDisk.write(key, StringIO.new(thumb))
    ActsAsTenant.with_tenant(shop) do
      file.update!(derivatives: {
        "thumb" => { "key" => key, "width" => 200, "height" => 133 },
        "card" => { "key" => "missing/card.webp", "width" => 600, "height" => 400 },
        "og" => { "key" => "og/should-not-be-used.webp", "width" => 1200, "height" => 630 }
      })
    end

    get "/media/#{file.id}/hero.png?width=150"
    expect(response.media_type).to eq("image/webp") # thumb（200 ≥ 150 的最小者）
    expect(response.body.b).to eq(thumb)

    get "/media/#{file.id}/hero.png?width=300" # card（600）命中但 blob 缺 ⇒ 回落原圖
    expect(response.media_type).to eq("image/png")
    expect(response.body.b).to eq(png)

    get "/media/#{file.id}/hero.png?width=5000" # 全部不足 ⇒ 原圖（永不放大）
    expect(response.media_type).to eq("image/png")
    expect(response.body.b).to eq(png)
  end

  it "SR2 🔴 image_tag widths：逐寬換 width 參數組 srcset、只取 ≤ src width；widths 不落 HTML 屬性" do
    ActsAsTenant.with_tenant(shop) { file.update!(alt_text: "hero") }
    filters = Class.new { include ThemeEngine::Filters }.new
    url = ThemeEngine::ImageUrlResult.new("/media/9/x.png?width=800",
                                          source_drop: ThemeEngine::FileImageDrop.new(file),
                                          requested_width: 800)
    tag = filters.image_tag(url, { "widths" => "200, 400, 800, 1600" })
    expect(tag).to include('srcset="/media/9/x.png?width=200 200w, /media/9/x.png?width=400 400w, /media/9/x.png?width=800 800w"')
    expect(tag).not_to include("1600w")        # 🔴 官方：只到 src width 上限
    expect(tag).not_to include("widths=")      # 🔴 widths 不落 HTML 屬性（先前實錘誤輸出）
    expect(tag).to include('alt="hero"')       # drop alt 推導
  end

  it "M5 渲染級：section 設定帶真檔值 ⇒ 頁面出真 <img src=/media/...>" do
    ActsAsTenant.with_tenant(shop) do
      theme = Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                            source: "first_party", license_attested: true)
      allow(ThemeEngine::Sources).to receive(:base_resolve).and_return(
        ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
      )
      # minimal 主題 promo section 帶 image 設定：以 DB template 覆寫注入
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index", template_type: "index",
                       content: { "sections" => { "p" => { "type" => "promo-img",
                                                           "settings" => { "img" => "shopify://shopify/files/hero.png" } } },
                                  "order" => [ "p" ] })
      ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id, path: "sections/promo-img.liquid",
                               content: <<~LIQUID)
                                 {{ section.settings.img | image_url: width: 800 | image_tag }}
                                 {% schema %}{ "name": "PromoImg", "settings": [ { "id": "img", "type": "image_picker" } ] }{% endschema %}
                               LIQUID
      html = ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!)
                                      .render("/").html
      # PR-9 升級斷言：官方 image_url/image_tag 形——width 參數＋height 推導
      # （1200×800 ⇒ 800÷1.5=533）＋srcset（官方例證同形）
      expect(html).to include(%(src="/media/#{file.id}/hero.png?width=800"))
      expect(html).to include(%(width="800" height="533"))
      expect(html).to include(%(srcset="/media/#{file.id}/hero.png?width=800 800w"))
    end
  end
end
