# frozen_string_literal: true

module Mutations
  # 建立部落格文章（官方 articleCreate：blogId!/title!/body!——98 §3）。
  class ArticleCreate < BaseContentMutation
    graphql_name "ArticleCreate"
    description "建立部落格文章。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :author_name, String, required: false
    argument :blog_id, ID, required: true
    argument :body, String, required: true
    argument :handle, String, required: false
    argument :is_published, Boolean, required: false
    argument :publish_date, GraphQL::Types::ISO8601DateTime, required: false
    argument :summary, String, required: false
    argument :tags, [ String ], required: false
    argument :template_suffix, String, required: false
    argument :title, String, required: true

    field :article, Types::ArticleType, null: true

    def resolve(blog_id:, title:, body:, author_name: nil, handle: nil, is_published: nil,
                publish_date: nil, summary: nil, tags: nil, template_suffix: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        blog = find_by_gid(blog_id, Blog, shop)
        return { article: nil }.merge(invalid("blogId", "找不到部落格。", "NOT_FOUND")) if blog.nil?
        return { article: nil }.merge(invalid("title", "標題必填。", "BLANK")) if title.blank?

        resolved_handle, err = unique_handle(Article.where(shop_id: shop.id, blog_id: blog.id),
                                             title, handle, resource: "article")
        return { article: nil }.merge(invalid("handle", err, "INVALID")) if err

        article = Article.new(shop_id: shop.id, blog:, title:, handle: resolved_handle,
                              body_html: body.to_s, excerpt_html: summary,
                              author_name:, tags: Array(tags), template_suffix:,
                              published_at: create_published_at(is_published, publish_date))
        begin
          article.save!
        rescue ActiveRecord::RecordNotUnique
          return { article: nil }.merge(invalid("handle", "此 handle 已被使用。", "TAKEN"))
        rescue ActiveRecord::RecordInvalid
          return { article: nil }.merge(invalid(nil, article.errors.full_messages.first.to_s, "INVALID"))
        end
        { article:, user_errors: [] }
      end
    end
  end
end
