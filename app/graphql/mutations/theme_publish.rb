# frozen_string_literal: true

module Mutations
  # 發布主題（包 30／D77）。
  #
  # 本尊對位＝`themePublish(id: ID!)`，描述逐字：`Publishes a theme.`
  # （取證 2026-08-30）。回傳 `theme` ＋ `userErrors`。
  # 單一發布不變量在 `Theme#publish!`（DB 產生欄＋唯一索引雙保險）。
  class ThemePublish < BaseMutation
    graphql_name "ThemePublish"
    description "發布主題（現任已發布者自動降回草稿；同交易）。"

    user_errors_type Types::Errors::ThemePublishUserErrorType

    argument :id, ID, required: true, description: "主題的 GID。"

    field :theme, Types::ThemeType, null: true

    # @return [Hash]
    # @note 副作用：至多兩列 themes UPDATE（Theme#publish!）。
    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)

      legacy_id = id.to_s[%r{\Agid://chilllove/Theme/(\d+)\z}, 1]
      theme = legacy_id && ActsAsTenant.with_tenant(shop) { Theme.find_by(id: legacy_id.to_i) }
      unless theme
        return { theme: nil, user_errors: [ {
          field: [ "id" ], message: I18n.t("errors.theme.not_found"), code: "NOT_FOUND"
        } ] }
      end

      # 🔴 發布無檔案來源的主題＝前台整站不可渲染 ⇒ fail-closed（ours，enum 有註）。
      if ThemeEngine::Sources.resolve(theme).nil?
        return { theme: nil, user_errors: [ {
          field: [ "id" ], message: I18n.t("errors.theme.source_missing"), code: "SOURCE_MISSING"
        } ] }
      end

      ActsAsTenant.with_tenant(shop) { theme.publish! }
      { theme: theme, user_errors: [] }
    end
  end
end
