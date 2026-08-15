#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-limits-keys.rb` 的回歸測試（fixture 驅動）。
#
# ## 🔴 為什麼「檢查腳本自己綠」不算交付
#
# `docs/specs/65` §K 第 7 條的判準逐字是：**只有前者綠不算交付**——
# 一個什麼都不檢查的腳本在乾淨倉庫上也是綠的。
# 要證明它有效，唯一的方法是**讓每一條規則各自被一個故意違反的 fixture 打紅**，
# 再加一條**反向斷言**（乾淨 fixture 必須 exit 0），
# 否則一個「永遠 fail」的檢查器會讓上面每一條都「通過」。
#
# 形態比照 `scripts/test-money-rules.rb` 與 `scripts/test-lint-rules.py`。
#
# ## 本測試存在的直接理由（2026-08-15）
#
# `check-limits-keys.rb` 送審時**沒有**回歸測試，PR #33 的兩個驗收方都指出了這件事，
# 而當時的理由是「既有兩支 check-*.rb 都沒有，比照辦理」——那個理由**已經不成立**：
# main 隨 PR #29 進來了 `scripts/test-money-rules.rb`，把「檢查器要有反向證明」
# 立成了專案慣例。
#
# 🔴 這支測試守的是一個**看不見的失效**：判定邏輯只要被改成
# `resolved.is_a?(String)` 的反面、或 `unless` 寫成 `if`，
# `check-limits-keys.rb` 在乾淨倉庫上**仍然 exit 0**，CI 全綠，
# 而它已經什麼都不擋了。
#
# 用法：ruby scripts/test-limits-key-rules.rb
# 退出碼：0=全過，1=有失敗

ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(ROOT, "scripts/check-limits-keys.rb")
FIXTURES = File.join(ROOT, "spec/fixtures/ci_violations")

# (fixture 目錄, 期望 exit code, 輸出須包含的字串, 這條在防什麼)
CASES = [
  [ "limits_bool_key", 1, "TrueClass",
    "裸字 `on` 鍵被 Psych 解析成 true——config/limits.yml 的 M27–M32 踩過的原形態" ],
  [ "limits_erb", 1, "ERB",
    "🔴 ERB fail-closed：原始檔的 AST 看起來乾淨，但 loader 先 render 後會得到 true 鍵" ],
  [ "limits_clean", 0, "OK",
    "🔴 反向斷言：乾淨 fixture 必須通過。缺這條，一個永遠 fail 的檢查器會讓上面兩條都「通過」" ]
].freeze

failures = []

CASES.each do |dir, want_status, want_output, why|
  path = File.join(FIXTURES, dir)
  unless Dir.exist?(path)
    failures << "#{dir}：fixture 目錄不存在（#{why}）"
    next
  end

  output = `ruby "#{CHECKER}" "#{path}" 2>&1`
  status = $?.exitstatus

  if status != want_status
    failures << "#{dir}：期望 exit #{want_status}，實得 #{status}（#{why}）\n      輸出：#{output.lines.first.to_s.strip}"
    next
  end

  next if output.include?(want_output)

  failures << "#{dir}：exit code 對，但輸出不含 `#{want_output}`（#{why}）\n      輸出：#{output.lines.first.to_s.strip}"
end

if failures.empty?
  puts "OK：limits 鍵型別檢查器的回歸測試通過（#{CASES.size} 條）"
  CASES.each { |dir, want_status, _, why| puts "  - #{dir} → exit #{want_status}：#{why}" }
  exit 0
end

warn "::error::limits 鍵型別檢查器的回歸測試失敗（#{failures.size}/#{CASES.size}）："
failures.each { |f| warn "  - #{f}" }
warn "  🔴 這代表 scripts/check-limits-keys.rb 的判定邏輯壞了，或 fixture 被改動。"
exit 1
