# frozen_string_literal: true

module Mutations
  # 更新部落格（官方 blogUpdate——98 §3）。
  class BlogUpdate < BaseContentMutation
    graphql_name "BlogUpdate"
    description "更新部落格。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :comment_policy, Types::CommentPolicyType, required: false
    argument :handle, String, required: false
    argument :id, ID, required: true
    argument :template_suffix, String, required: false
    argument :title, String, required: false

    field :blog, Types::BlogType, null: true

    def resolve(id:, **attrs)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        blog = find_by_gid(id, Blog, shop)
        return { blog: nil }.merge(invalid("id", "找不到部落格。", "NOT_FOUND")) if blog.nil?

        blog.title = attrs[:title] if attrs.key?(:title)
        blog.handle = attrs[:handle] if attrs[:handle].present?
        blog.comment_policy = attrs[:comment_policy] if attrs.key?(:comment_policy)
        blog.template_suffix = attrs[:template_suffix] if attrs.key?(:template_suffix)
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
