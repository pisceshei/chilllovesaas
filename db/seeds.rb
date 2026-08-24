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

# 平台語言字典（ML-0）：冪等，正典在 PlatformLocale::LAUNCH_SEED。
PlatformLocale.seed!

brand_name = Rails.configuration.x.brand.name
shop_created = false
shop = ActsAsTenant.without_tenant do
  Shop.find_or_create_by!(subdomain: ENV.fetch("SEED_SHOP_SUBDOMAIN", "demo")) do |record|
    shop_created = true
    record.assign_attributes(
      name: ENV.fetch("SEED_SHOP_NAME", "#{brand_name} Demo"),
      status: "active",
      store_currency: "HKD",
      timezone: "Asia/Hong_Kong",
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

# 🔴 指派是**登入的前提**，不是選配。
# `ApplicationController#resume_admin_session` 與 `SessionsController#create` 兩道閘
# 都以 `user_store_assignments` 判定「這個人屬不屬於這間店」（fail-closed）。
# 少了這一列，seeds 建出來的 owner **登入會被自己的安全閘擋掉**——
# 帳密全對、卻一直退回登入頁，而且錯誤訊息（刻意地）不會說出真正原因。
assignment = UserStoreAssignment.find_or_create_by!(staff_member_id: staff.id, shop_id: shop.id)

puts "#{shop_created ? 'Created' : 'Preserved'} empty shop #{shop.subdomain.inspect}."
puts "#{assignment.previously_new_record? ? 'Created' : 'Preserved'} store assignment "      "staff##{staff.id} → shop##{shop.id}."
puts "#{staff_created ? 'Created' : 'Preserved'} owner #{staff.email.inspect}."
puts "Development login password for a newly created owner: chill-love-demo" if !Rails.env.production? && staff_created
