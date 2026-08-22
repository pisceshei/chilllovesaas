# 91 — 坑登記簿（Pit Register）

> 重啟計畫 E 軌主檔（PR-E1 立骨架，2026-08-17）。用途：把全部歷史事故（死控件／假數字／
> 假成功／假憑證／文檔漂移⋯）收割成**按根因去重**的坑條目，每坑帶預防機制與複驗指令，
> **禁止同一個坑踩第二次**。與鄰檔關係（**四檔皆尚未建立**，屬未來文件——各由重啟計畫
> 對應 PR 引入：92 宣稱/假憑證清查＝A 軌 PR-A1、93 響應式複驗＝C 軌 PR-C0 配套、
> 94 網路取證索引＝D 軌 PR-D0、95 重做需求總綱＝F 軌收斂輪；建立後將反向連結本檔坑編號）。
> 驗收方 ⚪（範圍外觀察）的法定去處＝本檔（CLAUDE.md 驗收基準）；本檔建立前的 ⚪
> 積壓已轉入 §3（**批次來源見 §3 各節標頭**——第 4 輪起指標句化、第 5 輪隨批次制
> 改指各節，免再增範圍句副本）。

## §0 使用規約

### 0.1 單坑七欄 schema（缺一欄＝條目不完整，不得標結案）

| 欄 | 內容 | 紀律 |
|---|---|---|
| ① 形態分類 | F1–F12 之一（§0.2；可擴，擴類規約見 §0.2 表下） | 按**症狀形態**歸類 |
| ② 嚴重度／狀態 | 嚴重度 `P0/P1/P2/P3`（P3＝低危/一致性級——既有事故已用此級，如 58 號「逾期未銷＝P3 資料一致性事故」，無損映射）；狀態 `open/機制已立/明文接受/結案` | 「結案」唯有複驗指令實跑通過 |
| ③ 事故經過 | 何時、何處、怎麼發現（引 worklog/handoff/判詞出處） | 引文帶檔:行 |
| ④ 根因 | **直接根因＋系統性根因**兩層都要 | 去重按根因不按症狀 |
| ⑤ 預防機制 | 機制名（CI 閘門／schema 約束／流程步驟） | 🔴 **不接受「更小心」**類答案 |
| ⑥ 對應 CI 閘門 | `既有：<腳本名>`｜`擬建：G-xx（入 §2）`｜`明文不可機制化＋理由` | 三選一必填 |
| ⑦ 複驗指令 | 可重跑的命令或步驟（grep／腳本／頁面操作序列） | 「我確認過」不算 |

### 0.2 形態分類 F1–F12（初版；可擴）

| 代碼 | 形態 | 典型例（來源見各條目） |
|---|---|---|
| F1 | 死控件（onclick 缺失/被攔截/無 handler） | 原型死控件基準線 |
| F2 | 假數字（顯示值與資料不同源或虛構） | pulse≠列表 count |
| F3 | 假成功（無後端效果的成功 toast/狀態） | toast 綠但未寫入 |
| F4 | 假憑證（驗證宣稱無可重跑腳本/快照） | 34 §7「120/120 PASS」腳本在 /tmp |
| F5 | 副本漂移（同一規則多副本互斥/漏同步） | R-11 家族九份副本（PR #52 六輪） |
| F6 | 引用失真（引節錯/出處錯/斷章） | waybill 58 §G.3→58 §D.5(b)；16 §F5↔16 §F4.4 |
| F7 | 值域缺陷（enum 自造/漏值/越界/狀態名誤用） | INVALID_TRANSACTION_KIND 自造碼；checkout `active` |
| F8 | 狀態機缺陷（不可達出口/非法轉移/寫死狀態） | 無 PSP 退款的 SUCCESS 出口不可達 |
| F9 | 租戶隔離缺陷（謂詞/索引缺 shop_id） | refundMarkAsSettled 謂詞初版 |
| F10 | 回歸（修 A 壞 B；點修致家族互斥） | #53 四輪自傷；03:124 修一半 |
| F11 | 計數腐化（裸數字/枚舉過期/全稱宣稱無查法） | 「487 條唯一 URL」；「9 支」清單 |
| F12 | 閘門失效（CI 該擋沒擋/掃描盲區/反竄改誤傷） | doc-claims diff 制看不到未提交行 |

擴類規約（第 4 輪補——原僅「可擴」二字無程序）：新增 F13+ 一律在上表加列＋於擴類
當輪 worklog 記「為何**既有形態表**不涵蓋」（第 5 輪去寫死計數——「12 類」在首次
擴類即腐）；不改既有代碼號語義。

🔴 命名空間聲明（第 10 輪立、第 11 輪去枚舉、第 12 輪範圍收窄——原「一律」在 §3
摘寫區結構上守不住、四處自違）：**本檔 F 形態碼與 §2 G-xx（閘門缺口）皆為 91
內部編號——與其他任何檔的節號與缺口編號一律無關**；**§0–§2 正文（含本表）內引用
外部節號一律帶檔名前綴**（「16 §F5」形）；**§3 為摘寫轉入暫存區——沿用來源措辭，
前綴於展開 §1 時統一補齊**（與 §3 標頭「摘寫轉入」紀律對齊）；【F#】方括號形
保留給本檔形態標記。

### 0.3 登記與結案流程

1. **來源**：驗收判詞 ⚪／歷史收割（附錄 A）／輪次中自報。先入 §3 暫存（**摘寫＋
   來源錨＋日期**——摘寫紀律見 §3 標頭：非逐字、展開 §1 時回讀原文；（第 6 輪對齊）：
   原「原文」與 §3 標頭「摘寫轉入」互斥，以摘寫為準），收割輪展開成 §1 七欄條目；
   同根因者併條、症狀列於同條。
2. **編號**：`K-###` 順序遞增，永不重用；被合併的條目留空殼指向存留條目。
3. **結案**：⑦ 複驗指令實跑通過＋⑤ 機制已落地（或②標「明文接受」帶裁定出處）。
4. **G-xx**：⑥ 選「擬建」者同步在 §2 開列；§2 每條必須寫「建的代價」，逐條裁定建/不建。

## §1 坑條目

> 骨架輪未展開條目。首批條目由附錄 A 收割輪產出；展開順序＝先 P0 家族
> （假憑證/租戶隔離/金額），後敘事類。

（待收割輪填入，`K-001` 起）

## §2 閘門缺口表（G-xx）

（G-xx＝本檔閘門缺口編號；命名空間聲明見 §0.2 表下。）

| 編號 | 擬建閘門 | 防的坑（K-###） | 建的代價 | 裁定（建/不建/待） |
|---|---|---|---|---|
| G-01 | 判詞 ⚪ 落籍檢查——每輪判詞的 ⚪ 條目必須落在**本檔 §3 ∪ 該輪 exact-head PR body 的合法 `DEFERRED_WHITE` 行**兩者的聯集（後者＝鐵律 15.1／D38 的 terminal-white 例外：`head` 精確等於受驗 `headRefOid`、grammar 精確、`comment:item` pair 可在完整判詞集合複驗；錯 head、重複或無來源者一律不算登記，仍須判紅）（PR #55 判詞連續多輪點名此缺口；例外射程與 grammar 見 `CLAUDE.md` 鐵律 15.1 與 §驗收基準） | ⚪ 蒸發族（§3.3「兩源句腐化」組的上游——⚪ 無人搬運即消失） | 判詞為自由文本、需解析 ⚪ 段與 §3 對條，另須讀 PR body machine line 並綁 head 複驗來源 pair，格式耦合高；誤報時擋錯 PR | **待**（收割輪一併裁） |
| G-02 | markdown 柵欄自檢——掃全檔行首三反引號行：行數須偶數、每個閉合行去圍欄後為空（式子＝#55 第 7 輪判詞所給；防柵欄黏尾文吞段） | 柵欄事故族（#55 第 7 輪 151 checkbox 被吞＝現行犯） | 極低（一支 grep/awk 即可）；範圍限 docs/specs（或全 docs） | **待**（收割輪與 G-01 一併裁；第 9 輪登記） |
| G-03 | `claude-review.yml` prompt 的 ⚪ 處置段與 terminal-white 例外同步＋deferred ingestion checker——現行 prompt 無條件要求作者把 ⚪「搬進坑登記簿」並明文宣告「建立前登記於 PR 描述」的過渡辦法作廢，與鐵律 15.1／D38 的 exact-head `DEFERRED_WHITE` 例外正面相反；合規使用該例外的 terminal-white PR 會被讀 prompt 的驗收方判成未登記。ingestion 側另缺「下一個 tree-changing PR 首候選是否已把 merged PR body 的 pair 入籍」的機械檢查 | ⚪ 蒸發族（同 G-01）＋**判準型 consumer 漂移**（prompt 是驗收方實際讀的判準，散文 consumer 同步不涵蓋它；來源＝PR #66 Claude issue comment `5369828302` 🔴-1(b)） | 改 `.github/workflows/` 命中鐵律 18.3，且 `claude-review.yml` 反竄改會令該 PR 自身驗收失效 ⇒ 必須另開 workflow-only PR；ingestion checker 另需先定義「既有 merged PR」的查詢範圍與起點（與本節 §3 已登記的同名 ⚪ 同源） | **提案／待**（🔴 使用者尚未裁定；依鐵律 20.4「需擴 workflow／CI 判準時先登記候選與代價、另開 18.3 PR」，本 PR 不得改 workflow，指派給 P-8 的 **0f workflow-only 接線**一併交付） |
| G-04 | **表格列儲存格數的全樹檢查**——掃全部 `*.md` 的表格列，**先按 GFM 規則切出儲存格再比對格數**：去掉行首與行尾的邊界直線（邊界直線不代表額外欄）後以未跳脫 `\|` 分割，切出的格數多於表頭欄數即報錯（GFM tables extension 逐字：超額格 "the excess is ignored" ⇒ 該列末欄被靜默截斷）。🔴 **不得直接數未跳脫直線**——本表即反例：五欄的表頭列與本列各有 6 個未跳脫直線（首尾各一為邊界），照直線數比對會讓這道閘門開跑第一秒就否決自己所在的表、連基準線都建不出來（來源＝Codex inline `3831890277`，2026-08-21） | Markdown 假結果族（§3 已登記本 PR 與另四檔實例：`specs/52`（兩處）、`specs/83`、`specs/53`、`worklog/2026-08-18-P8-自動化基建`） | 低（一支 awk/ruby 即可）；需先裁定射程（全 `docs/` 或含 `*.md` 全樹）與既有違規的處置（一次修完 vs 建立基準線） | **提案／待**（🔴 使用者尚未裁定；本 PR 的結構斷言只涵蓋本輪改動檔，抓不到既有檔——依鐵律 20.4 先登記候選與代價，另開 18.3 PR 實作） |
| （其餘待收割輪填入） | | | | |

## §3 ⚪ 轉入暫存區（待展開成 §1 條目）

> **批次來源制（第 5 輪改——§3.3 出現後「兩源全量」句失效）：各批次的來源寫在各
> 3.x 節標頭，本標頭不再全稱**。初始批次（§3.1／3.2）來源＝PR #52 描述 ⚪ 段＋
> bot 第 17–24 輪判詞 ⚪ 兩源（2026-08-17，PR-E1）。
> 條目為**摘寫轉入（非逐字）**——有刪節與補錨（（第 4 輪更正）：原「照錄原文」與實物
> 不符，至少四處經摘寫/插錨/去腐）；**原文出處＝各批次標頭所列來源**，展開 §1 引
> 「檔:行」時一律回讀原文；【F#】／候選標記＝轉入時另加的形態預標。
> 展開時按根因併條；「已於來源輪內處理」者展開時直接標結案候選。

### 3.1 自 PR #52 首輪起累積

- 103 個狀態機／111 條事件：考掘當時點算之快照，固定計法未補（驗收方點算 §3 表 89＋19=108、§5.1 資料列 90）——轉入時屆補計法或修數【F11】
- 487 條官方來源 URL：已於 #52 改快照標記（HANDOFF.md＋handoff §①）——結案候選【F11】
- HANDOFF.md:126 過時「尚未有代碼」行：已於 #52 順手更新——結案候選【F5】
- B2B「全域取最低價」舊式五處：46b:940／29:243／28:500／74:81／specs/54:428——重建 Phase R 收斂；specs/55 §B.3 tax_bp 表示法（尺度後綴宣告制回寫）；closed 判定式倉庫外三處：specs/16:232／research/06:111／specs/50:21（46a:152 為官方取證檔照錄不改）【F5】
- Q-86×2 的 M0 前置列位 vs §7 時點欄 M1 的矛盾：處置＝§9.2 M0 前置未決欄該兩格屬「刻意提前問」——登記為刻意提前、§7 時點欄不改【F5·明文接受候選】
- 15 §F5 回寫完成後，總綱三處「該去改 15 §F5」指示句成陳舊指示（§2.4 M1／§6.2 D-32／03 章 F.2#5）——複驗：`grep -rn "15-F5" docs/research/90*` 補「已回寫（PR #52）」註記【F5】
- limits.yml `late_capture_surcharge_rate_informational_only` 鍵（鍵名錨；行號快照＝轉入時 :775，原登記 :765 已漂移）以 float 主單位率 0.0175 表示，與總綱 §8 規則③口徑不合（informational-only 鍵是否豁免無明文）——下次動 limits.yml 時釐清【F7】

### 3.2 自 bot 第 17–24 輪判詞 ⚪

- specs/14:27「publish＝單一 transaction 內兩筆 UPDATE 原子切換」與 X-30 序列化鎖同族——X-30 家族收斂時一併補鎖【F5】
- specs/18:11「payload 只帶 ID 與必要摘要、消費時再查現值」與 A1 凍結規則張力——08 章已把 event payload 列入匿名化 PII 清單（crypto-shredding），18:11 措辭待 A1 家族收斂時同步【F5】
- 16 §F8.2 逾期未掃窗口；redirect 掛點家族餘四處（62:515／67:844／limits.yml:3605／原型 :7941·:10681）；specs/52:68 拆單舊形；specs/19 F1 主公式；doc-claims 歷史層警告（條數見腳本輸出，第 4 條＝worklog 總綱合成 :510）【F5/F11】
- 03-cart-checkout.md:124 更正註記把「admin orderCreate PENDING 單」列進「停在 open」後果——orderCreate 不經 Checkout、無 open 態可停；僅註記舉例越界（敘事層）【F6】
- specs/50:45 S-28 仍寫「Checkout active → completed / abandoned」——與正典三值互斥，形態同 #52 第 21 輪修的 specs/15 兩處【F7】
- specs/18:79／specs/39:598／39:167 三處硬編「64KB」與 `outbound_http.webhook_response_bytes_max` 同值四份持有——下次調值需四處同改【F5】
- specs/55:79（M09 refundCreate）仍是拆型前單一出口形——R-11 家族出 PR 後收斂【F5·F8】
- 12:308 staged 路徑豁免 20MB 抓取上限後，image/generic 走 staged 時預檢缺入參；12:312 未寫 presigned POST 帶 content-length-range——下次動 12 章時釘明【F8】
- 「先落 pending 再打金流」未分支 pending 形三處（22:32 Refund 列、原型 chilllove-admin-v2.html:3963 與 :10919-20 toast 文案）；specs/50:33 S-16 單一出口舊形；16:278 枚舉待下次動 16 §F5 補全【F5】
- specs/55 §A 總表未含 refundMarkAsSettled 列（M42）——limits.yml required_for 增列處已互指，55 下次更新時補列【F5】
- refundMarkAsSettled 名稱 resource 邊界案例（名為 refund、被改的列是 OrderTransaction）——改名與否待裁定；謂詞已補 kind 限定、實害已閉【F7·裁定候選】
- limits.yml:547「與前面 22 支的差別」計數陳舊（main 既有 49ca498 引入）——下次動該註釋時改指標句【F11】
- 15:213／:221／:428 三處「COD 走 manual gateway」與 15:442 把 cod 列獨立值互斥——(kind,gateway) 值域表釘時兩處對齊（16:271 已標待釘）【F7】
- 16:399／:400 兩既有碼（REFUND_EXCEEDS_MAXIMUM_REFUNDABLE／REFUND_CONCURRENT_MODIFIED）不在 28:312 正典 26 值內——正典表增列或標領域碼歸屬待裁定【F7】
- orders.mark_refund_settled 不適用 limits sensitive_permissions 清單（本尊 help 名單，over_refund 同形）——僅登記【F7】
- 05:214-216 金流狀態轉移表觸發欄（「部分退款」／「全額退款」）未帶 SUCCESS 限定——R-11 家族下次收斂時一併看【F5】
- 13 D.6（A1 引為出處的節）通篇未提「凍結 payload」——沉默非矛盾，A1 家族收斂時補【F5】

### 3.3 自 PR #55（本 PR）判詞 ⚪（2026-08-17–18；**輪次見各條末註記，本標頭不記範圍**——第 6 輪去硬編：範圍句在 3.x 層同樣必腐；同根因併組）

