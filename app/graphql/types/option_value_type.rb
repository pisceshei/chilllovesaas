# frozen_string_literal: true

# GraphQL schema type 的 namespace。
module Types
  # 選項值（第 21 包讀取面；D12：值的身分是 id，譯文與 digest 都掛在 id 上）。
  class OptionValueType < BaseObject
    field :id, ID, null: false, description: "GID：gid://chilllove/OptionValue/{id}"
    field :position, Integer, null: false
    field :value, String, null: false

    def id = "gid://chilllove/OptionValue/#{object.id}"
  end
end
