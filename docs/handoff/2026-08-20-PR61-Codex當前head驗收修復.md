# Handoff — 2026-08-20：PR #61 Codex 當前 head 驗收修復

## ① 我改了什麼

PR #61 遠端 head 的六條 Codex inline 已在本地逐條處置：workflow PR 改走明示缺證的人工
審核停點、S-1 移出本階段、開場終態同步、Shopify 匯款憑證撤回缺席推論、歷史閘門裸數字
更正為未取得，以及 P-1 後三件套即時收割。

本輪 worklog：`docs/worklog/2026-08-20-PR61-Codex當前head驗收修復.md`。

## ② 為什麼這樣改（含被推翻的假設）

- **被推翻：Codex current-head review 沒有新增意見。** Review `.body` 是空殼不代表 inline 為零；
  三端點＋GraphQL 實讀出六條未清，故停止 push 並修復。
- **被推翻：validation-skip success 可以替代 Claude 判詞。** 它只證明反竄改 skip 已執行；
  缺少判詞時不能宣稱雙清，只能交使用者獨立人工審核。
- **被推翻：manual payment 頁沒提附件等於 Shopify 沒有上傳功能。** 缺席不是否定證據；
  官方另證明管理員內部 Timeline 可附檔，但顧客側能力仍未取得。
- **被推翻：P-1 早期全勾可代表階段終態。** 每個後續 PR 都會新增三件套；因此新增來源必須
  在同 PR 即時抽取並勾選，DoD 再驗零未勾項。

## ③ 還有什麼沒解決

- 新 head 尚未 push，也尚未取得 GitHub CI、Claude 與 Codex 驗收。
- 六條舊 threads 尚未 resolve；要等新 head current review 與修復實物都成立後再逐條處理。
- 顧客側匯款憑證能力仍是「未取得」，須由 S-14／`112` 前的測試店實測補證。

## ④ 下一個人要注意什麼

1. Review body 與 inline 是兩個意見載體；每輪必須三端點全量拉取，再用 GraphQL 核 unresolved。
2. workflow PR 的綠色 skip 不是判詞、不是雙清、不是 `1111`；只可觸發使用者獨立人工審核。
3. S-1 仍屬階段二'，D30 未授權階段一'先行。
4. Shopify 已證明的是 manual payment 狀態流與管理員內部附件，不是顧客上傳匯款憑證。
5. P-1 後任何新 worklog／handoff 必須同 PR 讀完、抽坑並以 `[x]` 入附錄；DoD 重驗零未勾項。
