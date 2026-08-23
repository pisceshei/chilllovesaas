# frozen_string_literal: true

module Types
  module Inputs
    # 一條譯文（docs/specs/67 §C.2；ML-2）。
    #
    # 🔴 形態是**逐欄位一列**，不是 `{locale: {title:…, body_html:…}}` 的 map——
    # map 形態承載不了六個稽核欄（outdated／value_source／review_required…），
    # 也毀掉欄位級 digest 與翻譯 CSV 的逐欄列（67 §E.2-1 硬規則 1）。
    class TranslationInput < GraphQL::Schema::InputObject
      graphql_name "TranslationInput"
      description "非來源語言的一條譯文。"

      argument :locale, String, required: true,
        description: "BCP-47 標籤；必須是該店已啟用語言，且不得等於來源語言。"
      argument :field, String, required: true,
        description: "可翻欄位：title / body_html / meta_title / meta_description。"
      argument :value, String, required: true,
        description: "譯文；空字串（或語義空 HTML）＝刪除該譯文列，前台回落來源語言。"
    end
  end
end
