# frozen_string_literal: true

require "zip"

module Themes
  # 主題 zip 匯入八步管線（G3 步 15a；契約正典＝99 §1–§3）。
  #
  # ①zip 有效性（開不了 ⇒ INVALID_ZIP＝官方碼）②尺寸閘（zip ≤50MB／解壓合計
  #   ≤250MB／檔數 ≤100k——99 §2 官方值，limits theme_import.*）③條目安全：
  #   路徑逃逸（../、絕對路徑）、symlink、壓縮比炸彈（ours 閾值）一律拒
  # ④單根剝除（官方未取得 ⇒ ours：全條目共享唯一根目錄時剝根——99 §3）
  # ⑤頂層目錄白名單（官方目錄樹；白名單外條目**略過**＝CLI package 同行為）
  # ⑥結構閘：layout/theme.liquid 必在（官方唯一硬要求逐字）
  # ⑦內容定址落盤：SHA-256(排序後 路徑+內容) ⇒ storage/themes/{checksum}
  #   （已存在＝重用，目錄不可變——AST cache 跨租戶防線的根治）
  # ⑧相容掃描報告（逐 .liquid 以我方 ENVIRONMENT parse；錯誤與未知結構入報告）
  #   ＋授權聲明 gate（license_attested 必須明示 true——鐵律 9 配套）。
  #
  # 全程成功/失敗都寫 theme_import_reports（失敗 theme_id NULL＋error_code）。
  class ImportZip
    Result = Struct.new(:theme, :report, :error_code, :error_message, keyword_init: true) do
      def success? = theme.present?
    end

    STORAGE_ROOT = Rails.root.join("storage", "themes")

    def self.call(shop:, zip_path:, name:, license_attested:, zip_filename: nil)
      new(shop:, zip_path:, name:, license_attested:,
          zip_filename: zip_filename || File.basename(zip_path.to_s)).call
    end

    def initialize(shop:, zip_path:, name:, license_attested:, zip_filename:)
      @shop = shop
      @zip_path = zip_path.to_s
      @name = name.to_s.strip
      @license_attested = license_attested
      @zip_filename = zip_filename
      @warnings = []
    end

    def call
      return fail_with("LICENSE_NOT_ATTESTED", "匯入前必須聲明已取得主題授權（鐵律 9）。") unless @license_attested
      if @name.blank? || @name.length > Limits.fetch(:theme_import, :theme_name_max)
        return fail_with("INVALID_NAME", "主題名稱必填且不得超過 #{Limits.fetch(:theme_import, :theme_name_max)} 字元（官方上限）。")
      end
      return fail_with("ZIP_TOO_LARGE", "zip 超過 #{zip_max_bytes / 1.megabyte}MB 上限（官方）。") if File.size(@zip_path) > zip_max_bytes

      entries = safe_entries
      return @failure if @failure
      return fail_with("ZIP_IS_EMPTY", "zip 內沒有可用的主題檔案。") if entries.empty?
      unless entries.key?("layout/theme.liquid")
        return fail_with("MISSING_LAYOUT", "缺 layout/theme.liquid（官方唯一硬要求）。")
      end

      checksum = compute_checksum(entries)
      write_storage(checksum, entries)
      report = compat_scan(entries).merge(
        "files" => entries.size, "checksum" => checksum,
        "warnings" => @warnings
      )

      theme = ActsAsTenant.with_tenant(@shop) do
        Theme.create!(shop_id: @shop.id, name: @name, role: "draft", source: "import",
                      license_attested: true, content_checksum: checksum,
                      version: report["theme_version"])
      end
      write_report(theme:, status: "ok", report:)
      Result.new(theme:, report:)
    rescue ActiveRecord::RecordInvalid => e
      fail_with("INVALID_NAME", e.record.errors.full_messages.first.to_s)
    end

    private

    def zip_max_bytes = Limits.fetch(:theme_import, :zip_max_mb).megabytes
    def total_max_bytes = Limits.fetch(:theme_import, :total_uncompressed_mb).megabytes
    def max_files = Limits.fetch(:theme_import, :max_files)
    def max_ratio = Limits.fetch(:theme_import, :max_compression_ratio)
    def allowed_dirs = Limits.enum(:theme_import, :allowed_top_dirs).map(&:downcase)

    # @return [Hash{String => String}] 相對路徑 => 內容（二進位安全）
    def safe_entries
      raw = {}
      total = 0
      Zip::File.open(@zip_path) do |zip|
        names = zip.filter_map { |entry| entry.name unless entry.directory? }
        root = common_root(names)
        zip.each do |entry|
          next if entry.directory?

          name = entry.name
          # ③路徑逃逸與 symlink（fail-closed：整包拒收，不是略過——半個主題更危險）
          if name.include?("..") || name.start_with?("/") || name.include?("\\")
            return set_failure("UNSAFE_PATH", "zip 條目含路徑逃逸（#{name}）。")
          end
          return set_failure("SYMLINK_FORBIDDEN", "zip 含 symlink 條目（#{name}）。") if entry.symlink?

          rel = root ? name.delete_prefix(root) : name
          next if rel.blank?

          top = rel.split("/", 2).first.to_s.downcase
          unless allowed_dirs.include?(top) && rel.include?("/")
            @warnings << "略過白名單外條目：#{rel}"
            next
          end

          # ③壓縮比炸彈＋②合計/檔數閘
          if entry.compressed_size.positive? && entry.size / [ entry.compressed_size, 1 ].max > max_ratio
            return set_failure("COMPRESSION_BOMB", "條目壓縮比異常（#{rel}）。")
          end
          total += entry.size
          return set_failure("TOTAL_TOO_LARGE", "解壓合計超過 #{total_max_bytes / 1.megabyte}MB（官方）。") if total > total_max_bytes
          return set_failure("TOO_MANY_FILES", "檔案數超過 #{max_files}（官方）。") if raw.size >= max_files

          raw[rel] = entry.get_input_stream.read
        end
      end
      raw
    rescue Zip::Error
      set_failure("INVALID_ZIP", "Must be a zip file.") # 官方碼＋逐字訊息形
    end

    # ④單根剝除（ours；99 §3 官方未取得）：全部條目共享同一個頂層目錄 ⇒ 剝。
    def common_root(names)
      firsts = names.map { |name| name.split("/", 2) }.map(&:first).uniq
      return nil unless firsts.size == 1 && names.all? { |name| name.include?("/") }

      candidate = "#{firsts.first}/"
      allowed_dirs.include?(firsts.first.to_s.downcase) ? nil : candidate
    end

    def set_failure(code, message)
      @failure = fail_with(code, message)
      {}
    end

    def fail_with(code, message)
      write_report(theme: nil, status: "failed", report: { "warnings" => @warnings }, error_code: code)
      Result.new(error_code: code, error_message: message)
    end

    # ⑦內容定址（排序後 路徑+內容 的 SHA-256——同 checksum 恆同內容，目錄不可變）
    def compute_checksum(entries)
      digest = Digest::SHA256.new
      entries.keys.sort.each do |rel|
        digest.update(rel)
        digest.update("\0")
        digest.update(entries[rel])
      end
      digest.hexdigest
    end

    def write_storage(checksum, entries)
      final_dir = STORAGE_ROOT.join(checksum)
      return if File.directory?(final_dir) # 已存在＝同內容重用（不可變）

      tmp_dir = STORAGE_ROOT.join("tmp-#{SecureRandom.hex(8)}")
      entries.each do |rel, content|
        path = tmp_dir.join(rel)
        FileUtils.mkdir_p(path.dirname)
        File.binwrite(path, content)
      end
      FileUtils.mkdir_p(STORAGE_ROOT)
      begin
        FileUtils.mv(tmp_dir, final_dir)
      rescue Errno::EEXIST, Errno::ENOTEMPTY
        FileUtils.rm_rf(tmp_dir) # 併發匯入同內容：先到者贏，內容相同無害
      end
    end

    # ⑧相容掃描：逐 .liquid parse（我方 ENVIRONMENT——未知 tag 在 lax 下收進
    # errors）；settings_schema 抽 theme_version。報告是資料不是閘（匯入照過，
    # 商家看報告決定要不要用）。
    def compat_scan(entries)
      liquid_errors = []
      entries.each do |rel, content|
        next unless rel.end_with?(".liquid")

        body = content.dup.force_encoding("UTF-8").scrub
        body = body.sub(ThemeEngine::Runtime::SCHEMA_RE, "")
        begin
          Liquid::Template.parse(body, environment: ThemeEngine::Runtime::ENVIRONMENT, error_mode: :lax)
        rescue Liquid::SyntaxError => e
          liquid_errors << { "file" => rel, "error" => e.message[0, 200] }
        end
      end
      version = extract_theme_version(entries["config/settings_schema.json"])
      { "liquid_errors" => liquid_errors, "theme_version" => version }
    end

    def extract_theme_version(raw)
      return nil if raw.nil?

      schema = ThemeEngine::Runtime.tolerant_json(raw.dup.force_encoding("UTF-8").scrub)
      info = Array(schema).find { |chunk| chunk.is_a?(Hash) && chunk["theme_version"] }
      info && info["theme_version"].to_s[0, 64]
    rescue JSON::ParserError
      nil
    end

    def write_report(theme:, status:, report:, error_code: nil)
      ActsAsTenant.with_tenant(@shop) do
        ThemeImportReport.create!(shop_id: @shop.id, theme_id: theme&.id,
                                  zip_filename: @zip_filename, status:, error_code:,
                                  report:)
      end
    rescue ActiveRecord::ActiveRecordError
      nil # 報告寫失敗不擋匯入結果（報告是輔助面）
    end
  end
end
