# frozen_string_literal: true

module Mutations
  # 刪除部落格（官方 blogDelete；🔴 底下 articles 官方沉默 ⇒ 我方裁定＝連文章
  # 一併刪（dependent: :destroy）——98 §5-3，dev doc 登記）。
  class BlogDelete < BaseContentMutation
    graphql_name "BlogDelete"
    description "永久刪除部落格（含其文章與留言）。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :id, ID, required: true

    field :deleted_blog_id, ID, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        blog = find_by_gid(id, Blog, shop)
        return { deleted_blog_id: nil }.merge(invalid("id", "找不到部落格。", "NOT_FOUND")) if blog.nil?

        blog.destroy!
        { deleted_blog_id: id, user_errors: [] }
      end
    end
  end
end
