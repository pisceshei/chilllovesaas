# frozen_string_literal: true

module Mutations
  # 庫存差額調整（排程第 17 包；本尊同名 mutation 的我方形態）。
  #
  # 🔴 `idempotencyKey: String!`＝**71 §A G28 的刻意加嚴**（使用者 2026-08-24 裁定）：
  #    本尊是 @idempotent directive 的 runtime 檢查（2026-04 起強制），我方推上 schema
  #    讓前端不可能忘記傳。錯誤分層裁定「必填性可推 schema、值域不可」。
  # 授權：D42——庫存寫入走 `inventory.edit`，與 products.edit 分開。
  class InventoryAdjustQuantities < BaseMutation
    graphql_name "InventoryAdjustQuantities"
    description "以差額調整庫存數量（唯一寫入入口 Inventory::Adjust 的 adjust 模式）。"

    user_errors_type Types::Errors::InventoryAdjustUserErrorType

    argument :idempotency_key, String, required: true,
      description: "冪等鍵（G28：契約層必填）。failed 可同 key 重試（D41）。"
    argument :input, Types::Inputs::InventoryAdjustQuantitiesInput, required: true

    field :inventory_adjustment_group, Types::InventoryAdjustmentGroupType, null: true

    def resolve(idempotency_key:, input:)
      # G28 已讓 schema 層擋缺鍵；本呼叫是與全 mutation 靜態掃描一致的雙保險。
      enforce_idempotency_contract!(idempotency_key)
      authorize_inventory_edit!

      result = Inventory::Adjust.call(
        shop: context.fetch(:current_shop),
        mode: "adjust",
        input: input.to_h.merge(idempotency_key:),
        staff: context[:current_staff]
      )
      { inventory_adjustment_group: result.group, user_errors: result.user_errors }
    end

    private

    # D42：inventory.edit 與 products.edit 是分開的鍵；M1 全員 owner ⇒ can? 恆 true，
    # 但 policy 縫現在就分開，M5 RBAC 展開時不必回頭拆。
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
