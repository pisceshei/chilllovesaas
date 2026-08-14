# Parity sweep R0：主清單＋總登記簿＋我方側地圖（docs/specs/71 創建）

> 對應規格：`docs/specs/71-admin-parity-sweep.md`（新建）｜使用者指令：admin 後台與 Shopify 商家後台逐控件對比補齊、不能有一絲差異（2026-08-13）｜commit：見本檔所在 commit

## 已完成的工作 (Done)

- **實測主清單**：chill-love-u5q5mnzq（測試店，使用者授權可寫入）zh-TW 介面全側欄導航樹實測——頂層 15 入口、
  訂單/產品/顧客/成長/內容/市場各區子頁、設定 21+account 子頁、四個新區（成長/財務/市場/代理式）首屏速記。
  穿透 open shadow root 收集（SESSION-EXPORT §5.1 紀律）。
- **我方側地圖**（5-agent 工作流 `wf_3ff4f4fd-6b3`，61.8 萬 tokens）：原型 5+27+13+22+20+1 頁面構成、
  139 個 toast 佔位（含死碼區 ~20 不可達）、DOCS 505 條註冊表健康度（缺註釋 0、死註釋 2、74 個 TBD API）、
  研究覆蓋薄弱排行（成長最薄）、既有缺口去重基準（53 號 open 162、50 號殘餘）。
- **裁定偏離保護清單 23 條**（71 §A）——對比輪的防「好心改回」機制，含金額/handle/URL/翻譯/支付/法域全部明知偏離。
- **輪次計畫 R1–R14**（覆蓋薄弱度驅動）＋首批 9 條正式登記（MISS×2/STRUCT×1/STUB×1/DEAD×2/DOC×2/V×1）。

## 修改的檔案與核心邏輯 (Changes)

- 新建 `docs/specs/71-admin-parity-sweep.md`（總登記簿，跨 session 續作入口）。
- **為什麼先建登記簿再動手改**：這是 49/51/53 稽核輪的既有教訓——沒有登記簿的大掃描會產生「宣稱做了但無法驗收」；
  §E 進度表＋§F 編號制讓每一輪可獨立驗收（CLAUDE.md「一個部分」定義）。
- **本輪自己踩的坑（已修正並留追溯註釋在 71 §B.1）**：初稿拿 M0 React shell 當對比對象，把成長/內容/財務等
  標成「整區缺失」——實際原型 full 版都有。教訓＝先建我方側地圖再標缺口；工作流結果推翻了草稿判定，
  修正後才 commit（避免錯誤結論進 git 歷史）。

## 尚未完成或需注意的風險 (Pending / TODO)

- **71-R0-V1 未查證**（limits.yml hreflang 鍵疑漂移，guard agent 警告）——標了「優先」，R1 開場先做。
- 佔位（STUB）139 處的**逐行號清單**在工作流 journal（`wf_3ff4f4fd-6b3/journal.jsonl`），未複製進 71 號
  （太長）；各輪轉真時從 journal 取——journal 是 session 目錄檔案，**跨 session 會失效**，若 R1 前 session
  結束，需在 R1 重抽（成本低，grep toast 即可）。
- 設定 21+1 ↔ 22 的逐頁映射、m-redirects 在本尊的歸屬、POS 範圍（44:907 曾判刻意不蓋 vs 使用者「不能有一絲差異」
  的新指令衝突）——都排進對應輪；**POS 範圍衝突需使用者裁定**（R13 前問）。
- 本尊部分形態受測試店狀態閘門（Payments 未啟用/商店未解鎖），R4/R9 靠 help 文檔補全貌；help 與實測矛盾時
  實測優先並登記 V。
