# frozen_string_literal: true

module Mutations
  # 更新自訂重導（包 36；API 形對齊本尊 urlRedirectUpdate）。
  #
  # 🔴 只許改 manual 列：handle_change 列由鏈坍縮不變量維護（HandleChange），
  #   人手改它會把「A→B、B 改名 C 時改寫 A→C」的自動維護破口打開 ⇒ NOT_EDITABLE。
  class UrlRedirectUpdate < BaseMutation
    graphql_name "UrlRedirectUpdate"
    description "更新自訂 301 重導。"

    user_errors_type Types::Errors::UrlRedirectUserErrorType

    argument :id, ID, required: true
    argument :path, String, required: true
    argument :target, String, required: true

    field :url_redirect, Types::UrlRedirectType, null: true

    def resolve(id:, path:, target:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      normalized = UrlRedirects::Normalize.call(path:, target:)
      return invalid(*normalized.error) if normalized.error

      ActsAsTenant.with_tenant(shop) do
        record = UrlRedirect.find_by(id: legacy_id(id))
        return invalid("id", "找不到此重導。", "NOT_FOUND") if record.nil?
        return invalid("id", "系統產生的重導不可手動修改。", "NOT_EDITABLE") unless record.source == "manual"

        begin
          record.update!(from_path: normalized.path, to_path: normalized.target)
        rescue ActiveRecord::RecordNotUnique
          return invalid("path", "此路徑已有重導（舊 handle 永不回收）。", "TAKEN")
        rescue ActiveRecord::RecordInvalid
          return invalid("path", record.errors.full_messages.first.to_s, "INVALID")
        end
        { url_redirect: record, user_errors: [] }
      end
    end

    private

    def legacy_id(gid)
      gid.to_s[%r{\Agid://chilllove/UrlRedirect/(\d+)\z}, 1]
    end

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def invalid(field, message, code)
      { url_redirect: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
