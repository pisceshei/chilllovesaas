#!/usr/bin/env ruby
# frozen_string_literal: true

# GitHub Actions workflow 的語法閘門——YAML 可解析 ＋ 每個 `run:` 區塊過 `bash -n`。
#
# ## 為什麼存在（2026-08-15）
#
# `.github/workflows/claude-review.yml` 有一支 240+ 行的閉環 shell 腳本，
# 而它**依設計不會被自己的驗收流程覆蓋**（反竄改機制：動該檔的 PR，驗收步驟整個跳過）。
# 同時 repo 的 CI **沒有任何一步**解析 workflow YAML 或跑 `bash -n`。
#
# 🔴 該檔自己的註釋記載它已經被同型語法錯誤咬過**兩次**：
#   - YAML block scalar 續行落在第 0 欄 ⇒ 整份 workflow 不再是合法 YAML
#   - heredoc 的同型事故
# 兩次都是「改的時候看起來沒問題，推上去才發現」。而反竄改讓它連驗收都拿不到，
# ⇒ 這個檔是全倉庫**最需要機械語法檢查、卻最沒有保護**的地方。
#
# ## 檢查什麼
#
# 規則 1｜`.github/workflows/*.yml` 每一份都必須是**合法 YAML**。
# 規則 2｜每個 step 的 `run:` 區塊都必須過 **`bash -n`**（語法檢查，不執行）。
#
# GitHub 表達式 `${{ ... }}` 在送給 bash 之前會被換成佔位符 `GHEXPR`——
# bash 看到 `${{` 會當成 bad substitution 而誤報。目前倉庫的 run 區塊裡
# （寫下當時的快照：25 個 run 區塊、0 個表達式；現值以本腳本實跑輸出為準——
# 2026-08-16 起 ci.yml 的 doc-claims 步驟已含 `${{ }}`，佔位符替換**已實際生效**，不再只是預防。）
#
# ## 不檢查什麼（🔴 誠實聲明，這段就是本腳本對外宣稱的契約，不得誇大）
#
#   1. **這不是 actionlint**。不驗證 action 的 inputs 是否存在、不驗證 `${{ }}` 內的
#      表達式語法、不檢查 `needs:`／`if:` 的語義、不檢查 secrets 是否宣告。
#      （前例：`claude-review.yml` 的註釋記載 `with: model:` 在 v1 是**未知 input，
#      GitHub 靜默忽略** ⇒ 那一類要靠 actionlint 或讀 action.yml，本腳本抓不到。）
#   2. **`bash -n` 只看語法，不看行為**。變數拼錯、`set -e` 的交互、
#      管線退出碼、命令不存在——全部抓不到。
#   3. **只檢查 `run:` 是 bash 的步驟**。宣告了 `shell: pwsh`／`python` 的一律跳過
#      （目前倉庫沒有這種步驟）。
#   4. **不檢查 composite action 或 reusable workflow**（目前倉庫沒有）。
#
# 用法：ruby scripts/check-workflow-syntax.rb [ROOT]
#   ROOT 省略時＝本倉庫根目錄。傳入時檢查該目錄下的 .github/workflows——
#   給 `scripts/test-workflow-syntax-rules.rb` 用。
# 退出碼：0=通過，1=有問題
#
# 相關：`.github/workflows/claude-review.yml` 檔頭（反竄改與兩次語法事故的記錄）。

require "yaml"
require "date"
require "tempfile"
require "open3"

ROOT = ARGV[0] ? File.expand_path(ARGV[0]) : File.expand_path("..", __dir__)
WORKFLOW_DIR = File.join(ROOT, ".github", "workflows")

# GitHub 表達式換成一個合法的 bash token，避免 `${{` 被當成 bad substitution。
# ⚠️ 非貪婪 ⇒ 表達式內若含 `}}` 字面（例如 `fromJSON('{"a":{}}')`）會截錯。
#    （初版寫「目前倉庫 0 個表達式」——已過時，ci.yml 現有 `${{ }}`；本註釋改為：真出問題時是 bash -n 誤報（**吵而不是靜默**），
#    那是可接受的失效方向。
GH_EXPR = /\$\{\{.*?\}\}/m

