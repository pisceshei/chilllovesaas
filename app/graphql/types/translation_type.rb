# frozen_string_literal: true

module Types
  # 一條譯文的讀取面（ML-2）。稽核欄一併回，前端據以顯示「原文已更新／待覆核」徽章。
  class TranslationType < BaseObject
    graphql_name "Translation"
    description "資源在某語言、某欄位的譯文。"

    field :locale, String, null: false
    field :field, String, null: false
    field :value, String, null: false
    field :outdated, Boolean, null: false,
      description: "來源文字已變更（67 §C.5）；**不影響前台渲染**，只驅動後台提示。"
    field :outdated_severity, String, null: false, description: "none / minor / major。"
    field :value_source, String, null: false, description: "human / machine / script_conversion / import。"
    field :review_required, Boolean, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    # @return [String] BCP-47 標籤
    def locale = object.locale_tag

    # @return [String] 欄位鍵
    def field = object.field_key
  end
end
