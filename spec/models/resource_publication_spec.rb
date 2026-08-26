require "rails_helper"

# 發布模型的行為驗收（docs/specs/88）。
#
# 🔴 這裡證明的是**本尊的三條規則**，不是我方發明的：
#   ①published_at 的三種語義（NULL／過去／未來＝排程）
#   ②Shop 這類管道不支援排程發布 → 能力旗標在 publication 上
#   ③不支援為單一 variant 排程發布
RSpec.describe ResourcePublication, type: :model do
  let(:shop) { create(:shop) }

  # 🔴 **第 12 包起，建立 publishable 會自動建發布列**（`Publications::Materialize`
  # 掛在 Product／ProductVariant／Collection 的 `after_create`）。
  #
  # 本檔驗的是 `ResourcePublication` **自己的 validation**（三種 published_at 語義、
  # 排程能力旗標、跨租戶歸屬、唯一性），每一格都要「手動建一列」才驗得到——
  # 而自動建的列會讓那些 `create!` 全部撞唯一性驗證（`Publishable has already been taken`）。
  # ⇒ 這裡把自動列清掉，回到「這個 publishable 在該管道上還沒有列」的起始狀態。
  #
  # ⚠️ **不要改成「讓生產者別建」**——那會把本檔變成在測一個生產環境不存在的狀態。
  # 生產者本身的驗收在 `spec/models/product_spec.rb` 的「發布層」組。
  def without_auto_publications(record)
    ActsAsTenant.without_tenant do
      ResourcePublication.unscoped.where(
        publishable_type: record.class.name, publishable_id: record.id
      ).delete_all
    end
    record
  end

  let(:product) do
    ActsAsTenant.with_tenant(shop) { without_auto_publications(create(:product, shop:)) }
  end
  # 🔴 **取用**建店時自動建立的那一個，不再自己 `create!`。
  # `Shop#after_create` 落地後（88 §5 #1），每一間店建立時就已經有一列
  # `online_store` publication ⇒ 這裡再 create 一次會撞
  # `uq_publications_channel`（`(shop_id, channel_handle)` 唯一索引），整檔紅。
  # 這正是「加一個 callback 會不會弄壞既有測試」要逐檔查的形態——
  # 本檔是全庫**唯一**受影響處（其他兩處用的是 `shop` 與 `agentic` 兩個不同 handle）。
  let(:publication) do
    ActsAsTenant.with_tenant(shop) { Publication.online_store }
  end

  it "treats published_at as three states: nil, past, and scheduled future" do
    ActsAsTenant.with_tenant(shop) do
      unpublished = described_class.create!(
        shop:, publication:, publishable: product, published_at: nil
      )
      expect(unpublished.published?).to be(false)

      unpublished.update!(published_at: 1.day.ago)
      expect(unpublished.published?).to be(true)

      # 未來時間＝排程發布：現在還沒上架，到點才算
      unpublished.update!(published_at: 3.days.from_now)
      expect(unpublished.published?).to be(false)
      expect(unpublished.published?(at: 4.days.from_now)).to be(true)
    end
  end

  it "rejects scheduling on a channel that does not support future publishing" do
    ActsAsTenant.with_tenant(shop) do
      # 本尊：Shop 管道不支援排程發布（82 §0.2）
      shop_channel = Publication.create!(
        shop:, name: "Shop", channel_handle: "shop",
        supports_future_publishing: false
      )

      record = described_class.new(
        shop:, publication: shop_channel, publishable: product,
        published_at: 3.days.from_now
      )

      expect(record).not_to be_valid
      expect(record.errors[:published_at]).to be_present

      # 立即發布仍然可以
      record.published_at = 1.minute.ago
      expect(record).to be_valid
    end
  end

  it "rejects scheduling a single variant" do
    ActsAsTenant.with_tenant(shop) do
      # 🔴 用**真的存在**的 variant。原本這裡寫 publishable_id: 1（不存在的 id），
      # 測試照樣綠——但綠的原因可能是「找不到該物件」而不是「不得為 variant 排程」，
      # 那樣就證明不到它宣稱要證明的事。
      variant = without_auto_publications(
        ProductVariant.create!(shop:, product:, title: "預設", position: 1)
      )

      record = described_class.new(
        shop:, publication:, publishable: variant, published_at: 3.days.from_now
      )

      expect(record).not_to be_valid
      expect(record.errors[:published_at]).to be_present

      # 立即發布仍然可以——證明擋的是「排程」不是「variant」
      record.published_at = 1.minute.ago
      expect(record).to be_valid
    end
  end

  describe "跨租戶防護（多型關聯）" do
    # 🔴 acts_as_tenant 對**多型**外鍵不做歸屬驗證（gem 原始碼
    # model_extensions.rb:57-62 明確排除），MySQL 也無法對多型欄位建外鍵
    # ⇒ gem 層與 DB 層都沒有人擋，只能由 model validation 擋。
    let(:other_shop) { create(:shop) }
    let(:other_product) do
      ActsAsTenant.with_tenant(other_shop) { create(:product, shop: other_shop) }
    end

    it "rejects a publishable that belongs to another shop" do
      ActsAsTenant.with_tenant(shop) do
        record = described_class.new(
          shop:, publication:, publishable_type: "Product", publishable_id: other_product.id
        )

        expect(record).not_to be_valid
        expect(record.errors[:publishable]).to be_present
      end
    end

    it "still rejects it when the tenant scope is not in effect" do
      # 🔴 這一條才是重點。常規請求下 belongs_to 的存在性驗證 ＋ default_scope
      # 會**順帶**擋住跨店 id，但那是偶然的副作用；在 without_tenant
      # （資料遷移、seeds、維運腳本）裡那層保護整個消失。
      # 沒有明擋的 validation，下面這一列會存進去。
      other_product # 先在對方租戶下建好
      ActsAsTenant.without_tenant do
        record = described_class.new(
          shop_id: shop.id, publication:,
          publishable_type: "Product", publishable_id: other_product.id
        )

        expect(record).not_to be_valid
        expect(record.errors[:publishable]).to be_present
      end
    end

    it "accepts a publishable from the same shop" do
      ActsAsTenant.with_tenant(shop) do
        record = described_class.new(shop:, publication:, publishable: product)
        expect(record).to be_valid
      end
    end
  end

  it "allows the same publishable in different publications but not twice in one" do
    ActsAsTenant.with_tenant(shop) do
      other = Publication.create!(shop:, name: "代理式", channel_handle: "agentic")

      described_class.create!(shop:, publication:, publishable: product)
      expect {
        described_class.create!(shop:, publication: other, publishable: product)
      }.not_to raise_error

      duplicate = described_class.new(shop:, publication:, publishable: product)
      expect(duplicate).not_to be_valid
    end
  end
end
