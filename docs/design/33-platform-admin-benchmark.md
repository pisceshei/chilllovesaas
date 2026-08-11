# 33 — 平台總控後台競品拆解與迭代方案

> 32 號寫的是「我們第一版打算做什麼」；本篇是**對照八家以上真實平台之後，重寫的目標盤**。原型 v1（`chilllove-platform-admin.html` 初版）只有 6 區、約 36 個控件，對照下來缺口是**結構性的**——不是少幾個按鈕，是少了整個租戶生命週期、金流治理、信任安全、合規營運四條線。本篇給出模組矩陣、關鍵機制數值、迭代波次 W1–W5 與驗收要點。原型 v2 依本篇實作。

調研對象：Shopify（Plus Organization／Partners／商店生命週期／計費催繳／AUP 執法／狀態頁／App 審核）、SHOPLINE、CYBERBIZ／meepShop／EasyStore／WACA／91APP、有贊、微盟、店匠 Shoplazza、Salesforce B2C Commerce（Business Manager）、commercetools、VTEX、BigCommerce、Adobe Commerce Cloud、Saleor Cloud、Shopware、Medusa Cloud、Stripe Connect、Vercel／Okta／Auth0／Atlassian、Statuspage、LaunchDarkly。來源見 §10。

---

## 1. 模組矩陣（✅有／△部分／—無；「我們 v1」為對照基準）

| 模組 | Shopify | 有贊 | 店匠 | SHOPLINE | SFCC | Stripe Connect | 我們 v1 | 目標 |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| 租戶列表／詳情 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | △ | **W1** |
| 多態生命週期（≥8 態） | ✅ | ✅ | ✅ | △ | — | ✅ | — | **W1** |
| 分級凍結（收款／提現／交易／唯讀／下線） | △ | ✅ | ✅ | △ | — | ✅ | — | **W1** |
| 開店審核／KYC 佇列 | — | ✅ | ✅ | ✅ | — | ✅ | — | **W1** |
| 補件 requirements 模型（due/past_due/deadline） | — | △ | △ | △ | — | ✅ | — | **W1** |
| 計費與催繳 dunning | ✅ | ✅ | ✅ | ✅ | — | ✅ | — | **W1** |
| 兩層權限（組織／商店，不繼承） | ✅ | ✅ | △ | △ | ✅ | ✅ | — | **W1** |
| 授權式代登入（非直接 impersonate） | ✅ | △ | △ | ✅ | — | △ | — | **W1** |
| 審計日誌（before/after、可匯出） | △ | ✅ | △ | — | ✅ | ✅ | △ | **W1** |
| 金流通道／MCC／費率／清結算 | ✅ | ✅ | ✅ | ✅ | — | ✅ | — | **W2** |
| 保留金／負餘額／撥款排程 | ✅ | ✅ | ✅ | ✅ | — | ✅ | — | **W2** |
| 爭議與卡組織門檻監控 | ✅ | △ | △ | △ | — | ✅ | — | **W2** |
| 違規處置階梯＋積分 | ✅ | ✅ | △ | △ | — | ✅ | — | **W2** |
| 申訴工作流 | ✅ | ✅ | △ | △ | — | △ | — | **W2** |
| 工單／客服 | ✅ | ✅ | ✅ | ✅ | — | ✅ | — | **W2** |
| 配額 entitlement 三段式 | △ | ✅ | △ | ✅ | ✅ | — | △ | **W2** |
| 對外狀態頁＋維護視窗 | ✅ | — | — | — | — | ✅ | — | **W3** |
| Feature flag 灰度／kill switch | △ | — | — | — | — | — | △ | **W3** |
| DSR 資料主體請求佇列 | ✅ | — | — | — | — | ✅ | — | **W3** |
| 電子發票管線（台灣） | — | — | — | ✅ | — | — | — | **W3** |
| 公告／API 棄用通知 | ✅ | ✅ | △ | △ | — | ✅ | — | **W3** |
| 環境（sandbox/staging/prod） | — | — | — | — | ✅ | — | — | **W4** |
| 備份與自助還原 | — | — | — | — | △ | — | — | **W4** |
| 版本部署與回滾 | — | — | — | — | ✅ | — | — | **W4** |
| Job 排程器 | — | — | — | — | ✅ | — | — | **W4** |
| 代理商／服務商分潤 | ✅ | ✅ | △ | ✅ | — | — | — | **W5** |
| 集團／連鎖母子店 | ✅ | ✅ | △ | △ | — | ✅ | — | **W5** |
| 批次升級與配置下發 | — | — | — | — | ✅ | — | — | **W5** |
| 權限定期複核 campaign | — | — | — | — | — | — | — | **W5** |

