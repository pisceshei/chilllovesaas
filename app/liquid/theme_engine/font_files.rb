# frozen_string_literal: true

module ThemeEngine
  # 平台字型檔（public/fonts/{family}/{handle}.woff2；T12）：啟動時讀成常量（Brakeman：不以參數組檔案路徑），
  # SHA-1 進 URL（本尊形 `/cdn/fonts/{family}/{handle}.{sha1}.woff2`），供給端比對雜湊後以 send_data 回本體。
  module FontFiles
    module_function

    FILES = Dir.glob(Rails.root.join("public/fonts/*/*.woff2").to_s).sort.to_h do |path|
      body = File.binread(path).freeze
      [ [ File.basename(File.dirname(path)), File.basename(path, ".woff2") ],
        { sha1: Digest::SHA1.hexdigest(body), body: body }.freeze ]
    end.freeze

    def sha1(family, handle) = FILES.dig([ family, handle ], :sha1)
    def body(family, handle) = FILES.dig([ family, handle ], :body)
  end
end
