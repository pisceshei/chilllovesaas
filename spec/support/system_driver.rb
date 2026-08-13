# frozen_string_literal: true

Capybara.register_driver :selenium_headless_lvh do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--window-size=1440,900")
  options.add_argument("--disable-gpu")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--no-sandbox") if ENV["CI"].present?
  options.add_argument("--host-resolver-rules=MAP *.lvh.me 127.0.0.1")

  Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium_headless_lvh
    Capybara.always_include_port = true
  end

  config.after(:each, type: :system) do
    Capybara.app_host = nil
  end
end