# 🔴 YAML 允許裸日期（`2026-08-15`），而 `YAML.load_file` 預設不許 Date
#    ⇒ 會丟 `Psych::DisallowedClass`。本腳本原本只 rescue `Psych::SyntaxError`，
#    那條路徑會讓腳本**帶著 Ruby backtrace 崩掉**，而不是報告違規。
#    （PR #42 的 Codex review 指出，已實測重現。）
PERMITTED = [ Date, Time, Symbol ].freeze

# 判斷一個 `shell:` 宣告該不該送去語法檢查、以及用哪個直譯器。
#
# 🔴 GitHub 的 `shell:` **可以是自訂模板**，例如 `bash -e {0}`、
#    `bash --noprofile --norc -eo pipefail {0}`（後者正是 `run:` 的預設）。
#    原本用 `[nil, "bash", "sh"].include?(shell)` 判斷 ⇒ 這些寫法**一個都不匹配**，
#    那些 run 區塊會被**靜默跳過不檢查**——又是「檢查沒驗到目標」。
#    （PR #42 的 Codex review 指出。）
# 回傳：要用的直譯器字串，或 nil＝不檢查（pwsh／python 等）。
def interpreter_for(shell)
  return "bash" if shell.nil?

  head = shell.to_s.strip.split(/\s+/).first.to_s
  case File.basename(head)
  when "bash" then "bash"
  when "sh"   then "sh"   # 宣告 sh 就用 sh -n 檢查，不要用 bash 的寬鬆語法放行
  end
end

violations = []
checked_files = 0
checked_runs = 0

files = Dir.glob(File.join(WORKFLOW_DIR, "*.yml")).sort + Dir.glob(File.join(WORKFLOW_DIR, "*.yaml")).sort

if files.empty?
  # 🔴 掃到 0 份不是「通過」，是這次檢查什麼都沒驗到（同 check-exec-bits.sh 的 canary）。
  warn "::error::#{WORKFLOW_DIR} 下一份 workflow 都沒找到——這不是通過，是檢查沒有生效。"
  warn "  常見原因：跑錯目錄、目錄被改名。ROOT=#{ROOT}"
  exit 1
end