- doc-claims 歷史層警告（皆在 phase0 交接檔，位置以腳本輸出為準；exit 0、腳本管轄）——併一組【F11；來源＝第 1 輪 ⚪ 起逐輪沿掛】
- phase0／session 交接檔以**本機路徑**作接手第一步與計畫出處（`~/.claude/projects/…`、`C:\Users\…`）——跨環境不可達（審核環境 Linux 實測）；接手指標的可攜性待收割輪定形【F5；來源＝第 1 輪 ⚪ 起逐輪沿掛】
- §0.2 F1–F12 例證欄無檔:行錨（§1 尚空）——收割輪落地條目時補【F11；來源＝第 1 輪 ⚪ 起沿掛】
- lint-prototype WARN 136（ERROR 0）——與本 PR 無關的既有原型債，B 軌處理【F1 存量；來源＝第 1 輪 ⚪ 起沿掛】
- phase1 交接檔 §④ 單源句（歷史層）——更正註記已加（第 3–4 輪），結案候選【F5；來源＝第 2 輪 ⚪】
- 91 §0.1「擴類須在本表加列」指位含糊＋§0.2 無規約段——第 4 輪已修正文（指位改 §0.2、補擴類規約），結案候選【F6；來源＝第 3 輪 ⚪】
- #56 先合造成反向窗口（main 判詞模板已指 91 §3 而 91 當時只在本分支）——隨 #55 合併自動關閉，結案候選【F12；來源＝第 3 輪 ⚪】
- **§3 標頭全稱句的未來腐化**（第 2 輪 ⚪5 預警「下個 PR 加條目後『兩源全量』句需再改」——**一輪後由本 PR 自己應驗**（§3.3 出現即失效＝第 4 輪判詞 🔴1）；第 5 輪已落批次來源制，結案候選；教訓＝全稱句對「會成長的清單」必腐，寫批次/指標句）【F11·結案候選】
- 本 PR 文書自指涉腐化三小條（第 4 輪判詞 ⚪）：worklog Done 段「照錄」句與 91 摘寫句互斥（歷史層註記已加）；worklog Pending 段引 91:65-66 行號因 §0.2 插行位移（歷史層註記已加）；擴類規約「既有 12 類」寫死計數（第 5 輪改「既有形態表」）【F5/F11·結案候選】
- 第 5 輪判詞 ⚪ 三條（2026-08-18）：3.x 標頭輪次範圍硬編＝腐化下推一層（第 6 輪已去範圍改條末註記，結案候選）；附錄 A 名單複驗總數制對一換一盲（第 6 輪升集合比對，結案候選）；91:9「建立前積壓」句不涵蓋 §3.3——已為指標句無誤導，僅登記【F11】
- 第 6 輪判詞 ⚪ 四條（2026-08-18；第 7 輪收）：session 檔「累計要點＝」讀似全集（改「要點舉隅」，結案候選）；A.3 十格無機械複驗（補 ls-files 迴圈式，結案候選）；「判詞 ⚪ 落籍」無閘門（**已立 §2 G-01 候選列**，裁定待收割輪）；PR 描述自測快照日期未含跨日（已改 08-17–18，結案候選）【F11/F12】
- 第 9 輪判詞 ⚪ 新 3 條（2026-08-18；第 11 輪登記——第 10 輪漏搬＝G-01 現行犯，本條目即該事故的登記）：§3.3 條目不依輪次遞增（排序約定隨 G-01 裁定時定）；worklog「逐列核對僅此列缺」被證偽句無站點內更正註記（更正在十行外另節——AGENTS 歷史層形收割輪統一）；G-02 式子少「哪行算閉合行」定義＋CommonMark 長閉合柵欄／四反引號包三反引號邊界（裁定待、落地時定）【F11/F12；來源＝第 9 輪 ⚪3/⚪4/⚪6，餘四條沿掛已入】
- 第 8 輪判詞 ⚪ 新條（2026-08-18；第 9 輪登記，僅登記不順手修）：phase1 檔新註記插於句中（CommonMark type-2 HTML block 中斷段落、bullet 斷句——與既有句末擺法不一，收割輪定形時統一）；附錄 A markdown 結構零機械檢查（**已落 §2 G-02 候選列**＝判詞給式，裁定待）；worklog「151 個 checkbox」裸計數（複驗屬實、doc-claims R4 刻意窄不管——歷史層）；「十條」與 §3.3 現行條數漂移＋標記位置與「條末」措辭不符（歷史層）【F5/F11/F12；來源＝第 8 輪 ⚪】
- 第 7 輪判詞 ⚪ 群（2026-08-18；第 8 輪登記，**依使用者鐵律僅登記不順手修**）：worklog「全倉唯一」句缺查法（doc-claims 第 6 條歷史層警告）；§3.3「各條末」措辭與 4 條實際標記位置不符；worklog「十條」計數與現 11 條漂移（歷史層）；A.3 迴圈複驗漏第 10 格 scripts/*（glob 非路徑，結案候選前補判法）；G-01「防的坑」因果指向宜對第 3 輪 🟡4、格式屬骨架期權宜；phase1:16 空殼句陳舊（更正註記已加＝判詞明定處置）；session:78「含第 2 輪節」硬編輪數（同族待斷根）；⚪ 落籍閘門缺口仍在（G-01 裁定待）【F5/F11；來源＝第 7 輪 ⚪1–⚪9】

### 3.4 自 PR #58 bot 判詞 ⚪（2026-08-18，P-0 立法輪）

- 🔴 **熔斷閘門實證失效（本條 2026-08-18 第 13 輪就地重寫；初版兩個斷言皆已被實測推翻，
  依 bot R11 🟡3／R12 🟡3「教訓落庫免只活在 PR 留言」紀律更新）**：
  **初版寫的是**「label 仍未宣告，但靠 `--add-label` **自動建立**、失敗不擋」——
  **兩點都錯**：①`gh pr edit --add-label` **不會建立**不存在的 label（外部行為斷言，證據見本條末〔證據 E〕）；②因此 `|| true`
  吞掉的不是偶發失敗，而是**每一次**。實測後果＝#58 第 4–10 輪期間 workflow 連發
  ⛔「自動驗收就此停止」而**驗收一路照跑**（label 從未掛上、閘門實質失效整整六輪，
  複驗：翻該 PR timeline 的 ⛔ 留言與其後的判詞交錯）。現況：label 已於 2026-08-18
  由人工建立（`review:需人工裁定`，色 B60205），#58 第 11 輪判詞後**首次自動掛上成功**
  ⇒ 閘門自此真動作。🔴 **P-8 的要求因此不是「補一個宣告式資源」而是三件**：
  ①label 以宣告式資源（或 workflow 內冪等 `gh label create`）保證存在；
  ②`--add-label` **失敗即顯性報錯**，不得再吞；③**「label 缺失即紅」的斷言**——
  沒有它，同一個靜默失效可以原樣重演。（機制側①②曾於 PR #59 落地；**該 PR 已於
  2026-08-19 合併，而三件要求同時隨「取消熔斷」裁定作廢**——見下方更正註。）【F12】
  <!-- 🔴 2026-08-19 更正：使用者裁定「取消熔断机制，所有的必须循环到双清为止。
       不限次数」⇒ **熔斷閘門整個移除**（claude-review.yml 的 env 常數／job label 閘門／
       超輪分支全刪，PR #59），上面那三件 P-8 要求隨之作廢——①②已落地的代碼一併移除、
       ③不再需要。**本條目的歷史紀錄不改**（它記的是真實發生過的六輪靜默失效）。
       🔴 **要留下的是形態不是那個閘門**：「宣稱掛上了其實沒掛上、失敗被 `|| true` 吞掉」
       這個靜默失效形態仍然有效，任何新的 label／狀態類機制都要照它設防。
       移除隨 **PR #59 於 2026-08-19 合併進 main** ⇒ 複驗：`git grep -c -F -e add-label origin/main -- ':/.github/workflows/claude-review.yml'` **應 exit 1 且無輸出**（＝該識別字不存在；⚠️ **不得用 `git show <ref>:<path> | grep -c`**，`grep -c`／`pipefail`／MSYS 三重 fail-open 的現行證據分別見 `docs/dev/external-facts.md` B1／B3／B4）。 -->
  <!-- 〔證據 E〕2026-08-19 補（#58 Codex[4] 點名：本條①是**外部 CLI 語義**，原文只有結論，
       無來源 URL／取證日期／英文原文逐字，也沒標〔推論〕）。依 `AGENTS.md` §8.2 第 1 款補齊。
       🔴 **查證結論＝斷言為真，且可由上游原始碼證明** ⇒ 走「補證據」，**不得**降級為〔推論〕：
       把一條證得出來的事實寫成猜測，登記簿只會更不可信。
       🔴 **本條為何非補不可**：熔斷機制已隨 PR #59 全部移除，倉庫裡**再無可反推的代碼**
       （複驗見上一段的 git grep）⇒ 這則坑記錄是該事實在本專案的**唯一載體**。

       E1 gh 自身說明**只承諾「by name」，不含建立語義**（本機 gh 2.97.0，`gh pr edit --help`，實測 2026-08-19）：
             "--add-label name          Add labels by name"
          ⇒ 這只證明「沒承諾會建」，**證明不了「不會建」**。決定性證據是 E2–E4。

       E2 上游原始碼：`--add-label` 先把**名稱解析成既有 label 的 ID**，查無即報錯中止
          （取證 2026-08-19，釘 cli/cli commit `95d3a1db45abd547c2dafbee4f8a68ca53fb9c80`）
          <https://github.com/cli/cli/blob/95d3a1db45abd547c2dafbee4f8a68ca53fb9c80/pkg/cmd/pr/shared/editable_http.go#L18-L25>
             "addedLabelIds, err := options.Metadata.LabelsToIDs(options.Labels.Add)"
             "if err != nil { return err }"
             "return addLabels(httpClient, id, repo, addedLabelIds)"
          <https://github.com/cli/cli/blob/95d3a1db45abd547c2dafbee4f8a68ca53fb9c80/api/queries_repo.go#L806-L822>
             "for _, l := range m.Labels { if strings.EqualFold(labelName, l.Name) { ids = append(ids, l.ID); found = true; break } }"
             "if !found { return nil, fmt.Errorf(\"'%s' not found\", labelName) }"
          ⇒ 比對範圍是**已抓下來的 repo 既有 label 清單**（大小寫不敏感），查無即 `'<name>' not found` 並中止。
          （同檔 `api/queries_repo.go:1427` 的 `labels(first: 100, …, after: $endCursor)` 在 for 迴圈內分頁
           ⇒ 清單是全量，排除「label 存在但沒抓到」這個替代解釋。）

       E3 送出的 mutation **只吃 ID**：gh 送 `AddLabelsToLabelableInput{LabelIDs: …}`
          （同上 editable_http.go#L152-L156）；GitHub GraphQL schema 對該欄位的定義
          （`gh api graphql` introspection，實測 2026-08-19）：`labelIds` — "The ids of the labels to add."
          ⇒ **結構上沒有以名稱建立的入口**。

       E4 反向封閉：`gh api "search/code?q=createLabel+repo:cli/cli"`（實測 2026-08-19）只命中
          `pkg/cmd/label/create.go`／`pkg/cmd/label/clone.go` ⇒ 建 label 的代碼**只存在於 `gh label` 子命令**，
          `pr edit` 路徑上不是「沒走到」而是「不存在」。

       ⚠️ **範圍限定，不得外推到 REST**：E1–E4 只涵蓋 `gh pr edit --add-label`（走 GraphQL）。
          **REST `POST /repos/{owner}/{repo}/issues/{n}/labels` 對不存在 label 的行為，官方文檔查無明文**
          <https://docs.github.com/en/rest/issues/labels?apiVersion=2022-11-28>（取證 2026-08-19）：該端點只寫
          "Adds labels to an issue." 與狀態碼 200／301／404／410／422，**全頁未說明** label 不存在時如何
          （頁內唯一提到不存在的句子屬**移除**端點："This endpoint returns a 404 Not Found status if the label does not exist."）
          ⇒ REST 路徑**〔推論·未實測〕**，依賴它的設計必須自驗。可重跑驗證
          （🔴 **不得在本倉庫跑**——會產生真實 label／PR 變更；用拋棄式測試倉庫）：
             U=<your-github-login>
             gh repo create "$U/label-probe" --private --add-readme
             N=$(gh api "repos/$U/label-probe/issues" -f title=probe --jq .number)
             gh api -X POST "repos/$U/label-probe/issues/$N/labels" -f 'labels[]=zzz-not-exist'; echo "rc=$?"
             gh api "repos/$U/label-probe/labels" --jq '.[].name'   # 看 zzz-not-exist 有沒有被建出來
             gh repo delete "$U/label-probe" --yes

       ⚠️ **本證據會過期**：E2–E4 釘的是 cli/cli 的一個 commit，上游改實作即失效；
          重查法＝重跑 E4 的 search/code，並比對那兩個檔案的當前 trunk 內容。 -->
- 鐵律 16.1／17.2／17.3 引用的三條「既有記憶條目」（web-research-for-fixes／
  fix-only-what-is-flagged／full-automation-authorized）原不在倉庫內；接手輪已把裁定內容補入
  `docs/DECISIONS.md` D17–D18，條文本身仍自足，本條轉為結案候選【F11】
- doc-claims `IN_SCOPE` 刻意不含 docs/specs/／docs/research/／docs/design/ ⇒ #58 第 2 輪
  🔴1（91 誤插）落在 docs/specs/ 而無閘門攔得到——既有取捨（腳本檔頭有誠實聲明），
  要擴須先解「本尊路徑 vs 我方路徑」判別；與 G-01 同屬登記簿保真缺口群
  【F12；來源＝#58 第 2 輪判詞 ⚪，第 4 輪補搬——第 3 輪漏搬＝G-01 第二次現行犯，
  本條目即該事故的登記】
- docs/plans/ 納管後實得覆蓋僅 R1／R3（R4／R5 範圍判斷硬綁 worklog／handoff 未動）
  ——契約層註釋已於第 4 輪補限定；要收窄落差改註釋已做、改 R4 範圍屬 G 級裁定
  【F12；來源＝#58 第 3 輪判詞 ⚪1】
- doc-claims 新納管項（docs/plans/）無 fixture 釘住掃描範圍——既有形態（doc_* fixture
  的 **md** 當時全落在 docs/worklog/（doc_ 集合見 `ls spec/fixtures/ci_violations/ | grep ^doc_`；
  doc_no_files 是無檔 canary、doc_clean 另有 scripts 檔）；IN_SCOPE **既有項**裡也只有
  worklog 真被 fixture 覆蓋）；「擴充承重」證據＝擴入當輪抓到兩條（該輪已修）；
  複驗法＝暫置一條壞引用 md 於 docs/plans/ 重跑應轉紅（或收割輪建 doc_plans fixture）
  【F12；來源＝#58 第 3 輪判詞 ⚪2；措辭經第 5 輪校正——見下條；**第 6 輪已建
  `doc_plans_scope` canary fixture 並經突變驗證（拿掉範圍→test 轉紅），結案候選**】
- 🔴候選 doc-claims R4/R5 的 CI 生產調用疑似結構性未執行：ci.yml 淺 clone＋淺 base
  fetch（成因細化＝#58 第 8 輪判詞 ⚪2，第 10 輪補搬：doc-claims step 的 base fetch
  沿用了為 anti-tamper **單點 ref** 檢查設計的最小深度修法，而它吃的是**三點 diff**——
  同一修法兩種消費形態，前者夠用後者斷根）⇒ 三點 diff 無 merge-base ⇒ 腳本印「R4/R5 本次未執行」warning 後 exit 0——
  quality 綠不保證 R4 跑過（#58 第 7 輪判詞 ⚪1 機械跡象）；**本地互證同輪成立**：
  閘門於 commit 前跑時 R4 對未提交行盲（diff 對 base→HEAD），同一行 pre-commit 綠、
  post-commit 紅——雙重洞疊加＝該輪 R4 實質零執行。修法屬 P-8：CI fetch 深度足＋
  「未執行」由 warning 升 canary 退出碼；操作紀律先行＝**commit 後必再跑一次
  doc-claims**【F12；來源＝#58 第 7 輪判詞 ⚪1＋本地實測，G-xx 候選】
- convergence :84 納管範圍表把 R4 寫成生效中——已於第 8 輪在已知限制補「CI 生產調用
  疑似未執行」限定【F11；來源＝#58 第 7 輪判詞 ⚪2，登記即處置】
- worklog 引述性數詞誤中 R4（「九條 fixture」為引述舊註釋原文非現況斷言，R4 機械比對
  不分引述）——第 8 輪已改寫去數詞；教訓：引述含數詞時改寫或帶複驗式【F11；來源＝
  #58 第 7 輪判詞 ⚪3，登記即處置】
- m0-review-convergence fixture 表既有漏列 doc_volatile_cjk（PR #42 期引入時未補列）
  ——#58 第 7 輪隨 🔴1 同筆補齊並加「列數勿手寫」指標句，結案候選【F11；來源＝#58
  第 6 輪判詞 ⚪1】
- doc-claims R1 的 TOP_DIRS 不認去 docs/ 前綴的短式路徑（`specs/110-…`、`research/105-…`
  對 R1 隱形）⇒ 方案待建檔表的機械覆蓋比表面窄——已補進 m0 篇章已知限制；要真擴
  屬 G 級裁定（短式→長式對映需判別本尊路徑）【F12；來源＝#58 第 6 輪判詞 ⚪2】
- worklog:162（歷史層）「107 路徑三處統一」與當輪 HEAD 不符（CLAUDE.md 側 replace
  沒匹配到＝靜默 no-op）——第 7 輪已真改＋歷史層加更正註記；教訓：批次 replace 後
  必 grep 驗證每一處都真的變了【F11；來源＝#58 第 6 輪判詞 ⚪3，登記即處置】
- 15.4 順序偏差一例（#58 第 5 輪）：push 先於 15.2 最後重拉；判詞獨立複驗實害為零
  （全部既有留言時戳早於 push）——教訓落庫於此免只活在 PR 留言；⚠️ 判詞明示
  **再犯不是 ⚪**（15.4「回到本款起點重來」）【F11；來源＝#58 第 5 輪判詞 ⚪，登記即處置】
- 本條上一版摘寫兩處失真（「九個…fixture 全在」漏「的 md」致與 doc_no_files/doc_clean
  的非 md 檔矛盾；「七項」漏「既有」限定致與 HEAD 現值打架）——第 5 輪已就地校正並
  去裸數字；91 §3 摘寫紀律的實例教訓：摘寫刪限定詞＝造假數字【F11；來源＝#58 第 4 輪
  判詞 ⚪，登記即處置】
- 「commit 後必再跑一次 doc-claims」紀律無規範層落點：AGENTS.md 閘門節與 CLAUDE.md
  15.4 都只要求 commit **前**跑閘門，該紀律現僅存在於 m0-review-convergence 已知限制
  與上方雙重洞條目——照規範層執行的人不會知道要補跑；規範層補課屬改 CLAUDE/AGENTS
  （18.3 人工類），隨 P-8 修洞同批裁定【F12；來源＝#58 第 8 輪判詞 ⚪1，第 10 輪補搬】
- AGENTS.md §1 三層表無 docs/plans/ 一格：總方案路線圖段已宣告終態層（第 9/10 輪混合
  制），但只讀 AGENTS.md 的人（含未來驗收方）不會知道要回寫它——補表屬改 AGENTS.md
  （18.3 人工類），與上條同批【F12；來源＝#58 第 9 輪 bot 判詞 ⚪1】
- 總方案在 doc-claims 只吃 R1/R3、對裸數字（R4）零機械防線，而其路線圖段已是終態層
  ——實例＝§9.3 曾以「N+ 支」裸下限代替閘門全集列舉，存活到第 10 輪才去數量化；
  真收口需先解 plans 納入 R4 的誤報面，G 級裁定；與上方「實得覆蓋僅 R1/R3」條目
  同群【F12；來源＝#58 第 9 輪 bot 判詞 ⚪2；🔴 第 11 輪更正：初登記兩處誤寫
  「R2」——R2 是跨 PR 錨定**豁免**規則、無納管範圍可擴，裸數字規則＝**R4**。
  錯源自第 9 輪判詞原文、作者照搬（bot R10 🟡3 自承）；教訓＝引用規則編號時回開
  checker 檔頭對一眼，判詞也是會錯的資料源】
- 總方案 §五 標題自帶快照聲明（「行號為 2026-08-18 現值」＝AGENTS §2 合法快照寫法）
  vs 第 10 輪把 §五 劃入終態層——原型未動時兩者都不假，**下一個動
  `docs/design/chilllove-admin-v2.html` 的 PR 會讓整節同時是「合法快照」與「終態
  過期」**；修法候選＝檔首分層宣告對 §五 行號另立快照例外，或行號改 grep 錨點——
  隨 U-0 開工時裁定【F5；來源＝#58 第 10 輪 bot 判詞 ⚪1】
- 🔴候選 **判詞讀取事故：GitHub 未認證 API 的快取讓我拿到半截判詞**（2026-08-18
  第 13 輪自報，本輪 🟡 全數沿掛的直接成因）：#58 第 11 輪判詞 `created 13:48:53Z`／
  `updated 13:51:17Z`／全文 8532 字元，我於 **13:51:29Z**（更新完成後 12 秒）抓取，
  拿到的卻是 **2933 字元的早期版本**——只含 🔴 段，🟡 三條完全沒進我的視野，於是
  第 12 輪「一條未動」。根因＝未認證 REST 回應有快取，判詞留言又是**邊跑邊編輯**
  的（bot 先貼骨架再補全）⇒ 「留言已建立」≠「判詞已完整」。**危害是靜默的**：
  半截判詞讀起來完全正常，沒有任何截斷跡象。紀律先行＝**抓判詞前先確認 review
  check-run 已 completed，且抓到後比對 `updated_at` 與長度**；機制側請 P-8 把這條
  併進倒計時腳本的就緒判準。
  ✅ **已於 PR #59 落地並於 2026-08-19 合併進 main**：該腳本的判詞就緒判準改為
  「**該 head 的 `review` check-run 已 completed**」——check-run 掛在 commit 上，
  同時解掉「綁 head」與「判詞是否已寫完」兩件事（原判準是 PR 全域的留言計數，
  既不綁 head、也讀得到還在串流編輯中的半截內容）。
  【F12；來源＝本輪自報，非判詞點名——G-xx 候選，與 R4/R5 雙重洞同群（都是
  「檢查跑了但沒真看到東西」）】
- 🔴候選 **閘門一鍵配方以 `echo` 收尾 ⇒ 退出碼傳不出去、紅燈照樣 commit**（2026-08-18
  第 13 輪自報現行犯）：worklog 自測段那份「可複製貼上」的配方原本結尾是 `echo FAIL=$FAIL`，
  而 `echo` **恆成功** ⇒ 串成 `… && git commit` 時，就算迴圈裡已印出 `RED <腳本>`、
  `FAIL=1`，commit 照樣執行（本輪 doc-claims 紅著進了 commit，靠 post-commit 複跑才發現）。
  形態＝**「檢查跑了、也真的紅了，但結果沒有被消費」**，與 R4/R5 雙重洞、熔斷 label
  靜默失效同群（都是閘門存在但不生效）。已就地補 `test "$FAIL" = 0`；機制側候選＝
  把該配方收進一支腳本（如 `bin/ci` 的文檔輪子集模式），免得每個複製它的人各自帶著
  自己的收尾【F12；來源＝本輪自報，非判詞點名——G-xx 候選】
- AGENTS.md 閘門節與 CLAUDE.md 15.4 只要求 commit **前**跑閘門，與 doc-claims R4 的
  post-commit 補跑紀律對不上（該紀律現只在 `docs/dev/m0-review-convergence.md` 與本檔
  上方條目）——與既有同群條目合看；規範層補課屬改 CLAUDE/AGENTS（18.3 人工類）
  【F12；來源＝#58 第 11 輪 bot 判詞 ⚪1】
- 總方案的矩陣誠實註把 doc-claims 納管檔列成「worklog/handoff/dev/plans/規約檔」，
  漏了 `IN_SCOPE` 的 `scripts/` 那一項——註本身的結論（Q/R/S/A–F 交付物不在納管面）
  不受影響，但列舉不全；下次動該註時補齊【F11；來源＝#58 第 11 輪 bot 判詞 ⚪2】
- `config/ci.rb` 註釋裡指 schema drift 步驟的 `ci.yml` 行號已腐（實際位置以
  `grep -n 'schema' .github/workflows/ci.yml` 為準）——而 doc-claims 的 `IN_SCOPE`
  **不含 `config/`** ⇒ 這條引用沒有任何閘門攔得到，且它正是 #58 第 12 輪兩處更正的
  唯一引據。修法候選＝`config/` 納入 `IN_SCOPE`（誤報面待評），或就地改章節式指路
  （AGENTS §4 的辦法）【F12；來源＝#58 第 12 輪 bot 判詞 ⚪1】
- #58 worklog 第 12 輪節內的「🟡2」缺輪次限定，在標題寫著「bot R11 🔴2」的小節裡
  會被讀成 R11 🟡2（實指 R10 🟡2）——歷史層依規則加更正註記不改原文；與上方
  「引規則編號回開檔頭對一眼」同族【F11；來源＝#58 第 12 輪 bot 判詞 ⚪2】
- §3.4 標頭「自 PR #58 bot 判詞 ⚪」在第 13 輪之後不再涵蓋自己的內容：該節已含
  **非判詞來源的自報條目**（判詞快取事故、閘門配方 echo 收尾）且首條已由 ⚪ 重寫成
  🔴 ⇒ 標頭既不對來源也不對嚴別。§3.3 標頭已為同形態改過一次（「本標頭不記範圍」），
  照抄即可；每條目自帶【來源＝…】故不誤導。順帶：標了「G-xx 候選」的條目未同步開進
  §2 閘門缺口表（R4/R5 雙重洞那條亦然）——屬既有形態，一併登記
  【F11；來源＝#58 第 13 輪 bot 判詞 ⚪1】
- `scripts/await-verdict.sh` 的「尚未建立」錨定散在三處（CLAUDE.md 17 機制註記／本 PR
  handoff §③／方案 P-8 列），**現值皆真**（該檔只在 PR #59），但 **#59 一合併三處同時變假**
  ——而 91 這邊指名了 #59 的條目不會跟著腐。處置：列進 #59 的合併收尾清單，或改成
  「見 PR #59」式指路【F11；來源＝#58 第 14 輪 bot 判詞 ⚪1】
- 閘門一鍵配方的 `.py` 分支寫死 `python`（Git Bash 刻意為之），而 `config/ci.rb` 對應三步
  用 `python3` ⇒ 在只提供 `python3` 的環境上三支 `.py` 會因 command not found 全計 RED、
  原因被 `>/dev/null 2>&1` 吞掉，而第 13 輪新加的 `test "$FAIL" = 0` 會直接擋掉 commit。
  方向是 fail-closed 故僅登記；下次動該配方時改 `command -v python3` 探測式
  【F12；來源＝#58 第 13 輪 bot 判詞 ⚪2】
- 「雙向 parity」G-xx 候選未同步開進 §2 閘門缺口表：`docs/plans/2026-08-18-總方案.md` 逐字
  「要機制化就得把 parity 改成帶明列豁免的雙向比對（G-xx 候選，本輪未建）」——與本檔
  R13 ⚪1 是**同形態的新實例**（標了「G-xx 候選」卻沒開進 §2）。既有形態、已登記
  【F11；來源＝#58 第 18 輪 bot 判詞 ⚪1】
- 跨日 push 造成同段落並列相差一天的日期：同一 commit（`0dd1dc2`，git 時間
  `Wed Aug 19 00:03:30 2026 +0800`）在 `HANDOFF.md:8` 寫「2026-08-18」、`:58` 寫「2026-08-19」，
  `AGENTS.md:74` 寫「2026-08-17 首裁、2026-08-19 重申」。各日期在作者本地時區皆成立、非假值，
  但日後回讀易誤讀成兩份裁定。🔴 **同根因的實例本輪又出現一次**：本 session 自寫的輪詢
  守護程序用本地日期組 `since=2026-08-19T00:00:00Z` 去濾 GitHub 的 UTC 時間戳，把
  `2026-08-18T18:11Z` 的判詞整個濾掉而誤報逾時 ⇒ **凡與 API 時間戳比較，一律用 UTC 取得
  當下時間**（`date -u`），不得用本地日期字面值
  【F11；來源＝#58 第 18 輪 bot 判詞 ⚪2＋本 session 實測】
- `docs/handoff/2026-08-18-P0-…` §① 敘事停在第 7 輪，R15–R17 的法律紅線與新檔未在該段出現；
  但 `:14` 逐字「完整檔案清單以 worklog Changes 表（終態層）為準」是有效委派、該表也確實
  補上了新檔 ⇒ **不判為終態層失同步**，僅登記；下次動該 handoff 時順手補敘事
  【F11；來源＝#58 第 18 輪 bot 判詞 ⚪3】
- `docs/dev/m0-review-convergence.md` 的「## 變更記錄」停在 2026-08-17（PR #53），漏記
  2026-08-19 這一批（取消熔斷相關的四處改動）⇒ 該檔自帶的沿革段本身也是終態層、
  也會漂移。下次動該檔時補記；形態同「終態層失同步」【F11；來源＝#58 第 21 輪 bot 判詞 ⚪1】
- `91:286`（R18 ⚪2 那條）引「`HANDOFF.md:8` 寫 2026-08-18、`:58` 寫 2026-08-19」，
  但 head 實測該裁定句已移到 `:57`——**本檔自己就犯了它登記的那個坑**（引別檔行號會腐化）。
  🔴 主鍵紀律要求用內容錨點不用行號，本條登記時沒照做。下次動本檔時改成 grep 式引用
  【F11；來源＝#58 第 21 輪 bot 判詞 ⚪2】
- **取消熔斷後仍無任何機制保證驗收循環終止**（2026-08-19 使用者裁定的已知代價）。
  `docs/dev/m0-review-convergence.md` 已把責任移轉寫清楚（「每當同一類意見第二次出現，
  先問這一類能不能寫成腳本」），但**仍無 G-xx 候選、未掛 `config/ci.rb`**。
  🔴 實測佐證：PR #59 第 8–13 輪，每輪驗收意見**約四成是前一輪修改造成的終態文檔漂移**
  （r8①②／r9①④／r10②③／r11①②），靠紀律無效已由該包自身證實 ⇒ 候選機制＝
  「終態文檔提到的識別字必須存在於它宣稱的檔案裡」，待開包
  【F11；來源＝#58 第 20/21 輪 bot 判詞 ⚪3＋#59 實測】
- PR #58 描述的「改動」段仍是首輪三條，未含取消熔斷立法與 `91`／`m0`／CD-1 三處改動
  （輪次摘要放 PR 留言是本 PR 的既有做法，故不擋）【F11；來源＝#58 第 21 輪 bot 判詞 ⚪4】
- **`IN_SCOPE` 何時擴到 research／specs／design、由誰負責**：#58 第 21 輪 Codex 指出
  §2.5 誠實註把它寫成 Q／R／S／A–F 的硬前置卻無工作包負責 ⇒ 已把「硬前置」拿掉
  （那是被點名的最小修）。**擴充本身是範圍外**，本 PR 不裁定、不建包——2026-08-19 曾
  一度新建 P-9 工作包，**因違反「只修點名處」而撤除**（該擴散在其後三輪自產五條意見）。
  日後要做時再獨立立包【F11；來源＝#58 第 21 輪 Codex P1 ＋ 2026-08-19 使用者糾正】
- **附錄 A 收割總數在多處寫死 151，而實際會隨新 worklog／handoff 增長**：
  #58 第 20 輪 Codex 只點名 P-1 列（已去數量化），其餘四處（§一裁定表、§二資產表、
  §三現況表、§十序列）**維持原文不動**——同檔同類順手修屬擴散，登記於此
  【F11；來源＝2026-08-19 使用者糾正「只修點名的問題」】
- **複驗指令用 `git show main:` 是 fail-open 寫法**：沒有本地 `main` 的環境（CI checkout／
  新 clone）下該命令失敗、空 stdin 進 `grep -c` 回 **0**，而 0 恰好等於「該識別字已被移除」
  的讀數 ⇒ **失敗方向指向它要否證的結論**。#58 第 22 輪 bot 判詞只點名 `plans:171`（已改
  `origin/main:`），**同型寫法另有 6 處未被點名**（`CLAUDE.md:240`／`AGENTS.md:243`／
  本檔 `:159`／`docs/dev/m0-review-convergence.md:18`／`docs/worklog/2026-08-18-P0-…:607`／
  `docs/handoff/2026-08-19-鐵律遵守稽核與P8合併.md:18`）——依「只修點名處」不動，登記於此
  【F11；來源＝#58 第 22 輪 bot 判詞 🟡3 ＋ 2026-08-19 使用者「只修點名的問題」裁定】
  <!-- 🔴 2026-08-19 更正（#58 第 31 輪初版；**同日經 bot R25 🔴3 點名後再更正**——初版三處與實物互斥）：上面「另有 6 處未被點名」是第 30 輪的現值。**第 31 輪改成 `git grep -c <ref> -- <pathspec>` 式的是其中 5 處終態層宣稱**（`CLAUDE.md:240`／`AGENTS.md:243`（現 `:303`）／本檔 `:159`／`m0-review-convergence.md:18`／`handoff-0819:18`）；**第 6 處 `worklog:607`（該式實起於 `:606`）屬歷史層，依 AGENTS.md 分層規範不改原文、改以就地更正註處理（＝同輪 🔴1 的修）**。初版誤寫「六處全部改成」＋「全樹無殘留」——前者把第 31 輪自己的六處口徑（5 處 MAX_FIX_ROUNDS ＋ `plans:171`）當成本條所列的六處，兩者不是同一集合；後者被 `worklog:606` 直接否證。本條目保留為形態紀錄——fail-open 寫法本身仍值得警惕。現值複驗（**限 `main` 字面、限 `docs/` ＋頂層 `*.md`**；`git show <sha>:…` 形不在本式涵蓋面）：`git grep -n -E -e 'git sho[w] main:' HEAD -- ':/docs' ':/*.md'`（`[w]` ＝刻意的自排除寫法，令本式不命中它自己）。🔴 **判準是「命中的性質」，不是行號清單**：每一條命中都必須是**引述／更正註／歷史敘事**，**不得有任何一條是活的複驗式**——逐條看指令輸出即可判定。⚠️ **不釘行號、不釘條數**：初版釘了「恰 6 行」，同一輪（第 35 輪）重建 Changes 表時，內容欄逐字寫進了這個舊寫法，命中當場由 6 變 10 ⇒ **釘死的集合會被合法編輯打破**——一旦它常態性地對不上，它就只剩裝飾作用。快照（2026-08-19 第 35 輪）：10 條，分布 `CLAUDE.md` ×1／本檔 ×1／該 worklog ×8，全數為引述或歷史層。 -->
- **連續推播會讓驗收永遠拿不到結果**：`claude-review.yml` 有 `concurrency: cancel-in-progress`
  ⇒ 半小時內推四次（#58 於 2026-08-19 00:28／00:41／00:45／00:59），前三個 review run 全被
  砍成 `cancelled`，只有最後一個跑完。當時表面症狀是「bot 不出意見了」，實際是自己造成的
  【F11；來源＝2026-08-19 實測】
- **`91:307–308` 的佐證括號以偏概全**：宣稱「PR #59 第 **8–13** 輪，每輪約四成意見是自產
  漂移」，但括號只列 r8①②／r9①④／r10②③／r11①② **四輪**實例，第 12／13 輪無舉證。
  論點方向不因此動搖（四輪已足以支撐「反覆出現」），但「每輪」是全稱句而舉證不全
  ⇒ 展開成 §1 條目時要嘛補齊 12／13 的實例、要嘛把「每輪」改成「多輪」
  【F11；來源＝#58 第 22 輪 bot 判詞 ⚪1】
- **同一輪的計數口徑三處不一致**：第 23 輪的 commit `1b83df0` 標題與 worklog 節標題寫
  「自主全樹掃描**六項**」，而該節內文只列**四條**，當輪 PR 留言又寫成「Codex 2 ＋自主 2」。
  三個數字描述同一件事 ⇒ 讀者無法確定該輪到底處理了幾項。屬散文計數紀律
  （AGENTS.md §2「不得手寫可由代碼算出的數字」的鄰接形態：這裡不是代碼可算，
  但同一事實在同 PR 三處不同）【F11；來源＝#58 第 22 輪 bot 判詞 ⚪4】
- 🔴 **本條自記為 G-01 現行犯**：上面兩條是**上一輪判詞明文要求落籍**的 ⚪，而該輪未搬、
  隔一輪才由下一份判詞（第 23 輪 🟡4）以「程序義務未履行」再次點名。G-01（判詞 ⚪ 落籍
  無閘門）已在 §2 開列、裁定待收割輪；本次是它的又一次現行犯，登記於此讓下一輪看得見
  這是重複形態而非偶發【F11；來源＝#58 第 23 輪 bot 判詞 🟡4】
- **附錄 A 的「新增檔須同 commit 補列」紀律只涵蓋「本 PR 新建」、不涵蓋「merge 帶入」**：
  實測附錄 A 另缺 `docs/worklog/2026-08-18-P8-自動化基建.md` 與
  `docs/handoff/2026-08-18-P8-自動化基建.md` 兩檔（隨 #59 合併帶入本分支）。
  🔴 **本輪未補**——第 23 輪判詞只點名第 29 輪新建的那一檔，依「只修點名處」不擴散；
  兩檔連同此成因登記於此，列為 G-xx 候選（集合比對應涵蓋 merge 帶入的新檔）
  【F11；來源＝2026-08-19 研究實測 ＋ 使用者「只修點名的問題」裁定】
- **Changes 表表頭的複驗指令與該表宣告的層別不同源**：現用
  `git log --oneline <base>^..HEAD --name-only` 是**commit 的聯集**語義（中途新增又刪除的
  檔會被算進去），而 Changes 表宣告為**終態層**（必須等於 HEAD 事實），正確查法是
  `git -c core.quotePath=false diff --name-only main...HEAD`（三點式＝對 merge-base 比較；
  `core.quotePath=false` 防中文檔名被轉義成八進位而比對假紅）。
  🔴 **本輪未改**——第 23 輪判詞未點名此處，依「只修點名處」僅登記
  【F11；來源＝2026-08-19 研究（git 官方 `A...B` 定義）＋使用者裁定】
- **`CLAUDE.md` 鐵律 17.4 引述的被否決提案「升 R4／R5 為 error」，前提在同一天被自己推翻**：
  該處逐字是「否決了兩個機制化提案**（升 R4／R5 為 error、加推送前檢查腳本）**」，而
  `AGENTS.md` §7 已於同日更正——**R4 本來就是 error**，只有 R5 走 `warnings`
  （複驗：`grep -n 'violations <<\|warnings <<' scripts/check-doc-claims.rb`）⇒ 提案名稱裡的
  「R4」是無效項，被否決的實質只有 R5。🔴 **僅登記不修**：該句是使用者裁定的逐字紀錄，
  改它等於改鐵律本文（17.3 例外清單明列「改鐵律本文」），需使用者裁定；且提案已被否決、
  無實害。日後若重提機制化，先按本條把提案名稱收窄為 R5，別把一個已經是 error 的規則
  再「升」一次【F11；來源＝#58 bot R25 ⚪；R26 判詞點名「本輪未落籍」後補登】
  <!-- 🔴 2026-08-21 更正（PR #66 Claude comment `5365460704`）：上段的逐字來源原在
       `CLAUDE.md` 舊 17.4，但該條已由 D37 改寫；現行 17.4 不再含此句。歷史原文保存在
       `docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md` 的「17.4 配套」相關段落；本條只作
       歷史坑位，不再把現行鐵律當逐字落點。複驗：
       `git grep -n -F '升 R4／R5 為 error' -- CLAUDE.md docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md`。 -->
- **R4／R5 雙重洞條目缺結案註：兩項 P-8 修法都已隨 PR #59 進 main**：本節上方那條
  （錨點：`grep -n 'CI 生產調用疑似結構性未執行' docs/specs/91-pit-register.md`）把修法寫成
  「屬 P-8：CI fetch 深度足＋「未執行」由 warning 升 canary 退出碼」，兩項都已落地——
  ①ci.yml 的 doc-claims 前置步驟先 `git fetch --no-tags --unshallow origin || true` 再補抓 base；
  ②同 step 帶 `--require-base`，而 `scripts/check-doc-claims.rb` 對該旗標的處置逐字是
  「＝**檢查根本沒有生效**（exit 3）」。複驗：`grep -n 'unshallow\|require-base' .github/workflows/ci.yml`
  與 `grep -n 'require_base' -A 6 scripts/check-doc-claims.rb`。
  🔴 **但這條不是整條結案**：機制解掉的只是 **CI 側**的淺 clone；該條同時承載的「commit 後
  必再跑一次 doc-claims」屬**本地側**紀律，成因是 pre-commit 時 R4 對未提交行盲，與 clone
  深度無關、未因 #59 而消失（`AGENTS.md` §7 末段的 2026-08-19 實測即本地側）。把它讀成
  全條結案，下一個人就會停掉補跑
  【F12；來源＝#58 bot R25 ⚪；R26 判詞點名「本輪未落籍」後補登】
- **`docs/dev/m0-automation-infra.md` 的第二處 `gh --add-label` 斷言只寫「實測為假」、無出處**：
  逐字是「舊註釋稱「label 不存在時 `--add-label` 會自動建立它」——**實測為假**（2026-08-18）」
  （錨點：`grep -n 'add-label' docs/dev/m0-automation-infra.md`），依 `AGENTS.md` §8 屬外部行為
  斷言，必須附 URL＋取證日期＋英文原文逐字，或標〔推論〕並寫出怎樣驗證。
  🔴 **範圍外，僅登記**：該檔隨 PR #59 於 2026-08-19 合併帶入本分支、不在 #58 的 diff 內
  （複驗：`git log --format=%h -- docs/dev/m0-automation-infra.md`），依鐵律 17.2「只修點名處」
  不順手改；第 36 輪 commit message 也已自記「登記不動」。補證據時**不必重查**——本節熔斷
  條目的〔證據 E〕（E1–E4：gh --help／上游原始碼把名稱解析成 ID／mutation 只吃 ID／全庫
  `createLabel` 反向封閉）就是同一個斷言的完整取證，直接引它即可
  【F11；來源＝#58 bot R26 ⚪；第 36 輪 commit message 已自記「登記不動」】

- **worklog 第 38／39 輪歷史層敘事有兩處無來源的外部工具行為斷言**：
  ①逐字「**外部對照**：Biome／yamllint／ESLint／RuboCop 一致要求「豁免的作用域必須確定」⋯
  yamllint 是唯一放寬到鄰行的，而它只放寬**一行且只往上**⋯本專案 ±2 且雙向，**超出所有先例**」
  （錨點：`grep -n 'Biome' docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md`）——四個工具的
  豁免作用域是**四份外部文檔的語義**，且「超出所有先例」是全稱句；
  ②逐字「外部同向：Google 的 timeless documentation 專頁把 `currently`／`as of this writing`／
  `now`／`latest`／`new` 逐條列為避用字」（錨點：
  `grep -n 'timeless documentation' docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md`）——
  避用字清單是外部文檔的明列內容。兩處皆無 URL／取證日期／英文原文逐字，也未標〔推論〕，
  依 `AGENTS.md` §8.2 應二選一補齊。
  🔴 **範圍外，僅登記**：兩句都在 worklog 的**歷史層敘事**（記「那一輪查到什麼、據此怎麼裁定」），
  不是終態層規範；且判詞列為 ⚪、不擋通過。依鐵律 17.2「只修點名處」本輪不改 worklog 一個字。
  補證據時的落點＝該兩句原地補 URL＋取證日期＋英文原文逐字（四個 linter 的豁免作用域各自一條
  官方文檔；Google 那條為 `developers.google.com/style` 的 timeless documentation 頁），
  🔴 **不得改寫成〔推論〕**——它們都是查得到原文的事實，本節熔斷條目的〔證據 E〕已立過同一裁定
  （把證得出來的事實寫成猜測，登記簿只會更不可信）
  【F11；來源＝#58 bot R28 ⚪1】

- **附錄 A 的雙向集合判準會把 `docs/worklog/README.md` 納入歷史收割，但它是格式說明檔**：
  現行判準要求 `git ls-files docs/worklog docs/handoff` 與 checkbox 路徑集合相等，所以 README
  不能在不改規則的情況下略過。P-1 實作 checker 時須二選一：①白名單排除 README，並同步
  P-1 判準文字與 fixture；②維持全收，通讀後以「零抽取」完成。選案前不得一邊保留集合相等、
  一邊靜默略過模板檔【F11／F12；來源＝#58 bot R30 ⚪1，R31 🟡1 點名未落籍；取證日期＝2026-08-19】

- **P-0 主 worklog 的歷史 Pending 仍有一處「官方從未公布」外部全稱句**：
  `docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md` 的外部事實建檔輪 Pending 逐字寫
  「A5 的求值時機（push 當下 vs 合併時惰性）官方從未公布」。本輪 Codex 只點名終態層
  `docs/dev/external-facts.md` 的同型句；主 worklog 這段屬歷史層且未被點名，依鐵律 17.2
  只登記、不順手改。未來收割時須保留原文並追加更正註：有限檢索只能支持〔推論〕，不能證明
  「從未公布」；升格條件由下一條 A5 求值時機未決登記管理
  【F11；來源＝#58 Codex review `4972060836` 後的同型掃描；取證日期＝2026-08-19】

- **A5 求值時機〔推論〕與受控實驗不屬於已查證外部事實檔**：
  `docs/dev/external-facts.md` A5 只保留 GitHub rulesets 官方逐字與它能支持的證據邊界；「事件當下更新
  vs 合併判定時惰性求值」仍未決，不得押注。升格法＝在 scratch repo 啟用 stale dismissal，先核准
  PR A，再合併會改變 A merge-base 的 related PR B；在 B 合併後、嘗試合併 A 前後分別以
  `GET /pulls/{N}/reviews` 記錄 review state／時間並重複至少三次。只有官方文件明載求值時點，或受控
  實驗能穩定區分兩案，才可將結論升格
  【F11；來源＝#58 Codex review `4972265738` inline `3813089519`；取證日期＝2026-08-19】

- **驗收方外部語義 handoff 尚有第三處「官方從未公布」歷史全稱句**：
  `docs/handoff/2026-08-19-驗收方外部語義與研究前置.md` 的既有歷史層逐字寫
  「`require_last_push_approval` 的判準未取得（官方從未公布比 `submitted_at` 還是比 commit）」；
  有限檢索不能證明「從未公布」。R33 只要求依同輪先例落籍，故本輪依鐵律 17.2 保留原文不改；
  P-1 收割時須在原文鄰行追加證據邊界更正，不得覆寫歷史
  【F11；來源＝#58 Claude R33 issue comment `5342461892` ⚪1；取證日期＝2026-08-19】

- **GitHub primary rate-limit 指引不能支持「客戶端沒有任何放棄門檻」的全稱句**：
  官方逐字只要求「You should not retry your request until after the time specified by the
  `x-ratelimit-reset` header」，而 secondary 指引另寫 exponential wait 與 specific number of retries；
  兩段都沒有替本專案指定總 deadline。有限官方頁面檢索不能證明某機制「不存在」，故
  `docs/dev/external-facts.md` B6 只保留逐字可支持的邊界；長時間 poller 是否設 deadline／次數界線
  是本專案設計決定。升格法＝若 GitHub 日後官方文檔明載 primary 的總重試／時間契約，按新原文
  更新 B6；在此之前只以本地腳本契約與測試驗證我方選案，不把它冒充 GitHub 保證
  【F11；來源＝#58 Codex review `4973362395` inline `3813973532`；取證日期＝2026-08-19；
  官方來源＝<https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api>、
  <https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api>】

- **R37 對 `HANDOFF.md:126`「從未正確過」的範圍外觀察經 commit-specific 行號反證**：
  `git show 2811225:HANDOFF.md` 與 `git show 22d5448^:HANDOFF.md` 的第 126 行均逐字包含「從 0
  重建」；`22d5448` 在檔頭新增六行後，同一句才移到第 132 行。故三處既有「漂移錯錨」定性
  符合 git 史，不能按 R37 建議改成「建檔即錯」。本條保留反證，避免 P-1 收割時採用錯誤更正
  【F6；來源＝#58 Claude R37 issue comment `5344159684` ⚪1（已證偽）；取證日期＝2026-08-19】

- **第六次 handoff 對附錄 A 集合的全稱句漏掉 A.3**：
  `docs/handoff/2026-08-19-PR58-第六次新head驗收修復.md` 逐字寫「附錄 A 的集合只由
  worklog／handoff 路徑構成」，但現行附錄另有 A.3 的 specs／workflow／scripts 事故密集檔。
  該句屬歷史層且本輪未被要求改寫，故只登記；收割時須保留原文並追加射程更正
  【F11；來源＝#58 Claude R37 issue comment `5344159684` ⚪2（沿掛 R36／R35）；
  取證日期＝2026-08-19】

- **P-0 主 worklog 留有兩句已被終態查證推翻的歷史殘影**：
  `docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md` 仍可由
  `grep -n -E 'primary 無放棄門檻|非 strict 是對合併當下的 head 求值' docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md`
  找到 B6 舊標題與 A7 舊句；終態 `docs/dev/external-facts.md` 已分別撤除全稱句及依 test merge
  commit 例外收窄。
  兩處都是歷史層、R37 未要求改實物，故只登記；下次動主 worklog 時以鄰行更正註保真
  【F5／F11；來源＝#58 Claude R37 issue comment `5344159684` ⚪3；取證日期＝2026-08-19】

- **`await-verdict.sh` 的 `MAX_POLLS` 缺上界會讓超大整數假逾時**：
  現行只檢查正整數與前導零；超出 shell 整數範圍的值可使
  `while [ "$i" -lt "$MAX_POLLS" ]` 比較報錯，迴圈零輪後走 exit 4，與既有 `00` 假逾時同族。
  本輪被點名的只有 INTERVAL，依鐵律 17.2 不擴修；PR #60 rebase 時須保留其
  `MAX_POLLS_MAX`／十進位位數先比的上界驗證，並與 #58 的 INTERVAL 900–1500 契約合併
  【F7；來源＝#58 Claude R37 issue comment `5344159684` ⚪4；取證日期＝2026-08-19】

### 3.5 自階段一' PR-1 開場包驗證（2026-08-20）

- **總方案 §2.6 的 X3–X10 列少於表頭一欄**：`docs/plans/2026-08-18-總方案.md` 該表表頭
  宣告「#／資產／要點」，但 X3–X10 只提供代碼與一格內容；Markdown 會把內容全放進「資產」欄，
  「要點」留空。PR-1 點名射程只含 CD 解凍、§十二裁定回寫與新執行方案落庫，依鐵律 17.2
  本輪只登記、不順手補欄。複驗：對該表每列計算 `(?<!\\)\|` 命中數，須與表頭相等
  【F5；來源＝PR-1 開場包 Markdown 結構自查；取證日期＝2026-08-20】

- **鐵律 13.3 的導入包錨仍寫 PR-C0，但現行路線圖已改由 P-6 交付**：本輪 Claude bot
  把它列為 ⚪；它與本輪 D32 點名的合併授權不是同一修復根，且直接改 `CLAUDE.md` 會擴大
  鐵律本文修復射程。依鐵律 17.2 本輪只登記，P-6 開工時以內容錨追 `git log -p` 後另包同步
  【F11；來源＝PR #61 Claude 首輪判詞 ⚪；取證日期＝2026-08-20】

- **S-1 與已被移出本階段的 R-8 有同型射程疑義**：PR #61 Codex 只點名 R-8 屬階段二'，
  階段一'方案的 Q-1 列仍把「S-1 屬二'，本階段可先行」列為並行包。依鐵律 17.2 不把
  未點名的 S-1 順手移除；後續須由 D30 射程裁定另包處置，未裁前不得把本登記當成執行授權
  【F11；來源＝PR #61 Codex 首輪 review 後同型掃描；取證日期＝2026-08-20】

- **Windows Ruby `Tempfile` 與 Git Bash 的 workflow syntax 本機假紅**：原生 Windows Ruby
  產生並保持開啟的暫存檔，Git Bash `bash -n <path>` 在本環境無法讀取；改由 stdin 傳入時，
  Ruby text mode 的 CRLF 又會讓反斜線續行失真，誤報 `unexpected |`／`unexpected elif`。
  以倉庫外 local-only adapter 將同一內容正規化為 LF 後餵入 stdin，既有
  `check-workflow-syntax.rb` 與 11 條回歸測試皆綠，證明 workflow 實物未壞。本輪未被點名且
  `scripts/` 不在修復射程，依鐵律 17.2 只登記、不修改腳本；若日後另包處理，必須先補
  Windows 原生 Ruby＋Git Bash 的承重 fixture，禁止用跳過該閘門冒充通過
  【F12；來源＝PR #61 本機閘門複驗；取證日期＝2026-08-20】

- **四條件評估器成功文案只寫「可人工合併」，未呈現 D32 代行通道**：
  `.github/workflows/claude-review.yml` 的成功留言仍固定為「四條件齊，可人工合併」。這句
  本身為真，但 D32 生效後不完整：具名射程的非 18.3 PR 也可由互動式 Codex 帶 head 鎖代行。
  同根的 `docs/dev/m0-automation-infra.md` 也把評估器文案只描述為「可人工合併」，workflow
  日後改文案時必須同包同步該機制文檔，不能只改產生端。
  該 workflow 未被本輪點名修改且屬 18.3，依鐵律 17.2 只登記、不順手改；待 P-8 後續
  workflow 包同步時，須同時保留「18.3 永遠人工」與 `AUTO_MERGE=false` 的信任邊界
  【F11；來源＝PR #61 Claude 第二輪判詞 ⚪；取證日期＝2026-08-20】

- **第三輪 handoff 把四條件過度概括成所有合併通道共同門檻**：18.3 的條文停點是雙清後
  通知使用者人工合併；若 PR 修改 review workflow，反竄改還可能使條件②④結構上不產生。
  原文已按歷史層規則保留並追加更正註，後續交接不得把 D31／D32／18.4 的四條件門檻外推
  到 18.3，造成永遠等不到的通知死鎖
  【F11；來源＝PR #61 Claude 第四輪判詞 ⚪；取證日期＝2026-08-20】

- **硬規則已更新但執行 prompt 沒同步，會讓驗收方繼續發布規則明禁的內容**：鐵律 19 已禁止
  未取證推論，`claude-review.yml` 卻仍允許〔推論〕與「未經查證修法」。制度變更的完成面
  必須同時核對規範本文與實際消費者；只改其一不能宣稱生效
  【F11；來源＝PR #61 Codex inline `3818337781`；取證日期＝2026-08-20】

- **首次交付誤套回應輪，會引用尚不存在的 PR 編號與 last-push tag**：初次分支 push 前沒有
  PR 編號，tag 也只能在建立 PR 後命名；首次交付須走 base 累計盤點與 15.2 豁免，後續輪才
  走 `pr{N}-last-push..HEAD` 與三端點全量重拉
  【F7/F11；來源＝PR #61 Codex inline `3818337791`；取證日期＝2026-08-20】

- **`--match-head-commit` 只鎖 PR head，不證明驗收時的 base 仍是最新 main**：並行包可讓 main
  在某包完成驗收後前進；代行合併前須 fetch、合入最新 base、對任何新 head 重跑閘門與雙方
  驗收，再於合併前比較 base SHA。該流程仍不得宣稱消除最後一次比較後的外部服務競態
  【F7/F11；來源＝PR #61 Codex inline `3818337801`＋`docs/dev/external-facts.md` A3；
  取證日期＝2026-08-20】

- **跨輪重犯不能再靠下一輪抽樣發現**：2026-08-20 依使用者裁定，已用本檔 F1–F12、可追
  worklog／handoff 及 PR #58／#60／#61 三端點驗收紀錄做根因稽核。符合「跨事故復發或修後
  再犯＋已有固定處理＋反向複驗」者已升格為鐵律 20；完整證據與未升格理由落在
  `docs/dev/m0-review-convergence.md`「重犯根因收斂稽核」。本條只登記制度結果，不把未被點名
  的既有同型坑順手修掉；日後若要擴 checker，仍須先進 §2 列代價並另取裁定
  【F4/F5/F6/F8/F10/F11/F12；來源＝D34／CLAUDE.md 鐵律 20；取證日期＝2026-08-20】

- **階段一'方案 §6.1 的 fenced 偽代碼仍含 Markdown 粗體符號**：在「每個並行包」那行，
  `**` 位於 fence 內會按字面顯示，不能形成強調；與鐵律 20.2⑦同型。本輪點名的是建立防重犯
  鐵律，未點名回改既有方案該段，依 17.2 只登記不順手改；另包處理時以「§6.1 階段編排器」
  內容錨定位，移除 fence 內的 Markdown 強調符後再做實際渲染複驗
  【F6；來源＝鐵律 20 結構自查；取證日期＝2026-08-20】

- **Windows 原生 Ruby 執行 `bin/setup` 會在 extensionless `bin/rails` 取得 `ENOEXEC`**：
  `ruby bin/setup --skip-server` 能進入 setup，但其 `system! "bin/rails db:prepare"` 交給 Windows
  `Kernel#system` 後回 `Errno::ENOEXEC`；逐項改用 `ruby bin/rails db:prepare` 與
  `ruby bin/rails log:clear tmp:clear` 則退出 0，Rails specs 亦通過。本輪任務未點名 `bin/`，
  依鐵律 17.2 只登記不改；另包處理時須同時證明 Unix shebang 路徑與 Windows 原生 Ruby 路徑，
  不能以跳過 setup 冒充 wrapper 已修
  【F6/F12；來源＝鐵律 21 本機閘門復驗；取證日期＝2026-08-20】

- **Windows 的 `python3.exe` App Execution Alias 可能存在但不是可用直譯器**：PR #61
  延遲意見修復閘門中，`Get-Command python3` 命中
  `C:/Users/pisce/AppData/Local/Microsoft/WindowsApps/python3.exe`，實際執行 gate 卻回 9009；
  同機 `C:/Users/pisce/AppData/Local/Programs/Python/Python312/python.exe --version` 實得
  Python 3.12.10，指定該絕對路徑且設 `PYTHONIOENCODING=utf-8` 後三個 Python gate 全綠。
  本輪未被點名修改 `config/ci.rb`／腳本，依鐵律 17.2 只登記不改；Windows 本機配方日後須驗證
  候選直譯器能實際執行，而非只信 `Get-Command` 存在，並保留非 ASCII 輸出探針
  【F6/F12；來源＝PR #61 延遲意見修復 29 閘門 A/B 實測；取證日期＝2026-08-20】

- **Rails system spec 會因 test 環境 Vite 首次冷建置超過 Capybara 預設等待而假紅**：
  PR #61 的完整 29 閘門首跑只有 `bundle exec rspec` 失敗，結果為 `284 examples, 1 failure`；
  `spec/system/m0_admin_shell_spec.rb:18` 在點擊登入後立即等待 `/admin/products`，失敗訊息卻仍顯示
  `/login`。但同次失敗截圖已呈現正確的 CHILL LOVE 商品空狀態；`log/test.log` 亦逐步證明登入
  建立有效 session、302 到 `/admin`、`GET /admin` 回 200、首次 Vite 建置與 layout render 約
  3.58 秒，之後 `/admin/api/2026-08/graphql.json` 回 200。倉庫未設定
  `Capybara.default_max_wait_time`，而 `/admin` 到 `/admin/products` 是 React `Navigate` 的客戶端
  redirect；因此本次證據指向冷啟動等待競態，不是登入或授權失效。該 spec／測試基建未被本包
  點名，依鐵律 17.2 只登記、不改；日後獨立包須以穩健的頁面／路徑等待或測前建置處理，並同時
  複驗冷、暖兩種執行，不能把單次暖快取綠燈外推成已斷根
  【F6/F11/F12；來源＝PR #61 2026-08-20 本機 29 閘門首跑、失敗截圖與 test log；取證日期＝2026-08-20】

- **受限工具環境會令 Ruby 對工作區外 gem 路徑的絕對 `Dir.glob` 假性回空**：同一個
  `solid_cache-1.0.10/lib/generators` 路徑在受限程序內呈現 `File.exist? == true`、
  `Dir.children` 可列出，但 `Dir.glob(<絕對路徑>) == []`；Zeitwerk 2.8.3 的 ignore 規則正由
  glob 展開，因而錯把 `solid_cache` generators eager load，造成
  `uninitialized constant Rails::Generators::Base` 與 `0 examples`。相同命令在獲准的本機外層
  可列出該路徑，Rails 8.1.3.1 boot、MySQL `SELECT 1` 與定向 system spec `1 example, 0 failures`
  全部通過。這是驗收執行環境差異，不是專案碼缺陷；本包只登記不改。之後本機 Rails gate 必須
  先用絕對 glob canary 判別環境，失敗時改在有完整檔案枚舉權的本機層執行，禁止把
  `0 examples` 當產品失敗或成功
  【F6/F11/F12；來源＝PR #61 2026-08-20 受限／外層同命令 A/B 實測；取證日期＝2026-08-20】

- **PowerShell `ConvertFrom-Json` 日期再用 `DateTimeOffset.Parse` 會受本地時區二次解讀而假判舊資料**：
  PR #61 current-head Codex review 於 07:08:48Z 產生後，reviews／inline 總量已由 36／62 增至
  37／67，但以觸發時間篩選的 `new` 仍報 0；逐筆列出才證實新 review `4979980175` 與五則 inline
  已存在。成因是 `ConvertFrom-Json` 已把 ISO timestamp 轉成 `DateTime`，再交給
  `DateTimeOffset.Parse` 時按 Asia/Taipei 重解未帶出的 `Z`，把 UTC 07:08 誤當本地 07:08。
  本輪沒有倉庫 poller 被點名，依 17.2 只登記不擴修；日後 PowerShell 輪詢須直接比較 UTC
  `DateTime`／先 `ToUniversalTime()`，並保留集合總量或最大 ID 作獨立 canary，禁止只信時間濾鏡
  【F11/F12；來源＝PR #61 current-head review 攝取 A/B 實測；取證日期＝2026-08-20】

- **Codex 的「無重大問題」總結可能早於同一輪 inline，不能把總結到達當作留言集合終止**：
  PR #61 head `44ebd39` 的 issue comment `5352954268` 於 07:45:46Z 宣稱未新增重大 inline，
  但 exact-head review `4980284182` 與兩則 inline `3819608325`／`3819608329` 於 07:47:33Z
  才建立；合併前 GraphQL 守衛因此從 36/0 看到 38/2 並 exit 4，避免錯合。現有 workflow／
  poller 未被本輪點名，依 17.2 只登記不改；後續合併仍須在動作前重拉完整 GraphQL unresolved
  集合，禁止用較早的總結 comment 或安靜時間猜測 inline 已送完
  【F11/F12；來源＝PR #61 merge guard 與 review `4980284182`；取證日期＝2026-08-20】

- **Shopify combinations 類型數是易腐快照，方案現值已與官方頁漂移**：階段一'方案 §11.5
  仍寫「合法組合五枚舉」，但 Shopify 官方《Combining discounts》於 2026-08-20 取證的逐字
  現值為 "There are six types of discount combinations:"。current-head Codex 只點名同節把競品
  模型升格成我方選案，未點名這個固定數字；依鐵律 17.2 本輪只登記、不順手改。後續獨立包須
  以官方頁逐列導出或明確日期快照取代固定枚舉敘述，並防止把供應商現值當永久我方契約。
  URL：<https://help.shopify.com/en/manual/discounts/discount-combinations>
  【F5/F11；來源＝PR #61 exact-head comment `5353555384` 修法前官方複查；取證日期＝2026-08-20】

- **總方案 P-5 仍把 percent 比例鍵列為金額 float 的抓取目標**：
  `docs/plans/2026-08-18-總方案.md` 的 P-5 判準仍寫
  `currency_conversion_fee_percent` 要被抓出處置，但 `config/limits.yml` 的名稱、註釋與現值
  都把它定義為百分比；PR #61 inline `3820221217` 只點名階段一'執行方案的同型矛盾。依鐵律
  17.2，本輪只修被點名位置並在此登記；後續獨立包須裁定 percent float 維持，或先取得使用者
  對 basis points 表示法、鍵名與 consumers 同步遷移的批准
  【F4/F5；來源＝`git log -p -S currency_conversion_fee_percent`；取證日期＝2026-08-20】

- **總方案 CD-1 收口矩陣只要求最小 full-dump 還原，沒有驗 PITR**：
  `docs/plans/2026-08-18-總方案.md` 的 CD-1 列可在異地副本完成最小還原便收口，未要求保存
  dump 的 binlog coordinates、核對連續歸檔或重播到指定時間；PR #61 inline `3820221220` 只點名
  階段一'執行方案的演練步驟。依鐵律 17.2，本輪不擴改總方案；後續獨立包須與
  `docs/specs/11-production-baseline.md` §2-6 及 MySQL 8.4 PITR 官方程序同步
  【F4/F5；來源＝總方案 CD-1 矩陣與 MySQL 8.4 官方 PITR 文檔；取證日期＝2026-08-20】

- **D36 已改成本地 handoff，但 workflow prompt 與兩份 script 契約註釋仍指向倉庫 handoff**：
  `.github/workflows/claude-review.yml` 驗收 prompt 仍以「handoff §①」作倉庫終態層例示；
  `scripts/check-doc-claims.rb` 檔頭未帶「本地」限定；`scripts/test-workflow-syntax-rules.rb` 檔頭仍命令
  fixture 組成改變時「這裡、handoff、worklog 三處一起改」。前者會引導驗收方要求修改已凍結的
  `docs/handoff/`，後兩者目前只影響契約文字、不影響腳本行為。三者都屬鐵律 18.3，後續分成
  workflow-only 與 script-only 工作包，按 `AGENTS.md`「三層文字，三套規則」的新分流同步文字，
  不得在本 PR 順手改。workflow-only 包因修改的正是 `claude-review.yml`，**無法取得自身 head 的
  Claude 判詞**；須取得 current-head Codex review、機械 CI 與 validation-skip 正向證據後停止
  自動放行，通知使用者做獨立人工審核／合併，再由合併後第一個 PR 跑 canary。script-only 包須
  同時覆蓋上述兩份 script 契約註釋；兩個工作包都依 18.3 走人工合併
  【F5/F12；來源＝PR #62 Claude 首輪判詞 issue comment `5356127623` 🟡3／⚪1、exact-head
  Codex inline `3822037663`／`3822037669` 與 Claude comment `5356779594` 🟡1／2；
  取證日期＝2026-08-20】

- **D36 凍結既有 handoff 後，§3.4 的「下次動該 handoff 時順手補敘事」已不可執行**：
  原條目所指檔案是 `docs/handoff/2026-08-18-P0-方案落庫與鐵律16-18.md`，目標在 §① 內以
  「第 26–27 輪補入本節」為穩定內容錨；可用
  `git grep -n -F '第 26–27 輪補入本節' HEAD -- 'docs/handoff/2026-08-18-P0-方案落庫與鐵律16-18.md'`
  唯一重取。原處置要求日後回寫 R15–R17 敘事，但現行 `CLAUDE.md` 鐵律 21.3 禁止再修改既有
  `docs/handoff/`。收割到 §1 時應保留舊條目作沿革，把未來更正分流到新 worklog，若屬使用者
  裁定另進 `docs/DECISIONS.md`；回指須使用上述精確路徑與穩定內容錨，不得解除唯讀或把本登記
  當成改檔授權
  【F5/F11；來源＝PR #62 Claude 首輪判詞 issue comment `5356127623` ⚪2、exact-head Codex
  inline `3822037678` 與 Claude comment `5356779594` 🟡3；取證日期＝2026-08-20】

- **PR 描述的 Changed docs 清單會漏列同一 head 的實際改檔**：PR #66 首輪描述列出多份制度檔，
  但沒有列 `docs/specs/91-pit-register.md`，即使該檔已在 PR diff。這是遠端描述與 Git tree 集合未
  對帳的同型風險；本輪依 ⚪ 僅登記，不為它改 Git tree。後續可在候選凍結後用
  `gh pr diff <N> --name-only` 與 PR body 的 Changed docs 清單做集合複驗；是否機械化仍待 §2 裁定
  【F5/F11；來源＝PR #66 Claude issue comment `5364608941` ⚪1；取證日期＝2026-08-21】

- **worklog 的完整閘門總數若未綁日期／ref／重跑命令就會腐化**：本工作記錄 Done 段保存
  `GATES_ALL_GREEN=29`，但沒有在同位置給出計數的取得日期、候選 ref 與導出命令；之後
  `config/ci.rb` 改動便可能讓數字失真。本輪依 ⚪ 與歷史層規則只登記、不靜默改寫原句；後續
  需要引用時應用當前 ref 的可重跑 selector 取代裸總數
  【F5/F11；來源＝PR #66 Claude issue comment `5364608941` ⚪2；取證日期＝2026-08-21】

- **worklog 的 Changes 清單是否應包含 worklog 自身未有成文規則**：PR #66 第二候選的 Changes
  段列出其餘變更文件，未列該 worklog 自己；驗收方明載「本倉庫無成文規定」，故本輪只登記、
  不藉此擴寫交付規則。若日後要把 Changes 當完整集合，須先裁定是否自含，並以
  `git diff --name-only <base>...<head>` 與該段 selector 做集合 fixture，避免人工計數
  【F5/F11；來源＝PR #66 Claude issue comment `5364935551` ⚪1；取證日期＝2026-08-21】

  **2026-08-21 D38 處置**：鐵律 21／worklog README 已改成每個獨立 Git 單位維護同一份
  worklog；本工作記錄的 Changes 終態清單亦納入自身。是否自含不再靠讀者猜測。

- **worklog 的 Markdown 渲染／表格計數若沒有可重跑命令與實際輸出就不能由第三方複驗**：
  PR #66 第二候選的 20.2.7 只聲明文件與表格皆成功，沒有保存 selector、API 呼叫與各結構計數；
  doc-claims 綠也不涵蓋 GitHub render 結果。後續若需要把 render 當驗收證據，應在 PR artifact／
  本地 handoff 保存命令與輸出，worklog 只保留綁 head 的快照引用
  【F5/F11；來源＝PR #66 Claude issue comment `5364935551` ⚪2；取證日期＝2026-08-21】

  **2026-08-21 D38 處置**：鐵律 20.2.7、階段一方案 §10 與本工作記錄改用穩定內容錨，並要求
  GitHub `/markdown` 回傳後驗證目標列最後一個 `<td>` 仍含末欄 sentinel；完整命令與輸出留同一
  本地 handoff，不再只留節點總數。

- **下位方案只靠上游條款繼承「過渡期人工合併」，讀者可能漏掉就地限制**：階段一方案 §6.2
  第 8 步仍保留 ④評估器 `1111` 後代行合併的常態路徑，過渡期限制由同節第 7 步及 CLAUDE
  18.1 上游提供。兩路徑目前不互斥，但 consumer 就地不重述會提高漏讀風險；若日後修改該步，
  應加入相鄰 guard 或用同一狀態 selector 生成，不在本輪順手重寫
  【F5/F11；來源＝PR #66 Claude issue comment `5365173662` ⚪1；取證日期＝2026-08-21】

  **2026-08-21 D38 處置**：階段一方案第 5／7／8 步已就地撤銷舊 evaluator／wait 腳本的證據
  效力，並明載 0e／0f 合併前只能人工合併；不再依賴上游條款補足互斥 guard。

- **worklog 表格使用倉庫內不可搜尋的臨時表名，第三方無法從名稱定位證據**：本工作記錄
  20.2.7 使用 `m0-root`／`total-p`／`total-risk`／`phase-sequence`／`worklog-matrix`，但這些不是
  文件錨點或腳本 selector。後續若需保存同類 render 證據，表名須對應穩定內容錨或 artifact key
  【F5/F11；來源＝PR #66 Claude issue comment `5365173662` ⚪2；取證日期＝2026-08-21】

  **2026-08-21 D38 處置**：終態反向複驗以表格中的自然內容錨（例如
  `docs/worklog/README.md` 與 `P-8（D38 現行）`）定位目標列，不再使用倉庫外臨時表名。

- **新舊 evaluator 都叫 C1，只有收斂文件明載橋接，基建文件仍可能被誤讀為現值**：
  `docs/dev/m0-automation-infra.md` 仍以 C1 描述已在 main 運作的 REST inline 加總 evaluator；
  `docs/dev/m0-review-convergence.md` 才說明新 C1 尚待 0e／0f。0e 落地時須同步基建文件或改成
  `legacy_C1`／`review_state_C1` 等不混淆名稱；本輪未改該檔，依 17.2 只登記
  【F5/F11；來源＝PR #66 Claude issue comment `5365460704` ⚪1；取證日期＝2026-08-21】

  **2026-08-21 D38 處置**：`docs/dev/m0-automation-infra.md` 現以頂層警告與「舊四條件
  evaluator」標題標明只屬已部署歷史，且不得作 C1／C3／雙清／合併證據；現行狀態機只指向
  `docs/dev/m0-review-convergence.md` 與 0e／0f／0g。

- **總方案 P-8 同一儲存格先寫舊「兩單元」再於末尾覆寫 D37 現值，讀到中段會拿到舊流程**：
  現值可由格末 D37 補充辨認，但 producer 仍同時承載相反時態。第二語義包或 P-8 終態回寫時
  應拆歷史／現行層或在舊句前加明確歷史標記；本輪依 17.2 不順手重排大型表格
  【F5/F11；來源＝PR #66 Claude issue comment `5365460704` ⚪2；取證日期＝2026-08-21】

  **2026-08-21 D38 處置**：總方案 P-8 現行表只保留 0e／0f／0g 一列；舊合包與兩單元文字移入
  明確 HTML 歷史註，不再渲染成現行表格。階段一方案的狀態表、收口段與 Verification 同步改名。

- **已部署 evaluator 與 `await-verdict.sh` 看不到 Codex clean issue-comment 載體，拿它們判雙清會
  結構性假死**：CLI 全量取證顯示 PR #61 issue comment `5351471350`、PR #64 issue comments
  `5358332294`／`5363805191` 均由 `chatgpt-codex-connector[bot]` 發出，首行以精確前綴
  `Codex Review: Didn't find any major issues.` 開頭、尾句不同，並帶獨立 `Reviewed commit:`；相同
  head 沒有 clean REST review。另有 PR #61 comment `5352954268` 的 B 型兩個非空首行
  `## 驗收結論`／`**未發現需要新增 inline 意見的重大問題。**`，但其後 1 分 47 秒又到 finding
  review `4980284182`，所以 clean 事件不能單獨作終態。舊 evaluator 只從 reviews／inline 建 C1，
  舊 wait 腳本也不解析受控 issue-comment 載體，故不能以「沒看到 review」外推 Codex 未完成。
  D38 已撤銷兩者的裁定權；0e fixture 必須覆蓋 A 型前綴＋尾句、B 型首行、先 clean 後 finding、
  finding review、issue-comment finding及缺／多／錯 ref，0f 才可接線
  【F5/F9/F11；來源＝PR #66 Claude issue comment `5365735867` ⚪1＋後續 comment
  `5366398775` 的複驗＋上述四則 GitHub CLI 實物；
  取證日期＝2026-08-21】

- **只比較 Markdown pipe／`<td>` 數量會在 GFM 丟棄超額儲存格時假綠**：PR #66 worklog 的
  20.2.2 末欄含未跳脫 shell `|`，GitHub 仍輸出預期 `<td>` 數，卻把超額第四格丟棄，造成末欄
  內容殘缺。D38 已把固定判準升為「結構數量＋最後 `<td>` 必含末欄 sentinel 全文」，並把該列
  shell 改成多個 `rg -e`，避免 live table 再含裸直線
  【F6/F11；來源＝PR #66 Claude issue comment `5365735867` 🔴2；取證日期＝2026-08-21】

- **worklog 的「⚪ 已登齊」若只點名首輪 comment，後續輪次增加後會變成完成性敘述滯後**：
  PR #66 worklog 20.2.3 仍只寫 comment `5364608941` 的兩條 ⚪，但本 PR 後續多輪 ⚪ 已另在本節
  登記。該句不是錯誤否定，卻不能再代表全 PR 完成性；日後只用具名 ledger 或動態集合對帳，
  不把單輪例子寫成全量證明。本輪依 17.2 只登記，不回寫該歷史列
  【F5/F11；來源＝PR #66 Claude issue comment `5366398775` ⚪1；取證日期＝2026-08-21】

- **階段一排程表的「代行合併」靠 0e／0f 上游完成後才成立，consumer 沒有就地重述 guard**：
  `docs/plans/2026-08-20-階段一執行方案.md` §2 排程表實際帶無條件「代行合併」文字的
  CD-3／P-3／P-7／Q-1／Q-3 等列位於
  0e／0f 後，按依賴順序不會在過渡期直接代行；但每列只寫「代行合併」，讀者若跳讀表格會漏掉
  上游前提。日後修改這些列時應改由同一狀態 selector 產生或就地附 guard；本輪依 17.2 只登記
  【F5/F11；來源＝PR #66 Claude issue comment `5366398775` ⚪2；取證日期＝2026-08-21】

- **AGENTS §6 的兩個流程摘要已不再逐字等於鐵律 15 現值**：未改 context 仍用「全部閘門逐支
  親眼看退出碼 → commit」與「15.2 重拉留言」，而 CLAUDE 15.4 現值是候選 tree 凍結後跑一次
  全部正典閘門，15.2 則叫「最終重拉」。語義未被推翻且本輪未點名修該 context，依 17.2 只登記；
  下次改 AGENTS §6 時用內容錨同步，不以本條授權順手改本文
  【F11；來源＝PR #66 Claude issue comment `5367036421` ⚪1；取證日期＝2026-08-21】

- **總方案歷史註內仍藏有自稱「D37 現值補充」的不可見 blockquote**：可見的
  `P-8（D38 現行）` 列與其後「歷史定位」已給正確入口，但 HTML comment 內仍新增了舊「現值」字樣。
  它不影響渲染，且 Claude 明列為範圍外觀察；依 17.2 只登記，日後移動該歷史區時一併改成沿革措辭
  【F11；來源＝PR #66 Claude issue comment `5367036421` ⚪2；取證日期＝2026-08-21】

- **總方案 §2.6 的 X3 表格列缺結尾直線**：同一表 header／其他資料列每列有 4 個未跳脫 `|`，
  X3 列只有 3 個，GitHub Markdown 會把它交給寬鬆表格解析而非維持明確欄界。本列早已存在於
  `origin/main`、不是 PR #66 改動，也未被本輪 reviewer 點名；依 17.2 只登記，不在制度包順手修。
  複驗：以 fenced-code-aware 掃描定位 `docs/plans/2026-08-18-總方案.md` 的 `| X3 |` 並比較同表 pipe 數
  【F5/F11；來源＝PR #66 整合修復 targeted Markdown 檢查、PR #66 Claude issue comment
  `5368272566` ⚪3；取證日期＝2026-08-21】

- **基建歷史說明仍用容易自命中的 `grep -n "MAX_FIX_ROUNDS"` 作複驗**：
  `docs/dev/m0-automation-infra.md` 的舊機制廢止說明中仍保留該指令，而現行固定寫法是
  以 `git grep` 與自排除 pattern 檢查 Git tree。Claude 明列為範圍外觀察；依 17.2
  只登記，不修該 consumer，日後改動該段時再用不自命中的 `git grep` 取代
  【F11；來源＝PR #66 Claude issue comment `5367753356` ⚪1；本條根因敘述仍待更正的觀察來源＝
  PR #66 Claude issue comment `5368272566` ⚪2；取證日期＝2026-08-21】

- **AGENTS 過渡期摘要仍只稱「新 C1 evaluator」，與現行 C1–C4 完整 evaluator 名稱不一致**：
  對應段落的合併 guard 與其他 consumers 已明載 C1–C4，此行只是不精確摘要，不改變
  現行狀態；Claude 明列為範圍外觀察。依 17.2 只登記，不修 `AGENTS.md`
  該行，日後改動該摘要時再同步成 C1–C4
  【F11；來源＝PR #66 Claude issue comment `5367753356` ⚪2；取證日期＝2026-08-21】

- **worklog 的歷史更正仍保存已被 D38 翻轉的 `README.md` 無 diff 斷言**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的歷史 HTML 更正要求
  `git diff --quiet origin/main -- docs/worklog/README.md` 為 exit 0，但 D38 已刻意把產物粒度包併回
  本包，README 現為 PR #66 的變更檔，故該舊式今日必然 exit 1。它位於歷史層且不改現行機械
  行為；依 17.2 只登記，日後整理該歷史段時以日期化更正取代，不在本輪順手改原文
  【F5/F11；來源＝PR #66 Claude issue comment `5368272566` ⚪1；取證日期＝2026-08-21】

- **worklog 的 mutation 紅燈宣稱曾缺可直接重跑的公開 wrapper**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 曾記憶體移除 registered pair 後輸出
  `WHITE_LEDGER_MUTATION_RED=1`，但當時刊出的 PowerShell block 本身只執行正向集合比較，
  第三方不能由該 block 單獨重現歷史輸出。屬證據呈現缺口，不反轉集合對帳現值；依 17.2
  只登記，日後引用歷史 mutation 時必須同時刊出 fixture／wrapper
  【F5/F11；來源＝PR #66 Claude issue comment `5368608706` ⚪1；取證日期＝2026-08-21】

- **階段一方案對 workflow validation-skip 的原因摘要過度壓縮**：
  `docs/plans/2026-08-20-階段一執行方案.md` 以「新 workflow 尚未進 default branch」概括
  0f 自身只能離線驗證、0g 才能 production canary；結果與分工正確，但沒有在該處完整重述
  GitHub／Claude action 的 server-side anti-tamper validation-skip 機制。依 17.2 只登記，
  不藉白色觀察順手改方案；日後若修改 0f／0g 原因欄，須引用已取證的 validation-skip 實物
  【F5/F11；來源＝PR #66 Claude issue comment `5368608706` ⚪2；取證日期＝2026-08-21】

- **PR body 與 worklog 的 `LEDGER_TUPLE` 呈現形態不一致**：
  worklog 把 tuple 放在 `text` code fence，PR body 的 raw tuple 行則直接相鄰，GitHub 會以
  paragraph soft-break 呈現；機械 parser 讀 raw body 且逐行錨定，行為與資料未反轉。依 17.2
  只登記，不為呈現差異改 remote body；日後若把 tuple 改成需人工閱讀的主要介面，再統一渲染形態
  【F5/F11；來源＝PR #66 Claude issue comment `5369077825` ⚪1；取證日期＝2026-08-21】

- **舊「五處共用依據」歷史更正仍指向已刪除的兩個 consumer**：
  本 PR 重寫現行收斂制度時，`CLAUDE.md` 與 `docs/dev/m0-review-convergence.md` 已不再保留原本
  共用的 fail-open 複驗式，但本檔歷史更正仍以「五處」列出它們。現行規則方向與 doc-claims
  沒有反轉；依 17.2 只登記，日後整理該歷史更正時再按實際 consumer 集合日期化校正
  【F2/F11；來源＝PR #66 Claude issue comment `5369375370` ⚪1；取證日期＝2026-08-21】

- **⚪ 對帳 observed reviewer allowlist 與 registered 來源字面不對稱**：
  observed 端依 workflow 接受 `claude[bot]`／`github-actions[bot]`，registered regex 仍要求來源
  字面為 `PR #66 Claude issue comment`；現有 recovery 身分留言沒有 ⚪，所以本輪集合未反轉。
  依 17.2 只登記；日後若 recovery reviewer 真承載 ⚪，須把來源 grammar 與實際作者一起版本化，
  不得以錯作者字面硬湊集合
  【F5/F11；來源＝PR #66 Claude issue comment `5369375370` ⚪2；取證日期＝2026-08-21】

- **`Assert-FrozenLedgerCoverage` 的射程 predicate 仍有一半是自由文字**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的 coverage 函式以 `### exact-head`＋7 位 hex 標題
  認列射程，legacy section 則靠硬編標題字串與硬編 head 具名補進。marker 已是 full-SHA 且逐段
  必須存在，故本輪集合未反轉；但「標題換句話就脫離射程」這個產生器類別只是上移一層。依 17.2
  只登記，日後整理該函式時改以 marker 為唯一真源、移除標題與硬編 head 依賴
  【F5/F11；來源＝PR #66 Claude issue comment `5369828302` ⚪1；取證日期＝2026-08-21】

- **terminal-white「下一個 tree-changing PR 全量讀既有 merged PR body」缺範圍與查詢起點**：
  `CLAUDE.md` 鐵律 15.1、`docs/DECISIONS.md` D38 與 `docs/plans/2026-08-18-總方案.md` P-1 都要求
  批量入籍，但沒界定「既有」涵蓋哪些 PR、自哪一號起、用什麼查詢，也沒有對應 checker ⇒ deferred
  pair 可能無限期停在遠端 body 而本檔讀不出缺口。不反轉現值（本輪 terminal-white 例外尚無實際
  使用者），依 17.2 只登記；機械化候選已併入 §2 的 G-03（ingestion checker），待使用者裁定
  【F5/F11；來源＝PR #66 Claude issue comment `5369828302` ⚪2；取證日期＝2026-08-21】

- **`external-facts.md` B5 與 GFM tables extension 的跳脫例外互斥**：
  B5 逐字寫「code span 內不做任何 inline 解析，反斜線轉義也失效」並註「GFM 規範同文」，
  但 GFM 的 **tables extension** 對表格儲存格內的直線有明文例外（逐字＝
  "Include a pipe in a cell content by escaping it, including inside other inline spans"，
  <https://github.github.com/gfm/>，取證 2026-08-21）⇒ 照 B5 現行文字辦事的人會結論
  「code span 裡跳脫無效」，而 `CLAUDE.md` 鐵律 20.2.7 恰恰要求跳脫。該檔不在本 PR 累積 diff
  內，依 17.2 只登記；日後動 B5 時補一句 tables-extension 例外並與 20.2.7 互相交叉引用
  【F7/F11；來源＝PR #66 Claude issue comment `5371106688` ⚪1；取證日期＝2026-08-21】

- **射程外另有四檔帶同型未跳脫表格直線**：
  `docs/specs/52-p0-logic-fixes.md`（兩處，含 code span 內的 `ORDER ||--o{ RETURN`，表頭 2 欄
  被切成 4 格、超額兩格遭 GFM 丟棄，渲染出的第二欄在 `ORDER ` 處截斷，其後結論整段消失）、
  `docs/specs/83-admin-1to1-audit-round3.md`、`docs/specs/53-ui-gap-recheck.md`、
  `docs/worklog/2026-08-18-P8-自動化基建.md`。四檔均不在本 PR 累積 diff 內，依 17.2 只登記。
  🔴 **機械化候選＝§2 的 G-04**（不限改動檔的全樹檢查；代價與待裁狀態見該列）
  【F7/F11；來源＝PR #66 Claude issue comment `5371707612` ⚪1；取證日期＝2026-08-21】

- **ledger registry 未涵蓋全部曾受驗的 head**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的受驗 head registry 本輪已改為逐筆附理由、
  且不再依賴分支祖先鏈（squash 後仍可重跑）；但 `ac27d90`／`c114ffe` 這兩個 PR 早輪確實受過驗
  的 head（判詞 `5365173662`／`5365460704`，worklog 尚為 `c114ffe` 留有敘事節）**仍不在
  registry**，檔內也沒有明文寫「ledger 自 `8b2d39d` 起算」。ledger 起點屬本 PR 自訂邊界、
  不反轉現值；依 17.2 只登記，日後若要把起點正式化，須在同一處寫明起算 head 與理由
  【F5/F11；來源＝PR #66 Claude issue comment `5372100557` ⚪1；取證日期＝2026-08-21】

- **`m0-review-convergence.md` 早期節與 D38 過渡期字面相反**：
  該檔 2026-08-20 的 D31／D32 終態補充以現在式寫「`AUTO_MERGE=false` 不得再被解讀成所有 PR
  都必須由使用者逐次操作」，而 D38 過渡期正是「全部 PR 由使用者人工合併」。該節本輪未被改動，
  且檔頭已標「早期機制編號保留作沿革」，故不反轉現值；依 17.2 只登記，日後整理該檔沿革層時
  以日期化更正處理
  【F2/F11；來源＝PR #66 Claude issue comment `5372100557` ⚪2；取證日期＝2026-08-21】

- **worklog 歷史層仍描述已被取代的 ledger 機制**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的 `7146270` 回應輪輸出節寫「期望集合已改為外部
  導出：由 `git log --format=%H <base>..HEAD`⋯」，該敘述**對它那一輪為真**；`ee6e7ec` 輪已改為
  不可變 registry ＋ ancestry 交叉檢查。歷史層依 AGENTS §1 不回改，但後人循該段找現行機制會
  找錯位置。日後整理沿革層時就地加日期化指路註即可，不反轉現值
  【F2/F11；來源＝PR #66 Claude issue comment `5372536493` ⚪1；取證日期＝2026-08-21】

- **`$ledgerBase` 硬編 `0fbe520` ⇒ rebase 後 ancestry 會假紅**：
  同檔 tuple block 的 `$ledgerBase` 是固定 SHA；分支若 rebase 到較新的 main，
  `0fbe520..HEAD` 會納入新 main 的 commit，這些 commit 都不在受驗 head registry 內 ⇒
  ancestry 迴圈報 `reviewed branch head missing from ledger registry`。方向保守
  （**假紅、不是 fail-open**），且舊版同樣要求每個 branch head 有 section、非本輪引入，
  故依 17.2 只登記不修。🔴 **修法方向＝未取得**：`git merge-base origin/main HEAD` 曾被寫成
  「正解」，2026-08-22 查證後撤回——rebase 會**同時改寫 branch commit 的 SHA**，而 registry 存的
  是 rebase 前的 SHA，換成 merge-base 之後守衛仍會 throw 同一句；淺 clone 下該命令無輸出。
  缺的證據＝`git merge-base` 在「rebase 後 SHA 改寫」與「`--depth` 淺 clone」兩情境下的行為、
  以及 registry 該如何重錄；取得方法＝git-scm 官方文檔 ＋ 臨時倉庫實跑該兩情境。
  依 AGENTS §8.2 第 2 條，取證前不得作為實作輸入
  【F5/F11；來源＝PR #66 Claude issue comment `5372536493` ⚪2 ＋ Codex inline `3832262558`；
  取證日期＝2026-08-21／2026-08-22】

- **`Assert-DeferredWhite` 以 `,@($deferred)` 收尾，與同 commit 新立的反巢狀規則互斥**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的 `Get-LedgerTupleSet` 註釋逐字要求「不用
  `,$set` 包裝：PS 5.1 下它會產生巢狀陣列，呼叫端 `@()` 收到的是一個元素」，而同檔相隔約
  160 行的 `Assert-DeferredWhite` 仍用 `,@(...)`。PS 5.1 實跑複驗（2026-08-22）：呼叫端的
  `@()` **一律收到 Count=1 的巢狀陣列**（函式回 0／1／2 個 pair 皆然）⇒ 正向 fixture 的
  `$positivePairs.Count -ne 1` 這半條守衛**恆為假**（`1 -ne 1`）⇒ **從不觸發**、
  `$positivePairs[0] -ne $deferredSample` 退化成陣列過濾比較（相等回空陣列 falsy、
  不等回一元素 truthy）。⚠️ **內層為空時兩半都為假 ⇒ 該情境從這道 `if` 逃掉**，由函式內的
  集合相等守衛接住。方向仍 fail-closed，
  <!-- 🔴 2026-08-22 極性更正（來源＝Codex inline `3832688949`）：本條原寫
       「`$positivePairs.Count -ne 1` **恆為真**而失效」。**逐字撤回**：巢狀陣列使 `.Count`
       恆等於 1，因此該表達式**恆為假**、守衛從不觸發——與「恆為真」方向相反。
       極性寫反會讓日後照本條寫回歸測試的人斷在相反的條件上。 -->
  但🔴 **承重的是函式內的集合相等守衛，不是這一行**（內層為空時該行條件實測為 False）；
  生產側 `$deferred` 賦值後全檔未再使用 ⇒ 無後果。依 17.2 只登記不修；日後統一寫法時
  **兩支要一起改**，並把數量判準改成對內層集合斷言
  【F5/F11；來源＝PR #66 Claude issue comment `5373193694` ⚪1；PS 5.1 實跑複驗＝2026-08-22】

- **`Invoke-AncestryGuard` 的兩格邊界（登記觀察與其處置的因果，不是待辦）**：
  Claude 指出①`$Registry` 整組為空時走降級 return、承重方向靜默消失（下游以
  `frozen ledger marker does not correspond to any known head` 接住 ⇒ 整體仍 fail-closed，
  但紅燈與 ancestry 無關）；②git 退出 0 而輸出為空時，訊息誤寫成 `non-squash reason: git exit=0`。
  🔴 **②的射程比判詞寫的大**：實跑複驗（2026-08-22）顯示只要**HEAD 是 `$Base` 的祖先或與之
  相等**即為此形態（`HEAD..HEAD` 與 `1e8e12a..5fc4355` 皆 exit 0／0 行）——而那正是 squash
  合併後把 base 更新到新 main 的情形，**等於降級分支要服務的場景反被判成「非 squash 原因」**；
  連帶當時的 tool-failure 突變以該句字串為判準，而 exit=0 與 exit=128 共用同一句 ⇒ 證不出
  紅燈來自工具失敗。⚠️ **這三點已被同輪重構一併改掉**（該重構由 Codex inline `3832262543`
  的 P1 強制，非本條所致）：空 registry 由 `ledger ancestry registry is empty` 明確 throw 且有
  具名突變；空輸出改由 `Get-BranchHeads` 以 `ledger ancestry git log returned no commit` 歸因，
  與 `ledger ancestry git log failed: exit=<n>` **訊息分離**，兩者各有具名突變
  （`failed` 餵不存在的 object 作 base、`returned no commit` 餵 `HEAD` 作 base）
  <!-- 🔴 2026-08-22 補正（來源＝Claude issue comment `5373872716` 🔴-2）：本句在寫下的當時
       **只有 `failed` 有突變**，`returned no commit` 零覆蓋——宣稱先於實物。同輪已補上
       `git-empty-range` 具名突變（`Get-BranchHeads 'HEAD'` ⇒ git 退出 0、輸出 0 行），
       本句自該 commit 起才成立。留註是因為它一度是假宣稱，不是因為現在還假。 -->
  【F5/F11；來源＝PR #66 Claude issue comment `5373193694` ⚪2；PS 5.1 實跑複驗＝2026-08-22】

- **`white ledger mismatch` 這條具名 throw 不可達**（本輪自查發現，非驗收方點名）：
  同檔 `Assert-DeferredWhite` 內，具名 `throw` 的前一行是
  `$delta | Format-Table -AutoSize | Out-String | Write-Error`；在 `$ErrorActionPreference =
  'Stop'` 下 `Write-Error` **先成為終止錯誤**，於是實際紅燈訊息是 delta 表格、具名訊息永遠不會
  出現。方向仍 fail-closed（照樣中止），與同檔已登記的 git stderr 事故同一形態。
  依 17.2 與「只修被點名的問題」，本輪只登記不修
  【F5/F11；來源＝PR #66 第 18 輪自查（`1e8e12a` 回應輪）；取證日期＝2026-08-22】

- **`PR body ledger mismatch` 未被任何突變驅動**（本輪自查發現，非驗收方點名）：
  同檔的 body tuple 突變（把某 head 換成 40 個 0）自行 inline 做 `Compare-Object`，
  **完全沒有呼叫 `Assert-FrozenLedgerCoverage`** ⇒ `BODY_LEDGER_MUTATION_RED=1` 證明的是
  inline 比較、不是生產函式的那條 throw。方向仍 fail-closed，本輪只登記不修；
  日後修法＝把該突變改走生產函式（同本輪對 `Get-LedgerTupleSet` 的處置）
  【F5/F11；來源＝PR #66 第 18 輪自查（`1e8e12a` 回應輪）；取證日期＝2026-08-22】

- **worklog 兩處節指標指錯**：`docs/worklog/2026-08-21-驗收收斂制度V2.md` 的兩則歷史層更正註
  分別寫「完整 11 條見『本輪（`1e8e12a` 回應）』節」與「見**下一節**『乙堆清單（以 comment id
  為鍵）』」，而該節實際位於「本輪（`ee6e7ec` 回應）驗證輸出」之前、也不在「本輪（`1e8e12a`
  回應）驗證輸出」內；後者的下一節其實是 20.4 復發紀錄。兩處都在歷史層更正註內、Pending 的
  權威指標正確 ⇒ 不反轉結論，依 17.2 只登記
  【F2/F11；來源＝PR #66 Claude issue comment `5373872716` ⚪1；取證日期＝2026-08-22】

- **本檔「相隔約 160 行」與實物不符**：本節 `Assert-DeferredWhite` 條目寫「同檔相隔約 160 行的
  `Assert-DeferredWhite`」，而受驗 head 上兩者實距 194–222 行。與同輪 🔴-1 同族（數字取自較早的
  樹狀態），但為 hedge 過的近似值、不反轉結論，依 17.2 只登記
  【F5/F11；來源＝PR #66 Claude issue comment `5373872716` ⚪2；取證日期＝2026-08-22】

- **worklog 把「本輪三條 🔴」寫進了上一輪的 20.4 復發紀錄節**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的「同根復發紀錄（`1e8e12a`）」節末，被追加了一句
  以「本輪三條 🔴 全是同一形態」起頭的敘述，而那三條 🔴 屬下一輪的判詞、該節自己的復發錨只有
  兩條。20.4 的四項義務已由後來新立的「同根復發紀錄（`6e2d2d8`）」節逐條履行 ⇒ 僅為節內
  「本輪」指涉錯位，屬歷史層敘事，依 17.2 只登記
  【F2/F11；來源＝PR #66 Claude issue comment `5374243076` ⚪1；取證日期＝2026-08-22】

- **乙堆節的標題與首句仍寫「以 comment id 為鍵」，實物已非如此**：該節標題與首句保留
  「以 comment id 為鍵／不是落點」的措辭，而鍵已先後改為三段合成、再改為整列語義正規化。
  標題字面被 tuple block 的 `$worklogBacklogPattern` 當**節界錨**使用 ⇒ 改標題必須同批改 regex
  與對應的突變，不是順手能改的；且首句論旨（不是落點）仍成立、同段下一句立即給出精確定義。
  依 17.2 只登記；日後若要改，標題與 regex 與突變三者須同批
  【F5/F11；來源＝PR #66 Claude issue comment `5374243076` ⚪2；取證日期＝2026-08-22】

- **worklog 歷史層更正註的「現行」子句已過期**：`docs/worklog/2026-08-21-驗收收斂制度V2.md`
  的 `1e8e12a` 回應輪輸出節內，有一則更正註寫「鍵已改為三段合成並涵蓋全部 11 列，**現行**輸出
  為 `DEFERRED_BACKLOG_PARITY=11`」。輸出值 11 在 HEAD 仍成立，但「三段合成」已被後續輪次改成
  整列語義正規化。該註屬歷史層、doc-claims 綠 ⇒ 不反轉結論，依 17.2 只登記；教訓是**更正註裡
  不要寫「現行」**，它會隨下一次修法過期
  【F2/F11；來源＝PR #66 Claude issue comment `5374657885` ⚪1；取證日期＝2026-08-22】

- **逐節 marker 守衛的射程只涵蓋 `### exact-head` 節**：受驗樹上 `FROZEN_LEDGER_HEAD` marker
  比 `### exact-head` 標題多一個，多出來的是 legacy 的 `8b2d39d`，它掛在
  `### 終態整合修正（⋯）` 節下。把它剪到檔尾散文，逐節迴圈不會看它、全域 marker 集合與 tuple
  三向計數也全不變 ⇒ 整個 block 仍 exit 0。⚠️ **同輪已把該 head 收進 `$sectionlessHeads`
  具名例外**（節集合 vs registry 的比對因此仍成立），但「該 marker 本身沒有節可綁」這一格
  依舊存在 ⇒ 依 17.2 只登記；日後若要斷根，正解是把 legacy 節改寫成 `### exact-head` 形式
  【F5/F11；來源＝PR #66 Claude issue comment `5374657885` ⚪2；取證日期＝2026-08-22】

- **§5 覆蓋帳的逐訊息分類未公布，第三方無法複驗「上列即完整清單」**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` §5 給出「判準型 N 條、覆蓋 M 條、未覆蓋清單」
  三個數，算術自洽，但「哪一條算判準型、哪一條算腳手架或 plumbing」的分類只在作者的分類器裡，
  未寫進檔案 ⇒ 第三方只能驗算術、不能驗分類。分類權在作者、doc-claims 綠 ⇒ 依 17.2 只登記；
  日後若要斷根，正解是把逐訊息分類表一併公布
  【F5/F11；來源＝PR #66 Claude issue comment `5375115145` ⚪1；取證日期＝2026-08-22】

- **backlog 切格對「超額格」的方向**：`Get-DeferredBacklogKeys` 原以 `-lt 4` 檢查格數，
  >4 格的列（某欄有未跳脫直線）會被放過。⚠️ **同輪已依 Codex inline `3833377543` 改為 `-ne 4`
  並補具名突變**；此條登記是為了留下「三種偏移方向逐一推過皆 fail-closed」這個判斷的因果，
  不是待辦
  【F5/F11；來源＝PR #66 Claude issue comment `5375115145` ⚪2；取證日期＝2026-08-22】

- **反向式的射程只認一種措辭**：`docs/worklog/2026-08-21-驗收收斂制度V2.md` 的全稱句分類
  反向式掃 `每(個|一)…都必須`，而同一件事在本檔另有一處寫成「每個命中都**要**能」⇒ 不在射程內。
  同族問題已在更早一輪把量詞射程放寬過一次（`共 **N 條**` → 含「N 道／N 者／N 處」等），
  這次是**動詞**那一維。方向保守（漏掃不是誤判），依 17.2 只登記；日後若要斷根，正解是把
  「必須／要／應」一併納入射程
  【F5/F11；來源＝PR #66 Claude issue comment `5375536028` ⚪2；取證日期＝2026-08-22】

- **以 🔴 抬頭宣告的守衛行為一度沒有對應突變**：同檔曾以「🔴 **例外清單被擴充也必須轉紅**」
  抬頭，底下卻只跟著一道測別件事的突變；`$SectionlessHeads` 升成參數正是為了讓這種突變可注入，
  當時七個呼叫點卻無一傳它 ⇒ **注入點是死的**。⚠️ 該宣稱的**行為**在當時為真（逐格推過），
  同輪已補三道具名突變把注入點用起來；此條登記是為了留下「以 🔴 抬頭宣告 ≠ 有斷言在守」
  這個教訓，不是待辦
  【F5/F11；來源＝PR #66 Claude issue comment `5375536028` ⚪1；取證日期＝2026-08-22】

- **`91` §3 的條目體例不一致：解決註有無不統一**：本節多數條目在同輪被解決時會帶
  「⚠️ **同輪已⋯**；此條登記是為了留下教訓，不是待辦」，而「§5 逐訊息分類未公布」那一條沒有
  ——同一個 PR 的下一輪就公布了 §5.1／§5.2，只讀 `91` 的人會以為它仍未解。屬登記簿體例與
  歷史層敘事 ⇒ 依 17.2 只登記；日後整理時統一補上解決註即可
  【F2/F11；來源＝PR #66 Claude issue comment `5375774655` ⚪1；取證日期＝2026-08-22】

- **凍結 ledger 節用本檔行號錨 Codex inline，行號會腐化**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的 `2d86082` ledger 節以「本檔 `:1035`／`:1304`」
  記錄兩則 Codex inline 的落點，而那兩個行號在同輪編輯後即已位移。屬凍結 ledger 的歷史層快照
  ⇒ 不回改；但與同檔 §5 自己立的「公布的錨一律是訊息、不是行號」互為對照。依 17.2 只登記；
  日後斷根的正解是 ledger 節也改用訊息／內容錨
  【F5/F11；來源＝PR #66 Claude issue comment `5375774655` ⚪2；取證日期＝2026-08-22】

- **本節「分類未寫進檔案」那一條，其條目本體已成為現在式假句**：該條逐字寫「分類**只在作者的
  分類器裡，未寫進檔案**⋯正解是把逐訊息分類表一併公布」，而分類器與逐訊息表在同一個 PR 的
  後續輪次都已進檔。⚠️ 更早一輪已就「缺解決註」登記過一條，但那條記的是**體例**，
  這裡的實況已升級為**條目自述與 HEAD 相反**。歷史層不回改 ⇒ 依 17.2 只登記；
  日後整理本節時，這兩條應合併處理
  【F2/F11；來源＝PR #66 Claude issue comment `5376115643` ⚪1；取證日期＝2026-08-22】

- **`Assert-ClassTableBijection` 掃的是整份 worklog，不是 §5.2 那一節**：它靠列的**形狀**
  （`| <數字> | \`訊息\` | ✅或❌ |`）「剛好只命中」§5.2，實測全檔命中數＝表列數，今天正確；
  但日後任何同形狀的表都會被靜默併入這次雙射，而錯誤會表現成「雙射不成立」這種難歸因的紅燈。
  正解是先用節錨（`#### §5.2` 起、下一個 `####` 止）切出範圍再比對。方向保守（會紅不會綠）
  ⇒ 依 17.2 只登記不修
  【F5/F11；來源＝PR #66 Claude issue comment `5376115643` ⚪2；取證日期＝2026-08-22】

- **覆蓋數（✅／❌）沒有被釘死，而「本表不另寫成散文」這條自訂規則被同一份檔案破壞**：
  §5.2 表頭逐字寫「本表的列數與 ✅／❌ 欄**不另寫成散文**」，而 §5.1 上方那句
  「判準型 throw 共 N 條不同訊息，其中 M 條有 committed 具名突變」**覆述的正是那兩個數**。
  🔴 **本條刻意不抄 N 與 M 的當時值**（2026-08-22 改寫；來源＝Claude issue comment
  `5376772877` 🟡-1 ＋ Codex inline `3834527592`）：初版逐字抄了「35／22」，而**同一個
  commit** 已把該句改成別的數 ⇒ 條目一落地就指向一個不存在的句子，讀者去核對只會看到對不上
  的數字，無從判斷坑還在不在。**登記一個「數字沒被釘死」的坑時抄下那個數字，本身就是同一個
  病**。以識別字定位：`worklog` 內以「兩個 powershell block 內判準型 throw 共」起頭的那一句。
  坑的實體＝分類器內的 `$expectedClassCounts` 只釘 `judgment`／`scaffold`／`plumbing`
  **三個**，沒有釘 covered／uncovered ⇒ 覆蓋集合日後變動時，✅ 欄與 §5.2b 快照兩處同改即綠，
  而散文那個 M **沒有任何機械力量強制它重算**（實況：坑仍在，2026-08-22 複驗）。
  ⚠️ 該散文帶實數日期戳，合 AGENTS §2 形式③（快照式陳述）⇒ 依 17.2 只登記不開 🟡。
  正解是把 covered／uncovered 一併釘進 `$expectedClassCounts`，或讓散文改為指向表而不覆述數字
  【F2/F11；來源＝PR #66 Claude issue comment `5376390266` ⚪1；取證日期＝2026-08-22】

- **§5.1 第四類的定義涵蓋不到第三個 block 內的腳手架型 throw**：第四類被定義為「量測工具
  本身的**自檢** throw」，但第三個 block 內有六條是 `mutation stayed green`／
  `mutation went red for the wrong reason`／`fixture not found` 這種**腳手架**訊息，
  按第二類自己的定義那就是腳手架。目前「互斥且窮盡」靠的是分類射程句（前兩個 block vs
  第三個 block）維持，**不是靠類別定義本身**——也就是說，同一條訊息落在哪一類取決於它在
  哪個 block，而不是它是什麼。方向保守（不影響任何斷言的紅綠，只影響分類敘述的自洽）
  ⇒ 依 17.2 只登記。正解是把射程寫進類別定義，或改以訊息語義分類、不看 block
  【F5/F11；來源＝PR #66 Claude issue comment `5376390266` ⚪2；取證日期＝2026-08-22】

- **§5.2b 快照的謂詞與 ✅ 欄的定義不是同一件事**：§5.2 表頭逐字把 ✅ 定義為
  「**有 committed 具名突變**」，§5.2b 則逐字說它取的是「**執行到的** throw 行⋯再取其中的
  判準型」。`Assert-ClassTableBijection` 實際驗的是「✅ 欄 ≡ 快照」，也就是**被執行到**，
  不是**有具名突變**。今天兩者重合（每一條 ✅ 都找得到對應的 `Assert-MutationRed` Label 或
  `*_RED` 標記），但機制不保證它們繼續重合——只要有人加一條「會被執行到、卻沒有具名突變」的
  判準型 throw（例如被別的守衛順帶觸發），✅ 欄仍會被要求標 ✅，而那一欄的字面承諾就不成立了。
  方向保守（不影響現有紅綠）⇒ 依 17.2 只登記。正解是把 ✅ 的定義改成「被執行到」（與量測
  一致），或另立一欄分開記「有具名突變」與「被執行到」
  【F2/F11；來源＝PR #66 Claude issue comment `5376772877` ⚪1；取證日期＝2026-08-22】

- **`Assert-NoLedgerProse` 的真實值共現判準是逐行的**：它 `-split` 成行後逐行檢查
  「真實 head 前綴」與「真實 run id」是否同時出現，因此把兩者分寫成**相鄰兩行**即可繞過。
  ⚠️ 舊版是單行 regex，同樣只看一行 ⇒ 本輪改動**沒有讓射程退步**，這不是本輪造成的缺口。
  ⇒ 依 17.2 只登記。正解是先把散文正規化成單一空白分隔的字串再比對，或改以段落為單位
  【F5/F11；來源＝PR #66 Claude issue comment `5376772877` ⚪2；取證日期＝2026-08-22】

- **同一份檔案裡「執行到的 throw」有兩個互斥的實測值，兩處都標同一天、都說「最終樹」**：
  `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的 `### 鐵律 20.4 同根復發紀錄（ee6e7ec）`
  段內逐字寫「於**最終樹**實測：**28 條 throw 被執行**，其中判準型 **22** 條」，而 §5.2b 的
  重取註與其後的執行輸出寫的是**另一組數**。同段的歷輪序列也停在舊值。
  🔴 **本條目刻意不抄下任一組數字**（2026-08-22 改寫；來源＝Codex inline `3834802025`）：
  初版把受驗 head 上的三個實測值抄進括號裡，而它們**在同一輪的最終樹上就已經不是那個值**
  ——於是這個「登記數字會腐」的條目，自己變成了第三份會腐的敘述。
  取現值的方法：抽 worklog 的 §5.3 圍欄跑一次，讀 `THROW_CLASS_TABLE_COVERED`；
  §5.2b 圍欄的行數與 §5.2 表的 ✅ 手數應與它相等。
  ⚠️ 兩個數各自在**它被寫下的那一輪**都是真的——集合後來被擴充了；問題在於**兩處都自稱
  「最終樹」**，讀者無法從文字判斷哪一個對應現在的 HEAD。該段落落在歷史層、帶日期戳、
  合 AGENTS §2 形式③，doc-claims 亦綠 ⇒ 依 17.2 只登記。正解＝在原處加一則更正註指向
  §5.2b 現值（**歷史層不回改原文**），並把歷輪序列補到現值
  【F2/F11；來源＝PR #66 Claude issue comment `5377113489` ⚪1；取證日期＝2026-08-22】

- **檔案數守衛的「錨點」仍是封閉列舉，而錨點與量詞一樣是開放類**：`$anchorPattern` 只列
  六種拼法（`final[\s\-_]*commit`／`最終 commit`／`終態 commit`／`末次提交|commit`／
  `最後一個 commit`／`HEAD commit`）。本 PR 描述自己就用了不在清單內的「**本 commit** 實際
  修改的 Markdown⋯」——該邏輯單位同時具備「數量」與「Markdown」兩個原子，只差錨點沒命中。
  九式（現十式）突變裡「錨點拼法」那一軸只測了 `final-commit`，仍落在同一個 regex 分支內。
  ⚠️ **這不是純缺陷而是取捨**：把「本 commit」加進錨點會**當場誤殺**上面那句合法散文，
  而本式自陳「刻意放寬到 fail-closed，寧可誤殺一句合法散文」——兩個方向不能同時要。
  同類的另一個缺口（「引言段＋緊接的 list item」不會被併）與根治方向（改為由機器行宣告
  檔案數並對 `git diff --name-only` 核對）已在 worklog 的 Pending 登記；本條是同一取捨的
  第二個面向，方向未退步 ⇒ 依 17.2 只登記
  【F5/F11；來源＝PR #66 Claude issue comment `5377113489` ⚪2；取證日期＝2026-08-22】

- **上一條 ⚪ 登記自己也犯了它登記的病，括號裡的三個數是受驗 head 的值**：該條目以現在式
  「實得」寫下三個覆蓋數，只帶與 HEAD 同一天的取證日期，僅靠【】裡的 comment id 間接錨住
  觀察 head ⇒ 讀者無法判斷那三個數對應哪一棵樹。⚠️ 本輪已依 Codex inline `3834802025`
  就地改寫（改為指出取現值的方法，不抄數字）；本條仍依 17.2 登記，**不因同批修掉就略過**
  ——登記的是「這個形態第三次出現」這件事
  【F2/F11；來源＝PR #66 Claude issue comment `5377352035` ⚪1；取證日期＝2026-08-22】

- **同一個 commit 對同一個總數採了相反策略**：worklog 的執行輸出段逐字寫「**本節刻意不寫
  『執行到的 throw 共 N 條』這種會被自己的敘述改動的總數**」，而數十行後的 Pending 段
  **寫出了那個總數**，同位置也沒有可重跑指令。⚠️ 該數與檔內不變式自洽（判準型數 ＋ 既有
  非判準型數），所以不是錯數字，是**沒有守衛的數字**——下一輪多一條 throw 被執行到就靜默過期。
  屬 worklog 敘事段、doc-claims 綠 ⇒ 依 17.2 只登記。正解＝Pending 該處改為指向 §5.2b／§5.3，
  或附可重跑指令
  【F2/F11；來源＝PR #66 Claude issue comment `5377352035` ⚪2；取證日期＝2026-08-22】

- **三道 parity 突變裡只有一道沒有「fixture 是否真的套用」前置斷言**：另外兩道各有
  `... fixture not found`，同節新增的幾道也各有 `... fixture did not apply`，唯獨
  `deferred-backlog-id-changed` 直接在 scriptblock 內做 `-replace` 而沒先斷言 `$mutant` 真的變了。
  ⚠️ 方向仍 fail-closed（不套用 ⇒ parity 相等 ⇒ 照樣紅在 `... mutation stayed green`），
  問題只在紅燈訊息指錯項、歸因成本較高。⚠️ 本輪該突變因凍結映射而被改注入落點欄，
  順手帶上了前置斷言；本條仍依 17.2 登記，記的是「這道體例當時缺了一處」
  【F5/F11；來源＝PR #66 Claude issue comment `5377352035` ⚪3；取證日期＝2026-08-22】

- **§5.2 覆蓋表把 `frozen ledger tuple set mismatch` 標成 ❌，而它正是擋下「PR 描述與受驗樹
  失衡」的那一道**：還原到 `02cbd9b` 的當下，PR 描述仍停在被撤回那一輪的機器行，正是這一道
  轉紅把它擋住。⚠️ 方向沒有退步（它確實會紅，本檔也記著它的優先順序），只是「它承重」
  目前**沒有 committed 的具名突變**去證明。非本輪改動 ⇒ 依 17.2 只登記。
  正解＝為它補一道具名突變（注入一條假 tuple 到 body 側）
  【F5/F11；來源＝PR #66 Claude issue comment `5377927841` ⚪1；取證日期＝2026-08-22】

- **三個 powershell block 沒有一處寫明「只能在候選分支樹上跑」**：`Get-BranchHeads` 用
  `git log <base>..HEAD`；在 `pull/<n>/merge` 這種 checkout 上 HEAD 是 merge commit ⇒
  tip 被 `Select-Object -Skip 1` 跳過之後，真正的候選 head 變成非 tip、而它不在 registry
  ⇒ 必然紅在 `reviewed branch head missing from ledger registry`。⚠️ **這不是缺陷**——
  這三個 block 本來就是作者本機的 pre-push 閘門；問題是**這個前提沒有寫下來**，
  換人接手照著跑會拿到一個看起來像事故的紅燈。⇒ 依 17.2 只登記。
  正解＝在三個 block 的檔頭各寫一句執行前提
  【F5/F11；來源＝PR #66 Claude issue comment `5377927841` ⚪2；取證日期＝2026-08-22】

- **`Get-DeferredBacklogKeys` 前的註釋仍描述被同批取代的「全域 id 集合」設計**：
  該段逐字仍寫「已知集合就地凍結在下面的預設參數裡」「集合裡的每一個 id 都必須至少被一列
  用到」，而 HEAD 凍的是**序號 → 來源整格**的映射、死條目自檢比的也是**序號**。
  ⚠️ 那一段下方另有日期化的更正段逐段給出現值，讀到底的人拿得到正確狀態 ⇒ 依 17.2 只登記。
  🔴 **本條不寫「有幾處」**（2026-08-22；來源＝Codex inline `3835455708`）：初版寫「兩處」，
  那是一個**手維護的計數**——任一句被增刪，這個數就與實物脫節，而條目本身不會有人重看。
  複驗指令（逐處自己數）：
  `grep -n '已知集合就地凍結\|集合裡的每一個 id' <worklog>`
  <!-- 🔴 2026-08-22 更正（來源＝Claude issue comment `5379100617` 🔴-2 ＋ Codex inline `3835546431`）：
       原指令是
         awk '/^# 🔴 清單\*\*只此一份\*\*/,/^function Get-DeferredBacklogKeys\(/' <worklog> | grep -n '已知集合\|每一個 id'
       它**恆為零輸出**：起點 pattern 落在要找的那兩句**之後**，範圍因此永遠不含它們。
       照著跑的人拿到空輸出，會讀成「那兩句已改掉、可結案」。
       🔴 **座標一律帶 ref，並用該 ref 重新導出**（不得取自工作樹）——導出指令：
         git show <ref>:docs/worklog/2026-08-21-驗收收斂制度V2.md \
           | grep -n -e '^# 🔴 清單\*\*只此一份\*\*' -e '^function Get-DeferredBacklogKeys(' \
                     -e '已知集合就地凍結' -e '集合裡的每一個 id'
       實得（本輪逐 ref 實跑）：
         ref=`5254cc4`（受驗樹）：兩句 `:1961`／`:1963`；起點 `:1965`；終點 `:1988`（共 4 行）
         ref=`bb4da97`（上一輪終態樹）：兩句 `:2028`／`:2030`；起點 `:2032`；終點 `:2055`
           ⚠️ 該 ref 上此式**共輸出 5 行**，第五處 `:4448` 是 worklog 逐字引用本 pattern 的
           **自指命中**，不是目標句 ⇒ 本條只列具名座標、**不列總命中數**。
       兩棵樹上「起點行號 > 兩句行號」都成立 ⇒ 恆零輸出的結論與 ref 無關。
       🔴 **這比原本的「兩處」更差**：換掉一個會腐的數字，換來一個**永遠報乾淨**的指令，
       正是本 PR 反覆在修的 fail-open 同型。
       新指令改釘**那兩句自己的完整措辭**，不依賴任何行號或區塊邊界。本輪實跑三項：
         ①**目標兩句都被命中**（在受驗樹 `5254cc4` 上是 `:1961`／`:1963`，行號隨後續編輯漂移，
           故此處只記「兩句都在」而不記終態樹的行號或總命中數）；
         ②**突變**（把兩句依「正解」改寫）後**歸零** ⇒ 修好時它會轉綠，不是恆綠；
         ③對另外兩處措辭不同的「已知集合」（`已凍結的已知集合`／`來源 id 改對已知集合`）
           **零誤抓** ⇒ 射程不外溢。
       ⚠️ **判讀時要排除自指命中**：worklog 的 20.4 紀錄裡逐字引用了這條 pattern，
       它自己也會被命中——這與本 PR 先前那次「六處命中其中三處是紀錄自己」同型，
       所以本條**不發布總命中數**，只發布上面三個可判別的性質。 -->
  <!-- 🔴 2026-08-22 更正之二（來源＝Claude issue comment `5379667404` 🔴-1）：
       上一則註曾寫「起點命中 `:1984`、終點 `:2007`，兩句在 `:1980`／`:1982`」——
       **這四個數在任何一棵樹上都不成立**（比 `5254cc4` 一律大 19、比 `bb4da97` 小 48，
       而 `5254cc4..bb4da97` 只有一個 commit，沒有第三棵樹可對得上），
       且與上一則註自己列的「受驗樹 `5254cc4` 上是 `:1961`／`:1963`」**直接互斥**。
       🔴 成因＝**我在編輯到一半的工作樹上量，發布成關於受驗樹的事實**。
       這與同輪 doc-claims「commit 前跑、發布成 post-commit」是同一個根因的兩種外觀：
       **量了 X，當成關於 Y 的事實發布**。⇒ 座標一律帶 ref 並用 `git show <ref>:` 導出。 -->
  <!-- 🔴 2026-08-22 更正之三（來源＝Claude issue comment `5379835974` 🔴-1）：
       上一則「更正之二」原本是**巢狀**寫在上一則註解裡面。**HTML 註解不巢狀**——外層 block
       在**第一個含結束序列**的行就結束，於是它後面 11 行內部工作註**渲染成可見正文**
       （GitHub blob 實測，ref `074b399`：「判讀時要排除自指命中」「所以本條⋯」「這比原本的⋯」
       三處皆可見）。⇒ 本輪把三則改成**兄弟註解**（各自獨立開閉），不再巢狀。
       🔴 **本註自己也差點再犯一次**：初稿在這段裡寫了結束序列的**字面**，於是本註在那一行
       就提前結束、後面兩行外洩。⇒ 註解內文**不得出現註解結束序列的字面**；要談它就用文字描述。
       🔴 複驗方式必須是**實際渲染**、不是結構斷言：把**整個 list item**（含 `- **` 標記）
       送 GitHub `/markdown`，確認註解內文不出現在輸出。只截中段會改變縮排上下文、驗不準。 -->
  🔴 **這是同一族的又一次**：判準改了、緊鄰的契約註釋沒跟上。正解＝把那些句子就地改寫成
  「凍結的是序號 → 來源整格」與「映射裡每一個**序號**都必須至少被一列用到」
  【F5/F11；來源＝PR #66 Claude issue comment `5378137169` ⚪1；取證日期＝2026-08-22】

- **「丙」表是清法② 裁定的唯一憑證，卻只存在於 PR 描述、無倉庫副本、無 parity 守衛**：
  <!-- 🔴 2026-08-22 更正（來源＝Claude issue comment `5379100617` 🔴-3② ＋ Codex inline `3835546438`）：
       本條原寫「**兩條** 🟡 清法②」。**寫下它的同一個 commit（`5254cc4`）就把丙表加到三列**
       （丙-1／丙-2／丙-3），⇒ 條目在它誕生的那個 commit 上就已經過期。
       🔴 **更難看的是位置**：本檔**緊鄰上一條**（內容錨＝`grep -n '本條不寫「有幾處」' <本檔>`）
       才剛寫下「本條不寫『有幾處』⋯那是一個手維護的計數——任一句被增刪，這個數就與實物脫節」
       ——**下一條就寫了一個**。
       ⇒ 依同一條理由刪去基數，改指向表格本身（**表格即集合**，多一列少一列都不需要改本條）。 -->
  <!-- 🔴 2026-08-22 更正之二（來源＝Claude issue comment `5379667404` 🔴-1 同族②）：
       上一則註原寫「本檔 `:1203`（**本條上方八行**）」。`:1203` 當時正確，但**寫下它的那次編輯
       自己插入了 20 行**，於是「上方八行」在同一個 commit 上就變成 24 行。
       ⇒ 改用**內容錨**（一道 grep），距離不再是宣稱的一部分。
       🔴 本則原本是**巢狀**寫在上一則裡（同 `5379835974` 🔴-1 的機制），已改為兄弟註解。 -->
  對照組是乙堆——它之所以被做成「PR body ＋ worklog 兩個載體 ＋ 整列語義 parity ＋ 承重突變」，
  理由正是「**清法②的明文條目是承重的**」。丙表承擔同樣角色，卻放在**不需要新 head 就能編輯**
  的 PR body 裡，且零斷言。⚠️ 補它需要**新增判準**，而那正是使用者 2026-08-22 射程裁定要停止的
  行為 ⇒ 依 17.2 只登記。正解＝下一個本來就要改 tree 的 PR 把丙表併進乙堆的兩載體 parity，
  或明文記下「丙表刻意不設守衛」的理由與代價
  【F5/F11；來源＝PR #66 Claude issue comment `5378916603` ⚪1；取證日期＝2026-08-22】

- **「grep 完人眼逐處判斷」型的反向式沒有機械輸出，射程隨文件成長而失控**：PR #66 該輪新增的
  兩道反向式都是這個形態——①`grep -n 'deferred-backlog-id-changed' <worklog>`（判準＝凡描述
  「它注入哪一欄」的句子必須一致）；②`git grep -n '2026-08-2[0-9] 實數\|實測' -- <worklog>`
  （條文要求「逐處回答『這一行在哪一分層』」）。②在該樹命中 **46 行**，逐輪人工判 46 行
  不可持續，而且**判完不留任何可貼的輸出**——下一輪無從知道上一輪判過沒有、判成什麼。
  ⚠️ 兩道在該輪都成立（驗收方逐處複驗過），問題是**可持續性與可稽核性**，不是正確性；
  補它需要**新增判準**，正是使用者 2026-08-22 射程裁定要停止的行為 ⇒ 依 17.2 只登記。
  正解方向＝把「這一行在哪一分層」變成**可機讀的層標記**（例如每個歷史層區段開頭一個
  哨兵註釋），讓反向式輸出「哪些行落在哪一層」這種可貼的集合，而不是每輪重讀 46 行
  【F5/F11；來源＝PR #66 Claude issue comment `5379100617` ⚪1；取證日期＝2026-08-22】

- **「內容錨」會命中引用它的那一行本身，命中集合因此不等於落點集合**：本輪為了取代會腐爛的
  行號錨而引入兩個內容錨，兩者都有這個性質——
  以 `docs/DECISIONS.md` 的解凍條件錨為例，`grep -n` 的命中裡有兩處是**引用該錨的更正註**、
  不是落點；本檔上一條的內容錨同理，而**本條登記文字若把該錨字串再寫一次，就會再多一個命中**。
  ⚠️ 內容錨仍然比行號錨好（它隨內容搬家、不會因插入而腐爛），問題是
  **它的輸出需要人再判一次「哪些是落點、哪些是引用」**，與本檔已登記的「自指命中」同族。
  ⇒ 依 17.2 只登記。正解方向＝錨字串裡加一個**只在落點出現的判別詞**，讓 grep 的命中集合
  直接等於落點集合。
  🔴 **本條刻意不重複任何錨字串、也不發布命中行號或總數**（來源＝PR #66 Codex inline
  `3835999071`）：初稿把錨字串與「實得兩處」一起寫進來，**登記這件事本身就製造了第三個命中**，
  於是那個「兩處」在誕生的 commit 上即為假。這與本節已登記的「自指命中」同族的**第二次**
  ⇒ 固定作法：**描述性質、不複述被搜的字串、不發布計數**
  【F5/F11；來源＝PR #66 Claude issue comment `5379835974` ⚪1；取證日期＝2026-08-22】

- **驗證段自己沒有遵守它同段宣告的 ref 紀律**：PR #66 `53ce036a` 的執行輸出段一邊寫下
  「座標一律帶 ref 並用 `git show <ref>:` 導出」，一邊有兩處違反它——①一句「本輪某區段的
  `<pre>` 由 1 降為 0」**沒有檔名也沒有 ref**，而三十餘行後的渲染複驗表用的是另一棵樹的
  區段行號（兩者相差正好是該處之前插入的行數）⇒ 同段內兩棵樹的行號並置；
  ②同段腳本用 `perl … "$W"` 直接讀**工作區**而不是 `git show <ref>:`。
  ⚠️ 兩者都不影響該輪任何結論（驗收方已獨立複驗），屬**體例未貫徹**而非事實錯誤
  ⇒ 依 17.2 只登記。正解方向＝把 ref 紀律做成該段的固定欄位（每個座標一欄 ref），
  而不是靠寫的人記得
  【F5/F11；來源＝PR #66 Claude issue comment `5380427808` ⚪1；取證日期＝2026-08-22】

- **一次渲染觀察被歸因到 CommonMark 規範，而該落點在歷史層、未隨生產者同步降級**：
  PR #66 的 `074b399` exact-head 節（歷史層）逐字寫著「新加的兄弟註解縮排 8 空格，
  **被 CommonMark 當成縮排程式碼區塊**」——那是把**一次實測**寫成**規範層的通則**，
  屬外部語義斷言而無官方逐字（19.2）。後續輪次已在 20.4 那一處把同一件事降級成
  「只陳述實測到的兩個值、不外推成通則」，但**歷史層那個落點沒有同步**
  ⇒ 典型的「生產者已改、消費者未動」，只是消費者落在不可就地改的那一層。
  ⚠️ 非該輪改動、不影響任何結論 ⇒ 依 17.2 只登記。
  正解＝在該歷史落點**原處追加日期化更正註**指向已降級的版本（不得就地改），
  或在下一個本來就要動該節的工作包一併處理
  【F5/F11；來源＝PR #66 Claude issue comment `5380713614` ⚪1；取證日期＝2026-08-22】

### 3.6 PR #64 P-8 證據來源文件債收斂驗收（2026-08-21）

<!-- 🔴 2026-08-22 改編號（合併 PR #66 進 main 之後）：本節原本引用 `external-facts` 的
     `A9`／`A10`／`B9`／`B10`。PR #66 先行合併，其同號條目是**完全不同的內容**
     ⇒ PR #64 的四節已改編為 `A16`／`A17`／`B13`／`B14`（見該檔各節的原編號自註），
     本節 22 行引用同批改號。
     🔴 **必須改**：本節是後續工作會消費的待辦清單，不改就會去改到 PR #66 的條目。
     ⚠️ 歷史層 worklog 裡的舊編號引用**不就地改**，以 external-facts 各節的自註作為對照。 -->

- **GitHub Markdown 對相關 HTML comment 的可見性與清單分段：未取得**：
  倉庫內部只可確認 PR #64 的 P-8、首輪、第四輪與第五輪驗收 worklog 使用 `AGENTS.md` 規定的
  HTML comment 更正形態；現有來源僅是 PR review comment ID，沒有官方 URL＋英文逐字，也沒有
  保留對應 GitHub `/markdown` request／response artifact。因此本登記**不發布**「更正不可見」或
  「第 0 欄 comment 會切成多個 `<ul>`」的外部行為結論。取得方式＝保存 exact request body 與
  response HTML，並另取官方 Markdown／CommonMark 適用語義；兩者未齊前維持未取得。本 PR 只
  收窄證據強度，不改 `AGENTS.md` 或歷史 worklog。後續抽樣另命中
  `docs/worklog/2026-08-21-PR64第三輪雙驗收修復.md` 的肯定式歷史標題，以及本 PR 累積 diff
  之外 `docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md` 的同型句；兩者只登記候選，不以
  終態的「未取得」授權回寫歷史層
  【F3/F5/F11/F12；來源＝PR #64 Claude comments `5358544615` ⚪2、`5359209200` ⚪3／4、
  `5359558626` ⚪3、`5360596028` ⚪4、`5360974435` ⚪3；Codex inline `3825640340`／
  `3826028172`；
  Claude comment `5363200002` ⚪4；取證日期＝2026-08-21】

- **GitHub Markdown API 取證若把 `-f text=@path` 誤當讀檔，會得到 exit 0 的假零**：
  本輪初次命令使用 `gh api ... -f text=@docs/worklog/...md`，current response 逐字是
  `<p dir="auto">@docs/worklog/2026-08-21-PR64第十一輪雙驗收修復.md</p>`；它渲染的是字面路徑，
  因此 table／pre 全為 0 仍 exit 0。可重用的 `-f`／`-F @path` 旗標契約、官方來源與逐字集中於
  `docs/dev/external-facts.md` B13；本條只保存事故。改用 `-F text=@path` 後才取得實際文件 HTML。
  後續 Markdown 複驗須同時釘 request body 來源與至少一個承重 response
  canary（例如預期有表格的檔必須含 `<table role="table">`），不得只因 API exit 0 就發布零計數
  【F1/F3/F5/F11/F12；本輪自報，未被驗收點名，依 17.2 只登記；取證日期＝2026-08-21】

<!-- 🔴 2026-08-21 第十二輪終態補充（Codex inline `3826028174`）：上列「未被驗收點名」
只描述第十一輪入庫時狀態；本輪已被點名。可重用 `-f`／`-F @path` 官方契約與證據邊界現集中於
`docs/dev/external-facts.md` B13，本條只保留事故、復發形狀與來源。 -->

- **external-facts 的 A 區標題已不能涵蓋 A16／A17**：
  `docs/dev/external-facts.md` A 區題為 GitHub 核准／合併前置條件，但 A16 是 GitHub CLI
  GraphQL pagination 實作，A17 是 PR commits REST 邊界，兩者不屬核准或合併前置條件。
  內容正確性與編排是兩件事；本輪阻擋意見只點名 A16 證據強度與 A17 閾值，依鐵律 17.2
  不順手搬章。後續文檔編排包應把工具語義移到 B 區或改 A 區總標題，並重跑所有錨與入口
  【F5/F11；來源＝PR #64 Claude comment `5359558626` ⚪2；取證日期＝2026-08-21】

- **91 §3 缺少「候選經證偽撤回」的 tombstone 形態**：
  PR #64 首輪暫登的 GraphQL 完成性候選在第二輪經官方語義與原句文法證偽後被整段刪除，
  目前只剩附錄 A.1 摘要可追沿革；§0.3 只規定合併重複條目時留空殼，沒有規定被證偽時
  應保留 status、來源與撤回理由。後續 P-1 坑簿機制包須為「合併／證偽／已修」分別定義
  可機械檢查的終態，不得把本登記當成恢復假債的理由
  【F11/F12；來源＝PR #64 Claude comment `5359558626` ⚪4、`git log -p`；取證日期＝2026-08-21】

- **歷史計數曾被靜默改寫；缺口是未套相鄰更正，不是制度衝突**：
  PR #64 第二輪 worklog 的 Done／20.3 歷史稽核曾把「四處」直接收窄成「被點名」，破壞沿革。
  AGENTS 歷史層與鐵律 20.2.3 可同時滿足：歷史原文保留並在原處加 dated correction；終態層則
  刪除非必要計數，或把必要計數綁日期／ref 與 recheck。第四輪 worklog 已用「保留四條＋相鄰
  immutable snapshot」證明兩規則不互斥；後續不得把真缺口誤登成待裁制度衝突
  【F4/F11；來源＝PR #64 Claude comment `5359997378` ⚪1、Codex inline `3824777629`；
  取證日期＝2026-08-21】

- **external-facts 的程式碼逐字引用缺「改排」標記**：
  A16 把 pinned 官方實作的三行縮排區塊排成較短的 blockquote；控制流語義經重取仍忠實，但該檔
  規則把 blockquote 當英文逐字原文載體。後續證據格式包須保留原始換行，或明示「節錄改排」；
  本 PR 不為非阻擋的呈現差異擴改外部事實
  【F3/F11；來源＝PR #64 Claude comment `5359997378` ⚪2；取證日期＝2026-08-21】

- **A16 的首組 `pageInfo` 提早終止候選缺官方證據，現況為未取得**：
  Claude comment 提出的候選是：首組完整 `pageInfo` 可能令 `findEndCursor` 回空游標並停止
  `--paginate`，即使另一層 connection 尚有頁；本輪未取得支持這個更強跨 connection 結論的
  pinned 官方逐字與 dated URL，故不得當成既定外部行為。後續 external-facts 獨立包須從 GitHub
  CLI 的 pinned `findEndCursor` 實作重取完整控制流、逐字、URL 與日期，查證成立後才可升格
  【F3/F5；來源＝PR #64 Claude comment `5359997378` ⚪3；取證日期＝2026-08-21】

- **首輪與第四輪事後 20.3 稽核沒有逐列交代不適用類型**：
  `docs/worklog/2026-08-21-PR64首輪Claude驗收修復.md` 的事後表只列 ①②③，未明列 ④⑤⑥⑦；
  `docs/worklog/2026-08-21-PR64第四輪雙驗收修復.md` 只列 ①②③⑦，未明列 ④⑤⑥。首輪工作
  單位實際加入 HTML comment，⑦ 並非顯然不適用。被點名的修復範圍不含回改這兩份歷史表，
  依 17.2／20.5 不擴修；後續 worklog 契約包再決定是否強制全列
  【F5/F11；來源＝PR #64 Claude comments `5359997378` ⚪4／`5360279873` ⚪2；
  取證日期＝2026-08-21】

- **PR 描述的 doc-claims 快照以可移動 tag 當 base，命令重跑不再對應原輸出**：
  head `7c10b6a` 的 PR 描述把 `ruby scripts/check-doc-claims.rb --base pr64-last-push --require-base`
  與掃描輸出並列，但同一流程會在 push 後強制把 `pr64-last-push` 移到新 head；因此命令文字不是
  immutable 快照入口。後續描述須把 base 綁到實跑時的完整 SHA，或只標成 dated output snapshot，
  不得以已移動 tag 冒充可重跑原輸出
  【F5/F11；來源＝PR #64 Claude comments `5360279873` ⚪1、`5360596028` ⚪1；後一輪指出
  當時 `git rev-parse pr64-last-push` 的解析 SHA 未保存，故該命令不能補作 immutable metadata；
  取證日期＝2026-08-21】

- **PR #64 歷史複驗錨到 PR 內 commit，main-only clone 需額外 fetch**：
  第四輪 worklog 仍以 `eb1afba..7c10b6a` 保存歷史輸入；它是有效的 PR 內快照，但不能僅憑 SHA
  字串宣稱新的 main-only clone 可直接取得。第五／第六輪已把現行入口改用 preserved main base，
  不回寫第四輪歷史命令；後續引用該舊快照須明列 fetch PR object 的前置。GitHub 對 squash 後
  pull ref 的保留期限／契約未取得，故不主張必然可達或不可達
  【F5/F11；來源＝PR #64 Claude comments `5360596028` ⚪2、`5360974435` ⚪2、
  `5361414731` ⚪3（本輪重申、無新動作）；
  取證日期＝2026-08-21】

- **external-facts B5 尚未收錄 code span 開閉 backtick string 等長規則**：
  CommonMark 0.31.2 §6.1 官方逐字為 "A code span begins with a backtick string and ends with a
  backtick string of equal length."，來源 <https://spec.commonmark.org/0.31.2/#code-spans>
  （取證 2026-08-21）。B5 現值只收優先序與反斜線語義；本輪阻擋修法已改用 fenced block，
  不需擴寫 B5，依 17.2 只登記。後續 evidence-format 包若補入，須保留與 fenced code 規則的分界
  【F3/F5/F11；來源＝PR #64 Claude comments `5360596028` ⚪3、`5360974435` ⚪1；
  官方頁面由本輪獨立重取；取證日期＝2026-08-21】

- **P-8 的現行 validator 指標與手抄守衛都沒有釘住下一次 supersede**：
  P-8 終態散文雖指名第五輪 worklog 的現行 heading，但 validator 只驗該 heading 在 entry 檔內
  唯一，沒有把 P-8 指名值與實際執行 block 做相等比較；指名文字又可被 80 欄換行拆開。
  同一 validator 的 `manual round list returned` 使用不跨行的 `.*?`，而歷史散文可跨行換行，
  因此跨行手抄列舉可能避開守衛。兩者都不影響本輪被點名的跨日期 A.1 漏列修復；依 17.2
  只登記，後續 validator 契約包須用結構化 current-entry metadata 與跨行反向案例共同收斂
  【F5/F11/F12；來源＝PR #64 Claude comments `5361414731` ⚪1／2、`5361847317` ⚪3
  （再次核對，無新動作）、`5363200002` ⚪1（第四次 supersede 復發錨）、`5363469305` ⚪1
  （第五次 supersede 復發錨）；取證日期＝2026-08-21】

- **PR64 的 20.3 correction validator 沒有固定 HEAD snapshot**：
  第十一輪 worklog 的 correction validator 以 `File.read` 直接讀工作樹，沒有像第五輪現行
  validator 先要求乾淨工作樹；有未提交編輯時可能把 working copy 結果寫成 HEAD 證據。本輪
  阻擋項不要求改該 validator，依 17.2 只登記。後續 validator 契約包須統一 snapshot 來源，並以
  dirty-worktree mutation 證明不會混用
  【F5/F11/F12；來源＝PR #64 Claude comment `5363200002` ⚪2；取證日期＝2026-08-21】

- **tracked worklog 無法在同一 commit 保存「最後 repo edit 後」的最終實跑結果**：
  第九／第十／第十一輪 20.3 表都把最後閘門寫成待跑，結果改放 PR 描述；若把結果再回寫 worklog，
  該回寫本身又成為新的 repo edit，使前一輪結果不能外推。這是 tracked evidence 的 bootstrapping
  邊界，不得靠手寫「已跑」消除。後續 evidence-tail／機器 artifact 包須把 immutable commit 與
  run URL 綁定，歷史 worklog 只留待辦及證據入口
  【F5/F11/F12；來源＝PR #64 Claude comment `5363200002` ⚪3；取證日期＝2026-08-21】

- **PR64 worklog 集合 validator 的輸入缺失／工具失敗分支沒有 mutation 承重**：
  現行 block 已有 normal、duplicate、drop、missing-section、off-date、delete、rename 路徑，
  但 `missing terminal correction`、entry path multiplicity、heading multiplicity、manual list、
  command failure 與 empty set 等 fail-closed guard 沒有各自的 mutation／fixture；因此不能由既有
  mutation 推出所有輸入缺失與工具失敗分支都被證明。這不影響本輪被點名的歷史表更正；依
  17.2 只登記，後續 validator 契約包須以逐分支 mutation 補齊 20.2.5
  【F5/F11/F12；來源＝PR #64 Claude comments `5361847317` ⚪1、`5363469305` ⚪3；
  取證日期＝2026-08-21】

- **PR64 destructive history guard 的零掃描 canary 擋不住 pathspec 縮成非空子集**：
  現行 block 只要求同一 pathspec 的 A 類 canary 非空；若 pathspec 從完整承重集合縮成仍有新增檔
  的子集，canary 仍非空、D／R 也可合法為空，整支會通過。`history_status` 接住 production D／R
  結果後沒有再被讀取，也不能補上集合射程相等的斷言。本輪未獲授權改歷史 validator，依 17.2
  只登記；後續 validator 契約包須先固定承重資產集合，並以「合法非空子集」mutation 證明縮射程
  會轉紅【F5/F11/F12；來源＝PR #64 Claude comment `5363665327` ⚪1；取證日期＝2026-08-21】

- **PR64 對歷史 worklog 現行 block 的實質改寫沒有在原處留下 dated correction**：
  第十三輪曾改寫第五輪 worklog 的現行 fenced block，但 heading 仍稱「第十二輪更正」，原處也沒有
  記錄第十三輪改了什麼；這讓歷史層只剩 git diff 才能還原沿革。本輪只登記、不回寫未被點名的
  第五輪 block；後續若再 supersede，必須在相鄰位置留下日期、來源判詞與變動邊界
  【F5/F11；來源＝PR #64 Claude comment `5363665327` ⚪2；取證日期＝2026-08-21】

- **PR64 destructive history guard 未涵蓋 `external-facts.md`**：
  第十三輪時 B13／B14 已成為 P-8 的承重外部事實，但第五輪現行 validator 的 destructive
  pathspec 只掃 `docs/worklog`；刪除或改名 `docs/dev/external-facts.md` 不會由該 guard 擋住。
  本輪只修被點名的 worklog production wiring，依 17.2 不擴大資產射程；後續 validator 契約包
  應先定義承重資產集合，再為每個集合配置同射程非空 canary 與刪除／改名 mutation
  【F5/F11/F12；來源＝PR #64 Claude comments `5363469305` ⚪2、`5363665327` ⚪3；
  取證日期＝2026-08-21】

- **終態 external-facts 把帶完整 SHA 的歷史快照稱為會移動的「PR exact head」**：
  `26fc683e40bb8ad6466d082c6887876345f84646` 有日期與完整 ref，快照本身可重現；但在終態層仍稱
  「PR #64 exact head」，下一次 push 後 descriptor 就不再等於 HEAD。依 17.2 不改未點名原文，
  後續 evidence-format 包須寫「當時的 head」或只保留日期＋SHA
  【F5/F11；來源＝PR #64 Claude comment `5363892357` ⚪1；取證日期＝2026-08-21】

- **external-facts A17 把官方 endpoint 與本專案的 `?sha=` 組法歸成同一個官方指引**：
  官方 PR commits 頁指向 repository List commits endpoint；`sha` query 的合法性由另一頁參數定義
  分別支持。把兩者合寫為「官方指向的端點是 `...commits?sha=...`」會模糊來源歸屬。依 17.2
  不改未點名原文；後續 evidence-format 包須把官方 endpoint、官方參數語義與本專案組法分欄
  【F3/F5/F11；來源＝PR #64 Claude comment `5363892357` ⚪2；取證日期＝2026-08-21】

- **external-facts B14 的 `--diff-merges` 預設 `off` 只有中文轉述、沒有英文逐字**：
  同節其他 Git 語義已有官方英文原文，但「未使用 `--first-parent` 時預設 off」仍只寫轉述；本輪
  點名修的是新寫入 A17／B13，不得順手擴修前輪內容，依 17.2 只登記。後續 evidence-format 包須
  重新取 Git 官方原文並保留完整條件
  【F3/F5/F11；來源＝PR #64 Claude comment `5363892357` ⚪3；取證日期＝2026-08-21】

- **91 附錄 A.1 的全量對帳仍只存在於 worklog fence，沒有 CI 機械閘門**：
  現行動態對帳可在人工執行時比對 PR64 worklog 集合，但 `ci.yml` 沒有呼叫該 fenced validator；
  因此「附錄已全量」仍不能由一般 CI 綠推得。本輪不改 workflow，也不把範圍外意見升格為修檔
  授權；後續若產品化，必須依鐵律 18.3 拆成 workflow／script 受限包並由使用者人工合併
  【F5/F11/F12；來源＝PR #64 Claude comment `5363469305` ⚪4；取證日期＝2026-08-21】

- **merge-only witness 的未點名歷史副本仍漏 `git diff-tree -r`**：
  `docs/worklog/2026-08-21-PR64第十二輪雙驗收修復.md` 的歷史 Done 仍寫 `git diff-tree -m`
  witness 為 1 次；對巢狀 `.pyc` 路徑實跑時，不加 `-r` 只得到 `M scripts`，加 `-r` 才得到
  目標 `D`。本輪被點名的是中央契約 `docs/dev/external-facts.md` B14；依 17.2 不回寫未點名的
  歷史副本。官方 `-r` 契約、可重跑命令與取證日期集中於 B14
  【F3/F5/F11/F12；來源＝PR #64 Codex inline `3826183941` 的同型抽樣；取證日期＝2026-08-21】

- **external-facts A16 的短引文丟失官方句中的情態與模式上下文**：
  A16 現值把片段引為 "the original query accepts..."，但 GitHub CLI 官方 pinned 原文是
  "For GraphQL requests, this requires that the original query accepts an `$endCursor: String` variable"；
  完整取頁片段的官方前綴另為 "In `--paginate` mode,"。現行 A16 的後續散文補回要求語義，
  結論未被證偽；缺口只在逐字節錄載體本身。依 17.2 不順手改 external-facts，後續 evidence-format
  包須讓引文自行保留必要情態／上下文。來源：
  <https://github.com/cli/cli/blob/fadd4efb7daddd8afd8a5517a0cb5f5f39af6ada/pkg/cmd/api/api.go>
  【F3/F5/F11；官方 pinned 原文獨立重取；PR #64 Claude comment `5361847317` ⚪2；
  取證日期＝2026-08-21】

- **`external-facts` B13 的 `-f/--raw-field` 逐字是無省略號的截斷句**：該句引為
  "…to add static string parameters"，而上游 `cli/cli` 的 `pkg/cmd/api/api.go` 全句為
  "Pass one or more `-f/--raw-field` values in `key=value` format to add static string
  parameters **to the request payload**."——缺的 "to the request payload" 正是限定該旗標
  「參數放進哪裡」的那半句，且截斷處**沒有省略號**，讀者無從察覺這是節錄。語義未被證偽、
  <!-- 🔴 2026-08-22 更正（來源＝Codex inline `3835660396`）：本條原寫「⋯正是把該旗標**定位在
       request body 層**的限定語」。**`request payload` 不等於 `request body`**——同一段官方
       說明的下一句逐字寫著：
         "To send the parameters as a `GET` query string instead, use `--method GET`."
       （本輪實跑 `gh api --help` 取得，與 <https://cli.github.com/manual/gh_api> 一致）
       ⇒ `-f` 的值在預設 POST 下進 body，在 `--method GET` 下進 **query string**。
       把它寫成「body 層」會讓照本檔組 GET 請求的人組錯，屬**會製造未來債的錯誤定位**。
       已改為官方自己的措辭「request payload」，並在此保留 GET 邊界。
       🔴 本條原本要說的事沒有變：**截斷處沒有省略號**這個載體問題仍然成立、仍只登記不修。 -->
  該行本輪未動 ⇒ 依 17.2 只登記。與本節 A16 的「短引文丟失情態」同根因（逐字節錄載體
  未保留必要限定），後續 evidence-format 包應統一規定「節錄必加省略號並保留限定語」
  【F3/F5/F11；來源＝PR #64 Claude issue comment `5364180385` ⚪1；取證日期＝2026-08-22】

- **`external-facts` B13 的「官方同頁**另**明列」在本輪之後變成同節內重述**：上一輪已把
  `-F …@-` 與 `--input` 的逐字補進**正上方**的 blockquote，於是該段「另（在別處）明列」的
  框架失去對象——讀者會去找一個不在別處、就在上面三行的東西。屬敘事框架與現況脫節，
  不影響任何斷言 ⇒ 依 17.2 只登記。正解＝把「另明列」改為指向上方 blockquote 的第二／三句
  【F5/F11；來源＝PR #64 Claude issue comment `5364180385` ⚪2；取證日期＝2026-08-22】

- **上一條的標題行在同一行用了四個 `**` run，GFM 把粗體切成兩段、被夾住的「另」反而不是粗體**：
  原文為 `` - **`external-facts` B13 的「官方同頁**另**明列」⋯變成同節內重述**：``。
  🔴 **本條的渲染證據是本輪實跑取得的**（判詞把它記為「未取得」）：把該行單獨送 GitHub
  `/markdown`（`mode=gfm`）實得
  `<li><strong><code>external-facts</code> B13 的「官方同頁</strong>另<strong>明列」⋯重述</strong>：⋯</li>`
  ——`<strong>` 標籤 **2 個**，邊界落在「官方同頁 / 另 / 明列」之間 ⇒ 作者意圖的
  「整句粗體、其中『另』再強調」**沒有發生**，實際是兩段粗體夾一個普通字。
  ⚠️ 可讀、不影響任何斷言，且它是敘事措辭而非規範性斷言 ⇒ 依 17.2 只登記。
  正解＝該行改用單一 `**⋯**` 包住整句，內部強調改用其他標記或直接去掉
  【F5/F11；來源＝PR #64 Claude issue comment `5379467830` ⚪1；取證日期＝2026-08-22】

- **worklog `Done` 段宣稱「六則 inline」，逐條列名只有五則**：PR #64 第十七輪 worklog 的
  `Done` 首項寫「Codex review `4999795981`（六則 inline：五則 P1、一則 P2）」，
  而同段逐條列名只出現五則。⚠️ **總數是對的**（該 review 確為六則），漏的是列名那一份；
  不影響任何處置結論 ⇒ 依 17.2 只登記。
  正解＝把第六則補進列名，或不寫總數、只列處置到的那幾則
  【F5/F11；來源＝PR #64 Claude issue comment `5379763381` ⚪1（`5381104120` ⚪3 續登記）；取證日期＝2026-08-22】

- **本檔「本節 22 行引用同批改號」是手寫數字、同位置無複驗指令**：該數在寫下時為真
  （驗收方複驗：舊號側 `-` 行 22、新號側 `+` 行 23，多的一條是說明註自身），
  但依 `AGENTS.md` §2「散文裡不得手寫可由代碼算出的數字」，它需要鄰近的複驗指令或快照標記。
  ⚠️ 不影響改號的正確性（改號結果另有集合複驗）⇒ 依 17.2 只登記。
  正解＝改為不寫數字，或鄰附 `git diff --stat` 之類的導出式
  【F5/F11；來源＝PR #64 Claude issue comment `5381104120` ⚪1；取證日期＝2026-08-22】

- **A.1 的一則 dated correction 引用的「160／160」在後續 head 已是 161／161**：
  該註記錄的是「tracked worklog 數與 A.1 條目數相等」這個**結論**，兩側同步成長
  ⇒ **結論在現值仍然成立**，過期的只是它引用的那一組具體數字。
  ⚠️ 它是歷史層的 dated correction、不就地改 ⇒ 依 17.2 只登記。
  正解＝該類註一律不寫具體數字，改寫「兩式必須相等」＋導出指令
  （本檔上方既有的 canonical 全量 md5 就是這個形態）
  【F5/F11；來源＝PR #64 Claude issue comment `5381104120` ⚪2；取證日期＝2026-08-22】

- **更正註寫在 `Changes` 子節，而被改寫的原文在 `Done` 段**：`AGENTS.md:112` 逐字要求「發現寫錯就在**原處**加更正註」，而 PR #64 第十七輪 worklog 那則第 4 次復發的更正註，註在 `Changes` 下的 `合併輪處置` 子節，被替換的兩段原文則在 `## 已完成的工作 (Done)`。
  ⚠️ 內容完整、來源與復發次數都寫了，且 `check-doc-claims.rb` 綠 ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：讀 `Done` 段的人**不會看到**那裡的兩段話已被撤回——更正註的全部作用就是「讓讀到錯誤原文的人當場看到更正」，位置錯了等於作用歸零。
  正解＝更正註一律緊貼被更正的原文；若一則註涵蓋多處，各處都放指標
  【F5/F11；來源＝PR #64 Claude issue comment `5381302078` ⚪1；取證日期＝2026-08-23】

- **「傳播到全部 N 個落點」這類全稱句，同位置無導出指令**：PR #64 第十七輪 worklog 寫「傳播到規則的**全部 5 個落點**」，一道 grep 即證偽（**在 `3ffd2d26` 那棵樹上**同規則另有四個落點無指標；本輪已補齊，現況以導出指令為準），而同列的落點清單本身讀起來是 6。
  ⚠️ 本輪已把該句撤掉並補齊落點（見該檔第十八輪處置），此處登記的是**類**不是那一個實例 ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：「全部 N 個」是一個**對集合的全稱斷言**，而寫的人手上只有自己剛改過的那幾處——
  這兩者從來不是同一個集合。同型事故在本檔另見「手寫 22 行」與「手寫 160／160」兩條（不寫總數——本節仍在增長）。
  正解＝**不寫數字**，改寫「規則的每一個落點都要有」＋一道能列出全集的 grep；要寫數字就同位置附導出式
  【F5/F11；來源＝PR #64 Claude issue comment `5381302078` ⚪2；取證日期＝2026-08-23】

- **「驗收方已在本倉庫重現該情境」這類轉述，無可存取的複驗錨**：`docs/DECISIONS.md` 的 D39 更正註曾逐字寫這一句，而驗收方原文說的是「I reproduced this in a temporary repository」——**臨時倉庫不是本倉庫**，且該倉庫讀者無從存取。
  ⚠️ 該句已在本輪改判準時隨整則註一起被換掉（現行註不含任何轉述型證據），此處登記的是**類** ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：把外部代理的「我試過了」轉寫成本倉庫的既成事實，會讓後續讀者以為倉庫裡有那個 fixture。
  正解＝轉述外部驗證一律逐字引原文＋標明載體（哪個 comment id、哪一句），不改寫成本倉庫語氣
  【F5/F11；來源＝PR #64 Claude issue comment `5381302078` ⚪3；取證日期＝2026-08-23】

- **落點複驗的雙 grep 左式無射程限定，輸出須人工逐筆分辨**：`docs/DECISIONS.md` D39「落點同步」那條改成導出指令後，左式（規則陳述句全集）在本樹輸出數十行，其中**大部分不是規則陳述**——而是歷史 worklog 的敘事、`docs/DECISIONS.md` 自己的沿革段、以及各處對該規則的**引述**。
  成分導出（不寫死數字，會隨文件成長）：
  ```bash
  grep -rn '不另建「第 M 輪」\|一份 worklog\|不按驗收輪增殖\|只維護一份' --include=*.md docs/ AGENTS.md CLAUDE.md \
    | sed 's|:.*||' | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn
  ```
  <!-- 🔴 2026-08-23 更正（來源＝本輪 push 前對抗式複驗，非驗收方點名）：
       本條初稿逐字寫「其中大半是 `docs/handoff/`（D36 已凍結、不回寫）與歷史 worklog 的敘事」。
       🔴 實跑證偽：`docs/handoff/` 只佔 **1 行**。
       後果不是描述不美——初稿據此開出的正解是「左式加路徑排除（至少排掉 `docs/handoff/`）」，
       那樣只會少掉那 1 行，**解決不了它自己描述的問題**。
       🔴 這是「我以為的成分」被當成「量到的成分」發布：我沒有跑過 `uniq -c`，只是從印象寫。
       ⇒ 改為只給導出指令，並把正解改成按「是不是規則陳述」判，不是按路徑排除。 -->
  ⚠️ 該條已自註「逐筆看左邊每一個規則陳述（非引用、非 worklog 敘事）」，**判準本身沒錯，缺的是機械斷言** ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：沒有機械斷言 ⇒ 這條複驗的可靠度等於執行者的耐心；而它保護的正是「規則有沒有真的生效」。
  正解＝改成 checker 腳本，判準是「**每個規則陳述句** ±N 行內有指標」——**不是路徑排除**（排除路徑解決不了「同一個檔裡既有規則陳述又有敘事」這件事）。過渡期用導出指令＋人工逐筆判，並在同位置寫明判別法：規則陳述＝該句本身要求讀者做或不做某事；敘事／引述＝該句在描述某輪發生過什麼
  【F5/F11；來源＝PR #64 Claude issue comment `5381492053` ⚪1；取證日期＝2026-08-23】

- **worklog 檔名射程與內容射程持續背離**：`docs/worklog/2026-08-22-PR64第十七輪雙驗收修復.md` 檔名寫「第十七輪」，內容已含第十八、十九輪處置段。D39 之後同一份 worklog 會持續累積輪次，而 `docs/worklog/README.md` 的檔名規約在同位置沒有說明這件事。
  ⚠️ 這是 D38「一個 PR 一份 worklog」的**必然結果**，不是缺陷 ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：用檔名找「第 N 輪在哪」的人會找不到，而本倉庫的復發計數正是靠逐輪紀錄。
  正解＝檔名規約明文「檔名記的是**建檔輪次**，不是內容射程；輪次入口看檔內 `### 第 N 輪處置` 標題」，並在 README 同位置附導出指令
  【F5/F11；來源＝PR #64 Claude issue comment `5381492053` ⚪2；取證日期＝2026-08-23】

- **本 PR 動過的檔裡有既有的「表格欄數不符 header」列，且形態不只一種**：
  ① `docs/plans/2026-08-18-總方案.md` 的 X3–X10（header 三欄、各只有兩欄，末欄整格缺）；
  ② `docs/dev/m0-review-convergence.md` 表後那句以 `（表列以 `…` 為準）` 開頭的段落——它**沒有以直線開頭**，卻因為緊貼表格且句中 code span 內有未跳脫的直線，被 GFM 併進上一張表當成表列、切成兩格、反引號失去 code 語義。
  🔴 **不在此列舉筆數**：初稿只寫了 ①、並逐字寫「僅⋯八列」，複驗立刻找到 ②；第 23 輪換上集合判準的檢查器後又找到 ③④。例外集合一旦手寫列舉就會漏——導出指令見下。
  ③ `docs/plans/2026-08-18-總方案.md` 的 `P-8` 那一列：原始碼是表列形狀，**渲染後不是 `<tr>`**（被擠出表格）；
  ④ `docs/specs/91-pit-register.md` 的「（其餘待收割輪填入）」那一列末欄為空。
  ⚠️ ③④ 同樣在 base `bbf5f3b7` 上就已存在、本 PR 未動該區塊 ⇒ 一併只登記。
  依 GFM 官方規格逐字——
  > “The remainder of the table’s rows may vary in the number of cells. If there are a number of cells fewer than the number of cells in the header row, empty cells are inserted. If there are greater, the excess is ignored”
  （<https://github.github.com/gfm/> §4.10 Tables，取證日期＝2026-08-23）
  ——**少格**不會丟資料（補空格），**超格**才會丟；這八列屬前者，症狀是該表第三欄對它們一律空白。
  ⚠️ 兩者在 base `bbf5f3b7` 上就已存在，本 PR 對這兩個檔的 hunk 都不在該區塊（複驗：`git diff bbf5f3b7..HEAD -- <該檔> | grep '^@@'`）；依使用者「只修點名的」裁定不在本包修 ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：與 20.2.7 點名的那一列（內容錨：PR #64 第十七輪 worklog `合併輪處置` 表裡「兩向差集皆空」開頭的 `Claude 🔴-1` 列）是**同一類**（表格欄數與 header 不符），只是方向相反（缺格 vs 超格）；缺格不會像超格那樣丟掉內容，所以優先度低，但同一支掃描器兩者都會報。
  🔴 **兩種形態的正解不同，不能共用一條**：
  - **形態 ①（表列缺格）** 正解＝**補上第三欄**。🔴 **不要改 header 為兩欄**——同表的 X1／X2 有第三欄，把 header 縮成兩欄會讓它們的第三欄變成超額 cell 而被 GFM **靜默丟棄**，
    正好是本條上一段引的那句 "the excess is ignored"。
  - **形態 ②（段落被誤吸進表格）** 正解＝在該表最後一列與該段落之間**補一個空行**。
    🔴 **不要照形態 ① 補第三欄**——那會把一個本來是散文的句子**固化成表列**，等於承認了誤吸。
    ⚠️ 只跳脫 code span 內的直線**不夠**：句子仍緊貼表格 ⇒ 仍被吸進去；
    而只補空行**就夠了**——該句成為獨立 `<p>` 之後，code span 內的直線不再被當成儲存格分隔（本輪以 GitHub `/markdown` 實跑確認）。
    🔴 初稿在這裡寫「兩者要同時做」，是**未實跑就推論**；照初稿改會在一個本來不需要跳脫的 code span 裡留下一個 `\|`。

  複驗＝欄數掃描（逐表逐列比對「未跳脫直線數 − 1」與 header 欄數，跳過 fenced code block 與分隔列）。
  🔴 **本倉庫尚無此掃描器**（`scripts/` 下查無）；本輪是以一次性腳本跑的，隨用隨棄。要固化成閘門須另立工作包
  【F5/F11；來源＝PR #64 Claude issue comment `5381492053`（本輪 20.3 ⑦ 掃描的副產物，非驗收方點名）；取證日期＝2026-08-23】

- **`scripts/check-doc-claims.rb` R4 的中文數詞字元類不含「兩」**：該檔 `NUM` 逐字為 `/(?:[〇零二三四五六七八九十百][〇零一二三四五六七八九十百]*|一[〇零一二三四五六七八九十百]+|\d+)/`——**「兩」不在字元類裡**，而中文量詞前用「兩」比用「二」常見得多。
  ⇒ 「三張表」會被 R4 抓到，「**兩**張表」不會；「共三份」會，「共**兩**份」不會。
  ⚠️ 這是**閘門缺口**不是文件缺陷，且改 `scripts/` 屬本包射程外（使用者「只修點名的」裁定）⇒ 依 17.2 只登記。
  🔴 **登記的代價**：本 PR 第 19 輪確實有一句「對本輪改過的**兩張表**」落在 R4 的生效射程內（改動 worklog 的新增行）而**結構性隱形**，
  `ruby scripts/check-doc-claims.rb --base <上一 head>` 實得 OK、🟡 警告 0。該句最後是被人工對抗式複驗抓到的，不是被閘門。
  🔴 **這是同根因第 2 次**：該腳本 121–125 行自己記載「初版五條 pattern 全以 `\d+` 開頭 ⇒ 對本專案最常見的寫法結構上全盲」——
  當時補了中文數詞，但補的字元類漏了最常用的那一個。
  正解＝`NUM` 的兩個字元類各補「兩」（連帶考慮 千／萬／廿／卅／倆），並加 fixture 打紅「共兩份」「兩張表」；
  複驗＝`ruby scripts/test-doc-claims-rules.rb` 需有一則新 fixture 因此轉紅
  【F5/F11；來源＝PR #64 第 19 輪 push 前對抗式複驗（非驗收方點名）；取證日期＝2026-08-23】

- **鐵律 20.3 的稽核表沒有任何機器會讀它，同一張表已被點名四次**：PR #64 的 20.3 表在第 15 輪（欄名被改）、第 18 輪（輸出欄指向不存在的段落）、第 20 輪（欄名再被改＋四列無輸出）、以及該輪 push 前複驗（⑥ 列的反向複驗式本身是 fail-open）各被點名一次。
  前三次的固定處理都是「把這一格補上」，第四次證明問題不在某一格——**這張表的每一格都是散文，正確性只取決於寫的人有沒有真的逐格跑過**。
  ⚠️ 改 `scripts/` 屬 PR #64 射程外（使用者「只修點名的」裁定）⇒ 依 17.2 只登記。
  🔴 **登記的代價**：在它被機制化之前，20.3 表的可靠度等於「作者這一輪的自律」，而本 PR 已經證明那個可靠度不足以支撐四輪。
  正解＝把可機械化的列做成 `scripts/` 檢查器並掛 CI，至少涵蓋：
  ①⑥ 的禁區 pathspec（`git diff --name-only <range> -- .github scripts script config bin spec package.json Rakefile Gemfile .rubocop.yml` 非空即 FAIL；**用 pathspec 不用 regex 交替**，因為交替符在 Markdown 表格裡會被跳脫成字面直線而恆不匹配）
  ②⑦ 的表格欄數斷言與末欄 sentinel（渲染後每列最後一個 `<td>` 非空）
  ③「輸出欄不得只有指令或位置指標而無實跑結果」的形狀檢查
  複驗＝新檢查器對 `abafcc2^..abafcc2`（該 commit 動過 `.github/workflows/`）必須 FAIL；對純 docs 的 range 必須 PASS
  🔴 **本條的 pathspec 與 worklog 20.3 ⑥ 列必須逐字相同**——它是未來檢查器的規格來源，
  兩處分歧時實作出來的檢查器會重現已被點名過的缺口。同步複驗（兩式輸出必須完全相同）：
  ```bash
  grep -o -- '-- \.github[^`]*' docs/specs/91-pit-register.md
  grep -o -- '-- \.github[^`]*' docs/worklog/2026-08-22-PR64第十七輪雙驗收修復.md
  ```
  <!-- 🔴 2026-08-23 更正（來源＝PR #64 Claude issue comment `5382552421` 🔴-3）：
       本條的 pathspec 原本逐字漏掉 `spec` 與 `package.json`。上一輪已在 worklog 的 20.3 ⑥ 列補寬，
       **卻沒有同步本條與 PR 描述** ⇒ 照本條實作出來的 CI 檢查器，正好重現上一輪被點名的缺口
       （把 `pnpm test` 改成 no-op 或刪掉 `spec/` 仍會報綠）。
       🔴 這是同一輪內的 producer／consumer 不同步：**我把「修好」等同於「被點名的那一行改了」**。 -->
  【F5/F11；來源＝PR #64 第 20 輪 push 前對抗式複驗（11 agent，非驗收方點名）；取證日期＝2026-08-23】

- **更正註逐字保留「被改動的處」時，用手寫列舉就會漏**：PR #64 第 20 輪的更正註逐字寫「本節⋯有**六處**被本輪就地改寫，依 19.5 逐字保留改前原文如下」，而同一個 commit 在該節內改動的段落多於六處。
  ⚠️ 本輪已改為「逐字保留被點名的那幾處 ＋ 其餘以 `git show <舊 head>:<檔>` 取回指標為準」⇒ 依 17.2 只登記**類**。
  🔴 **登記的代價**：19.5 的目的是讓讀者看得出「這裡曾經寫過別的」。列舉漏掉的那幾處，讀者不但看不出改過，還會因為前面有一份「完整清單」而**更加相信沒改過**——不完整的列舉比沒有列舉更糟。
  正解＝更正註一律附**取回指標**（`git show <改動前 head>:<檔案>`）與**導出指令**（`git diff <舊> <新> -- <檔>`），逐字保留只給被點名的那幾處，不宣稱涵蓋全部
  【F5/F11；來源＝PR #64 Claude issue comment `5382422505` ⚪1；取證日期＝2026-08-23】

- **同一份 worklog 有兩張 `### 鐵律 20.3 送驗前稽核`，射程重疊而方法不同**：PR #64 第十七輪 worklog 內，前一張綁第 15–17 輪、後一張標「涵蓋第 18／19／20 輪」但宣告的 range 是 `bbf5f3b7..HEAD`——**該 range 也涵蓋第 17 輪**。
  兩張表對重疊區間的 ⑥ 列給了不同方法（前者「`git status` 僅 docs 檔」、後者禁區 pathspec），讀者拿不到「哪一張管哪一段」的判準。
  ⚠️ 前一張是歷史層（記第 15–17 輪當時做了什麼），依 `AGENTS.md:112` 不就地改⇒ 依 17.2 只登記。
  🔴 **登記的代價**：稽核表是用來回答「這一輪有沒有掃過」的。兩張射程重疊的表並存時，那個問題對重疊區間有兩個互相衝突的答案。
  正解＝新表的射程宣告改為**排除已被前一張涵蓋的區間**（例如綁 `<前一張的終點>..HEAD`），或在新表開頭明寫「前一張管到哪個 head 為止」
  【F5/F11；來源＝PR #64 Claude issue comment `5382422505` ⚪2；取證日期＝2026-08-23】

