# frozen_string_literal: true

require "rails_helper"

RSpec.describe "M0 Admin shell", type: :system do
  it "讓 staff 登入後看見 CHILL LOVE shell 與商品空狀態" do
    shop = create(:shop, subdomain: "m0-demo")
    staff = ActsAsTenant.with_tenant(shop) do
      create(:staff_member, shop:, email: "owner@example.test", password: "long-password-123")
    end
    Capybara.app_host = "http://#{shop.subdomain}.lvh.me"

    visit login_path
    fill_in "email", with: staff.email
    fill_in "password", with: "long-password-123"
    click_button "登入"

    expect(page).to have_current_path("/admin/products")
    expect(page).to have_css(".cl-brand__name", text: "CHILL LOVE")
    # ML-1：介面語言依員工 locale（factory 預設 en，裁定 C3）⇒ 英文文案
    expect(page).to have_text("No products yet")
    expect(page).to have_button("Add product")

    screenshot_path = ENV["M0_SCREENSHOT_PATH"]
    page.save_screenshot(screenshot_path) if screenshot_path.present?
  end
end
