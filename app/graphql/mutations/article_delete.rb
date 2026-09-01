# frozen_string_literal: true

module Mutations
  # 刪除部落格文章（官方 articleDelete：永久刪——98 §3）。
  class ArticleDelete < BaseContentMutation
    graphql_name "ArticleDelete"
    description "永久刪除部落格文章。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :id, ID, required: true

    field :deleted_article_id, ID, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        article = find_by_gid(id, Article, shop)
        return { deleted_article_id: nil }.merge(invalid("id", "找不到文章。", "NOT_FOUND")) if article.nil?

        article.destroy!
        { deleted_article_id: id, user_errors: [] }
      end
    end
  end
end
