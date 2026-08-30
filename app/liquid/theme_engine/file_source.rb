# frozen_string_literal: true

module ThemeEngine
  # 唯讀主題檔案來源（目錄形態）。
  #
  # 🔴 路徑逃逸防線：相對路徑正規化後必須仍在根目錄下（`..`／絕對路徑一律拒），
  #   與 25 §4 匯入管線第 1 步同一威脅模型——這裡是讀取側的對偶。
  class FileSource
    def initialize(root)
      @root = File.expand_path(root)
    end

    # @return [String, nil] 檔案內容；不存在或路徑逃逸 ⇒ nil（引擎層寬容處理）
    def read(rel)
      f = resolve(rel)
      f && File.file?(f) ? File.read(f) : nil
    end

    def exist?(rel)
      f = resolve(rel)
      !f.nil? && File.file?(f)
    end

    private

    def resolve(rel)
      full = File.expand_path(File.join(@root, rel.to_s))
      full.start_with?("#{@root}#{File::SEPARATOR}") ? full : nil
    end
  end
end
