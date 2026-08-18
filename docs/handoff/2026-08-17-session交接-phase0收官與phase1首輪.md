# Handoff — Session 交接：Phase 0 收官＋Phase 1 首輪（2026-08-17，使用者指示暫停點）

> 🔴 本檔是**跨 session 完整交接**（使用者指示：完成修復→寫本檔→暫停）。接手順序：
> ①讀本檔全文 ②讀 `~/.claude/projects/C--Users-pisce-Downloads-shopifysystem/memory/MEMORY.md`
> （使用者鐵律索引，含本日新增 web-research-for-fixes）③從 §③ 的「下一步」續跑。

## ① 我改了什麼（本 session 全部成果）

**Phase 0 收官（全部完成）**：
- **PR #52 已合併**（merge commit `a093dda`）——第 18–26 輪驗收循環收斂：
  第 18 輪清 Codex flush（live 55 則→44 題：10 題標早輪已修、33 處修點名處）；
  第 19–26 輪逐輪清 bot 意見（R-11 退款家族最深：出口分支→帳本內/線下拆型→
  併一路人工確認→謂詞補 shop_id→正典碼 INCLUSION，九份副本至逐字同構）；
  末輪（`044398d`）bot 通過＋Codex 零 inline **同 head 雙零**。
- **PR #54 已合併**：Fable 5 額度耗盡致驗收兩次逐字同死（ERRTEXT 帶原文）→
  照 claude-review.yml ④先例把 `--model` 換回 `claude-opus-5`（沿革⑥）。
- tag `pr52-last-push` 已刪（遠端＋本地）；main 全閘門重跑綠。
- PR #52 描述 ⚪ 段全程維護（後全量轉入 91）。

**Phase 1 已開工**：
- **PR #55（PR-E1）已開**：`docs/specs/91-pit-register.md` 骨架——七欄 schema、
  F1–F12 形態分類、G-xx 缺口表骨架、§3 ⚪ 兩源全量轉入、附錄 A 收割清單
  （worklog/handoff 逐檔 checkbox）；Phase 0 交接檔隨 PR 入庫。
- **#55 首輪判詞（bot 🔴3🟡1＋Codex 9 則）已全數修復**＝本 commit：
  附錄 A 補自身 3 檔＋quotepath 旗標＋同 commit 補列紀律；phase0 交接檔 §① 時點錨
  ＋§④ 閘門一鍵 Python 缺口更正註記；CLAUDE.md／AGENTS.md「91 尚未建立」句改
  「已建立、過渡作廢」；92–95 改未來式帶 PR 錨；嚴重度補 P3；§3 預標如實標示；
  limits 錨改鍵名；A.3 憑印象寫錯的檔名改倉庫實名（第 2 輪改五格、第 3 輪補
  71 一格——「五檔名⋯全數」原句計數不實，F6 現行犯 ×2）。
- **PR #56 已開（in flight）**：claude-review.yml ⚪ 去處句同步（#55 🔴-3 的第三處）
  ——workflow 檔受反竄改防線約束（必須與 main 一致），照 #37/#47/#54 先例走獨立
  PR；**合併後須 cherry-pick `dd2c21a` 回 #55 分支**恢復 byte-identical。

## ② 為什麼這樣改（關鍵裁定與被推翻的假設）

- **使用者本日新裁定**：「review 出問題允許上網查資料/參考項目再修」（記憶
  `web-research-for-fixes`——涉域語義先查官方文檔/成熟專案，斷言帶取證日期；
  與 fix-only 並用，查證不是擴範圍的理由）。
- **被推翻的假設／自傷教訓（全部已立防）**：
  ①「58 §K13 六家全 false」係誤讀（K13＝5 carrier 欄、⛔/—/❌ 語義各異）——
  已刪四處並留更正註記；②A.3 檔名憑印象寫＝五個全錯——引用一律開檔核；
  <!-- 🔴 2026-08-17 更正（bot #55 第 2 輪）：「五個全錯」少計——同批第六格
  （71-parity-register→實名 71-admin-parity-sweep）第 2 輪漏改、第 3 輪補。 -->
  ③閘門一鍵只跑 .rb/.sh 漏兩支 Python——phase0 檔已加更正註記；
  ④doc-claims 是 **diff-對-已提交制**：commit 前跑看不到新行 ⇒ **commit 後必
  重跑 doc-claims 再 15.1**（新流程已寫入 #52 worklog 第 25 輪節）；
  ⑤`git add` 用逐檔列舉不用目錄形（吞 untracked 交接檔，兩輪踩過）；
  ⑥中文檔名操作一律 `git -c core.quotepath=false`。
- **修法選擇的三個先例**（後續同型直接沿用）：R-11 SUCCESS 出口三型（外部金流
  webhook／帳本內即時同交易 SUCCESS／線下待確認 pending＋人工確認 UPDATE，判準＝
  目的地是否即為平台帳本內餘額）；錯誤碼一律取 28:312 正典 26 值；治理三件
  （權限鍵/confirm/冪等鍵）一律落 limits.yml 機器可讀鍵。

## ③ 還有什麼沒解決（按序做）

1. **等 #56 Codex 判詞 → 零意見即合併 → 刪分支 → 在 #55 分支
   `git cherry-pick dd2c21a` → 驗證 `git diff origin/main -- .github/workflows/claude-review.yml` 為空**
   ——順序不可反：#56 合併後 #55 的 workflow 與新 main 不同、驗收會被反竄改跳過。
2. **#55 第 2 輪已 push（本 commit）**：等雙判詞→依循環清到雙零→合併→刪分支與
   `pr55-last-push` tag→拉 main 跑閘門。
3. **收割輪開跑**（91 附錄 A 逐檔）＋A1（specs/92 宣稱索引）；隨後 C0/D0
   （**Playwright 依賴需使用者裁定**——階段一開工前裁定點①，連同②截圖存放紀律）。
4. 懸而未決：驗收模型是否切回 Fable 5（額度已回復；③「most capable」理由未被
   推翻——使用者裁定）；總綱 §7 九條 Q（M2 前）；§3 轉入項的展開（收割輪做）。

## ④ 下一個人要注意什麼

- **鐵律 15 逐字照走**；基準 tag 現值＝`pr55-last-push`（本 commit push 後更新）。
  #56 無 tag（單 commit 迷你 PR，比對基準＝其唯一 commit `dd2c21a`）。
- 判詞讀取 SOP 沿用 phase0 交接檔 §④（該檔已入庫，§① 有時點錨——歷史快照勿當現況）；
  GitHub API 無認證限流 60/hr，耗盡時走頁面 HTML＋`git`；PR body 編輯用頁內
  form POST（`_method=put`＋authenticity_token，見 #52 輪次實作）。
- **驗收行為**：bot 每 push 自動跑（opus）；Codex 需 `@codex review`（新 PR 自動）；
  熔斷 label `review:需人工裁定` 達 3 輪未過會自動貼上——移除後 push 才會再觸發。
- 背景輪詢本次暫停時**全部已停**；接手後自行起新輪詢（形態見 session 內先例：
  curl 頁面 HTML grep「審 <sha>」與「Reviewed commit <sha>」）。
- 本輪產生/更新的 worklog：`docs/worklog/2026-08-17-91坑登記簿骨架.md`（含第 2 輪節）、
  `docs/worklog/2026-08-15-業務邏輯總綱合成.md`（#52 第 18–26 輪節）、
  `docs/worklog/2026-08-16-驗收模型改回fable5.md`（終態更正註記）。
