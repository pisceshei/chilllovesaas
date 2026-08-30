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
#   C1 collections 管道過濾（殺：不濾 publication——真引擎 S9-Col-Hidden 排除格）
#   MF2/J1 json 黑名單（殺：把 root/單一 metafield 的拒絕「修好」成正常序列化）
#   J2 variant json 無 quantity_price_breaks（殺：直接 dump drop 全屬性）
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

    it "P4b 🔴 nil 混值（真引擎 2026-08-31 探針，83 §12.2）：nil 排除、不當 0 參與；varies 只比非 nil 集合" do
      # live 對照組（S9-CAP-Mix-Test 9918007967979）：A=15000、B=nil ⇒
      # 單數/min/max 全＝15000、varies=false。
      product, variants, = build_tshirt
      ActsAsTenant.with_tenant(shop) { variants[0].update!(compare_at_price_cents: 15_000) }
      d = drop_for(product)
      expect(d.compare_at_price).to eq(15_000)
      expect(d.compare_at_price_min).to eq(15_000)
      expect(d.compare_at_price_max).to eq(15_000)
      expect(d.compare_at_price_varies).to be(false)
    end

    it "P5 🔴 多變體全售罄（真引擎雙商品證據，83 §12.2）：sofav＝position 首位、first_available_variant＝nil" do
      product, variants, = build_tshirt
      ActsAsTenant.with_tenant(shop) do
        stock!(variants[0], 0)
        variants[2].update!(inventory_policy: "deny")
      end
      d = drop_for(product)
      expect(d.first_available_variant).to be_nil
      expect(d.selected_or_first_available_variant.title).to eq("S")
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

  describe "資料出口：collections（A′5）" do
    def with_collections(product)
      ActsAsTenant.with_tenant(shop) do
        online = Publication.online_store!
        shown = Collection.create!(shop_id: shop.id, title: "出口測試-顯", handle: "outlet-shown",
                                   description_html: "", collection_type: "manual", sort_order: "manual")
        hidden = Collection.create!(shop_id: shop.id, title: "出口測試-隱", handle: "outlet-hidden",
                                    description_html: "", collection_type: "manual", sort_order: "manual")
        [ shown, hidden ].each do |c|
          CollectionMembership.create!(shop_id: shop.id, collection_id: c.id, product_id: product.id,
                                       origin: "manual", position: 1)
        end
        # 隱藏組：拔掉 online store 的發布列（materialize 建的）
        ResourcePublication.where(shop_id: shop.id, publication_id: online.id,
                                  publishable_type: "Collection", publishable_id: hidden.id).delete_all
        [ online, shown, hidden ]
      end
    end

    it "C1 🔴 只回渲染管道上已發布的系列（S9-Col-Hidden 排除格的本地鏡射）" do
      product, = build_tshirt
      online, shown, = with_collections(product)
      d = ActsAsTenant.with_tenant(shop) do
        ThemeEngine::ProductDrop.new(Product.find(product.id), publication: online)
      end
      expect(d.collections.map(&:handle)).to eq([ "outlet-shown" ])
      expect(d.collections.first.id).to eq(shown.id)
    end

    it "C2 無管道語境 ⇒ 空陣列（安全側）；collection json＝真引擎 9 鍵序" do
      product, = build_tshirt
      online, = with_collections(product)
      expect(drop_for(product).collections).to eq([])
      d = ActsAsTenant.with_tenant(shop) do
        ThemeEngine::ProductDrop.new(Product.find(product.id), publication: online)
      end
      j = JSON.parse(ThemeEngine::JsonSerializer.dump(d.collections))
      expect(j.first.keys).to eq(%w[id handle updated_at published_at sort_order
                                    template_suffix published_scope title body_html])
      expect(j.first["published_at"]).to be_present # materialize 的已發布列
      expect(j.first["body_html"]).to be_nil        # 空 description ⇒ null
    end
  end

  describe "資料出口：metafields（A′6）" do
    def define_metafield!(product, namespace:, key:, value:, value_type: "single_line_text_field")
      ActsAsTenant.with_tenant(shop) do
        definition = MetafieldDefinition.create!(shop_id: shop.id, namespace:, key:,
                                                 name: key.humanize, owner_type: "Product",
                                                 value_type:, validations: [])
        Metafield.create!(shop_id: shop.id, metafield_definition: definition,
                          owner_type: "Product", owner_id: product.id, value: value)
      end
    end

    it "MF1 namespace.key 鏈：直接輸出＝值、.value＝值、.type＝定義型別；未知 key/namespace ⇒ nil 鏈安全" do
      product, = build_tshirt
      define_metafield!(product, namespace: "fecify", key: "product_id", value: "S9CAP-FEC-001", value_type: "id")
      mf = drop_for(product).metafields.liquid_method_missing("fecify").liquid_method_missing("product_id")
      expect(mf.to_s).to eq("S9CAP-FEC-001")
      expect(mf.value).to eq("S9CAP-FEC-001")
      expect(mf.type).to eq("id")
      ns = drop_for(product).metafields.liquid_method_missing("nope")
      expect(ns.liquid_method_missing("missing")).to be_nil
    end

    it "MF2 🔴 json 黑名單（真引擎 83 §12.4）：root 與單一 metafield 拒絕、namespace＝扁平 {key: value}" do
      product, = build_tshirt
      define_metafield!(product, namespace: "fecify", key: "product_id", value: "S9CAP-FEC-001")
      root = drop_for(product).metafields
      refusal = { "error" => "json not allowed for this object" }
      expect(JSON.parse(ThemeEngine::JsonSerializer.dump(root))).to eq(refusal)
      ns = root.liquid_method_missing("fecify")
      expect(JSON.parse(ThemeEngine::JsonSerializer.dump(ns))).to eq("product_id" => "S9CAP-FEC-001")
      one = ns.liquid_method_missing("product_id")
      expect(JSON.parse(ThemeEngine::JsonSerializer.dump(one))).to eq(refusal)
    end
  end

  describe "資料出口：category（A′7）" do
    it "CT1 category_gid 導出 gid/id；name＝nil（taxonomy 字典未落庫，登記）；無值 ⇒ nil" do
      product, = build_tshirt
      expect(drop_for(product).category).to be_nil
      ActsAsTenant.with_tenant(shop) do
        product.update!(category_gid: "gid://shopify/TaxonomyCategory/aa-1-13-8")
      end
      cat = drop_for(product).category
      expect(cat.id).to eq("aa-1-13-8")
      expect(cat.gid).to eq("gid://shopify/TaxonomyCategory/aa-1-13-8")
      expect(cat.name).to be_nil
    end
  end

  describe "json parity（真引擎 83 §12.2 形）" do
    it "J1 🔴 product | json：鍵序＝live .js 對照形（有 content 無 url；無 media 鍵；無圖 featured_image=null）" do
      product, = build_tshirt
      j = JSON.parse(ThemeEngine::JsonSerializer.dump(drop_for(product)))
      expect(j.keys).to eq(%w[id title handle description published_at created_at vendor type tags
                              price price_min price_max available price_varies compare_at_price
                              compare_at_price_min compare_at_price_max compare_at_price_varies
                              variants images featured_image options requires_selling_plan
                              selling_plan_groups content])
      expect(j).not_to have_key("url")
      expect(j).not_to have_key("status")
      expect(j["featured_image"]).to be_nil
      expect(j["price"]).to eq(10_000) # integer cents（鐵律 3 同尺度直通）
    end

    it "J2 🔴 variant json＝21 鍵、無 quantity_price_breaks；name/public_title 拼裝規則" do
      product, = build_tshirt
      j = JSON.parse(ThemeEngine::JsonSerializer.dump(drop_for(product)))
      v = j["variants"].first
      expect(v.keys).to eq(%w[id title option1 option2 option3 sku requires_shipping taxable
                              featured_image available name public_title options price weight
                              compare_at_price inventory_management barcode requires_selling_plan
                              selling_plan_allocations quantity_rule])
      expect(v).not_to have_key("quantity_price_breaks")
      expect(v["name"]).to eq("Drops Tee - S")
      expect(v["public_title"]).to eq("S")
    end

    it "J3 options_with_values | json＝{name, position, values:[字串]}（值壓平）" do
      product, = build_tshirt
      j = JSON.parse(ThemeEngine::JsonSerializer.dump(drop_for(product).options_with_values))
      expect(j).to eq([ { "name" => "尺寸", "position" => 1, "values" => %w[S M L] } ])
    end

    it "J5 🔴 濾鏡 wiring：`{{ p | json }}` 經 Liquid 渲染真的走 JsonSerializer（殺：濾鏡退回裸 JSON.generate）" do
      product, = build_tshirt
      out = Liquid::Template.parse("{{ p | json }}")
                            .render({ "p" => drop_for(product) }, filters: [ ThemeEngine::Filters ])
      expect(JSON.parse(out)["handle"]).to eq("drops-tee")
    end

    it "J4 兜底：未知 drop ⇒ to_s（gem 無 json 濾鏡，序列化全歸我方）" do
      expect(ThemeEngine::JsonSerializer.dump("x")).to eq('"x"')
      expect(ThemeEngine::JsonSerializer.dump([ 1, nil, true ])).to eq("[1,null,true]")
    end
  end
end