- **就地改寫「別人立的 dated 更正註」時沒有自己的來源標註**：PR #64 第 21 輪改寫了第 20 輪立的一則更正註內文（把一句全稱句改成列舉），而該處**沒有留下自己的 dated 標記或來源**——同輪其他就地改寫都有標。
  ⚠️ 整段在 HTML 註釋內、渲染後不可見，且 doc-claims 綠 ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：更正註是**事故軌跡**。改寫別人立的註而不留自己的標記，等於把兩輪的認知壓成一輪，
  下一個人讀到的是「第 20 輪就想通了」，而事實是第 21 輪才改的。19.5 擋的正是這件事。
  ⚠️ 同處另有兩個小瑕疵（本輪一併登記，不單獨立條）：句末留下未閉合的全形左括號；「三件事」的手寫列舉漏掉兩項，
  而同一則註三行之上才剛寫過「手寫列舉就會漏」。
  正解＝改寫既有更正註一律追加自己的 dated 標記與來源，不就地覆蓋；列舉一律附導出指令
  【F5/F11；來源＝PR #64 Claude issue comment `5382552421` ⚪1；取證日期＝2026-08-23】

- **註釋內的巢狀分隔標記出現多餘的收尾**：`docs/DECISIONS.md` 有一處句末是兩個連續的 `----`，而同檔體例是一個 `----` 收一則巢狀 dated 註，第二個沒有對應的開啟。
  ⚠️ 在 HTML 註釋內、不影響渲染，doc-claims 綠 ⇒ 依 17.2 只登記。
  🔴 **登記的代價**：`----` 是本倉庫**自訂**的巢狀註分隔法（因為 HTML 註釋不能真的巢狀）。
  自訂標記沒有任何機器檢查，配對錯了只能靠讀者自己數——而它存在的理由正是「HTML 註釋巢狀會出事」。
  正解＝把巢狀 dated 註改成**同層並列的獨立註**（各自 `<!-- -->` 收口），不要自訂巢狀語法；
  過渡期複驗＝`grep -c -- '^ *---- ' <檔>` 與 `grep -c -- ' ----$' <檔>` 應成對
  【F5/F11；來源＝PR #64 Claude issue comment `5382552421` ⚪2；取證日期＝2026-08-23】