**結論**：v1 命中率約 15%。金流治理與信任安全兩條線是**完全空白**，而這兩條正是「可運營」的實際門檻——不是功能不足，是出事沒有處理台。

---

## 2. 關鍵機制詞典（可直接寫進實作的數值）

### 2.1 租戶狀態與副作用（綜合 Shopify／店匠／有贊）

| 狀態 | 前台 | 商家後台 | 金流 | 資料/時效 |
|---|---|---|---|---|
| `draft` 草稿 | 未開通 | 只能填資料 | — | 30 天未提交自動清 |
| `pending_review` 待審 | 未開通 | 唯讀＋審核中橫幅 | — | 目標 5–7 工作天（SHOPLINE 實測值） |
| `info_required` 補件 | 未開通 | 可補件 | — | 逾期未補 → 駁回 |
| `rejected` 駁回 | 未開通 | 可看原因、可重送 | — | 原因碼字典見 §2.2 |
| `trial` 試用 | 正常 | 正常（部分模組鎖） | 測試模式 | 14 天，到期→ `past_due` |
| `active` 正式 | 正常 | 正常 | 正常 | — |
| `past_due` 逾期 | 正常 | 正常＋催繳橫幅 | 正常 | 首次扣款失敗起算，**28 天**未付→ `frozen`（Shopify 線） |
| `restricted` 受限 | 依處分 | **有限**：可看帳單、可提申訴、可換銀行帳號 | 停收款 | **受限期間暫停計費**（Shopify 明確做法） |
| `paused` 暫停營業 | 商品可看、**結帳關閉** | 可用，但折扣／棄單挽回／禮品卡／第三方通路停 | 停 | 無時限（Shopify Pause and build） |
| `frozen` 凍結 | 顧客看不到（503＋noindex） | **不可進**，但**帳單頁仍可讀**；**30 天後訂單狀態頁自動恢復**供顧客查單 | 停 | 付清即解；超 30 天須重選方案 |
| `closed` 關閉 | 410 | 本期帳單週期結束後失去存取 | 結清 | **資料保留 2 年**可復店；**子網域永久不可重用** |
| `deleted` 註銷 | — | — | — | 不可逆；審計去識別化保留 |

**兩個必須保留的例外**（漏了客服會被打爆）：`frozen` 時①帳單與發票歷史仍可讀②顧客訂單狀態頁 30 天後恢復。

### 2.2 分級凍結（六個獨立開關，可組合、可設到期）

`收款凍結`｜`提現凍結`｜`交易凍結`｜`後台唯讀`｜`前台下線`｜`帳號查封`。
店匠的關鍵洞察：**補件期間「收入暫停但店鋪仍可運營」**——單一 boolean 凍結是錯的模型。

駁回原因碼字典（SHOPLINE 五大退件原因為底）：`SITE_INFO_INCOMPLETE` 官網未揭露公司資訊／`NO_PRIVACY_POLICY` 缺隱私權政策／`SCOPE_MISMATCH` 營業項目與實售不符／`SITE_NOT_LIVE` 網站未上線／`BANK_NAME_MISMATCH` 撥款帳戶名稱與登記名不符／`DOC_EXPIRED` 文件過期／`DOC_UNREADABLE` 文件不清晰／`UBO_MISSING` 缺最終受益人。

### 2.3 KYC requirements 模型（照抄 Stripe Connect）

```
requirements {
  currently_due[]        // 現在就要
  eventually_due[]       // 之後要
  past_due[]             // 已逾期（會觸發停權）
  pending_verification[] // 已交待審
  disabled_reason        // rejected.fraud / rejected.listed /
                         // rejected.terms_of_service /
                         // rejected.incomplete_verification / rejected.other
  current_deadline       // 期限
  errors[] { code, requirement, reason }
}
future_requirements { ... 有自己的 deadline，到期整批搬進 requirements }
```
**佇列排序**：平台資訊請求 → `past_due` → `currently_due` → future → `eventually_due`。
**三種補救路徑**（每筆都要有）：代租戶提交／產生補件連結寄給租戶／升級為工單。

