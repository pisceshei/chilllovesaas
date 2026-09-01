# frozen_string_literal: true

module Mutations
  # 建立部落格（官方 blogCreate——98 §3；commentPolicy 預設 CLOSED＝admin Disabled）。
  class BlogCreate < BaseContentMutation
    graphql_name "BlogCreate"
    description "建立部落格。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :comment_policy, Types::CommentPolicyType, required: false, default_value: "closed"
    argument :handle, String, required: false
    argument :template_suffix, String, required: false
    argument :title, String, required: true

    field :blog, Types::BlogType, null: true

    def resolve(title:, comment_policy:, handle: nil, template_suffix: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        return { blog: nil }.merge(invalid("title", "標題必填。", "BLANK")) if title.blank?

        resolved_handle, err = unique_handle(Blog.where(shop_id: shop.id), title, handle,
                                             resource: "blog")
        return { blog: nil }.merge(invalid("handle", err, "INVALID")) if err

        blog = Blog.new(shop_id: shop.id, title:, handle: resolved_handle,
                        comment_policy:, template_suffix:)
        begin
          blog.save!
        rescue ActiveRecord::RecordNotUnique
          return { blog: nil }.merge(invalid("handle", "此 handle 已被使用。", "TAKEN"))
        rescue ActiveRecord::RecordInvalid
          return { blog: nil }.merge(invalid(nil, blog.errors.full_messages.first.to_s, "INVALID"))
        end
        { blog:, user_errors: [] }
      end
    end
  end
end
