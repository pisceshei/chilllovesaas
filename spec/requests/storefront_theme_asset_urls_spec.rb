# frozen_string_literal: true

require "rails_helper"

# T12 主題資產 URL 本尊形（docs/dev/t12-theme-asset-urls.md；external-facts §G28，官方 filters 頁＋hoko.vip 2026-09-05）——格：
#   TA1 asset_url：`//host:port/cdn/shop/t/{id}/assets/{file}?v={≤20 位摘要}{主題版本秒}`；同檔同值、異檔異摘要；缺檔無 `?v=`；裸 registers 退舊形
#   TA2 asset_img_url：預設 `_small`、`'large'` ⇒ `_large`；`?v=` 取原檔
#   TA3 font_url／font_face：`//host/cdn/fonts/{family}/{handle}.{sha1}.woff2`（雜湊＝public/fonts 檔 SHA-1）；`'woff'` ⇒ `.woff`；font_face 兩行 src
#   TA4 file_url／file_img_url：`//host/cdn/shop/files/{name}?v=…`（StoredFile 以 filename 查）；缺檔仍出 URL 無 v；`_small`
#   TA5 shopify_asset_url／global_asset_url：`themes_support/{stem}-{8hex}{ext}`／`cdn/s/global/{file}`
#   TA6 供給端 /cdn/shop/t/{id}/assets/*：200＋hoko 標頭；錯 v 仍 200；尺寸形回原檔；逃逸／缺檔／異主題 id 404（max-age=60）；草稿主題以 id 亦 200
#   TA7 供給端 /cdn/fonts/*：200 immutable＋CORS；雜湊不符 404；.woff 404
#   TA8 供給端 /cdn/shop/files/*：完整檔名 200；`_large` 尺寸形 200（原檔回落）；缺 404
#   TA9 整頁：layout 的 stylesheet_tag 出本尊形（host 含埠由 request.host_with_port 決定）
#   TA10 Normalizer：我方形與 hoko 形正規化後相等（主機／主題 id／?v= 皆身分值）
RSpec.describe "Storefront theme asset URLs (T12)", type: :request do
  let(:shop) { create(:shop, subdomain: "t12-shop") }
  let(:fixture) { ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0")) }
  let(:theme) { ActsAsTenant.with_tenant(shop) { Theme.published.first } }
  let(:stamp) { theme.updated_at.to_i }

  before do
    host! "t12-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published", source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(fixture)
  end

  def harness(extra = {})
    h = Class.new { include ThemeEngine::Filters }.new
    regs = { theme: theme, source: fixture, asset_host: "t12-shop.lvh.me:3000", host: "t12-shop.lvh.me", shop_id: shop.id }.merge(extra)
    h.instance_variable_set(:@context, Struct.new(:registers).new(regs))
    h
  end

  def make_file(name, body = "PNG-#{name}")
    key = "t12/#{name}"
    Storage::LocalDisk.write(key, StringIO.new(body))
    ActsAsTenant.with_tenant(shop) do
      StoredFile.create!(shop_id: shop.id, filename: name, content_type: "image/png", byte_size: body.bytesize,
                         checksum: Digest::SHA256.hexdigest(body), storage_key: key, status: "ready", width: 10, height: 10)
    end
  end

  it "TA1 🔴 asset_url：本尊形 `//host:port/cdn/shop/t/{id}/assets/{file}?v={摘要}{版本秒}`；同檔同值、異檔異摘要；缺檔無 ?v=；裸 registers 退舊形" do
    url = harness.asset_url("site.css")
    expect(url).to match(%r{\A//t12-shop\.lvh\.me:3000/cdn/shop/t/#{theme.id}/assets/site\.css\?v=\d{1,20}#{stamp}\z})
    expect(harness.asset_url("site.css")).to eq(url)
    js = harness.asset_url("site.js")
    expect(js).to match(%r{/assets/site\.js\?v=\d{1,20}#{stamp}\z})
    expect(js[/v=(\d+)/, 1]).not_to eq(url[/v=(\d+)/, 1])
    expect(harness.asset_url("nope.css")).to eq("//t12-shop.lvh.me:3000/cdn/shop/t/#{theme.id}/assets/nope.css")
    bare = Class.new { include ThemeEngine::Filters }.new
    bare.instance_variable_set(:@context, Struct.new(:registers).new({}))
    expect(bare.asset_url("site.css")).to eq("/theme-assets/site.css")
  end

  it "TA2 asset_img_url：預設 _small、'large' ⇒ _large，?v= 取原檔" do
    v = harness.asset_url("site.css")[/v=(\d+)/, 1]
    expect(harness.asset_img_url("site.css")).to eq("//t12-shop.lvh.me:3000/cdn/shop/t/#{theme.id}/assets/site_small.css?v=#{v}")
    expect(harness.asset_img_url("site.css", "large")).to eq("//t12-shop.lvh.me:3000/cdn/shop/t/#{theme.id}/assets/site_large.css?v=#{v}")
  end

  it "TA3 🔴 font_url／font_face：`//host/cdn/fonts/jost/jost_n4.{sha1}.woff2`（雜湊＝檔 SHA-1）；'woff' ⇒ .woff；font_face 兩行 src" do
    drop = ThemeEngine::FontLibrary.drop("jost_n4")
    sha = Digest::SHA1.file(Rails.root.join("public/fonts/jost/jost_n4.woff2")).hexdigest
    expect(harness.font_url(drop)).to eq("//t12-shop.lvh.me:3000/cdn/fonts/jost/jost_n4.#{sha}.woff2")
    expect(harness.font_url(drop, "woff")).to eq("//t12-shop.lvh.me:3000/cdn/fonts/jost/jost_n4.#{sha}.woff")
    face = harness.font_face(drop)
    expect(face).to include(%(src: url("//t12-shop.lvh.me:3000/cdn/fonts/jost/jost_n4.#{sha}.woff2") format("woff2"),))
    expect(face).to include(%(url("//t12-shop.lvh.me:3000/cdn/fonts/jost/jost_n4.#{sha}.woff") format("woff");))
    expect(harness.font_url(ThemeEngine::FontLibrary.drop("sans_serif"))).to eq("")
  end

  it "TA4 file_url／file_img_url：`//host/cdn/shop/files/{name}?v=…`（filename 查 StoredFile）；缺檔仍出 URL 無 v；_small" do
    make_file("hero.png")
    url = harness.file_url("hero.png")
    expect(url).to match(%r{\A//t12-shop\.lvh\.me:3000/cdn/shop/files/hero\.png\?v=\d{1,20}\z})
    expect(harness.file_url("hero.png")).to eq(url)
    expect(harness.file_img_url("hero.png")).to eq(url.sub("hero.png", "hero_small.png"))
    expect(harness.file_img_url("hero.png", "large")).to eq(url.sub("hero.png", "hero_large.png"))
    expect(harness.file_url("missing.pdf")).to eq("//t12-shop.lvh.me:3000/cdn/shop/files/missing.pdf")
  end

  it "TA5 shopify_asset_url／global_asset_url：官方路徑形" do
    expect(harness.shopify_asset_url("option_selection.js"))
      .to match(%r{\A//t12-shop\.lvh\.me:3000/cdn/shopifycloud/storefront/assets/themes_support/option_selection-[0-9a-f]{8}\.js\z})
    expect(harness.shopify_asset_url("vendor/qrcode.js"))
      .to match(%r{/themes_support/vendor/qrcode-[0-9a-f]{8}\.js\z})
    expect(harness.global_asset_url("lightbox.js")).to eq("//t12-shop.lvh.me:3000/cdn/s/global/lightbox.js")
  end

  it "TA6 🔴 供給端 /cdn/shop/t/{id}/assets/*：200＋hoko 標頭；錯 v 仍 200；尺寸形回原檔；逃逸／缺檔／異主題 404；草稿主題以 id 亦 200" do
    get "/cdn/shop/t/#{theme.id}/assets/site.css?v=#{stamp}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("color: #111")
    expect(response.headers["Cache-Control"].split(", ")).to match_array(%w[public max-age=31557600]) # Rails 重排指令順序（91 記）
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")

    get "/cdn/shop/t/#{theme.id}/assets/site.css?v=1"
    expect(response).to have_http_status(:ok)

    get "/cdn/shop/t/#{theme.id}/assets/site_large.css"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("color: #111")

    get "/cdn/shop/t/#{theme.id}/assets/..%2Fconfig%2Fsettings_schema.json"
    expect(response).to have_http_status(:not_found)
    expect(response.headers["Cache-Control"].split(", ")).to match_array(%w[public max-age=60])

    get "/cdn/shop/t/#{theme.id}/assets/nope.css"
    expect(response).to have_http_status(:not_found)

    get "/cdn/shop/t/999999/assets/site.css"
    expect(response).to have_http_status(:not_found)

    draft = ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Draft", version: "1.0", role: "draft", source: "first_party", license_attested: true)
    end
    get "/cdn/shop/t/#{draft.id}/assets/site.css"
    expect(response).to have_http_status(:ok)
  end

  it "TA7 供給端 /cdn/fonts/*：200 immutable＋CORS；雜湊不符 404；.woff 404" do
    sha = Digest::SHA1.file(Rails.root.join("public/fonts/jost/jost_n4.woff2")).hexdigest
    get "/cdn/fonts/jost/jost_n4.#{sha}.woff2"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to start_with("font/woff2")
    expect(response.headers["Cache-Control"].split(", ")).to match_array(%w[public max-age=31536000 immutable])
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    expect(response.body.bytesize).to eq(File.size(Rails.root.join("public/fonts/jost/jost_n4.woff2")))

    get "/cdn/fonts/jost/jost_n4.#{'0' * 40}.woff2"
    expect(response).to have_http_status(:not_found)
    get "/cdn/fonts/jost/jost_n4.#{sha}.woff"
    expect(response).to have_http_status(:not_found)
  end

  it "TA8 供給端 /cdn/shop/files/*：完整檔名 200；_large 尺寸形 200（原檔回落）；缺 404" do
    make_file("hero.png", "PNG-BODY")
    get "/cdn/shop/files/hero.png?v=123"
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("PNG-BODY")
    get "/cdn/shop/files/hero_large.png"
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("PNG-BODY")
    get "/cdn/shop/files/nope.png"
    expect(response).to have_http_status(:not_found)
  end

  it "TA9 整頁：模板裡的 asset_url／file_url／font_url 出本尊形（主機＝request.host_with_port）" do
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee")
      create(:product_variant, shop:, product: p, price_cents: 18800)
    end
    make_file("hero.png")
    get "/products/acme-tee?view=t12"
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{data-t12-css href="//t12-shop\.lvh\.me/cdn/shop/t/#{theme.id}/assets/site\.css\?v=\d{1,20}#{stamp}"})
    expect(response.body).to match(%r{data-t12-file>//t12-shop\.lvh\.me/cdn/shop/files/hero\.png\?v=\d{1,20}<})
    expect(response.body).not_to include("/theme-assets/")
  end

  it "TA10 Normalizer：我方形與 hoko 形正規化後相等" do
    ours = %(<link href="//t12-shop.lvh.me:3000/cdn/shop/t/#{theme.id}/assets/base.css?v=12345678901234567890#{stamp}" rel="stylesheet" type="text/css" media="all" />)
    hoko = %(<link href="//hoko.vip/cdn/shop/t/2/assets/base.css?v=154899163682928891721788313528" rel="stylesheet" type="text/css" media="all" />)
    expect(RenderParity::Normalizer.new(host: "t12-shop.lvh.me:3000").call(ours)).to eq(RenderParity::Normalizer.new(host: "hoko.vip").call(hoko))
    font_ours = %(url("//t12-shop.lvh.me:3000/cdn/fonts/jost/jost_n4.#{'a' * 40}.woff2"))
    font_hoko = %(url("//hoko.vip/cdn/fonts/jost/jost_n4.d47a1b6347ce4a4c9f437608011273009d91f2b7.woff2"))
    expect(RenderParity::Normalizer.new(host: "t12-shop.lvh.me:3000").call(font_ours)).to eq(RenderParity::Normalizer.new(host: "hoko.vip").call(font_hoko))
  end
end
