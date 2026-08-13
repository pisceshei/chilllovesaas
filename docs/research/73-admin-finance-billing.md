# 73 — 財務＋帳單 按鈕級 teardown（R4，2026-08-13 實測 chill-love-u5q5mnzq）

> 雙源：實測（test，Plus・dev 店・zh-TW）＋ help.shopify.com（help，5 agent 工作流，見 §7）。
> CSS 為**研究記錄**：記的是本尊的量測值與結構；我方實作依鐵律 8 一律走 23 號 tokens、
> 依鐵律 9 不抄本尊 CSS——本檔的映射表（§5.3）就是「量測值 → 我方 token」的橋。

## §1 財務總覽 `/finances`（302 → `/finance`）

本店未啟用 Shopify Payments ⇒ **推銷空態形態**（active 形態靠 help 補，見 §7）：

| 控件 | 實測內容 |
|---|---|
| 頁首 | 🏛 財務＋右上「文件 ⌄」下拉 |
| 文件 ⌄ | 兩項：**1099-K 表格**／**Shopify Payments 活動報表**（美稅文件⇒法域 pack 能力，HK pack 無此二項） |
| 2FA banner | ⓘ「新增多一層安全防護——啟用兩步驟驗證，才能使用您的帳戶。瞭解詳情」＋「設定兩步驟驗證」深色鈕＋插圖（info 面板 `--p-color-bg-surface-info #eaf4ff`） |
| 空態卡 | 插圖＋「在 Shopify 中管理您的財務」＋「設定 Shopify Payments 可讓您更快收到支付款項，並提供更優質的結帳體驗。」＋「啟用 Shopify Payments」主鈕 |
| 稅務區 | 標題「稅務」＋列「設定稅金代收 ›」（→ 稅金設定） |
| footer | 「深入瞭解 Shopify Finance」連結 |
| 導航 | **財務無子項**（71 §B.1 已登記；我方 m-finance 帶 m-billing 子項＝結構差，見 71-R4-STRUCT1） |

## §2 帳單 `/settings/billing`（302 → `/settings/organization-billing`，Plus 組織級集中帳單）

頁首：🏛 帳單＋右上「帳單資料」鈕（→ §3）。

### §2.1 目前帳單週期卡
- 「目前帳單週期」＋週期日期範圍「2026年7月15日 – 2026年8月15日」（**30 天週期、起日=方案開通日**）
- 「查看目前費用」連結 → `/settings/organization-billing/invoice/upcoming`（§4.1）
- 右側「累積總計 **$0.00 USD**」（24px/500 大數字）
- 「⊕ 新增付款方式」列 → modal（§3.1 同一支）

### §2.2 過去的帳單卡
- 狀態 filter tabs（**付款狀態 enum 全值域**）：全部｜已付款｜未付款｜付款失敗｜處理中｜已退款｜已取消＋「更多檢視」（saved views 家族）
- 右側 icon 組：搜尋＋篩選、排序 ⇅（popover：「排序依據」radio＝開立日期；由舊到新↑／由新到舊↓）
- 表：checkbox｜開立日期｜帳單號碼（#558817009 格式）｜帳單類型（值：帳單週期…）｜付款狀態（badge，已付款=success 綠）｜金額（右對齊）
- 分頁 ‹ ›；卡右上 ⋯ 選單：**匯出帳單**／**建立費用報告**
- 列可點 → `/settings/organization-billing/invoice/{id}`；dev 店 $0 帳單回 **404 空態**（綠色 404 卡＋「此網址找不到 頁面／找不到帳單 #…」）＝資料閘門，正式形態靠 help（§7）

## §3 帳務資料 `/settings/organization-billing/profile`

副標「編輯您的付款方式與稅務 ID，並檢視您的幣別與地址」。實測僅兩卡（dev 店資料閘門；稅務 ID／地址段落未現——71-R4-V1）：
- **付款方式**卡：「用於 Shopify 上的購買與帳單」＋⊕ 新增付款方式
- **幣別**卡：「您的帳單幣別選項依組織設定中的公司所在國家/地區而定。」＋列「幣別 USD (美元)」——**唯讀、由組織所在地推導**（我方 setBillingPage 的幣別可選 select＝發明控件，71-R4-BUG1）

