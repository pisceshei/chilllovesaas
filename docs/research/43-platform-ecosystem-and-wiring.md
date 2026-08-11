# 43 — 平台生態五模組深研（W5）與三端對接矩陣

> 兩件事：**第一部分**把 33 號 §1 模組矩陣的 **W5 生態層**（代理商／集團連鎖／方案計費／上架審核／平台 BI）查到可實作深度——33 號只確認了「誰有誰沒有」，本篇給出畫面、控件、狀態機、數值與口徑；**第二部分**建立「功能 × 三端表現 × API 家族 × 資料同源」的對照矩陣（23 條功能線）＋跨端斷點風險清單（16 條，各附偵測與防範），作為之後 API 交叉核實（28 號 §18 驗收）的底稿。
>
> 標記慣例：**✅官方**＝有官方文檔可逐字查證；**◑第三方**＝第三方整理或社群實測，方向可信、數字需複核；**△推測**＝官方未公開，依業界慣例或本專案上下文推導的設計建議。
>
> 上游：`docs/design/33`（競品拆解，本篇深化其 §1 W5 列與 §2.9 代登入）｜`docs/design/32` §0（平台定位）｜`docs/research/28`（API 契約，§17 三端對接矩陣的簡表被本篇 §6 擴充）｜`docs/specs/35` §3（跨端副作用表雛形，被本篇 §6–§7 取代性擴充）｜`docs/specs/36–39`（資料表與控件的引用來源）。

---

# 第一部分：平台生態五模組深研

## 1. 代理商／服務商體系

### 1.1 Shopify Partner／Dev Dashboard 的商店管理面 ✅官方

Partner 側「商店」分**三類**，能力邊界完全不同（這個三分法是我們 partner 域資料模型的骨架）：

| 類型 | 用途 | 可否轉移給商家 | 關鍵限制 |
|---|---|---|---|
| **Collaborations** | 進入既有商家的店提供服務 | —（本來就是商家的店） | 權限由商家逐項授予；不佔商家席次 |
| **Dev stores** | 開發測試 | **不可轉移** | 純測試用 |
| **Client transfer stores** | 替客戶建站，完工後交付 | **可轉移** | 轉移前：只能裝 free／partner-friendly apps（custom／draft app 不可）；不支援真實交易與出貨標籤；檔案／影片／3D 儲存上限**比照 Basic 方案** |

列表側（Dev Dashboard）：collaborations 分頁以狀態徽章＋三點選單呈現，官方未公開完整欄位集（△推測欄位：商店名／myshopify 網域／方案／狀態／權限摘要／最後使用時間——我們自建時以此為準，最後使用時間支撐 90 天自動失效的可視化）。

### 1.2 Collaborator 請求全流程 ✅官方

1. 商家端在 **Settings → Users → Security** 取得 **4 位數 collaborator request code**；重新產生新碼即令舊碼失效。
2. Partner 端 **Stores → Request store access**：輸入商家**永久 `myshopify.com` 網址**（不支援自訂網域）→ 輸入 4 位數碼 → **逐項勾選要求的權限** → Send request。**例外**：若該 partner 組織已有 app 安裝在該店，可**免碼**發起請求。
3. 請求狀態機（Partner 側可見四態）：`Request sent`（待商家批准）→ `Active` → `Expires soon` → `Expired`（需重新發起請求）。
4. 商家端在 Users 以 **Requests** 篩選檢視；接受前可看到**依請求權限自動生成的角色**（命名慣例「collaborator 名 x 店名」），可先編輯權限或改指派既有角色，再 Accept／Reject。
5. 生效後：**不佔商家席次**；**90 天未登入自動失效**；商家可隨時移除（輸入密碼確認，不可逆）。單一請求方 pending 上限 10（33 §2.9 已查證）。
6. 可請求的權限全集：官方文檔僅例示（View products／Manage settings／指定 app 與 channel 存取），**未列全集**——實際上就是商家 staff 權限矩陣的子集。◑第三方實測與我方推導：對映到我們 12 號權限模型時，collaborator 可請求集＝staff 權限全集**減去**「帳務／使用者管理／商店轉移」三類（△推測，需以 12 號角色矩陣定案）。

> 對我們的意義：33 §2.9 的「授權式代登入」講的是**平台方**進店；本節是**第三方服務商**進店。兩者可共用 `access_grants` 表（加 `grantee_type: platform_staff | partner`），但過期策略不同——平台代登入單次 60 分鐘，partner collaboration 為長期授權＋90 天閒置失效。

### 1.3 Client transfer store 轉移流程 ✅官方

1. Dev Dashboard **Stores** 分頁建立 client transfer store：選國家／地區（決定稅制與幣別預設），可選 Shopify Plus 功能集。
2. 建置期間受 §1.1 的三項限制（app 白名單／無真實交易／Basic 級儲存）。
3. 完工後發起 transfer ownership：客戶收 email 接受。
4. 轉移後：**商家成為 owner、商店脫離 partner 組織**；該店**不再適用促銷與免費試用**；partner 若要繼續維運，需另走 collaboration 請求。
5. 商家側 ownership 轉移的通用限制（同樣適用於此）：僅 owner 可轉移＋需重新驗證身分；**Plus 組織內的店不可自助轉移**（找 Plus Support）；有 Shopify Capital／Credit／Balance 餘額者擋轉移（Balance 須先清空）；組織至少留一店，唯一店移出＝組織解散。

> 落地：我們的 `shops` 需要 `origin`（`self_signup | partner_built | platform_created`）與 `transferred_at`；轉移動作＝一次 owner 變更＋partner 歸屬解除＋計費主體切換，三者必須在同一 transaction＋審計。

### 1.4 分潤帳呈現 ✅官方

**收益類型與費率全表**（partner 分潤引擎的計算字典）：

| 收益類型 | 費率 | 存續期 | 附帶條件 |
|---|---|---|---|
| 建店轉移／launch 推薦 | **20% 月基礎訂閱費 ＋ 0.1% eligible GMV** | 4 年 | GMV 計佣年上限 $100M USD |
| POS | 20% POS Payments profit | 4 年 | 商家月 GPV > $1,000 才起算 |
| B2B | 20% B2B Payments profit | 4 年 | — |
| Shop Pay off Shopify | 0.1% GPV | 1 年 | — |
| Plus／Enterprise 推薦 | **$2,500 USD 一次性** | — | — |
| POS Pro 推薦 | $500 USD 一次性 | — | 連續 2 個月、每月 ≥10 個交易日 |
| App 分成 | 首 $1M USD **100%**（超過 85%）或全額 85%（依歷史二選一）；另扣 **2.9% processing fee** | — | — |
| Theme 分成 | 85% | — | — |

**Payout 機制**（撥款排程引擎可直接抄）：
- 雙半月週期三段制：1–10 日入帳的收益 → **15 日後 5 個工作天**撥付；11 日至「月底前第 5 天」→ **月末後 5 個工作天**；月末最後 5 天 → 併入**次月 15 日檔**。
- **最低撥款門檻 $25**，未達滾入下期；經 Hyperwallet 撥付。
- **新推薦收益 30 天 hold**（確認商家首筆付款清算）；商家帳單扣款失敗 → 對應佣金不撥（先收到錢才分潤——我們照抄：`commission_entries.status: accrued → cleared → paid`，cleared 以租戶發票 `paid` 為觸發）。
- Payouts 頁結構：按 **Sales**（app／theme／service）與 **Referrals**（client transfer／Plus 推薦）分組；已處理的 payout 含**稅與費用獨立明細行**；狀態含 `Failed`（可 retry）與 `Pending`；可整批或按期匯出 CSV；佣金發票在獨立 invoice 區下載。
- Payout CSV 明細行欄位（2021-08 改制後）：`Partner sale`（原始售額）→ 減 `Shopify fee` → 減 `Processing fee` → 得 `Partner share`。**啟示：明細行必須保留「毛額→逐項扣減→淨額」的完整算式欄，不能只給淨額**，否則 partner 對不了帳（工單來源）。

