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
  end
end
