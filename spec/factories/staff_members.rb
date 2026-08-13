FactoryBot.define do
  factory :staff_member do
    association :shop
    sequence(:email) { |number| "owner#{number}@example.test" }
    password { "long-password-123" }
    password_confirmation { "long-password-123" }
    status { "active" }
    owner { true }
  end
end
