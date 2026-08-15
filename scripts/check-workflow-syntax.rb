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
# 一個表達式都沒有（實測 25 個 run 區塊、0 個），但第一個用它的人不該撞到假警報。
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
require "tempfile"
require "open3"

ROOT = ARGV[0] ? File.expand_path(ARGV[0]) : File.expand_path("..", __dir__)
WORKFLOW_DIR = File.join(ROOT, ".github", "workflows")

# GitHub 表達式換成一個合法的 bash token，避免 `${{` 被當成 bad substitution。
GH_EXPR = /\$\{\{.*?\}\}/m
# 只有這些 shell（或未宣告＝預設 bash）才送去 bash -n。
BASH_SHELLS = [ nil, "bash", "sh" ].freeze

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
    doc = YAML.load_file(path, aliases: true)
  rescue Psych::SyntaxError => e
    violations << "#{rel}:#{e.line} YAML 解析失敗——#{e.problem}。" \
      "🔴 最常見原因：block scalar（`run: |`）的續行縮排掉到第 0 欄，" \
      "或 heredoc 內容與 YAML 縮排打架。"
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
      script = step["run"]
      next unless script

      shell = step["shell"] || job.dig("defaults", "run", "shell") || doc.dig("defaults", "run", "shell")
      next unless BASH_SHELLS.include?(shell)

      checked_runs += 1
      label = step["name"] || "第 #{idx + 1} 步"

      Tempfile.create([ "wf-run-", ".sh" ]) do |f|
        f.write(script.gsub(GH_EXPR, "GHEXPR"))
        f.flush
        _out, err, status = Open3.capture3("bash", "-n", f.path)
        next if status.success?

        detail = err.lines.map(&:strip).reject(&:empty?).first.to_s
        violations << "#{rel} 的 job `#{job_name}` / 步驟「#{label}」的 run 區塊 " \
          "**bash -n 不通過**：#{detail}"
      end
    end
  end
end

if violations.empty?
  puts "OK：workflow 語法檢查通過"
  puts "  - #{checked_files} 份 workflow 皆為合法 YAML"
  puts "  - #{checked_runs} 個 run 區塊皆通過 bash -n（GitHub 表達式已換成佔位符）"
  puts "  - 不驗證 action inputs／表達式語義／執行期行為，理由見檔頭誠實聲明"
  exit 0
end

warn "::error::workflow 語法檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
warn "  🔴 `.github/workflows/claude-review.yml` 動到的 PR **拿不到 Claude 驗收**（反竄改機制），"
warn "     所以它的語法錯誤只有這一步擋得住。不要略過。"
exit 1
