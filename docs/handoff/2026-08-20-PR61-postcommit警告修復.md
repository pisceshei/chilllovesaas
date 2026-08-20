# Handoff — 2026-08-20：PR #61 post-commit doc-claims 警告修復

## ① 我改了什麼

本步輸入是提交 `e9a1298eed027cebf7a56b63d512868d5fcb721e`。2026-08-20 的
`ruby scripts/check-doc-claims.rb` 實跑快照為 exit 0 但仍有 R5 warning；警告命中
`docs/worklog/2026-08-20-PR61-commit後doc-claims修復.md` 對先前已刪完整性用語的逐字重複。
push 已停止，該句已改成語義描述。配對 worklog：
`docs/worklog/2026-08-20-PR61-postcommit警告修復.md`。

## ② 為什麼這樣改（含被推翻的假設）

- **被推翻：checker exit 0 即可 push。** `AGENTS.md` 明定 R5 warning 也必須為 0；本次輸出正是
  「exit 0、warning 未清」的反例。
- **被推翻：在修復記錄中引用被刪措辭不會重新觸發。** checker 掃的是新增行文字；歷史說明若
  原樣重複完整性詞，仍然是一個新發布宣稱。
- **未採：加入白名單或關閉 R5。** 問題只在這句記錄方式，最小修法是改寫該句，不改 checker。

## ③ 還有什麼沒解決

- 本文件定稿時，完整閘門、commit、commit 後 doc-claims、15.1／15.2 與 push 均尚未完成。
- 新增的本 handoff／worklog 也只有在 commit 後才進入新增行掃描；若再有 warning，繼續停止。
- PR #61 遠端 CI、bot 判詞與 review threads 尚未更新；仍不得代行合併。

## ④ 下一個人要注意什麼

1. 依 15.4 從完整 production 等價閘門開始，不要只定向跑 doc-claims。
2. commit 後執行 `ruby scripts/check-doc-claims.rb`，同時核對 exit code 與輸出的 warning 計數。
3. warning 未清就建立下一個失敗步驟，不得把「不擋」讀成「通過本專案 push 條件」。
4. 真正清零後才進 15.1／15.2；push 後以綁新 head 的 PR remote handoff 記結果，PR #61 仍由使用者
   人工合併。
