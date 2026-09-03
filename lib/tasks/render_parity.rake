# frozen_string_literal: true

# 渲染 1:1 對表（使用者 2026-09-03 裁定）：本尊店同主題頁面 vs 我方店頁面，正規化後逐段 diff，輸出 Markdown 報告。
#
#   bin/rails "render_parity:diff[REF,CAND,OUT]"
#     REF ／ CAND ＝ URL（https://…）或本地 HTML 檔路徑
#     OUT ＝ 報告輸出路徑（預設 tmp/render-parity.md）
#   環境變數：REF_HOST／CAND_HOST（去掉絕對網址用；未給時由 URL 推）；CAND_PREFIX＝我方路由前綴（例 /zh-hans-tw，
#   已登記裁定差異，見 Normalizer#initialize）
#
# 這支只產報告，不下「可接受」判斷；每條差異由人登記為引擎缺口（91 §3）或資料差異（鏡像店消除）。
namespace :render_parity do
  desc "本尊 vs 我方頁面正規化逐段 diff"
  task :diff, [ :ref, :cand, :out ] => :environment do |_, args|
    require "net/http"
    require "uri"

    fetch = lambda do |source|
      if source.to_s.match?(%r{\Ahttps?://})
        uri = URI.parse(source)
        response = Net::HTTP.get_response(uri)
        # E8b：`ALLOW_404=1` 時 404 頁也對表（本尊 /nope 與不存在的 blog 皆為 404 模板）
        ok = response.is_a?(Net::HTTPSuccess) || (ENV["ALLOW_404"] == "1" && response.code == "404")
        raise "GET #{source} => #{response.code}" unless ok

        [ response.body.force_encoding("UTF-8"), uri.host ]
      else
        [ File.read(source, encoding: "UTF-8"), nil ]
      end
    end

    ref_html, ref_host = fetch.call(args[:ref])
    cand_html, cand_host = fetch.call(args[:cand])
    ref_host = ENV.fetch("REF_HOST", ref_host.to_s)
    cand_host = ENV.fetch("CAND_HOST", cand_host.to_s)

    report = RenderParity::Report.new(
      reference: RenderParity::Normalizer.new(host: ref_host).call(ref_html),
      # CAND_PREFIX 可不帶前導斜線（Git Bash／MSYS 會把 `/zh-hans-tw` 這種值當 POSIX 路徑轉成 Windows 路徑）
      candidate: RenderParity::Normalizer.new(host: cand_host, url_prefix: ENV["CAND_PREFIX"].presence&.then { |p| p.start_with?("/") ? p : "/#{p}" }).call(cand_html),
      normalizer: RenderParity::Normalizer.new(host: "")
    )
    out = args[:out].presence || "tmp/render-parity.md"
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, report.to_markdown(title: "render parity: #{args[:ref]} vs #{args[:cand]}"))
    worst = report.sections.min_by(&:similarity)
    puts "report => #{out}"
    puts "sections: #{report.sections.size}; worst: #{worst&.key} #{format('%.3f', worst&.similarity || 0)}"
  end

  # 鏡像店（RenderParity::Mirror）：bin/rails "render_parity:mirror[SUBDOMAIN,SPEC]"
  #   SUBDOMAIN 預設 mirror；SPEC 預設 hoko（spec/fixtures/render_parity/hoko.json）
  #   production 另需 THEME_CHECKSUM=<已匯入主題的 content_checksum>
  desc "依快照描述建立／對齊一間與本尊店同資料的鏡像店（冪等、不刪資料）"
  task :mirror, [ :subdomain, :spec ] => :environment do |_, args|
    spec_name = args[:spec].presence || "hoko"
    spec = JSON.parse(File.read(Rails.root.join("spec", "fixtures", "render_parity", "#{spec_name}.json"), encoding: "UTF-8"))
    result = RenderParity::Mirror.call(subdomain: args[:subdomain].presence || "mirror", spec: spec,
                                       theme_checksum: ENV["THEME_CHECKSUM"])
    result.log.each { |line| puts line }
    puts "mirror shop ##{result.shop.id} #{result.shop.subdomain}"
  end
end
