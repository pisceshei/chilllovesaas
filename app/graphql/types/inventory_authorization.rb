module Types
  # 庫存讀取授權（D42：`inventory.view` 是與 `products.view` **分開的鍵**）。
  #
  # 🔴 抽成共用模組而不是各處各寫一份：第 29 包審查 R-1 抓到
  #   `ProductVariantType#inventory_levels` 掛在只受 `authorize_products!` 保護的
  #   `product(id:)` 之下 ⇒ 只有 `products.view` 的員工可繞過 `inventory.view`
  #   讀到全地點庫存明細、地點名稱與**可寫入的** `inventoryItemId`。
  #   庫存讀取面日後還會長在別的型別上（訂單、報表），每長一處就抄一次判斷式，
  #   遲早有一處抄漏——所以判準只留一份。
  #
  # M1 全員 owner ⇒ `can?` 恆 true，但縫現在就分開，M5 RBAC 展開時不必回頭拆。
  module InventoryAuthorization
    private

    # @raise [GraphQL::ExecutionError] 無 `inventory.view` 時（code＝ACCESS_DENIED）
    # @return [void]
    def authorize_inventory!
      staff = context[:current_staff]
      return if staff && (staff.owner? || staff.can?("inventory.view"))

      raise GraphQL::ExecutionError.new(
        I18n.t("errors.inventory.access_denied"),
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end
  end
end
