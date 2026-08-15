#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-workflow-syntax.rb` 的回歸測試（fixture 驅動）。
#
# 65 §K.7 逐字：「**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有」。
#
# ## 四條各自守什麼
#
# 前兩條**直接對應 `claude-review.yml` 註釋裡記載的兩次真實事故**，不是想像出來的：
#   - `wf_bad_yaml`：block scalar 續行掉到第 0 欄 ⇒ 整份不再是合法 YAML（2026-08-14 踩過）
#   - `wf_bad_bash`：YAML 合法但 bash 語法壞掉 ⇒ **只驗 YAML 的檢查會放行**，
#     要到 CI 真的跑那一步才炸。這是最陰險的一種。
#
# 後兩條守檢查器本身：
#   - `wf_clean`：反向斷言。**刻意含 GitHub 表達式與 heredoc**——
#     `${{ }}` 直接送 bash 會是 bad substitution，heredoc 在 block scalar 裡合法，
#     兩者都是容易誤報的形態。這條同時證明「佔位符替換有效」與「不誤傷 heredoc」。
#   - `wf_empty`：一份 workflow 都找不到時必須 fail 而不是印 OK（空值長得像資料）。
#
# 用法：ruby scripts/test-workflow-syntax-rules.rb
# 退出碼：0=全過，1=有失敗

ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(ROOT, "scripts/check-workflow-syntax.rb")
FIXTURES = File.join(ROOT, "spec/fixtures/ci_violations")

# (fixture 目錄, 期望 exit code, 輸出須包含的字串, 這條在防什麼)
CASES = [
  [ "wf_clean", 0, "OK",
    "🔴 反向斷言：乾淨 workflow 必須通過，且**含 `${{ }}` 與 heredoc 也不得誤報**——" \
    "缺這條，一個永遠 fail 的檢查器會讓下面每條都「通過」" ],
  [ "wf_bad_yaml", 1, "YAML 解析失敗",
    "block scalar 續行掉到第 0 欄——claude-review.yml 註釋記載的 2026-08-14 真實事故" ],
  [ "wf_bad_bash", 1, "bash -n",
    "🔴 YAML 合法但 bash 語法壞掉——只驗 YAML 的檢查會放行，要到 CI 跑那一步才炸" ],
  [ "wf_bad_heredoc", 1, "但有警告",
    "🔴 **未閉合 heredoc**——`bash -n` 對它 **exit 0**、只在 stderr 印警告 ⇒ " \
    "只判退出碼的檢查器完全放行。而 claude-review.yml 記載的兩次語法事故，" \
    "**其中一次正是 heredoc** ⇒ 這道閘門原本擋不住它宣稱要守的兩件事之一" ],
  [ "wf_date_scalar", 0, "OK",
    "🔴 反向斷言之二：**合法但容易讓檢查器崩掉**。裸日期是合法 YAML，但 load_file 預設不許 " \
    "Date ⇒ 原本會丟 Psych::DisallowedClass 讓腳本帶著 backtrace 崩掉。" \
    "本份同時覆蓋自訂 shell 模板 `bash -e {0}`——原白名單不匹配它 ⇒ 該 run 區塊被靜默跳過不檢查" ],
  [ "wf_empty", 1, "一份 workflow 都沒找到",
    "🔴 掃不到檔案時必須 fail，不能印 OK（空值長得像資料）" ]
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

  failures << "#{dir}：exit code 對，但輸出不含「#{want_output}」（#{why}）\n      輸出：#{output.lines.first.to_s.strip}"
end

if failures.empty?
  puts "OK：workflow 語法檢查器的回歸測試通過（#{CASES.size} 條）"
  CASES.each { |dir, want_status, _, why| puts "  - #{dir} → exit #{want_status}：#{why}" }
  exit 0
end

warn "::error::workflow 語法檢查器的回歸測試失敗（#{failures.size}/#{CASES.size}）："
failures.each { |f| warn "  - #{f}" }
warn "  🔴 這代表 scripts/check-workflow-syntax.rb 的判定壞了，或 fixture 的前提變了。"
exit 1
