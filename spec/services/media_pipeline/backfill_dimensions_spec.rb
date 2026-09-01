# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-14：圖片尺寸不變量（官方 image 物件 width/height 恆 number、
# 無 nil 態——shopify.dev objects/image 取證 2026-09-01）＋存量回填。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   ID1 驗證矩陣（殺：繞過管線直寫 ready 圖片列 ⇒ Ella if-image 守衛內除法
#       在我方獨有炸點——divided-by-0 軸④的 30 位點審計）
#   BF1 回填＋blob 缺失轉 failed（殺：回填 fail-open 留下 nil 尺寸列）
RSpec.describe MediaPipeline::BackfillDimensions do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # 替身後端（同 process_file_spec 分工：像素真值由 bt3 線上驗收）
  let(:backend) do
    Class.new do
      def self.open(_bytes) = Struct.new(:width, :height).new(640, 480)
    end
  end

  def make_row!(status:, width: nil, height: nil, blob: "B")
    key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
    Storage::LocalDisk.write(key, StringIO.new(blob)) if blob
    row = StoredFile.new(shop_id: shop.id, filename: "#{SecureRandom.hex(3)}.png",
                         content_type: "image/png", byte_size: 5,
                         checksum: SecureRandom.hex(32), storage_key: key,
                         status:, width:, height:)
    row.save!(validate: false) # 模擬不變量生效前的存量列
    row
  end

  it "ID1 🔴 驗證矩陣：ready 圖片缺尺寸 ⇒ invalid；有尺寸/中間態/非圖片 ⇒ valid" do
    invalid = StoredFile.new(shop_id: shop.id, filename: "x.png", content_type: "image/png",
                             byte_size: 5, checksum: "c", storage_key: "k1", status: "ready")
    expect(invalid).not_to be_valid
    expect(invalid.errors[:width]).to be_present

    invalid.width = 100
    invalid.height = 80
    expect(invalid).to be_valid

    uploaded = StoredFile.new(shop_id: shop.id, filename: "y.png", content_type: "image/png",
                              byte_size: 5, checksum: "c", storage_key: "k2", status: "uploaded")
    expect(uploaded).to be_valid # pipeline 中間態不受限

    pdf = StoredFile.new(shop_id: shop.id, filename: "z.pdf", content_type: "application/pdf",
                         byte_size: 5, checksum: "c", storage_key: "k3", status: "ready")
    expect(pdf).to be_valid # 非圖片不受限
  end

  it "BF1 🔴 回填：缺尺寸 ready 圖片列補實際尺寸；blob 缺失 ⇒ 轉 failed；冪等" do
    fixable = make_row!(status: "ready")
    broken  = make_row!(status: "ready", blob: nil) # 無 blob
    intact  = make_row!(status: "ready", width: 10, height: 10)

    result = described_class.call(backend: backend)
    expect(result.fixed).to eq(1)
    expect(result.failed).to eq(1)

    expect(fixable.reload).to have_attributes(width: 640, height: 480, status: "ready")
    expect(broken.reload.status).to eq("failed")
    expect(broken.processing_error).to be_present
    expect(intact.reload).to have_attributes(width: 10, height: 10)

    rerun = described_class.call(backend: backend)
    expect([ rerun.fixed, rerun.failed ]).to eq([ 0, 0 ]) # 冪等：補完即出集合
  end
end
