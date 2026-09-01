# frozen_string_literal: true

module Customers
  # 同意狀態轉移（G6 步 8a；官方兩支 consent mutation 的共同核心）。
  #
  # ①寫入面＝官方可寫三值（"Accepted values: SUBSCRIBED, UNSUBSCRIBED, and
  #   PENDING."——CustomerEmailMarketingConsentInput 逐字）；not_subscribed／
  #   redacted／invalid 唯讀（系統設定）。
  # ②前置＝official 逐字：email 線 "The customer must have an email address to
  #   update their consent."；SMS 線 "The customer must have a phone number on
  #   their account to receive SMS marketing."
  # ③合併＝latest-wins：consent_updated_at 較舊的寫入**照樣入事件表**（稽核），
  #   但不覆蓋快取（官方 "reflects the consent record with the most recent
  #   consent_updated_at date"）。缺值＝當下。
  # ④快取同步：customers.{channel}_marketing_state ＋ legacy boolean 對
  #   （G6-7 消費者仍讀 boolean——20.2② 同批不斷鏈）＋ email 線的 source/時間欄。
  class UpdateMarketingConsent
    Result = Data.define(:customer, :event, :error)

    class << self
      # @param source [String] checkout/admin/api
      # @return [Result]
      def call(shop:, customer:, channel:, state:, opt_in_level: nil,
               consent_updated_at: nil, source: "admin")
        state = state.to_s.downcase
        opt_in_level = opt_in_level&.to_s&.downcase
        unless CustomerMarketingConsent::WRITABLE_STATES.include?(state)
          return failure("state 只收 SUBSCRIBED/UNSUBSCRIBED/PENDING（官方可寫三值）。", "INCLUSION")
        end
        if opt_in_level && !CustomerMarketingConsent::OPT_IN_LEVELS.include?(opt_in_level)
          return failure("optInLevel 不在官方三值內。", "INCLUSION")
        end
        if channel == "email" && customer.email.blank?
          return failure("顧客沒有 email，無法更新 email 行銷同意（官方前置）。", "INVALID_STATE")
        end
        if channel == "sms" && customer.phone.blank?
          return failure("顧客沒有電話號碼，無法更新 SMS 行銷同意（官方前置）。", "INVALID_STATE")
        end

        timestamp = consent_updated_at || Time.current
        event = nil
        ActiveRecord::Base.transaction do
          event = CustomerMarketingConsent.create!(
            shop_id: shop.id, customer_id: customer.id, channel:, state:,
            opt_in_level:, consent_updated_at: timestamp, source:
          )
          apply_cache!(customer, channel, state, timestamp, source)
        end
        Result.new(customer: customer.reload, event:, error: nil)
      end

      private

      # latest-wins 投影：較舊的 consent_updated_at 不覆蓋快取。
      def apply_cache!(customer, channel, state, timestamp, source)
        latest = CustomerMarketingConsent
                 .where(shop_id: customer.shop_id, customer_id: customer.id, channel:)
                 .where("consent_updated_at > ?", timestamp).exists?
        return if latest

        if channel == "email"
          customer.update!(email_marketing_state: state,
                           email_marketing_consent: state == "subscribed",
                           email_marketing_consent_updated_at: timestamp,
                           email_marketing_consent_source: source)
        else
          customer.update!(sms_marketing_state: state,
                           sms_marketing_consent: state == "subscribed")
        end
      end

      def failure(message, code)
        Result.new(customer: nil, event: nil, error: [ message, code ])
      end
    end
  end
end