### 2.4 催繳 dunning 時程

首次扣款失敗 → 重試（節奏自定，建議 D+1／D+3／D+7／D+14）→ **D+28 凍結** → **凍結後 60 天** 保留終止帳號權利（Shopify 的兩條硬線）。
Shopify 明文：**不給延期、不改發票到期日**；替代方案是降方案／轉暫停營業／移除加購模組。後台需顯示**倒數天數**與**手動干預**（延長寬限、部分豁免、標記為協商中）。

### 2.5 爭議率門檻（平台必須逐租戶監控，否則替租戶扛罰款）

| 制度 | 門檻 | 罰則 |
|---|---|---|
| Visa VAMP Non-compliant | count ≥ 5 且 ratio ≥ **0.5%** | 可能收費 |
| Visa VAMP Excessive | ratio ≥ **1.5%** 且 count ≥ 1,500 | 必定收費 |
| MC ECM | 100–299 筆且 **1.5–2.99%** | 月2–3: 1,000 → 月19+: 100,000 USD |
| MC HECM | ≥300 筆且 **≥3%** | 月2: 1,000 → 月19+: 200,000 USD |
| MC EFM | ≥1,000 筆且淨詐欺 >50,000 USD 且爭議率 >**0.50%** | 月2: 500 → 月19+: 100,000 USD |
| Stripe 內部建議 | 爭議率 > **0.75%** 即過高 | — |

**計算口徑陷阱**：Visa 用同月分母；**Mastercard 用「本月爭議 ÷ 上月交易筆數」**。卡組織回報值延遲約 1 個月，UI 必須**雙欄並列**：卡組織回報值／我方即時估算值。Mastercard 需**連續 3 個月**低於門檻才除名。

### 2.6 撥款與資金（Stripe Connect ＋ SHOPLINE ＋ 店匠）

撥款週期 `manual/daily/weekly/monthly`＋`delay_days`（上限 31 天）＋每幣別最低餘額；台灣實務 **T+4 工作日**（SHOPLINE）。
保留金 `reserve`；**負餘額滿 180 天由平台餘額補平**（這條決定平台的損失上限，必須有畫面）。
合規性資金保留期：美國 2 年／泰國 10 天／其他 90 天。
爭議歸屬：direct charge 扣租戶；destination／separate charges **一律先扣平台**，再向租戶追回。

**台灣紅線**：《電子支付機構管理條例》——平台若代收代付並保管資金即落入特許範圍。**後台不得出現「平台錢包／提現」概念**，只能是「通道對帳與分潤結算」，租戶自持商戶號（平台僅存 MerchantID／HashKey／HashIV 做代理設定）。

### 2.7 違規處置階梯（有贊《商家管理規範》為最完整範本）

市場管控 5 項：警告／商品下架／限制參加營銷活動／單品監管／店鋪監管。
違規處理 11 項：警告／刪除商品／刪除店鋪主頁／刪除微頁面／限制社區功能／**強制退款**／限制參加平台活動／限制交易／**限制提現與轉帳**／**公示警告**／**查封帳戶**。
積分：**A 類（一般）／B 類（嚴重）雙軌獨立累計、分別執行**；自然年累計，未達 B 類 48 分者年底清零；恢復條件＝糾正全部違規＋處理措施執行完畢且期限屆滿。
Shopify 的執法階梯（更精簡）：內容下架 → 停用付款 → 限制 admin → 鎖店 → 終止帳號。
申訴：知識產權 3–7 工作天；狀態 `待審／補件／維持原判／撤銷處分`；須留審理人與證據。

### 2.8 審計日誌欄位（Vercel schema ＋ PCI 保留期）

`timestamp｜action（如 tenant.freeze）｜actor_id｜actor_name｜actor_email｜ip｜user_agent｜request_id｜previous(JSON)｜next(JSON)`
再加 Okta 的關聯維度：`outcome.result`、`transaction_id`（同一操作多事件串接）、`session_id`、`target_type/target_id`、`source（UI/API/自動化）`。
**保留期採 PCI DSS 10.5.1：至少 12 個月，最近 3 個月須可立即查詢**（同時滿足 SOC 2）。append-only，DB 層不授權 update/delete。

