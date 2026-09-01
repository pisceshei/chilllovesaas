# frozen_string_literal: true

module Mutations
  # 更新自訂頁面（官方 pageUpdate；redirectNewHandle＝改 handle 自動建 301——98 §3）。
  class PageUpdate < BaseContentMutation
    graphql_name "PageUpdate"
    description "更新自訂頁面。"

    user_errors_type Types::Errors::ContentUserErrorType

    argument :body, String, required: false
    argument :handle, String, required: false
    argument :id, ID, required: true
    argument :is_published, Boolean, required: false
    argument :publish_date, GraphQL::Types::ISO8601DateTime, required: false
    argument :redirect_new_handle, Boolean, required: false, default_value: false
    argument :template_suffix, String, required: false
    argument :title, String, required: false

    field :page, Types::PageType, null: true

    def resolve(id:, redirect_new_handle:, **attrs)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        page = find_by_gid(id, Page, shop)
        return { page: nil }.merge(invalid("id", "找不到頁面。", "NOT_FOUND")) if page.nil?

        old_handle = page.handle
        page.title = attrs[:title] if attrs.key?(:title)
        page.body_html = attrs[:body] if attrs.key?(:body)
        page.handle = attrs[:handle] if attrs[:handle].present?
        page.template_suffix = attrs[:template_suffix] if attrs.key?(:template_suffix)
        if attrs.key?(:is_published) || attrs.key?(:publish_date)
          page.published_at = resolve_published_at(attrs[:is_published], attrs[:publish_date],
                                                   current: page.published_at)
        end
        begin
          page.save!
        rescue ActiveRecord::RecordNotUnique
          return { page: nil }.merge(invalid("handle", "此 handle 已被使用。", "TAKEN"))
        rescue ActiveRecord::RecordInvalid
          return { page: nil }.merge(invalid(nil, page.errors.full_messages.first.to_s, "INVALID"))
        end
        if redirect_new_handle && page.handle != old_handle
          create_handle_redirect(shop, "/pages/#{old_handle}", "/pages/#{page.handle}")
        end
        { page:, user_errors: [] }
      end
    end

    private

    # 官方 redirectNewHandle 語義；TAKEN（舊列已存在）靜默容忍——重導表舊 handle 永不回收。
    def create_handle_redirect(shop, from, to)
      UrlRedirect.create!(shop_id: shop.id, from_path: from, to_path: to,
                          status_code: 301, source: "handle_change")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end
  end
end
