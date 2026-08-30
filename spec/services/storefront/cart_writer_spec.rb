# frozen_string_literal: true

require "rails_helper"

# 購物車寫入矩陣（specs/15 F1；真店契約 83 §3.3／§12.5）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   W2 同鍵重加＝quantity 相加不加行（殺：拿掉 upsert 改裸 create——兩分頁併發丟量）
#   W3 同 variant 不同 properties＝兩行（殺：合併鍵退化成 variant_id——PR #52 第 4 輪事故）
#   W4 售罄 422 三鍵形（殺：錯誤形亂改；文案繁中）
#   W7 clear 清行不清 note/attributes（殺：整車 destroy 重建）
#   W8 顯示價＝即時、unit_price_cents＝快照（殺：把快照當顯示價——F1 #3）
RSpec.describe Storefront::CartWriter do
  let(:shop) { create(:shop) }
  let(:cart) { ActsAsTenant.with_tenant(shop) { Cart.create!(shop_id: shop.id, attributes_json: {}) } }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  def variant!(stock: 5, policy: "deny", price_cents: 10_000)
    variant = create(:product_variant, shop:, price_cents:,
                                       product: create(:product, shop:, status: "active"))
    variant.update!(inventory_policy: policy)
    level = variant.inventory_item.inventory_levels.order(:id).first
    level.update!(available: stock)
    variant
  end

  it "W1 加新行：回行、行帶合併鍵；cart json 頂層 14 鍵（83 §3.3 live 對照序）" do
    v = variant!
    line = described_class.add(cart:, variant_id: v.id, quantity: 2)
    expect(line.quantity).to eq(2)
    expect(line.merge_key_hash).to match(/\A\h{64}\z/)
    j = Storefront::CartSerializer.cart_json(cart.reload)
    expect(j.keys).to eq(%w[token note attributes original_total_price total_price total_discount
                            total_weight item_count items requires_shipping currency
                            items_subtotal_price cart_level_discount_applications discount_codes])
    expect(j["item_count"]).to eq(2)
    expect(j["total_price"]).to eq(20_000)
  end

  it "W2 🔴 同鍵重加 ⇒ 同一行 quantity 相加（upsert 撞唯一索引收斂，F1 #5）" do
    v = variant!
    described_class.add(cart:, variant_id: v.id, quantity: 2)
    described_class.add(cart:, variant_id: v.id, quantity: 3)
    expect(cart.cart_line_items.count).to eq(1)
    expect(cart.cart_line_items.sole.quantity).to eq(5)
  end

  it "W3 🔴 同 variant 不同 properties ⇒ 合法兩行（合併鍵含 properties）" do
    v = variant!
    described_class.add(cart:, variant_id: v.id, properties: { "刻字" => "甲" })
    described_class.add(cart:, variant_id: v.id, properties: { "刻字" => "乙" })
    expect(cart.cart_line_items.count).to eq(2)
  end

  it "W4 🔴 售罄（tracked＋0＋deny）⇒ CartError 422、body 三鍵形（真店 §12.5 逐字結構）" do
    v = variant!(stock: 0)
    expect { described_class.add(cart:, variant_id: v.id) }.to raise_error(Storefront::CartError) { |e|
      expect(e.status).to eq(422)
      body = e.as_json_body
      expect(body.keys).to eq(%w[status message description])
      expect(body["message"]).to include("已售罄")
      expect(body["message"]).to eq(body["description"])
    }
  end

  it "W5 缺貨續賣（continue）⇒ 0 庫存仍可加；查無變體 ⇒ 422" do
    v = variant!(stock: 0, policy: "continue")
    expect(described_class.add(cart:, variant_id: v.id).quantity).to eq(1)
    expect { described_class.add(cart:, variant_id: 999_999_999) }
      .to raise_error(Storefront::CartError) { |e| expect(e.status).to eq(422) }
  end

  it "W6 change：quantity=0 移除；單行上限（limits cart.max_quantity_per_line）擋" do
    v = variant!
    line = described_class.add(cart:, variant_id: v.id)
    described_class.change(cart:, line_key: line.id.to_s, quantity: 0)
    expect(cart.cart_line_items.count).to eq(0)
    line2 = described_class.add(cart:, variant_id: v.id)
    cap = Limits.fetch(:cart, :max_quantity_per_line)
    expect { described_class.change(cart:, line_key: line2.id.to_s, quantity: cap + 1) }
      .to raise_error(Storefront::CartError)
  end

  it "W7 🔴 clear 清行、保留 note／attributes（官方語義；83 §3.3 clear 實測同形）" do
    v = variant!
    described_class.add(cart:, variant_id: v.id)
    described_class.update_meta(cart:, note: "備註", attributes: { "gift" => "yes" })
    described_class.clear(cart: cart.reload)
    j = Storefront::CartSerializer.cart_json(cart.reload)
    expect(j["item_count"]).to eq(0)
    expect(j["note"]).to eq("備註")
    expect(j["attributes"]).to eq("gift" => "yes")
  end

  it "W8 🔴 顯示價＝即時 variant 價；unit_price_cents＝加入當下快照（F1 #3 雙層語義）" do
    v = variant!(price_cents: 10_000)
    line = described_class.add(cart:, variant_id: v.id)
    v.update!(price_cents: 12_000)
    item = Storefront::CartSerializer.item_json(line.reload)
    expect(item["price"]).to eq(12_000)          # 即時價
    expect(line.unit_price_cents).to eq(10_000)  # 快照（合併鍵承重）
    expect(item["key"]).to eq("#{v.id}:#{line.merge_key_hash}")
  end

  it "W9 行數上限（limits cart.max_lines）：新鍵超限擋、既有鍵仍可加量" do
    allow(Limits).to receive(:fetch).and_call_original
    allow(Limits).to receive(:fetch).with(:cart, :max_lines).and_return(1)
    v1 = variant!
    v2 = variant!
    described_class.add(cart:, variant_id: v1.id)
    expect { described_class.add(cart:, variant_id: v2.id) }.to raise_error(Storefront::CartError)
    expect(described_class.add(cart:, variant_id: v1.id).quantity).to eq(2)
  end
end
