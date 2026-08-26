# frozen_string_literal: true

require "rails_helper"

# `SalesCatalog`＝三層 AND 的第三層（`docs/specs/88` §1）。
# 本尊實測形態＝`docs/research/82` §9.5b／§10.3。
RSpec.describe SalesCatalog, type: :model do
  let!(:shop) { create(:shop, subdomain: "sales-catalog") }

  def build_catalog(**attrs)
    described_class.new({ shop:, title: "線上商店", catalog_type: "app", status: "active" }.merge(attrs))
  end

  describe "值域" do
    it "catalog_type 恰三值，**不含 none**" do
      # 🔴 本尊 `CatalogType` 有第四個值 `NONE`，但它的語義是「不屬於任何 catalog」
      #   ——那是讀取時的一種結果，不是一種 catalog 的種類。落庫會讓
      #   「沒有 catalog」與「有一個叫 none 的 catalog」變成兩個無法區分的狀態。
      expect(described_class::TYPES).to contain_exactly("app", "market", "company_location")
    end

    it "status 恰三值（admin UI 只曝露前二，draft 只在 API 層）" do
      expect(described_class::STATUSES).to contain_exactly("active", "archived", "draft")
    end

    it "非法 catalog_type 被擋" do
      ActsAsTenant.with_tenant(shop) do
        expect(build_catalog(catalog_type: "none")).not_to be_valid
        expect(build_catalog(catalog_type: "app")).to be_valid
      end
    end

    it "非法 status 被擋" do
      ActsAsTenant.with_tenant(shop) do
        expect(build_catalog(status: "deleted")).not_to be_valid
        described_class::STATUSES.each do |status|
          expect(build_catalog(status:)).to be_valid, "#{status} 應該合法"
        end
      end
    end
  end

  describe "title" do
    it "必填" do
      ActsAsTenant.with_tenant(shop) do
        expect(build_catalog(title: nil)).not_to be_valid
        expect(build_catalog(title: "")).not_to be_valid
      end
    end

    # 上限 255＝本尊表單的字元計數器實測值（`82` §9.5c 顯示 `0/255`）。
    it "上限 255 字元" do
      ActsAsTenant.with_tenant(shop) do
        expect(build_catalog(title: "a" * 255)).to be_valid
        expect(build_catalog(title: "a" * 256)).not_to be_valid
      end
    end
  end

  describe ".channel_catalog_title" do
    # 🔴 我方**刻意不照抄**本尊的 `Channel Catalog {publicationId} for {ChannelName}`
    #   格式，理由見 `sales_catalog.rb` 的方法註釋（catalog 先於 publication 建立，
    #   建立當下沒有 publication id）。這一格把那個裁定釘住。
    it "直接用管道名，不含 publication id" do
      expect(described_class.channel_catalog_title("線上商店")).to eq("線上商店")
    end
  end

  describe "租戶隔離（鐵律 2）" do
    let!(:other) { create(:shop, subdomain: "sales-catalog-other") }

    it "看不到別間店的 catalog" do
      ActsAsTenant.with_tenant(shop) { expect(described_class.count).to eq(1) }
      ActsAsTenant.with_tenant(other) { expect(described_class.count).to eq(1) }

      mine = ActsAsTenant.with_tenant(shop) { described_class.first }
      theirs = ActsAsTenant.with_tenant(other) { described_class.first }
      expect(mine.id).not_to eq(theirs.id)

      ActsAsTenant.with_tenant(shop) { expect(described_class.find_by(id: theirs.id)).to be_nil }
    end

    it "沒有租戶時 fail-closed（不是靜默回空集合）" do
      expect { described_class.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end
  end

  describe "被 publication 指著時不得消失" do
    # 🔴 這一格證明 `has_one :publication` **沒有 `dependent:`** 是對的：
    #   刪除的阻擋由外鍵擔保，而外鍵連 `delete_all` 都擋得住
    #   （`dependent: :restrict_with_error` 只擋 `destroy`）。
    #   沒有 catalog 的 publication ＝三層 AND 第三層斷掉 ＝該管道商品靜默不可見。
    it "delete_all 也被外鍵擋下" do
      ActsAsTenant.with_tenant(shop) do
        expect { described_class.delete_all }.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end

    it "destroy 同樣被外鍵擋下" do
      ActsAsTenant.with_tenant(shop) do
        expect { described_class.first.destroy }.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end
  end

  describe "整店刪除" do
    # 🔴 `shop.rb` 把 `has_many :sales_catalogs` 宣告在 `has_many :publications` **之後**，
    #   因為 `dependent:` 按宣告順序註冊成 `before_destroy`。順序倒過來會先刪 catalog、
    #   被外鍵擋住，錯誤訊息只會說「無法刪除 catalog」，看不出根因。
    it "空店仍然刪得掉（catalog 不會擋住刪店）" do
      target = create(:shop, subdomain: "sales-catalog-drop")
      target_id = target.id

      expect { target.destroy }.not_to raise_error
      expect(ActsAsTenant.without_tenant { described_class.where(shop_id: target_id).count }).to eq(0)
      expect(ActsAsTenant.without_tenant { Publication.where(shop_id: target_id).count }).to eq(0)
    end
  end

  describe "scope" do
    it ".active 只收 active" do
      ActsAsTenant.with_tenant(shop) do
        described_class.create!(title: "封存的", catalog_type: "app", status: "archived")
        expect(described_class.count).to eq(2)
        expect(described_class.active.pluck(:status)).to eq([ "active" ])
      end
    end
  end
end