### 2.9 授權式代登入（取代無條件 impersonate）

照抄 Shopify collaborator request：租戶端產生 **4 位數授權碼**（重新產生即失效舊碼）→ 平台方輸入碼＋**逐項勾選需要的權限**＋附事由 → 租戶收信與站內通知，看到**依請求權限自動生成的角色**，可接受／拒絕 → 生效後**不佔租戶席次**、**90 天未使用自動失效**、隨時可撤銷、單一請求方 pending 上限 10。
再疊 Stripe 的時效：單次工作階段 **60 分鐘**、商家後台頂部持續橫幅、每個動作 `impersonated:true` 雙寫審計。
禁止動作：改商家密碼／email、超額退款、刪除商店。

### 2.10 配額三段式 enforcement（SFCC Quota Status）

`log_only`（只記錄）→ `warn`（**60% 門檻**上儀表板）→ `error`（**100% 擋下並拋例外**）。紅／橘／綠燈；每日違規摘要 email。
配額參考量級（SFCC／commercetools 實數）：Sites 100／Catalogs 200／Custom Objects 400,000／Promotions 10,000；commercetools：query fetch 500、max offset 10,000、GraphQL complexity 20,000、Stores 300,000。

### 2.11 Feature flag 生命週期（LaunchDarkly）

狀態 4 態（7 天窗）：`New`／`Active`／`Launched`（近 7 天只服務單一變體且為 on）／`Inactive`（≥7 天未被評估）。
生命週期（30 天窗）：`Live` → `Ready for code removal`（temporary、所有關鍵環境已 Launched、≥30 天、仍有 code reference）→ `Ready to archive`（已無 code reference）→ `Deprecated` → `Archived` → `Deleted`（必須先 archive）。
分階段推送狀態機（Vercel Rolling Releases）：`configured → started → approved（逐階段人工批准）→ completed`，另有 `aborted`＝kill switch。
定向維度用 **cohort**（方案／地區／GMV 級距／beta 名單），不是純百分比。

### 2.12 環境／部署／備份／升級（企業級四件事）

- **環境**：建議分支對映式（long-lived 綁 branch＋PR 自動 preview），環境數是計費維度。卡片顯示 `name/type/region/status/last activity`，動作 `Branch / Merge / Sync / Redeploy`。非正式環境**預設**關閉對外 email、擋搜尋引擎、還原後自動停用 webhook／app（Saleor 做法）。
- **部署**：保留 N 版（SFCC 預設 10，可設 3–20），active 與前一版永不清；**production 只准寫 inactive 再切換**；**Transfer → Publish 兩段式**；一鍵 Rollback。
- **備份**：**保留 7 天為業界基準線**（14 天與 PITR 為加價檔）；備份含 DB＋媒體、**不含程式碼**；環境刪除後備份寬限 7 天；**還原對話框必須顯示依資料量估算耗時**（Adobe 基準：60GB≈1h／150GB≈2.5h／200GB+≈5h）。
- **升級**：**patch 全自動／minor 租戶自選時機／major 手動遷移**（Saleor 與 Shopware 一致）；**不可跳版**，升級路徑由平台計算；維護視窗需**同時暫停 webhook 投遞**；每租戶顯示支援狀態四態（Maintained／Extended support／Security fixes only／EOL）。

### 2.13 資料合規時限

GDPR **1 個月**（複雜可延 2 個月，合計 3，且須在 1 個月內告知延期理由）；CCPA/CPRA **45 天**（可延 45）。
Shopify redact 模型：`customers/data_request`／`customers/redact`（近 6 個月有下單則延後，否則最少延遲 10 天）／`shop/redact`（解安裝後 48 小時），皆 HMAC 驗簽、**30 天內完成**。
台灣《數位經濟相關產業個資檔案安全維護管理辦法》：外洩 **72 小時內**依附表二通報數位部；蒐集處理利用紀錄與**自動化機器軌跡保存至少 5 年**；資本額 1,000 萬或個資 5,000 筆以上者**每 12 個月至少稽核一次**；**平台業者須訂定個資保護守則並要求租戶遵守**（→ 需「租戶合規承諾簽署與版本管理」模組）。

### 2.14 台灣落地專屬

