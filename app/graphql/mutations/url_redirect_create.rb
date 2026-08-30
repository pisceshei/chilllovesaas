# frozen_string_literal: true

module Mutations
  # 建立自訂重導（包 36；62 §B.5；API 形對齊本尊 urlRedirectCreate 的 path/target）。
  #
  # 🔴 存無前綴正規形（UrlRedirects::Normalize 檔頭的 DOC-5 裁定）；source 恆 manual。
  # 來源路徑撞既有列 ⇒ TAKEN（舊 handle 永不回收——包含 handle_change 產的列）。
  # 來源路徑是活資源 ⇒ 允許建立但**天然不生效**：301 引擎只在 404 之後查表，
  # 活頁面永遠先贏——不存在遮蔽窗，也因此不做跨表活性檢查（引擎註釋同記）。
  class UrlRedirectCreate < BaseMutation
    graphql_name "UrlRedirectCreate"
    description "建立自訂 301 重導。"

    user_errors_type Types::Errors::UrlRedirectUserErrorType

    argument :path, String, required: true, description: "來源路徑（無 locale 前綴）。"
    argument :target, String, required: true, description: "目標路徑（無 locale 前綴）。"

    field :url_redirect, Types::UrlRedirectType, null: true, description: "建立的重導；失敗時為 null。"

    def resolve(path:, target:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      normalized = UrlRedirects::Normalize.call(path:, target:)
      return invalid(*normalized.error) if normalized.error

      ActsAsTenant.with_tenant(shop) do
        record = UrlRedirect.new(from_path: normalized.path, to_path: normalized.target,
                                 status_code: 301, source: "manual")
        begin
          record.save!
        rescue ActiveRecord::RecordNotUnique
          return invalid("path", "此路徑已有重導（舊 handle 永不回收）。", "TAKEN")
        rescue ActiveRecord::RecordInvalid
          return invalid("path", record.errors.full_messages.first.to_s, "INVALID")
        end
        { url_redirect: record, user_errors: [] }
      end
    end

    private

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
