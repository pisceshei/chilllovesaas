# frozen_string_literal: true

module Mutations
  # 刪除重導（包 36；API 形對齊本尊 urlRedirectDelete）。
  #
  # 🔴 handle_change 列**允許刪除**（62 §F.3／HDL-8：「除非商家已刪該 301」——
  #   刪除正是官方允許商家釋放舊 handle 的動作；刪後舊 handle 可重用）。
  class UrlRedirectDelete < BaseMutation
    graphql_name "UrlRedirectDelete"
    description "刪除一筆重導。"

    user_errors_type Types::Errors::UrlRedirectUserErrorType

    argument :id, ID, required: true

    field :deleted_url_redirect_id, ID, null: true, description: "被刪除的重導 GID；失敗時為 null。"

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      ActsAsTenant.with_tenant(shop) do
        record = UrlRedirect.find_by(id: id.to_s[%r{\Agid://chilllove/UrlRedirect/(\d+)\z}, 1])
        if record.nil?
          return { deleted_url_redirect_id: nil,
                   user_errors: [ { field: [ "id" ], message: "找不到此重導。", code: "NOT_FOUND" } ] }
        end

        record.destroy!
        { deleted_url_redirect_id: "gid://chilllove/UrlRedirect/#{record.id}", user_errors: [] }
      end
    end

    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end
  end
end
