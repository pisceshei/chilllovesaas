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
    end
  end
end
