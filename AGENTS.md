# AGENTS.md — 專案工作守則（驗收方與實作方共用）

> 🔴 **2026-08-15 使用者裁定改制：Codex 只做驗收，不做實作。**
> 本檔原本的標題是「給 Codex（實作代理）的工作守則」，開頭寫「你是本專案的**實作方**」。**已廢止。**
>
> **現行分工**：
> - **實作**＝人主導的 Claude Code 工作階段（讀本檔全部技術鐵律與工作規約）；
> - **驗收**＝兩個**獨立**的驗收方，各自出意見、互不派工：
>   - **Codex**（`chatgpt-codex-connector` 的 PR 自動審查，inline review）
>   - **Claude bot**（`.github/workflows/claude-review.yml`，貼【驗收結論】）
>
> 🔴 **驗收方請注意**：你的產出是**意見**，不是工單。**不要 @ 任何代理派修、不要自行 approve／merge、不要直接改代碼。**
> 修法有多條路時（例如「fail-closed 最小修」vs「補齊語義」），**把選項與各自代價寫出來讓人裁定**，不要替專案選。
>
> 🔴 **實作方請注意**：本檔以下全部技術鐵律與工作規約**照舊適用**——
> 改制改的是「誰來寫代碼」，**不是**放寬任何一條鐵律。寫代碼開 PR、不自行合併；
> 規格有疑義以文檔為準，文檔沒有答案才問使用者。

## 開工前（每個任務都要）

1. 先讀 `HANDOFF.md`（15 分鐘上手路徑、決策 D1–D7、法律紅線、里程碑 M0–M6）。
2. 開發某畫面/功能前，讀對應章節：`docs/research/22`（按鈕級驗收清單）、`docs/research/71`（parity 總登記簿：§A 保護清單＋§F 差異登記）、`docs/research/7x` 該模組 teardown（72 首頁指標/73 財務帳單/74 顧客線/75 折扣…逐輪增補）、`docs/specs/11–19`（生產級做法與坑）、`docs/research/28`（API 契約——**admin 一切走 GraphQL**）、`docs/research/31`（主題引擎工作包）。
3. UI 一律以 `docs/design/23-interaction-css-spec.md` 的 tokens 為準；對照 `docs/design/chilllove-admin-v2.html` 原型（開「⌗ 註釋模式」看每個控件的規格）。
4. 🔴 **鐵律 12（Shopify 對齊鐵律，2026-08-13 使用者裁定）——實作方同樣受約束**：
   - **親自點擊、禁止猜 URL**：每個頁面/按鈕/欄位/選單/下拉都要點過；導航一律用真實 `href`。
   - **不存在「有問題的頁面」或 404**：只可能是①沒載完（等＋**重載 1–3 次**）或②你在猜路徑；
     **不得寫「本尊沒有這頁/這功能」**。
   - **測試店可寫入**：`chill-love-u5q5mnzq` 資料全假，使用者授權新增/編輯/刪除——**要走完整
     操作流程**（建立→修改→刪除）才算拿到狀態機與副作用；避免真實費用與對外發信。
   - **註釋四件事**（DOCS 與 `docs/dev/` 皆適用）：①這是什麼 ②具體功能與**完整值域** ③怎麼做出
     這效果（邏輯/狀態機/出處/limits 引用）④🔴**跨功能・跨頁・前端影響（預先對接）**。
5. 🔴 **階段對齊標準（2026-08-13 使用者裁定，硬性；六層）**：每個階段的實作必須與 Shopify 本尊保持一致性——
   **按鈕級完全複製功能邏輯與交互邏輯**（每個按鈕/欄位/值域/空態/錯誤態/狀態機）＋
   🔴 **值域窮舉**（所有下拉選單/下拉欄位/選擇器/autocomplete/⋯選單/分段控制的選項**全量**照抄，
   含原文、預設值、條件顯示規則——**enum 不得自創、不得省略**；7x teardown 檔是唯一權威值域來源）＋
   🔴 **依 7x 的架構圖實作**（URL 路由樹含 302 與 query 語義／頁面層級容器歸屬／跨頁共用元件家族——
   共用元件改一處要同步所有掛載點）＋**對照 CSS 量測**（7x 檔 §CSS 三段式：本尊量測值 → 我方 token
   映射；實作只用我方 tokens，鐵律 8/9）＋**結合 help.shopify.com 說明文檔**（實測＋help 雙源；
   上限值引 `config/limits.yml` 不硬編）＋**條件性控件三源判定**。
   與本尊的差異只有兩種合法形態：71 §A 保護清單（使用者裁定）或 §F 登記的 V——其餘一律做到一致；
   拿不準是否「本尊如此」時查對應 7x teardown，7x 沒寫的在 PR 標假設，不要靜默猜。

