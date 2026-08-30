# frozen_string_literal: true

FactoryBot.define do
  # 🔴 shop 建立時 after_create 已長出 primary market（HK）＋primary domain＋presence＋白名單
  #   （Markets::ProvisionDefaults）——測既定鏈用 `shop.markets.find_by(is_primary: true)`，
  #   本 factory 只給「再開一個次級市場」的情境。
  factory :market do
    shop
    sequence(:name) { |number| "測試市場 #{number}" }
    sequence(:handle) { |number| "market-#{number}" }
    status { "active" }
    market_type { "region" }
    is_primary { false }
  end

  factory :market_region do
    shop
    market
    country_code { "TW" }
  end

  factory :domain do
    shop
    sequence(:host) { |number| "domain#{number}.example" }
    domain_type { "redirect" }
    status { "active" }
  end

  factory :market_web_presence do
    shop
    market
    domain { nil }
    subfolder_suffix { "tw" }
    default_shop_locale { "en" }
  end
end
