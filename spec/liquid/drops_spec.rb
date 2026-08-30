# frozen_string_literal: true

require "rails_helper"

# 缺口分析落地包（docs/plans/2026-08-30-商品模塊-Liquid對接缺口分析.md 切分 1＋A2 選中佈線）。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤；每格點名它要殺的反向實作）：
#   V1 tracked＋0 庫存＋deny ⇒ available=false（殺：`available = true` 硬編碼回歸）
#   V2 同上但 policy=continue ⇒ true（殺：漏 continue 分支）
#   V3 兩地點 3+2 ⇒ inventory_quantity=5（殺：只讀單一地點）
#   V4 untracked ⇒ available=true ∧ inventory_management=nil（殺：無條件 "shopify"）
#   P2 S/M 售罄、L 有貨 ⇒ selected_or_first_available_variant=L（殺：恆 variants.first）
#   O1 value 級 available 投影（殺：values 退回純字串陣列）
#   O3 value == value 跨陣列、value == "S"（殺：拿掉 == 覆寫——Ella
#      product-variant-options.liquid:36-40 的 `color == value` 迴圈會全滅）
#   SP stub 釘死（殺：把 nil/[]/false stub「順手」改成半真值）
RSpec.describe "ThemeEngine drops（商品前台補完）" do
  let(:shop) { create(:shop) }

  # 生產形態鏡射：PageRenderer#render 以 with_tenant 包住整段渲染（drops 的
  # 一切關聯讀取都在租戶脈絡內）；spec 同形，否則 acts_as_tenant 擋關聯。
  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # 尺寸 S/M/L 三變體；S 有貨、M 售罄(deny)、L 售罄(continue)。
  def build_tshirt
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", handle: "drops-tee", title: "Drops Tee")
      option = create(:product_option, product:, shop:, name: "尺寸", position: 1)
      values = %w[S M L].each_with_index.map do |v, i|
        create(:option_value, product_option: option, shop:, value: v, position: i + 1)
      end
      variants = values.map.with_index do |ov, i|
        create(:product_variant, product:, shop:, title: ov.value, position: i + 1,
                                 price_cents: 10_000 + (i * 1000), option_values: [ ov ])
      end
      stock!(variants[0], 5)
      stock!(variants[1], 0)
      stock!(variants[2], 0)
      variants[2].update!(inventory_policy: "continue")
      [ product.reload, variants, values ]
    end
  end

  def stock!(variant, quantity)
    level = variant.inventory_item.inventory_levels.order(:id).first
    level.update!(available: quantity)
  end

  def drop_for(product, selected_variant_id: nil)
    ActsAsTenant.with_tenant(shop) do
      loaded = Product.where(shop_id: shop.id, id: product.id)
                      .includes(product_variants: [ :product_variant_option_values,
                                                    { inventory_item: :inventory_levels },
                                                    { media: :stored_file } ],
                                product_options: :option_values,
                                media: :stored_file).first
      ThemeEngine::ProductDrop.new(loaded, selected_variant_id: selected_variant_id)
    end
  end

  describe "VariantDrop 庫存感知（A1／A′1）" do
    it "V1 🔴 tracked＋0＋deny ⇒ available=false" do
      product, = build_tshirt
      m = drop_for(product).variants.find { |v| v.title == "M" }
      expect(m.available).to be(false)
      expect(m.inventory_quantity).to eq(0)
    end

    it "V2 tracked＋0＋continue ⇒ available=true（缺貨續賣）" do
      product, = build_tshirt
      l = drop_for(product).variants.find { |v| v.title == "L" }
      expect(l.available).to be(true)
    end

    it "V3 🔴 兩地點 3+2 ⇒ inventory_quantity=5（跨地點合計）" do
      product, variants, = build_tshirt
      ActsAsTenant.with_tenant(shop) do
        second = shop.locations.create!(name: "倉庫二")
        variants[0].inventory_item.inventory_levels.find_by!(location_id: second.id).update!(available: 2)
        variants[0].inventory_item.inventory_levels.order(:id).first.update!(available: 3)
      end
      s = drop_for(product).variants.find { |v| v.title == "S" }
      expect(s.inventory_quantity).to eq(5)
      expect(s.available).to be(true)
    end

    it "V4 🔴 untracked ⇒ available=true ∧ inventory_management=nil" do
      product, variants, = build_tshirt
      ActsAsTenant.with_tenant(shop) { variants[1].inventory_item.update!(tracked: false) }
      m = drop_for(product).variants.find { |v| v.title == "M" }
      expect(m.available).to be(true)
      expect(m.inventory_management).to be_nil
    end

    it "V5 tracked ⇒ inventory_management='shopify'（主題 JS 硬編碼比對的相容字串）＋ policy 透出" do
      product, = build_tshirt
      s = drop_for(product).variants.find { |v| v.title == "S" }
      expect(s.inventory_management).to eq("shopify")
      expect(s.inventory_policy).to eq("deny")
    end

    it "V6 url＝商品 URL＋?variant=；weight＝公克整數；barcode 透出" do
      product, variants, = build_tshirt
      ActsAsTenant.with_tenant(shop) { variants[0].update!(barcode: "4710000000001", weight_grams: 250) }
      s = drop_for(product).variants.find { |v| v.title == "S" }
      expect(s.url).to eq("/products/drops-tee?variant=#{variants[0].id}")
      expect(s.weight).to eq(250)
      expect(s.weight_unit).to eq("kg")
      expect(s.barcode).to eq("4710000000001")
    end
  end

  describe "ProductDrop 聚合與選中（A1／A2）" do
    it "P1 任一變體可購 ⇒ product.available=true；全售罄（deny）⇒ false" do
      product, variants, = build_tshirt
      expect(drop_for(product).available).to be(true)
      ActsAsTenant.with_tenant(shop) do
        stock!(variants[0], 0)
        variants[2].update!(inventory_policy: "deny")
      end
      expect(drop_for(product).available).to be(false)
    end

    it "P2 🔴 無選中 ⇒ selected_or_first_available_variant＝首個「可購」變體（S 售罄後＝L）" do
      product, variants, = build_tshirt
      ActsAsTenant.with_tenant(shop) { stock!(variants[0], 0) }
      d = drop_for(product)
      expect(d.selected_variant).to be_nil
      expect(d.selected_or_first_available_variant.title).to eq("L")
      expect(d.first_available_variant.title).to eq("L")
    end

    it "P3 selected_variant_id 佈線 ⇒ selected_variant／variant.selected 旗標" do
      product, variants, = build_tshirt
      d = drop_for(product, selected_variant_id: variants[1].id)
      expect(d.selected_variant.title).to eq("M")
      expect(d.selected_or_first_available_variant.title).to eq("M")
      expect(d.variants.find { |v| v.title == "M" }.selected).to be(true)
      expect(d.variants.find { |v| v.title == "S" }.selected).to be(false)
    end

    it "P4 compare_at_price_varies＝跨變體計算（兩個相異非 nil 值 ⇒ true；全 nil ⇒ false）" do
      # 🔴 nil 混值（部分變體無 compare_at）的本尊 varies 語義未取證——本格刻意
      #   只測無爭議端；混值格待 CLI 探針對表後補（缺口分析 §D 同軸）。
      product, variants, = build_tshirt
      base = drop_for(product)
      expect(base.compare_at_price_varies).to be(false)
      # 真引擎（83 §12）：全 nil 時 min/max ＝ 0（不是 nil）
      expect(base.compare_at_price_min).to eq(0)
      expect(base.compare_at_price_max).to eq(0)
      ActsAsTenant.with_tenant(shop) do
        variants[0].update!(compare_at_price_cents: 20_000)
        variants[1].update!(compare_at_price_cents: 30_000)
      end
      expect(drop_for(product).compare_at_price_varies).to be(true)
    end
  end

  describe "選項值 drop（A3）" do
    it "O1 🔴 value.available＝該值變體群的可購投影（S=true、M=false、L=true）" do
      product, = build_tshirt
      opt = drop_for(product).options_with_values.first
      availability = opt.values.to_h { |v| [ v.to_s, v.available ] }
      expect(availability).to eq("S" => true, "M" => false, "L" => true)
    end

    it "O2 to_s＝值字串（Ella `{{ value | handle }}` 相容）；name 同值" do
      product, = build_tshirt
      value = drop_for(product).options_with_values.first.values.first
      expect(value.to_s).to eq("S")
      expect(value.name).to eq("S")
      expect("#{value}").to eq("S")
    end

    it "O3 🔴 跨陣列 value == value（同 id）與 value == '字串' 都成立" do
      product, = build_tshirt
      d1 = drop_for(product).options_with_values.first.values.first
      d2 = drop_for(product).options_with_values.first.values.first
      expect(d1 == d2).to be(true)
      expect(d1 == "S").to be(true)
      expect(d1 == "M").to be(false)
    end

    it "O4 value.variant＝可購優先的代表變體；value.id／product_url（Ella dataset 消費形）" do
      product, variants, values = build_tshirt
      opt = drop_for(product).options_with_values.first
      m = opt.values.find { |v| v.to_s == "M" }
      expect(m.id).to eq(values[1].id)
      expect(m.variant.title).to eq("M") # 唯一命中者（售罄也回它——代表性不因售罄消失）
      expect(m.product_url).to eq("/products/drops-tee?variant=#{variants[1].id}")
    end

    it "O5 option.selected_value 跟隨選中變體；selected 投影到值" do
      product, variants, = build_tshirt
      opt = drop_for(product, selected_variant_id: variants[2].id).options_with_values.first
      expect(opt.selected_value).to eq("L")
      expect(opt.values.find { |v| v.to_s == "L" }.selected).to be(true)
    end
  end

  describe "stub 契約釘死（缺口分析 §B——改成半真值＝本組轉紅提醒補全套）" do
    it "SP1 變體側：unit_price／unit_price_measurement nil、quantity_rule 官方預設形、quantity_price_breaks []" do
      product, = build_tshirt
      v = drop_for(product).variants.first
      expect(v.unit_price).to be_nil
      expect(v.unit_price_measurement).to be_nil
      expect(v.quantity_rule).to eq("min" => 1, "max" => nil, "increment" => 1)
      expect(v.quantity_price_breaks).to eq([])
    end

    it "SP2 商品側：gift_card? false、requires_selling_plan false、selling_plan_groups []、category nil；值側 swatch nil" do
      product, = build_tshirt
      d = drop_for(product)
      expect(d.gift_card?).to be(false)
      expect(d.requires_selling_plan).to be(false)
      expect(d.selling_plan_groups).to eq([])
      expect(d.category).to be_nil
      expect(d.options_with_values.first.values.first.swatch).to be_nil
    end
  end
end