### 1.5 有贊渠道商：客戶歸屬與地域保護 ✅官方（框架）＋△推測（細則）

官方可查證（youzan.com/intro/qudao）：
- 模式＝**代理商制**：「0 加盟費」但需繳**保證金**；申請流程「提交申請 → 線下審核 → 洽談方案 → 簽約合作」。
- 收益結構六種：銷售返利／新客合作／老客續費／交付服務／代運營增值收入／年度激勵；另有**階梯獎勵**（按簽單量分級）與**沖單激勵**（達標獎金）。
- 加盟門檻五條：認同產品、有營業執照與獨立法人＋辦公場地、負責人有經營與團隊管理經驗＋成熟銷售團隊、SaaS／社交電商背景、**本地優質客戶資源**（暗示地域經營導向）。
- 工具：**渠道 CRM**（qudao.youzan.com 獨立入口）；扶持含渠道經理駐地、市場活動補貼、專屬客服、大客戶售前支持。
- 客戶歸屬與地域保護的**條款細節官方未公開**。△推測（陸系渠道慣例，供我們設計）：報備制——渠道在 CRM 提交客戶線索（公司名＋統編／手機號去重）→ 平台審核歸屬 → **保護期**（慣例 30–90 天，可續）→ 期內該客戶成交一律計佣給報備方；撞單（兩渠道報同一客戶）以報備時間先後＋跟進證據裁決；**直销與渠道衝突**是最大糾紛源，需明文「平台直銷碰到已報備客戶讓單或折算」。我們實作 `partner_client_links(partner_id, lead_key, shop_id?, status[reported/protected/converted/expired/disputed], protected_until, evidence)` ＋撞單裁決工單化。

### 1.6 SHOPLINE Partner ✅官方（框架）

- 合作夥伴四類：**策略合作夥伴／代理商與聯盟夥伴／開發者合作夥伴（app 上架）／技術合作夥伴（客製串接）**。
- 等級制＝**金、銀、銅認證標章**（達成不同成就的代理商取得），具體升級門檻與分潤比例未公開（△推測：以年度簽單額＋續約率門檻分級，高級別享轉介優先權——SHOPLINE 明文「將針對不同的客戶轉介予最適合的合作夥伴」，即**平台把 inbound 名單分發給夥伴**，這是台灣市場的重要機制）。
- Partner 帳號內建三角色：Owner／Administrator／Staff（權限遞減）——partner 組織本身也要有自己的成員權限模型。
- 微盟：僅招商頁（weimob.com/zs），後台細節未公開，本篇不採。

### 1.7 我們的設計落點 △推測（設計建議）

- **資料模型**：`partners`（等級／保證金／狀態）、`partner_members`（owner/admin/staff）、`partner_client_links`（§1.5 歸屬模型）、`partner_commission_plans`（費率版本化，仿 §1.4 字典）、`partner_commission_entries`（accrued/cleared/paid/clawback，掛 `billing_invoices`）、`partner_payout_statements`（雙半月＋最低門檻＋明細行毛額算式）、collaboration 復用 `access_grants` 加 `grantee_type`。
- **畫面**：Partner Portal 獨立入口（客戶列表＋報備／collaboration 請求／佣金與撥款單）；平台側「生態」區三頁（夥伴列表與等級／歸屬與撞單裁決佇列／佣金與撥款批次）。
- **紅線**：佣金撥付走銀行轉帳（發票核銷），不建 partner 錢包餘額——同 37 號 `nopool` 電支條例紅線。

## 2. 集團／連鎖多店

### 2.1 Shopify Plus organization ✅官方

**Expansion stores 規則**（多店額度模型的參照）：
- 標準 Plus 合約含 **1 主店＋9 expansion stores（共 10）**，不另收費；**staging 店不計入**；超過 10 家找 Support 個案議價。
- 資格限制：expansion 店須為**同品牌延伸＋相同商品類型**；帳單幣別僅 **USD 或 INR**。預核類型：國際站／B2B 批發／D2C（每合約**免費一家**）／員工內購店／實體零售。
- 建店流程：Settings → Organization 新建，可選擇性**匯入資料（themes／products／files／collections）**——「開新店帶資料」是產品能力，不是遷移工具。
- **加入既有店**：需主店 owner 與被併店 owner **雙方書面同意**＋Plus Support 核驗（平台側必須有這條人工流程的工單化）。
- 隔離與集中：各店 settings／products／collections／inventory **完全獨立、無自動同步**；**app 逐店計費**；theme license 逐店購買；集中的只有 **users（組織層權限）與 billing**。組織 admin 分區：Stores／Users／Billing／Analytics／Test drives（＋Academy）。組織層權限五項與四級 Business entities 見 33 §2.15，不重複。

**非 Plus 的 organization（group store）** ✅官方：
- 前置：僅 owner 可操作、須擁有 ≥2 店、**各店帳單幣別一致**、INR 計費不可、Plus 店不適用（走 expansion）。
- 路徑：Settings → General → Organizations and store transfers → Manage → Group store in an organization → 選既有組織或新建 → 確認。
- 後果：付款方式**升到組織層集中**；「View billing／Edit billing payment methods」等財務權限**移到組織層 Billing 權限**（僅組織 owner／admin 保有）；使用者管理權限亦升組織層；**組織建立後幣別不可改**；移出唯一店＝組織解散、被移出店需重設付款方式。

### 2.2 有贊連鎖：總部—網店樹狀管理 ✅官方

**兩層後台結構**：

| | 總部後台 | 網店後台 |
|---|---|---|
| 模組 | 店鋪管理（組織機構／網店管理）、商品、訂單、客戶、數據分析、**資產管理（資金歸集／收益發放）**、應用營銷、設置（員工／角色／認證） | 本店訂單、獨立結算帳戶檢視、本店數據、有限設置（店名／Logo／營業資訊／員工角色） |

**商品下發**（操作面）：
- 「總部創建商品，並分配到網店，且**總部可控制網店商品上下架狀態**」。
- 網店未開「自建權限」時**不可編輯商品**，只能檢視＋操作上下架；開權限後可自主編輯。
- 庫存兩型：**獨立庫存型**（網店可自行修改）vs **共享庫存型**（網店不可編輯）——同一店內兩型並存，這是「下發」模型的核心參數。
- 不支援下發的品類：海淘／酒店／供貨商品。

**訂單與資金歸集**：
- 訂單：「總部可操作所有網店訂單（發貨、退款、取消）」；「網店僅可查看和處理本店訂單」——**上層對下層全權，下層僅本店**，正是我們 Platform:: 與租戶 admin 的權限拓撲在「集團」場景的複本。
- 資金：總部與網店**各有獨立結算帳戶**；「被加入資金歸集的店鋪，**餘額不可提現**」→ 總部「發放收益」給網店 → 網店**收益帳戶**可提現；未設歸集規則的網店餘額可自提。（＝歸集是**開關制**且以「不可提現＋收益發放」實現，不是實時資金上收。）
- **台灣紅線**：這套「餘額不可提現＋總部發放」在台灣即《電支條例》特許範圍。我們只能做**報表歸集**（各店應收彙總視圖）＋**應收分潤結算單**（總部與分店各自持有商戶號，平台只算帳不碰錢）——與 37 號 `nopool` 宣告一致。