files.each do |path|
  rel = path.sub("#{ROOT}/", "").tr("\\", "/")
  checked_files += 1

  begin
    doc = YAML.load_file(path, aliases: true, permitted_classes: PERMITTED)
  rescue Psych::SyntaxError => e
    violations << "#{rel}:#{e.line} YAML 解析失敗——#{e.problem}。" \
      "🔴 最常見原因：block scalar（`run: |`）的續行縮排掉到第 0 欄，" \
      "或 heredoc 內容與 YAML 縮排打架。"
    next
  rescue Psych::Exception => e
    # 例如 DisallowedClass。仍然報成違規，**不要讓腳本崩掉**——
    # 崩掉的話 CI 只看得到 Ruby backtrace，讀的人不知道是哪份 workflow 的問題。
    violations << "#{rel} YAML 載入失敗（#{e.class}）：#{e.message}"
    next
  end

  jobs = doc.is_a?(Hash) ? doc["jobs"] : nil
  unless jobs.is_a?(Hash)
    violations << "#{rel} 解析得到的結構沒有 `jobs` mapping——" \
      "workflow 格式可能改了，本腳本會因此**靜默失去效力**，請先修本腳本。"
    next
  end

  jobs.each do |job_name, job|
    next unless job.is_a?(Hash)

    (job["steps"] || []).each_with_index do |step, idx|
      # 🔴 steps 底下多打一個 `-`（空元素）在 YAML 合法 ⇒ step 是 nil，
      #    `nil["run"]` NoMethodError 帶 backtrace 崩掉——與裸日期（wf_date_scalar）
      #    修掉的是同一形態（合法輸入讓檢查器崩），只是入口不同。
      #    與上方 `next unless job.is_a?(Hash)` 對稱（第 2 輪驗收 🟡）。
      next unless step.is_a?(Hash)

      script = step["run"]
      next unless script

      # 🔴 `defaults:` 掛一個字串是合法 YAML ⇒ `dig` 對 String 丟 TypeError 帶 backtrace 崩掉
      #    ——與裸日期（wf_date_scalar）、nil step（wf_nil_step）同形態的**第三個入口**
      #    （第 4 輪驗收指出，實測復現）。fixture＝wf_bad_defaults。
      job_defaults = job["defaults"].is_a?(Hash) ? job["defaults"] : {}
      doc_defaults = doc["defaults"].is_a?(Hash) ? doc["defaults"] : {}
      shell = step["shell"] || job_defaults.dig("run", "shell") || doc_defaults.dig("run", "shell")
      interpreter = interpreter_for(shell)
      next unless interpreter

      checked_runs += 1
      label = step["name"] || "第 #{idx + 1} 步"

      Tempfile.create([ "wf-run-", ".sh" ]) do |f|
        f.write(script.gsub(GH_EXPR, "GHEXPR"))
        f.flush
        # LC_ALL=C：stderr 非空即違規的判準下，locale 差異（某些 runner 對非 C locale
        # 印告警）會一次把全部 run 區塊打紅、反而看不出根因（第 2 輪驗收 🟡）。
        _out, err, status = Open3.capture3({ "LC_ALL" => "C" }, interpreter, "-n", f.path)
        noise = err.lines.map(&:strip).reject(&:empty?)

        # 🔴 **只看退出碼是不夠的**（PR #42 的 Codex review 指出，已實測）：
        #    `bash -n` 對**未閉合的 heredoc** 會 **exit 0**，只在 stderr 印一句
        #    `warning: here-document at line N delimited by end-of-file (wanted 'EOF')`。
        #    ⇒ 只判 `status.success?` 的話，這一類**完全放行**。
        #    而 `claude-review.yml` 記載的兩次語法事故，**其中一次正是 heredoc**——
        #    也就是說這道閘門原本擋不住它宣稱要守的兩件事之一。
        #    修法：**stderr 有任何輸出就算違規**。實測本倉庫 27 個 run 區塊 stderr 全空，
        #    所以這條不會製造誤報；而它的失效方向是「吵」不是「靜默」，那是對的方向。
        next if status.success? && noise.empty?

        detail = noise.first.to_s
        kind = status.success? ? "#{interpreter} -n 雖然 exit 0，但有警告" : "#{interpreter} -n 不通過"
        violations << "#{rel} 的 job `#{job_name}` / 步驟「#{label}」的 run 區塊 **#{kind}**：#{detail}"
      end
    end
  end
end

if violations.empty?
  # 🔴 **第二層 canary：run 區塊掃到 0 個也是「什麼都沒驗到」**
  #    （2026-08-15，PR #42 的 Claude 驗收指出）。
  #    上面已經對「一份 workflow 都沒找到」做了 canary，但**同一個判準在下一層缺席**：
  #    若所有 run 區塊都被 `interpreter_for` 跳過（這正是本檔第三條修正在修的
  #    回歸形態），舊寫法會印「**0 個 run 區塊皆通過 bash -n**」並 exit 0。
  #    ⇒ **這道閘門對它自己剛修好的那類故障，會綠著通過。**
  #    出處：docs/specs/65 §K 第 7 條＋本檔上方 files.empty? 那段的同一個理由。
  if checked_runs.zero?
    warn "::error::掃到 #{checked_files} 份 workflow，但 **0 個 run 區塊**被檢查——這不是通過，是檢查沒有生效。"
    warn "  常見原因：interpreter_for 回歸（全部 shell 被判成不認得）、或 workflow 真的只有 uses: 步驟。"
    warn "  若確實是後者，請在這裡放寬判準並寫明理由；不要默默印 OK。"
    warn "  ROOT=#{ROOT}"
    exit 1
  end

  puts "OK：workflow 語法檢查通過"
  puts "  - #{checked_files} 份 workflow 皆為合法 YAML"
  puts "  - #{checked_runs} 個 run 區塊皆通過 shell 語法檢查（bash/sh -n；GitHub 表達式已換成佔位符）"
  puts "  - 不驗證 action inputs／表達式語義／執行期行為，理由見檔頭誠實聲明"
  exit 0
end

warn "::error::workflow 語法檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
warn "  🔴 `.github/workflows/claude-review.yml` 動到的 PR **拿不到 Claude 驗收**（反竄改機制），"
warn "     所以它的語法錯誤只有這一步擋得住。不要略過。"
exit 1
