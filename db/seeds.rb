# frozen_string_literal: true

# M0 的預設商店刻意不建立商品，讓登入後可以驗收商品空狀態。
# production 必須明確選擇建立 demo，且 seed 只建立缺少的資料，不覆寫既有
# tenant/staff 狀態或密碼。來源：HANDOFF.md M0；docs/specs/11 §1。
if Rails.env.production? && ENV["SEED_DEMO_SHOP"] != "1"
  abort "Production demo seed requires explicit SEED_DEMO_SHOP=1 opt-in."
end

seed_password = ENV["SEED_ADMIN_PASSWORD"].presence
if Rails.env.production? && seed_password.nil?
  abort "Production seed requires SEED_ADMIN_PASSWORD."
end

brand_name = Rails.configuration.x.brand.name
shop_created = false
shop = ActsAsTenant.without_tenant do
  Shop.find_or_create_by!(subdomain: ENV.fetch("SEED_SHOP_SUBDOMAIN", "demo")) do |record|
    shop_created = true
    record.assign_attributes(
      name: ENV.fetch("SEED_SHOP_NAME", "#{brand_name} Demo"),
      status: "active",
      store_currency: "TWD",
      timezone: "Asia/Taipei",
      plan: "basic"
    )
  end
end
abort "Refusing to seed staff into a non-active shop." unless shop.status == "active"

email = ENV.fetch("SEED_ADMIN_EMAIL", "owner@chilllove.test").strip.downcase
staff_created = false
staff = ActsAsTenant.with_tenant(shop) do
  StaffMember.find_or_create_by!(email:) do |record|
    staff_created = true
    password = seed_password || "chill-love-demo"
    record.assign_attributes(
      status: "active",
      owner: true,
      password:,
      password_confirmation: password
    )
  end
end

puts "#{shop_created ? 'Created' : 'Preserved'} empty shop #{shop.subdomain.inspect}."
puts "#{staff_created ? 'Created' : 'Preserved'} owner #{staff.email.inspect}."
puts "Development login password for a newly created owner: chill-love-demo" if !Rails.env.production? && staff_created
