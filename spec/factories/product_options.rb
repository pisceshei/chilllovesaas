FactoryBot.define do
  # `shop` 刻意**不**用 association：選項的 shop 必須與 product 的 shop 相同，
  # 各自 association 會生出兩間店的資料（跨租戶髒資料）。同 product_variants factory 的理由。
  factory :product_option do
    association :product
    shop { product.shop }
    sequence(:name) { |number| "選項 #{number}" }
    sequence(:position) { |number| number }

    # 🔴 `values` 是 transient：選項值的 position 必須在選項內連續且唯一
    # （`uq_option_values_product_option_id_position`），交給 factory 統一產生，
    # 比讓每個測試自己數 position 可靠。
    transient do
      values { [] }
    end

    after(:create) do |option, evaluator|
      evaluator.values.each_with_index do |value, index|
        create(:option_value, product_option: option, value:, position: index + 1)
      end
    end
  end
end
