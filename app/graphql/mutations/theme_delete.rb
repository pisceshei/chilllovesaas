# frozen_string_literal: true

module Mutations
  # 主題刪除（官方："delete an unpublished theme"——已發布主題拒刪，99 §1；
  # help：已發布主題須先發布別的主題）。storage 目錄不刪（同內容共享——91 §3.66）。
  class ThemeDelete < BaseMutation
    graphql_name "ThemeDelete"
    description "刪除未發布主題。"

    user_errors_type Types::Errors::ThemeManageUserErrorType

    argument :id, ID, required: true

    field :deleted_theme_id, ID, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        theme = find_theme(id, shop)
        return { deleted_theme_id: nil }.merge(invalid("id", "找不到主題。", "NOT_FOUND")) if theme.nil?

        if theme.role == "published"
          return { deleted_theme_id: nil }.merge(invalid("id",
            "已發布主題不可刪除——先發布另一個主題（官方行為）。", "PUBLISHED_THEME_PROTECTED"))
        end

        theme.destroy!
        { deleted_theme_id: id, user_errors: [] }
      end
    end

    private

    def authorized_shop!
      unless ThemePolicy.new(context[:current_staff], Theme).index?
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def find_theme(gid, shop)
      numeric = gid.to_s[%r{\Agid://chilllove/Theme/(\d+)\z}, 1]
      numeric && Theme.find_by(shop_id: shop.id, id: numeric)
    end

    def invalid(field, message, code)
      { user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
