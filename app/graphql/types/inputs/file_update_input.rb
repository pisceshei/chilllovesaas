# frozen_string_literal: true

module Types
  module Inputs
    # `fileUpdate` 的單筆輸入（第 28 包）。
    class FileUpdateInput < GraphQL::Schema::InputObject
      graphql_name "FileUpdateInput"
      description "要更新的檔案與新值。"

      argument :id, GraphQL::Types::ID, required: true,
                                        description: "gid://chilllove/File/{id}"
      argument :alt, String, required: false,
                             description: "檔案層 alt（空字串＝清除；不送＝不動）。"
      # 官方 `FileUpdateInput.filename` 逐字："The name of the file including its
      # extension."（取證 2026-08-25）。🔴 只改顯示用的檔名，**不動 `storage_key`**
      # ——blob 路徑是 uuid，改名不必搬檔，也就不會有搬到一半失敗的中間態。
      argument :filename, String, required: false,
                                  description: "顯示檔名（含副檔名）；同店撞名回 FILENAME_ALREADY_EXISTS。"
    end
  end
end
