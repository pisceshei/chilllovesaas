# frozen_string_literal: true

module Types
  # 自訂頁面（步 14a；欄名對齊本尊 Page——98 §3）。
  class PageType < BaseObject
    graphql_name "Page"
    description "自訂頁面。"

    field :body, String, null: false, description: "頁面內文 HTML。"
    field :body_summary, String, null: false, description: "內文前 150 字（官方 bodySummary 語義）。"
    field :handle, String, null: false
    field :id, ID, null: false, description: "gid://chilllove/Page/{id}"
    field :is_published, Boolean, null: false, description: "當下是否可見（published_at ≤ now）。"
    field :published_at, GraphQL::Types::ISO8601DateTime, null: true,
      description: "可見起點；null＝Hidden（官方語義：Returns null when the page isn't visible）。"
    field :template_suffix, String, null: true
    field :title, String, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def id = "gid://chilllove/Page/#{object.id}"
    def body = object.body_html

    def body_summary
      text = ActionController::Base.helpers.strip_tags(object.body_html.to_s).strip
      text.length > 150 ? "#{text[0, 150]}…" : text
    end

    def is_published = object.published_at.present? && object.published_at <= Time.current
  end
end
