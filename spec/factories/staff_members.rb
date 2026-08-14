FactoryBot.define do
  # 🔴 staff_member 已升為組織層（裁定 D8／§A G24），**不再 belongs_to shop**。
  #
  # 但幾乎所有既有 spec 都是「某店的某個 staff」這個語境，所以保留 `shop:` 這個
  # transient 參數：傳了就順手建一筆 UserStoreAssignment，讓 spec 寫法不用大改，
  # 同時如實反映新模型——「屬於某店」現在是一筆**指派**，不是一個欄位。
  #
  # 不傳 `shop:` 就是一個沒有任何店指派的帳號（用來測 fail-closed）。
  factory :staff_member do
    transient do
      shop { nil }
      role { nil }
    end

    sequence(:email) { |number| "owner#{number}@example.test" }
    password { "long-password-123" }
    password_confirmation { "long-password-123" }
    status { "active" }
    owner { true }

    after(:create) do |staff_member, evaluator|
      if evaluator.shop
        UserStoreAssignment.create!(
          staff_member: staff_member,
          shop: evaluator.shop,
          role: evaluator.role
        )
      end
    end
  end
end
