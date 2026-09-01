# frozen_string_literal: true

module Mutations
  # 刪除自訂頁面（官方 pageDelete：永久刪——98 §3）。
  class PageDelete < BaseContentMutation
    graphql_name "PageDelete"
    description "永久刪除自訂頁面。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :id, ID, required: true

    field :deleted_page_id, ID, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        page = find_by_gid(id, Page, shop)
        return { deleted_page_id: nil }.merge(invalid("id", "找不到頁面。", "NOT_FOUND")) if page.nil?

        page.destroy!
        { deleted_page_id: id, user_errors: [] }
      end
    end
  end
end
