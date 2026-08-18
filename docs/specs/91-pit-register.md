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
| G-01 | 判詞 ⚪ 落籍檢查——每輪判詞的 ⚪ 條目在本檔 §3 有對應（PR #55 判詞連續多輪點名此缺口） | ⚪ 蒸發族（§3.3「兩源句腐化」組的上游——⚪ 無人搬運即消失） | 判詞為自由文本、需解析 ⚪ 段與 §3 對條，格式耦合高；誤報時擋錯 PR | **待**（收割輪一併裁） |
| G-02 | markdown 柵欄自檢——掃全檔行首三反引號行：行數須偶數、每個閉合行去圍欄後為空（式子＝#55 第 7 輪判詞所給；防柵欄黏尾文吞段） | 柵欄事故族（#55 第 7 輪 151 checkbox 被吞＝現行犯） | 極低（一支 grep/awk 即可）；範圍限 docs/specs（或全 docs） | **待**（收割輪與 G-01 一併裁；第 9 輪登記） |
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

> 🔴 **新增 worklog/handoff 的同一 commit 必須同步補列本清單**（第 2 輪改——原
> 「之後隨輪補列」擋不住同 commit 新增檔漏列：本 PR 首版即漏了自己的 3 檔，
> 其中 phase0 交接檔正是最密集的收割源）。

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
