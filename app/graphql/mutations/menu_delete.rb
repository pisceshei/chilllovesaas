# frozen_string_literal: true

module Mutations
  # 刪除導覽選單（官方："Default menu cannot be deleted."——98 §3）。
  class MenuDelete < BaseContentMutation
    graphql_name "MenuDelete"
    description "刪除導覽選單。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :id, ID, required: true

    field :deleted_menu_id, ID, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        menu = find_by_gid(id, Menu, shop)
        return { deleted_menu_id: nil }.merge(invalid("id", "找不到選單。", "NOT_FOUND")) if menu.nil?

        if Menu::DEFAULT_HANDLES.include?(menu.handle)
          return { deleted_menu_id: nil }.merge(invalid("id", "預設選單不可刪除。",
                                                        "DEFAULT_MENU_PROTECTED"))
        end

        menu.destroy!
        { deleted_menu_id: id, user_errors: [] }
      end
    end
  end
end
