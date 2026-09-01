# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-24：Liquid resource limits 校準的回歸格——**真 Ella 7.2.0**
# 商品頁（3 媒體含外部影片）整頁渲染。
#
# 事故（2026-09-02 生產實錘）：assign_score_limit=100,000 被真 Ella gallery
# 撞線（bt3 實測需求 100,138）⇒ 頁面帶「Liquid error: Memory limits exceeded」
# 且外部影片整塊消失。本格＝限額回歸＋PR-22 影片鏈的真主題端到端。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：把 limits 調回舊值本格必紅（EG1 斷言零 Liquid
#   error）；把 media 合流退化本格必紅（youtube embed 斷言）。
RSpec.describe "Ella product gallery（真主題 resource limits 回歸）" do
  let(:shop) { create(:shop) }
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      # name+version → Sources key "ella-7.2.0" → test/fixtures/themes/ella-7.2.0
      Theme.create!(shop_id: shop.id, name: "Ella", version: "7.2.0", role: "published",
                    source: "licensed", license_attested: true)
    end
  end

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  def build_product!
    product = create(:product, shop:, status: "active", handle: "eg-tee", title: "EG Tee")
    create(:product_variant, shop:, product:, price_cents: 18800)
    # 🔴 9 圖＋1 影片：gallery 的 per-media 陣列 concat/where 令 assign score
    # 隨媒體數平方成長——輕場景（2 圖）壓不破舊限（ML1 突變首輪不紅實錘），
    # 本場景在舊限 100,000 下必紅、在校準值下綠。
    9.times do |i|
      key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
      Storage::LocalDisk.write(key, StringIO.new("x"))
      file = StoredFile.create!(shop_id: shop.id, filename: "eg#{i}.png",
                                content_type: "image/png", byte_size: 1,
                                checksum: SecureRandom.hex(32), storage_key: key,
                                status: "ready", width: 800, height: 533)
      Media.create!(shop_id: shop.id, product_id: product.id, file_id: file.id,
                    media_type: "image", position: i + 1, source_url: "/x", status: "ready")
    end
    Media.create!(shop_id: shop.id, product_id: product.id, media_type: "external_video",
                  external_host: "youtube", external_id: "vj01PAffOac",
                  position: 10, source_url: "https://youtu.be/vj01PAffOac", status: "ready")
    product
  end

  it "EG1 🔴 真 Ella 商品頁：零 Liquid error＋外部影片 embed 出現（限額回歸）" do
    build_product!
    result = ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!)
                                      .render("/products/eg-tee")
    expect(result.status).to eq(200)
    errors = result.html.scan(/Liquid error[^<]{0,60}/).uniq
    expect(errors).to eq([]), "真 Ella 渲染出現 Liquid error：#{errors.inspect}"
    expect(result.html).to include("youtube.com/embed/vj01PAffOac") # PR-22 鏈真主題端到端
  end
end
