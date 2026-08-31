# frozen_string_literal: true

require "rails_helper"

# G6-1b：capability 同步語義（首次全開／保留手動關閉／移除不可用）。
#
# 🔴 假綠殺手：S2 殺「每次同步都覆蓋 enabled」（商家手動關閉被鏡像洗掉）；
# S3 殺「不可用方式留在白名單」（F4.2 清單移除回退）。
RSpec.describe Psp::ProviderCapabilities do
  let!(:shop) { create(:shop) }
  let(:record) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentProvider.create!(provider: "airwallex", client_id: "cid", api_secret: "key")
    end
  end

  def stub_fetch(names)
    allow(Psp::Airwallex::PaymentMethodTypes).to receive(:fetch).and_return(names)
  end

  it "S1 🔴 首次成功同步＝自動啟用（字典 ∩ 帳號可用）＋快取原樣 names" do
    stub_fetch(%w[alipayhk card fps octopus])
    ActsAsTenant.with_tenant(shop) { described_class.sync!(record) }

    expect(record.available_methods).to eq(%w[alipayhk card fps octopus])
    # octopus 不在 v1 字典 ⇒ 不進 enabled；字典內三個自動開
    expect(record.enabled_methods).to match_array(%w[card alipayhk fps])
    expect(record.capabilities_synced_at).to be_present
  end

  it "S2 🔴 其後同步不覆蓋商家手動關閉" do
    stub_fetch(%w[alipayhk card fps])
    ActsAsTenant.with_tenant(shop) do
      described_class.sync!(record)
      record.update!(enabled_methods: %w[card]) # 商家手動關掉 alipayhk/fps
      described_class.sync!(record)
    end
    expect(record.enabled_methods).to eq(%w[card])
  end

  it "S3 🔴 已不可用的方式從 enabled 移除（PSP 收不了的不得留在白名單）" do
    stub_fetch(%w[alipayhk card fps])
    ActsAsTenant.with_tenant(shop) { described_class.sync!(record) }
    stub_fetch(%w[card]) # 帳號側 alipayhk/fps 被關
    ActsAsTenant.with_tenant(shop) { described_class.sync!(record) }

    expect(record.available_methods).to eq(%w[card])
    expect(record.enabled_methods).to eq(%w[card])
  end

  it "S4 非 airwallex ⇒ Unsupported（paypal 隨 G6-2）" do
    other = ActsAsTenant.with_tenant(shop) { ShopPaymentProvider.create!(provider: "paypal") }
    expect { described_class.sync!(other) }.to raise_error(described_class::Unsupported)
  end
end
