# frozen_string_literal: true

module Notifications
  # 平台模板字典（G6 步 6；89 §3/§7）。
  #
  # ①這是什麼：模板 key → 預設 subject＋預設 body 檔的註冊表。**平台字典層**
  #   （無租戶資料，隨版本部署）；租戶覆寫在 notification_templates 表。
  # ②key 對位本尊 email_templates URL key（89 §3 實測）；abandoned_checkout
  #   去 `_notification` 尾綴＝ours 簡化（89 §7.1）。
  # ③預設 subject＝本尊 edit 頁實測逐字（order_confirmation）／預覽渲染回推
  #   （另兩支——渲染值 #9999 回推成 {{ name }} 形；89 §3 表）。
  # ④預設 body＝自寫（鐵律 9 不抄本尊模板代碼）；變數名照 89 §5 官方契約
  #   （order 屬性**攤平**、fulfillment 帶前綴、棄單恢復連結＝裸 url）。
  module Catalog
    Entry = Data.define(:kind, :default_subject, :default_name, :title_key)

    ENTRIES = {
      "order_confirmation" => Entry.new(
        kind: "order_confirmation",
        default_subject: "Order {{ name }} confirmed",
        default_name: "Order confirmation",
        title_key: "settings.notifications.kind.orderConfirmation"
      ),
      "shipping_confirmation" => Entry.new(
        kind: "shipping_confirmation",
        default_subject: "A shipment from order {{ name }} is on the way",
        default_name: "Shipping confirmation",
        title_key: "settings.notifications.kind.shippingConfirmation"
      ),
      "abandoned_checkout" => Entry.new(
        kind: "abandoned_checkout",
        default_subject: "Complete your Purchase",
        default_name: "Abandoned checkout",
        title_key: "settings.notifications.kind.abandonedCheckout"
      ),
      # 步 11：登入驗證碼（74 §7 passwordless；訂閱主題不可自訂主旨中的 code 變數）。
      "customer_otp" => Entry.new(
        kind: "customer_otp",
        default_subject: "Your login code",
        default_name: "Customer login code",
        title_key: "settings.notifications.kind.customerOtp"
      )
    }.freeze

    KINDS = ENTRIES.keys.freeze

    # @param kind [String]
    # @return [Entry]
    def self.entry(kind) = ENTRIES.fetch(kind)

    # 預設 body（config/notification_templates/<kind>.liquid；deploy 產物、非租戶資料）。
    #
    # @return [String]
    def self.default_body(kind)
      entry(kind) # 值域守衛（未知 kind fail-fast，不落 File.read 任意路徑）
      Rails.root.join("config", "notification_templates", "#{kind}.liquid").read
    end
  end
end
