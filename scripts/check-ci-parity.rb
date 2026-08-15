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
# 規則 1｜`.github/workflows/ci.yml` 的 quality job 裡被呼叫的每一支
#        `scripts/*.{rb,py,sh}`，都必須出現在 `config/ci.rb` 的某個 `step` 指令裡。
#        （方向是單向的：ci.yml ⊆ ci.rb。ci.rb 可以多跑東西，不能少跑。）
#
# 規則 2｜**非 `scripts/` 的檢查指令也要對等**（2026-08-15 依 PR #39 的 Codex review 新增）。
#        原本只比對 `scripts/*` ⇒ `pnpm audit --audit-level high` 這種**在 ci.yml 有、
#        ci.rb 沒有**的落差，本檢查**結構上看不到**——它宣稱要防的那類落差還留著一整類。
#        判準：只看 `KNOWN_RUNNERS` 開頭的行（`bin/*`／`pnpm`／`npm`／`bundle`／`rake`），
#        取「執行器 ＋ 第一個非旗標參數」當識別（例如 `pnpm audit`、`bin/rubocop`），
#        要求同一組出現在 ci.rb。
#        🔴 **刻意不解析任意 shell**：多行 run 區塊裡有 `bad=$(`、`done`、`| while` 這種碎片，
#           天真地逐行拆會產生一堆假規則。白名單式的取樣面小，但**不會製造假警報**。
#
# 規則 3｜**本檢查自己必須被 ci.yml 呼叫**（同上，Codex review 指出的自我約束缺口）。
#        規則 1 是單向的 ⇒ 有人把 `Check CI parity` 這一步從 ci.yml 刪掉時，
#        差集仍然是空的、本機呼叫仍然成功，**同步保護就這樣靜默關掉了**。
#        ⇒ 對這一支腳本本身做雙向檢查。
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
#
# 🔴 兩種寫法都要認（PR #39 的 Codex review 指出，已實測）：
#   ①**帶引號**的路徑（可含空白）：`ruby "scripts/check parity.rb"`
#   ②不帶引號、**可含子目錄**：`ruby scripts/ci/check.rb`
# 舊的字元類 `[A-Za-z0-9_.\-]+` 兩種都掃不到——遇到 `/` 或空白就停 ⇒
# **靜默失去覆蓋**（檢查器照樣 exit 0）。而本倉庫的執行位元閘門明文支援含空白的檔名，
# 這裡卻認不得同一種路徑，前後不一致。
SCRIPT_REF = %r{"scripts/[^"]+?\.(?:rb|py|sh)"|scripts/[^\s"';|&]+\.(?:rb|py|sh)}

# 規則 2 的取樣面：只認這些開頭的行。刻意窄，理由見檔頭。
KNOWN_RUNNERS = %w[pnpm npm bundle rake].freeze

# 規則 2 的豁免：CI 專屬的環境準備，不該要求 bin/ci 也跑。
# 🔴 逐項列舉、不得口頭擴充；加項目要在 PR 描述說明理由。
RUNNER_EXEMPT = [
  # runner 上要先裝依賴才跑得動任何東西；本機由 `bin/setup`（ci.rb 第一步）負責。
  "pnpm install"
].freeze

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

# 🔴 先剝掉**整行的 shell 註釋**再掃（PR #39 的 Codex review 指出）。
#    否則 `# See scripts/example.rb for context` 這種純說明會被當成「有執行」，
#    本檢查就會要求 ci.rb 補一支根本沒被呼叫的腳本 ⇒ **純文件的 workflow 改動會弄紅 CI**。
#    ⚠️ 只剝整行註釋，**不剝行尾的 `#`**——`sed 's/#//'` 那種寫法裡的 `#` 不是註釋，
#      剝了會改壞指令。取樣少一點，好過誤判。
#    （對稱性：ci.rb 那側早就只認 `step` 開頭的行、不認註釋。兩側現在一致。）
def command_lines(run)
  run.to_s.lines.map(&:rstrip).reject { |l| l.strip.empty? || l.strip.start_with?("#") }
end

# ci.yml 的 quality job 用到的腳本（step 名稱一併留著，錯誤訊息才指得出是哪一步）。
workflow_scripts = {}
# 規則 2：非 scripts/ 的「執行器 ＋ 第一個非旗標參數」。
workflow_commands = {}

