# frozen_string_literal: true

module Mutations
  # 建立出貨（G6-8 步 5；對位本尊 fulfillmentCreate——官方句「Creates a fulfillment
  # for one or more FulfillmentOrder objects.」，取證 2026-09-01。命名裁定：
  # fulfillmentCreateV2 官方頁標「Deprecated. Use fulfillmentCreate instead.」
  # ⇒ 現行命名＝fulfillmentCreate）。
  #
  # v1 形＝input 照本尊（lineItemsByFulfillmentOrder pairs），服務層只接受恰一組
  # pair（每單一張 FO——Fulfillments::Create 檔頭）。
  class FulfillmentCreate < BaseMutation
    graphql_name "FulfillmentCreate"
    description "建立出貨（指定履約工作單與行項；含追蹤資訊）。"

    user_errors_type Types::Errors::FulfillmentCreateUserErrorType

    argument :fulfillment, Types::Inputs::FulfillmentCreateInput, required: true

    field :fulfillment, Types::FulfillmentType, null: true

    def resolve(fulfillment:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      pairs = fulfillment[:line_items_by_fulfillment_order]
      if pairs.size != 1
        return error("lineItemsByFulfillmentOrder", "v1 一次只支援一張履約工作單。", "INVALID")
      end

      pair = pairs.first
      fo_id = pair[:fulfillment_order_id].to_s[%r{\Agid://chilllove/FulfillmentOrder/(\d+)\z}, 1]
      return error("fulfillmentOrderId", "履約工作單 GID 格式錯誤。", "INVALID") if fo_id.nil?

      line_items = Array(pair[:fulfillment_order_line_items]).map do |li|
        numeric = li[:id].to_s[%r{\Agid://chilllove/LineItem/(\d+)\z}, 1]
        return error("lineItems", "行項 GID 格式錯誤。", "INVALID") if numeric.nil?

        { line_item_id: numeric.to_i, quantity: li[:quantity] }
      end

      order_id = ActsAsTenant.with_tenant(shop) do
        FulfillmentOrder.find_by(id: fo_id.to_i)&.order_id
      end
      return error("fulfillmentOrderId", "找不到這張履約工作單。", "NOT_FOUND") if order_id.nil?

      result = ActsAsTenant.with_tenant(shop) do
        Fulfillments::Create.call(
          shop:, order_id:, fulfillment_order_id: fo_id.to_i, line_items:,
          tracking: normalize_tracking(fulfillment[:tracking_info]),
          notify_customer: fulfillment[:notify_customer]
        )
      end
      to_payload(result)
    end

    private

    # 官方 number/url 單數與 numbers/urls 複數（平行陣列按位對應）合併成
    # 物件陣列（Fulfillment model 檔頭③的儲存形）。
    def normalize_tracking(input)
      return {} if input.nil?

      numbers = Array(input[:numbers])
      urls = Array(input[:urls])
      pairs = numbers.each_with_index.map { |n, i| { number: n, url: urls[i] } }
      pairs << { number: input[:number], url: input[:url] } if input[:number].present?
      { company: input[:company], numbers: pairs }
    end

    def to_payload(result)
      if result.error
        field, message, code = result.error
        { fulfillment: nil, user_errors: [ { field: [ field ], message:, code: } ] }
      else
        { fulfillment: result.fulfillment, user_errors: [] }
      end
    end

    def error(field, message, code)
      { fulfillment: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end

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
