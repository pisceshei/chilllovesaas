FactoryBot.define do
  factory :shop do
    sequence(:name) { |number| "測試商店 #{number}" }
    sequence(:subdomain) { |number| "store#{number}" }
    custom_domain { nil }
    status { "active" }
    store_currency { "TWD" }
    timezone { "Asia/Taipei" }
    plan { "basic" }
    feature_flags { {} }
  end
end
