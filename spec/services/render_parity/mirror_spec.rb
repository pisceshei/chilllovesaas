# frozen_string_literal: true

require "rails_helper"

# 鏡像店（E8）：把 hoko.vip 快照描述冪等地建到一間店。
# 🔴 假綠殺手：MR2 二次呼叫不得產生重複商品／集合／選單項（find-or-skip 被拿掉 ⇒ 轉紅）；
#   MR1 來源語言必須真的切到 zh-Hans（只加不切 ⇒ `<html lang>` 仍 en）。
RSpec.describe RenderParity::Mirror do
  let(:spec) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/render_parity/hoko.json"), encoding: "UTF-8"))
  end

  def counts(shop)
    ActsAsTenant.with_tenant(shop) do
      { products: Product.where(shop_id: shop.id).count, collections: Collection.where(shop_id: shop.id).count,
        pages: Page.where(shop_id: shop.id).count, items: MenuItem.where(shop_id: shop.id).count,
        themes: Theme.where(shop_id: shop.id).count }
    end
  end

  it "MR1 🔴 建店＋對齊：店名／幣別／旗標、來源語言 zh-Hans（唯一已發布）、主市場 TW、主題、3 商品、集合、頁面、選單" do
    result = described_class.call(subdomain: "mirror-spec", spec: spec)
    shop = result.shop
    expect(shop.name).to eq("我的商店 3")
    expect(shop.store_currency).to eq("HKD")
    expect(shop.customer_accounts_enabled).to be(true)
    expect(shop.taxes_included).to be(true)
    ActsAsTenant.with_tenant(shop) do
      source = ShopLocale.find_by!(is_source: true)
      expect(source.locale_tag).to eq("zh-Hans")
      expect(ShopLocale.where(published: true).pluck(:locale_tag)).to eq([ "zh-Hans" ])
      market = Market.find_by!(is_primary: true)
      expect(market.market_regions.pluck(:country_code)).to eq([ "TW" ])
      presence = market.market_web_presences.first
      expect(presence.default_shop_locale).to eq("zh-Hans")
      expect(presence.market_web_presence_locales.pluck(:locale_tag, :is_market_default)).to eq([ [ "zh-Hans", true ] ])
      expect(Theme.published.first).to have_attributes(name: "ella", version: "7.2.0")
      expect(Product.where(shop_id: shop.id, status: "active").order(:id).pluck(:handle)).to eq(%w[acme-tee bolt-mug cosy-lamp])
      expect(Product.find_by!(handle: "acme-tee").product_variants.first.price_cents).to eq(18_800)
      collection = Collection.find_by!(handle: "frontpage")
      expect(collection.title).to eq("首頁")
      expect(collection.sort_order).to eq("most_relevant") # E8b：本尊 admin 首頁系列 Default sort＝Most relevant
      expect(Page.find_by!(handle: "contact").title).to eq("聯絡我們")
      expect(Page.find_by!(handle: "contact").published_at).to be_present # E8b：本尊頁面已發布（先前草稿 ⇒ 前台 404）
      expect(Page.find_by!(handle: "contact").template_suffix).to eq("contact") # E8b：本尊 /pages/contact 用 page.contact 模板
      # E8b：庫存跟隨快照（本尊 products.json：只有 cosy-lamp available）
      lamp = Product.find_by!(handle: "cosy-lamp").product_variants.first
      expect(InventoryLevel.joins(:inventory_item).where(inventory_items: { product_variant_id: lamp.id }).sum(:available)).to eq(10)
      tee = Product.find_by!(handle: "acme-tee").product_variants.first
      expect(InventoryLevel.joins(:inventory_item).where(inventory_items: { product_variant_id: tee.id }).sum(:available)).to eq(0)
      expect(Menu.find_by!(handle: "main-menu").menu_items.order(:position).pluck(:title)).to eq(%w[首頁 目錄 聯絡我們])
    end
    expect(result.log).to include(a_string_matching(/\Ashop created/))
  end

  it "MR2 🔴 冪等：第二次呼叫不重複建立（商品／集合／頁面／選單項／主題數不變），只回報 exists" do
    first = described_class.call(subdomain: "mirror-spec", spec: spec)
    before = counts(first.shop)
    again = described_class.call(subdomain: "mirror-spec", spec: spec)
    expect(counts(again.shop)).to eq(before)
    expect(again.log).to include(a_string_matching(/product exists: acme-tee/))
    expect(again.log).to include(a_string_matching(/theme: published theme exists/))
  end
end
