# frozen_string_literal: true

module Types
  # 部落格文章（步 14a；98 §3——author/summary 對齊官方欄語義）。
  class ArticleType < BaseObject
    graphql_name "Article"
    description "部落格文章。"

    field :author_name, String, null: true, description: "顯示名（官方 ArticleAuthor.name 對位）。"
    field :blog_id, ID, null: false
    field :body, String, null: false
    field :comments_count, Integer, null: false, description: "已發布留言數。"
    field :handle, String, null: false, description: "裸 handle（Admin 層；Liquid 層是 blog/article 複合形——98 §1）。"
    field :id, ID, null: false, description: "gid://chilllove/Article/{id}"
    field :is_published, Boolean, null: false
    field :pending_comments_count, Integer, null: false, description: "待審留言數（admin Manage comments 徽章）。"
    field :published_at, GraphQL::Types::ISO8601DateTime, null: true
    field :summary, String, null: true, description: "摘要 HTML（官方 summary；Liquid excerpt）。"
    field :tags, [ String ], null: false
    field :template_suffix, String, null: true
    field :title, String, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def id = "gid://chilllove/Article/#{object.id}"
    def blog_id = "gid://chilllove/Blog/#{object.blog_id}"
    def body = object.body_html
    def summary = object.excerpt_html
    def tags = object.tags.to_a
    def is_published = object.visible?
    def comments_count = object.published_comments.count
    def pending_comments_count = object.article_comments.where(status: "pending").count
  end
end
