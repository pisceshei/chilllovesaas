# frozen_string_literal: true

module Storefront
  # 買家登入態讀取（G6 步 11；AccountsController 與 CheckoutsController 共用）。
  module CustomerAuth
    extend ActiveSupport::Concern

    CUSTOMER_COOKIE = "_cl_customer"

    # @return [Customer, nil] 過期/查無/已抹除＝nil
    def current_customer
      return @current_customer if defined?(@current_customer)

      token = cookies.signed[CUSTOMER_COOKIE]
      session = ActsAsTenant.with_tenant(current_shop) do
        CustomerSession.authenticate(shop: current_shop, token:)
      end
      @current_customer = session && ActsAsTenant.with_tenant(current_shop) do
        Customer.find_by(id: session.customer_id, anonymized_at: nil)
      end
    end
  end
end
