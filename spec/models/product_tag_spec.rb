# frozen_string_literal: true

require "rails_helper"

# 第 11 包：標籤正規化列的 model 層防線。
RSpec.describe ProductTag do
  let(:shop) { create(:shop, subdomain: "product-tag-model") }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  let(:product) { create(:product, shop:, title: "商品") }

  def row_with(key)
    described_class.new(shop_id: shop.id, product_id: product.id, tag_key: key, tag_display: "顯示")
  end

  it "🔴 J2（2026-08-26 收斂輪）：tag_key 超過欄寬 ⇒ model 驗證擋下，不落到 DB 拋 ValueTooLong" do
    # 第二道防線：服務層（SaveProduct）先擋，但 migration 回填與任何未來的寫入路徑
    # 都經過 model。少了它，溢位以 `ActiveRecord::ValueTooLong` 現形，而該例外不在
    # 服務層的 rescue 清單裡 ⇒ 漏成 500（鐵律 4①）。
    row = row_with("k" * 256)

    expect(row).not_to be_valid
    expect(row.errors[:tag_key]).to be_present
  end

  it "剛好在欄寬內＝合法" do
    expect(row_with("k" * 255)).to be_valid
  end
end
