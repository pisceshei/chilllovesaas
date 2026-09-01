# frozen_string_literal: true

require "rails_helper"

# G6 步 9a：Engine 解析半場（17-F2 候選/條件/組合；不算錢——錢在 Calculator）。
#
# 🔴 假綠殺手：
#   E2 統一錯誤文案（殺：區分不存在/過期——枚舉爬碼者拿到訊號，17-F4.1）
#   E4 雙向同意（殺：單向旗標就共存——H-41/H-42 家族）
#   E5 shipping 疊 shipping 硬擋（殺：旗標全開就放行）
RSpec.describe Discounts::Engine do
  let(:shop) { create(:shop, subdomain: "deng") }
  let(:lines) { [ { key: "a", quantity: 2, unit_price_cents: 30_000, variant_id: 1 } ] }

  def build_discount(**attrs)
    defaults = { shop_id: shop.id, title: "折", discount_class: "order", method: "code",
                 code: "SAVE10", value_type: "percentage", percentage_basis_points: 1000,
                 status: "active" }
    ActsAsTenant.with_tenant(shop) { Discount.create!(defaults.merge(attrs)) }
  end

  def evaluate(code: nil, customer_key: nil)
    ActsAsTenant.with_tenant(shop) do
      described_class.evaluate(shop:, lines:, code:, customer_key:)
    end
  end

  it "E1 code 正規化：「 save10 」命中 SAVE10（upcase+trim；17-F1.2）" do
    build_discount
    evaluation = evaluate(code: "  save10  ")
    expect(evaluation.code_error).to be_nil
    expect(evaluation.discounts.map { |d| d[:title] }).to eq([ "折" ])
  end

  it "🔴 E2 不存在／過期／已停用 ⇒ 同一句「折扣碼無效或不適用」（枚舉防護）" do
    build_discount(code: "EXPIRED", ends_at: 1.day.ago)
    build_discount(code: "DRAFTED", status: "draft")

    [ "NOSUCH", "EXPIRED", "DRAFTED" ].each do |code|
      evaluation = evaluate(code:)
      expect(evaluation.code_error).to eq("折扣碼無效或不適用"),
        "#{code} 的錯誤訊息洩漏了存在性＝爬碼訊號"
    end
  end

  it "E3 automatic 只取 effective active（scheduled/expired 排除；狀態推導不落庫）" do
    build_discount(method: "automatic", code: nil, title: "現行")
    build_discount(method: "automatic", code: nil, title: "未來", starts_at: 2.days.from_now)
    build_discount(method: "automatic", code: nil, title: "過去", ends_at: 2.days.ago)

    evaluation = evaluate
    expect(evaluation.discounts.map { |d| d[:title] }).to eq([ "現行" ])
  end

  it "🔴 E4 組合＝雙向同意：單向開旗標不共存；不可共存取買家利益最大" do
    big = build_discount(method: "automatic", code: nil, title: "大", percentage_basis_points: 2000,
                         combines_order: true) # 願意與 order 共存
    build_discount(method: "automatic", code: nil, title: "小", percentage_basis_points: 500,
                   combines_order: false) # 不願意

    evaluation = evaluate
    expect(evaluation.discounts.map { |d| d[:title] }).to eq([ "大" ]),
      "單向同意就共存＝H-41 家族；衝突時應取折讓大者"

    # 雙向都開 ⇒ 共存
    ActsAsTenant.with_tenant(shop) do
      Discount.where(shop_id: shop.id).update_all(combines_order: true)
    end
    evaluation2 = evaluate
    expect(evaluation2.discounts.size).to eq(2)
  end

  it "🔴 E5 兩張 shipping ⇒ 只取一張（硬規則不看旗標——用 update_all 繞過 model 驗證
      塞 combines_shipping=true，模擬旗標層失守後引擎仍要擋）" do
    build_discount(method: "automatic", code: nil, title: "免運A", discount_class: "shipping",
                   percentage_basis_points: 10_000, combines_product: true, combines_order: true)
    build_discount(method: "automatic", code: nil, title: "免運B", discount_class: "shipping",
                   percentage_basis_points: 5000, combines_product: true, combines_order: true)
    # 17-F1.4 的 model 驗證讓 shipping 類永遠 combines_shipping=false ⇒ 旗標路徑
    # 已天然擋疊。硬規則是縱深防禦——把旗標打穿才能單測它（refunds M3 同法）。
    ActsAsTenant.without_tenant do
      Discount.where(shop_id: shop.id, discount_class: "shipping")
              .update_all(combines_shipping: true)
    end

    evaluation = evaluate
    shipping = evaluation.discounts.select { |d| d[:discount_class] == "shipping" }
    expect(shipping.size).to eq(1)
    expect(shipping.first[:title]).to eq("免運A") # best wins
  end

  it "E6 條件：min_subtotal_cents／min_quantity 未達 ⇒ code 回統一錯誤" do
    build_discount(conditions: { "min_subtotal_cents" => 100_000 }) # 小計 60000 未達
    expect(evaluate(code: "SAVE10").code_error).to eq("折扣碼無效或不適用")

    build_discount(code: "QTY5", conditions: { "min_quantity" => 5 }) # 量 2 未達
    expect(evaluate(code: "QTY5").code_error).to eq("折扣碼無效或不適用")
  end

  it "E7 用量軟檢：times_used 達 usage_limit ⇒ code 不可用" do
    build_discount(usage_limit: 3, times_used: 3)
    expect(evaluate(code: "SAVE10").code_error).to eq("折扣碼無效或不適用")
  end

  it "shipping 類不得開 combines_shipping（17-F1.4 model 驗證）" do
    expect do
      build_discount(discount_class: "shipping", combines_shipping: true)
    end.to raise_error(ActiveRecord::RecordInvalid, /shippingDiscounts/)
  end
end
