# frozen_string_literal: true

module Psp
  # provider 列的 capability 同步（G6-1b；使用者裁定「配置成功後自動讀取已申請好的
  # 付款方式」的落點）。
  #
  # 語義（15-F4.2 ＋「清單變動回退」必測的守法）：
  #   ①`available_methods` ＝ PSP 回報的 active oneoff 名（原樣快取）；
  #   ②🔴 **首次成功同步自動全開**：`enabled_methods`＝字典 ∩ available——「配置成功
  #     ⇒ 帳號開通的方式自動出現」；
  #   ③其後同步**不覆蓋商家手動關閉**（enabled 是商家白名單，不是鏡像）；
  #   ④🔴 任何一次同步都會把**已不可用**的方式從 enabled 移除（PSP 收不了的方式
  #     不得留在白名單——F4.2 清單移除回退）。
  #
  # 🔴 外部 IO 在任何 DB 交易之外（鐵律 5）；只支援 airwallex（paypal 隨 G6-2）。
  module ProviderCapabilities
    Unsupported = Class.new(StandardError)

    module_function

    # @param record [ShopPaymentProvider]
    # @param transport [#call, nil] specs 注入
    # @return [ShopPaymentProvider] 已同步並存檔的列
    # @raise [Airwallex::Client::Unauthorized, Airwallex::Client::Error, Unsupported]
    def sync!(record, transport: nil)
      raise Unsupported, "capability 同步目前只支援 airwallex（paypal 隨 G6-2）" unless record.provider == "airwallex"

      names = Airwallex::PaymentMethodTypes.fetch(record, transport:)
      first_sync = record.capabilities_synced_at.nil?

      record.available_methods = names
      dictionary = ShopPaymentProvider.method_dictionary(record.provider).map { |m| m[:code].to_s }
      record.enabled_methods = (dictionary & names) if first_sync
      record.enabled_methods = record.enabled_methods & names
      record.capabilities_synced_at = Time.current
      record.save!
      record
    end
  end
end
