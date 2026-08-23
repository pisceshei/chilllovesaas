# frozen_string_literal: true

module Types
  # 某資源在某語言的翻譯進度（ML-2）。鐵律 7：所有進度數字只從 `translation_status` 來，
  # 編輯頁徽章／列表欄／設定頁總覽不得各自 GROUP BY。
  class TranslationStatusType < BaseObject
    graphql_name "TranslationStatus"
    description "資源在某語言的翻譯進度。"

    field :locale, String, null: false
    field :required_fields, Integer, null: false, description: "必翻欄位數（title／body_html）。"
    field :translated_fields, Integer, null: false
    field :outdated_count, Integer, null: false
    field :review_pending, Integer, null: false
    field :complete, Boolean, null: false, description: "必翻齊全且無過期。"

    # @return [String] BCP-47 標籤
    def locale = object.locale_tag

    # @return [Boolean]
    def complete = object.complete?
  end
end
