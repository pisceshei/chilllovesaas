#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-workflow-syntax.rb` 的回歸測試（fixture 驅動）。
#
# 65 §K.7 逐字：「**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有」。
#
# ## 🔴 這幾條各自守什麼（**不寫死條數**——已過期兩次；實跑輸出為準。改組成時這裡、handoff、worklog 三處要一起改）
#
# **對應 `claude-review.yml` 註釋記載的兩次真實事故**
#   - `wf_bad_yaml`：block scalar 續行掉到第 0 欄 ⇒ 整份不再是合法 YAML（2026-08-14）
#   - `wf_bad_heredoc`：未閉合 heredoc——`bash -n` 對它 **exit 0**、只在 stderr 印警告
#     ⇒ 只判退出碼的檢查器完全放行
#     🔴 **該 fixture 的 `shell: bash --noprofile --norc -eo pipefail {0}` 那一行是承重的**，
#       不得因為「看起來跟 heredoc 無關」而刪掉（見該檔檔頭註釋）。
#
# **判準本身**
#   - `wf_bad_bash`：YAML 合法但 bash 語法壞掉 ⇒ 只驗 YAML 的檢查會放行
#   - `wf_custom_shell`：🔴 `interpreter_for` 的**正向**斷言——自訂 shell 模板下的壞 bash 必須被抓到
#
# **反向斷言（不得誤報）**
#   - `wf_clean`：刻意含 `${{ }}` 與 heredoc——前者直接送 bash 會是 bad substitution，
#     後者在 block scalar 裡合法。同時證明「佔位符替換有效」
#   - `wf_date_scalar`：裸日期是合法 YAML，但 `load_file` 預設不許 Date
#     ⇒ 原本會丟 `Psych::DisallowedClass` 讓腳本帶著 backtrace 崩掉
#   - `wf_nil_step`：steps 多打一個 `-`（空元素）——合法 YAML、step 是 nil，
#     無 Hash 防護時 `nil["run"]` 崩掉（與裸日期同形態，入口不同；2026-08-16 加）
#   - `wf_bad_defaults`：`defaults:` 掛字串——`dig` 對 String 崩（第三入口；2026-08-16 加）
#   - `wf_bad_run_defaults`：`defaults.run:` 掛字串／`run:` 掛 sequence／`steps:` 掛 scalar
#     ——第四／五／六入口三形態合一份（2026-08-16 加；PR #49 首輪指出本清單漏列這兩條）
#
# **「什麼都沒驗到」的兩層**
#   - `wf_empty`：一份 workflow 都找不到 ⇒ fail（空值長得像資料）
#   - `wf_no_runs`：🔴 找到了檔、卻 **0 個 run 區塊**被檢查 ⇒ 也必須 fail
#
# <!-- 2026-08-15 依 PR #42 的 Claude 驗收改寫。原文寫「四條」而 CASES 實際有六條，
#      `wf_bad_heredoc` 與 `wf_date_scalar` 完全沒進清單；且反向斷言已不是「後兩條」。
#      本輪又新增兩條 ⇒ 當時八條；2026-08-16 加 wf_nil_step。條數不再寫死。 -->
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
    "✅ 本份**同時覆蓋**自訂 shell 模板（`bash -e {0}`），而且是**承重的**：" \
    "它只有一個 run 區塊，interpreter_for 回歸 ⇒ 該區塊被跳過 ⇒ checked_runs=0 " \
    "⇒ 第二層 canary exit 1，而本條期望 0 ⇒ 變紅（2026-08-16 突變實測確認）。" \
    "🔴 2026-08-16 更正（第 2 輪驗收指出，複驗成立）：本欄原寫「不覆蓋⋯跳過也是 exit 0，" \
    "分不出來」——那在 checked_runs canary 加入後就不成立了：canary 正是讓" \
    "「跳過」與「通過」分得出來的那一層。原敘述會讓人以為 ok.yml 的 shell 行只是裝飾。" \
    "正向斷言（壞 bash 在自訂 shell 下被抓）仍在 wf_custom_shell，兩份守不同方向" ],
  [ "wf_nil_step", 0, "1 個 run 區塊",
    "🔴 反向斷言之三：steps 多打一個 `-`（空元素）——合法 YAML、step 是 nil。" \
    "無 is_a?(Hash) 防護時 `nil[\"run\"]` 崩掉（與裸日期同形態，入口不同）。" \
    "needle 用 run 計數：只斷言 exit 0 的話，「崩掉之前一個都沒檢查」與" \
    "「跳過 nil 後正常檢查」在有 rescue 的未來版本裡可能分不出來。" \
    "⚠️ needle 依賴 fixture 恰好一個 run 區塊（該檔檔頭有承重註記）" ],
  [ "wf_bad_defaults", 0, "1 個 run 區塊",
    "🔴 反向斷言之四：`defaults:` 掛字串——合法 YAML、`dig` 對 String 丟 TypeError 崩掉。" \
    "與裸日期／nil step 同形態的第三個入口（第 4 輪驗收指出，實測復現）。" \
    "needle 用 run 計數：崩掉時一個都沒檢查，計數分得出來" ],
  [ "wf_bad_run_defaults", 0, "1 個 run 區塊",
    "🔴 反向斷言之五＋六＋第六入口（PR #42 第 6 輪＋PR #48 首輪）：`defaults.run:` 掛字串" \
    "（dig 第四入口）、step `run:` 掛 sequence（gsub 第五入口）、job `steps:` 掛 scalar" \
    "（each_with_index 第六入口）都不得崩潰。" \
    "needle 用 run 計數：sequence 形與 scalar 形被跳過、真 run 被檢查，1 個才是對的" ],
  [ "wf_custom_shell", 1, "bash -n",
    "🔴 **`interpreter_for` 的正向斷言**：官方文件化的自訂 shell 模板 " \
    "`bash --noprofile --norc -eo pipefail {0}` 下的壞 bash **必須被抓到**。" \
    "舊白名單不匹配它 ⇒ 靜默跳過；而期望 exit 0 的 fixture 分不出這件事" ],
  [ "wf_no_runs", 1, "0 個 run 區塊",
    "🔴 **第二層零掃描**：掃到了檔但 0 個 run 區塊被檢查，同樣是「什麼都沒驗到」。" \
    "舊寫法印「0 個 run 區塊皆通過 bash -n」並 exit 0——" \
    "而那正是 interpreter_for 回歸會產生的形態，閘門對自己剛修好的故障綠著通過" ],
  [ "wf_empty", 1, "一份 workflow 都沒找到",
    "🔴 掃不到檔案時必須 fail，不能印 OK（空值長得像資料）" ]
].freeze

# 🔴 canary：本測試自己也會「沒有失敗」與「沒有檢查」長得一模一樣。
#    把 CASES 清空，這支會印「OK（0 條）」並 exit 0——姊妹檔 test-doc-claims-rules.rb
#    一直有這一層而本檔漏了（PR #48 首輪驗收指出）。數字只准往上調；要調低必須在
#    PR 描述說明刪了哪一條、為什麼不再需要。
MIN_CASES = 11
if CASES.size < MIN_CASES
  warn "::error::CASES 只剩 #{CASES.size} 條（下限 #{MIN_CASES}）——這不是通過，是檢查被砍掉了。"
  exit 1
end

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
