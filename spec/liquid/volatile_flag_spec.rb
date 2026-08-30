# frozen_string_literal: true

require "rails_helper"

# volatile 旗標鏈（63 §D.5）：drop 讀庫存 ⇒ registers 旗標 ⇒ Result#volatile? ⇒ 頁快取 TTL。
# 前兩節在此釘住；第三節＝PageCache C2；末端整合＝storefront_pages S6 家族。
RSpec.describe "volatile render flag" do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  it "🔴 VariantDrop#inventory_quantity 渲染時往 registers[:render_flags] 註冊 :volatile" do
    variant = create(:product_variant, shop:, product: create(:product, shop:, status: "active"))
    flags = Set.new
    template = Liquid::Template.parse("{{ v.inventory_quantity }}")
    template.render!({ "v" => ThemeEngine::VariantDrop.new(variant, nil) },
                     registers: { render_flags: flags })
    expect(flags).to include(:volatile)
  end

  it "沒讀揮發欄位 ⇒ 不註冊（Result.volatile? 預設 false 的上游保證）" do
    variant = create(:product_variant, shop:, product: create(:product, shop:, status: "active"))
    flags = Set.new
    Liquid::Template.parse("{{ v.price }}")
                    .render!({ "v" => ThemeEngine::VariantDrop.new(variant, nil) },
                             registers: { render_flags: flags })
    expect(flags).to be_empty
  end
end
