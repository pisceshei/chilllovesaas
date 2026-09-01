# frozen_string_literal: true

module Mutations
  # 更新部落格文章（官方 articleUpdate；redirectNewHandle 建複合路徑 301——98 §3）。
  class ArticleUpdate < BaseContentMutation
    graphql_name "ArticleUpdate"
    description "更新部落格文章。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :author_name, String, required: false
    argument :body, String, required: false
    argument :handle, String, required: false
    argument :id, ID, required: true
    argument :is_published, Boolean, required: false
    argument :publish_date, GraphQL::Types::ISO8601DateTime, required: false
    argument :redirect_new_handle, Boolean, required: false, default_value: false
    argument :summary, String, required: false
    argument :tags, [ String ], required: false
    argument :template_suffix, String, required: false
    argument :title, String, required: false

    field :article, Types::ArticleType, null: true

    def resolve(id:, redirect_new_handle:, **attrs)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        article = find_by_gid(id, Article, shop)
        return { article: nil }.merge(invalid("id", "找不到文章。", "NOT_FOUND")) if article.nil?

        old_handle = article.handle
        article.title = attrs[:title] if attrs.key?(:title)
        article.body_html = attrs[:body] if attrs.key?(:body)
        article.excerpt_html = attrs[:summary] if attrs.key?(:summary)
        article.author_name = attrs[:author_name] if attrs.key?(:author_name)
        article.tags = Array(attrs[:tags]) if attrs.key?(:tags)
        article.handle = attrs[:handle] if attrs[:handle].present?
        article.template_suffix = attrs[:template_suffix] if attrs.key?(:template_suffix)
        if attrs.key?(:is_published) || attrs.key?(:publish_date)
          article.published_at = resolve_published_at(attrs[:is_published], attrs[:publish_date],
                                                      current: article.published_at)
        end
        begin
          article.save!
        rescue ActiveRecord::RecordNotUnique
          return { article: nil }.merge(invalid("handle", "此 handle 已被使用。", "TAKEN"))
        rescue ActiveRecord::RecordInvalid
          return { article: nil }.merge(invalid(nil, article.errors.full_messages.first.to_s, "INVALID"))
        end
        if redirect_new_handle && article.handle != old_handle
          blog_handle = article.blog.handle
          begin
            UrlRedirect.create!(shop_id: shop.id,
                                from_path: "/blogs/#{blog_handle}/#{old_handle}",
                                to_path: "/blogs/#{blog_handle}/#{article.handle}",
                                status_code: 301, source: "handle_change")
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
            nil
          end
        end
        { article:, user_errors: [] }
      end
    end
  end
end
