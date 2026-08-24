# frozen_string_literal: true

require "rails_helper"

# 第 25 包 staged 簽名（B6 presigned POST 的簽名層）。
RSpec.describe Storage::SignedUpload do
  let(:shop) { create(:shop, subdomain: "signed-up-shop") }

  it "issue→verify! 往返；參數齊全（key/expires_at/content_length_max/signature）" do
    target = described_class.issue(shop:, filename: "貓咪 photo.png", byte_size: 1024)
    expect(target.url).to eq("/admin/uploads/staged")
    expect(target.key).to start_with("shops/#{shop.id}/staged/")
    expect(target.resource_url).to include("/admin/uploads/staged-blob/shops/#{shop.id}/staged/")
    params = target.parameters.to_h { |p| [ p[:name], p[:value] ] }
    expect(params.keys).to contain_exactly("key", "expires_at", "content_length_max", "signature")

    verified = described_class.verify!(
      key: params["key"], expires_at: params["expires_at"],
      content_length_max: params["content_length_max"], signature: params["signature"])
    expect(verified).to eq(key: target.key, content_length_max: 1024)
  end

  it "🔴 竄改任一欄（key／大小／逾期）都 InvalidSignature——「簽小傳大」在簽名層擋" do
    target = described_class.issue(shop:, filename: "a.png", byte_size: 1024)
    params = target.parameters.to_h { |p| [ p[:name], p[:value] ] }

    expect {
      described_class.verify!(key: params["key"], expires_at: params["expires_at"],
        content_length_max: "999999999", signature: params["signature"])
    }.to raise_error(described_class::InvalidSignature)

    expect {
      described_class.verify!(key: params["key"] + "x", expires_at: params["expires_at"],
        content_length_max: params["content_length_max"], signature: params["signature"])
    }.to raise_error(described_class::InvalidSignature)

    travel_to(Time.current + Limits.fetch(:media, :staged_upload_ttl_seconds) + 61) do
      expect {
        described_class.verify!(key: params["key"], expires_at: params["expires_at"],
          content_length_max: params["content_length_max"], signature: params["signature"])
      }.to raise_error(described_class::InvalidSignature, /expired/)
    end
  end

  it "staged_key_from：本家 resourceUrl 還原 key；他店 key 與外部 URL 回 nil" do
    target = described_class.issue(shop:, filename: "a.png", byte_size: 10)
    expect(described_class.staged_key_from(target.resource_url, shop:)).to eq(target.key)

    other = create(:shop, subdomain: "signed-up-other")
    expect(described_class.staged_key_from(target.resource_url, shop: other)).to be_nil
    expect(described_class.staged_key_from("https://evil.test/x.png", shop:)).to be_nil
  end
end
