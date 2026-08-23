# frozen_string_literal: true

module Mutations
  # 更新**目前員工**的介面語言（docs/specs/67 §E.1：介面語言＝員工屬性、平台 bundle）。
  #
  # - 只改自己（`context[:current_staff]`），不收 staff id——改別人的介面語言不是這支的事。
  # - 值域＝`limits.yml` `i18n.admin.ui_locales`（鐵律 6），不合法回 `INVALID`。
  # - 不需要 idempotencyKey：純覆寫、天然冪等（`limits.idempotency.required_for` 不含本支）；
  #   仍照 MutationType 義務①呼叫 `enforce_idempotency_contract!`（靜態掃描兜底）。
  #
  # @see docs/plans/2026-08-23-多語言方案.md §5.1
  class StaffLocaleUpdate < BaseMutation
    graphql_name "StaffLocaleUpdate"
    description "更新目前員工的 admin 介面語言。"

    user_errors_type Types::Errors::StaffLocaleUpdateUserErrorType

    argument :locale, String, required: true,
      description: "BCP-47 介面語言標籤（平台支援清單：i18n.admin.ui_locales）。"

    field :locale, String, null: true, description: "更新後的介面語言；失敗時為 null。"

    def resolve(locale:)
      enforce_idempotency_contract!(nil)
      staff = context[:current_staff]
      unless staff
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      normalized = Locales::Tag.normalize(locale)
      allowed = Limits.fetch(:i18n, :admin, :ui_locales).map(&:to_s)
      unless allowed.include?(normalized)
        return { locale: nil, user_errors: [ { field: [ "locale" ], message: I18n.t("errors.staff.locale_unsupported"), code: "INVALID" } ] }
      end

      staff.update!(locale: normalized)
      { locale: normalized, user_errors: [] }
    end
  end
end
