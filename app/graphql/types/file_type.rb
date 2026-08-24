# frozen_string_literal: true

module Types
  # 檔案（表 files／model StoredFile——類名避開 Ruby core `File`，對外仍是 `File`）。
  class FileType < Types::BaseObject
    graphql_name "File"
    description "檔案庫的一個檔案。"

    field :id, ID, null: false, description: "GID（gid://chilllove/File/{id}）。"
    field :filename, String, null: false
    field :content_type, String, null: false
    field :byte_size, GraphQL::Types::BigInt, null: false
    field :status, FileStatusEnum, null: false
    field :alt, String, null: true, method: :alt_text
    field :url, String, null: false, description: "檔案讀出端點（admin 認證後可取）。"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    def id = "gid://chilllove/File/#{object.id}"

    def url = "/admin/files/#{object.id}/blob"
  end
end
