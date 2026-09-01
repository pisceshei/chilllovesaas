# frozen_string_literal: true

module Mutations
  # 主題改名（官方 themeUpdate 的 name 面——99 §1；41 §634 動作選單 Rename）。
  class ThemeRename < BaseMutation
    graphql_name "ThemeRename"
    description "重新命名主題。"

    user_errors_type Types::Errors::ThemeManageUserErrorType

    argument :id, ID, required: true
    argument :name, String, required: true

    field :theme, Types::ThemeType, null: true

    def resolve(id:, name:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        theme = find_theme(id, shop)
        return { theme: nil }.merge(invalid("id", "找不到主題。", "NOT_FOUND")) if theme.nil?
        if name.strip.blank? || name.strip.length > Limits.fetch(:theme_import, :theme_name_max)
          return { theme: nil }.merge(invalid("name", "名稱必填且 ≤#{Limits.fetch(:theme_import, :theme_name_max)} 字元（官方上限）。", "INVALID"))
        end

        begin
          theme.update!(name: name.strip)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          return { theme: nil }.merge(invalid("name", "同名主題已存在。", "TAKEN"))
        end
        { theme:, user_errors: [] }
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
