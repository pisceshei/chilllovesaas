# frozen_string_literal: true

module Types
  module Errors
    # 檔案線（stagedUploadsCreate／fileCreate）的 typed error code enum（鐵律 4）。
    #
    # 值域＝共用池＋已證四值中池裡沒有的三個（12 §C.7:90，取證 2026-08-14）。
    # 撞名（raise_error 模式）回 INVALID＝我方對映（官方撞名專屬碼未取證，ours）。
    class FilesUserErrorCode < BaseCodeEnum
      graphql_name "FilesUserErrorCode"
      description "檔案 mutations 可能回傳的錯誤碼。"

      from_pools
      own_value :UNACCEPTABLE_ASSET, "格式不受理（HTML 一律拒收；content-type 不在白名單）。"
      own_value :ALT_VALUE_LIMIT_EXCEEDED, "alt 文字超過 512 字元上限。"
      own_value :FILE_DOES_NOT_EXIST, "originalSource 指向的 staged 檔不存在（未上傳或已逾期清除）。"
      # ── 第 28 包：檔案庫的 fileUpdate／fileDelete。四值全部照抄官方
      #    `FilesErrorCode`（shopify.dev/docs/api/admin-graphql/latest/enums/FilesErrorCode，
      #    取證 2026-08-25），不自創——本輪研究抓到我方原本要用的 `FILE_IS_PROCESSING`
      #    在官方值域裡不存在，對應的官方碼是下面兩個。 ──
      # 官方逐字："File has a pending operation."
      own_value :FILE_LOCKED, "檔案有進行中的作業（處理管線正在寫衍生尺寸），完成後才能刪。"
      # 官方逐字："The file is not in the READY state."
      own_value :NON_READY_STATE, "檔案不在 READY 狀態（fileUpdate 要求 ready）。"
      # 官方逐字："File cannot be updated in a failed state."
      own_value :INVALID_FAILED_MEDIA_STATE, "處理失敗的檔案不可更新（終態，只能刪）。"
      # 官方逐字："The provided filename already exists."
      own_value :FILENAME_ALREADY_EXISTS, "同名檔案已存在。"
    end
  end
end
