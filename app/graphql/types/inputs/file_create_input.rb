# frozen_string_literal: true

module Types
  module Inputs
    # fileCreate 的單檔輸入（12 §C.7:87）。
    class FileCreateInput < GraphQL::Schema::InputObject
      graphql_name "FileCreateInput"
      description "以 originalSource 建立一個檔案。"

      argument :original_source, String, required: true,
        description: "staged resourceUrl 或外部 http(s) URL（外部路徑過 SSRF 防線）。"
      argument :alt, String, required: false
      argument :filename, String, required: false, description: "覆寫檔名；預設取自來源。"
      argument :duplicate_resolution_mode, Types::DuplicateResolutionModeEnum, required: false,
        description: "撞名解法；預設 limits media.duplicate_resolution_mode_default（APPEND_UUID）。"
    end
  end
end
