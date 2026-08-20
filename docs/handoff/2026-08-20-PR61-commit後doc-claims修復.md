# Handoff — 2026-08-20：PR #61 commit 後 doc-claims 修復

## ① 我改了什麼

步驟輸入是提交 `ae47cf210d22ee14749d714e7bcc57f244fec387`。2026-08-20 執行
`ruby scripts/check-doc-claims.rb` 的快照為 exit 1：兩項 R4 error 分別命中「完整 29 支」與
「首跑 28 支」，一項 R5 warning 命中「唯一失敗」。push 已停止；本步只改這三句，另新增配對
worklog `docs/worklog/2026-08-20-PR61-commit後doc-claims修復.md`，並更新附錄 A 與開場入口。

## ② 為什麼這樣改（含被推翻的假設）

- **被推翻：commit 前 doc-claims 綠即可代表提交後也綠。** `AGENTS.md` 已明定 checker 以已提交
  diff 判新增行；`ae47cf2` 的 post-commit 實跑立即抓出兩個 error 與一個 warning。
- **未採：替 29／28 補更多手抄總數。** 這些總數對診斷冷啟動沒有必要，改寫成 Rails gate 的
  具體輸出能保留事件證據，又不製造第二個易腐宣稱。
- **未採：掃全倉順手清同型句。** 鐵律 17.2 只授權本次 checker 點名處；其他同型問題只能另行
  登記或等被點名，不能在此擴散。

## ③ 還有什麼沒解決

- 本文件定稿時，修正後的完整閘門、commit、post-commit doc-claims、15.1／15.2 與 push 都尚未
  完成；先前 head 與結果不得外推。
- 新增的本 handoff／worklog 尚未經 commit 後新增行掃描；若再命中，必須停止並開下一個失敗步驟。
- PR #61 遠端驗收與五個 review thread 尚未更新；人工合併限制不變。

## ④ 下一個人要注意什麼

1. 從完整 production 等價閘門重跑，不得只跑 doc-claims；本機 Rails gate 先用絕對 gem glob
   canary 判別受限環境。
2. commit 後立刻跑 `ruby scripts/check-doc-claims.rb`，同時看 exit code 與 warning；任一非零或
   warning 都停止 push。
3. 15.1 以 `git diff pr61-last-push..HEAD` 對五個 current-head inline 逐項找 hunk；15.2 再全量拉
   issue comments、reviews body、paginated inline 與 GraphQL threads。
4. push 後的成功／失敗改用綁新 head 的四段式 PR remote handoff；PR #61 仍不可代行合併。
