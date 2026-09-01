# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-22：external_video media 進 Liquid（影片鏈第②步a）。
# 資料面＝D48 既有（media_type=external_video＋external_host/external_id）；
# 本包補 drop 面＋product.media 合流。官方 media 物件依 media_type 分派
# （shopify.dev objects/media；external_video_url/tag 收 host/external_id
# ＝PR-16 duck-type）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   EV1 media 合流依 position（殺：media=images ⇒ 影片在 gallery 靜默消失）
#   EV2 全鏈到 iframe（殺：drop 面缺 host/external_id ⇒ PR-16 filter 收不到）
RSpec.describe "ThemeEngine external video media（PR-22）" do
  let(:shop) { create(:shop) }
  let(:filter_harness) do
    h = Class.new { include ThemeEngine::Filters }.new
    h.instance_variable_set(:@context, Struct.new(:registers).new({}))
    h
  end

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  def build_product_with_media
    product = create(:product, shop:, status: "active", handle: "ev-tee", title: "EV Tee")
    create(:product_variant, shop:, product:, price_cents: 1000)
    key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
    Storage::LocalDisk.write(key, StringIO.new("x"))
    file = StoredFile.create!(shop_id: shop.id, filename: "ev.png", content_type: "image/png",
                              byte_size: 1, checksum: SecureRandom.hex(32), storage_key: key,
                              status: "ready", width: 10, height: 10)
    Media.create!(shop_id: shop.id, product_id: product.id, file_id: file.id,
                  media_type: "image", position: 2, source_url: "/x", status: "ready")
    Media.create!(shop_id: shop.id, product_id: product.id, media_type: "external_video",
                  external_host: "youtube", external_id: "vj01PAffOac",
                  position: 1, source_url: "https://youtu.be/vj01PAffOac", status: "ready")
    Product.where(id: product.id).includes(media: :stored_file).first
  end

  it "EV1 🔴 product.media 合流：影片＋圖片依 position 排序；images 仍只出圖片" do
    drop = ThemeEngine::ProductDrop.new(build_product_with_media)
    expect(drop.media.map(&:media_type)).to eq(%w[external_video image]) # position 1,2
    expect(drop.media_count).to eq(2)
    expect(drop.images.map(&:media_type)).to eq(%w[image]) # 官方 images＝圖片子集
    expect(drop.featured_image.media_type).to eq("image")  # featured 仍走圖片面

    video = drop.media.first
    expect([ video.host, video.external_id ]).to eq(%w[youtube vj01PAffOac])
    expect(video.preview_image).to be_nil # 無縮圖資料面（主題 default 寬容）
  end

  it "EV2 🔴 全鏈：media drop → external_video_url → iframe（PR-16 duck-type 接上）" do
    drop = ThemeEngine::ProductDrop.new(build_product_with_media)
    video = drop.media.first
    url = filter_harness.external_video_url(video, { "autoplay" => 1 })
    expect(url).to eq("https://www.youtube.com/embed/vj01PAffOac?autoplay=1") # 官方 embed 形
    tag = filter_harness.external_video_tag(url)
    expect(tag).to include(%(src="https://www.youtube.com/embed/vj01PAffOac?autoplay=1"))
    expect(tag).to include("allowfullscreen")
  end
end
