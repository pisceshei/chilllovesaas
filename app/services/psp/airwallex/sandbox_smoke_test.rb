# frozen_string_literal: true

module Psp
  module Airwallex
    # sandbox 端到端煙測（G6-1 enable 前置；65 §L V-132 的「沙箱實測」項）。
    #
    # 流程：登入（隱含在第一個請求）→ 建 HKD 1.00 intent（走 Money 契約全鏈）→
    # 官方測試卡 confirm → 取回終態。**只准 sandbox**（PaymentIntents 層已 raise 把關）。
    #
    # 用法（bt3）：RAILS_ENV=production bundle exec rails runner \
    #   'puts Psp::Airwallex::SandboxSmokeTest.run(Shop.find_by(subdomain: "demo")).inspect'
    module SandboxSmokeTest
      # 官方 sandbox 測試卡（digest §H：4035501000000008＝非 3DS 成功卡）。
      TEST_CARD = {
        number: "4035501000000008", expiry_month: "12", expiry_year: "2030",
        cvc: "123", name: "CHILL LOVE TEST"
      }.freeze

      module_function

      # @param shop [Shop]
      # @return [Hash] 各步結果（不含任何祕密）
      def run(shop)
        provider = ActsAsTenant.with_tenant(shop) { ShopPaymentProvider.find_by!(provider: "airwallex") }
        intents = PaymentIntents.new(provider)
        amount = Money::Storage.from_cents(100, "HKD")

        created = intents.create(
          amount:, request_id: SecureRandom.uuid,
          merchant_order_id: "smoke-#{SecureRandom.hex(6)}"
        )
        confirmed = intents.confirm_with_test_card(created.fetch("id"), card: TEST_CARD)
        final = intents.get(created.fetch("id"))

        {
          environment: provider.environment,
          intent_id: created["id"],
          created_status: created["status"],
          confirmed_status: confirmed["status"],
          final_status: final["status"],
          amount_echo: final["amount"],
          currency: final["currency"]
        }
      end
    end
  end
end