- **電子發票**：加值中心（綠界／藍新）代辦字軌；**字軌餘量須自行監控**，耗盡即無法開立；**工商憑證效期 5 年，到期前 60 天內須重新申請**；開立時機三選一（付款／**出貨（建議）**／收貨）；全額取消自動作廢、部分退貨自動折讓。
- **稅籍與前台揭露**：達起徵點（2025/1/1 起貨物月銷 10 萬、勞務 5 萬）須辦稅籍登記，並於**銷售網頁揭露營業人名稱與統一編號**；稅籍須登錄網域與網路位址；**平台業者須保存並依請求提供會員交易資料**。
- **七天鑑賞期例外**七款（易腐／客製化／報紙期刊／已拆封影音軟體／非有形媒介數位內容／已拆封個人衛生用品／國際航空客運）→ 商品層需有「排除鑑賞期」旗標＋前台強制告知，平台需可巡檢濫用。
- **差異化機會**：**前台合規巡檢器**——自動爬租戶前台檢查營業人名稱＋統編、隱私政策、退換貨政策、鑑賞期告知，不合格自動開工單。西方平台沒有這個，台灣平台方卻有實質責任。

### 2.15 兩層權限模型（Shopify Plus）

組織層與商店層**完全獨立、互不繼承**。組織層權限僅 5 項：Stores／Business entities（**四級：View／View sensitive／Edit／Add**）／Billing（兩級）／Analytics overview／Feature test drives。
一人可掛多角色，**權限累加**；User group 批次綁定；四頁（Users／Roles／Groups／Activity logs）**皆可 CSV 匯出**。
**驗證網域擁有權後，可自助重設該網域使用者的 2FA**——這條能砍掉大量客服工單。
SFCC 的三軸補充：模組權限／功能動作權限／語系權限，且可 scope 到單站。
VTEX 的關鍵設計：**role = resource 集合，且人與程式（API key）共用同一套 resource 詞彙表**。

---

## 3. 目標資訊架構（原型 v2 的 16 區）

```
營運    ├ 總覽（可行動佇列儀表板）
        ├ 租戶（列表 → 詳情 10 分頁）
        ├ 審核佇列（KYC／補件／駁回）
        └ 工單
金流    ├ 計費與催繳
        ├ 清結算（通道／撥款／保留金／負餘額）
        └ 爭議與風控（卡組織門檻監控）
信任安全 ├ 違規處置（積分＋動作階梯）
        ├ 申訴
        └ 合規（DSR／電子發票／個資通報／前台巡檢）
平台工程 ├ 可靠性與事故（含對外狀態頁發布）
        ├ 發布與灰度（flag 生命週期／rolling release）
        └ 環境與備份
治理    ├ 審計日誌（before/after diff）
        ├ 人員與權限（角色矩陣／JIT 提權／複核）
        └ 公告與棄用通知
        └ 平台設定
```

**租戶詳情十分頁**：概覽／資質 KYC／用量配額／計費／金流／網域與環境／風控／合規／工單／審計。

---

## 4. 迭代波次

| 波次 | 內容 | 掛哪個里程碑 | 為何是這個順序 |
|---|---|---|---|
| **W1 生命週期地基** | 多態狀態機＋分級凍結＋KYC 審核佇列＋requirements 模型＋dunning＋兩層權限＋授權式代登入＋審計 before/after | **M0 埋表／M8 出畫面** | 這些決定資料表與 middleware，M0 不埋就得動骨架 |
| **W2 金流與信任安全** | 通道分配／MCC／費率／撥款／保留金／負餘額／爭議門檻監控／違規階梯＋積分／申訴／工單／配額三段式 | **M8** | 上線後第一個月就會用到；出事沒台子＝人工救火 |
| **W3 透明度與合規** | 對外狀態頁＋維護視窗／flag 灰度＋kill switch／DSR 佇列／電子發票管線／公告與棄用通知／前台合規巡檢 | **M8→M9** | 法定時限與 B2B 續約檢查項 |
| **W4 工程治理** | 環境模型／備份還原／版本回滾／job 排程器 | **M9＋** | 企業客戶才需要；先有客戶再做 |
| **W5 生態擴張** | 代理商分潤與客戶歸屬／集團連鎖母子店＋資金歸集／批次配置下發（VTEX Edition 模式）／權限定期複核 campaign | **M9 後新里程碑** | 商業模式擴張期 |

