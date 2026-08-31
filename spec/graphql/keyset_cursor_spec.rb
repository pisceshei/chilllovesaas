# frozen_string_literal: true

require "rails_helper"

# 第 21 包：cursor 泛化（白名單制＋向後相容）。
RSpec.describe Products::KeysetCursor do
  let(:shop) { create(:shop, subdomain: "cursor-shop") }
  let(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) } }
  let(:product) { ActsAsTenant.without_tenant { variant.product } }

  it "🔴 向後相容：舊版（無 key 概念）編出的 products cursor 在新代碼可解" do
    legacy = Base64.urlsafe_encode64(
      JSON.generate([ product.created_at.utc.iso8601(6), product.id ]), padding: false)
    time, id = described_class.decode(legacy)
    expect(time.to_f).to be_within(0.000001).of(product.created_at.to_f)
    expect(id).to eq(product.id)
  end

  it "position 鍵編解 roundtrip（變體 connection 用）" do
    cursor = described_class.encode(variant, key: :position)
    pos, id = described_class.decode(cursor, key: :position)
    expect(pos).to eq(variant.position)
    expect(id).to eq(variant.id)
  end

  it "updated_at 鍵編解 roundtrip（G6-7 顧客列表預設序）" do
    cursor = described_class.encode(product, key: :updated_at)
    time, id = described_class.decode(cursor, key: :updated_at)
    expect(time.to_f).to be_within(0.000001).of(product.updated_at.to_f)
    expect(id).to eq(product.id)
  end

  it "白名單外的 key 拒絕（fail-closed）" do
    # 樣本鍵曾用 :updated_at——G6-7 把它登記進白名單後改用真正不在名單的鍵；
    # 斷言語義（未知鍵 KeyError）不變。
    expect { described_class.encode(product, key: :total_spent_cents) }.to raise_error(KeyError)
    expect { described_class.decode("whatever", key: :title) }.to raise_error(KeyError)
  end

  it "壞 cursor 回 BAD_USER_INPUT（既有語義不變）" do
    expect { described_class.decode("!!!", key: :position) }
      .to raise_error(GraphQL::ExecutionError)
  end
end
