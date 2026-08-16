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
  step "Invariants: Prototype lint", "python3 scripts/lint-prototype.py"
  step "Invariants: Lint rules regression", "python3 scripts/test-lint-rules.py"
  # 🔴 文檔引用保真。理由見 ci.yml 對應步驟的註釋（九輪驗收裡 12/15 條 🔴 是文檔類）。
  #    本機不傳 --base，腳本預設 `origin/main`；取不到 base 時 R4／R5 略過並明說，
  #    R1／R3 仍為全樹 ⇒ 離線也不會誤擋。
  step "Invariants: Doc claims", "ruby scripts/check-doc-claims.rb"
  step "Invariants: Doc claim rules regression", "ruby scripts/test-doc-claims-rules.rb"
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