## 工作流

- **分支**：`m{里程碑}/{功能}`（例 `m0/rails-skeleton`、`m1/products-crud`）。**永不直接 push main**。
- **PR**：一個 PR 對應一個可驗收單元；描述必附「對應規格章節＋自測結果＋假設清單」。
- **commit 格式**：`M1: products CRUD with variant diff`。
- **驗收**：PR 開出後由 Claude 對照 specs 驗收清單審核（跑測試＋逐條打勾）；修改意見回到 PR，通過才合併。

## 技術鐵律（違反即打回）

1. 技術棧：Rails 8.1 + MySQL 8 + Vite/React(TS) admin + Liquid 相容前台（D1/D4）；不引入未討論的重型依賴。
2. **業務資料**全表帶 `shop_id` 且複合索引開頭；金額全程 **integer cents**（出現 float 即 bug）；transaction 內禁外部 IO；上限引用 `config/limits.yml`。
   <!-- 2026-08-14 裁定：身分與權限走**組織層白名單豁免**（71 §A G24）。白名單＝**我方實際表名**，
        逐表列舉、不得口頭擴充：
          已建：staff_members（＝本尊的 users）／roles／role_permissions／sessions
          未建（M5 RBAC 展開時）：organizations／user_roles／user_groups／user_group_roles
        🔴 `user_store_assignments` **不在豁免內、必須帶 shop_id**——它是 user × shop 的關聯本體。
        🔴 `shops` 不是「豁免」，它是租戶根，是 shop_id 指向的那張表。
        🔴 豁免的是「表有沒有 shop_id 欄」，**不是「查詢可不可以不帶 shop_id」**——
        跨店存取仍須先解析出可及 shop_id 集合再逐表帶條件。
        新增白名單表要改 CLAUDE.md 鐵律 2、71 §A G24 與 `scripts/check-tenant-isolation.rb`
        的 `ORG_LEVEL_TABLES` **三處**，並在 PR 描述標明。 -->
   <!-- 2026-08-14 第二次修正（寫 docs/dev/m1-identity-tenancy.md 時對照 schema 發現）：
        原文的白名單抄自 R12 對本尊的觀察，是**本尊的表名**不是我方的，實測對不上——
        ①列了 5 張我方根本沒建的表（organizations/users/user_roles/user_groups/user_group_roles）
        ②列了 `user_store_assignments`，但它**有且必須有 shop_id**，列進豁免是反的
        ③🔴 **漏列 `sessions`**——migration 實際拆掉了它的 shop_id，CI 腳本也放行了它，
          但規則從未授權過。配套條款③要求新增白名單表得同步改規則，這一張沒改到。
        規則與機制對不上時，機制照樣跑、規則變成裝飾——這正是 G24 豁免最不能出事的地方。 -->
3. admin SPA 只打 `/admin/api/{version}/graphql.json`（28 號慣例：GID/cursor 分頁/userErrors/MoneyBag）；業務錯誤走 userErrors 不走 HTTP 4xx。
4. 寫路徑冪等（訂單成立/退款/庫存調整必帶 idempotencyKey）；事件走 outbox。
5. **法律紅線**：不用 `@shopify/polaris`、不抄 Dawn/Horizon 代碼與 Shopify CSS/資產/文案；icon 用 Lucide；Liquid gem（MIT）可用。`test/fixtures/themes/ella-7.2.0` 是使用者已購授權的測試 fixture——僅限測試，不得散布。
6. 文案繁體中文；金額顯示 `HK$1,480`（tabular-nums），實際符號與小數位由市場的 locale 決定，不得硬編。
   <!-- 依 2026-08-12「基準法域＝香港」裁定（CLAUDE.md 鐵律 10/11）修正，原文：「金額顯示 `NT$1,480`（tabular-nums）。」
        🔴 台灣預設時代的殘留。Codex 以本檔為守則，示例值錯了會直接產出錯的基準。 -->

## 註釋與文檔（強制——缺了即打回，與技術鐵律同級）

> 目的：任何工程師或代理隨時接手，讀註釋與 `docs/dev/` 即可上手。把「以後有人接手」當成驗收標準來寫代碼。