### §3.1 新增付款方式 modal（只拆結構，未輸入任何資料）
- 付款方式類型 select（預設「信用卡」；其他選項在 PCI iframe 內無法枚舉——71-R4-V2）
- 信用卡資訊：卡號（尾隨 🔒）｜到期日（MM / YY）｜信用卡驗證碼 (CVV)（尾隨 ⓘ）——**hosted fields（跨域 iframe），JS 不可及**
- 帳單地址（自組織資料預填）：國家/地區 select（香港特別行政區）｜名字/姓氏｜地址（帶 🔍 自動補全）｜公寓、套房等｜**行政區（文字，例：九龍灣）｜地區 select（例：九龍）＝HK 地址 schema**（與 M0 jurisdiction pack 地址欄位對齊）
- footer：取消／「新增信用卡」（未填＝disabled）

## §4 帳單明細頁

### §4.1 `/invoice/upcoming` 目前帳單週期
- 卡 1＝目前帳單週期（同 §2.1，無「查看目前費用」）
- 卡 2＝**明細**：小計 $0.00 USD／**累積總計**（highlight 列，bg surface-secondary）

### §4.2 `/invoice/{id}`：dev 店 404（見 §2.2）；正式欄位（各費用區塊拆解）靠 help §7

## §5 CSS 研究（量測 2026-08-13；Polaris token 名僅為本尊事實記錄）

### §5.1 Token 值（`:root` computed）
| 類 | 量測值 |
|---|---|
| 底色 | bg `#f1f1f1`／surface `#fff`／surface-secondary `#f7f7f7`／surface-info `#eaf4ff` |
| 文字 | text `#303030`／secondary `#616161`／link `#005bd3`／icon `#4a4a4a` |
| 語義 | brand-fill `#303030`（深色主鈕）／critical `#c70a24`／success `#047b5d`／border `#e3e3e3` |
| 間距 | 100=.25rem 150=.375 200=.5 300=.75 400=1 500=1.25 600=1.5（**4px 基準**） |
| 字體 | Inter 系；size 300=.75rem 325=.8125 350=.875 400=1 500=1.25；weight 450（正文）/500/600 |
| 圓角 | 100=.25rem 200=.5 300=.75 400=1 500=1.25 |
| 陰影 | shadow-100/200＝六層極淡疊影＋1px 外框 `#0000000f`；**button＝三層 inset bevel**（`0 -1px 0 0 #b5b5b5 inset, 0 0 0 1px #0000001a inset, 0 .5px 0 1.5px #FFF inset`）；button-primary＝深色版 inset bevel |

### §5.2 元件量測
| 元件 | 量測 |
|---|---|
| 頁 h1 | 18px／600／lh 24px／#303030 |
| 大金額（累積總計） | 24px／500／lh 32px |
| 狀態 filter tab（選中） | 13.33px／500／bg `rgba(0,0,0,.08)`／radius 8px／pad 4×12 |
| 狀態 filter tab（未選） | 同上但 bg 透明、字 #616161 |
| 表頭 th | 12px／500／lh 20px／#616161／bg #f7f7f7 |
| 下拉選單項 | 13px／450／radius 8px／pad 4×8／高 28px |

### §5.3 → 我方 token 映射（鐵律 8/9：值取 23 號 §1，不抄本尊）
- 頁 h1 → `--t-lg`＋`--fw-semibold`；大金額 → `--t-2xl num`（tabular-nums 恆帶）
- filter tab 選中態 bg → 我方 `rgba(26,28,30,.05)` 家族（既有 hmSelect 選中態同源）；radius → `--r-200`
- 表頭 → 我方 `.idx thead` 既有（12px/#616161 等價 token 已存在）
- inset bevel 主鈕＝本尊 2026 的招牌「可舔按鈕」：我方**不複製**（視覺自有語言），交互等價物＝`.btn-pri` 現行樣式；記錄在案供設計參考
- 間距 4px 基準與我方 `--sp-*` 同構；無需新 token

