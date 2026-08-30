# frozen_string_literal: true

module Storefront
  # 購物車錯誤（真店 422 形逐字結構：{status,message,description}——83 §12.5）。
  # 獨立檔＝Zeitwerk eager-load 可解析（CI 首輪抓到藏在 cart_writer.rb 內
  # 導致 uninitialized constant 的教訓）。
  class CartError < StandardError
    attr_reader :status

    def initialize(message, status: 422)
      super(message)
      @status = status
    end

    def as_json_body = { "status" => status, "message" => message, "description" => message }
  end
end
