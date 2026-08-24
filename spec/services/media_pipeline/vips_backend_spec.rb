# frozen_string_literal: true

require "rails_helper"

# 第 26 包審查 C17：VipsBackend 原本零覆蓋。libvips 本機沒裝，**但錯誤分類是純邏輯**
# ——那正是審查 C0/C5 指出的關鍵防線，必須在 CI 有測。
RSpec.describe MediaPipeline::VipsBackend do
  describe "錯誤分類（白名單制；未知一律當環境錯）" do
    def fault?(message)
      described_class.send(:file_fault?, StandardError.new(message))
    end

    it "🔴 檔案內容問題 ⇒ 判 file fault（走 failed 終態）" do
      [
        "VipsJpeg: Premature end of JPEG file",
        "vipsload: corrupt file detected",
        "pngload: invalid IHDR chunk",
        "VipsForeignLoad: not a known file format",
        "gifload: insufficient data in stream",
        "webpload: truncated data"
      ].each { |message| expect(fault?(message)).to be(true), message }
    end

    it "🔴 環境問題 ⇒ **不**判 file fault（上拋走重試）——把 OOM 當壞檔會永久燒掉使用者的圖" do
      [
        "vips_tracked_malloc: out of memory",
        "vips_tracked_open: unable to open file, Too many open files",
        "VipsForeignSave: no such operation webpsave_buffer",
        "vips_colourspace: no known route from 'cmyk' to 'srgb'",
        "some entirely unknown libvips failure"
      ].each { |message| expect(fault?(message)).to be(false), message }
    end
  end

  describe ".reset_availability!" do
    it "🔴 方法真的存在（審查 C15：`def m = expr if cond` 會讓方法根本沒被定義）" do
      expect(described_class).to respond_to(:reset_availability!)
      described_class.available? # 先 memoize
      expect { described_class.reset_availability! }.not_to raise_error
      expect { described_class.reset_availability! }.not_to raise_error # 未 memoize 時也安全
    end
  end

  describe "libvips 不在時" do
    it "open 拋 BackendUnavailable（不是 NameError、不是 failed）" do
      allow(described_class).to receive(:available?).and_return(false)
      expect { described_class.open("x") }.to raise_error(described_class::BackendUnavailable)
    end
  end
end
