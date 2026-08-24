# frozen_string_literal: true

module Mutations
  # 庫存絕對值設定（排程第 17 包）。CAS 語義：每筆 quantities 必須帶 compareQuantity
  # 或顯式 ignoreCompareQuantity（本尊 COMPARE_QUANTITY_REQUIRED）。
  # idempotencyKey String! ＝ G28；授權＝D42（inventory.edit）。
  class InventorySetQuantities < BaseMutation
    graphql_name "InventorySetQuantities"
    description "以絕對值設定庫存數量（唯一寫入入口 Inventory::Adjust 的 set 模式）。"

    user_errors_type Types::Errors::InventoryAdjustUserErrorType

    argument :idempotency_key, String, required: true,
      description: "冪等鍵（G28：契約層必填）。failed 可同 key 重試（D41）。"
    argument :input, Types::Inputs::InventorySetQuantitiesInput, required: true

    field :inventory_adjustment_group, Types::InventoryAdjustmentGroupType, null: true

    def resolve(idempotency_key:, input:)
      # G28 已讓 schema 層擋缺鍵；本呼叫是與全 mutation 靜態掃描一致的雙保險。
      enforce_idempotency_contract!(idempotency_key)
      authorize_inventory_edit!

      result = Inventory::Adjust.call(
        shop: context.fetch(:current_shop),
        mode: "set",
        input: input.to_h.merge(idempotency_key:),
        staff: context[:current_staff]
      )
      { inventory_adjustment_group: result.group, user_errors: result.user_errors }
    end

    private

    def authorize_inventory_edit!
      staff = context[:current_staff]
      return if staff && (staff.owner? || staff.can?("inventory.edit"))

      raise GraphQL::ExecutionError.new(
        I18n.t("errors.inventory.access_denied"),
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end
  end
end
