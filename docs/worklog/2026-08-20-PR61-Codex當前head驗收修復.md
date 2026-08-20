# PR #61 Codex 當前 head 驗收修復

## 已完成的工作 (Done)

- push 前依鐵律 15.2 於 2026-08-20 全量拉取 `issues/61/comments`、`pulls/61/reviews`、
  `pulls/61/comments`（皆 `--paginate`）及 GraphQL `reviewThreads`，確認 review `4978468264`
  對遠端 head `3f53354af5fd255f709113d2c4fea9580fc32dae` 有六條未清 inline：
  `3818122484`、`3818122487`、`3818122490`、`3818122495`、`3818122498`、`3818122502`。
  因此撤回先前「零新增」錯誤結論，在尚未 push 的本地分支完成處置。
- 用 `git log -p` 核對階段序列、18.3 workflow 停點、開場包終態與 P-1 收割沿革；S-1 從
  階段一'移除，workflow PR 改成 Claude 證據不可得時明示未取得並交使用者獨立人工審核，
  P-1 後新增三件套改為同 PR 立即收割與勾選。
- 依 Shopify 官方文檔取證 manual payment 的 Pending→mark paid 流程，以及管理員 Timeline
  內部留言可附檔；顧客側上傳匯款憑證仍未取得，已撤回「官方沒有」的缺席推論（取證
  2026-08-20；<https://help.shopify.com/en/manual/payments/manual-payments>、
  <https://help.shopify.com/en/manual/fulfillment/managing-orders/managing-order-details>）。
- 四份既有驗收 worklog 的裸閘門數字改為有日期的證據更正：因歷史原始輸出未留存，該句
  只能標「未取得」，不能作 current-head 驗收證據；開場 worklog／handoff 的終態段同步至
  D33、鐵律 19 與後續驗收三件套。

## 修改的檔案與核心邏輯 (Changes)

- `docs/plans/2026-08-20-階段一執行方案.md`：清除 S-1 越界、建立 workflow PR 可達成人工
  審核通道、P-1 持續收割不變量，並更正 Shopify 匯款憑證證據邊界。
- `docs/worklog/2026-08-20-階段一開場包.md`、配對 handoff：把 Changes／① 更新到 PR #61
  終態；四份 PR61 驗收 worklog 撤回沒有保存輸出的裸閘門完成性聲明。
- `docs/specs/91-pit-register.md`：補列本 worklog／handoff；本檔與配對 handoff 構成本單位三件套。

## 尚未完成或需注意的風險 (Pending / TODO)

- 本次修復尚須通過完整本地閘門、commit 後 diff、三端點全量重拉、push 與新 head 的
  Claude／Codex 驗收；舊 head 的六條 inline 在新 head 證明修復前不得 resolve。
- 若 workflow 變更 PR 的當前 head 實跑出現 `validation-skip`，狀態必須明載
  「Claude 證據未取得／未達雙清」，並按本方案停下通知使用者獨立人工審核；該次
  `validation-skip` success 不得當成通過。
- 顧客側匯款憑證上傳仍未取得測試店證據；S-14／`112` 不得把它分類成 Shopify 缺口。
