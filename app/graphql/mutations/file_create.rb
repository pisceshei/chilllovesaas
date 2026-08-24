# frozen_string_literal: true

module Mutations
  # 兩段式上傳第 3 步（12 §D.7）：originalSource → files 一列＋MEDIA_UPLOADED 事件。
  class FileCreate < BaseMutation
    description "以 originalSource（staged 或外部 URL）建立檔案。"

    user_errors_type Types::Errors::FilesUserErrorType

    argument :files, [ Types::Inputs::FileCreateInput ], required: true
    argument :idempotency_key, String, required: false

    field :files, [ Types::FileType ], null: false

    def resolve(files:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      # 🔴 fileCreate 是建立型（limits idempotency.required_for_catalog_create）：
      #    無 key 的重複點擊會憑空多出檔案實體（append_uuid 下不衝突＝靜默重複）。
      #    強制帶 key 對齊契約；完整批量 replay 未實作（Guard 單 resource 且其 txn
      #    邊界與本包 fs-out-of-txn 相斥），登記 docs/specs/91 §3。
      raise GraphQL::ExecutionError.new(
        "fileCreate 必須提供 idempotencyKey。",
        extensions: { "code" => "IDEMPOTENCY_KEY_REQUIRED" }
      ) if idempotency_key.blank?
      authorize_files!

      result = Storage::FileCreate.call(
        shop: Current.shop,
        files_input: files.map do |input|
          { original_source: input.original_source, alt: input.alt,
            filename: input.filename, duplicate_resolution_mode: input.duplicate_resolution_mode }
        end
      )
      { files: result.files, user_errors: result.user_errors.map { |e| e.slice(:field, :message, :code) } }
    end

    private

    def authorize_files!
      staff = context[:current_staff]
      return if staff && StoredFilePolicy.new(staff, StoredFile).create?

      raise GraphQL::ExecutionError.new(
        "沒有權限寫入檔案。",
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end
  end
end