## §6 Dev 店閘門清單（本輪實測不可及、待 help／有數據店補）
1. Shopify Payments 啟用後的財務總覽 active 形態（餘額/待撥款/現金流）
2. 帳務資料的稅務 ID／地址段（§3）
3. 帳單 detail 的費用區塊拆解（§4.2）
4. 付款方式類型 select 的完整選項（PCI iframe）
5. 單店（非組織）帳單頁與組織版差異

## §7 help 雙源補充（r4-finance-billing-help 工作流，wf_1938d305-8d7；critic 回 null，缺口見 §7.6）

### §7.1 帳單頁（billing-core＋tax-statements）
- **目前帳單週期卡＝五件事**（help 明文）：週期日期範圍／帳單累計總額／**付款方式**／**距離達到計費門檻所剩的金額**／各項費用明細。另有「檢視剩餘抵用金」入口（billing credits）。
- **計費門檻**：「是一個金額，帳戶活動費用超過即觸發新帳單」（第三方交易費＋app 週期費＋其他未付費用）；達標＝訂閱出帳前**先開帳單立即請款**；具體金額與級距 help 不載（平台內部值）⇒ **非商家控件坐實（71-R4-BUG2 verdict）**。
- **過往帳單列**：9 位數帳單編號（#開頭）／付款狀態／開立日期／總金額／**付款時間軸**／費用明細；銀行帳單顯示 `SHOPIFY * <9位帳單號碼>`。
- **匯出**：單張＝選帳單→匯出帳單→CSV 或 PDF；批次＝⋯（水平選單）→匯出帳單→「目前頁面」或「依日期」（最早至開帳號日）→CSV 寄 email。**付費明細「檢視摘要」**＝日期範圍（限 90 天內）＋套用＋匯出/列印。
- **帳單明細＝四類費用區塊**：訂閱（降級套折抵）／App（定期・用量・一次性）／運送（標籤費＋調整）／交易費用（未啟自有支付者收第三方交易費）＋底部小計/稅費/總計。PDF＝費用總覽（總額/訂閱/app/其他/稅額/週期/店名/付款方式/費用類型/反向課稅 VAT 通知）＋逐筆拆解。**折讓單（credit note）**：有折讓單的帳單有「下載折讓單」（PDF）；未付款自動沖減、已付款退款。
- **計費設定檔**（/settings/billing/profile）：付款方式（新增＝類型→hosted 流程；小額臨時授權驗卡）＋**每張卡 ⋯ 選單：設為主要（3+ 張時；2 張直接切換）／取代（＝改帳單地址的入口，「取代信用卡」）／刪除（僅剩一種不可刪）**＋幣別（**「管理」→「切換帳單幣別」對話框**：選項依公司所在國家/地區；下一週期生效；未付費用維持原幣別；換匯含 **1.5% 兌換手續費**）＋稅務資訊。
- **稅籍登記＝法域欄位**（per-jurisdiction，證實鐵律 11 模型）：AU＝ABN 11 位＋GST 聲明勾選／NZ＝IRD 8-9 位／EU＝VAT 編號走 VIES 驗證（待驗證→已驗證）／TH＝13 位＋聲明／SA=15 位、AE=15 位／CL＝RUT／EG＝TRN+UIN／ZA＝VAT 編號**但登記仍不免稅**（特例）／SG・MY＝**無自助欄位不可免稅**／US・CA＝聯絡支援提交文件（審查 ≤2 週）。**免稅一律不追溯**。
- **抵用金四類互不流用**（訂閱/app/運送/交易），僅能抵未來週期；停用商店後保留 60 天。
- **付款方式類型**：MC/Visa/Amex/Diners/Discover、聯名金融卡（需支援定期＋國際交易）、PayPal、平台餘額卡；**不收預付卡與虛擬卡**；地區型＝ACH（US）/SEPA（限非 Plus・EUR）/UPI（IN）/JCB（JP）⇒ pack 宣告面。
- **主要/備援**：主要扣款失敗→自動用備援；**Plus 方案不能設備援**；扣款失敗/漏繳→**凍結**（admin 不可入、前台不可瀏覽；到期日前不凍結；具「檢視帳務」權限者仍可看帳單；逾 30 天須重選方案）。
- **週期規則**：月繳＝每 30 天（31 天月可能收到兩張）；年繳＝期初收全額；app 費用**獨立 30 天週期**；帳單以 **UTC** 開立；帳單通知寄店主＋具「檢視帳務並接收帳務電子郵件權限」的員工。
- 退款政策：月繳 7 天/年繳 30 天申請窗；降級不退款改抵用金。第三方交易費公式 `[(商品成本−折扣)+稅+運費]×費率`，退款/取消**不退**交易費。

