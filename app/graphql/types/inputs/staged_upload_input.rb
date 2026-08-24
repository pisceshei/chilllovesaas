# frozen_string_literal: true

module Types
  module Inputs
    # stagedUploadsCreate 的單一目標（12 §D.7-1；B9 本批 image-only）。
    class StagedUploadInput < GraphQL::Schema::InputObject
      graphql_name "StagedUploadInput"
      description "一個待上傳檔案的宣告。"

      argument :filename, String, required: true
      argument :mime_type, String, required: true,
        description: "content-type；本批白名單＝limits media.image_content_types（B9 image-only）。"
      # 🔴 本尊只對 VIDEO/MODEL_3D 必填；我方一律必填（ours 加嚴）——
      #    配額預檢必須在第 1 步做（12 §D.7-5），且大小進簽名（content-length-range 同構）。
      argument :file_size, GraphQL::Types::BigInt, required: true,
        description: "宣告大小（bytes）；進簽名＝上傳上限。"
    end
  end
end
