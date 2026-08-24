# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# `LocalDisk.delete_with_empty_parents` 的正反面（第 28 包後修）。
#
# 🔴 本組存在的理由是一個**線上實測發現、測試看不到**的洩漏：`delete` 用 `rm_f`，
#   只拿掉檔案、留下目錄。衍生 key 是
#   `shops/{id}/derivatives/{file_id}/{checksum}/{variant}.webp`——每個檔案自己一棵樹，
#   刪一個檔就永久留下兩層空目錄。2026-08-25 於 bt3 量到 14 個檔案對應 31 個
#   `derivatives/{file_id}` 目錄、17 個空的，差額正好是該輪刪掉的檔數。
#   單元測試看不到是因為每個 example 各自建檔各自清，累積要跨很多次刪除才顯形。
RSpec.describe Storage::LocalDisk do
  let(:tmp_root) { Pathname.new(Dir.mktmpdir("local-disk")) }

  before { allow(described_class).to receive(:root).and_return(tmp_root) }

  after { FileUtils.rm_rf(tmp_root) }

  def write!(key, body = "BYTES")
    described_class.write(key, StringIO.new(body))
  end

  it "🔴 刪衍生檔會把變空的 file_id 與 checksum 兩層一起收掉" do
    key = "shops/1/derivatives/7/abc123/thumb.webp"
    write!(key)
    expect(tmp_root.join("shops/1/derivatives/7/abc123")).to be_directory

    described_class.delete_with_empty_parents(key)

    expect(described_class.exist?(key)).to be(false)
    expect(tmp_root.join("shops/1/derivatives/7/abc123")).not_to exist
    expect(tmp_root.join("shops/1/derivatives/7")).not_to exist
  end

  it "🔴 只收空的——同層還有別的衍生尺寸時，目錄必須留著" do
    write!("shops/1/derivatives/7/abc123/thumb.webp")
    write!("shops/1/derivatives/7/abc123/card.webp")

    described_class.delete_with_empty_parents("shops/1/derivatives/7/abc123/thumb.webp")

    expect(tmp_root.join("shops/1/derivatives/7/abc123")).to be_directory
    expect(described_class.exist?("shops/1/derivatives/7/abc123/card.webp")).to be(true)
  end

  it "🔴 不得往上收進共用層：`shops/{id}/files/` 還有別的 blob 就得留著" do
    write!("shops/1/files/a.png")
    write!("shops/1/files/b.png")

    described_class.delete_with_empty_parents("shops/1/files/a.png")

    expect(tmp_root.join("shops/1/files")).to be_directory
    expect(described_class.exist?("shops/1/files/b.png")).to be(true)
  end

  it "🔴 收到 root 就停，絕不刪 root（刪光整店最後一個檔的極端情形）" do
    write!("shops/1/files/only.png")

    described_class.delete_with_empty_parents("shops/1/files/only.png")

    # 空的中間層可以收，但 root 本身必須還在
    expect(tmp_root).to be_directory
  end

  it "檔案不存在時不是錯誤（補償刪除可能重入）" do
    expect { described_class.delete_with_empty_parents("shops/1/derivatives/9/x/thumb.webp") }
      .not_to raise_error
  end

  it "🔴 反向：舊的 `delete` 保持原行為（留下目錄）——兩支語義不得混淆" do
    key = "shops/1/derivatives/8/def456/thumb.webp"
    write!(key)

    described_class.delete(key)

    expect(described_class.exist?(key)).to be(false)
    expect(tmp_root.join("shops/1/derivatives/8/def456")).to be_directory
  end
end
