# frozen_string_literal: true

module MediaPipeline
  # 衍生尺寸的正典（第 26 包；13 §F3-3 逐字「thumb 160、card 533、detail 1200、
  # og 1200×630」）。
  #
  # 🔴 **fit 語義是我方裁定（ours）**——13 §F3 只列了名稱與數字、未說縮放語義：
  #   - thumb／card／detail＝**最長邊上限**（保持比例、**不放大**：小圖原樣輸出，
  #     放大只會產生更大的檔案與更糊的圖）。
  #   - og＝**固定 1200×630 裁切填滿**（Open Graph 的固定比例是社交平台的版位要求，
  #     不是「不超過」；比例不符時居中裁切）。
  # 🔴 格式一律 webp（13 §F3-3「轉 webp」）。og 的社交平台相容性（LinkedIn 對 webp
  #   的支援未取證）留到第 35 包 SEO 實測；屆時若需 jpeg 再加一個 variant，
  #   不改本表既有值（登記於 worklog）。
  module Derivatives
    # variant → {mode:, width:, height:}
    #   mode :fit＝最長邊上限不放大；mode :cover＝裁切填滿固定尺寸
    SPECS = {
      "thumb" => { mode: :fit, width: 160, height: 160 },
      "card" => { mode: :fit, width: 533, height: 533 },
      "detail" => { mode: :fit, width: 1200, height: 1200 },
      "og" => { mode: :cover, width: 1200, height: 630 }
    }.freeze

    EXTENSION = ".webp"

    module_function

    def names = SPECS.keys

    # 衍生檔的 storage key（獨立命名空間，不與原檔／staged 混）。
    # 🔴 不用「原 key ＋ 尺寸後綴」形：那正是 12 §C.7:255 保留字尾清單在防的撞名形態。
    # 🔴 帶**內容 checksum 前綴**（審查 C6）：replace 換了內容時同一 file 可能有兩輪
    #    處理在飛，各寫各的 key 才不會互相覆蓋成一組混合尺寸。
    def key_for(file, variant, checksum: nil)
      digest = (checksum || file.checksum).to_s.first(12)
      "shops/#{file.shop_id}/derivatives/#{file.id}/#{digest}/#{variant}#{EXTENSION}"
    end
  end
end