- **`scripts/check-doc-claims.rb` 的 `VOLATILE_NUM` 單位清單缺「格／列／欄／輪」**：該常數現有的量詞是 `支`（檢查器／腳本）、`條`（case／fixture）、`個`（fixture）、`張`（表）與 `共 N [支條個張份]`。
  ⇒ 「十一**格**」「三**列**」「第 N **輪**」這類寫法**結構性隱形**。
  ⚠️ 改 `scripts/` 屬 PR #64 射程外（使用者「只修點名的」裁定）⇒ 依 17.2 只登記。
  🔴 **登記的代價**：PR #64 第 23 輪確實有一句「本輪矩陣**十一格**全部實跑」落在該閘門射程內而未被攔下，
  最後是驗收方人工抓到的。**而「格」正是這個 PR 最常用的量詞**——D39 的輸入矩陣、20.3 的稽核表都以「格」計。
  🔴 這與本檔已登記的「`NUM` 字元類不含「兩」」是**同一個腳本的同一族缺口**：量詞與數詞兩側各漏一批，
  而它們的交集正好覆蓋本專案最常見的寫法。
  正解＝`VOLATILE_NUM` 補 `格|列|欄|輪`（併入既有的 `共 N [支條個張份]` 字元類與獨立量詞兩處），
  並加 fixture 打紅「十一格」「三列」；複驗＝`ruby scripts/test-doc-claims-rules.rb` 需有新 fixture 因此轉紅
  【F5/F11；來源＝PR #64 Claude issue comment `5382825871` ⚪（續上一輪未落籍）；取證日期＝2026-08-23】

