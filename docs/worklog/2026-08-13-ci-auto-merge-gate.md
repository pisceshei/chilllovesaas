# CI 驗收閉環加人工合併閘門（AUTO_MERGE=false）

> 對應規格：`.github/workflows/claude-review.yml` 逐行審計（2026-08-13 六路分析之 audit:ci-closed-loop）｜ commit：見本檔所在 commit

## 已完成的工作 (Done)

- `.github/workflows/claude-review.yml` 的 `env.AUTO_MERGE` 由 `"true"` 改為 `"false"`：Claude 驗收「通過」後仍自動 approve＋留言，但**合併改由人工執行**（workflow 第 139 行原本就內建此路徑的引導文字，零額外改碼）。
- 逐行審計確認：本 workflow 只監聽 `pull_request`（opened/synchronize/ready_for_review），**沒有 push 觸發器**——直接 push main 不會觸發任何自動化；今日的 force-push 與後續 doc commits 都不經過它。
- 依 2026-08-13 使用者裁定執行（四選項問答，選「AUTO_MERGE=false」）。

## 修改的檔案與核心邏輯 (Changes)

- `.github/workflows/claude-review.yml`（env 區塊，+8 行註釋 −1 行值）。
- **為什麼改**：合併 main 的唯一閘門是 LLM 留言第一行的「【驗收結論】通過」，有兩個已確認的風險形態：
  1. **prompt injection**——Claude 讀 PR diff 與描述，注入文字可誘導「通過」，全程無程式層防禦、無人工步驟即落地 main；
  2. **舊結論沿用**——驗收留言未綁 commit SHA，且解析步驟 `if: !cancelled()` 在 Claude 步驟失敗時照跑，存在「上輪通過但 merge 失敗 → 新 push → 本輪 Claude 逾時 → 撿舊通過合併未審核 commit」的真實序列。
- **為什麼不選另外兩案**：branch protection 要 1 人審（零改碼）依賴 GitHub 網頁設定、不在倉庫版本控制內，接手者看不見；全停用（workflow_dispatch only）會丟掉自動驗收留言這個最有價值的部分。AUTO_MERGE=false 同時消掉「任何通過的 PR 都對最低序 open M issue 重複派工」的副作用（派工邏輯在 merge 成功分支內）。

## 尚未完成或需注意的風險 (Pending / TODO)

- **風險②的根修未做**：正解是驗收留言內嵌 head SHA、解析步驟比對後才 approve/merge。改回 `AUTO_MERGE="true"` 前必須先修（已在檔內註釋寫死此前置條件）。
- **字典序地雷未修**：next-stage 派工用 `sort_by(.title)`，`M10` 會排在 `M2` 前面；目前只有 M0–M6 尚安全，擴充里程碑前要改成數值排序。
- **verdict 解析靠全文 grep**：留言正文若引用「【驗收結論】需修改」字樣會誤判，目前僅靠 prompt 指示防範（第 88 行），未做程式層防線。
- **GITHUB_TOKEN 合併不觸發 push workflow**（GitHub 防遞迴）：目前 repo 只有這一個 workflow 無影響，但日後在 main 加 CI/deploy workflow 時，若改回自動合併，那些 commit 會靜默跳過 CI——屆時需改用 PAT 或 merge queue。
- **本檔改動是否能 push 尚未驗證**：credential 若缺 `workflow` scope，GitHub 會拒絕修改 workflow 檔的 push——見本 commit 的 push 結果；被拒則需使用者本人推這一個 commit。
