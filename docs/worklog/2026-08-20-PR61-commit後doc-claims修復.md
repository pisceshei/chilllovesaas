# PR #61：commit 後 doc-claims 修復

> 對應規格：`AGENTS.md` §文檔更新規則 6、`CLAUDE.md` 鐵律 15.4／21 ｜ commit：本提交

## 已完成的工作 (Done)

- 對提交 `ae47cf210d22ee14749d714e7bcc57f244fec387` 執行
  `ruby scripts/check-doc-claims.rb`。2026-08-20 實跑快照：exit 1；命中兩項 R4 error，另有一項
  R5 warning，因此依規則停止 push。
- 只修檢查輸出點名的三句：handoff 的「29 支」改成不寫易腐總數；Rails worklog 去掉首跑
  29／28 的手抄總數；Rails handoff 撤掉未附列舉的完整性用語，保留可由該次 RSpec 輸出直接支持的
  `284 examples, 1 failure`。
- 新增本 worklog 與同名 handoff，並補進 `docs/specs/91-pit-register.md` 附錄 A 與開場包終態入口；
  沒有順手改其他未被本次 post-commit 輸出點名的同型句。

## 修改的檔案與核心邏輯 (Changes)

- `docs/handoff/2026-08-20-PR61-Codex-2ed2403驗收修復.md`：移除沒有鄰近複驗式的閘門總數。
- `docs/worklog/2026-08-20-PR61-Rails冷啟動閘門復驗.md`：以「Rails gate 的實跑結果」取代整包
  手抄計數，保留真正需要診斷的輸出。
- `docs/handoff/2026-08-20-PR61-Rails冷啟動閘門復驗.md`：撤回「唯一」全稱句，避免把未附列舉的
  完整性宣稱發布出去。
- `docs/specs/91-pit-register.md`、開場 handoff 與本配對三件套：保存 commit 後才可觀測到的失敗
  分支，下一位可從 `ae47cf2` 與上列命令重現，而不用猜為何沒有 push。

## 尚未完成或需注意的風險 (Pending / TODO)

- 本次修正尚未重跑完整 production 等價閘門、commit 與 commit 後 doc-claims；依 15.4，先前任何
  綠燈都不能沿用。
- 新增文件只有在 commit 後才會進入 doc-claims 的新增行射程；因此本提交後必須再次執行並確認
  error 與 warning 都為 0，否則繼續停止 push。
- PR #61 的遠端 review thread、CI 與 bot current-head 驗收仍未更新，且仍由使用者人工合併。
