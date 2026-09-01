# frozen_string_literal: true

module Mutations
  # 更新導覽選單（官方 menuUpdate：**整棵替換不是合併**——98 §3 語義）。
  class MenuUpdate < BaseContentMutation
    graphql_name "MenuUpdate"
    description "更新導覽選單（items 整棵替換）。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :handle, String, required: false
    argument :id, ID, required: true
    argument :items, [ Types::Inputs::MenuItemInputType ], required: true
    argument :title, String, required: false

    field :menu, Types::MenuType, null: true

    def resolve(id:, items:, title: nil, handle: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        menu = find_by_gid(id, Menu, shop)
        return { menu: nil }.merge(invalid("id", "找不到選單。", "NOT_FOUND")) if menu.nil?

        if handle.present? && handle != menu.handle && Menu::DEFAULT_HANDLES.include?(menu.handle)
          return { menu: nil }.merge(invalid("handle", "預設選單的 handle 不可修改。",
                                             "DEFAULT_MENU_PROTECTED"))
        end

        result = Content::SaveMenu.call(shop:, menu:, title: title || menu.title,
                                        handle: handle.presence || menu.handle,
                                        items: items.map(&:to_h))
        return { menu: nil }.merge(invalid(*result.error)) if result.error

        { menu: result.menu, user_errors: [] }
      end
    end
  end
end
