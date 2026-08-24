# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# 第 28 包：staged 孤兒清掃（25→26→27 三度順延後收口）。
#
# 🔴 這一組必須同時證明**會刪**與**不會誤刪**。只證明「腳本能跑」不算防線
#   （鐵律 20.2 第 5 類：fail-open／happy-path-only）——一個永遠刪 0 個的清掃
#   與一個把使用者正在上傳的檔案抽掉的清掃，都會讓「跑完沒報錯」看起來一樣。
RSpec.describe Storage::StagedPurge do
  let(:shop) { create(:shop, subdomain: "purge-shop") }

  # 🔴 **把 storage root 換成本例專用的暫存目錄**。用真的 `storage/chilllove` 會有兩個
  #   問題：①掃到的是全域狀態——本檔第一次寫出來時 `scanned` 實測是 1031，全部是
  #   歷次測試留下的 staged 目錄（這正好是本包要收的那筆帳，但拿它當斷言輸入
  #   就等於讓斷言依賴別人的殘留）②清掃會真的刪掉開發機上的檔案。
  # （`around` 裡不能 stub——rspec-mocks 的 double 生命週期只在 example 內，
  #   在 around 裡呼叫 `allow` 會直接報 "outside of the per-test lifecycle"。）
  let(:tmp_root) { Pathname.new(Dir.mktmpdir("staged-purge")) }

  before { allow(Storage::LocalDisk).to receive(:root).and_return(tmp_root) }

  after { FileUtils.rm_rf(tmp_root) }

  def staged_dir(name, age_seconds:)
    dir = Storage::LocalDisk.root.join("shops", shop.id.to_s, "staged", name)
    FileUtils.mkdir_p(dir)
    File.write(dir.join("upload.png"), "BYTES")
    # `File.utime` 收不了 TimeWithZone（TypeError），要先 `to_time`。
    stamp = (Time.current - age_seconds).to_time
    File.utime(stamp, stamp, dir)
    dir
  end

  it "刪掉過期窗以外的目錄，保留窗內的" do
    window = described_class.expiry_window
    old = staged_dir("expired", age_seconds: window + 60)
    fresh = staged_dir("fresh", age_seconds: 10)

    result = described_class.call

    expect(File.exist?(old)).to be(false)
    expect(File.exist?(fresh)).to be(true)
    expect(result.purged).to eq(1)
    expect(result.bytes_freed).to eq(5)
    expect(result.errors).to be_empty
  end

  it "🔴 過期窗＝ttl＋寬限，不是只有 ttl（fileCreate 可能正在讀那份 bytes）" do
    ttl = Limits.fetch(:media, :staged_upload_ttl_seconds)
    grace = Limits.fetch(:media, :staged_purge_grace_seconds)
    expect(described_class.expiry_window).to eq(ttl + grace)

    # 剛過 ttl、還在寬限內 ⇒ **不得**刪
    borderline = staged_dir("just-past-ttl", age_seconds: ttl + 5)
    described_class.call
    expect(File.exist?(borderline)).to be(true)
  end

  it "🔴 不碰永久區——`shops/{id}/files/` 底下的 blob 一個都不能少" do
    ActsAsTenant.with_tenant(shop) do
      key = "shops/#{shop.id}/files/keep-me.png"
      Storage::LocalDisk.write(key, StringIO.new("BYTES"))
      staged_dir("expired", age_seconds: described_class.expiry_window + 60)

      described_class.call

      expect(Storage::LocalDisk.exist?(key)).to be(true)
    end
  end

  it "🔴 單一目錄失敗不中斷整輪，且錯誤要進 errors（不得靜默吞）" do
    a = staged_dir("boom", age_seconds: described_class.expiry_window + 60)
    b = staged_dir("ok", age_seconds: described_class.expiry_window + 60)
    allow(FileUtils).to receive(:rm_rf).and_call_original
    allow(FileUtils).to receive(:rm_rf).with(a.to_s).and_raise(Errno::EACCES)

    result = described_class.call

    expect(result.errors.size).to eq(1)
    expect(result.errors.sole).to include("boom")
    expect(File.exist?(b)).to be(false)   # 另一個照刪
    expect(result.purged).to eq(1)
  end

  it "沒有 staged 目錄時是零掃描的乾淨結果（不是例外）" do
    result = described_class.call
    expect(result.scanned).to eq(0)
    expect(result.purged).to eq(0)
  end
end
