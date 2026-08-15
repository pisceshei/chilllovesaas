#!/usr/bin/env ruby
# frozen_string_literal: true

# CI 對等性檢查——把「`bin/ci` 與 GitHub CI 要跑同一批檢查」從紀律變成機制。
#
# ## 背景（2026-08-15）
#
# `config/ci.rb` 在 2026-08-15 補上一段 🔴 條款，逐字寫著：
#   「**`bin/ci` 通過 ≠ CI 綠**⋯落差的後果是：本機全綠 → 推上去被擋，
#     而擋下來的理由是本機**沒有機會發現**的。⇒ 兩邊要同步。」
#
# 🔴 **那條條款在寫下它的隔天就被違反了**：PR #33 往 `.github/workflows/ci.yml`
# 的 quality job 加了 `check-limits-keys.rb` 與 `test-limits-key-rules.rb` 兩步，
# 而 `config/ci.rb` 一行未動。同時原註釋自稱「五個」自訂檢查，底下實際列六步、
# ci.yml 有九步——**三個數字互不相同，而 CI 是照 ci.yml 跑的那一份**。
#
# 這與本專案其他幾次事故同型（CLAUDE.md 鐵律 2 的白名單、AGENTS.md 的執行位元節）：
# **規則與機制各跑各的時，機制照樣跑，規則變成裝飾。**
# ⇒ 靠人記得同步守不住，改成 CI 擋。
#
# ## 檢查什麼
#
# 規則 1｜`.github/workflows/ci.yml` 裡被呼叫的每一支 `scripts/*.{rb,py,sh}`，
#        都必須出現在 `config/ci.rb` 的某個 `step` 指令裡。
#        （方向是單向的：ci.yml ⊆ ci.rb。ci.rb 可以多跑東西，不能少跑。）
#
# 比對的是**腳本路徑**而不是完整指令字串，因為兩邊的參數本來就可以不同——
# 例如 `check-baseline-raise.py` 在 ci.yml 傳 `FETCH_HEAD`（workflow 會先 fetch），
# 本機不傳而走預設 `origin/main`。強制指令逐字相同會逼出假的一致性。
#
# ## 不檢查什麼（🔴 誠實聲明，這段就是本腳本對外宣稱的契約，不得誇大）
#
#   1. **不檢查 inline shell 步驟**。ci.yml 的 `Verify bin/ and scripts/ are executable`
#      是直接寫在 workflow 裡的 shell，不是 `scripts/` 下的檔 ⇒ 本腳本看不到它，
#      `bin/ci` 也跑不到它。**這是已知缺口，不是已解決**。
#      要補的話正解是把它抽成 `scripts/check-exec-bits.sh`，那樣它就自動落入規則 1。
#   2. **不檢查步驟順序或名稱**，只檢查「有沒有跑到」。
#   3. **不檢查 `test` job**（migration／rspec／前端那些），那些本來就由 ci.rb 的
#      前八步以不同形式涵蓋，逐項對應會製造假精確。本腳本只管 quality job 的自訂檢查。
#   4. **不反向檢查**（ci.rb 有而 ci.yml 沒有不算違規）——本機多跑東西是好事。
#
# 用法：ruby scripts/check-ci-parity.rb
# 退出碼：0=通過，1=有落差
#
# 相關：`config/ci.rb` 的 🔴 同步條款、`.github/workflows/ci.yml` 的 quality job。

require "yaml"

ROOT = File.expand_path("..", __dir__)
WORKFLOW = File.join(ROOT, ".github/workflows/ci.yml")
CI_RB = File.join(ROOT, "config/ci.rb")

# `scripts/` 下被當成可執行檔呼叫的東西。副檔名限定三種，避免把
# `git ls-files -s bin/ scripts/`（目錄形式，非具體腳本）也算進來。
SCRIPT_REF = %r{scripts/[A-Za-z0-9_.\-]+\.(?:rb|py|sh)}

[ WORKFLOW, CI_RB ].each do |path|
  next if File.exist?(path)

  warn "::error::#{path.sub("#{ROOT}/", '')} 不存在——本腳本的前提不成立，請修正 scripts/check-ci-parity.rb。"
  exit 1
end

workflow = YAML.load_file(WORKFLOW, aliases: true)
quality = workflow.dig("jobs", "quality", "steps") || []

if quality.empty?
  warn "::error::.github/workflows/ci.yml 解析不到 jobs.quality.steps——" \
       "workflow 結構可能改了，本腳本會因此**靜默失去效力**，請先修本腳本再合併。"
  exit 1
end

# ci.yml 的 quality job 用到的腳本（step 名稱一併留著，錯誤訊息才指得出是哪一步）。
workflow_scripts = {}
quality.each do |step|
  run = step["run"].to_s
  run.scan(SCRIPT_REF) { |_| }
  run.to_enum(:scan, SCRIPT_REF).map { Regexp.last_match(0) }.each do |ref|
    workflow_scripts[ref] ||= step["name"].to_s
  end
end

ci_rb_source = File.read(CI_RB, encoding: "UTF-8")
# 只看 `step "...", "..."` 那一行的指令部分——註釋裡提到腳本名不算「有跑」。
# 🔴 這個區別很重要：本腳本自己的檔頭就大量提到腳本名，若連註釋都算數，
#    任何人只要在 ci.rb 寫一句「以後要加 xxx.rb」就能讓檢查變綠。
ci_rb_commands = ci_rb_source
                 .each_line
                 .select { |line| line =~ /^\s*step\s+/ }
                 .join("\n")
ci_rb_scripts = ci_rb_commands.to_enum(:scan, SCRIPT_REF).map { Regexp.last_match(0) }.uniq

missing = workflow_scripts.keys - ci_rb_scripts

if missing.empty?
  puts "OK：CI 對等性檢查通過"
  puts "  - ci.yml quality job 用到 #{workflow_scripts.size} 支腳本，config/ci.rb 全部涵蓋"
  puts "  - 比對的是腳本路徑不是完整指令（參數本來就可以不同，理由見檔頭）"
  puts "  - inline shell 步驟（執行位元閘門）不在檢查範圍，理由見檔頭誠實聲明"
  exit 0
end

warn "::error::CI 對等性檢查失敗（#{missing.size} 支腳本只在 ci.yml 跑、bin/ci 跑不到）："
missing.each do |ref|
  warn "  - #{ref}（ci.yml 的「#{workflow_scripts[ref]}」步驟）"
end
warn "  🔴 後果：本機 `bin/ci` 全綠 → push → CI 紅，而擋下來的理由本機沒有機會發現。"
warn "  修法：在 config/ci.rb 加上對應的 `step \"Invariants: ...\", \"<指令>\"`。"
warn "  （若某支刻意只在 CI 跑，請改本腳本並在檔頭誠實聲明寫明理由，不要靜默豁免。）"
exit 1
