# frozen_string_literal: true

module Mutations
  # 改檔案層 metadata（第 28 包檔案庫）。
  #
  # 🔴 **只改 `files.alt_text`，不回寫既有 `media.alt_text`**：同一張圖掛在三個商品
  #   上可以有三個不同 alt（`Types::ImageType` 檔頭的裁定），從檔案庫改一次就把
  #   那三份蓋掉是不可接受的。檔案層 alt 的作用是「之後新掛載時的預設值」。
  class FileUpdate < BaseFileMutation
    description "更新檔案層 alt／檔名（不影響既有商品媒體的 alt）。"

    user_errors_type Types::Errors::FilesUserErrorType

    argument :files, [ Types::Inputs::FileUpdateInput ], required: true
    # 契約參數：是否**強制**帶由 limits `idempotency.required_for` 決定（鐵律 6），
    # 不在這裡各自列清單；更新型目前不在該清單內，參數仍照收（呼叫端要帶就能帶）。
    argument :idempotency_key, String, required: false

    field :files, [ Types::FileType ], null: false

    # 🔴 更新型 mutation 不強制 idempotencyKey（同 productSet 的理由：宣告式覆寫
    #    天然冪等——同一份 alt 送兩次結果相同）。建立型才強制（見 FileCreate）。
    def resolve(files:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      authorize_files!

      result = Storage::FileWrite.update(
        shop: context.fetch(:current_shop),
        # 🔴 `key?` 而不是 `alt.present?`：「不送 alt」與「送空字串清除 alt」是兩件事，
        #    用 present? 會讓清除變成靜默不動。
        entries: files.map do |input|
          entry = { id: input.id }
          entry[:alt] = input.alt if input.key?(:alt)
          entry[:filename] = input.filename if input.key?(:filename)
          entry
        end,
      )
      { files: result.files, user_errors: user_errors_from(result) }
    end
  end
end
