# frozen_string_literal: true

module Mutations
  # 更新追蹤資訊（G6-8 步 5；對位本尊 fulfillmentTrackingInfoUpdate，取證 2026-09-01）。
  #
  # 🔴 整組取代（ours——官方對取代/合併語義沉默，Fulfillments::UpdateTracking 檔頭）。
  class FulfillmentTrackingInfoUpdate < BaseMutation
    graphql_name "FulfillmentTrackingInfoUpdate"
    description "更新出貨的追蹤資訊（整組取代）。"

    user_errors_type Types::Errors::FulfillmentTrackingInfoUpdateUserErrorType

    argument :fulfillment_id, GraphQL::Types::ID, required: true
    argument :tracking_info_input, Types::Inputs::FulfillmentTrackingInput, required: true
    argument :notify_customer, Boolean, required: false

    field :fulfillment, Types::FulfillmentType, null: true

    def resolve(fulfillment_id:, tracking_info_input:, notify_customer: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      numeric = fulfillment_id.to_s[%r{\Agid://chilllove/Fulfillment/(\d+)\z}, 1]
      if numeric.nil?
        return { fulfillment: nil,
                 user_errors: [ { field: [ "fulfillmentId" ], message: "出貨 GID 格式錯誤。", code: "INVALID" } ] }
      end

      numbers = Array(tracking_info_input[:numbers])
      urls = Array(tracking_info_input[:urls])
      pairs = numbers.each_with_index.map { |n, i| { number: n, url: urls[i] } }
      if tracking_info_input[:number].present?
        pairs << { number: tracking_info_input[:number], url: tracking_info_input[:url] }
      end

      result = ActsAsTenant.with_tenant(shop) do
        Fulfillments::UpdateTracking.call(
          shop:, fulfillment_id: numeric.to_i,
          tracking: { company: tracking_info_input[:company], numbers: pairs },
          notify_customer: notify_customer
        )
      end
      if result.error
        field, message, code = result.error
        { fulfillment: nil, user_errors: [ { field: [ field ], message:, code: } ] }
      else
        { fulfillment: result.fulfillment, user_errors: [] }
      end
    end

    private

    def authorized_shop!
      staff = context[:current_staff]
      unless staff && OrderPolicy.new(staff, Order).create?
        raise GraphQL::ExecutionError.new(
          I18n.t("errors.orders.access_denied"),
          extensions: { "code" => "ACCESS_DENIED" }
        )
      end

      context.fetch(:current_shop)
    end
  end
end
