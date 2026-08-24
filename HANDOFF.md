# HANDOFF — CHILL LOVE 完整上下文入口

> 🔴 **本檔於 2026-08-24 全文重寫**（PR #114 接手面稽核：舊版 24 條斷言與現況相反，
> 最嚴重的是「應用代碼將從 0 重建」——那是 2026-08-16 的裁定，2026-08-23 起實踐上已放棄，
> 每一包都在既有代碼上做加法）。舊版全文在 git 歷史。
> 本檔**只做入口與現況**，不轉述規則——規則的正典在 CLAUDE.md／AGENTS.md／DECISIONS.md，
> 轉述必縮寫、縮寫必失真（金額鐵律曾被縮成一行，正是 CLAUDE.md 明文禁止的形態）。

## 0. 接手順序（第一天照這個讀）

1. **本檔**（現況與地圖）
2. `docs/handoff/2026-08-24-總交接.md`——**最重要的一份**：環境操作手冊、未結事項總帳、
   工程陷阱彙編、第 19 包就緒度、刻意殘留資料清單
3. `docs/plans/2026-08-24-三方向執行順序.md`——**現行排程**（37 包總表，塊 A–F）
4. `docs/DECISIONS.md`——裁定 D1–D47 全文（**不要重新辯論已裁定的事**；
   最容易誤觸的：D8 白名單、D13 系列 sources、D40 開發模式、D43 CSV 延後、
   D45 on_hand 放寬、D46 兩層授權、D47 handoff 入庫）
5. `CLAUDE.md` 鐵律 1–21 ＋ `AGENTS.md`（**661／444 行，全文讀**，別依賴任何摘要——
   🔴 含本檔）
6. 最近的 `docs/handoff/`（2026-08-23 起每 PR 一份）與對應 worklog

## 1. 專案是什麼

CHILL LOVE——多租戶電商 SaaS，功能邏輯與交互 1:1 對齊 Shopify 2026 春季版，
視覺用自有設計語言。第一階段（研究＋規格＋高保真原型＋Liquid PoC）已收官；
現在是第二階段實作，**應用代碼是現行資產，不是待丟棄存量**。

## 2. 現況（2026-08-24，main = PR #113 合併後；數字均可 grep 複驗）

- **線上**：bt3 伺服器，`http://demo.chilling.com.hk:28080`，demo 店可登入操作。
  部署細節與帳密位置見總交接 §環境。
- **已上線的功能面**：商品 CRUD（含伺服器端搜尋／狀態篩選／編輯態）、系列（手動）、
  後台五語多語言（含翻譯 CSV）、**庫存線全套**（ledger／唯一寫入入口／列表／商品頁卡／
  調整記錄頁）、**第一道租戶閘**（D46）。
- **admin SPA 實頁只有三條路由**（products／collections／inventory ＋各自子頁與設定頁），
  側欄其餘項目全是 placeholder。GraphQL：13 支 query field、9 支 mutation。
  逐項清單＝總交接 §M1 現況。
- **排程進度**：37 包中已完成 **1、15、16、17、18**；**2–14 未做**（不是做完了——
  第 1 包後直接跳到庫存塊，塊 A 共用地基大部分未動，明細見總交接 §排程現況）。
- **下一包＝第 19 包（事件與 outbox 轉發）**。🔴 它沒有像第 18 包那樣的執行規格，
  且有四個已知擋路石（outbox schema 與規格對不上等），開工前先讀總交接 §第 19 包。

## 3. 已鎖定的大方向（細節一律看 DECISIONS.md 全文）

技術棧 Rails 8.1 + MySQL 8 + Vite/React(TS)（D1/D4）；API-first GraphQL（D5）；
基準法域香港＋jurisdiction pack（鐵律 11）；不用 Polaris、不抄 Dawn/Horizon（鐵律 9）；
**業務資料**全表 `shop_id`（組織層身分表依 D8 白名單豁免——白名單以 CLAUDE.md 鐵律 2
的**我方表名版**為準）；金額三尺度不可縮寫（鐵律 3 全文＋`docs/specs/65`）；
D40 直接開發模式：分支 → PR → CI 兩 job 綠 → squash merge，不等人工驗收。

## 4. 檔案地圖（找東西先看這裡）

| 要找什麼 | 去哪 |
|---|---|
| 規則與鐵律 | `CLAUDE.md`（1–21）、`AGENTS.md` |
| 裁定紀錄 | `docs/DECISIONS.md`（D1–D47） |
| 現行排程 | `docs/plans/2026-08-24-三方向執行順序.md`（37 包） |
| 環境／操作／未結帳 | `docs/handoff/2026-08-24-總交接.md` |
| 每包做了什麼 | `docs/worklog/`（一包一份，三段固定） |
| 每輪的判斷與教訓 | `docs/handoff/`（一 PR 一份，四段固定；D47 起恢復入庫） |
| 功能實作說明 | `docs/dev/m{N}-*.md`（一功能一篇） |
| 對本尊的實測 | `docs/research/`（7x teardown、90 藍圖、94/95 庫存） |
| 生產級規格 | `docs/specs/`（11–19 模組、65 金額、71 parity、91 坑登記、120 部署） |
| 對本尊的合法差異 | `docs/specs/71` §A 保護清單（G1–G30）＋ §F 待驗證 |
| 上限值 | `config/limits.yml`（鐵律 6：一律引用，不硬編） |
| 原型 | `docs/design/chilllove-admin-v2.html`（開「⌗ 註釋模式」） |

## 5. 每一包的固定節奏（全文在 AGENTS.md，這裡只列骨架）

開工前讀規格與 22 對應章節 → 實作（註釋即規格，鐵律 12.4 四件事）→
全套測試綠（rspec／vitest／typecheck／rubocop／brakeman）→
worklog ＋ handoff ＋ 產物**同 commit** → push → PR（描述附規格章節＋自測＋假設清單）→
CI 兩 job 綠 → squash merge → 部署 bt3 → **線上實機驗收**（不只看測試綠——
本專案抓到的要害缺陷大半是線上實測抓到的）→ 更新狀態板 artifact。
🔴 `check-doc-claims.rb` 掃**已提交** diff，commit 之後才跑。

## 6. 有問題找誰

文件沒有答案的才問使用者；使用者裁定過的（DECISIONS.md）不要再問。
使用者授權全自動化（免逐步確認），但合併前提是 CI 綠；測試店
`chill-love-u5q5mnzq` 有完整寫入授權（鐵律 12.2，唯一約束：不產生真實費用、不對外發信）。
