# frozen_string_literal: true

require "rails_helper"

# G6-3 前半：PSP provider 憑證層（37 §6.3）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   「密文落庫」格殺「encrypts 被拔掉仍全綠」——明文比對測不出加密存在與否；
#   「指紋算在明文」格殺「對密文取指紋」（non-deterministic 密文每次不同）。
RSpec.describe ShopPaymentProvider do
  let!(:shop) { create(:shop) }

  def build_provider(**attrs)
    ActsAsTenant.with_tenant(shop) do
      described_class.new(provider: "airwallex", **attrs)
    end
  end

  it "🔴 祕密欄落庫是密文不是明文（37 §6.3 最低標＝AR encryption）" do
    record = build_provider(api_secret: "sk_live_secret")
    ActsAsTenant.with_tenant(shop) { record.save! }
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT api_secret FROM shop_payment_providers WHERE id = #{record.id}"
    )
    expect(raw).not_to include("sk_live_secret")
    expect(record.reload.api_secret).to eq("sk_live_secret") # 解密往返
  end

  it "指紋＝SHA-256 前 16 hex，算在明文上；清空祕密 ⇒ 指紋同步清空" do
    record = build_provider(api_secret: "sk_test_abc123")
    ActsAsTenant.with_tenant(shop) { record.save! }
    expect(record.api_secret_fingerprint)
      .to eq(Digest::SHA256.hexdigest("sk_test_abc123").first(16))

    ActsAsTenant.with_tenant(shop) { record.update!(api_secret: nil) }
    expect(record.api_secret_fingerprint).to be_nil
  end

  it "provider 字典＝psp_packs 的鍵（平台層）；域外值被擋" do
    expect(described_class.provider_dictionary).to include("airwallex", "paypal")
    record = build_provider
    record.provider = "stripe" # pack 未落鍵 ⇒ 不在字典
    expect(record).not_to be_valid
    expect(record.errors[:provider].first).to include("pack 字典")
  end

  it "environment ∈ sandbox|production；預設 sandbox" do
    record = build_provider
    expect(record.environment).to eq("sandbox")
    record.environment = "demo"
    expect(record).not_to be_valid
  end

  it "每店每 provider 一列（uniqueness scope shop_id）" do
    ActsAsTenant.with_tenant(shop) do
      described_class.create!(provider: "airwallex")
      dup = described_class.new(provider: "airwallex")
      expect(dup).not_to be_valid
    end
  end

  it "enabled_methods：新實例預設 []（json 表達式預設不進未存檔實例——實測坑）；非字串陣列被擋" do
    record = build_provider
    expect(record.enabled_methods).to eq([])
    record.enabled_methods = [ "card", 123 ]
    expect(record).not_to be_valid
  end
end
