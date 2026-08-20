# PR #62 第三輪 post-commit 警告第二次修復

## 已完成的工作 (Done)

- 對 commit `93a02cd880ed519a9c02bfbd8654804d77d5f8c3` 重跑
  `ruby scripts/check-doc-claims.rb`；2026-08-20 快照仍為 exit 0、R5 warning 1，命中與
  `f6c9b7a` 相同的第三輪 worklog 句子，因此再次停止 push。
- 讀取 checker 實作確認原因：`near?` 只取目標行前後 2 行，`RECHECK_CMD` 只認同一窗口內的
  backtick 指令。第一次更正的 `git grep` 位於窗口外，故修法語義正確但機械防線仍看不到。
- 保留原句及第一次更正，在原句正下方追加第二次日期更正；該行直接帶 exact-ref `git grep`，
  使證據落在 checker 實際攝取窗口。本輪沿用同一份倉庫外第三輪 handoff。

## 修改的檔案與核心邏輯 (Changes)

- `docs/worklog/2026-08-20-PR62第三輪驗收修復.md`：原完成性句正下方追加窗口內複驗命令。
- `docs/worklog/2026-08-20-PR62第三輪post-commit警告第二次修復.md`：保存第二次 post-commit
  失敗、checker 實作證據與修法。
- `docs/specs/91-pit-register.md`：附錄 A.1 補列本 worklog；§3 不變。

## 尚未完成或需注意的風險 (Pending / TODO)

- 依階段一方案 §6.2，仍須重跑完整閘門、另做 commit，再執行 post-commit doc-claims；只有
  exit 0 且 warning 0 才能開始鐵律 15 與 push。
- 三個 Codex threads、下一 exact head 三方驗收及鐵律 18.3 人工合併邊界均未改變。
