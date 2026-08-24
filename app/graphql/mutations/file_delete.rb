# frozen_string_literal: true

module Mutations
  # 從檔案庫刪檔（第 28 包）。
  #
  # 🔴 **刪檔會連帶拿掉引用它的商品媒體**——`Storage::FileWrite.delete` 先 destroy
  #   那些 `media` 列（走 `before_destroy` 釋放 `file_usages`）再刪 `files` 列。
  #   前端必須先用 `usageCount` 告訴使用者「這張圖正被 N 個商品使用」，不能讓
  #   商品圖無聲消失。
  class FileDelete < BaseFileMutation
    description "刪除檔案（連帶移除引用它的商品媒體）。"

    user_errors_type Types::Errors::FilesUserErrorType

    argument :file_ids, [ GraphQL::Types::ID ], required: true
    argument :idempotency_key, String, required: false

    field :deleted_file_ids, [ GraphQL::Types::ID ], null: false

    def resolve(file_ids:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      authorize_files!

      result = Storage::FileWrite.delete(shop: context.fetch(:current_shop), file_ids:)
      { deleted_file_ids: result.deleted_file_ids, user_errors: user_errors_from(result) }
    end
  end
end
