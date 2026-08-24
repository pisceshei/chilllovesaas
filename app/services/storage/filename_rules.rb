# frozen_string_literal: true

module Storage
  # 檔名規則（第 25 包；12 §C.7:255——stagedUploadsCreate 與 fileCreate 共用一份，
  # 兩處各驗一次＝配額預檢在第 1 步做（12 §D.7-5）而 fileCreate 是最終防線）。
  module FilenameRules
    RESERVED_SUFFIXES = Limits.enum(:media, :filename_reserved_suffixes)
                              .map { |v| v.to_s.downcase }.freeze

    module_function

    # @return [Symbol, nil] :invalid／:unacceptable；nil＝通過
    def violation(filename)
      name = filename.to_s
      return :invalid if name.blank? || name.start_with?(".") || name.include?("/") || name.include?("\\")

      extension = ::File.extname(name).downcase
      return :unacceptable if [ ".html", ".htm" ].include?(extension) # HTML 一律拒收（12 §C.7）

      stem = ::File.basename(name, ".*").downcase
      # 保留字尾＝本尊衍生圖後綴（photo_thumb.jpg 會撞衍生圖命名空間）
      hit = RESERVED_SUFFIXES.any? do |suffix|
        stem == suffix || stem.end_with?("_#{suffix}") || stem.end_with?("-#{suffix}")
      end
      hit ? :invalid : nil
    end
  end
end
