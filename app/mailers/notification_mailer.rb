# frozen_string_literal: true

# 通知信 mailer（G6 步 6；89 號 teardown）。
#
# ①這是什麼：全部顧客通知信的單一出口。模板（overlay→預設）→ Renderer → html mail。
# ②From＝shop.sender_email（89 §6 官方語義），未設定 ⇒ no-reply@<base_host>。
# ③🔴 不做外部 IO 以外的事：payload 由呼叫端（DeliverJob）建好傳入，
#   mailer 只渲染與寄送——測試可對 payload 斷言而不 stub SMTP。
class NotificationMailer < ApplicationMailer
  # @param shop_id [Integer]
  # @param kind [String] Notifications::Catalog::KINDS
  # @param to [String]
  # @param payload [Hash]
  def notify(shop_id:, kind:, to:, payload:)
    shop = Shop.find(shop_id)
    result = ActsAsTenant.with_tenant(shop) do
      Notifications::Renderer.render(shop:, kind:, payload:)
    end

    mail(to:, from: sender_for(shop), subject: result.subject) do |format|
      format.html { render html: result.html.html_safe, layout: false }
    end
  end

  private

  def sender_for(shop)
    shop.sender_email.presence || "no-reply@#{Chilllove::TenantResolver.base_host}"
  end
end
