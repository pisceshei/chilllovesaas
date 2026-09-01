# frozen_string_literal: true

module Mutations
  # 主題檔案覆寫列刪除（步 16e3）。語義雙形（UI 依 overlayState 標示）：
  # - base 檔被覆寫 ⇒ 刪列＝**還原原始版本**（本尊 Timeline restore 的近似）；
  # - overlay-only 新檔 ⇒ 刪列＝**刪除檔案**。
  # 🔴 兩形都必 touch theme（步 2 紅字）；base 檔本體不可刪（tombstone＝91 §3.71 ⚪）。
  class ThemeFileDelete < BaseMutation
    graphql_name "ThemeFileDelete"
    description "刪除主題檔案覆寫列（被覆寫檔＝還原原始版本；新檔＝刪除）。"

    user_errors_type Types::Errors::ThemeManageUserErrorType

    argument :path, String, required: true
    argument :theme_id, ID, required: true

    field :path, String, null: true

    def resolve(theme_id:, path:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        theme = find_theme(theme_id, shop)
        return failure("themeId", "找不到主題。", "NOT_FOUND") if theme.nil?

        row = ThemeFileOverlay.find_by(shop_id: shop.id, theme_id: theme.id, path:)
        return failure("path", "此檔沒有覆寫版本可還原／刪除。", "NOT_FOUND") if row.nil?

        row.destroy!
        # 🔴 頁快取鍵旋轉（步 2 紅字）：還原／刪除同樣改變渲染輸出。
        theme.touch

        { path:, user_errors: [] }
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

    def failure(field, message, code)
      { path: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
