# frozen_string_literal: true

require "rails_helper"

# S10（D76）：price_lists 資料層矩陣。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   K1 decrease>100 必須 invalid（刪掉條件式上限 ⇒ 轉紅）——負價格閘
#   K2 同 catalog 第二張 price list 必須 invalid（刪 uniqueness ⇒ 轉紅）——單數所有格閘
#   K3 publication 刪除→孤兒 catalog 清理在**帶 price list 時仍成功**且 price list 同滅
#      （拿掉 has_one 的 dependent: :destroy ⇒ FK RESTRICT 讓這格轉紅）
RSpec.describe PriceList do
  let(:shop) { create(:shop) }

  def catalog!(title: "S10 測試 catalog")
    ActsAsTenant.with_tenant(shop) do
      SalesCatalog.create!(shop_id: shop.id, title:, catalog_type: "market", status: "active")
    end
  end

  def price_list!(catalog, **attrs)
    ActsAsTenant.with_tenant(shop) do
      described_class.create!(
        { shop_id: shop.id, sales_catalog: catalog, name: "HK 價格表", currency: "HKD",
          adjustment_type: "percentage_decrease", adjustment_basis_points: 0,
          compare_at_mode: "adjusted" }.merge(attrs)
      )
    end
  end

  it "合法建立：§9.5b payload 的欄位形（HKD／PERCENTAGE_DECREASE 0／ADJUSTED）" do
    row = price_list!(catalog!)
    expect(row).to be_persisted
    expect(row.compare_at_mode).to eq("adjusted")
  end

  it "enum 值域：type 與 mode 各恰二值，值域外 invalid" do
    catalog = catalog!
    ActsAsTenant.with_tenant(shop) do
      expect(described_class.new(shop_id: shop.id, sales_catalog: catalog, name: "x", currency: "HKD",
        adjustment_type: "fixed", adjustment_basis_points: 0, compare_at_mode: "adjusted")).not_to be_valid
      expect(described_class.new(shop_id: shop.id, sales_catalog: catalog, name: "x", currency: "HKD",
        adjustment_type: "percentage_increase", adjustment_basis_points: 0, compare_at_mode: "zeroed")).not_to be_valid
    end
  end

  it "K1 🔴 decrease 上限 10000bp（負價格閘）：10000 合法、10001 invalid；increase 無此上限" do
    catalog = catalog!
    expect(price_list!(catalog, adjustment_basis_points: 10_000)).to be_persisted
    ActsAsTenant.with_tenant(shop) do
      over = described_class.new(shop_id: shop.id, sales_catalog: catalog!(title: "另一顆"), name: "x",
        currency: "HKD", adjustment_type: "percentage_decrease",
        adjustment_basis_points: 10_001, compare_at_mode: "adjusted")
      expect(over).not_to be_valid
      up = described_class.new(shop_id: shop.id, sales_catalog: catalog!(title: "第三顆"), name: "x",
        currency: "HKD", adjustment_type: "percentage_increase",
        adjustment_basis_points: 25_000, compare_at_mode: "adjusted")
      expect(up).to be_valid
    end
  end

  it "負百分比 invalid" do
    ActsAsTenant.with_tenant(shop) do
      row = described_class.new(shop_id: shop.id, sales_catalog: catalog!, name: "x", currency: "HKD",
        adjustment_type: "percentage_increase", adjustment_basis_points: -1, compare_at_mode: "adjusted")
      expect(row).not_to be_valid
    end
  end

  it "K2 🔴 一個 catalog 至多一張 price list（官方單數所有格）" do
    catalog = catalog!
    price_list!(catalog)
    ActsAsTenant.with_tenant(shop) do
      second = described_class.new(shop_id: shop.id, sales_catalog: catalog, name: "第二張",
        currency: "HKD", adjustment_type: "percentage_decrease",
        adjustment_basis_points: 5, compare_at_mode: "adjusted")
      expect(second).not_to be_valid
    end
  end

  it "K3 🔴 publication 刪除的孤兒 catalog 清理帶著 price list 仍成功，price list 同滅" do
    result = ActsAsTenant.with_tenant(shop) do
      Publications::Write.create(shop: shop, title: "S10 自訂管道")
    end
    publication = result.publication
    expect(publication).to be_present
    catalog = publication.sales_catalog
    price_list!(catalog)

    delete_result = ActsAsTenant.with_tenant(shop) do
      Publications::Write.delete(shop: shop, publication: publication)
    end
    expect(delete_result.user_errors).to be_empty
    ActsAsTenant.without_tenant do
      expect(SalesCatalog.where(id: catalog.id)).to be_empty
      expect(described_class.where(sales_catalog_id: catalog.id)).to be_empty
    end
  end
end
