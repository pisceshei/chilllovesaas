# PR #61：post-commit doc-claims 警告修復

> 對應規格：`AGENTS.md` §文檔更新規則 6、`CLAUDE.md` 鐵律 15.4／21 ｜ commit：本提交

## 已完成的工作 (Done)

- 對提交 `e9a1298eed027cebf7a56b63d512868d5fcb721e` 執行
  `ruby scripts/check-doc-claims.rb`。2026-08-20 實跑快照：exit 0，但 R5 warning 未清，因此停止
  push；警告精確命中前一份 worklog 對已刪完整性用語的逐字重複。
- 將該句改成描述修法語義，不再重複觸發詞；沒有修改被點名句以外的歷史內容，也沒有把 exit 0
  當成可忽略 warning 的理由。
- 新增本 worklog、同名 handoff、附錄 A 與開場入口，保存這個「成功碼仍不等於本專案可推」的
  流程分支。

## 修改的檔案與核心邏輯 (Changes)

- `docs/worklog/2026-08-20-PR61-commit後doc-claims修復.md`：把自我重複的全稱觸發詞改成
  「未附列舉的完整性用語」，保留為何要改的資訊但不重新發布同一句宣稱。
- 本 worklog、`docs/handoff/2026-08-20-PR61-postcommit警告修復.md`、
  `docs/specs/91-pit-register.md` 與開場 handoff：建立該警告分支的可追溯入口。

## 尚未完成或需注意的風險 (Pending / TODO)

- 本文件定稿時，修正後的完整 production 等價閘門、commit 與 post-commit doc-claims 尚未執行；
  必須全部重來，不能沿用 `e9a1298` 的 exit 0。
- 下一次 doc-claims 必須同時滿足 exit 0 與 warning 0；只看程序退出碼仍會造成假清。
- PR #61 遠端 current-head 驗收、review thread 回覆與 CI 仍未開始，人工合併限制不變。
