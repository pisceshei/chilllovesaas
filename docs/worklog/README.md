# 工作記錄（worklog）

> 規則出處：`CLAUDE.md` §工作方式；2026-08-21 收斂裁定覆寫「每次修復另建一份」的舊解讀。
> **硬性，不是選配。**

## 什麼時候寫

**每個可獨立合併的 Git 驗收單位維護一份**，初始候選與該單位產物一起 commit。

通常一個 PR／原子工作包一份；umbrella 真正拆成幾個可獨立合併的 PR，才各有一份。同一 PR 的
驗收修復不是新單位：若 finding 需要改 tracked tree，在同一份 worklog 更新處置與終態 `Changes`，
與一次整合修復 commit 一起提交；純等待、證偽／裁定不修、same-head completion、resolve、PR body
或遠端終態不改 worklog，也不得為它們製造新 head。
🔴 **「一份 worklog（不另建「第 M 輪」）」這一條對規則生效前已開的 PR 不追溯；其餘條文（分層、更正註、閘門、ledger）照舊不豁免**：判準與射程邊界見 `docs/DECISIONS.md` **D39**（2026-08-22 使用者裁定）。

## 檔名

`docs/worklog/YYYY-MM-DD-<功能>.md`

同一天完成幾個可獨立合併的工作包，就各有一份，例如：

```
2026-08-14-product-graphql-mutations.md
2026-08-14-translations-market-id-drop.md
2026-08-14-money-psp-decimal-adapter.md
```

## 三段固定格式

```markdown
# <功能名稱>

> 對應規格：`docs/specs/NN` §X.Y ｜ commit：<sha>

## 已完成的工作 (Done)

- [條列這次實作了哪些功能、修復了什麼 bug]

## 修改的檔案與核心邏輯 (Changes)

- [列出異動的檔案路徑，並簡述關鍵函式或架構變動]

## 尚未完成或需注意的風險 (Pending / TODO)

- [列出還沒寫的邊際條件、潛在 bug 或待補的單元測試]
```

## 兩條紅線

1. 🔴 **Pending 段不得留空。** 真的沒有待辦，要寫「無，理由是⋯⋯」。空白讀起來像「沒檢查」，不是「檢查過沒有」——下一個人無法分辨這兩件事，只能重做一次。

2. 🔴 **Changes 段要寫「為什麼」，不只是 `git diff` 的白話版。** 檔案路徑 git 自己有；worklog 的價值在於記下**當時的判斷**：為什麼選這個資料結構、為什麼沒走另一條路、哪個假設還沒驗證。

## 與交接文件的分工

| | worklog | handoff |
|---|---|---|
| 粒度 | 一個可獨立合併的 PR／原子工作包 | 一個工作包／PR 的完整生命週期 |
| 回答 | 這個部分**做了什麼** | 本工作包／PR **完整生命週期**的判斷、證據與教訓 |
| 段落 | Done／Changes／Pending | ①改了什麼 ②為什麼（含被推翻的假設）③沒解決的 ④下一個人注意 |
| 頻率 | 每個獨立 Git 驗收單位一份；同 PR 修復不另建 | 每個工作包／PR 一份，本地持續更新 |

**兩者並存，不互相取代。** 本地 handoff 要列出該工作包配對的 worklog；兩者都不得按 bot
驗收輪次增殖。handoff 不進 Git，詳見鐵律 21。