1. **文檔註釋**：所有 public class/module/方法必須有文檔註釋——用途、參數、回傳、副作用（Ruby 用 YARD 風格，TS/React 用 TSDoc；繁體中文為主、術語保留英文）。React 元件註明 props 與對應 `docs/design/23` tokens 章節。
2. **「為什麼」註釋**：複雜業務邏輯（金額計算、併發控制、冪等、庫存 ledger、Liquid 相容行為、快取失效）必須註明設計原因並引用規格出處，例：`# 併發扣庫存用悲觀鎖，見 docs/specs/14 §3`。migration 檔頭註明對應 `docs/research/06` §7 的表定義條目。
3. **功能文檔**：每個新增功能的 PR 必須同時新增 `docs/dev/m{N}-{功能}.md`（模板與規則見 `docs/dev/README.md`）：概述、規格出處、架構與資料流、API 對應、資料表、關鍵取捨、測試、已知限制。修 bug／重構的 PR 則更新受影響的既有篇章。
4. PR 描述加一欄「文檔」：列出本 PR 的 docs/dev 變更；沒有變更要寫明理由（例：純 CI 修改）。

## 工作記錄與交接文件的寫法（強制——本節違反即打回，與技術鐵律同級）

> 規則**來源**是 `CLAUDE.md` §工作方式（那裡規定「要不要寫」）。本節只規定「**怎麼寫**」。
>
> 🔴 立這一節的理由（2026-08-15 使用者裁定）：兩個 PR 連續**九輪**驗收未通過，
> 15 條 🔴 裡 **12 條是 worklog／handoff 的散文與事實不符，0 條是代碼缺陷**。
> 更關鍵的是——九輪之後用機械檢查掃同一批檔案，30 分鐘內又找到 3 條全新的同型缺陷，
> **全部出自「修正 commit」**。⇒ 散文成了交付的瓶頸，而「更小心一點」已被證明無效。

### 1. 三層文字，三套規則

| 層 | 是什麼 | 時間語義 | 可否回頭改 |
|---|---|---|---|
| **歷史層** | `docs/worklog/`／`docs/handoff/` 的**敘事段** | 寫下當刻的認知 | 🔴 **不改**。發現寫錯 → 加 `<!-- 🔴 YYYY-MM-DD 更正（來源）：原文⋯ -->`，**原文保留** |
| **終態層** | worklog 的 `Changes` 表、handoff `§①`、`docs/dev/` 篇章 | **必須等於 HEAD 的事實** | 🔴 **每輪必須回寫**，不得只追加新節了事 |
| **契約層** | `scripts/` 檔頭、fixture `README`、退出碼表 | 等於代碼**當前**行為 | 改代碼＝同一個 commit 改它 |

🔴 **「歷史層不改」是既有裁定**，不是本節新創——`docs/worklog/2026-08-15-引用保真與執行位元.md`
逐字：「worklog 是歷史紀錄，**刻意不改**」。
⇒ **驗收方不得要求回頭改歷史層的敘事**；發現錯誤請要求**加更正註記**。
⇒ 反過來，**終態層過期就是 🔴**：照 `docs/dev` 入口接手的人會拿到錯的清單。

### 2. 🔴 散文裡不得手寫「可由代碼算出」的數字

禁止裸寫：`17 條 case`、`11 個 fixture`、`共 7 支檢查器`、`四張表`、`15 條全綠`。
理由是實測的：2026-08-15 **兩次「修掉過期數字」的修正，本身都寫進了新的錯數字**。

三種合法寫法，擇一：
1. **不寫數字**——「整份 `CASES` 全綠」「本倉庫的檢查器」；
2. **附複驗指令**（同行或鄰近兩行內）——``（複驗：`git ls-files scripts/ | grep -c check-`）``；
3. **貼實跑輸出並標明是快照**——數字**允許過期**，因為它明示了時點，讀者知道要重跑。

### 3. 🔴 全稱句要嘛列舉，要嘛附查法

禁止裸寫：「唯一沒有的一支」「都各有一支」「所有 X 都 Y」「從來沒有」。
全稱句被否證的成本是 O(1)，而寫它的成本也是 O(1)——這個不對稱在 2026-08-15 連燒三輪。
⇒ 改成**列舉**（「三組有：A→a、B→b、C→c；三支沒有：D、E、F」）或**附複驗指令**。

### 4. 🔴 引用不在本分支樹上的檔案，一律錨定

三件事同時做到：
- 用**未來式或條件式**（「PR #41 合併後」「正解是⋯**本輪沒做**」），不得用現在式斷言其內容；
- 標出 **PR 號與日期**：`（PR #39 的 worklog，2026-08-15 尚未進 main）`；
- 🔴 **不得寫該檔的行號**——它會隨對方分支漂移。要指位置就寫章節名或 `grep` 指令。

