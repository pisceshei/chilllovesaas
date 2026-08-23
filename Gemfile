source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use mysql as the database for Active Record
gem "mysql2", "~> 0.5"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Admin SPA、GraphQL 契約與多租戶安全底座（HANDOFF D1/D5、規格 12/28）。
gem "acts_as_tenant"
gem "bcrypt", "~> 3.1"
gem "graphql"
gem "pundit"
gem "rack-attack"
gem "strong_migrations"
gem "vite_rails"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# 🔴 2026-08-14：dependabot 提出 1.14 → 2.0.3，已測後**退回 1.x**並登記理由。
# image_processing 2.0 拿掉 MiniMagick 後端、**硬依賴 libvips（ruby-vips）**，
# 本機與 CI 都沒裝 ⇒ 整組 rspec 在 require 階段就 LoadError（cannot load such file -- vips）。
# 這不是普通升版而是**換影像處理引擎**，屬基建決策（DECISIONS D6 的「自建圖片 CDN → imgproxy」
# 方向其實與 vips 一致，但要不要現在把 vips 變成建置硬需求是另一回事）。
# 目前程式碼**尚未用到** image_processing（grep 只命中本行），所以退回零成本。
# ⇒ 升 2.x 的前置條件：①決定影像後端 ②本機與 CI 都裝好 libvips ③補影像處理的實際用例與測試。
gem "image_processing", "~> 1.14"

# CSV 自 Ruby 3.4 起是 bundled gem，不再預設 require（翻譯 CSV 匯入匯出用，ML-5b）。
gem "csv"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # M0 驗收使用 MySQL request/system specs；資料工廠只服務測試。
  gem "factory_bot_rails"
  gem "rspec-rails"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  gem "foreman" # Run Rails, Vite, and Solid Queue together through bin/dev.

  # 將 migration 結構註記同步到 model，方便後續里程碑接手。
  gem "annotaterb", require: false
end


group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
