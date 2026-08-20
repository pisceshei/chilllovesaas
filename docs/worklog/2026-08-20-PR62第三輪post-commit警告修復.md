# PR #62 第三輪 post-commit 警告修復

## 已完成的工作 (Done)

- 對 commit `f6c9b7a551efd64018add8c551a87d08d2d5951d` 實跑
  `ruby scripts/check-doc-claims.rb`；2026-08-20 快照為 exit 0、R5 warning 1，精確命中第三輪
  worklog 對內容錨重取方式的全稱用語。依 AGENTS.md 文件規則與階段一方案 §6.2，warning 仍
  fail-closed，已停止 push。
- 第三輪 worklog 已成歷史層，因此保留原句並在原處追加日期更正；更正附 exact ref、完整 handoff
  路徑與可執行的 `git grep -n -F`，讓原句的重取聲明有鄰近查法，而非靜默改寫已提交內容。
- 本修復沿用同一份第三輪倉庫外本地 handoff，不新增 repo handoff；本 worklog 已同步列入 91
  附錄 A.1，未把機械警告重複登記為 §3 產品坑。

## 修改的檔案與核心邏輯 (Changes)

- `docs/worklog/2026-08-20-PR62第三輪驗收修復.md`：原句旁追加日期更正與 exact-ref 重取命令。
- `docs/worklog/2026-08-20-PR62第三輪post-commit警告修復.md`：保存 post-commit 才可觀測的
  warning、處置與待辦。
- `docs/specs/91-pit-register.md`：附錄 A.1 補列本 worklog；§3 內容不變。

## 尚未完成或需注意的風險 (Pending / TODO)

- 修正後須依階段一方案 §6.2 回到完整閘門、另做 commit，再執行 post-commit doc-claims；下一次
  必須同時滿足 exit 0 與 warning 0，否則仍禁止 push。
- 本工作單位其後仍須完成鐵律 15、逐則回覆／resolve 三個 Codex threads，以及下一 exact head
  的 CI、Codex、Claude；鐵律 18.3 的人工合併邊界不變。
