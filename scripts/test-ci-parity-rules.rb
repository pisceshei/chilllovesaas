#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-ci-parity.rb` 的回歸測試（fixture 驅動）。
#
# ## 🔴 這支測試為什麼晚到
#
# `check-ci-parity.rb` 送審時（PR #39）**沒有回歸測試**，而它是同批新增的檢查器中
# 唯一沒有的一支——`check-limits-keys.rb`、`check-money-boundary.rb`、
# `check-exec-bits.sh`、`check-workflow-syntax.rb` 都有。
#
# 直接原因很具體：它把 `ROOT` **寫死**成倉庫根目錄，於是**沒有辦法**餵給它一個
# 故意違反的 fixture ⇒ 想寫測試的人會發現寫不了，然後就不寫了。
# 🔴 教訓：**「可測性」是檢查器的設計需求，不是寫完之後才想的事。**
# 一支只能對真倉庫跑的檢查器，等於宣告「我永遠不會被反向證明」。
# （修法＝接受 `ARGV[0]` 當 ROOT，形態比照另外兩支 check-*.rb。）
#
# 判準出處：`docs/specs/65` §K 第 7 條——**檢查本身也要被測試**，
# 一條永遠不會紅的 CI 規則等於沒有。
#
# ## 🔴 這張表是被實測打出來的，不是想出來的
#
# 加 ROOT 參數之後第一件事就是拿兩個 fixture 去打它，**兩個都沒打紅**：
#
#   parity_runner_collapse  →  exit 0（應該 exit 1）
#   parity_name_spoof       →  exit 0（應該 exit 1）
#
# 兩個都是真缺陷，都已在同一個 commit 修掉（詳見各 case 的說明欄）。
# ⇒ 這支測試不是「補文件」，它在被寫出來的當天就抓到了兩個活的 bug。
#
# 用法：ruby scripts/test-ci-parity-rules.rb
# 退出碼：0=全過，1=有失敗

ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(ROOT, "scripts/check-ci-parity.rb")
FIXTURES = File.join(ROOT, "spec/fixtures/ci_violations")

# (fixture 目錄, 期望 exit code, 輸出須包含的字串, 這條在防什麼)
CASES = [
  [ "parity_clean", 0, "OK：CI 對等性檢查通過",
    "🔴 反向斷言：乾淨 fixture 必須通過。缺這條，一個永遠 fail 的檢查器會讓下面每一條都「通過」" ],
  [ "parity_clean", 0, "另比對 2 組非 scripts/ 指令",
    "🔴 正向覆蓋數：規則 2 真的**認出**了 bin/rubocop 與 pnpm audit 兩組。" \
    "只斷言 exit 0 的話，把 KNOWN_RUNNERS 清空（規則 2 全面停擺）仍然全綠" ],

  [ "parity_missing_script", 1, "scripts/check-tenant-isolation.rb",
    "規則 1：ci.yml 跑了、config/ci.rb 沒跑的腳本必須被點名" ],

  [ "parity_runner_collapse", 1, "`npm audit`",
    "🔴 **實測抓到的活 bug（修前 exit 0）**：ci.yml 跑 `npm audit`、ci.rb 只有 `pnpm audit`。" \
    "舊寫法用 `line.include?(runner)` 比對，而 `\"pnpm audit\".include?(\"npm\")` ＝ true；" \
    "備援的正則 `/npm\\s+(?:-\\S+\\s+)*audit\\b/` 也命中 `pnpm audit` 的後半段 ⇒ 兩道防線一起失效。" \
    "修法＝兩側共用 command_key，比對完整 token 而不是子字串" ],

  [ "parity_name_spoof", 1, "scripts/check-limits-keys.rb",
    "🔴 **實測抓到的活 bug（修前 exit 0）**：`step \"TODO: 之後要加 ruby scripts/x.rb\", \"true\"`。" \
    "`step` 的簽名是 `step \"名稱\", \"指令\"`，兩段在**同一行** ⇒ 掃整行的話，" \
    "腳本名寫在**名稱**裡就算「有跑」。修法＝只取第二個引號字串" ],

  [ "parity_guard_disabled", 1, "本檢查自己不在 ci.yml 的 quality job 裡",
    "規則 3：有人把 `Check CI parity` 那一步從 ci.yml 刪掉時，" \
    "規則 1／2 的差集仍然是空的、本機呼叫仍然成功——同步保護會**靜默關掉**" ],

  [ "parity_no_quality", 1, "解析不到 jobs.quality.steps",
    "fail-closed：workflow 結構改了（job 改名／steps 搬家）時必須報錯。" \
    "靜默當成空陣列的話，規則 1／2 的來源側是空的 ⇒ 差集恆空 ⇒ **永遠通過**" ],

  [ "parity_unparsed_step", 1, "解析不出",
    "🔴 fail-closed：`step CHECKS[:parity]`（非兩段引號字串）無法判斷實際跑什麼。" \
    "靜默跳過的話，那一步會從對等性比對中消失，而症狀是「檢查通過」" ],

  [ "parity_no_steps", 1, "0 行 `step`",
    "🔴 canary：config/ci.rb 改寫成別的 DSL（一行 `step` 都不剩）時，" \
    "`ci_rb_scripts` 是空的 ⇒ 規則 1 會把**每一支腳本**都報成缺少，看似很紅；" \
    "但若同時 ci.yml 也空了就會靜默全綠。把「掃到 0 行」明講出來，" \
    "才分得出「沒有違規」與「沒有檢查」" ],

  [ "parity_comment_only", 0, "用到 1 支腳本",
    "🔴 反向斷言：`# 之後要加 ruby scripts/check-schema-drift.rb（還沒寫）` 這種" \
    "**整行註釋**不得被當成「有執行」，否則純文件的 workflow 改動會弄紅 CI。" \
    "斷言用**腳本計數**而不是 exit 0：只看 exit code 的話，" \
    "把註釋剝除邏輯拿掉會讓 ci.rb 那側也一起多算，仍可能兩邊抵銷成綠" ]
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
  puts "OK：CI 對等性檢查器的回歸測試通過（#{CASES.size} 條 / #{CASES.map(&:first).uniq.size} 個 fixture）"
  CASES.each { |dir, want_status, needle, why| puts "  - #{dir} → exit #{want_status}，含 `#{needle}`：#{why}" }
  exit 0
end

warn "::error::CI 對等性檢查器的回歸測試失敗（#{failures.size}/#{CASES.size}）："
failures.each { |f| warn "  - #{f}" }
warn "  🔴 這代表 scripts/check-ci-parity.rb 的判定邏輯壞了，或 fixture 被改動。"
exit 1
