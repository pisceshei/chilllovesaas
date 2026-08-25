# frozen_string_literal: true

# 譯文稽核（第 7 包；形態沿用 `lib/tasks/inventory.rake` 的 reconcile）。
#
# 🔴 **放 `lib/tasks/` 不放 `scripts/`**：`scripts/` 是 CI 機械閘門的所在地，放進去會讓
#   本任務落入鐵律 18.3 的人工合併清單；而且它需要 Rails 環境（`scripts/` 的腳本一律不需要）。
#
#   rails translations:audit              # 全平台唯讀掃描
#   rails translations:audit[demo]        # 單店
#   rails "translations:fix[demo]"        # 單店修復（blank_value / unsanitized_html 兩條）
namespace :translations do
  # 報告的共用輸出。棄權必須印在最前面且無條件印——
  # 「沒找到問題」與「沒去找」看起來必須不一樣（鐵律 20.2 第 5 類 fail-open）。
  def print_report(shop, report)
    puts "shop=#{shop.subdomain} 掃描 #{report.scanned} 列"
    report.abstained.each { |item| puts "  ⚠️ 棄權 #{item[:rule]}：#{item[:reason]}" }
    if report.scanned.zero?
      # 🔴 零掃描 canary：0 列不是「乾淨」，是「這家店沒有譯文可掃」。
      puts "  （這家店一列譯文都沒有——本次沒有掃到任何東西，不等於沒有問題）"
      return
    end
    if report.clean?
      puts "  ✅ 未棄權的規則全部乾淨"
      return
    end
    report.findings_by_rule.each { |rule, count| puts "  [#{rule}] #{count} 筆" }
    report.findings.first(20).each do |f|
      puts "    #{f.rule} t##{f.translation_id} #{f.resource_type}/#{f.resource_id} " \
           "#{f.locale_tag}.#{f.field_key} — #{f.detail}"
    end
    puts "    …（只列前 20 筆，共 #{report.findings.length} 筆）" if report.findings.length > 20
  end

  def each_target(subdomain)
    scope = subdomain.present? ? Shop.where(subdomain:) : Shop.all
    abort "找不到商店：#{subdomain}" if subdomain.present? && scope.empty?
    scope.find_each { |shop| yield shop }
  end

  desc "稽核既有譯文（空值／未 sanitize 的 HTML／孤兒語言／來源語言列）；有發現則非零結束"
  task :audit, [ :subdomain ] => :environment do |_task, args|
    total = 0
    each_target(args[:subdomain]) do |shop|
      # 每 500 列印一次進度：html 欄每列要兩次 parse（~50ms 量級），大店是分鐘級任務，
      # 沒有進度輸出看起來像卡死（審查 C6）。
      report = Translations::Audit.call(shop:, progress: ->(n) { puts "  …已掃 #{n} 列" })
      total += report.findings.length
      print_report(shop, report)
    end
    abort "audit FAILED：共 #{total} 筆發現（`rails \"translations:fix[<subdomain>]\"` 可修前兩條）" if total.positive?
    puts "audit OK：0 筆發現（棄權的規則見上方 ⚠️）"
  end

  desc "修復可自動修的兩條規則（刪空值列／重寫未 sanitize 的 HTML）並重算 translation_status"
  task :fix, [ :subdomain ] => :environment do |_task, args|
    # 🔴 修復會刪列，一律要求指名商店——`rails translations:fix` 不帶參數會變成
    #   「對全平台每一家店做不可逆刪除」，那不該是一個打錯字就會發生的事。
    abort "translations:fix 必須指名商店：rails \"translations:fix[<subdomain>]\"" if args[:subdomain].blank?

    each_target(args[:subdomain]) do |shop|
      report = Translations::Audit.call(shop:, fix: true, progress: ->(n) { puts "  …已掃 #{n} 列" })
      print_report(shop, report)
      puts "  🔧 已修復 #{report.fixed} 列（其餘規則僅登記不動）"
      if report.skipped_stale.positive?
        # 掃描與修復之間值變了 ⇒ 重驗擋下、未動（審查 C2 的 TOCTOU 防線）。再跑一次即可。
        puts "  ⏭️ #{report.skipped_stale} 列在掃描後被改動，已跳過未修——重跑一次 fix 可收斂"
      end
    end
  end
end