**M0 必須先埋的**（否則 W1 落地時要動大表）：`shops.status` 多態 enum、六個凍結旗標、`kyc_submissions`／`kyc_requirements`、`platform_audit_logs`（含 previous/next JSON）、`access_grants`（授權式代登入）、`billing_subscriptions`／`dunning_attempts`、`limits_overrides`。

---

## 5. 各模組驗收要點（節錄，完整條目寫在 32 號 §9 的擴充版）

1. **狀態機**：12 態逐一測前台 HTTP／後台可讀寫／金流／webhook 四個維度；兩個例外（凍結仍可讀帳單、30 天後訂單狀態頁恢復）各有測試。
2. **分級凍結**：六旗標可獨立、可組合、可設到期自動解除；補件中「收款停但店可運營」場景有測試。
3. **KYC**：requirements 五分類排序正確；三種補救路徑皆可用；駁回原因碼字典完整；補件計時與逾期自動轉態。
4. **Dunning**：D+28 凍結線與凍結後 60 天終止線可設定；倒數顯示正確；手動干預留審計。
5. **爭議監控**：VAMP／ECM／EFM 三制門檻各自計算，Mastercard 用上月分母；雙欄（回報值／估算值）；越線自動告警＋建議動作。
6. **代登入**：授權碼機制、逐項權限、60 分鐘 TTL、90 天閒置失效、商家端橫幅、禁止動作被擋、雙寫審計——逐條測。
7. **審計**：每個平台寫入動作皆有列且含 before/after；12 個月保留、3 個月可立即查；無 update/delete 權限；可匯出 CSV。
8. **配額**：60% warn／100% error 三段式；儀表板紅橘綠；每日摘要。
9. **DSR**：GDPR 30 天／CCPA 45 天計時器；逾期升級告警；erasure 與 legal hold 衝突時 hold 優先。
10. **發票**：字軌餘量門檻告警；工商憑證到期前 60 天告警；作廢與折讓佇列。
11. **狀態頁**：5 元件狀態＋事故四階段；維護視窗預告同時暫停 webhook；訂閱分發。
12. **Flag**：4 態自動推導；rolling release 逐階段批准；kill switch 一鍵；cohort 定向。

---

## 6. 資料模型增補（在 32 §7 之上）

- `kyc_submissions`（shop_id, subject_type[個人/獨資/有限公司/股份/財團法人], tax_id, submitted_at, reviewed_by, decided_at, decision, reject_codes[]）
- `kyc_requirements`（submission_id, key, bucket[currently_due/eventually_due/past_due/pending_verification], deadline, error_code, error_reason）
- `kyc_documents`（submission_id, kind[公司登記/負責人證件/UBO/存摺封面/網域證明/稅籍函], file_ref, expires_at）
- `shop_restrictions`（shop_id, flag[payin/payout/trade/readonly/offline/banned], reason, expires_at, created_by）
- `billing_subscriptions`／`billing_invoices`／`dunning_attempts`（attempt_no, attempted_at, result, next_retry_at）
- `payout_accounts`／`payout_schedules`／`payout_runs`／`reserves`／`negative_balances`
- `payment_channels`（shop_id, provider, merchant_no, mcc, fee_bps, descriptor, status）
- `disputes`（shop_id, network, opened_at, state[open/under_review/won/lost], amount_cents, evidence_due_at）
- `dispute_metrics_monthly`（shop_id, network, ratio_reported, ratio_estimated, count, threshold_state）
- `violation_cases`（shop_id, category[A/B], points, actions[], status）／`violation_points_ledger`／`appeals`
- `access_grants`（shop_id, staff_id, code, scopes[], reason, approved_at, expires_at, revoked_at, last_used_at）
- `dsr_requests`（shop_id, subject_email, kind[access/erasure/portability], due_at, state）／`legal_holds`
- `einvoice_settings`（shop_id, provider, merchant_id, hash_key_ref, issue_timing, cert_expires_at）／`einvoice_tracks`（range_start, range_end, remaining）
- `feature_flags`／`flag_targets`（cohort 條件）／`rollouts`（stage, approved_by）
- `announcements`（audience_query, schedule, read_receipts）
- `tickets`／`ticket_messages`
- `platform_audit_logs` 增補 `previous JSON`、`next JSON`、`transaction_id`、`source`、`outcome`