### §7.2 財務總覽 active 形態（finances-hub）
- **權限**：財務總覽**僅帳號擁有人**可見（非可授予的 staff 權限）。
- 卡片組：**最近交易卡**（日期/說明/帳戶/金額，可點入）＋**帳戶卡**（四總額：支付款項/主要 Main/Credit/Capital，各可點入；兼金融產品推銷與資格檢查入口）＋**稅費卡**（未收稅=引導；已收稅=顯示代收地區數）＋**Bill Pay 卡**（雙態）。可檢視對帳單、頁上直接移轉資金。
- 導航證實：「財務」下**有「支付款項」子項**（前往財務 > 支付款項）——⚠ 與本店實測（無子項）不同：**子項依產品啟用狀態出現**（未啟收款=無子項）。71-R4-V4 修正 STRUCT1 敘述。
- Balance/Credit/Capital/Bill Pay/Tax＝「Shopify Finance 產品套件」＝**平台自有金融產品邊界（G15）**：我方不建，登記邊界；Balance 限美國。

### §7.3 撥款（payouts-capital；G15 ⇒ PSP pack 對應面）
- 排程：每日（JP 不可）／每週（選星期幾）／每月（選日期，超月末自動調整）＋「每次收到支付款項時，以電子郵件通知我」勾選；改排程→待處理款延至新排程下一適用日。
- 撥款詳情：總覽（總金額/狀態/銀行帳戶/**轉移參考編號**/charges·refunds·adjustments·保留金細目）＋交易區段（含 Pending）。**狀態四值：已排程/已存入/失敗/已提款**。
- 匯出餘額交易 CSV（email 寄送）11 欄：Transaction Date/Type/Order/Card Brand/Card Source/Payout Status/Payout Date/Available On/Amount/Fee/Net。篩選 7 鍵＋可儲存檢視。
- 失敗處理：更新銀行帳戶→自動重新啟用；負向撥款「再嘗試扣款兩次」＋「我已存入資金」鈕；失敗原因 10 條（zh-TW 原文已存）。保留款兩型（固定額/百分比）；帳戶保留 6 因。
- 結算：週末假日不計；週五至週日收款計第 0 天；各國 2-7 工作日＋銀行 1-3 天。
- Capital＝邀請制融資（預支/貸款；月里程碑 30%/60%、18 個月清償）＝**平台金融產品邊界**，不進我方。

### §7.4 → limits.yml 落鍵（billing 節，本輪新增）
credit_expiry_after_deactivation_days=60／summary_export_max_days=90／refund_request_window_days（月 7/年 30）／currency_conversion_fee_percent=1.5／invoice_number_digits=9／frozen_replan_after_days=30

### §7.5 對我方的裁定面
- BUG1（幣別）修正**再修正**：不是「純唯讀」——是「管理→切換」對話框，但**選項集由公司所在地決定**；HK 無本地幣別選項 ⇒ 我方 HK org demo 呈唯讀＋DOCS 記「選項>1 時才出現管理鈕」。
- BUG2（門檻）坐實：非商家控件；呈現＝目前帳單週期卡內的「距離門檻所剩金額」進度，不是設定列。
- STRUCT1 敘述修正：財務導航子項（支付款項）**存在但依啟用狀態出現**——我方 kids 應隨 FIN_PSP 動態。

### §7.6 critic 缺口（回 null，自查補登）
help 老 URL 樹（your-invoice/how-billing-works）已整組改版重導 ⇒ 28 號引用時用新樹；未抓：billing-cycles-thresholds 子頁全文、unknown-charge/double-charge 疑難頁、手動付款機制、帳單到期日規則、凍結精確時間線。
