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

    # D12：變體的選項座標。
    #
    # 🔴 **預設是空陣列＝無選項變體**（本尊的 Default Title），那是**合法狀態**，
    # 不是「還沒填」。⇒ 同一個 product 底下**只能有一個**預設變體，
    # 第二個會撞 `uq_product_variants_option_values_digest`——那正是 D12 要建立的不變量。
    # 需要多個變體的測試必須給不同的 `option_values`。
    #
    # 🔴 **不在 factory 裡塞假 digest**。digest 一律由 `ProductVariant` 的
    # `before_validation` 依 join 列算出，factory 只負責建 join 列並觸發重算。
    transient do
      option_values { [] }
    end

    # 🔴 **座標必須在存檔**之前**掛上去，不能事後補**（2026-08-16 改，PR #38 Codex review）。
    #    `ProductVariant` 現在驗「商品的每個選項恰好一個值」——在一個已經有選項的商品上，
    #    先存一個沒有座標的變體是**不合法的中間狀態**，存不進去。
    # ⚠️ 這不是 factory 的權宜，是**真實約束**：寫入 service 也必須把變體與它的座標
    #    在同一次寫入裡建好。factory 照著同樣的形狀走，測試才代表得了生產路徑。
    after(:build) do |variant, evaluator|
      evaluator.option_values.each do |value|
        variant.product_variant_option_values.build(
          shop: variant.shop,
          product: variant.product,
          product_option: value.product_option,
          option_value: value
        )
      end
    end
  end
end
