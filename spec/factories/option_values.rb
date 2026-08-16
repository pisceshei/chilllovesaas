FactoryBot.define do
  factory :option_value do
    association :product_option
    shop { product_option.shop }
    sequence(:value) { |number| "值 #{number}" }
    sequence(:position) { |number| number }
  end
end
