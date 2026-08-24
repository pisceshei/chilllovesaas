# frozen_string_literal: true

module Storage
  # 圖片 magic-byte 嗅探（第 25 包審查 C5：content-type 由**內容**決定，不由副檔名／
  # 宣告的 mimeType——staged 端點只驗簽名＋大小、不驗內容，宣告 image/png 實際傳 HTML
  # 會被以 image/png 落庫）。
  #
  # 🔴 這是安全邊界不是便利：純副檔名／宣告 content-type 可被偽造；magic byte 是
  # 檔案本體，偽造它就得先是合法圖檔。回傳白名單內的 content_type 或 nil（拒收）。
  # 完整像素／長寬比驗證＋衍生圖屬第 26 包（libvips），本層只做「是不是宣稱的那種圖」。
  module ImageSniff
    module_function

    # @param bytes [String] 檔案前綴（≥12 bytes 即可判別本批四型）
    # @return [String, nil] "image/jpeg"｜"image/png"｜"image/gif"｜"image/webp"｜nil
    def content_type(bytes)
      head = bytes.to_s.byteslice(0, 16).to_s.b
      return "image/jpeg" if head.start_with?("\xFF\xD8\xFF".b)
      return "image/png" if head.start_with?("\x89PNG\r\n\x1A\n".b)
      return "image/gif" if head.start_with?("GIF87a".b) || head.start_with?("GIF89a".b)
      # WEBP＝RIFF....WEBP（第 0-3 "RIFF"、第 8-11 "WEBP"；中間 4 bytes 是檔長）
      return "image/webp" if head.byteslice(0, 4) == "RIFF".b && head.byteslice(8, 4) == "WEBP".b

      nil
    end
  end
end
