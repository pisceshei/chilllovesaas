# frozen_string_literal: true

module Mutations
  # 寄件人位址更新（G6 步 6；89 §1 Sender email 欄）。
  #
  # 值域：空字串＝清空（回 mailer 預設 no-reply）；格式閘＝URI::MailTo 正則。
  # ⚪ 官方的 sender 確認流／SPF·DKIM 提示（89 §6）後置。
  class NotificationSenderEmailUpdate < BaseMutation
    graphql_name "NotificationSenderEmailUpdate"
    description "更新通知信寄件人位址（空字串＝清空、回平台預設）。"

    user_errors_type Types::Errors::NotificationTemplateUserErrorType

    argument :sender_email, String, required: true

    field :sender_email, String, null: true

    def resolve(sender_email:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      value = sender_email.strip.presence
      if value && !value.match?(URI::MailTo::EMAIL_REGEXP)
        return { sender_email: shop.sender_email,
                 user_errors: [ { field: [ "senderEmail" ],
                                  message: "email 格式不正確。", code: "INVALID" } ] }
      end

      shop.update!(sender_email: value)
      { sender_email: value, user_errors: [] }
    end

    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end
  end
end
