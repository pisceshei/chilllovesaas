require "rails_helper"

# 發布模型的行為驗收（docs/specs/88）。
#
# 🔴 這裡證明的是**本尊的三條規則**，不是我方發明的：
#   ①published_at 的三種語義（NULL／過去／未來＝排程）
#   ②Shop 這類管道不支援排程發布 → 能力旗標在 publication 上
#   ③不支援為單一 variant 排程發布
RSpec.describe ResourcePublication, type: :model do
  let(:shop) { create(:shop) }
  let(:product) do
    ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
  end
  let(:publication) do
    ActsAsTenant.with_tenant(shop) do
      Publication.create!(shop:, name: "線上商店", channel_handle: "online_store")
    end
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
      record = described_class.new(
        shop:, publication:, publishable_type: "ProductVariant", publishable_id: 1,
        published_at: 3.days.from_now
      )

      expect(record).not_to be_valid
      expect(record.errors[:published_at]).to be_present
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
