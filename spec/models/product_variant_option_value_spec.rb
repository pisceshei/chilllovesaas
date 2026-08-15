# frozen_string_literal: true

require "rails_helper"

# D12 的四條 DB 層不變量 ＋ digest 的語義。
#
# 🔴 這裡驗的是**資料庫真的擋得住**，不是「model 有寫 validation」。
# 每一條都刻意繞過 model（`insert_all`）或直接觸發 DB 錯誤——
# model validation 是給正常路徑的可讀訊息，DB 約束才是最後防線。
RSpec.describe ProductVariantOptionValue, type: :model do
  let(:shop) { create(:shop) }

  # `product` / `size` / `variant` 全部在 tenant 內建立（require_tenant=true）
  def within_shop(&block)
    ActsAsTenant.with_tenant(shop, &block)
  end

  describe "🔴 DB 層的四條不變量" do
    it "① 合法的座標可以寫入" do
      within_shop do
        product = create(:product, shop:)
        size = create(:product_option, product:, values: %w[S M])
        variant = create(:product_variant, product:, option_values: [ size.option_values.first ])

        expect(variant.product_variant_option_values.count).to eq(1)
        expect(variant.option_values.map(&:value)).to eq([ "S" ])
      end
    end

    it "② 同一個 (變體, 選項) 塞第二個值 ⇒ 擋下" do
      within_shop do
        product = create(:product, shop:)
        size = create(:product_option, product:, values: %w[S M])
        small, medium = size.option_values.order(:position).to_a
        variant = create(:product_variant, product:, option_values: [ small ])

        duplicate = build(:product_variant_option_value,
          product_variant: variant, option_value: medium)

        # model 層先擋（正常路徑拿得到可讀訊息）
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:product_option_id]).to be_present

        # 🔴 繞過 model 之後 DB 仍然擋得住——這才是不變量。
        expect {
          described_class.insert!({
            shop_id: shop.id, product_id: product.id, product_variant_id: variant.id,
            product_option_id: size.id, option_value_id: medium.id,
            created_at: Time.current, updated_at: Time.current
          })
        }.to raise_error(ActiveRecord::RecordNotUnique, /uq_pvov_variant_option/)
      end
    end

    it "③ 說謊的 product_option_id（值不屬於該選項）⇒ 擋下" do
      within_shop do
        product = create(:product, shop:)
        size  = create(:product_option, product:, values: %w[S])
        color = create(:product_option, product:, values: %w[Red])
        variant = create(:product_variant, product:)

        # 宣告「這是 color 的值」但實際塞 size 的值。
        # 🔴 少了 fk_pvov_value 這支三欄歸屬外鍵，這一列會寫進去，
        #    於是同一個變體可以同時掛「顏色=紅」與「顏色=藍」。
        expect {
          described_class.insert!({
            shop_id: shop.id, product_id: product.id, product_variant_id: variant.id,
            product_option_id: color.id, option_value_id: size.option_values.first.id,
            created_at: Time.current, updated_at: Time.current
          })
        }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_pvov_value/)
      end
    end

    it "④ 跨商品掛選項（同一間店的另一個商品的選項）⇒ 擋下" do
      within_shop do
        product = create(:product, shop:)
        other   = create(:product, shop:)
        variant = create(:product_variant, product:)
        foreign_option = create(:product_option, product: other, values: %w[X])

        # 🔴 這是 `product_id` 這個冗餘欄存在的唯一理由：
        #    MySQL 的 CHECK 不能跨表，只有複合外鍵擋得住。
        expect {
          described_class.insert!({
            shop_id: shop.id, product_id: other.id, product_variant_id: variant.id,
            product_option_id: foreign_option.id,
            option_value_id: foreign_option.option_values.first.id,
            created_at: Time.current, updated_at: Time.current
          })
        }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_pvov_variant/)
      end
    end
  end

  describe "🔴 變體座標的唯一性（13 §F1-2 的兜底）" do
    it "同一商品的兩個變體不得有相同的選項組合" do
      within_shop do
        product = create(:product, shop:)
        size = create(:product_option, product:, values: %w[S])
        small = size.option_values.first

        create(:product_variant, product:, option_values: [ small ], position: 1)

        expect {
          create(:product_variant, product:, option_values: [ small ], position: 2)
        }.to raise_error(ActiveRecord::RecordNotUnique, /uq_product_variants_option_values_digest/)
      end
    end

    it "🔴 同一商品只能有一個「無選項」變體（本尊的 Default Title）" do
      within_shop do
        product = create(:product, shop:)
        first = create(:product_variant, product:, position: 1)
        expect(first.option_values_digest).to eq(Catalog::OptionValuesDigest::NO_OPTIONS)

        expect {
          create(:product_variant, product:, position: 2)
        }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    it "不同商品可以有相同的 digest（唯一索引帶 product_id 的理由）" do
      within_shop do
        a = create(:product, shop:)
        b = create(:product, shop:)
        expect {
          create(:product_variant, product: a)
          create(:product_variant, product: b)
        }.not_to raise_error
      end
    end

    it "兩間店互不干擾（鐵律 2：唯一索引以 shop_id 開頭）" do
      other_shop = create(:shop)
      within_shop { create(:product_variant, product: create(:product, shop:)) }
      expect {
        ActsAsTenant.with_tenant(other_shop) do
          create(:product_variant, product: create(:product, shop: other_shop))
        end
      }.not_to raise_error
    end
  end

  # ── digest 的語義（D12 最關鍵的兩條）────────────────────────────────────────
  describe "🔴 digest 的穩定性" do
    it "改名選項值 ⇒ digest 不變、變體 id 不變（67 §B.3-4）" do
      within_shop do
        product = create(:product, shop:)
        color = create(:product_option, product:, values: %w[Red])
        red = color.option_values.first
        variant = create(:product_variant, product:, option_values: [ red ])

        before_digest = variant.option_values_digest
        before_id = variant.id

        red.update!(value: "Crimson")
        variant.reload.save!

        expect(variant.option_values_digest).to eq(before_digest)
        expect(variant.id).to eq(before_id)
      end
    end

    it "調整選項 position ⇒ digest 不變（排序鍵是 id 不是 position）" do
      within_shop do
        product = create(:product, shop:)
        size  = create(:product_option, product:, position: 1, values: %w[S])
        color = create(:product_option, product:, position: 2, values: %w[Red])
        variant = create(:product_variant, product:,
          option_values: [ size.option_values.first, color.option_values.first ])

        before_digest = variant.option_values_digest

        # 🔴 兩步交換（`uq_product_options_product_id_position` 是唯一索引，
        #    直接對調中途會撞）——這也是重排端點日後要處理的形態。
        size.update!(position: 99)
        color.update!(position: 1)
        size.update!(position: 2)
        variant.reload.save!

        expect(variant.option_values_digest).to eq(before_digest)
      end
    end

    # 🔴 這一條釘住的是「digest 不是身分」——63 §B.5 的身分保持會讓它變，
    # 而那是**正常的**，不是矛盾。
    it "加一個選項給既有變體 ⇒ digest 改變，但變體 id 不變（63 §B.5）" do
      within_shop do
        product = create(:product, shop:)
        variant = create(:product_variant, product:)
        before_id = variant.id
        expect(variant.option_values_digest).to eq(Catalog::OptionValuesDigest::NO_OPTIONS)

        # 加第一個選項：既有變體補上該選項的**第一個值**（§B.5 第一列）
        volume = create(:product_option, product:, values: %w[230ml 250ml 330ml])
        create(:product_variant_option_value,
          product_variant: variant, option_value: volume.first_value)
        variant.reload.save!

        expect(variant.id).to eq(before_id)
        expect(variant.option_values_digest).not_to eq(Catalog::OptionValuesDigest::NO_OPTIONS)
        expect(variant.option_values.map(&:value)).to eq([ "230ml" ])
      end
    end
  end
end
