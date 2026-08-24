# frozen_string_literal: true

module Types
  # staged 上傳目標（12 §D.7-1：url＋parameters＋resourceUrl）。
  class StagedUploadTargetType < Types::BaseObject
    graphql_name "StagedUploadTarget"
    description "兩段式上傳的目標：POST url 帶 parameters，完成後以 resourceUrl 呼叫 fileCreate。"

    field :url, String, null: false, description: "上傳端點（同源 POST multipart）。"
    field :parameters, [ StagedUploadParameterType ], null: false
    field :resource_url, String, null: false, description: "上傳完成後交給 fileCreate 的 originalSource。"
  end
end
