# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product, type: :model do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # ── 四態值域（13 §F1.2 / limits.yml:804）─────────────────────────────────
  describe "狀態值域" do
    it "是四態，且逐字等於 limits.yml 的宣告（鐵律 6：不得硬編）" do
      expect(described_class::STATUSES)
        .to eq(Limits.enum(:product, :status_values).map(&:downcase))
      expect(described_class::STATUSES).to contain_exactly("active", "draft", "archived", "unlisted")
    end

    it "接受 unlisted" do
      product = build(:product, shop:, status: "unlisted")
      expect(product).to be_valid
    end

    it "拒絕值域外的狀態" do
      product = build(:product, shop:, status: "published")
      expect(product).not_to be_valid
      expect(product.errors[:status]).to be_present
    end

    # 🔴 這一條是**規格自己的恆等不變量**（limits.yml:809
    # `discoverable_subset_of_purchasable: true`），不是我發明的斷言。
    # 違反＝把買家從搜尋結果送進一個買不了的頁面（soft-404）。
    it "discoverable ⊆ purchasable（13 §F1.2 恆等不變量）" do
      expect(Limits.fetch(:product, :discoverable_subset_of_purchasable)).to be(true)
      expect(described_class::DISCOVERABLE_STATUSES - described_class::PURCHASABLE_STATUSES).to be_empty
    end

    it "UNLISTED 可購買但不可被發現——這正是它存在的理由" do
      expect(described_class::PURCHASABLE_STATUSES).to include("unlisted")
      expect(described_class::DISCOVERABLE_STATUSES).not_to include("unlisted")
    end
  end

  # ── 單一產生器（鐵律 7）──────────────────────────────────────────────────
  describe ".with_status_set" do
    let!(:active) { create(:product, shop:, status: "active") }
    let!(:unlisted) { create(:product, shop:, status: "unlisted") }
    let!(:draft) { create(:product, shop:, status: "draft") }
    let!(:archived) { create(:product, shop:, status: "archived") }

    it "purchasable 集合選出 active 與 unlisted" do
      result = described_class.with_status_set(described_class::PURCHASABLE_STATUSES, shop_id: shop.id)
      expect(result).to contain_exactly(active, unlisted)
    end

    it "discoverable 集合只選出 active" do
      result = described_class.with_status_set(described_class::DISCOVERABLE_STATUSES, shop_id: shop.id)
      expect(result).to contain_exactly(active)
    end

    it "帶明確 shop_id 作 defense in depth：別的租戶的商品不會進來" do
      other_shop = create(:shop)
      ActsAsTenant.with_tenant(other_shop) { create(:product, shop: other_shop, status: "active") }

      result = described_class.with_status_set(described_class::PURCHASABLE_STATUSES, shop_id: shop.id)
      expect(result.map(&:shop_id).uniq).to eq([ shop.id ])
    end

    it "不回傳 draft 與 archived（兩者 purchasable 與 discoverable 皆為 false）" do
      purchasable = described_class.with_status_set(described_class::PURCHASABLE_STATUSES, shop_id: shop.id)
      expect(purchasable).not_to include(draft, archived)
    end
  end

  # ── 刻意不做的東西（把「為什麼沒有」釘住，避免下一輪有人以為是漏做）────────
  describe "刻意未實作" do
    it "不提供 purchasable／discoverable 具名 scope" do
      # 13 §F1.2(d) 的 scope SQL 用 product_publications／variant_publications
      # 兩張不存在的表；而 20260814200000 的回填一列 ProductVariant 都沒有。
      # 照規格加變體層 EXISTS ⇒ 全站商品靜默變成不可購買；
      # 省略變體層 ⇒ 名為 purchasable 的 scope 只做了三層 AND 的第一層，名字在說謊。
      expect(described_class).not_to respond_to(:purchasable)
      expect(described_class).not_to respond_to(:discoverable)
    end
  end
end

RSpec.describe Types::ProductStatusEnum do
  it "GraphQL 值域逐字等於 limits.yml（三份清單不得分岔）" do
    expect(described_class.values.keys).to eq(Limits.enum(:product, :status_values))
  end

  it "每個 token 對應到小寫的 DB 值" do
    expect(described_class.values.values.map(&:value)).to eq(Product::STATUSES)
  end

  it "每個值都有說明（14 §F1.2 的真值表要能從 schema 讀到）" do
    expect(described_class.values.values.map(&:description)).to all(be_present)
  end

  # 🔴 刻意偏離本尊並且必須留住：Shopify 對舊版 API 把 UNLISTED 回成 ACTIVE，
  # 那會讓舊版整合把它當 ACTIVE 處理再送進 feed／索引 ⇒ noindex 完全失效。
  it "不做舊 API 版本降級（limits.yml:817，刻意偏離，13 §F1.2(f)）" do
    expect(Limits.fetch(:product, :unlisted_downgrade_on_old_api_version)).to be(false)
    expect(described_class.values).to have_key("UNLISTED")
  end
end
