# frozen_string_literal: true

module Mutations
  # 通知模板更新（G6 步 6；89 §4 編輯器兩欄＋Revert to default）。
  #
  # 語義：upsert 覆寫列；revertToDefault: true ⇒ 刪列（合併視圖回到平台預設）。
  # Liquid 語法錯誤在儲存時擋下（INVALID）——渲染期 :lax 容錯是第二道，
  # 但明知壞的模板不該落庫。
  class NotificationTemplateUpdate < BaseMutation
    graphql_name "NotificationTemplateUpdate"
    description "更新通知模板（subject＋bodyLiquid；revertToDefault ⇒ 回平台預設）。"

    user_errors_type Types::Errors::NotificationTemplateUserErrorType

    argument :key, String, required: true, description: "模板 key（89 §3；如 order_confirmation）"
    argument :subject, String, required: false
    argument :body_liquid, String, required: false
    argument :revert_to_default, Boolean, required: false

    field :notification_template, Types::NotificationTemplateType, null: true

    def resolve(key:, subject: nil, body_liquid: nil, revert_to_default: false)
      kind = key
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      unless Notifications::Catalog::KINDS.include?(kind)
        return error("key", "未知的通知模板。", "NOT_FOUND")
      end

      if revert_to_default
        ActsAsTenant.with_tenant(shop) do
          NotificationTemplate.where(channel: "email", key: kind).delete_all
        end
        return { notification_template: merged_view(shop, kind), user_errors: [] }
      end

      entry = Notifications::Catalog.entry(kind)
      overlay = ActsAsTenant.with_tenant(shop) do
        NotificationTemplate.find_by(channel: "email", key: kind)
      end
      next_subject = subject.nil? ? (overlay&.subject || entry.default_subject) : subject
      next_body = body_liquid.nil? ? (overlay&.body || Notifications::Catalog.default_body(kind)) : body_liquid

      return error("subject", "主旨不可空白。", "BLANK") if next_subject.blank?
      return error("bodyLiquid", "內文不可空白。", "BLANK") if next_body.blank?

      syntax_error = liquid_error(next_subject) || liquid_error(next_body)
      return error("bodyLiquid", "Liquid 語法錯誤：#{syntax_error}", "INVALID") if syntax_error

      ActsAsTenant.with_tenant(shop) do
        row = overlay || NotificationTemplate.new(shop_id: shop.id, channel: "email", key: kind,
                                                  name: entry.default_name)
        row.update!(subject: next_subject, body: next_body)
      end
      { notification_template: merged_view(shop, kind), user_errors: [] }
    end

    private

    def merged_view(shop, kind)
      overlay = ActsAsTenant.with_tenant(shop) do
        NotificationTemplate.find_by(channel: "email", key: kind)
      end
      entry = Notifications::Catalog.entry(kind)
      {
        key: kind,
        subject: overlay&.subject || entry.default_subject,
        body_liquid: overlay&.body || Notifications::Catalog.default_body(kind),
        is_default: overlay.nil?
      }
    end

    # 儲存期語法檢查：strict parse；錯誤訊息回給編輯器。
    def liquid_error(source)
      Liquid::Template.parse(source, error_mode: :strict)
      nil
    rescue Liquid::SyntaxError => e
      e.message[0, 200]
    end

    def error(field, message, code)
      { notification_template: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end

    # 登入態即可（與 shopPaymentProviderSet 同門檻：settings 細粒度權限隨 M5 RBAC）。
    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end
  end
end
