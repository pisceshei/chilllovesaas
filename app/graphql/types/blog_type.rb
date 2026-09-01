# frozen_string_literal: true

module Types
  # 部落格（步 14a；98 §3）。
  class BlogType < BaseObject
    graphql_name "Blog"
    description "部落格。"

    field :articles_count, Integer, null: false, description: "文章總數（含 Hidden——admin 計數）。"
    field :comment_policy, CommentPolicyType, null: false
    field :handle, String, null: false
    field :id, ID, null: false, description: "gid://chilllove/Blog/{id}"
    field :template_suffix, String, null: true
    field :title, String, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def id = "gid://chilllove/Blog/#{object.id}"
    def articles_count = object.articles.count
  end
end