---

## 7. 我們可打的差異化（競品都沒有）

1. **平台治理 API＋webhook**：Shopify 至今**沒有組織層 Admin API、審計日誌也只有 UI＋CSV**。我們 day 1 就給 `Platform::` GraphQL 全量操作。
2. **前台合規巡檢器**（台灣）：自動檢查租戶前台的統編揭露、隱私政策、鑑賞期告知。
3. **自助備份還原＋可匯出**：Adobe 的 Pro 環境有備份卻**不給自助還原**（要開工單），Medusa 才剛做到 export/import。
4. **租戶端透明**：把審計日誌中與該租戶有關的部分（誰在什麼時候代登入、做了什麼）開放給商家自己看——沒有平台這樣做，但這是信任的最強證明。

---

## 8. 與既有文件的關係

- 32 號＝v1 規格，仍有效的部分：§0 定位與邊界、§5 角色矩陣骨架、§6 API 慣例、§8 數字口徑。**§2 狀態機被本篇 §2.1 取代**，**§9 驗收清單以本篇 §5 擴充**。
- 原型 `chilllove-platform-admin.html` 依本篇 §3 重建為 v2（16 區、租戶詳情 10 分頁）。
- 里程碑掛接：W1 的資料表併入 **M0**；W1–W2 畫面在 **M8**；W3 在 **M8→M9**；W4/W5 為 M9 後。

---

## 9. 未查證與待複核

- 有贊 A/B 類積分的**節點分數對應措施表**（12/24/48 分各觸發什麼）官方頁未展開，僅確認 B 類 48 分為分水嶺。
- Shopify **dunning 重試次數與間隔**未公開（28 天凍結線與 60 天終止線可查證）。
- Shopify 員工進入商家後台的內部授權機制**無公開文檔**，本篇以 collaborator 模型替代。
- VTEX API key 到期與輪換政策、BigCommerce 各方案 storefront 數，官方頁面本次未能載入。
- 電子發票「48 小時上傳」期限來自媒體整理，建議以財政部《電子發票實施作業要點》原文複核。

---

## 10. 來源

