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
  🔴 **機械化候選**：現行表格結構斷言只涵蓋「本輪改動的表格」，抓不到既有檔；候選是把
  「表格列含未跳脫直線」做成**不限改動檔的全樹檢查**，代價與裁定併入 §2 待裁列
  【F7/F11；來源＝PR #66 Claude issue comment `5371707612` ⚪1；取證日期＝2026-08-21】

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
- [x] `docs/worklog/2026-08-20-PR63首輪驗收修復.md`（review `4984000690`；全稱句已加可重跑範圍更正；handoff 意見依使用者 2026-08-20 裁定不修，D36 尚只在未合併 PR #62 head `5209087`，沒有新增坑項）
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
