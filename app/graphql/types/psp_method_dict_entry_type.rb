# frozen_string_literal: true

module Types
  # 平台層 method 字典項（G6-3 分層：字典平台層、白名單租戶層；來源＝limits
  # `psp_method_dictionary`，前端不得另存副本——drift 即白名單複驗失效）。
  class PspMethodDictEntryType < Types::BaseObject
    graphql_name "PspMethodDictEntry"
    description "PSP method 字典項（code＝pack 字典碼；label＝品牌顯示名）。"

    field :code, String, null: false
    field :label, String, null: false

    def code = object[:code].to_s
    def label = object[:label].to_s
  end
end