**Shopify**：[Organization settings](https://help.shopify.com/en/manual/organization-settings)・[Organization permissions](https://help.shopify.com/en/manual/your-account/users/roles/permissions/organization-permissions)・[Collaborator accounts](https://help.shopify.com/en/manual/your-account/users/security/collaborator-accounts)・[Requesting access to a client's store](https://help.shopify.com/en/partners/dashboard/managing-stores/request-access)・[Pausing your store](https://help.shopify.com/en/manual/your-account/manage-orgs-and-stores/manage-pricing-plan/pause-store)・[Frozen stores](https://help.shopify.com/en/manual/your-account/manage-billing/billing-charges/frozen-store)・[Deactivate store](https://help.shopify.com/en/manual/your-account/manage-orgs-and-stores/manage-pricing-plan/deactivate-store)・[Resolving terms violations](https://help.shopify.com/en/manual/compliance/legal/terms-violations)・[Chargeback process](https://help.shopify.com/en/manual/payments/chargebacks/chargeback-process)・[Shopify Status](https://www.shopifystatus.com/)・[API versioning](https://shopify.dev/docs/api/usage/versioning)・[Privacy law compliance](https://shopify.dev/docs/apps/build/compliance/privacy-law-compliance)・[Partner API](https://shopify.dev/docs/api/partner/latest)

**華語 SaaS**：[SHOPLINE 方案與配額](https://shopline.tw/about/pricing/basic)・[SHOPLINE 擴充模組](https://shopline.tw/about/pricing/module)・[SHOPLINE Open API](https://open-api.docs.shoplineapp.com/docs/update-merchant)・[CYBERBIZ 方案比較](https://www.cyberbiz.io/pricing/compare/)・[CYBERBIZ 綠界電子發票設定](https://help.cyberbiz.io/ec/website-management/ecpay-invoice)・[meepShop 費用](https://www.meepshop.com/pricing)・[有贊店鋪認證標準](https://help.youzan.com/displaylist/detail_4_4-2-1107)・[有贊商家管理規範](https://help.youzan.com/displaylist/detail_10_10-2-31811)・[有贊違規行為分類](https://help.youzan.com/displaylist/detail_4_4-1-69549)・[有贊連鎖操作手冊](https://help.youzan.com/displaylist/detail_4_4-2-41756)・[有贊權限系統 SAM](https://tech.youzan.com/sam/)・[微盟云](https://cloud.weimob.com/)・[Shoplazza Payments](https://helpcenter.shoplazza.com/hc/en-us/articles/30690605767065-Shoplazza-Payments-Setting-up-secure-payments)・[店匠資金結算說明](https://helpcenter.shoplazza.com/hc/zh-cn/articles/56191222928537-独立站收单与资金结算参考说明)

**企業級**：[SFCC Code Deployment](https://developer.salesforce.com/docs/commerce/b2c-commerce/guide/b2c-code-deployment.html)・[SFCC Governance and Quotas](https://developer.salesforce.com/docs/commerce/b2c-commerce/guide/b2c-governance-and-quotas.html)・[SFCC Sandboxes](https://developer.salesforce.com/docs/commerce/b2c-commerce/guide/b2c-get-started-sandboxes.html)・[commercetools Limits](https://docs.commercetools.com/api/limits)・[commercetools Orgs/Teams/Projects](https://docs.commercetools.com/merchant-center/organizations-teams-projects)・[commercetools Audit Log](https://docs.commercetools.com/merchant-center/change-history)・[VTEX Store architecture](https://developers.vtex.com/docs/guides/store-architecture)・[VTEX Sponsor Account](https://developers.vtex.com/docs/guides/vtex-io-documentation-sponsor-account)・[BigCommerce API accounts](https://docs.bigcommerce.com/developer/docs/overview/api-fundamentals/api-accounts)・[Adobe Cloud Console](https://experienceleague.adobe.com/en/docs/commerce-on-cloud/start/cloud-console)・[Adobe snapshots](https://experienceleague.adobe.com/en/docs/commerce-on-cloud/user-guide/develop/storage/snapshots)・[Saleor Environments](https://docs.saleor.io/cloud/environment)・[Shopware Release Policy](https://developer.shopware.com/release-notes/)・[Medusa Cloud Environments](https://docs.medusajs.com/cloud/environments)

**平台範式與合規**：[Stripe: viewing all connected accounts](https://docs.stripe.com/connect/dashboard/viewing-all-accounts)・[Stripe: handle verification updates](https://docs.stripe.com/connect/handle-verification-updates)・[Stripe: manage payout schedule](https://docs.stripe.com/connect/manage-payout-schedule)・[Stripe: account balances](https://docs.stripe.com/connect/account-balances)・[Stripe: disputes on Connect](https://docs.stripe.com/connect/disputes)・[Stripe: dispute monitoring programs](https://docs.stripe.com/disputes/monitoring-programs)・[Visa VAMP fact sheet](https://corporate.visa.com/content/dam/VCOM/corporate/visa-perspectives/security-and-trust/documents/visa-acquirer-monitoring-program-fact-sheet-2025.pdf)・[Vercel Audit Logs](https://vercel.com/docs/audit-log)・[Okta System Log](https://developer.okta.com/docs/reference/system-log-query/)・[Statuspage status calculations](https://support.atlassian.com/statuspage/docs/top-level-status-and-incident-impact-calculations/)・[LaunchDarkly flag lifecycle](https://launchdarkly.com/docs/home/flags/flag-status)・[GDPR Art.12](https://gdpr-info.eu/art-12-gdpr/)・[PCI SSC SAQ A updates](https://blog.pcisecuritystandards.org/important-updates-announced-for-merchants-validating-to-self-assessment-questionnaire-a)

**台灣法規**：[數位經濟相關產業個資辦法](https://law.moda.gov.tw/LawContent.aspx?id=GL000090)・[網際網路零售業個資辦法](https://law.moda.gov.tw/LawContent.aspx?id=FL077934)・[通訊交易解除權合理例外情事適用準則](https://www.rootlaw.com.tw/LawArticle.aspx?LawID=A040030000011300-1041231)・[財政部網路交易課稅 Q&A](https://www.etax.nat.gov.tw/etwmain/tax-info/network-transaction-taxtation-area/q-and-a)・[財政部電子發票平台加值中心](https://www.einvoice.nat.gov.tw/index!showAddCenter)・[綠界申請發票字軌](https://support.ecpay.com.tw/8354)
