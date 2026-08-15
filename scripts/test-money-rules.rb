#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-money-boundary.rb` 的回歸測試（fixture 驅動）。
#
# ## 🔴 為什麼「檢查腳本自己綠」不算交付
#
# `docs/specs/65` §K 第 7 條的判準逐字是：**只有前者綠不算交付**——
# 一個什麼都不檢查的腳本在乾淨倉庫上也是綠的。
# 要證明它有效，唯一的方法是**讓每一條規則各自被一個故意違反的 fixture 打紅**。
#
# 這與 `scripts/test-lint-rules.py` 是同一個形態，而那個形態是被上一輪打出來的：
# `r_dead_control` 在四輪內踩了六種「漏看」，**每一種 CI 都是綠的**——
# 判準從頭到尾沒錯，錯的一直是取樣面。
#
# 用法：ruby scripts/test-money-rules.rb
# 退出碼：0=全過，1=有失敗
ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(ROOT, "scripts/check-money-boundary.rb")
FIXTURES = File.join(ROOT, "spec/fixtures/ci_violations")

# (fixture 目錄, 期望命中的檢查標籤, 這條在防哪一種繞過)
CASES = [
  [ "c1_cents_in_psp", "[C1]",
    "PSP 目錄裡出現 storage 尺度的識別字——看到 `_cents` 出現在送款呼叫點就是 bug" ],
  [ "c2_bad_kwarg", "[C2]",
    "不經 adapter、直接組 HTTP body（金額 kwarg 沒有 `_minor`／`_psp_decimal` 後綴）" ],
  [ "c3_decimal_column", "[C3]",
    "migration 用 `t.decimal` 建金額欄位——鐵律 3「出現 float 即 bug」的 migration 期執法點" ],
  [ "c3_integer_cents", "[C3]",
    "`_cents` 欄位用 `t.integer`（會溢位；須 bigint）" ],
  # 🔴 2026-08-15 新增。本輪之前 C3 只列舉三種錯誤寫法（decimal／float／integer）
  #    ⇒ `t.string :price_cents` **完全通過**，而成功訊息卻宣告「`_cents` 皆為 bigint」。
  #    C3 已改成白名單式（型別不是 bigint 就違規），這個 fixture 守住那個改動。
  [ "c3_string_cents", "[C3]",
    "`_cents` 欄位用 `t.string`——列舉式檢查抓不到，白名單式才抓得到" ],
  [ "c4_money_decimal", "[C4]",
    "🔴 PSP 目錄裡出現 R4——唯一的可能就是有人拿 feed／物流商的值來送款" ],
  [ "c4_bare_decimal_suffix", "[C4]",
    "🔴 用了 R4 的後綴 `_decimal`（R6 的是 `_psp_decimal`，刻意不同）" ],
  [ "c5_build_outside", "[C5]",
    "🔴 在 money.rb 以外呼叫 `__build` 手工湊一個 R5——L2 唯一建構路徑的唯一破口" ],
  [ "matrix_missing_currency", "[矩陣]",
    "🔴 測試矩陣缺 zero-decimal 幣別——沒有它，100 倍事故會在上線後才出現" ],
  [ "matrix_missing_format", "[矩陣]",
    "🔴 沒有 decimal_string 型 fixture pack——那條路徑的錯誤在 HKD 上也會錯" ]
].freeze

failures = []

CASES.each do |dir, label, why|
  path = File.join(FIXTURES, dir)
  unless Dir.exist?(path)
    failures << "#{dir}：fixture 目錄不存在"
    next
  end

  output = `ruby "#{CHECKER}" "#{path}" 2>&1`
  status = $?.exitstatus

  if status.zero?
    failures << "#{dir}：檢查器**沒有**擋下來（exit 0）——防的是：#{why}"
  elsif !output.include?(label)
    failures << "#{dir}：擋下來了但不是 #{label}（實得：#{output.lines.grep(/\[/).first&.strip}）"
  end

  puts format("  %-4s %-26s %s", status.zero? ? "FAIL" : "PASS", dir, label)
end

# 🔴 反向：乾淨倉庫必須 exit 0。
# 沒有這一條的話，一個「永遠 fail」的檢查器也會讓上面九條全過。
clean_output = `ruby "#{CHECKER}" "#{ROOT}" 2>&1`
clean_status = $?.exitstatus
if clean_status.zero?
  puts format("  %-4s %-26s %s", "PASS", "（乾淨倉庫）", "exit 0")
else
  failures << "乾淨倉庫沒有通過（exit #{clean_status}）：\n#{clean_output}"
  puts format("  %-4s %-26s %s", "FAIL", "（乾淨倉庫）", "exit #{clean_status}")
end

puts

if failures.empty?
  puts "OK：金額 CI 執法回歸測試 #{CASES.size + 1} 項全過"
  exit 0
end

warn "::error::金額 CI 執法回歸測試失敗（#{failures.size} 項）："
failures.each { |f| warn "  - #{f}" }
exit 1
