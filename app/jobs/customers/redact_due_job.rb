# frozen_string_literal: true

module Customers
  # 到點抹除 job（G6 步 8a；recurring 每小時）。
  #
  # 官方抹除射程（help 逐字）："Shopify erases personal data, such as your
  # customer's name and address. Certain information, like what was sold and the
  # date and time of the sale, is still visible"／"the profile and order history
  # remain in your Shopify admin."
  # ⇒ 我方：姓名/email/電話/note 清空、地址簿刪除、兩通道狀態→redacted（事件
  #   照 append）、anonymized_at 落戳；**customer 列與訂單不刪**。
  # ⚪ order 層欄位（orders.email/地址快照）的遮蔽隨後續裁定（91 §3.52）。
  class RedactDueJob < ApplicationJob
    queue_as :background

    def perform
      ActsAsTenant.without_tenant do
        Customer.where(anonymized_at: nil)
                .where(redaction_scheduled_at: ..Time.current)
                .find_each { |customer| redact!(customer) }
      end
    end

    private

    def redact!(customer)
      shop = Shop.find(customer.shop_id)
      ActsAsTenant.with_tenant(shop) do
        ActiveRecord::Base.transaction do
          now = Time.current
          %w[email sms].each do |channel|
            CustomerMarketingConsent.create!(
              shop_id: shop.id, customer_id: customer.id, channel:,
              state: "redacted", consent_updated_at: now, source: "system"
            )
          end
          CustomerAddress.where(customer_id: customer.id).delete_all
          customer.update!(
            first_name: nil, last_name: nil, email: nil, phone: nil, note: nil,
            email_marketing_state: "redacted", sms_marketing_state: "redacted",
            email_marketing_consent: false, sms_marketing_consent: false,
            redaction_scheduled_at: nil, anonymized_at: now
          )
        end
      end
    end
  end
end
