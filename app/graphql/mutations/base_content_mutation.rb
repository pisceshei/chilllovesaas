# frozen_string_literal: true

module Mutations
  # 內容線 mutation 共用底座（步 14a；98 §3 官方契約對齊）。
  #
  # ①權限＝登入態（settings 線同門檻——`settings.edit` 不在 RBAC 種子，細粒度隨 M5）。
  # ②可見性語義（官方 pageCreate 逐字對齊）：isPublished 未給且無 publishDate ⇒
  #   發布（"Defaults to `true` if no publish date is specified."）；publishDate
  #   給了 ⇒ 以該時刻為準（未來＝排程）；isPublished=false ⇒ NULL（Hidden）。
  # ③handle：顯式給 ⇒ 撞列回 TAKEN；未給 ⇒ HandleGenerator＋`-N` 尾碼唯一化
  #   （官方 "auto-incremented by one"——98 §6.4 逐字）。
  class BaseContentMutation < BaseMutation
    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    # GID → tenant-scoped record（customer_update 同構的正則法；型別名照類名）。
    def find_by_gid(gid, model, shop)
      numeric = gid.to_s[%r{\Agid://chilllove/#{model.name}/(\d+)\z}, 1]
      numeric && model.find_by(shop_id: shop.id, id: numeric)
    end

    def invalid(field, message, code)
      { user_errors: [ { field: field ? [ field ] : nil, message:, code: } ] }
    end

    # @return [Time, nil] published_at 終值（nil＝Hidden）
    def resolve_published_at(is_published, publish_date, current: nil)
      return Time.zone.parse(publish_date.to_s) if publish_date.present?
      return current || Time.current if is_published.nil? ? current.present? : is_published

      nil
    end

    # 建立語義（官方 default true）：兩者皆缺 ⇒ 立即發布。
    def create_published_at(is_published, publish_date)
      return Time.zone.parse(publish_date.to_s) if publish_date.present?

      is_published == false ? nil : Time.current
    end

    # @param scope [ActiveRecord::Relation] handle 唯一域（含 shop／blog 條件）
    def unique_handle(scope, title, explicit, resource:)
      return [ explicit.to_s, nil ] if explicit.present?

      base = Catalog::HandleGenerator.call(title.to_s, resource:).handle
      candidate = base
      1.step do |n|
        return [ candidate, nil ] unless scope.exists?(handle: candidate)
        return [ nil, "handle 唯一化重試超限" ] if n > 50

        candidate = "#{base}-#{n}"
      end
    end
  end
end
