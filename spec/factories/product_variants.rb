FactoryBot.define do
  # `shop` 刻意**不**用 association：變體的 shop 必須與 product 的 shop 相同，
  # 各自 association 會生出兩間店的變體（跨租戶髒資料），而 `acts_as_tenant`
  # 不驗證這件事（見 app/models/resource_publication.rb 的同型註釋）。
  factory :product_variant do
    association :product
    shop { product.shop }
    sequence(:title) { |number| "變體 #{number}" }
    sequence(:position) { |number| number }
    price_cents { 0 }
    currency { "HKD" }

    # D12：變體的選項座標。
    #
    # 🔴 **預設是空陣列＝無選項變體**（本尊的 Default Title），那是**合法狀態**，
    # 不是「還沒填」。⇒ 同一個 product 底下**只能有一個**預設變體，
    # 第二個會撞 `uq_product_variants_option_values_digest`——那正是 D12 要建立的不變量。
    # 需要多個變體的測試必須給不同的 `option_values`。
    #
    # 🔴 **不在 factory 裡塞假 digest**。digest 一律由 `ProductVariant` 的
    # `before_validation` 依 join 列算出，factory 只負責建 join 列並觸發重算。
    transient do
      option_values { [] }
    end

    after(:create) do |variant, evaluator|
      next if evaluator.option_values.empty?

      evaluator.option_values.each do |value|
        create(:product_variant_option_value, product_variant: variant, option_value: value)
      end
      # 🔴 join 列是在變體存檔**之後**才建的 ⇒ 必須再存一次讓 digest 追上。
      # 這正是 model 註釋裡那條「直接操作 join 表之後必須自己再存一次」的實例。
      variant.reload.save!
    end
  end
end
