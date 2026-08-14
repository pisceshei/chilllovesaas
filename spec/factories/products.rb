FactoryBot.define do
  factory :product do
    association :shop
    sequence(:title) { |number| "商品 #{number}" }
    sequence(:handle) { |number| "product-#{number}" }
    description_html { "" }
    status { "draft" }
    tags { [] }
  end
end