**統一裝修**：「總部為所有網店設置統一的微頁面，網店無法修改，僅可查看」；總部開權限後網店可自主裝修——即 **主題／頁面的「鎖定下發＋逐店解鎖」二態**。
**營銷權限**：27+ 種玩法（限時折扣／滿減送／多人拼團／秒殺／砍價 0 元購…）由總部控制網店「自建活動權限」；關閉時網店「可查看和推廣，不可編輯」。
**開店與主體**：總部 → 店鋪 → 組織機構 → 新建網店（填資訊＋配置能力）；分店為**獨立主體須單獨認證**、同主體可**由總部授權主體資訊**——KYC 的「主體繼承」開關，直接影響我們 `kyc_submissions` 是否可引用母店資料。

### 2.3 VTEX franchise accounts ✅官方

- Franchise account＝掛在 main account 下的 **white label seller**：**消費者不可見**，統一在主站門面下成交。
- **繼承**：catalog 繼承自 main account（franchise 不建商品）；**客戶資料集中存 main account 的 Master Data**；無獨立網域。
- **自持**：各 franchise 有**自己的 logistics 設定與 OMS**（自管庫存、自出貨）；**價格／促銷／支付方式可自持或繼承**，main account 保留 override 權。
- 用途：把實體店／加盟商網路變成線上通路的履約節點（訂單按區域／庫存路由到 franchise）；開通需向 VTEX Support 申請。
- 對照：有贊連鎖＝「多前台多後台」，VTEX franchise＝「單前台多履約帳戶」。我們的多店組織應同時支援兩種拓撲（`organization_stores.mode: storefront | fulfillment_node`，△推測）。

### 2.4 我們的設計落點 △推測（設計建議）

- 表：`organizations`（billing_currency 鎖定、owner）、`organization_stores`（role: hq/branch、mode、joined_at、approval 記錄——對應 Shopify「雙方書面同意」的工單化）、`org_product_pushes`（下發批次：商品集＋庫存型＋上下架控制權）、`org_theme_pushes`（統一裝修＋逐店解鎖旗標）、`org_settlement_reports`（報表歸集，不碰資金）。
- 額度：組織內店數走 `config/limits.yml`（仿 Plus 1+9；staging 不計）。
- 權限：組織層與商店層**不繼承**（33 §2.15 D8 裁決）；總部對分店的「全權操作」以組織層角色顯式授予，並全程審計（等同平台代登入的可觀測標準）。

## 3. 方案與計費管理（平台自營面）

### 3.1 Stripe products & prices 模型 ✅官方

平台後台「方案目錄」的正確資料形狀（37 號 `billingplans` 控件的底層模型）：

- **Product＝方案，Price＝定價版本**。鐵則：「若在定價頁是不同列（Basic vs Pro），必須是不同 product；同一列不同計費週期（月繳/年繳），是同一 product 的不同 price」。不同 tier 掛同一 product 會讓發票行名稱無法區分。
- **Price 不可變（immutable）**：改價＝**建新 price ＋ archive 舊 price**（`active=false`），不得改 `unit_amount`——舊 price 作為歷史交易的不可變紀錄留存。**這就是 grandfathering 的實作機制**：既有訂閱繼續掛舊 price，新客走新 price；平台後台需要「哪些租戶還在舊價、佔比、批次遷移工具」的檢視（△推測：我們做 `plan_price_versions` 列表＋`grandfathered_count` 欄）。
- Product/price 一般**只能 archive 不能刪**（從未使用過的才可刪）；檔案永久保存以對帳。
- 一個 price 可載**多幣別**（`currency_options`）；`default_price` 指定主推版本；`price_data` 支援 inline 臨時價（不進目錄）；tiered（graduated 累進／volume 整段）與 usage-based 支援訂閱；**計費週期上限 3 年**；同一訂閱的多 price 須同 interval（除非 flexible billing mode）。
- 對映到 37 號既有裁決互證：「方案停售不刪除（既有訂閱續存）」＝archive；「改價只影響新週期」＝新 price 掛新訂閱；「降級阻擋規則寫在計費引擎」＝我們自加的約束層。

### 3.2 Stripe Entitlements：模組訂閱的同步機制 ✅官方

「租戶買了什麼模組」與「系統開了什麼功能」之間的權威橋樑：

- **Feature**（`name` ＋ 全域唯一 `lookup_key`）→ 以 `product_feature` 掛到一或多個 product（一個 feature 可屬多方案）。
- 訂閱 active 期間，客戶持有該 product 全部 features 的 **active entitlements**；升降級／取消時 Stripe 發 **`entitlements.active_entitlement_summary.updated`** webhook，payload 帶完整當前 entitlement 集（**上限 10 條，超過用 `entitlements.url` 分頁拉全量**）——收到事件即開通／回收功能。
- 官方建議**把 entitlements 持久化到本地**（webhook 失敗時以 List Active Entitlements 對帳）。
- **關鍵口徑**：「既有訂閱在 product feature 變更時，**於下一計費週期才產生新 entitlements**」——平台改方案內含模組，存量租戶**不會立即**生效。我們必須決定是否跟隨（△建議：跟隨預設＋提供「立即重算」批次工具，並在 BI 的模組滲透率口徑註明滯後）。
- 對映我們：`plan_features`（=product_feature）＋`shop_entitlements`（本地持久化）＋事件 `entitlements.updated` 進 outbox；**feature flag（39 號）與 entitlement 分責**——entitlement＝商業授權（買沒買），flag＝技術灰度（開沒開）；middleware 檢查順序 entitlement → flag。

### 3.3 優惠券與折扣碼模型 ✅官方

- **Coupon（後台驅動）**：`percent_off` 或 `amount_off`（＋多幣別 `currency_options`）；`duration: once / repeating(duration_in_months) / forever`；`max_redemptions`（**跨客戶總量**）；`redeem_by`；`applies_to` 限定適用商品；**建立後僅 name 可改**；刪除只擋新套用、不影響既有 discount。`once` 只折**下一張**發票，用掉後從訂閱的 discounts 陣列消失（客服常見誤判點）。
- **Promotion code（客戶面碼）**：包裝 coupon 的分發層，多碼可指向同一 coupon；**碼不區分大小寫**、「任何人可用」的 active 碼全域唯一（客戶專屬碼可重名）；限制項：綁定特定 customer／`first_time_transaction`（**曾開過 PaymentIntent 或曾試用即不算首購**——嚴格定義）／`minimum_amount`（**僅在首次付款檢查**）／`expires_at`（不可晚於 coupon 的 `redeem_by`）／`max_redemptions`（不可大於 coupon 的）。**coupon 失效 → 其所有 promo codes 永久失效不可復活**；達到上限或過期的碼同樣不可復活（只能發新碼）。
- **疊加**：一張訂閱/發票最多 **20 個 discounts**；同源 coupon 不可重複疊；**amount_off 與 percent_off 的疊加順序影響結果**（20% off 再 -$5 ≠ -$5 再 20% off）——我們的折扣引擎必須固定順序並在 UI 明示。更新 discounts 本身**不觸發 proration**、下期發票生效。

### 3.4 資源包與加購 △推測（＋33 已查證的錨點）

