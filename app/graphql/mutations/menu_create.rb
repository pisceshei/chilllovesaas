# frozen_string_literal: true

module Mutations
  # 建立導覽選單（官方 menuCreate：title!/handle!/items!——98 §3）。
  class MenuCreate < BaseContentMutation
    graphql_name "MenuCreate"
    description "建立導覽選單。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :handle, String, required: true
    argument :items, [ Types::Inputs::MenuItemInputType ], required: true
    argument :title, String, required: true

    field :menu, Types::MenuType, null: true

    def resolve(title:, handle:, items:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        result = Content::SaveMenu.call(shop:, menu: nil, title:, handle:,
                                        items: items.map(&:to_h))
        return { menu: nil }.merge(invalid(*result.error)) if result.error

        { menu: result.menu, user_errors: [] }
      end
    end
  end
end
