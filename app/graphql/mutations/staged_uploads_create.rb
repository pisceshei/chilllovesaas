# frozen_string_literal: true

module Mutations
  # 兩段式上傳第 1 步（12 §D.7；B6 自建 presigned POST）。
  #
  # 🔴 配額預檢在本步做（12 §D.7-5）：mimeType 白名單（B9 image-only）、
  #    fileSize ≤ 圖檔上限、檔名規則、批次 ≤ files_upload_batch_max——
  #    預檢過的大小進簽名（content-length-range 同構），上傳端點照簽名再驗一次。
  # 無 DB 寫入（純簽名）⇒ 不進 limits.idempotency 名單；contract 呼叫照鐵律。
  class StagedUploadsCreate < BaseMutation
    description "為一批待上傳檔案簽發 staged 上傳目標。"

    user_errors_type Types::Errors::FilesUserErrorType

    argument :input, [ Types::Inputs::StagedUploadInput ], required: true
    argument :idempotency_key, String, required: false

    field :staged_targets, [ Types::StagedUploadTargetType ], null: false

    def resolve(input:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      authorize_files!

      errors = []
      if input.length > Limits.fetch(:content, :files_upload_batch_max)
        return { staged_targets: [], user_errors: [ user_error([ "input" ],
          I18n.t("errors.files.batch_too_large"), "INVALID") ] }
      end

      allowed_types = Limits.enum(:media, :image_content_types).map { |v| v.to_s.downcase }
      max_bytes = Limits.fetch(:content, :files_image_max_mb) * 1024 * 1024
      targets = []
      input.each_with_index do |declaration, index|
        if (violation = Storage::FilenameRules.violation(declaration.filename))
          code = violation == :unacceptable ? "UNACCEPTABLE_ASSET" : "INVALID"
          errors << user_error([ "input", index.to_s, "filename" ],
            I18n.t("errors.files.filename_invalid"), code)
          next
        end
        unless allowed_types.include?(declaration.mime_type.to_s.downcase)
          errors << user_error([ "input", index.to_s, "mimeType" ],
            I18n.t("errors.files.type_unacceptable"), "UNACCEPTABLE_ASSET")
          next
        end
        if declaration.file_size <= 0 || declaration.file_size > max_bytes
          errors << user_error([ "input", index.to_s, "fileSize" ],
            I18n.t("errors.files.too_large"), "INVALID")
          next
        end
        targets << Storage::SignedUpload.issue(
          shop: context.fetch(:current_shop), filename: declaration.filename,
          byte_size: declaration.file_size)
      end
      { staged_targets: errors.any? ? [] : targets, user_errors: errors }
    end

    private

    def user_error(field, message, code) = { field:, message:, code: }

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
