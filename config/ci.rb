# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  # 🔴 2026-08-15 補（PR #39 的 Codex review 指出）：ci.yml 的 quality job 跑
  #    `pnpm audit --audit-level high`，而本檔沒有等價步驟——**本機全綠但 CI 會紅**，
  #    正是本檔那條同步條款要防的落差。而當時的 check-ci-parity.rb **結構上看不到它**
  #    （只比對 `scripts/*`）⇒ 該檢查同輪已擴充為也比對 bin/*／pnpm 這類指令。
  # ⚠️ 需要網路（查 npm advisory DB）；離線跑 bin/ci 會紅在這一步，不是你弄壞的。
  #    check-baseline-raise.py 那種「取不到基準優雅略過」**刻意不套用**在安全稽核上——
  #    安全檢查靜默略過比紅燈更糟。
  step "Security: Frontend audit", "pnpm audit --audit-level high"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Test: Rails", "bundle exec rspec"
  step "Test: Frontend", "pnpm test"
  step "Type check: Frontend", "pnpm typecheck"
  step "Build: Frontend", "pnpm build"

  # 🔴 **`bin/ci` 通過 ≠ CI 綠**（2026-08-15 補齊，理由寫下來免得又被漏掉）。
  # 本檔原本只有上面那批通用步驟（bin/setup／rubocop／audit／rspec／pnpm 等；
  # 2026-08-15 建檔時 8 步，現為 9 步 ⇒ 🔴 **不要在敘述裡寫死步數**，它會過時），
  # 而 `.github/workflows/ci.yml` 的 quality job 另外跑一批專案自訂檢查。
  # 落差的後果是：本機全綠 → 推上去被擋，而擋下來的理由是本機**沒有機會發現**的。
  # ⇒ 兩邊要同步。以下逐一對應 ci.yml 的 quality job。
  #
  # 🔴 **原文在這裡多寫了「＋ schema drift」，2026-08-15 刪除——那句話是錯的，**
  #    **而且錯得會誘導出一個有害的修法。** 事實：
  #    `Verify schema.rb has no drift`（`git diff --exit-code db/schema.rb`）在
  #    **`test` job**（ci.yml:100），不在 quality job；`services: mysql` 也只掛在 test job 上。
  #    照原文去理解的人會想「那 parity 檢查應該也要涵蓋 schema drift」，
  #    於是往 quality job 加一支 `check-schema-drift.rb`——**而 quality job 連不上資料庫**，
  #    那支腳本的「連不上就 exit 0」分支會**每次都命中** ⇒ 得到一個
  #    **結構上不可能失敗的步驟**，比沒有這一步更糟（它看起來像有在守）。
  #    ⇒ schema drift 的正確歸屬就是 test job，本檔不對等它（同「不檢查 test job」的理由）。
  #
  # 🔴 **這條「兩邊要同步」的條款，在寫下它的隔天就被違反了**（2026-08-15）：
  #    PR #33 往 ci.yml 加了 `check-limits-keys.rb` 與 `test-limits-key-rules.rb` 兩步，
  #    本檔一行未動；同時原註釋自稱「**五個**」而底下實際列了六步、ci.yml 有九步——
  #    三個數字互不相同。**紀律守不住，所以改成機制**：
  #    `scripts/check-ci-parity.rb` 會斷言 ci.yml 引用的每一支 `scripts/*` 都出現在本檔，
  #    對不上就 CI fail。⇒ 以後漏同步會被擋下來，不必靠人記得。
  #    （同型教訓：CLAUDE.md 鐵律 2 白名單、AGENTS.md 執行位元節，都是「規則與機制分岔」。）
  # 🔴 2026-08-15 抽出：原本是 ci.yml 的 inline shell，**本機完全跑不到**。
  #    抽成腳本之後 bin/ci 才守得住「Windows 提交的檔案缺執行位元」這一類——
  #    那正是 2026-08-14 CI 全紅的原因，而它在本機一直是綠的。
  step "Invariants: Exec bits", "bash scripts/check-exec-bits.sh"
  step "Invariants: Exec bit rules regression", "bash scripts/test-exec-bits-rules.sh"
  step "Invariants: Prototype lint", "python3 scripts/lint-prototype.py"
  step "Invariants: Lint rules regression", "python3 scripts/test-lint-rules.py"
  # ci.yml 傳 FETCH_HEAD（它會先 `git fetch --depth=1`）；本機不傳，
  # 腳本預設 base＝`origin/main`，取不到基準時**優雅略過並 exit 0**（見該檔 :62、:67-68），
  # 所以離線也不會誤擋。
  step "Invariants: Dead-control baseline", "python3 scripts/check-baseline-raise.py"
  # 🔴 文檔引用保真。理由見 ci.yml 對應步驟的註釋（九輪驗收裡 12/15 條 🔴 是文檔類）。
  #    本機不傳 --base，腳本預設 `origin/main`；取不到 base 時 R4／R5 略過並明說，
  #    R1／R3 仍為全樹 ⇒ 離線也不會誤擋。
  step "Invariants: Doc claims", "ruby scripts/check-doc-claims.rb"
  step "Invariants: Doc claim rules regression", "ruby scripts/test-doc-claims-rules.rb"
  step "Invariants: Tenant isolation", "ruby scripts/check-tenant-isolation.rb"
  step "Invariants: Design token single source", "ruby scripts/check-tokens-sync.rb"
  step "Invariants: Reversal naming", "ruby scripts/check-reversal-naming.rb"
  # 鐵律 3 的 L4。與下一步是一組：檢查器自己綠不算交付（65 §K 第 7 條）。
  step "Invariants: Money unit boundary", "ruby scripts/check-money-boundary.rb"
  step "Invariants: Money rules regression", "ruby scripts/test-money-rules.rb"
  # 鐵律 6 的鍵契約。與下一步是一組，同 65 §K.7 的理由。
  step "Invariants: Limits key types", "ruby scripts/check-limits-keys.rb"
  step "Invariants: Limits key rules regression", "ruby scripts/test-limits-key-rules.rb"
  # D68 的 B 道：--t-/--lh- 兩族必須全部 rem（預設 16px 下零視覺差，
  # 渲染層驗收驗不出漏轉 ⇒ 靜態檢查是唯一對 token 表完整的一道）。與下一步成對（65 §K.7）。
  step "Invariants: Rem token integrity", "ruby scripts/check-rem-tokens.rb"
  step "Invariants: Rem token rules regression", "ruby scripts/test-rem-token-rules.rb"
  # 🔴 本步驟守的就是上面那條同步條款本身。它必須同時出現在本檔與 ci.yml——
  #    只掛在 ci.yml 上的話，本機跑不到；只寫在本檔的話，CI 擋不住。
  # 🔴 方向別寫反（2026-08-15 依 PR #39 的 Claude 驗收更正，原文寫 `ci.yml ⊇ config/ci.rb`）：
  #    腳本自己的契約在 `scripts/check-ci-parity.rb:25` 逐字是
  #    「方向是單向的：**ci.yml ⊆ ci.rb**。ci.rb 可以多跑東西，不能少跑。」
  #    ⇒ 步驟名寫反了，而這行就印在 `bin/ci` 的輸出上，是多數人唯一會看到的方向說明。
  step "Invariants: CI parity (ci.yml ⊆ config/ci.rb)", "ruby scripts/check-ci-parity.rb"
  # 🔴 上一步的反向證明——**沒有它，上一步壞掉不會有人知道**。
  #    它補上的當天就抓到兩個讓對等性檢查靜默 exit 0 的活 bug，
  #    形態與其餘 test-*.rb 相同（65 §K.7：檢查本身也要被測試）。
  step "Invariants: CI parity rules regression", "ruby scripts/test-ci-parity-rules.rb"
  # workflow 的語法閘門。本機跑得到特別有價值：改 claude-review.yml 的 PR
  # 拿不到 Claude 驗收（反竄改），本機這一步是它上線前唯一的機械檢查。
  step "Invariants: Workflow syntax", "ruby scripts/check-workflow-syntax.rb"
  step "Invariants: Workflow syntax rules regression", "ruby scripts/test-workflow-syntax-rules.rb"


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
