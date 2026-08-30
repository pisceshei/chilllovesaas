# frozen_string_literal: true

module Types
  # 路徑級重導（包 36；62 §B.5）。API 欄名對齊本尊 `UrlRedirect`（path/target——
  # naming_contract.api_field_names）；`source` 是我方加欄（自己命名，§H.5(c)）。
  class UrlRedirectType < BaseObject
    graphql_name "UrlRedirect"
    description "路徑級 301 重導。"

    field :id, ID, null: false, description: "gid://chilllove/UrlRedirect/{id}"
    field :path, String, null: false, description: "來源路徑（無 locale 前綴正規形）。"
    field :source, String, null: false, description: "產生來源（handle_change／manual／domain_move／import）。"
    field :target, String, null: false, description: "目標路徑（無 locale 前綴正規形）。"

    def id = "gid://chilllove/UrlRedirect/#{object.id}"
    def path = object.from_path
    def target = object.to_path
  end
end
