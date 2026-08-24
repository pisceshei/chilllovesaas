# frozen_string_literal: true

module Mutations
  # 檔案庫 mutation 的共用底座（第 28 包）：授權。
  #
  # 權限鍵＝`files.edit`（`StoredFilePolicy#create?`）——檔案庫在內容線、不沿用
  # products.edit：只給了商品權限的 staff 不該能刪掉整個檔案庫。
  class BaseFileMutation < BaseMutation
    private

    def authorize_files!
      staff = context[:current_staff]
      return if staff && StoredFilePolicy.new(staff, StoredFile).create?

      raise GraphQL::ExecutionError.new(
        I18n.t("errors.files.access_denied"),
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end

    def user_errors_from(result) = result.user_errors.map { |e| e.slice(:field, :message, :code) }
  end
end