- SHOPLINE／CYBERBIZ 的「擴充模組」單價表 33 號已研究（模組制加購是台灣市場慣例）；陸系（有贊/微盟）另有**資源包**：簡訊包／流量包／AI 額度包等**消耗型計量包**。設計上與訂閱分開：`resource_packs`（SKU＋額度＋效期）＋`pack_balances`（shop_id, remaining, expires_at）＋扣減走冪等 ledger；額度耗盡走 36 號配額三段式的 `error` 段，並在 admin 顯著提示可加購。
- 我們的方案後台結構（整合 37 `billingplans` 已有規則）：**方案表**（product 層）→ **定價版本表**（price 層，immutable＋grandfathered 計數）→ **模組目錄**（feature/entitlement）→ **優惠券／折扣碼**（§3.3 全模型）→ **資源包**。超額策略三選一（軟限告警／硬限阻擋／自動加購）與降級阻擋沿用 37。

## 4. 上架審核（App／Theme）

### 4.1 App 審核狀態機與新提交體驗 ✅官方

- 狀態機：`Draft` → `Submitted` →（`Paused`：**核心要件缺失致 reviewer 無法開審**，如裝不起來）→ `Reviewed`（有需修項，逐項與 reviewer 討論）→ `Published`；任意時點可 **Withdraw**。33 號已有此骨架，本篇補齊下述工作台細節。
- **Requirement-level tracking**（2025 改版的核心）：審核回饋集中在 App → Distribution，**每一條不合格的 requirement 有自己的狀態追蹤器**，開發者可**逐條**查看回饋、**逐條與 reviewer 對話**、修好後**逐條標記 resolved**；**全部 resolved 前封鎖重送**（blocked resubmission）。
- 送審前自動化：**自動預檢**（theme app extensions 合規＋listing 要件，即時回饋）；**AI self-review**（對照 App Store requirements 自查，約 2 分鐘）。
- 時限：**7–14 個工作天**（◑第三方整理，官方未給硬承諾）；BFCM 前旺季變慢；重送重新排隊；純 listing 小改通常免全審；「核心功能與原送審不符」須整包重審。

### 4.2 App 審核 checklist 分類 ✅官方（分類與例示條目）

| 分類 | 代表性條目 |
|---|---|
| 禁止與受限型態 | 部分 app 類型禁止上架；部分僅限 limited visibility；須符 AUP（高風險商品等） |
| 安裝與設定 | 裝後**立即走 OAuth** 再做其他事；OAuth／收費確認不得用彈窗；升降方案須可自助 |
| 功能與品質 | **不得拖低店面 Lighthouse 分數 >10 分**；核心功能與 listing 一致；cookie／SameSite 合規 |
| 安全與資料隱私 | 隱私政策必填；**90 天內棄用的 API 不得使用**；金流須走 PCI 合規通道 |
| Listing 與品牌 | App 名 ≤30 字元且以品牌名開頭；icon 1200×1200 JPEG/PNG；英文主檔可自動翻 8 語 |
| 權限與 OAuth | 授權頁逐項 grant/decline；embedded app 用 session token |
| 支援 | 文檔須有 Shopify 情境的明確步驟；緊急聯絡人須維持有效 |

### 4.3 Theme 審核：五階段與要求數值 ✅官方

- 提交：Partner Dashboard → Themes → Submit（ZIP 上傳＋同意 Partner Agreement＋listing 表單與 presets）；送出即發 email、Dashboard 最長 24h 反映。
- **審核五階段（順序制）**：①功能與 OS 2.0 相容 → ②**Lighthouse 效能與無障礙指標** → ③技術要求（頁面/功能/瀏覽器/資產/SEO/a11y/社群）→ ④設計與 UX（附詳細回饋）→ ⑤上架前終檢。
- 回饋格式：email 附 **required changes 清單**（可與審核團隊討論）；**未修就重送 → 可能被暫停提交資格**；審核開始後**鎖定更新**至結案。
- 硬性數值：Lighthouse **效能 ≥60**（product/collection/home 三頁平均）、**無障礙 ≥90**；文字對比 **4.5:1**（大字 3:1）；瀏覽器矩陣（桌面 Safari 近 2 版/Chrome 近 3/Firefox 近 3/Edge 近 2；行動 iOS Safari 近 2/Chrome Mobile 近 3/Samsung Internet 近 2＋IG/FB/Pinterest webview）；禁 Sass、禁壓縮版 css/js（ES6 與第三方庫除外）；demo 店禁 Lorem Ipsum；**商家支援 2 個工作日內回覆**；重大 bug 不即修可被暫時下架；**Theme Store 獨家**。

### 4.4 Reviewer 工作台設計落點 △推測（33 狀態機之上的補全）

- **佇列頁**：欄＝提交物／類型（app/theme/更新）／開發者／進入佇列時間／SLA 時鐘（7–14 工作日倒數，逾期紅）／目前階段（theme 五階段 badge）／分派 reviewer。支援按階段與逾期篩選。
- **案件詳情**＝requirement checklist 樹：分類（§4.2 七類或 §4.3 十二類）→ 逐條三態 `pass / fail / needs_info`，fail 必附**原因碼**（canned rejection 字典，仿 33 §2.2 駁回原因碼做法）＋自由文字；右側為**逐 requirement 對話串**（開發者可回覆，狀態各自流轉——直接照抄 Shopify requirement-level tracking）。
- **自動預檢面板**：Lighthouse 分數、theme-check 結果、API 掃描（棄用 API/scope 超求）、listing 完整度——fail 項自動預填 checklist。
- **更新審核**：對已上架物的更新只審 **delta**（版本 diff 視圖）；「核心功能變更」偵測則升級為全審。
- 資料模型：`review_submissions`（kind, state, sla_due_at, assignee）＋`review_requirements`（submission_id, category, key, state, reason_code, note）＋`review_threads`（requirement 級對話）＋`review_precheck_results`。狀態機沿 33 已定義者，本表補「requirement 級」子狀態。

## 5. 平台 BI：SaaS 營運指標標準集

### 5.1 MRR 與五種 movement ✅官方（ChartMogul 分類器）

- **MRR**＝訂閱經常性收入正規化為月（年繳 ÷12）；**排除**一次性費（setup／實施）、專業服務、稅。37 號已裁決：我們的 MRR **不含 GMV 抽成與加購模組**（各自獨立卡）——與本節口徑相容：抽成屬 usage 性質、加購模組若為訂閱制可另算 module-MRR。
- **恆等式**：`MRR(t) = MRR(t−1) + New + Expansion + Reactivation − Contraction − Churn`。分類定義：

