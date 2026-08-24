# frozen_string_literal: true

module Types
  # staged 上傳的一組簽名參數（12 §D.7-1 的 parameters 鍵值對）。
  class StagedUploadParameterType < Types::BaseObject
    graphql_name "StagedUploadParameter"
    description "上傳表單要附帶的一組參數。"

    field :name, String, null: false
    field :value, String, null: false
  end
end
