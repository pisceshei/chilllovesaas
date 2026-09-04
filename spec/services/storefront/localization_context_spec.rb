# frozen_string_literal: true

require "rails_helper"

# E15：`localization.available_countries`／`localization.country`（官方 objects/localization・objects/country，external-facts §G22）。
# 本尊實測基準＝hoko.vip 五市場 header 區段（Section Rendering，2026-09-04）：31 國、zh-CN 順序 丹麦／保加利亚／克罗地亚／匈牙利／
# 卢森堡…、在地名 台湾／美国／香港特别行政区／日本／法国、每列 `($HKD)`、當前國 TW、無 popular 清單。
# 🔴 假綠殺手：LC1 集合必須是「全部 active 市場 regions 聯集」而非只有主市場（只給主市場 ⇒ Ella 頁首走「僅語言」分支，初始
#   HTML 與本尊不同）；順序必須是字典觀察序（用 ISO 碼序 ⇒ 轉紅）；LC3 draft 市場不得列入；LC4 單市場店恆 1 國。
RSpec.describe Storefront::LocalizationContext do
  let(:spec) { JSON.parse(File.read(Rails.root.join("spec/fixtures/render_parity/hoko.json"), encoding: "UTF-8")) }

  def primary_presence(shop)
    ActsAsTenant.with_tenant(shop) { Market.find_by!(is_primary: true).market_web_presences.order(:id).first }
  end

  def drop_for(shop, locale_tag)
    ActsAsTenant.with_tenant(shop) { described_class.drop(web_presence: primary_presence(shop), locale_tag:) }
  end

  it "LC1 🔴 五市場 ⇒ 31 國聯集、zh-CN 在地名與觀察序、店幣別 ($HKD)、當前國 TW、popular? 恆 false" do
    shop = RenderParity::Mirror.call(subdomain: "lc-spec", spec: spec).shop
    drop = drop_for(shop, "zh-Hans")
    countries = drop.invoke_drop("available_countries")
    expect(countries.size).to eq(31)
    expect(countries.first(5).map { |c| [ c["iso_code"], c["name"] ] })
      .to eq([ %w[DK 丹麦], %w[BG 保加利亚], %w[HR 克罗地亚], %w[HU 匈牙利], %w[LU 卢森堡] ]) # hoko header SRA 2026-09-04 前五
    by_code = countries.index_by { |c| c["iso_code"] }
    expect(by_code.slice("TW", "US", "HK", "JP", "FR").transform_values { |c| c["name"] })
      .to eq("TW" => "台湾", "US" => "美国", "HK" => "香港特别行政区", "JP" => "日本", "FR" => "法国")
    expect(countries.map { |c| [ c["currency"]["symbol"], c["currency"]["iso_code"] ] }.uniq).to eq([ [ "$", "HKD" ] ]) # `($HKD)`
    expect(countries.map { |c| c["popular?"] }.uniq).to eq([ false ])
    expect(by_code["HK"]["market"]["handle"]).to eq("hk")
    expect(by_code["FR"]["market"]["handle"]).to eq("eu")
    expect(by_code["FR"]["available_languages"].map { |l| l["iso_code"] }).to eq(%w[zh-CN zh-TW en fr ja])
    current = drop.invoke_drop("country")
    expect(current.slice("iso_code", "name")).to eq("iso_code" => "TW", "name" => "台湾")
    expect(current["currency"]["iso_code"]).to eq("HKD")
    expect(drop.invoke_drop("market")).to eq("handle" => "tw", "id" => ActsAsTenant.with_tenant(shop) { Market.find_by!(is_primary: true).id })
  end

  it "LC2 語言切到 en ⇒ 在地名與順序跟語言走（本尊 en 序：Austria／Belgium／Bulgaria…；HK＝Hong Kong SAR）" do
    shop = RenderParity::Mirror.call(subdomain: "lc-spec", spec: spec).shop
    countries = drop_for(shop, "en").invoke_drop("available_countries")
    expect(countries.first(3).map { |c| c["name"] }).to eq(%w[Austria Belgium Bulgaria])
    expect(countries.find { |c| c["iso_code"] == "HK" }["name"]).to eq("Hong Kong SAR") # external-facts §G21 en 在地名
    expect(countries.map { |c| c["iso_code"] }).to match_array(drop_for(shop, "zh-Hans").invoke_drop("available_countries").map { |c| c["iso_code"] })
  end

  it "LC3 🔴 draft 市場與非 region 市場不列入" do
    shop = RenderParity::Mirror.call(subdomain: "lc-spec", spec: spec).shop
    ActsAsTenant.with_tenant(shop) do
      draft = Market.create!(name: "加拿大", handle: "ca", status: "draft", market_type: "region")
      draft.market_regions.create!(shop_id: shop.id, country_code: "CA")
      draft.market_web_presences.create!(shop_id: shop.id, subfolder_suffix: "ca", default_shop_locale: "zh-Hans")
    end
    codes = drop_for(shop, "zh-Hans").invoke_drop("available_countries").map { |c| c["iso_code"] }
    expect(codes).not_to include("CA")
    expect(codes.size).to eq(31)
  end

  it "LC4 單市場店（建店預設 HK）⇒ available_countries 恰 1 國＝當前國（Ella 據此隱藏地區選擇器）" do
    shop = create(:shop)
    source_tag = ActsAsTenant.with_tenant(shop) { ShopLocale.find_by!(is_source: true).locale_tag }
    drop = drop_for(shop, source_tag)
    countries = drop.invoke_drop("available_countries")
    expect(countries.map { |c| c["iso_code"] }).to eq([ "HK" ])
    expect(countries.first["name"]).to eq(drop.invoke_drop("country")["name"])
  end
end
