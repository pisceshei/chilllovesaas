# frozen_string_literal: true

require "rails_helper"

# 第 26 包：處理管線的狀態機與失敗語義。
#
# 🔴 **後端替身而非 skip**：libvips 只有 bt3 有（本機 Windows／CI 皆無，
#    Gemfile:34-42 已記載）。用替身把**狀態機、衍生命名、DB 寫入、失敗分類**
#    全部測到；「像素真的縮了」由線上驗收（bt3 有 vips）負責——分工寫在 worklog。
RSpec.describe MediaPipeline::ProcessFile do
  let(:shop) { create(:shop, subdomain: "mp-shop") }

  # 替身後端：記錄呼叫、可注入失敗
  def backend_double(behaviour: :ok, probe: [ 800, 600 ])
    double = Object.new
    double.instance_variable_set(:@behaviour, behaviour)
    double.instance_variable_set(:@probe, probe)
    double.instance_variable_set(:@calls, [])
    def double.calls = @calls
    def double.probe(_bytes)
      case @behaviour
      when :decode_failed then raise MediaPipeline::VipsBackend::DecodeFailed, "bad header"
      when :too_many_pixels then raise MediaPipeline::VipsBackend::TooManyPixels, "too big"
      when :unavailable then raise MediaPipeline::VipsBackend::BackendUnavailable, "no libvips"
      end
      MediaPipeline::VipsBackend::Probe.new(width: @probe[0], height: @probe[1])
    end
    def double.derive(_bytes, spec)
      @calls << spec
      raise MediaPipeline::VipsBackend::DecodeFailed, "mid-way" if @behaviour == :derive_fails

      [ "WEBP#{spec[:width]}", spec[:width], spec[:height] ]
    end
    double
  end

  def make_file!(status: "uploaded")
    ActsAsTenant.with_tenant(shop) do
      key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
      Storage::LocalDisk.write(key, StringIO.new("ORIGINALBYTES"))
      StoredFile.create!(filename: "a.png", content_type: "image/png", byte_size: 13,
                         checksum: "x" * 64, storage_key: key, status:)
    end
  end

  # 🔴 backend 注入必須在**例內**做（`around` 在 example block 執行前跑，
  #    那時 @backend 還沒設 ⇒ 會落回真 VipsBackend，本機直接 BackendUnavailable）。
  def install!(**options)
    @backend = backend_double(**options)
    described_class.backend = @backend
    @backend
  end

  after { described_class.reset_backend! }

  it "🔴 成功路徑：uploaded→ready，四個衍生齊全、key 依 file.id＋variant 決定、原圖尺寸落庫" do
    install!
    file = make_file!
    result = ActsAsTenant.with_tenant(shop) { described_class.call(file) }

    expect(result.status).to eq("ready")
    file.reload
    expect(file.status).to eq("ready")
    expect(file.width).to eq(800)
    expect(file.height).to eq(600)
    expect(file.derivatives.keys).to match_array(%w[thumb card detail og])
    # key 帶內容 checksum 前綴（審查 C6：replace 兩輪在飛時不互相覆蓋）
    expect(file.derivatives["thumb"]["key"])
      .to eq("shops/#{shop.id}/derivatives/#{file.id}/#{file.checksum.first(12)}/thumb.webp")
    expect(file.derivatives["og"]).to include("width" => 1200, "height" => 630)
    # blob 真的落磁碟
    MediaPipeline::Derivatives.names.each do |variant|
      expect(Storage::LocalDisk.exist?(file.derivatives[variant]["key"])).to be(true)
    end
    # 四個 spec 都被要過（thumb/card/detail 是 fit、og 是 cover）
    expect(@backend.calls.map { |c| c[:mode] }).to eq(%i[fit fit fit cover])
  end

  it "🔴 檔案壞＝failed 終態不重試（不 raise），訊息落 processing_error" do
    install!(behaviour: :decode_failed)
    file = make_file!
    result = ActsAsTenant.with_tenant(shop) { described_class.call(file) }

    expect(result.status).to eq("failed")
    file.reload
    expect(file.status).to eq("failed")
    expect(file.processing_error).to include("bad header")
    expect(file.derivatives).to be_nil
  end

  it "🔴 超像素上限＝同樣 failed（防解壓炸彈，不是環境問題）" do
    install!(behaviour: :too_many_pixels)
    file = make_file!
    result = ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    expect(result.status).to eq("failed")
    expect(file.reload.processing_error).to include("too big")
  end

  it "🔴 環境缺件（libvips 沒裝）＝上拋讓 relay 退避重試；status 還原 uploaded、錯誤留 processing_error" do
    install!(behaviour: :unavailable)
    file = make_file!
    expect {
      ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    }.to raise_error(MediaPipeline::VipsBackend::BackendUnavailable)
    file.reload
    # 🔴 審查 C7：不得留在 processing——那是沒有出路的孤兒態（事件 dead 後沒人撿）
    expect(file.status).to eq("uploaded")
    expect(file.processing_error).to include("no libvips")
    expect(file.derivatives).to be_nil
  end

  it "🔴 審查 C8：derivatives JSON 說有但 blob 被刪 ⇒ 不視為完成，重跑補回" do
    install!
    file = make_file!
    ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    thumb_key = file.reload.derivatives["thumb"]["key"]
    Storage::LocalDisk.delete(thumb_key)
    calls_before = @backend.calls.length

    ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    expect(@backend.calls.length).to be > calls_before
    expect(Storage::LocalDisk.exist?(file.reload.derivatives["thumb"]["key"])).to be(true)
  end

  it "🔴 審查 C9：failed 分支清空 derivatives（舊的一組已作廢，不得留給讀取面）" do
    install!
    file = make_file!
    ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    expect(file.reload.derivatives).to be_present

    install!(behaviour: :decode_failed)
    ActsAsTenant.with_tenant(shop) do
      file.update!(status: "uploaded")
      described_class.call(file)
    end
    expect(file.reload.status).to eq("failed")
    expect(file.derivatives).to be_nil
  end

  it "🔴 審查 C6：處理期間內容被 replace 換掉 ⇒ 丟棄本輪結果、不覆蓋新值" do
    install!
    file = make_file!
    # 在 write_derivatives! 之後、寫回之前把 checksum 換掉（模擬另一輪 replace 已完成）
    allow(Storage::LocalDisk).to receive(:write).and_wrap_original do |m, key, io|
      result = m.call(key, io)
      ActsAsTenant.with_tenant(shop) do
        StoredFile.where(id: file.id).update_all(checksum: "z" * 64) if key.end_with?("og.webp")
      end
      result
    end
    result = ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    expect(result.status).not_to eq("ready")
    expect(file.reload.derivatives).to be_nil
  end

  it "衍生途中失敗：已寫的衍生 blob 補償刪除（不留孤兒），錯誤照樣是 failed" do
    install!(behaviour: :derive_fails)
    file = make_file!
    written = []
    allow(Storage::LocalDisk).to receive(:write).and_wrap_original do |m, key, io|
      written << key
      m.call(key, io)
    end
    result = ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    expect(result.status).to eq("failed")
    written.each { |key| expect(Storage::LocalDisk.exist?(key)).to be(false) }
  end

  it "冪等：已 ready 且四個衍生齊全 ⇒ 直接返回、後端零呼叫（at-least-once 重叫安全）" do
    install!
    file = make_file!
    ActsAsTenant.with_tenant(shop) { described_class.call(file) }
    calls_before = @backend.calls.length

    ActsAsTenant.with_tenant(shop) { described_class.call(file.reload) }
    expect(@backend.calls.length).to eq(calls_before)
  end
end