⚠️ **不要為了通過檢查而刪掉交叉指引**——交叉指引本身有價值，錯的只是把
「另一個分支上有」寫成「現在就有」。

### 5. 🔴 「我已確認」四個字，必須有對應的指令輸出

`檔案:行號` 是最容易腐爛的引用。寫下之前跑 `grep -n` 或 `git show <ref>:<檔> | grep -n`，
把指令放進 PR 描述的自測欄。**沒有指令輸出就不要寫「已確認」。**
（2026-08-15 有兩次自稱「已確認」而結果為假，其中一次的 commit message 還寫著「實跑⋯確認」。）

### 6. 驗收回應輪次的寫法

一輪驗收回應＝一個「部分」，仍須寫 worklog（`CLAUDE.md` §工作方式），但：
- 新增內容放進 `## 驗收後修正（PR #N 第 M 輪）` 小節（**歷史層**，往後追加）；
- 🔴 **同一個 commit 內必須回寫終態層**——worklog `Changes` 表、handoff `§①`、
  受影響的 `docs/dev/`。**只追加不回寫＝打回。**
- commit 前跑 `ruby scripts/check-doc-claims.rb`（第 2／4／5 條已機制化，見下節）。

### 7. 機制而非紀律

第 2／4／5 條由 `scripts/check-doc-claims.rb` 機器判定，掛在 CI `quality` job 與 `bin/ci`。
🔴 **不要只靠讀本節**：本倉庫已經量過紀律型條款的失效率——
`config/ci.rb` 那條「兩邊要同步」在**寫下的隔天**就被違反。
⇒ 寫完 worklog／handoff **先跑那支腳本**，它比重讀一遍便宜也可靠得多。
全文與取捨（它抓不到什麼）見 `docs/dev/m0-review-convergence.md`。

## 🔴 Windows 開發者必讀：檔案執行位元

在 Windows 上 git 預設 `core.filemode=false`，**新增 `bin/*` 或腳本時不會帶執行位元**
（以 `100644` 提交），本機完全正常，但到 Linux CI 上執行就是 `exit 126: Permission denied`
——錯誤訊息完全看不出根因。2026-08-14 的 CI 全紅就是這個原因（`bin/rails` 等 10 個檔 ＋
`scripts/cloud-setup.sh` 全部缺 +x）。

**規則（2026-08-15 擴大，與 CI 判準逐字一致）**：
`bin/` 下**全部**檔案，以及 `scripts/` 下**帶 shebang 的**檔案，git mode 一律必須是 `100755`。
帶 shebang 是宣告「我可以直接跑」，宣告了卻沒有執行位元就是自相矛盾；
`scripts/` 下無 shebang 的資料檔不受此規則約束。

- **提交前檢查**（與 CI 同一份邏輯；`-F'\t'` 是為了路徑含空白時不被截斷）：

  ```bash
  git ls-files -s bin/ | awk -F'\t' 'substr($1,1,6) != "100755" { print $2 }'
  git ls-files -s scripts/ | awk -F'\t' 'substr($1,1,6) != "100755" { print $2 }' \
    | while IFS= read -r f; do if head -c 2 "$f" | grep -q '#!'; then echo "$f"; fi; done
  ```

  （有輸出就是有問題）
- **修法**：`git update-index --chmod=+x <檔案>`
- CI 兩個 job 的 checkout 之後各有一步 `Verify bin/ and scripts/ are executable` 會擋下來
  並印出修法。**但仍建議本機提交前自己跑一次**——本機一秒，CI 一輪要好幾分鐘。
  🔴 **改這條規則時，`.github/workflows/ci.yml` 的那兩份與本節必須同步改**
  （2026-08-15 擴大範圍時，本節一度沒跟上，PR #35 的 Codex review 指出：
  文件說「只掃 `scripts/*.sh`」而 CI 已改成 shebang 判準，讀文件的人會以為 `.rb`／`.py` 不受管）。

## 測試與驗收基準

- 每功能過 `docs/specs/11` §0 七維度；併發場景（超賣/折扣用量/退款上限）必須有測試。
- 主題引擎相關：golden theme＝Ella（`docs/research/27` §8 十條、31 §6 矩陣）；Liquid API 面對照 `docs/research/26` 清單。
- 跑 `bundle exec rspec`＋`npm test` 綠了才開 PR。
