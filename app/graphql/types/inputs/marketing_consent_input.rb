# frozen_string_literal: true

module Types
  module Inputs
    # 行銷同意輸入（官方 CustomerEmailMarketingConsentInput／Sms 同形合併；
    # marketingState 可寫三值＝官方逐字 "Accepted values: SUBSCRIBED, UNSUBSCRIBED,
    # and PENDING."）。
    class MarketingConsentInput < GraphQL::Schema::InputObject
      graphql_name "MarketingConsentInput"
      description "行銷同意（state 可寫三值；consentUpdatedAt 缺值＝當下，latest-wins）"

      argument :marketing_state, String, required: true
      argument :marketing_opt_in_level, String, required: false
      argument :consent_updated_at, GraphQL::Types::ISO8601DateTime, required: false
    end
  end
end
