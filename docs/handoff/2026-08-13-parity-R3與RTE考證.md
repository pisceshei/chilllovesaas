# 交接：parity R3 設定五頁＋RTE 引擎考證（2026-08-13 第四場）

> 本輪 worklog（1 份）：`2026-08-13-parity-R3設定五頁.md`
> 輪次紀律：worklog＋handoff＋commit 三件一起（使用者 2026-08-13 裁定，見 memory round-discipline-handoff）。

## ① 我改了什麼

1. **R3 五頁 parity 全流程**：實測（apps／sales_channels／domains／privacy 含三子頁／custom_data 含
   建立頁×2）＋help 三路 agent 雙源 → 71 §F 登記 12 條（2 STRUCT＋4 MISS 全修、2 DOC、4 V 遞延）→
   原型六組修復 → limits.yml 兩節 → DOCS 5 改寫＋14 新增 → lint 0 err／煙霧 18/18／console 0。
2. **RTE 考證（使用者本輪中途指令「核實 shopify 使用的是什麼富文本編輯器」）**：DOM 實證
   TinyMCE 6.8.3（最後 MIT 版；本尊原生 toolbar 停用、自繪工具列——「rte-uplift」架構）。
   開放決策 **B-8** 已立（我建議 TipTap 2），等使用者裁定。
3. **雜項**：隱私生成器法規基準補 HK PDPO（G21 一致性）；散檔複本根目錄補 `.claude/launch.json`
   （attach 8766 預覽用，不在 git 內）。

## ② 為什麼這樣改（含被推翻的假設）

- 🔴 **「應用程式與銷售管道」不是一頁**：我方原型（與 41 §12.19 時代的認知）把它做成合併頁；
  2026 實測＋help 同證是**兩個獨立設定頁**——這是 R0 主清單就該抓到的結構差，當時被「設定 21+1 頁」
  的粗粒度對照蓋掉了。教訓：**設定頁的「頁數」也是逐項對比對象，不能只對內容**。
- 🔴 **行銷設定兩列看起來像子頁，實測是跨頁錨點深連結**（結帳／通知）——「同一入口不同容器」形態。
  沒點進去就登記會把它寫成「隱私頁缺行銷設定卡」的假 MISS。R0-MISS2（點開才知是釘選對話）的教訓
  再次應驗：**登記前先點開**。
- 🔴 **螢幕證據會漏、DOM 證據補**：custom_data owner 列表捲動截圖漏了「地點／轉移」兩類，
  DOM 連結掃描抓回全 15 類。同法還撈到**完整鍵盤快捷鍵表**（71-R3-DOC2，R14 素材）。
- **RTE 為什麼不直接跟著用 TinyMCE**：本尊釘 6.8.3 是授權邊界（7.x 變 GPL）；我們要的是
  「功能與交互 1:1」不是「引擎 1:1」，工具列反正自繪，凍結版引擎的 XSS 維護成本才是長期主險——
  但這是鐵律 1 等級的依賴決策，所以立 B-8 不擅動。
- **前一輪 help 工作流 2/3 agent 結果丟失**（session 重啟）：journal 只記到 apps/channels 一路。
  處置＝重派兩個背景 agent 補齊，沒有拿殘缺結果硬寫。教訓：**跨 session 的工作流要先讀 journal
  確認每路都有 result 再引用**。
- Chrome 被使用者誤關一次：PowerShell 重啟＋tabs_context 重連即續拆，登入態未失。

## ③ 還有什麼沒解決

- **71-R3-V1**（Cookie 偏好設定 tab＋GPC 落點）、**V2**（metaobject 顧客帳號 API 佐證）、
  **V3**（網域 per-domain 三型 vs 62 §J 全域開關——R10 裁定）、**V4**（商品/產品用語表——R12）。
- **B-8 RTE 引擎**待使用者裁定（open-decisions §B-8，含兩案利弊與我的建議）。
- R4–R14 未開；下一輪 **R4＝財務＋帳單**（71 §E）。
- PR #12 仍等 CI＋使用者合併；M1 前置未動。
- 使用者側待裁存量：A-3／A-4／B-5／B-6／B-7／**B-8（新）**／E-1／POS 範圍（R13 前）。

## ④ 下一個人要注意什麼

1. **輪次紀律**：每輪＝worklog＋handoff＋commit 三件一起，不等提醒。
2. **對比前讀 71 §A（23 條保護清單）**；53號 N-04（不做管道設定層）本輪已再確認並保留。
3. **設定層容器只有三種**（主頁／setSubOpen 次級視圖／openGen modal）——本尊的獨立頁在原型裡
   映射到哪種，DOCS 條目都有註明，別再開第四種容器。
4. **metafieldSave 的返回點用 `SETSUB==='cd-owner'` 判斷**，不要改回 CD_OWNER（殘留值會誤路由）。
5. **limits.yml `custom_data.max_definitions` 口徑未定**（全店 vs 每資源）——落表前複驗，
   鍵上有註記。
6. 測試店可寫入（使用者全權授權）；本輪未建任何殘留測試資料。
7. lint 跑法：`PYTHONIOENCODING=utf-8 python scripts/lint-prototype.py`（cp950 終端會炸 emoji）。