quality.each do |step|
  name = step["name"].to_s
  lines = command_lines(step["run"])

  lines.join("\n").to_enum(:scan, SCRIPT_REF).map { Regexp.last_match(0) }.each do |ref|
    workflow_scripts[ref.delete('"')] ||= name
  end

  lines.each do |line|
    tokens = line.strip.split(/\s+/)
    runner = tokens.first.to_s
    next unless KNOWN_RUNNERS.include?(runner) || runner.start_with?("bin/")
    next if line.include?("scripts/") # 已由規則 1 涵蓋

    # 🔴 只有 `KNOWN_RUNNERS`（pnpm／npm／bundle／rake）才看子指令——
    #    它們的第一個非旗標參數確實是子指令（`pnpm audit`／`bundle exec`）。
    #    `bin/*` 一律**只看執行器本身**：它們是單一用途的包裝腳本，
    #    而它們的參數常是旗標的**值** ⇒ 取「第一個非旗標 token」會抓錯。
    #    實例：`bin/rubocop -f github` 會被讀成子指令 `github`，
    #    於是要求 ci.rb 有一個叫 `bin/rubocop github` 的步驟——**假警報**。
    arg = KNOWN_RUNNERS.include?(runner) ? tokens[1..].to_a.find { |t| !t.start_with?("-") } : nil
    key = [ runner, arg ].compact.join(" ")
    next if RUNNER_EXEMPT.include?(key)

    workflow_commands[key] ||= name
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
ci_rb_scripts = ci_rb_commands.to_enum(:scan, SCRIPT_REF).map { Regexp.last_match(0) }.map { |s| s.delete('"') }.uniq

missing = workflow_scripts.keys - ci_rb_scripts

# 規則 2：非 scripts/ 的指令對等。ci.rb 那側同樣只看 `step` 行。
missing_commands = workflow_commands.keys.reject do |key|
  runner, arg = key.split(" ", 2)
  ci_rb_commands.lines.any? do |line|
    next false unless line.include?(runner)
    arg.nil? || line.match?(/#{Regexp.escape(runner)}\s+(?:-\S+\s+)*#{Regexp.escape(arg)}\b/)
  end
end

# 規則 3：本檢查自己必須被 ci.yml 呼叫（否則同步保護會被靜默關掉）。
self_ref = "scripts/check-ci-parity.rb"
guard_disabled = !workflow_scripts.key?(self_ref)

if missing.empty? && missing_commands.empty? && !guard_disabled
  puts "OK：CI 對等性檢查通過"
  puts "  - ci.yml quality job 用到 #{workflow_scripts.size} 支腳本，config/ci.rb 全部涵蓋"
  puts "  - 另比對 #{workflow_commands.size} 組非 scripts/ 指令（bin/*／pnpm／npm／bundle／rake）"
  puts "  - 本檢查自己有被 ci.yml 呼叫（規則 3：單向差集擋不住「把這一步刪掉」）"
  puts "  - 比對的是腳本路徑與指令識別，不是完整參數（參數本來就可以不同，理由見檔頭）"
  puts "  - inline shell 步驟不在檢查範圍，理由見檔頭誠實聲明"
  exit 0
end

warn "::error::CI 對等性檢查失敗："

if guard_disabled
  warn "  🔴 **本檢查自己不在 ci.yml 的 quality job 裡**（找不到 #{self_ref}）。"
  warn "     規則 1／2 是單向差集 ⇒ 把 `Check CI parity` 那一步刪掉時，差集仍然是空的、"
  warn "     本機呼叫仍然成功，**同步保護就這樣靜默關掉了**。這是它必須自我約束的理由。"
  warn "     修法：把 `- name: Check CI parity` 那一步加回 ci.yml 的 quality job。"
end

unless missing.empty?
  warn "  #{missing.size} 支腳本只在 ci.yml 跑、bin/ci 跑不到："
  missing.each { |ref| warn "    - #{ref}（ci.yml 的「#{workflow_scripts[ref]}」步驟）" }
end

unless missing_commands.empty?
  warn "  #{missing_commands.size} 組指令只在 ci.yml 跑、bin/ci 跑不到："
  missing_commands.each { |key| warn "    - `#{key}`（ci.yml 的「#{workflow_commands[key]}」步驟）" }
end

warn "  🔴 後果：本機 `bin/ci` 全綠 → push → CI 紅，而擋下來的理由本機沒有機會發現。"
warn "  修法：在 config/ci.rb 加上對應的 `step \"...\", \"<指令>\"`。"
warn "  （若某項刻意只在 CI 跑，請加進本腳本的 RUNNER_EXEMPT 並在 PR 描述說明理由，不要靜默豁免。）"
exit 1
