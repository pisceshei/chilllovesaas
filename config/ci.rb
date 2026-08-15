# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Test: Rails", "bundle exec rspec"
  step "Test: Frontend", "pnpm test"
  step "Type check: Frontend", "pnpm typecheck"
  step "Build: Frontend", "pnpm build"

  # 🔴 **`bin/ci` 通過 ≠ CI 綠**（2026-08-15 補齊，理由寫下來免得又被漏掉）。
  # 本檔原本只有上面八步，而 `.github/workflows/ci.yml` 的 quality job 另外跑
  # **五個**專案自訂檢查 ＋ schema drift。落差的後果是：本機全綠 → 推上去被擋，
  # 而擋下來的理由是本機**沒有機會發現**的。
  # ⇒ 兩邊要同步。以下逐一對應 ci.yml 的 quality job。
  # 🔴 2026-08-15 抽出：原本是 ci.yml 的 inline shell，**本機完全跑不到**。
  #    抽成腳本之後 bin/ci 才守得住「Windows 提交的檔案缺執行位元」這一類——
  #    那正是 2026-08-14 CI 全紅的原因，而它在本機一直是綠的。
  step "Invariants: Exec bits", "bash scripts/check-exec-bits.sh"
  step "Invariants: Exec bit rules regression", "bash scripts/test-exec-bits-rules.sh"
  step "Invariants: Prototype lint", "python3 scripts/lint-prototype.py"
  step "Invariants: Lint rules regression", "python3 scripts/test-lint-rules.py"
  step "Invariants: Tenant isolation", "ruby scripts/check-tenant-isolation.rb"
  step "Invariants: Reversal naming", "ruby scripts/check-reversal-naming.rb"
  # 鐵律 3 的 L4。與下一步是一組：檢查器自己綠不算交付（65 §K 第 7 條）。
  step "Invariants: Money unit boundary", "ruby scripts/check-money-boundary.rb"
  step "Invariants: Money rules regression", "ruby scripts/test-money-rules.rb"


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