## 附錄 A：歷史收割清單（逐檔打勾；勾＝已通讀並完成坑抽取）

> 收割紀律：**去重按根因不按症狀**；每檔讀完在此打勾並在 §1/§3 落抽取結果（零抽取
> 也要勾，代表「讀過、無新坑」）。**完成判準**＝全部勾完後，隨機抽 5 份 worklog
> 復讀，漏抓率 0 才算收（抽樣記錄附於本節末）。
> 名單複驗（**集合比對**，第 6 輪升級、第 7 輪改 fenced＋左界收窄——inline code 內
> 反斜線不逸出反引號、CommonMark 逐字取用致渲染斷句；且原式掃整檔，§1 條目落地帶
> 「檔:行」引文即常態誤報。下列兩式輸出相等即通過（quotepath 旗標：中文檔名無它
> 輸出為八進位跳脫）：

```bash
git -c core.quotepath=false ls-files docs/worklog docs/handoff | sort | md5sum
grep -E '^- \[.\] ' docs/specs/91-pit-register.md | grep -oE 'docs/(worklog|handoff)/[^`]+' | sort | md5sum
```

> 🔴 **新增 tracked worklog 的同一 commit 必須同步補列本清單**（第 2 輪改——原
> 「之後隨輪補列」擋不住同 commit 新增檔漏列）。依 D36，之後不得新增 tracked
> `docs/handoff/`；倉庫外的本地 handoff 不屬於本清單。既有 `docs/handoff/` 保留於
> A.2 作歷史追溯，不刪除、不改寫。

### A.1 worklog

- [ ] `docs/worklog/2026-08-13-M0骨架移植改造.md`
- [ ] `docs/worklog/2026-08-13-admin稽核第三輪.md`
- [ ] `docs/worklog/2026-08-13-ci-auto-merge-gate.md`
- [ ] `docs/worklog/2026-08-13-hreflang鍵漂移修正.md`
- [ ] `docs/worklog/2026-08-13-parity-R10市場.md`
- [ ] `docs/worklog/2026-08-13-parity-R1成長區.md`
- [ ] `docs/worklog/2026-08-13-parity-R2b全域chrome首頁收尾.md`
- [ ] `docs/worklog/2026-08-13-parity-R2首頁指標系統.md`
- [ ] `docs/worklog/2026-08-13-parity-R3設定五頁.md`
- [ ] `docs/worklog/2026-08-13-parity-R4財務帳單.md`
- [ ] `docs/worklog/2026-08-13-parity-R5顧客線.md`
- [ ] `docs/worklog/2026-08-13-parity-R6折扣.md`
- [ ] `docs/worklog/2026-08-13-parity-R7訂單線.md`
- [ ] `docs/worklog/2026-08-13-parity-R8產品線子頁.md`
- [ ] `docs/worklog/2026-08-13-parity-R9內容與線上商店.md`
- [ ] `docs/worklog/2026-08-13-parity-sweep-R0主清單.md`
- [ ] `docs/worklog/2026-08-13-文檔債同步.md`
- [ ] `docs/worklog/2026-08-13-本機環境部署與M0全套實測.md`
- [ ] `docs/worklog/2026-08-13-移除translations-market-id.md`
- [ ] `docs/worklog/2026-08-13-金額規格M7M8M9結案.md`
- [ ] `docs/worklog/2026-08-14-89號剩餘缺陷清掃.md`
- [ ] `docs/worklog/2026-08-14-A1撤銷術語.md`
- [ ] `docs/worklog/2026-08-14-A3快照欄.md`
- [ ] `docs/worklog/2026-08-14-A5發布模型.md`
- [ ] `docs/worklog/2026-08-14-CI全紅修復.md`
- [ ] `docs/worklog/2026-08-14-PR24驗收修復.md`
- [ ] `docs/worklog/2026-08-14-merge-R11-R13.md`
- [ ] `docs/worklog/2026-08-14-parity-R11分析.md`
- [ ] `docs/worklog/2026-08-14-parity-R12設定.md`
- [ ] `docs/worklog/2026-08-14-parity-R13管道.md`
- [ ] `docs/worklog/2026-08-14-review回應.md`
- [ ] `docs/worklog/2026-08-14-原型P0四條修復.md`
- [ ] `docs/worklog/2026-08-14-欄位設定假成功訊息.md`
- [ ] `docs/worklog/2026-08-14-死控件lint-review三輪.md`
- [ ] `docs/worklog/2026-08-14-死控件lint-review二輪.md`
- [ ] `docs/worklog/2026-08-14-死控件lint規則.md`
- [ ] `docs/worklog/2026-08-14-白名單一致性.md`
- [ ] `docs/worklog/2026-08-14-裁定D8-D11與PR12合併.md`
- [ ] `docs/worklog/2026-08-14-驗收maxturns事故.md`
- [ ] `docs/worklog/2026-08-15-CI對等性機制化.md`
- [ ] `docs/worklog/2026-08-15-PR29-review修正.md`
- [ ] `docs/worklog/2026-08-15-PR29驗收修正-送款位數閘門.md`
- [ ] `docs/worklog/2026-08-15-PSP單位邊界.md`
- [ ] `docs/worklog/2026-08-15-SKU索引降級.md`
- [ ] `docs/worklog/2026-08-15-allowlist語法修正.md`
- [ ] `docs/worklog/2026-08-15-codex改為只做驗收.md`
- [ ] `docs/worklog/2026-08-15-effort等級敘述更正.md`
- [ ] `docs/worklog/2026-08-15-limits-yaml布林鍵陷阱.md`
- [ ] `docs/worklog/2026-08-15-limits回歸測試覆蓋缺口.md`
- [ ] `docs/worklog/2026-08-15-mutation寫入地基.md`
- [ ] `docs/worklog/2026-08-15-userErrors契約對齊本尊.md`
- [ ] `docs/worklog/2026-08-15-workflow語法閘門.md`
- [ ] `docs/worklog/2026-08-15-冪等指紋.md`
- [ ] `docs/worklog/2026-08-15-商品四態UNLISTED.md`
- [ ] `docs/worklog/2026-08-15-執行位元閘門抽出與補洞.md`
- [ ] `docs/worklog/2026-08-15-對等性檢查器補上反向證明.md`
- [ ] `docs/worklog/2026-08-15-建店預設管道.md`
- [ ] `docs/worklog/2026-08-15-引用保真與執行位元.md`
- [ ] `docs/worklog/2026-08-15-業務邏輯十五章考掘.md`
- [ ] `docs/worklog/2026-08-15-業務邏輯總綱合成.md`
- [ ] `docs/worklog/2026-08-15-水位漏改造成的假診斷.md`
- [ ] `docs/worklog/2026-08-15-金額CI執法.md`
- [ ] `docs/worklog/2026-08-15-金額值物件R1R4.md`
- [ ] `docs/worklog/2026-08-15-驗收fallback四路分辨.md`
- [ ] `docs/worklog/2026-08-15-驗收失敗的假歸因.md`
- [ ] `docs/worklog/2026-08-15-驗收失敗看不到原因.md`
- [ ] `docs/worklog/2026-08-15-驗收恢復後的兩項修正.md`
- [ ] `docs/worklog/2026-08-15-驗收模型改回Opus5.md`
- [ ] `docs/worklog/2026-08-15-驗收機器人推理強度.md`
- [ ] `docs/worklog/2026-08-15-驗收閉環收斂機制.md`
- [ ] `docs/worklog/2026-08-15-驗收閉環第四種失效.md`
- [ ] `docs/worklog/2026-08-15-驗收閉環舊結論復用.md`
- [ ] `docs/worklog/2026-08-16-T1實測-變體刪除語義.md`
- [ ] `docs/worklog/2026-08-16-T4實測-最後一個變體.md`
- [ ] `docs/worklog/2026-08-16-變體選項join表.md`
- [ ] `docs/worklog/2026-08-16-鐵律13-14與驗收改制.md`
- [ ] `docs/worklog/2026-08-16-驗收判詞改制.md`
- [ ] `docs/worklog/2026-08-16-驗收只會通過的根因.md`
- [ ] `docs/worklog/2026-08-16-驗收模型改回fable5.md`
- [ ] `docs/worklog/2026-08-16-黃燈清理.md`
- [ ] `docs/worklog/2026-08-17-鐵律15提交前復核.md`
- [ ] `docs/worklog/README.md`
- [ ] `docs/worklog/2026-08-17-91坑登記簿骨架.md`（本 PR 新增，第 2 輪補列）
- [ ] `docs/worklog/2026-08-18-P00-public安全補課.md`（PR #57 新增；#58 第 6 輪補列——#57 未動本檔＝集合比對缺口實例）
- [ ] `docs/worklog/2026-08-18-P0-方案落庫與鐵律16-18.md`（PR #58 新增，第 6 輪補列）
- [ ] `docs/worklog/2026-08-18-P8-自動化基建.md`（PR #59 合併帶入；#58 R29 🔴1 補列）
- [ ] `docs/worklog/2026-08-19-P8補審-approve綁定斷言更正.md`（PR #60 新增；PR-1 D1 修復補列）
- [ ] `docs/worklog/2026-08-19-PR60-第十輪驗收修復.md`（PR #60 新增；PR-1 D1 修復補列）
- [ ] `docs/worklog/2026-08-19-PR58-R29驗收修復.md`（PR #58 R29 接手輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-新head驗收修復.md`（PR #58 `0db8ef5` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第二次新head驗收修復.md`（PR #58 `e2e5db7` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第三次新head驗收修復.md`（PR #58 `811a5e2` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第四次新head驗收修復.md`（PR #58 `427e11f` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第五次新head驗收修復.md`（PR #58 `4856da2` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第六次新head驗收修復.md`（PR #58 `bda2455` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第七次新head驗收修復.md`（PR #58 `e2c3573` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第八次新head驗收修復.md`（PR #58 `4335450` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-19-PR58-第九次新head驗收修復.md`（PR #58 `7aadf4ae` 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-20-PR60-第十一輪rebase契約同步.md`（PR #60 新增；PR-1 D1 修復補列）
- [ ] `docs/worklog/2026-08-20-PR61-首輪驗收修復.md`（PR #61 驗收輪新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-20-PR61-第二輪驗收修復.md`（PR #61 第二輪驗收新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-20-PR61-第三輪驗收修復.md`（PR #61 第三輪驗收新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-20-PR61-第四輪驗收修復.md`（PR #61 第四輪驗收新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-20-階段一開場包.md`（PR-1 新增，同 commit 補列）
- [ ] `docs/worklog/2026-08-20-鐵律19零假設發布.md`（PR #61 使用者新裁定，同 commit 補列）
- [ ] `docs/worklog/2026-08-20-PR61-Codex當前head驗收修復.md`（PR #61 current-head Codex 六條，同 commit 補列）
- [x] `docs/worklog/2026-08-20-PR61-Codex-96ffc01驗收修復.md`（PR #61 Codex review `4978735798`；已讀並抽取三項坑）
- [x] `docs/worklog/2026-08-20-鐵律20重犯斷根.md`（D34／鐵律 20；已讀並抽取跨輪重犯根因）
- [x] `docs/worklog/2026-08-20-PR61-Codex-5cea329驗收修復.md`（PR #61 review `4978950448`；已讀並處置三則 current-head inline）
- [x] `docs/worklog/2026-08-20-鐵律21逐步交接沿革查證.md`（D35 前置沿革與影響面；已讀，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-鐵律21本機MySQL與閘門復驗.md`（本機環境與假綠撤回；已抽取 Windows setup wrapper 缺口）
- [x] `docs/worklog/2026-08-20-鐵律21逐步交接落地.md`（D35／鐵律 21；已讀，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-鐵律21遠端終態收斂.md`（D35 遠端終態防自失效；已讀，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-鐵律21閘門Shell路徑復驗.md`（Windows Bash 路徑假失敗；已抽取環境坑）
- [x] `docs/worklog/2026-08-20-Claude-Fable5額度回退Opus5.md`（PR #62 兩次 attempt 逐字同報 Fable 5 limit；依 workflow 沿革⑦的既定處置切回 Opus 5，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-PR63首輪驗收修復.md`（review `4984000690`；全稱句已加可重跑範圍更正；handoff 意見依使用者 2026-08-20 裁定不修；D36 已隨 PR #62 於 2026-08-20 合併進 main，merge commit `0fbe520502588b34f9b9cad6ae9b3a282d4db643`，複驗：`gh pr view 62 --repo pisceshei/chilllovesaas --json state,headRefOid,mergeCommit,mergedAt`；沒有新增坑項）
- [x] `docs/worklog/2026-08-20-PR63第二輪驗收修復.md`（review `4984304467`；補清 D36 未合併邊界與驗證數字的日期／head snapshot，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-PR61-Codex-2ed2403驗收修復.md`（review `4979564233`；五則 current-head inline 已逐項處置）
- [x] `docs/worklog/2026-08-20-PR61-Rails冷啟動閘門復驗.md`（29 閘門首跑的 system spec 假紅；已抽取冷啟動等待競態）
- [x] `docs/worklog/2026-08-20-PR61-commit後doc-claims修復.md`（commit 後檢查轉紅；已修三個被點名宣稱）
- [x] `docs/worklog/2026-08-20-PR61-postcommit警告修復.md`（post-commit R5 warning；已移除自我重複觸發詞）
- [x] `docs/worklog/2026-08-20-PR61-Codex-35c9eea修復查證.md`（review `4979980175` 修法前查證；已抽取 PowerShell UTC 篩選坑）
- [x] `docs/worklog/2026-08-20-PR61-Codex-35c9eea驗收修復.md`（review `4979980175` 五則 inline 修復；已讀，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-PR61-Codex-35c9eea閘門復驗.md`（Git Bash PATH 修正後完整 29 閘門；既有坑涵蓋，無新增項）
- [x] `docs/worklog/2026-08-20-PR61-本機MySQL當前查活.md`（當前 MySQL／Rails A/B 查活；受限層根因已由 §3.5 既有條目涵蓋）
- [x] `docs/worklog/2026-08-20-PR61-Codex-44ebd39延遲意見修復查證.md`（review `4980284182` 修法前查證；已抽取總結先於 inline 的終態坑）
- [x] `docs/worklog/2026-08-20-PR61-Codex-44ebd39延遲意見修復.md`（review `4980284182` 兩則延遲 inline 精準修復；既有坑涵蓋，無新增項）
- [x] `docs/worklog/2026-08-20-PR61-Codex-44ebd39延遲意見閘門復驗.md`（完整 29 閘門；已抽取 Windows Python App Alias 假直譯器）
- [x] `docs/worklog/2026-08-20-PR61-Codex-b96426f殘留層級修復.md`（current-head P1；同一語義的證據段與摘要同步收斂，既有坑涵蓋）
- [x] `docs/worklog/2026-08-20-PR61-Codex-b96426f七則延遲意見修復查證.md`（review `4980533036` 七則 inline 修法前查證；既有坑涵蓋）
- [x] `docs/worklog/2026-08-20-PR61-Codex-b96426f七則延遲意見修復.md`（review `4980533036` 七則 inline 精準修復；既有坑涵蓋）
- [x] `docs/worklog/2026-08-20-PR61-Codex-b4bd731促銷疊加修復查證.md`（exact-head comment `5353555384` 修法前查證；已抽取 combinations 快照漂移坑）
- [x] `docs/worklog/2026-08-20-PR61-Codex-b4bd731驗收修復.md`（exact-head comment `5353555384`＋review `4980786354`；兩個 P1 精準修復，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-PR61-Codex-5a70431七則驗收修復查證.md`（review `4981088935` 七則 inline 修法前查證；已抽取總方案兩個同型坑）
- [x] `docs/worklog/2026-08-20-PR61-Codex-5a70431七則驗收修復.md`（review `4981088935` 七則 inline 精準修復；既有坑涵蓋，無新增項）
- [x] `docs/worklog/2026-08-20-handoff工作單位節奏與本地保存更正.md`（D36 恢復工作單位節奏；新 handoff 改為倉庫外本地保存，沒有新增坑項）
- [x] `docs/worklog/2026-08-20-PR62首輪驗收修復.md`（Codex review `4982782311` 與 Claude comment `5356127623`；D36 延後消費者及凍結 handoff 待辦已落 §3）
- [x] `docs/worklog/2026-08-20-PR62第二輪驗收修復.md`（Codex inline `3821829610` 與 Claude comment `5356457527` 同件；REST／GraphQL 重取入口已補，未新增 §3 項）
- [x] `docs/worklog/2026-08-20-PR62第三輪驗收修復.md`（Codex review `4983293473` 三則 inline 與 Claude comment `5356779594` 同三根因；延後包與精確錨已補）
- [x] `docs/worklog/2026-08-20-PR62第三輪post-commit警告修復.md`（commit `f6c9b7a` 後 doc-claims 命中一則 R5；已在原處補查法，未新增 §3 項）
- [x] `docs/worklog/2026-08-20-PR62第三輪post-commit警告第二次修復.md`（commit `93a02cd` 後同一 R5 仍在；已按 checker 鄰近窗口補查法，未新增 §3 項）
- [x] `docs/worklog/2026-08-21-驗收收斂制度V2.md`（D37／Convergence Protocol v2；已讀，根因與固定處理已落 `docs/dev/m0-review-convergence.md`；已抽取閘門總數、Changes 自含、Markdown 複驗與臨時表名等 §3 項）

- [x] `docs/worklog/2026-08-20-P8證據來源與合併後文件債收斂.md`（PR #62 exact-head review `4983737311` 的兩則 inline 與 PR #62 合併後終態已逐項收斂；PR #64 驗收令反查射程收窄，候選歷史債經官方語義複驗證偽）
- [x] `docs/worklog/2026-08-21-PR64首輪Claude驗收修復.md`（issue comment `5358544615` 的射程意見已清；暫登 §3 候選於第二輪經語義複驗撤回）
- [x] `docs/worklog/2026-08-21-PR64第二輪雙驗收修復.md`（Claude comment `5359209200`＋Codex review `4985307122`；PR 描述、歷史更正格式、外部事實與假債已逐項收斂）
- [x] `docs/worklog/2026-08-21-PR64第三輪雙驗收修復.md`（Claude comment `5359558626`＋Codex review `4985595726`；20.3 缺件、A9／A10 證據邊界與易腐計數已處置）
- [x] `docs/worklog/2026-08-21-PR64第四輪雙驗收修復.md`（Claude comment `5359997378`＋Codex review `4985973166`；累積清單回歸、終態 Changes 與範圍外登記已處置）
- [x] `docs/worklog/2026-08-21-PR64第五輪雙驗收修復.md`（Claude comment `5360279873`＋Codex review `4986192842`；終態集合遞迴過期、20.4 復發閉環與本輪文件意見已處置）
- [x] `docs/worklog/2026-08-21-PR64第六輪雙驗收修復.md`（Claude comment `5360596028`＋Codex review `4986421292`；穩定基準、可重跑渲染、動態集合與 A9／91 證據邊界已處置）
- [x] `docs/worklog/2026-08-21-PR64第七輪雙驗收修復.md`（Claude comment `5360974435`＋Codex review `4986687378`；HEAD-only 集合、multiplicity、A9 歷史更正與 91 假衝突已處置）
- [x] `docs/worklog/2026-08-21-PR64第八輪Codex驗收修復.md`（Codex review `4987003396`；A9 完整取頁／GraphQL 游標契約與 A10 超限 fallback 逐字已補）
- [x] `docs/worklog/2026-08-21-PR64第八輪Claude晚到驗收修復.md`（Claude comment `5361414731`；跨日期 PR64 worklog 漏列改為 fail-closed 並加承重 mutation）
- [x] `docs/worklog/2026-08-21-PR64第九輪Codex驗收修復.md`（Codex review `4987319876`／inline `3825320726`；歷史 worklog 刪除／改名改為 fail-closed 並加雙 mutation）
- [x] `docs/worklog/2026-08-21-PR64第十輪Claude驗收修復.md`（Claude comment `5361847317`；20.3 類型名與歷史 snapshot 改用相鄰更正收斂）
- [x] `docs/worklog/2026-08-21-PR64第十一輪雙驗收修復.md`（Claude comment `5362492718`＋Codex review `4987731284`；destructive history producer、20.3 固定編號與 rendering 未取得已處置）
- [x] `docs/worklog/2026-08-21-PR64第十二輪雙驗收修復.md`（Claude comment `5363200002`＋Codex review `4988295763`；零掃描 canary、merge diff、rendering 歷史更正與外部契約集中已處置）
- [x] `docs/worklog/2026-08-21-PR64第十三輪雙驗收修復.md`（Claude comment `5363469305`＋Codex review `4988472500`；production wiring、外部契約去重與 `diff-tree -r` witness 已處置）
- [x] `docs/worklog/2026-08-21-PR64第十四輪雙驗收修復.md`（Claude comment `5363665327`＋Codex review `4988636859`；repository commits fallback 與 `gh api` body 供給邊界已處置）
- [x] `docs/worklog/2026-08-21-PR64第十五輪Claude驗收修復.md`（Claude comment `5363892357`；⚪ 落籍、20.3 實跑輸出與 A10／B9 官方逐字已處置）
- [x] `docs/worklog/2026-08-22-PR64第十六輪雙驗收修復.md`（Claude comment `5364180385`＋Codex review `4988979665`；B9 逐句歸屬、B10 條件逐字、W14 歷史表還原與 `th=` 計數式錨定已處置）
- [x] `docs/worklog/2026-08-22-PR64第十七輪雙驗收修復.md`（Claude comment `5379467830`＋Codex review `4999795981`；W15 就地改寫還原、A.1 漏列、R5 警告與窗口實測不一致已處置）

<!-- 🔴 2026-08-22 補列（來源＝Claude issue comment `5379467830` 🔴-2 ＋ Codex inline `3835660386`）：
     第十六輪那一列**在該 worklog 誕生的同一個 commit（`53d346b`）就該加上**——本節上方
     「新增 tracked worklog 的同一 commit 必須同步補列本清單」正是為了擋這件事，
     且它是第 2 輪才加嚴的（原文「之後隨輪補列」擋不住同 commit 新增檔漏列）。
     ⇒ **條文擋住了它要擋的形態，漏的是執行**：我當輪沒有把「本 commit 有沒有新增 tracked
     worklog」列進送驗前稽核。
     可重跑反向複驗＝**本節上方既有的那組 canonical 全量雜湊**（內容錨＝
     `grep -n 'ls-files docs/worklog docs/handoff' docs/specs/91-pit-register.md`），
     兩式 md5 相等即通過。本輪實跑：相等。
     另以集合差再驗一次（同一結論、不同表述）：
       comm -23 <(git -c core.quotepath=false ls-files 'docs/worklog/*.md' | sort) \
                <(grep -oP '^- \[[x ]\] `\K[^`]+' docs/specs/91-pit-register.md \
                    | grep '^docs/worklog/' | sort)
     以及反方向 `comm -13`，**兩向皆為空集合**（實測：tracked 160、A.1 條目 160）。 -->
<!-- 🔴 2026-08-22 更正之二（來源＝PR #64 Codex inline `3835780547`）：
     上一則註曾把射程收窄成「只檢查本 PR 新增的 worklog」，理由是「A.1 是**漸進收割清單**，
     實測 tracked 159 份、A.1 條目 279 條」。**那個理由是我自己量錯**：
     `grep -oP '^- \[[x ]\] \`\K[^\`]+'` **沒有篩 `docs/worklog/` 前綴**，於是把 A.2 的
     handoff 條目一起數了進來（本輪重現：不篩＝279、篩了＝160）。
     🔴 **A.1 就是全量索引**：tracked worklog 160、A.1 條目 160，`comm` 兩向皆空；
     勾選符號才代表收割進度。⇒ 收窄射程**會讓「刪掉一列」不被察覺**，等於把閘門改弱。
     ⇒ 已還原為全量比對，並改用本節上方**既有的** canonical 全量雜湊（不另立新判準）。
     🔴 教訓：**收窄一道既有閘門之前，先確認要收窄的理由不是自己的測量誤差。** -->
<!-- 🔴 2026-08-22 補列（承上，來源＝`5379467830` 🔴-2）：第十六輪那一列在該 worklog
     誕生的同一個 commit 就該加上；條文擋住了它要擋的形態，漏的是執行——我當輪沒有把
     「本 commit 有沒有新增 tracked worklog」列進送驗前稽核。 -->

### A.2 handoff

- [ ] `docs/handoff/2026-08-12-carrier-integration.md`
- [ ] `docs/handoff/2026-08-12-follow-shopify-and-prototype-sync.md`
- [ ] `docs/handoff/2026-08-12-hk-baseline-p0-execution.md`
- [ ] `docs/handoff/2026-08-12-jurisdiction-architecture.md`
- [ ] `docs/handoff/2026-08-12-measurement-audit-p0p1-money-tax.md`
- [ ] `docs/handoff/2026-08-12-open-decisions.md`
- [ ] `docs/handoff/2026-08-12-product-1to1-and-money-boundary.md`
- [ ] `docs/handoff/2026-08-12-rulings-carrier-product-alignment.md`
- [ ] `docs/handoff/2026-08-12-ui-p0-batch-and-jurisdiction-sweep.md`
- [ ] `docs/handoff/2026-08-13-SESSION-EXPORT.md`
- [ ] `docs/handoff/2026-08-13-admin稽核第三輪與中止.md`
- [ ] `docs/handoff/2026-08-13-parity-R10市場.md`
- [ ] `docs/handoff/2026-08-13-parity-R3與RTE考證.md`
- [ ] `docs/handoff/2026-08-13-parity-R4財務帳單.md`
- [ ] `docs/handoff/2026-08-13-parity-R5顧客線.md`
- [ ] `docs/handoff/2026-08-13-parity-R6折扣.md`
- [ ] `docs/handoff/2026-08-13-parity-R7訂單線.md`
- [ ] `docs/handoff/2026-08-13-parity-R8產品線子頁.md`
- [ ] `docs/handoff/2026-08-13-parity-R9內容與線上商店.md`
- [ ] `docs/handoff/2026-08-13-完整性清單.md`
- [ ] `docs/handoff/2026-08-13-環境雲端與parity前四輪.md`
- [ ] `docs/handoff/2026-08-13-還原上雲與三輪清債.md`
- [ ] `docs/handoff/2026-08-13-開場白-給新的claude.md`
- [ ] `docs/handoff/2026-08-13-雲端接手指南.md`
- [ ] `docs/handoff/2026-08-14-A1撤銷術語.md`
- [ ] `docs/handoff/2026-08-14-A3快照欄.md`
- [ ] `docs/handoff/2026-08-14-A5發布模型.md`
- [ ] `docs/handoff/2026-08-14-merge-R11-R13.md`
- [ ] `docs/handoff/2026-08-14-parity-R11分析.md`
- [ ] `docs/handoff/2026-08-14-parity-R12設定.md`
- [ ] `docs/handoff/2026-08-14-parity-R13管道.md`
- [ ] `docs/handoff/2026-08-14-review回應與白名單修正.md`
- [ ] `docs/handoff/2026-08-14-原型P0修復與缺陷複驗.md`
- [ ] `docs/handoff/2026-08-14-欄位設定與逐檢視隔離.md`
- [ ] `docs/handoff/2026-08-14-死控件機制化.md`
- [ ] `docs/handoff/2026-08-14-裁定D8-D11與PR12合併.md`
- [ ] `docs/handoff/2026-08-15-CI對等性機制化.md`
- [ ] `docs/handoff/2026-08-15-PR1-schema對齊.md`
- [ ] `docs/handoff/2026-08-15-PR1寫入路徑地基.md`
- [ ] `docs/handoff/2026-08-15-limits回歸測試覆蓋缺口.md`
- [ ] `docs/handoff/2026-08-15-limits鍵型別機制化.md`
- [ ] `docs/handoff/2026-08-15-shopify業務邏輯總綱.md`
- [ ] `docs/handoff/2026-08-15-workflow語法閘門.md`
- [ ] `docs/handoff/2026-08-15-執行位元閘門抽出與補洞.md`
- [ ] `docs/handoff/2026-08-15-引用保真與執行位元.md`
- [ ] `docs/handoff/2026-08-15-驗收九輪不收斂.md`
- [ ] `docs/handoff/2026-08-15-驗收失敗的假歸因.md`
- [ ] `docs/handoff/2026-08-15-驗收模型改回Opus5.md`
- [ ] `docs/handoff/2026-08-15-驗收機器人全滅與復原.md`
- [ ] `docs/handoff/2026-08-15-驗收閉環修復與分工改制.md`
- [ ] `docs/handoff/2026-08-16-變體選項join表.md`
- [ ] `docs/handoff/2026-08-16-鐵律13-14與驗收改制.md`
- [ ] `docs/handoff/2026-08-16-驗收判詞改制.md`
- [ ] `docs/handoff/2026-08-16-黃燈清理.md`
- [ ] `docs/handoff/2026-08-17-鐵律15提交前復核.md`
- [ ] `docs/handoff/2026-08-17-phase0收官與codex59佇列交接.md`（本 PR 入庫；**59 條佇列＋47 條 live 清單來源檔，最密集收割源**，第 2 輪補列）
- [ ] `docs/handoff/2026-08-17-phase1開工與91骨架.md`（本 PR 新增，第 2 輪補列）
- [ ] `docs/handoff/2026-08-17-session交接-phase0收官與phase1首輪.md`（本 PR 第 2 輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-18-P00-public安全補課.md`（PR #57 新增；#58 第 6 輪補列）
- [ ] `docs/handoff/2026-08-18-P0-方案落庫與鐵律16-18.md`（PR #58 新增，第 6 輪補列）
- [ ] `docs/handoff/2026-08-18-P8-自動化基建.md`（PR #59 合併帶入；#58 R29 🔴1 補列）
- [ ] `docs/handoff/2026-08-19-鐵律遵守稽核與P8合併.md`（PR #58 第 29 輪新增；鐵律遵守稽核＋P-8 合併紀錄）
- [ ] `docs/handoff/2026-08-19-驗收方外部語義與研究前置.md`（PR #58 第 35 輪新增；#58 R29 🔴1 補列）
- [ ] `docs/handoff/2026-08-19-全專案交接-階段0收官與codex接手.md`（PR #58 第 41 輪後新增；#58 R29 🔴1 補列）
- [ ] `docs/handoff/2026-08-19-PR58-R29驗收修復.md`（PR #58 R29 接手輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-新head驗收修復.md`（PR #58 `0db8ef5` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第二次新head驗收修復.md`（PR #58 `e2e5db7` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第三次新head驗收修復.md`（PR #58 `811a5e2` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第四次新head驗收修復.md`（PR #58 `427e11f` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第五次新head驗收修復.md`（PR #58 `4856da2` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第六次新head驗收修復.md`（PR #58 `bda2455` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第七次新head驗收修復.md`（PR #58 `e2c3573` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第八次新head驗收修復.md`（PR #58 `4335450` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR58-第九次新head驗收修復.md`（PR #58 `7aadf4ae` 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-19-PR60-第十輪驗收修復.md`（PR #60 新增；PR-1 D1 修復補列）
- [ ] `docs/handoff/2026-08-20-PR60-第十一輪rebase契約同步.md`（PR #60 新增；PR-1 D1 修復補列）
- [ ] `docs/handoff/2026-08-20-PR61-首輪驗收修復.md`（PR #61 驗收輪新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-20-PR61-第二輪驗收修復.md`（PR #61 第二輪驗收新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-20-PR61-第三輪驗收修復.md`（PR #61 第三輪驗收新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-20-PR61-第四輪驗收修復.md`（PR #61 第四輪驗收新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-20-階段一開場包.md`（PR-1 新增，同 commit 補列）
- [ ] `docs/handoff/2026-08-20-鐵律19零假設發布.md`（PR #61 使用者新裁定，同 commit 補列）
- [ ] `docs/handoff/2026-08-20-PR61-Codex當前head驗收修復.md`（PR #61 current-head Codex 六條，同 commit 補列）
- [x] `docs/handoff/2026-08-20-PR61-Codex-96ffc01驗收修復.md`（PR #61 Codex review `4978735798`；已讀並抽取三項坑）
- [x] `docs/handoff/2026-08-20-鐵律20重犯斷根.md`（D34／鐵律 20；已讀並抽取跨輪重犯根因）
- [x] `docs/handoff/2026-08-20-PR61-Codex-5cea329驗收修復.md`（PR #61 review `4978950448`；已讀並處置三則 current-head inline）
- [x] `docs/handoff/2026-08-20-鐵律21逐步交接沿革查證.md`（D35 前置沿革與影響面；已讀，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-鐵律21本機MySQL與閘門復驗.md`（本機環境與假綠撤回；已抽取 Windows setup wrapper 缺口）
- [x] `docs/handoff/2026-08-20-鐵律21逐步交接落地.md`（D35／鐵律 21；已讀，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-鐵律21遠端終態收斂.md`（D35 遠端終態防自失效；已讀，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-鐵律21閘門Shell路徑復驗.md`（Windows Bash 路徑假失敗；已抽取環境坑）
- [x] `docs/handoff/2026-08-20-PR61-Codex-2ed2403驗收修復.md`（review `4979564233`；五則 current-head inline 已逐項處置）
- [x] `docs/handoff/2026-08-20-PR61-Rails冷啟動閘門復驗.md`（29 閘門首跑的 system spec 假紅；證據與邊界已交接）
- [x] `docs/handoff/2026-08-20-PR61-commit後doc-claims修復.md`（commit 後檢查轉紅；命中與修法已交接）
- [x] `docs/handoff/2026-08-20-PR61-postcommit警告修復.md`（post-commit R5 warning；證據與邊界已交接）
- [x] `docs/handoff/2026-08-20-PR61-Codex-35c9eea修復查證.md`（review `4979980175` 修法前查證；已抽取 PowerShell UTC 篩選坑）
- [x] `docs/handoff/2026-08-20-PR61-Codex-35c9eea驗收修復.md`（review `4979980175` 五則 inline 修復；已讀，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-PR61-Codex-35c9eea閘門復驗.md`（Git Bash PATH 修正後完整 29 閘門；既有坑涵蓋，無新增項）
- [x] `docs/handoff/2026-08-20-階段一-PR61-本機MySQL當前查活.md`（當前 MySQL／Rails A/B 查活；既有坑涵蓋，無新增項）
- [x] `docs/handoff/2026-08-20-PR61-Codex-44ebd39延遲意見修復查證.md`（review `4980284182` 修法前查證；已抽取總結先於 inline 的終態坑）
- [x] `docs/handoff/2026-08-20-PR61-Codex-44ebd39延遲意見修復.md`（review `4980284182` 兩則延遲 inline 精準修復；已讀，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-PR61-Codex-44ebd39延遲意見閘門復驗.md`（完整 29 閘門；已抽取 Windows Python App Alias 假直譯器）
- [x] `docs/handoff/2026-08-20-PR61-Codex-b96426f殘留層級修復.md`（current-head P1；已讀並同步同語義兩端，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-PR61-Codex-b96426f七則延遲意見修復查證.md`（review `4980533036` 七則 inline 修法前查證；已讀，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-PR61-Codex-b96426f七則延遲意見修復.md`（review `4980533036` 七則 inline 精準修復；已讀，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-PR61-Codex-b4bd731促銷疊加修復查證.md`（exact-head comment `5353555384` 修法前查證；已抽取 combinations 快照漂移坑）
- [x] `docs/handoff/2026-08-20-PR61-Codex-b4bd731驗收修復.md`（exact-head comment `5353555384`＋review `4980786354`；兩個 P1 精準修復，沒有新增坑項）
- [x] `docs/handoff/2026-08-20-PR61-Codex-5a70431七則驗收修復查證.md`（review `4981088935` 七則 inline 修法前查證；已抽取總方案兩個同型坑）
- [x] `docs/handoff/2026-08-20-PR61-Codex-5a70431七則驗收修復.md`（review `4981088935` 七則 inline 精準修復；既有坑涵蓋，無新增項）

### A.3 事故密集檔（specs／機制檔）

- [ ] `docs/specs/49-ui-gap-register.md`
- [ ] `docs/specs/50-logic-gap-register.md`
- [ ] `docs/specs/51-token-conformance.md`
- [ ] `docs/specs/53-ui-gap-recheck.md`
- [ ] `docs/specs/84-m1-gate-triage.md`
- [ ] `docs/specs/89-prototype-defect-reverify.md`
- [ ] `docs/specs/71-admin-parity-sweep.md` §F（V 項全表；（第 3 輪更正）：原誤寫 `71-parity-register.md`——與 A.3 前五格同批「憑印象寫」，第 2 輪漏改此格）
- [ ] `.github/workflows/claude-review.yml`（🔴 全檔註釋＝最密集事故檔之一）
- [ ] `.github/workflows/ci.yml`（同上）
- [ ] `scripts/*` 檔頭 docstring（複驗：`ls scripts/`，逐支）

A.3 名單複驗（第 7 輪補——集合比對僅覆蓋 A.1/A.2，本節原靠人工）：下式輸出應為空：

```bash
grep -E '^- \[.\] ' docs/specs/91-pit-register.md | grep -oE '(docs/specs|\.github/workflows)/[^`]+' | while read f; do git -c core.quotepath=false ls-files --error-unmatch "$f" >/dev/null 2>&1 || echo "MISSING: $f"; done
```

### A.4 抽樣復讀記錄（完成判準）

（收割完成後填：抽樣檔名 ×5、復讀日、漏抓數——漏抓率非 0 ⇒ 全清單重讀）