| Movement | 定義 | 邊界案例 |
|---|---|---|
| New Business | 非付費客戶首次購買訂閱 | **同時買多個訂閱＝單一 New**，不拆多筆 |
| Expansion | 既有活躍客戶總 MRR 上升（升級/加購/**折扣到期**） | — |
| Contraction | 降級或取消部分（非最後一個）訂閱，淨額下降；**套用折扣也算** | — |
| Churn | 取消**最後一個**訂閱 | 認列時點＝服務期末，非按取消鈕當日 |
| Reactivation | 曾 churn 的客戶回到付費 | 「取消＋立刻換更貴方案」預設記 Churn+Reactivation；**把兩訂閱連結後應轉記 Expansion** |
| Neutral | 等價換方案，MRR 不變 | 同日多次變更在歸併窗內重新分類 |

- 陷阱：同日/短窗內的多筆變更須**歸併後再分類**，否則 waterfall 會出現假 churn＋假 reactivation 對沖。

### 5.2 NRR／GRR／logo：公式與基準 ✅官方（多源互證）

```
NRR = (期初 MRR + Expansion − Contraction − Churn) ÷ 期初 MRR     可 >100%
GRR = (期初 MRR − Churn − Contraction) ÷ 期初 MRR                 逐客戶 cap 於期初值，恆 ≤100%
Logo retention = (期末客戶數 − 期內新客) ÷ 期初客戶數
Logo churn = 1 − logo retention；Revenue churn 用金額分子——兩者不可互推
```
- 基準（私有 SaaS，按 ACV 分層）：ACV <$12K → GRR 90%／NRR 98%；$12K–250K → 91%／102%；>$250K → 95%／106%。公開 SaaS NRR 平均約 114%（頂部 110–130%）；logo retention 平均約 85%。NRR 全距 60%（差）–150%+（極佳）。
- **NRR 遮蔽問題**：NRR>100% 可能掩蓋 GRR 危機——「大量小客戶流失被少數大客戶擴張蓋住」；85% GRR＋110% NRR 是危險組合。**兩線必須並列呈現**。

### 5.3 口徑陷阱清單（BI 頁面的「口徑說明」note 直接取材）✅官方＋◑第三方

1. **Snapshot vs cohort**：NRR/GRR 正規定義是**鎖定同一群客戶**（一年前 cohort 的當期 MRR ÷ 當時 MRR），不是兩張快照相除——快照法會把新客混入分子。
2. **月流失率被成長稀釋**：`當月流失 MRR ÷ 總 MRR` 的分母含新增 MRR，高速成長期會**低估**流失（SaaS Capital 明言這是最不可靠的指標）。
3. **Churn 認列時點**＝服務期末，不是按下取消的日子（提前取消但服務到期末者，期末才算流失）。
4. **Reactivation 不算留存**：回流客計入 reactivation movement，不得美化 retention。
5. **月約年約混算**：未正規化（年繳÷12）直接相加＝口徑錯誤。
6. **排除項**：setup fee、實施費、專業服務、**同月內的 upsell**（避免把首月加購灌成 expansion）。
7. **Usage 型收入波動**：用 **TTM（滾動 12 月）平滑**再算留存。
8. **NRR 遮蔽 GRR**（§5.2）。
9. **頭部集中**：大客戶佔比高時，全體 NRR 無意義，須按 ACV／GMV 級距分層。
10. **Logo vs revenue 不可互推**：logo churn 高＋revenue churn 低＝長尾小客戶在流失，是先行指標而非雜訊。

### 5.4 Cohort 留存矩陣 ✅官方（方法）

- 以**取得月份分群**（列）×**經過月數**（欄）的三角矩陣，格值＝該 cohort 於第 n 月仍留存的收入 %（或 logo %）；對角線為最新資料。
- 讀法：**縱向**（同一經過月比不同 cohort）看 onboarding／ICP 是否在改善；**橫向**看衰減曲線形狀（前 3 月陡降＝激活問題；長尾持平＝核心價值成立）。
- 分段維度：方案／GMV 級距／來源渠道（自來 vs 代理商引薦——連回模組 1：**代理商引薦客戶的留存要單獨出 cohort**，這是夥伴等級評定的依據之一，△推測）。

### 5.5 方案轉化漏斗與模組滲透率 ◑第三方（基準值）＋△推測（滲透率定義）

- 漏斗：visitor → signup → activation（首個關鍵動作）→ trial → paid → retained。試用轉付費基準（ChartMogul 2026／First Page Sage）：
  - **要信用卡（opt-out）**：中位 25–35%、優 50–60%（FPS 實測 48.8%）；
  - **免信用卡（opt-in）**：中位 4–6%、優 10–15%（FPS 18.2%）；
  - freemium 3–5%（優 8–12%）；每千訪客終端付費：要卡 10.5 人 > 免卡 3.6 人（要卡制**總量**反而高，但代價是 signup 減半——35 註冊 vs 45）。
  - 我們 14 天 trial（33 §2.1）屬免卡制 → 儀表板基準線掛 4–6%，並把「補齊付款方式」作為 activation 事件單獨追蹤。
- **模組滲透率（attach rate）**：`啟用模組 X 的活躍付費租戶 ÷ 全部活躍付費租戶`；收入口徑另算 `模組 X 的 MRR ÷ 總 MRR`。真相源＝`shop_entitlements`（§3.2）。陷阱：**方案內含 vs 單獨加購須分開統計**（內含不代表使用；加購才是付費意願信號），再疊「實際使用率」（30 天內有事件）成三層：內含→啟用→活躍。Entitlement 的「下一週期生效」會讓滲透率**滯後一個計費週期**，圖上須註記。
- **Quick ratio** ＝ `(New + Expansion + Reactivation) ÷ (Churn + Contraction)`，>4 為健康成長（業界慣例，△非硬標準）。

### 5.6 我們的設計落點 △推測（設計建議）

- 表：`mrr_movements`（shop_id, movement_type, amount_cents, occurred_on, subscription_id, prev_plan/next_plan, merge_window_key）由 `billing_subscriptions` 事件派生，**歸併窗 24h**（§5.1 陷阱）；`platform_metric_rollups` 擴充 NRR/GRR/logo 欄。**全部 BI 卡片從 rollup 出**（CLAUDE.md 鐵律 7；37 號 billkpi 同源）。
- 畫面五件：MRR waterfall（六色 movement）／NRR+GRR 雙線（附 §5.3 口徑 note，仿 37 `ratecaveat` 不可關閉）／cohort 熱力三角／trial 漏斗（分要卡免卡）／模組滲透三層橫條。

---

# 第二部分：三端對接矩陣與跨端斷點風險

## 6. 功能 × 三端 × API 家族 × 資料同源（23 條）

> 讀法：每條功能線寫「platform 後台看到/做什麼 → 商家 admin 看到/做什麼 → storefront 表現什麼 → 走哪個 API 家族 → 資料同源在哪」。API 家族代號：**P**＝Platform GraphQL（`/platform/api/{v}/graphql.json`，35–39 號）；**A**＝Admin GraphQL（28 §1–14）；**S**＝Storefront HTTP（28 §16：SSR 頁面＋Ajax/JSON＋SEO 面）；**L**＝Liquid drops（26 號，進程內直讀，25 §6）；**W**＝Webhooks（28 §15）。同源表以 36–39 號資料模型章為準。

| # | 功能線 | Platform 後台 | 商家 Admin | Storefront | API 家族 | 資料同源 |
|---|---|---|---|---|---|---|
| 1 | 商店生命週期（12 態） | 狀態機單一入口：凍結/解凍/關店/刪除，原因碼必選＋審計（36 號） | 狀態橫幅；`frozen` 唯讀且**帳單頁仍可讀**；`restricted` 僅帳單/申訴/換銀行帳號 | `active` 正常；`paused` 可逛**結帳關**；`frozen` 503+noindex（**30 天後訂單狀態頁恢復**）；`closed` 410 | P（轉移 mutation）；A（admin 只讀 `shop.status` 衍生 UI）；S（middleware 按狀態切回應） | `shops.status`＋`shop_restrictions`（六旗標）；middleware 讀同一列（33 §2.1/D10） |
| 2 | KYC 與收款開通 | 審核佇列五分類排序、三補救路徑、駁回原因碼（36 號） | 補件表單＋`requirements` 倒數橫幅；通過前收款不可用 | 未過 KYC：結帳只允許測試模式或隱藏付款 | P（審核）；A（商家補件 mutations）；S（結帳 gating） | `kyc_submissions`/`kyc_requirements`/`kyc_documents`；結帳 gating 讀 `payment_channels.status` |
| 3 | 方案與模組訂閱 | 方案目錄（product/price immutable）＋grandfathered 檢視＋entitlement 重算工具（§3） | 「方案與帳單」頁：當前方案/加購/升降級自助；模組 UI 隨 entitlement 出現/消失 | 間接：模組決定前台能力（如禮品卡/多幣） | P（方案 CRUD＋覆寫）；A（商家自助升降級）；L（`shop` drop 暴露能力位） | `billing_subscriptions`＋`plan_features`/`shop_entitlements`（§3.2 本地持久化） |
| 4 | 配額 enforcement | 三段式 log_only/warn(60%)/error(100%)；`limits_overrides` 覆寫＋審計（36/D1） | 用量頁紅橘綠；達 error 段操作被擋（`LIMIT_EXCEEDED`） | 前台 Ajax 面吃滿回 **429+Retry-After**（D4：GraphQL 面回 THROTTLED） | P（覆寫）；A（userErrors）；S（429） | `config/limits.yml`＋`limits_overrides`＋用量 counter；三端讀**同一 resolver** |
| 5 | 金流通道與撥款 | 通道/商戶號/MCC/費率（四眼）＋撥款排程 T+4＋保留金/負餘額（37 號） | 收款設定顯示通道狀態與撥款日曆；**不可見**平台側費率成本價 | 結帳顯示可用付款方式（通道 active 才出現） | P（通道與撥款）；A（`paymentProviders` 28 §11）；S（結帳 POST 15 號） | `payment_channels`/`payout_schedules`/`payout_runs`；結帳付款方式清單同源 `payment_channels` |
| 6 | 爭議 | 案件佇列＋VAMP/ECM 雙分母監控＋雙欄（回報/估算）（37 號） | 爭議清單＋舉證上傳＋期限倒數 | 無直接呈現（買家在卡行端發起） | P（監控與處置）；A（舉證 mutations）；W（`disputes/*` 通知商家，△28 首發未含需增補） | `disputes`/`dispute_metrics_monthly`；商家端讀 WHERE shop_id 同表 |
| 7 | 違規處置與申訴 | 積分階梯＋處置動作（下架/限流/凍結）＋申訴佇列 SLA 時鐘（38 號） | 處置通知＋申訴表單＋狀態（待審/補件/維持/撤銷） | 商品被下架＝前台 404/下架頁；店級處置見 #1 | P（處置與裁決）；A（申訴提交）；S（下架呈現） | `violation_cases`/`violation_points_ledger`/`appeals`；商品下架寫回 `products.status` |
| 8 | 電子發票 | 字軌餘量監控＋憑證到期告警＋作廢/折讓佇列（38 號） | 發票設定（載具/捐贈/開立時機）＋單張發票操作 | 結帳收集載具/統編；訂單狀態頁顯示發票號 | P（字軌治理）；A（設定與單張操作）；S（結帳欄位＋L 顯示） | `einvoice_settings`/`einvoice_tracks`＋訂單發票欄；結帳欄位 schema 同源 settings |
| 9 | 網域與憑證 | 平台萬用憑證（DNS-01，D12）到期監控；租戶自訂域 DNS 檢查/重驗 | 網域頁：TXT 挑戰＋CNAME 狀態＋設主網域 | 網域生效＋301 收斂（30 §9-3）＋HTTPS | P（平台域）；A（`domainCreate` 等 28 §11）；S（301/憑證） | `domains`（驗證狀態機）；storefront router 與 admin 讀同表 |
| 10 | 主題安裝與編輯 | 主題市場上架審核（§4.3–4.4）；問題主題全平台下架 | 主題庫＋編輯器（28 §10 editor API）＋發布 | 發布版渲染；preview token 看草稿 | P（審核）；A＋editor 內部 API；L（全部 drops）；W（`themes/publish`） | `themes`/`templates`/`theme_settings`；發布指標 `themes.role=main` |
| 11 | Feature flag 灰度 | flag 生命週期＋cohort 定向＋rolling release 逐階段批准＋kill switch（39 號） | 功能出現/消失（無 flag 管理 UI）；逐店覆寫在平台租戶詳情 | 主題功能出現/消失（L 讀能力位） | P（flag CRUD/rollout）；A/L 僅消費 | `feature_flags`/`flag_targets`/`rollouts`（D5 獨立表為權威） |
| 12 | 維護視窗 | 排程＋對外狀態頁發布＋**同時暫停 webhook 投遞**（39/33 §2.12） | 唯讀＋預告橫幅（倒數） | 維護頁（503+Retry-After） | P（排程）；S（維護頁）；W（暫停/恢復補投） | `maintenance_windows`（39 號）；三端讀同一排程表 |
| 13 | 公告與棄用通知 | audience_query 定向＋排程＋已讀率（39 號） | 通知中心＋admin 頂部 banner；API 棄用倒數 | 無 | P（發布）；A（已讀回執） | `announcements`（read_receipts） |
| 14 | 多語多幣 Markets | 平台側僅監控（市場數配額）；匯率源設定 | Markets CRUD＋priceList＋webPresence＋翻譯（28 §13） | `/{locale}` 前綴＋market 網域＋幣別切換（localization Ajax） | A（§13 全套）；S（§16 路由＋localization）；L（1.11 在地化 drops） | `markets`/`price_lists`/`translations`（29 號）；SSR RequestContext 承擔 @inContext |
| 15 | 訂單全鏈（成立→出貨→退款） | 跨租戶訂單檢索（風控視角）；異常訂單處置 | 訂單列表/詳情/履約/退款（28 §4–6） | 結帳 POST 成單→訂單狀態頁→退款通知 | S（結帳 POST）；A（§4–6）；W（orders/* 7 topics＋refunds/create）；P（唯讀跨租戶） | `orders`/`fulfillments`/`refunds`＋`order_transactions`；金額全鏈 integer cents |
| 16 | 庫存 | 配額監控（SKU 數上限） | 庫存頁＋調整（`inventoryAdjustQuantities` 28 §3，冪等） | PDP/加購物車按 `available` 擋超賣 | A（§3）；S（cart Ajax 檢查）；W（`inventory_levels/update`） | `inventory_levels`（恆等式 06 §5）；前台可售數與 admin 同一查詢 |
| 17 | 折扣 | 濫用監控（超額折扣告警，△） | 折扣 CRUD（28 §8）＋用量統計 | 購物車/結帳套用＋自動折扣顯示 | A（§8）；S（結帳計價）；L（`discount_application` drops） | `discounts`/`discount_applications`；**用量計數併發要害**（CLAUDE.md） |
| 18 | 顧客帳戶 | DSR 佇列（GDPR 30 天/CCPA 45 天雙時鐘，D3）＋redact 執行 | 顧客列表/詳情/segments（28 §7） | `/account/*` 登入/訂單/地址；redact 後匿名化 | A（§7）；S（account 路由）；P（DSR）；W（customers/redact 類，28 §15 privacy topics） | `customers`/`customer_addresses`＋`dsr_requests`/`legal_holds`（hold 優先） |
| 19 | 分析數字同源 | 平台 KPI/GMV 圖（`platform_daily_rollups`）＋BI 五件（§5.6） | pulse 卡/報告/liveView（28 §14） | 無（但产生事件：sessions/轉化） | A（§14）；P（平台 rollup query） | **rollup 服務單一出口**（19 號；鐵律 7）；平台 GMV 口徑＝已付款订单，與商家報告同 rollup 鏈 |
| 20 | Webhook | 失敗監控＋手動重試＋自動刪除訂閱前告警（32 §3-4） | 訂閱 CRUD（28 §15）＋投遞記錄 | 無 | A（訂閱）；W（投遞：HMAC＋8 次/4h 退避）；P（監控） | `event_outbox`＋webhook 訂閱表；**維護視窗聯動 #12** |
| 21 | 審計與代登入 | 全域審計（before/after、append-only）＋授權式代登入（4 位碼+60 分鐘 TTL） | **「本店被平台做過什麼」透明頁**（33 §7-4 差異化）＋代登入常駐橫幅 | 無 | P（審計 query＋access_grants）；A（透明頁 WHERE shop_id） | `platform_audit_logs`（shop_id 可空）＋`access_grants`；寫入動作 `impersonated:true` 雙寫 |
| 22 | 代理商與 collaboration（W5 前瞻） | 夥伴列表/歸屬裁決/佣金撥款批次（§1.7） | collaborator 請求收件匣：看自動生成角色→接受/拒絕；4 位碼在安全設定 | 無 | P（partner 域）；A（商家審批 mutations）；Partner Portal（獨立入口，走 P 的 partner scope） | `partners`/`partner_client_links`/`partner_commission_entries`＋`access_grants` |
| 23 | 集團多店（W5 前瞻） | 組織列表＋店數配額＋加入審批工單（§2.4） | 總部 admin：商品/主題下發＋分店結算報表；分店 admin：受控編輯（下發鎖） | 各分店獨立 storefront（或 fulfillment_node 模式無前台） | P（組織治理）；A（org 層擴充 scope）；S（各店獨立） | `organizations`/`organization_stores`/`org_product_pushes`；下發鎖寫在資源列（如 `products.pushed_locked`） |

**與 28 §17 的關係**：§17 是「客戶端 × API 面 × 認證」三行簡表；本表把它展開到功能線級。之後做 API 交叉核實時，逐條檢查：該功能線在其 API 家族欄列出的每個面**都有對應操作**（缺=補 mutation/route），且同源欄的表是三端讀取的唯一真相。

## 7. 跨端斷點風險清單（16 條，各附偵測與防範）

> 定義：「platform 改了，admin／storefront 沒反映」或反向的狀態不一致 bug。每條格式：**風險場景 → 偵測手段 → 防範手段**。防範共通原則先立三條：①跨端狀態一律**事件驅動失效**（outbox → 消費者），不靠 TTL 自然過期；②每個快取鍵帶**版本 stamp**（如 `shop_state_version`），寫路徑 bump、讀路徑比對；③32 §3-1 的**合成巡檢 job**（10 分鐘）從「平台改動清單」抽樣打三端驗證。

| # | 風險場景 | 偵測 | 防範 |
|---|---|---|---|
| 1 | **凍結後 storefront 快取未失效**：`frozen` 已寫入但 CDN/頁面快取仍出貨架，503+noindex 未生效（買家繼續下單到凍結店） | 合成巡檢：狀態轉移事件後 60 秒內打前台首頁與結帳，斷言 503；監控「frozen 店的 orders/create」＝恆為 0 的守恆指標 | 狀態轉移副作用**同步** purge 快取（同 transaction 後的 outbox 消費者）；storefront middleware **每請求讀 `shops.status`**（Solid Cache read-through＋版本 stamp），不信任頁面級快取 |
| 2 | **上限覆寫後 admin 快取的 limits 未刷新**：`limits_overrides` 已提高，商家 admin 仍按舊上限擋操作（或反向：調低後仍放行） | 對帳 job：每小時抽樣比對「enforcement 實際使用的 limit 值」vs `config/limits.yml`+overrides 合成值；不一致告警 | limits resolver 單一入口（禁止各處自讀 yml）；覆寫寫入時 bump `shop.limits_version`，admin SPA 的 limits 查詢帶版本、mismatch 即重拉 |
| 3 | **flag 覆寫與 Liquid 渲染快取**：逐店開 flag 後主題功能未出現（section 渲染結果被快取） | flag 變更事件後合成巡檢渲染受影響 template，斷言功能 DOM 存在 | 渲染快取鍵納入 `flags_digest`（該店啟用 flag 集的 hash）；flag 變更→digest 變→快取自然 miss |
| 4 | **方案降級後模組 UI 仍可見**：entitlement 依 §3.2 於下一週期生效，但我們若選「立即生效」而 admin bundle 快取舊 entitlement，商家仍能進已失權模組（操作被後端拒＝壞體驗；不拒＝越權） | 每日對帳：`shop_entitlements` vs 實際 middleware 放行記錄 diff；audit 中出現「無 entitlement 卻成功」→ P1 告警 | 前後端同源：SPA 啟動與 `entitlements.updated` 事件皆重拉 entitlement；**後端 middleware 為準**（UI 只是鏡子）；寬限期內顯示唯讀而非隱藏（防資料被鎖死） |
| 5 | **收款凍結只擋 UI 不擋 API**：`payin` 旗標下結帳頁停用，但 Ajax `/checkout` POST 或舊 tab 仍能提交收單 | 守恆指標：payin 凍結店的成功收款交易數恆 0；異常即告警＋自動退款佇列 | 旗標檢查放在**收單 service object**（單一入口），不是 controller/前端；結帳 session 建立與 confirm 兩點都驗 |
| 6 | **維護視窗 webhook 未暫停或恢復後未補投**：視窗內事件照發（打到租戶維護中的系統）或恢復後 outbox 積壓遺失順序 | 視窗期間 webhook 發送計數應為 0 的守恆監控；恢復後 outbox lag 指標 | 視窗開始事件→投遞 worker 進 pause（39 號）；事件**照常入 outbox 不丟**，恢復後按序補投；視窗結束自動觸發補投 job 並回報積壓量 |
| 7 | **網域憑證輪換斷點**：DNS-01 萬用憑證換發後邊緣節點仍持舊憑證，或租戶自訂域 CNAME 改指後 admin 顯示「已驗證」但前台 TLS 失敗 | 合成巡檢對全部自訂域做 TLS 握手＋到期天數檢查（30 天前告警，32 §3-4） | 憑證部署採兩段式（新舊並存→切換→回收）；`domains.verified_at` 之外加 `last_probe_ok_at`，UI 顯示探測值而非驗證歷史值 |
| 8 | **KYC 通過但通道開通 async 未完成**：平台審核通過→admin 顯示「可收款」，但收單通道 MCC 指派仍在途（37 號：MCC 為 async 回寫），買家結帳失敗 | 「kyc approved 且 channel != active 超過 SLA」佇列（36 號審核佇列的異常分頁） | admin 收款狀態顯示**取 `payment_channels.status`**（終態），不取 KYC 決定；結帳付款方式清單同源（矩陣 #5），通道未 active 前不渲染該支付方式 |
| 9 | **爭議凍結提現與撥款批次競態**：`payout` 凍結旗標落表時，當期撥款 run 已生成批次並送出 | 撥款 run 執行前重讀旗標的斷言測試；對帳：凍結期間 `payout_runs` 中該店金額恆 0 | 撥款 job 於**送出前最後一刻**重驗 `shop_restrictions`（不是批次生成時）；已送出者進 clawback 流程並審計 |
| 10 | **發票字軌耗盡**：storefront 結帳承諾開立發票，但該店字軌餘量歸零→出貨開票失敗（法遵風險） | 字軌餘量門檻告警（38 號）；「已出貨未開票」佇列齡監控 | 餘量低於 N 自動請購新字軌工單；耗盡時開票 job 轉 pending 並通知，**不阻擋結帳**（發票補開，交易照常）——口徑寫入 38 號驗收 |
| 11 | **Markets 價格/匯率更新後快取與 feed 未跟上**：priceList 改價後前台快取價與 feed（30 號 GMC）殘留舊價（廣告價不符=GMC 停權風險） | feed diff 監控：抽樣比對 feed 價 vs 現行 priceList；GMC 拒登率告警 | 價格寫路徑發 `products/update` webhook→feed 增量重推＋IndexNow（28 §15 既有鏈路）；前台價格快取鍵含 `price_list_version` |
| 12 | **分析數字漂移**：平台 KPI 卡、商家 pulse、報告頁各自寫 SQL，同一 GMV 三個數 | CI 靜態檢查：分析類 query 只准 import rollup 服務；每日抽樣三端同指標斷言相等 | 鐵律 7 的執行面：rollup 服務單一出口＋快照表；平台 GMV 與商家 GMV 差異只允許來自「口徑維度」（幣別/時區），且維度註記在 UI |
| 13 | **webhook 訂閱被自動刪除而商家不知情**：連續失敗自動刪除（28 §15）後整合靜默斷線 | 刪除前的「連續失敗中」狀態暴露在商家 admin＋平台監控（32 §3-4 webhookfails） | 自動刪除前發 email＋admin 通知（倒數）；刪除動作本身發 `webhook_subscription/removed` 類通知（△28 首發 topics 未含，需增補）＋落審計 |
| 14 | **代登入寫入未標記**：平台 staff 經代登入操作，events 少了 `impersonated:true`（商家透明頁失真=信任破產） | 測試：代登入 session 下每類寫入斷言 flag；審計對帳：`access_grants` 活躍時段內該店 events 必含標記 | flag 注入放在 session context 層（單一入口），非各 mutation 自帶；32 §4 的禁止動作清單在同層攔截 |
| 15 | **`paused` 狀態 job 未停**：暫停營業但棄單挽回/禮品卡到期提醒等 job 照發（33 §2.1：paused 須停折扣/棄單挽回/禮品卡/第三方通路） | 守恆監控：paused 店的對外 email 發送數恆 0（豁免帳單類） | job 統一走 tenant-state guard（第一參數還原租戶後先驗狀態，35 §2.1 慣例）；guard 清單由狀態機副作用表生成，不散落各 job |
| 16 | **closed 店的 SEO 殘留**：前台已 410 但 sitemap 分片/GMC feed/IndexNow 仍列該店 URL（或子網域被詐騙者仿冒重註冊） | 巡檢：closed 店的 sitemap 應為空、feed 應下架全量；子網域重用檢查恆 fail | 關店副作用鏈補「SEO 撤除」步驟（sitemap 重生成＋feed 全量下架＋IndexNow 刪除通知，30 §9 死鏈規範）；子網域永久保留（33 §2.1 已定） |

**驗收掛接**：以上 16 條各自成為對應模組驗收清單的新增條目（36–39 號第 10 節）；共通的三原則（事件驅動失效/版本 stamp/合成巡檢）寫入 11 §0 七維度的「資料」與「可觀測」維度檢查項。

---

## 8. 未查證與待複核

- Shopify collaborator 可請求權限的**全集清單**官方未列（§1.2）；Dev Dashboard managed stores 列表欄位為推測（§1.1）。
- 有贊渠道商的客戶報備/保護期細則、SHOPLINE partner 金銀銅升級門檻與分潤比例、微盟服務商後台——均未公開（§1.5–1.6 標△部分）。
- App 審核 7–14 工作天為第三方整理（§4.1）；Theme 審核無公開 SLA。
- VTEX franchise 的訂單路由規則細節（按庫存/區域的優先序）官方頁未展開（§2.3）。
- 28 §15 首發 24 topics 未含 disputes 與 webhook 訂閱刪除通知（矩陣 #6、風險 #13 提出增補）——需回寫 28 號。
- SaaS 基準值（§5.2/5.5）取自 2024–2026 各家調查，逐年更新；建檔時以區間而非單點寫入儀表板。

## 9. 來源

**Shopify Partner／組織**：[Requesting access to a client's store](https://help.shopify.com/en/partners/dashboard/managing-stores/request-access)・[Collaborator accounts](https://help.shopify.com/en/manual/your-account/users/security/collaborator-accounts)・[Dev Dashboard: Collaborations](https://shopify.dev/docs/apps/build/dev-dashboard/stores/collaborations)・[Client transfer stores](https://shopify.dev/docs/apps/build/dev-dashboard/stores/client-transfer-stores)・[Transferring stores to clients](https://help.shopify.com/en/partners/dashboard/managing-stores/hand-off-development-stores)・[Partner earnings](https://help.shopify.com/en/partners/partner-program/how-to-earn)・[Getting paid](https://help.shopify.com/en/partners/partner-program/getting-paid)・[Manage your payouts](https://help.shopify.com/en/partners/manage-account/manage-payouts-invoices/payouts)・[Payout CSV changes](https://shopify.dev/changelog/changes-to-the-partner-payout-csv-and-app-earnings-csv)・[Revenue share](https://shopify.dev/docs/apps/launch/distribution/revenue-share)・[Organization settings](https://help.shopify.com/en/manual/organization-settings)・[Expansion stores](https://help.shopify.com/en/manual/organization-settings/expansion-stores)・[Group a store to an organization](https://help.shopify.com/en/manual/your-account/manage-orgs-and-stores/manage-orgs/group-store)・[Change or transfer ownership](https://help.shopify.com/en/manual/your-account/manage-orgs-and-stores/change-transfer-ownership)

**上架審核**：[App requirements checklist](https://shopify.dev/docs/apps/launch/app-requirements-checklist)・[App review process](https://shopify.dev/docs/apps/launch/app-store-review/review-process)・[New app submission experience](https://shopify.dev/changelog/new-app-submission-experience-in-the-partner-dashboard)・[Theme submission](https://shopify.dev/docs/storefronts/themes/store/review-process/submit-theme)・[Theme store requirements](https://shopify.dev/docs/storefronts/themes/store/requirements)・◑[Growave: app review timelines](https://www.growave.io/blog/how-long-does-shopify-app-review-take)

**華語生態**：[有贊連鎖操作手冊](https://help.youzan.com/displaylist/detail_4_4-2-41756)・[有贊渠道合作](https://www.youzan.com/intro/qudao)・[SHOPLINE Partner](https://help.shopline.com/hc/en-001/articles/28196619744537-SHOPLINE-Partner)・[SHOPLINE 合作夥伴（台灣）](https://shopline.tw/cooperate)・[微盟招商](https://www.weimob.com/zs)

**VTEX**：[Store architecture](https://developers.vtex.com/docs/guides/store-architecture)・◑[VTEX Franchise Account 解析（e-Plus）](https://agenciaeplus.com.br/en/conta-franquia-vtex-o-que-e-e-como-funciona/)

**Stripe Billing**：[How products and prices work](https://docs.stripe.com/products-prices/how-products-and-prices-work)・[Entitlements](https://docs.stripe.com/billing/entitlements)・[Coupons and promotion codes](https://docs.stripe.com/billing/subscriptions/coupons)

**SaaS 指標**：[SaaS Capital: revenue retention fundamentals](https://www.saas-capital.com/blog-posts/essential-saas-metrics-revenue-retention-fundamentals/)・[Churnkey: GRR vs NRR vs logo](https://churnkey.co/blog/gross-retention-vs-net-retention-vs-logo-retention-what-they-are-how-to-optimize-them)・[ChartMogul: Understanding MRR movements](https://help.chartmogul.com/hc/en-us/articles/4416682609426-Understanding-MRR-movements)・◑[Userpilot: trial conversion benchmarks](https://userpilot.com/blog/saas-average-conversion-rate/)（引 ChartMogul 2026／First Page Sage）
