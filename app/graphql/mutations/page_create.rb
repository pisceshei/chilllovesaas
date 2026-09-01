# frozen_string_literal: true

module Mutations
  # 建立自訂頁面（步 14a；官方 pageCreate 對位——98 §3）。
  class PageCreate < BaseContentMutation
    graphql_name "PageCreate"
    description "建立自訂頁面。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :body, String, required: false, description: "內文 HTML。"
    argument :handle, String, required: false
    argument :is_published, Boolean, required: false,
      description: "官方語義：未給且無 publishDate ⇒ 發布。"
    argument :publish_date, GraphQL::Types::ISO8601DateTime, required: false
    argument :template_suffix, String, required: false
    argument :title, String, required: true

    field :page, Types::PageType, null: true

    def resolve(title:, body: nil, handle: nil, is_published: nil, publish_date: nil,
                template_suffix: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        return { page: nil }.merge(invalid("title", "標題必填。", "BLANK")) if title.blank?

        resolved_handle, err = unique_handle(Page.where(shop_id: shop.id), title, handle,
                                             resource: "page")
        return { page: nil }.merge(invalid("handle", err, "INVALID")) if err

        page = Page.new(shop_id: shop.id, title:, handle: resolved_handle,
                        body_html: body.to_s, template_suffix:,
                        published_at: create_published_at(is_published, publish_date))
        begin
          page.save!
        rescue ActiveRecord::RecordNotUnique
          return { page: nil }.merge(invalid("handle", "此 handle 已被使用。", "TAKEN"))
        rescue ActiveRecord::RecordInvalid
          return { page: nil }.merge(invalid(nil, page.errors.full_messages.first.to_s, "INVALID"))
        end
        { page:, user_errors: [] }
      end
    end
  end
end
