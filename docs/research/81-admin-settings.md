# 81 — 設定 按鈕級 teardown（R12，2026-08-14 實測）

> 六層標準（層⓪載入紀律／層①按鈕級／層②值域窮舉／層③架構分析／層④CSS 三段式／層⑤help 雙源／層⑥條件控件三源）。
> 實測：`chill-love-u5q5mnzq`（Shopify Plus，組織 CHILLING TECH LIMITED）。全程從側欄真實 `href` 導航（鐵律 12.1）。
> 🔴 **12.2 的例外一次**：建立自訂角色被「步進式再驗證（輸入密碼）」擋下——**我不輸入密碼**（見 §2.6），
> 因此角色的 create→delete 未走完；權限目錄本身已完整取得（新增角色表單即完整目錄）。

---

## §0 架構圖（層③）

### §0.1 🔴 設定是「全螢幕覆蓋層」不是一般頁面
`/settings` **302 → `/settings/general`**，右上角有 **✕ 關閉**，關閉後回到覆蓋前的頁面。
⇒ 我方 `openSettings()` overlay ＋ `closeSettings()` 的做法**與本尊同構**（含 focus trap 與 save bar 浮於 overlay 之上）。

### §0.2 🔴 側欄是兩層：組織 ＋ 商店（本輪最重架構發現）
```
CHILLING TECH LIMITED（組織）
├─ 組織      /settings/organization-details
└─ 使用者    /settings/organization-account          ← 🔴 使用者在組織層
    ├─ 角色   /settings/organization-account/roles
    └─ 安全性 /settings/organization-account/security

CHILL LOVE（商店，chill.deals）
├─ 一般      /settings/general
│   ├─ 商店聯絡詳細資訊 /settings/general/store-contact-details
│   ├─ 中繼欄位         /settings/general/metafields
│   ├─ 品牌             /settings/general/branding      ← 🔴 品牌是「一般」的子頁
│   └─ 商店活動記錄     /settings/general/activity
├─ 方案      /settings/plan
├─ 帳單      /settings/billing
├─ 付款      /settings/payments
├─ 結帳      /settings/checkout
├─ 顧客帳號  /settings/customer_accounts
├─ 運送與配送 /settings/shipping
├─ 稅額與關稅 /settings/taxes
├─ 地點      /settings/locations
├─ 應用程式  /settings/apps
├─ 銷售管道  /settings/sales_channels
├─ 網域      /settings/domains
├─ 顧客事件  /settings/customer_events
├─ 通知      /settings/notifications
│   ├─ 顧客通知 /settings/notifications/customer
│   ├─ 員工通知／出貨要求通知／Webhook（三個同層子頁）
├─ 中繼欄位與 metaobject /settings/custom_data
├─ 語言      /settings/languages
├─ 顧客隱私  /settings/privacy
└─ 政策      /settings/legal
```
另有 `/settings/account`（個人帳號，非商店設定）。
🔴 **市場不在設定裡**（頂層 `/markets`，R10 已證）；**禮品卡不在設定裡**（產品區資源，R8 已證）。

### §0.3 🔴 2026 已改為以角色為基礎的存取控制（RBAC）
使用者頁橫幅原文：「**以角色為基礎的存取控制現已啟用**／現在系統已將您組織內擁有任何存取權限的
使用者集中顯示於一處，並為其自動指派角色。請審查存取權限，並移除不再需要權限的使用者。」
⇒ 舊的「每個員工一份 checkbox 權限表」已被取代為 **使用者 ↔ 角色 ↔ 權限** 三段模型。
我方原型的商店級 staff 權限是**舊模型**，架構級落差（R12-STRUCT1）。

### §0.4 設定分頁映射表（本尊 20 ↔ 我方 23）
| 本尊 | slug | 我方 key | 判定 |
|---|---|---|---|
| 組織 | organization-details | `org` | ✅ |
| 使用者 | organization-account | `users` | 🔴 我方掛商店層、無角色/安全性子頁（R12-STRUCT1） |
| 一般 | general | `general` | ⚠ 我方缺四個子頁 |
| 方案 | plan | `plan` | ✅ |
| 帳單 | billing | `billing` | ✅ |
| 付款 | payments | `payments` | ✅ |
| 結帳 | checkout | `checkout` | ✅ |
| 顧客帳號 | customer_accounts | `accounts` | ✅ |
| 運送與配送 | shipping | `shipping` | ✅ |
| 稅額與關稅 | taxes | `taxes` | ✅ |
| 地點 | locations | `locations` | ✅ |
| 應用程式 | apps | `apps` | ✅ |
| 銷售管道 | sales_channels | `channels` | ✅ |
| 網域 | domains | `domains` | ✅ |
| 顧客事件 | customer_events | `events` | ✅ |
| 通知 | notifications | `notifications` | ⚠ 我方缺四個子區 |
| 中繼欄位與 metaobject | custom_data | `customdata` | ✅ |
| 語言 | languages | `languages` | ✅ |
| 顧客隱私 | privacy | `privacy` | ✅ |
| 政策 | legal | `policies` | ✅（🔴 slug 是 `legal` 不是 `policies`） |
| — | — | `brand` | 🔴 **歸屬錯位**：本尊在 `general/branding` 子頁（R12-STRUCT2，同 R9-STRUCT1 形態） |
| — | — | `giftcards` | 🔴 本尊設定樹**無此分頁**（禮品卡＝產品區資源）——待查我方此頁承載什麼（R12-V1） |
| — | — | `seo` | ⚠ 本尊無此分頁；但 §A **G20**（AI 爬蟲開關三組不合一）與 30 號 SEO 研究要求我方有落地處 ⇒ **我方獨有，合法**，應在頁面註明出處 |
| 商店活動記錄 | general/activity | — | 🔴 我方**無**（R12-MISS1） |

---

## §1 使用者與權限（層②核心；我方最薄的 ⑨）

### §1.1 使用者列表
- 頁首動作【3】：匯出／匯入／**新增使用者**
- 欄【4】：使用者／狀態／（無標題的盾牌欄＝安全登入狀態，🚫 表示未強制）／角色
- 實測列：`LEEKEN` ｜ 狀態 `有效` ｜ 🚫 ｜ 角色 `組織擁有人, 商店擁有人`（**角色可多值**）
- 底部連結：深入瞭解使用者

### §1.2 預設角色【窮舉：10 個／4 類別】
| 類別 | 角色 |
|---|---|
| **組織**（4） | 應用程式開發人員／組織管理員／組織 POS 管理員／組織使用者管理員 |
| **合作夥伴**（1） | 協作者存取權限 |
| **銷售點 (POS)**（3） | POS 完整權限／POS 裝置設定／POS 使用者管理員 |
| **商店**（2） | 商店管理員／商店使用者管理員 |
- 列表欄【3】：名稱（可排序）／類別／員工（人數）；另有 `全部` 檢視 chip ＋ 搜尋 ＋ 排序鈕 ＋ 匯出 ＋ **新增角色**
- 🔴 **「組織擁有人／商店擁有人」不在這 10 個裡**——它們是**內建擁有人角色**，不出現在可管理的角色清單中。

### §1.3 新增角色表單
- 名稱（**≤255**，字元計數器）／說明（**≤255**）
- **角色類別下拉【窮舉：4】**（🔴 「角色類別決定可用的權限」）：
  - 組織 — 跨多個商店的權限
  - 商店 — 商店內的權限
  - 銷售點 (POS) — POS 內的權限
  - 合作夥伴 — 合作夥伴組織的權限
- 選定類別後才渲染權限樹：搜尋框 ＋ 「選取所有權限」總開關 ＋ **全部展開／全部收合** 切換連結
- **驗證錯誤原文**：`至少必須授予一項權限`

### §1.4 🔴 權限目錄（商店類別）【窮舉：115 個權限／17 群組／3 層】
> 結構：**群組列**（帶 `0/n` 計數＋摺疊 chevron）→ **子標題**（無 checkbox 的分隔文字）→ **權限**（x=415）→ **縮排子權限**（x=441）

| # | 群組 | 計數 | 權限（子標題以【】標示，縮排子權限以 ↳ 標示） |
|---|---|---|---|
| 1 | 首頁 | 0/1 | 首頁 |
| 2 | 訂單 | 0/20 | 檢視／管理訂單資訊／編輯訂單 ↳套用折扣／設定付款條件／使用信用卡收款／使用存放在保存庫中的付款方式扣款／記錄付款／請款／出貨與運送 ↳購買託運單標籤／取消／匯出／刪除　**【退貨與退款】** 退貨／退款至原始付款方式 ↳將先前已退款至商店抵用金的訂單超額退款至原始付款方式／退款至商店抵用金　**【未完成結帳作業】** 管理　**【爭議】** 管理 |
| 3 | 草稿 | 0/9 | 檢視／建立和編輯 ↳套用折扣／設定付款條件／使用信用卡收款／使用存放在保存庫中的付款方式扣款／標示為已付款並記錄付款／匯出／刪除 |
| 4 | 產品 | 0/11 | 檢視 ↳檢視成本／建立和編輯 ↳編輯成本 ↳編輯價格／匯出／刪除　**【庫存】** 管理庫存 (不含轉移)／檢視轉移 ↳管理轉移 ↳管理貨件 |
| 5 | 禮品卡 | 0/4 | 檢視／建立和編輯／匯出／停用 |
| 6 | 顧客 | 0/15 | 檢視／建立和編輯／清除個人資料／要求資料／匯出／合併／檢視商店抵用金交易 ↳編輯商店抵用金／刪除　**【公司】** 檢視／建立和編輯／指派員工至公司地點／刪除／檢視商店抵用金交易 ↳編輯商店抵用金 |
| 7 | 行銷 | 0/4 | 檢視、建立和刪除行銷活動與自動化作業　**【行銷活動】** 檢視／建立和編輯／刪除 |
| 8 | 折扣 | 0/1 | 檢視、建立和刪除 |
| 9 | 內容 | 0/11 | 選單　**【metaobject 定義】** 檢視／建立和編輯／刪除　**【項目】** 檢視／建立和編輯／刪除　**【檔案】** 檢視／建立／編輯／刪除 |
| 10 | Markets | 0/9 | 檢視／建立和編輯／刪除　**【目錄】** 檢視／建立和編輯／刪除　**【推出】** 檢視／建立和編輯／刪除 |
| 11 | 結帳和顧客帳號 | 0/3 | 檢視和編輯 ↳管理商店抵用金可見性 ↳管理身分識別提供者 |
| 12 | 快速銷售 | 0/1 | 在 Shopify 行動版上使用「快速銷售」 |
| 13 | 財務 | 0/4 | 檢視稅務文件／檢視餘額帳戶活動／檢視所有 Shopify Credit 帳戶活動／檢視支付款項 |
| 14 | 分析 | 0/2 | 報告／控制面板 |
| 15 | 網路商店 | 0/3 | 佈景主題 ↳編輯程式碼 (包含產生佈景主題區塊)／部落格貼文和頁面 |
| 16 | 應用程式開發 | 0/3 | 檢視由員工和協作者開發的應用程式 ↳開發 ↳啟用開發作業 |
| 17 | 設定 | 0/14 | 管理設定／檢視帳單並接收帳單電子郵件 ↳編輯帳單付款方式並支付帳單 ↳管理 Shopify 方案／管理應用程式帳單／管理付款設定／管理運送和配送／管理稅額和關稅／管理地點／管理網域 ↳將網域轉移至其他 Shopify 商店／檢視顧客事件 ↳管理和新增自訂像素／管理商店政策／管理和安裝應用程式與管道 ↳核准應用程式費用 |

🔴 **「推出」有自己的三個權限**（Markets 群組下）——與 R10（rollouts 頁）、R11（推出分析維度）串成同一條線：
推出是**一等資源**，需要獨立的權限、路由、分析維度。

### §1.5 🔴 父子權限是**真連動**，不只是縮排
實測：勾選縮排子項「套用折扣」→ **自動勾選其父項「編輯訂單」與群組基線「檢視」**。
⇒ 我方必須實作 **祖先鏈自動授予**（勾子 ⇒ 補齊所有祖先），不能只做視覺縮排。
⚠ **實測方法教訓**：用 JS `element.click()` 測**測不出來**（React 受控元件不吃程式化點擊，
是假陰性）；必須用真實滑鼠座標點擊。

### §1.6 🔴 建立角色要「步進式再驗證」（sudo mode）
按儲存後彈出：「**請驗證您的帳號以繼續／為加強安全性，請輸入您的密碼**」＋ 密碼欄（含顯示切換）＋ 驗證鈕。
⇒ **權限異動屬高敏動作，需重新輸入密碼**。我方若要對齊，須設計 step-up auth（帶時效的 sudo session）。
**本輪未輸入密碼**（我的硬性限制），因此角色的完整 create→delete 未走完（R12-V2）。

### §1.7 安全性頁
- **組織安全性**
  - 「安全登入方式為不強制要求」＋ 變更鈕 → 彈窗「變更安全登入規定」【窮舉：2】
    - **所有使用者皆必要** — 「您組織中的所有使用者皆必須透過密碼金鑰或兩步驟驗證等安全方式登入。**此規定不適用於 Shopify POS**。」
    - **特定使用者**（預設）— 「從個別使用者的頁面管理安全登入方式規定。未被強制要求使用密碼金鑰或兩步驟驗證的使用者，可能會讓您的組織面臨風險。」
  - 使用者活動記錄「監控並檢視使用者活動」＋ 檢視鈕
- **商店安全性 > 協作者**
  - 「授予設計師、開發人員和行銷人員存取此商店的權限。**協作者不計入您的員工上限**。」
  - **協作者請求代碼**（實測 4 位數 `6994`）＋ 產生新代碼鈕
  - 「分享此代碼，即可允許他人向您傳送此商店的協作者要求。**您仍須從「使用者」審核並核准此要求**。」
  ⇒ 兩段式：代碼降低誤加入風險，但**核准仍是必要步驟**。

---

## §2 一般設定【窮舉：9 張卡片】

| # | 卡片 | 內容 |
|---|---|---|
| 1 | 商家詳細資訊 | 「此商店中用於**金融產品、市場、app 和稅額**的商業實體」＋實體列（名稱／類型 私人公司／地址）＋`⋯`＋連結「在**組織設定**中管理實體」 |
| 2 | 商店聯絡詳細資訊 | 商店名稱＋email＋電話（列 →）／商店地址（列 →） |
| 3 | 開發商店 | 建立時間＋**提交**鈕（開發店專屬，條件性卡片） |
| 4 | 商店預設值 | 幣別顯示（🔴 說明：「**若要管理顧客看到的幣別，請前往 Markets**」）＋ 港元 (HKD HK$)；🔴 「**若要變更您的使用者層級時區和語言，請前往您的帳號設定**」 |
| 5 | 訂單 ID 格式 | 前綴／後綴＋即時預覽「您的訂單 ID 將顯示為 #1001、#1002、#1003，…」；說明「顯示於訂單頁面、顧客頁面和顧客訂單通知」 |
| 6 | 訂單處理 | **自動封存訂單**【2 條件】訂單已付款後／訂單已出貨並已付款後，或所有品項皆已退款時；說明「該訂單將從您的未完成訂單清單中移除」 |
| 7 | 商店資產 | 中繼欄位（→ general/metafields）／品牌（→ general/branding） |
| 8 | 資源 | 變更記錄｜Shopify 說明中心｜聘僱 Shopify 合作夥伴｜鍵盤快捷鍵｜商店活動記錄 |
| 9 | 組織和商店轉移 | 「此商店為用於測試的開發商店，因此無法轉移。」（條件性文案） |

🔴 **兩條結構事實推翻常見假設**：
1. **時區與語言不在商店設定**，在**使用者帳號設定**（per-user）。我方若把時區做成商店級單一值，
   與本尊模型不同——訂單時間顯示會因人而異（R12-V3）。
2. **商店幣別 ≠ 顧客看到的幣別**：這裡只是店幣（記帳/顯示基準），顧客幣別由 **Markets** 決定。
   與鐵律 3／R10 的市場幣別鏈是同一條線。

---

## §3 通知【窮舉：4 子區＋11 組 47 個顧客範本】

### §3.1 頁面結構
- 寄件者電子郵件（單一輸入框，說明「您的商店與顧客收發電子郵件所使用的電子郵件地址」）
- 子區【4】：**顧客通知**（通知顧客訂單與帳號事件）／**員工通知**（通知員工新訂單事件）／
  **出貨要求通知**（當您將訂單標記為已履行時，通知您的出貨服務供應商）／**Webhook**（將商店事件的 XML 或 JSON 通知傳送至某網址）

### §3.2 顧客通知範本目錄
| 組 | 數 | 範本（觸發時機） |
|---|---:|---|
| 訂單處理 | 3 | 訂單確認（顧客下單時）／訂單草稿發票（訂單草稿頁面建立發票時）／運送確認（標記為已履行時） |
| 到店取貨 | 2 | 已可到店取貨／顧客已取貨 |
| 當地配送 | 3 | 訂單開始當地配送／訂單已完成當地配送／訂單錯過當地配送 |
| 禮品卡 | 2 | 新的禮品卡（已發行或寄送時，給顧客或收件人）／禮品卡收據（顧客為禮品卡新增收件人時） |
| 商店抵用金 | 1 | 已發放商店抵用金 |
| 訂單異常 | 8 | 訂單發票（有未付餘額）／訂單編輯／訂單取消（顧客取消時）／訂單付款收據（自儲存付款方式扣款後）／訂單退款／未完成結帳作業／訂單連結（從已過期的訂單狀態頁面要求新連結時）／出貨作業發票 |
| 付款 | 4 | 付款錯誤／待處理付款錯誤／待處理付款成功／付款提醒（到期日當天或之後） |
| 銷售點 (POS) | 5 | POS 未完成結帳作業／POS 寄送購物車電子郵件給顧客／POS 與行動收據／POS 換貨收據／退貨收據 |
| 運送資訊更新 | 3 | 運送資訊更新（新增或更新追蹤編號）／配送中／已送達 |
| 退貨與取消 | 6 | 已建立退貨流程／**已建立訂單層級退貨單（🔴 僅限美國）**／退貨申請已核准／退貨申請已被拒絕／已收到要求／已拒絕取消要求 |
| 帳號與外展行銷 | 10 | 顧客帳號邀請／顧客帳號歡迎／顧客帳號密碼重設／顧客新增付款方式的要求／B2B 存取電子郵件／B2B 地點付款方式更新／聯絡顧客／顧客電子郵件地址變更確認／行銷訊息雙重確認加入／顧客行銷訂閱確認 |

🔴 **「已建立訂單層級退貨單（僅限美國）」是法域閘控的通知範本** ⇒ 通知範本集合**不是固定清單**，
要按 jurisdiction pack 過濾（鐵律 11／R12-V4）。

### §3.3 頁尾兩張非範本卡
- **Shopify Messaging**：「專為拓展業務而生，而且無須編寫程式碼就能使用的電子郵件工具」＋ 安裝鈕（app 推廣）
- **透過 Shop 再行銷**【4 開關，實測皆開】：購物車提醒／重新補貨／降價／瀏覽後離開
  說明：「將線上店面訪問數轉換為銷售。在 Shop 瀏覽您商品的 Shop 使用者，會收到提醒其購買的電子郵件和推播提醒。」
  ⇒ 這是**跨 app 的再行銷觸發器**，不是本店的通知範本；我方若沒有 Shop 等價物，此區不對應。

---

## §4 語言與 Translate & Adapt

- 頁首【3】：匯出／匯入／**新增語言**
- 卡片說明：「為您的商店新增翻譯平均可將跨境轉換提高 13%」
- 表格欄【3】：語言／狀態／網域，＋ 行動作
  - `英文（預設）` ｜ **已發布** ｜ 2 個網域 ▾ ｜ **[調整]** `⋯`
  - `繁體中文` ｜ **未發布** ｜ 2 個網域 ▾ ｜ **[翻譯]** `⋯`
- 🔴 **主動作鈕依狀態切換**：已發布 → 「調整」；未發布 → 「翻譯」
- **狀態值域【2】**：已發布／未發布
- **`⋯` 值域【5】**：發布／預覽／指派給網域／**設為網域預設（未發布時禁用灰）**／移除語言
  ⇒ 層⑥條件控件：`設為網域預設` 的啟用條件＝該語言已發布
- **Shopify Translate & Adapt**：獨立 app 卡片，狀態「已安裝」＋ **開啟**鈕
  ⇒ 🔴 翻譯編輯器**不是內建畫面**，是 app（同 R9 線上商店＝內嵌 app 的形態）。
  我方 70 號翻譯規格是自建內建面板 ⇒ 邊界問題與 R9-V1 同源（R12-V5）。
- 頁尾：「深入瞭解語言。**若要變更您的帳號語言，請管理帳號。**」（第三次指向帳號設定）

---

## §5 CSS 三段式（層④）

| # | 部位 | 本尊量測（實測） | 我方 token 映射（23 號） |
|---|---|---|---|
| 1 | 設定覆蓋層 | 內容區最大寬 ~1120px、左側欄寬 278px、覆蓋層圓角 12px、四周留白 32px、✕ 鈕 32px 見方 | `--w-overlay` `--r-300` `--sp-800` |
| 2 | 側欄項目 | 列高 32px、內距 8/12、圖示 16px＋間距 12px、字 13px/450、選中態背景 `#F1F1F1`＋圓角 8px | `--h-row-sm:32px` `--sp-200/300` `--r-200` `--bg-selected` |
| 3 | 側欄分區 | 組織／商店兩段之間 1px 分隔線＋上下 12px；段首標題 13px/600＋副標 12px `#616161` | `--hairline` `--fs-75` `--fg-subdued` |
| 4 | 設定卡片 | 圓角 12px、內距 20px、卡間距 24px、卡標題 14px/600、說明 13px `#616161` | `--r-300` `--sp-500` `--sp-600` |
| 5 | 可點列（→） | 列高 56px（雙行）、右側 chevron 16px、hover 背景 `#FAFAFA`、列間 1px 分隔 | `--h-row-lg:56px` `--bg-hover` |
| 6 | 權限樹 | 群組列高 48px＋計數右對齊；權限列高 32px；縮排階梯 **x=391/415/441（24px 一階）**；checkbox 16px | `--sp-600:24px` 階梯；`--h-row-sm` |
| 7 | 步進驗證彈窗 | 寬 360px、圓角 16px、圖示徽章 48px 圓形綠底、主鈕滿寬高 40px | `--w-modal-sm` `--r-400` |
| 8 | 狀態 badge | 高 20px、圓角 8px、字 12px/500；已發布＝綠底、未發布＝灰底 | `--badge-*` 既有族 |

---

## §6 對我方的裁定面（→ 71 §F）

1. **R12-STRUCT1（最重）**：使用者/權限模型是 **組織層 RBAC（使用者↔角色↔權限）**，
   我方是商店層 staff checkbox ⇒ 架構級改造，**M1 前必答**（影響 `shop_id` 邊界：角色可跨店）。
2. **R12-STRUCT2**：品牌歸屬錯位（本尊在 `general/branding` 子頁）。
3. **R12-MISS1**：商店活動記錄（`general/activity`）我方無。
4. **R12-V3**：**時區與語言是使用者層級不是商店層級** ⇒ 我方資料模型需要 `user.timezone`／`user.locale`。
5. **R12-V4**：通知範本集合**受法域閘控**（「僅限美國」實例）⇒ 範本清單要進 jurisdiction pack。
6. **R12-V5**：翻譯編輯器在本尊是**獨立 app**（Translate & Adapt），與 R9-V1 內嵌 app 邊界同源。
7. **R12-V6**：權限父子**真連動**（勾子自動補齊祖先鏈）。
8. **R12-V2**：權限異動需 **step-up auth（重新輸入密碼）**——我方是否實作 sudo session。
9. **R12-V1**：我方 `giftcards` 設定分頁在本尊設定樹中不存在，需查它承載什麼、應歸到哪。
10. **合法獨有**：`seo` 分頁對應 §A **G20**（AI 爬蟲開關三組不合一）＋30 號 SEO 研究，**不是自創**，
    但頁面應註明出處以免下一輪又被當成偏離。

---

## §7 help 層（層⑤雙源；與實測的差異逐條登記）

### §7.1 🔴 權限分組：help 是**扁平 19 群**，實測是**巢狀 17 群**——同一批權限、不同分組邊界
help 的群組序：Home／Orders／Draft orders／**Products**／**Inventory**／**Catalogs**／Gift cards／Customers／
Analytics／Marketing／Discounts／**Content**／**Files**／Online store／Checkout and customer accounts／
**Companies**／App development／Store settings／Finance（＋Apps and channels）。

實測把其中五個降為**子標題**：Inventory→產品組內【庫存】、Catalogs→Markets 組內【目錄】、
Files→內容組內【檔案】、Companies→顧客組內【公司】、Apps and channels→設定組內。
⇒ **權限集合一致、群組樹不同**。我方建模若照 help 的扁平 19 群，UI 會與本尊對不上；
若照實測的 17 群，又要注意 help 的權限描述是按扁平群寫的。**以實測樹為 UI、以 help 描述為語義**（R12-DOC1）。
來源：`/manual/your-account/staff-accounts/staff-permissions/staff-permissions-descriptions`

### §7.2 🔴 父子連動的完整規則（help 明文，補完實測只看到的「勾子補父」）
- 「When you assign a permission that has additional dependencies or require permissions,
  **the required permissions are automatically selected as well**.」
- 🔴 **不可取消的自動勾選（can't be deselected）**：
  - Inventory 任一權限 → 自動勾 **Products > View**，**不可取消**
  - Catalogs 任一權限 → 自動勾 **Products > View**，**不可取消**
- **可事後手動取消的自動勾選**：Content／Products／Online store 權限 → 自動勾 Files 的 View/Create/Edit
- 其他明文相依：Manage payments settings → Manage settings｜View tax documents → View payouts｜
  Disputes>Manage → Orders>View｜Enable development → Manage and install apps and channels｜
  Draft orders>Apply discounts 需 View＋Create and edit｜Draft orders>Create and edit 需至少一個付款權限
- 🔴 **連動取消**：「If you deselect a required permission, then **all other dependant permissions
  deselect automatically as well**.」
- **互斥**：help **明載沒有任何互斥關係**；唯一的「不可組合」是 §7.3 的角色類別限制。
⇒ 我方需要的是一張 **依賴圖（含「不可取消」旗標）＋雙向傳播**（授予往上、撤銷往下），
不是單純的樹（R12-V6 升級為 M1 前必答）。

### §7.3 🔴 角色類別的硬約束
「**A role can't contain a combination of permissions from different categories.**」
但**同一使用者可同時持有不同類別的多個角色**（實測 LEEKEN ＝「組織擁有人, 商店擁有人」正是此形態）。
- 類別可用條件：Organization 自訂角色**限 Plus／Partner org**；Store 需 **Basic/Starter 以上**；
  POS 需 POS channel ＋ 至少一個 POS Pro 地點；Partner 僅 Partner 組織。

### §7.4 角色目錄：實測 10 ≠ help 的「12 管理角色 ＋ 7 預設角色」
- help「**Shopify 管理的角色**（不可自訂、不可刪除）」12 個：Store owner／Organization owner／
  Administrator／Organization administrator／App developer／Store user administrator／POS administrator／
  Organization POS administrator／POS full permissions／POS user administrator／POS device setup／Collaborator access
- help「**Predefined roles**」7 個：**Online store editor／Customer support／Merchandiser／Marketer**（Store 類）
  ＋ Store manager／Cashier／Sales associate（POS 類）
- **實測角色列表只有 10 列**（＝管理角色中排除 Store owner／Organization owner 兩個擁有人角色，
  它們不出現在可管理清單）；**7 個 predefined roles 實測未出現** ⇒ 可能需手動加入或依方案/管道條件顯示（R12-V7）。

### §7.5 敏感權限【help 窮舉 7 條，實測 UI 未標示】
1. Customers > Request data（store）2. Finance > Edit billing payment methods and pay invoices（store）
3. Finance > Manage other payment settings（store）4. Business entities > View > View sensitive information（org）
5. View financials（partner）6. Manage credits and refunds（partner）7. Store settings > Manage other payment settings（POS）
- help 只給建議（最小授予、職責分散、鼓勵 2FA），**未規定授予時有強制驗證流程**。
- ⚠ 但**實測發現建立角色本身就要 step-up auth（輸入密碼）**（§1.6）——**help 未載此閘門**（R12-DOC2）。

### §7.6 使用者數量上限（依方案）＋不計入者
| 方案 | 上限 |
|---|---:|
| Pause and Build | 1 |
| **Starter** | **0** |
| **Basic** | **0** |
| Grow | 5 |
| Advanced | 15 |
| Shopify Plus | 無限 |
- **不計入上限**：store owner（每店 1）／organization owner（每組織 1）／**協作者（無限）**／
  **POS-only staff（無限，需 POS channel）**。Partner org 與開發商店無座位限制。
- ⇒ 實測橫幅「協作者不計入您的員工上限」與此一致。

### §7.7 邀請流程與狀態機
- 路徑 Settings > Users > Add users，分頁 **Admin and Point of Sale** / **Point of Sale only**
- 🔴 **邀請有效期 7 天**；過期的官方做法是**移除該使用者再重新新增**——
  help **未提供「重寄邀請」或「取消邀請」的獨立操作**（R12-V8：我方要不要多做重寄）
- 狀態：**Pending**／**Suspend access ⇄ Reactivate**（暫停後無法登入，並自動鎖定該人的信用卡）／
  **Remove user**（🔴 需輸入**自己的帳號密碼**確認、不可復原、相關信用卡自動取消）
  ⇒ 又一個 step-up auth 出現點，與 §1.6 同一機制。
- **POS-only 使用者不需 email，用 PIN 登入**，需 POS Pro。

### §7.8 使用者群組 Groups（🔴 Plus 專屬，實測未出現）
「A user group is a collection of users that share certain roles.」指派 group 即自動獲得其全部角色；
可屬多個 group；移出即收回；刪除 group 會從所有成員收回其角色與商店指派。
⇒ 完整模型是 **使用者 ↔ 群組 ↔ 角色 ↔ 權限** 四段，比我方以為的三段多一層（R12-V9）。

### §7.9 政策【help 窮舉 6 份】
**Return policy**（🔴 不是 Refund policy）／Privacy policy／Terms of service／Shipping policy／
Legal notice／Subscription policy。**沒有 Contact information 這一項**。
- 自動產生範本**只在英文**；非英文商店需自行撰寫。免責原文：「Although Shopify can generate templates,
  you're responsible for following your published policies.」
- 顯示位置：checkout footer（全部）／order review 頁（return policy）／商品頁與購物車（shipping policy）
- URL 格式 **`/policies/[policy-type]`**（例 `/policies/shipping-policy`）
- 🔴 **政策不會被自動翻譯**，只能手動（Translate & Adapt 的 `SHOP_POLICY` 資源）

### §7.10 品牌 Brand assets【欄位與限制窮舉】
| 欄位 | 限制 |
|---|---|
| Default logo | PNG/JPEG，**最小寬 512px** |
| Square logo | PNG/JPEG，建議 **512×512**，平台可能裁圓 |
| Cover image | PNG/JPEG，建議 **1920×1080**，**僅一張** |
| Slogan | **≤80 字元** |
| Short description | **≤150 字元** |
| Primary color ＋ Contrasting color | 色票或 HEX |
| Secondary colors ＋各自 Contrasting | **Starter 無此項** |
| Social links | Starter 在此設定；其他方案在 Theme settings |
- 🔴 **資料模型**：Liquid `shop.brand.colors.primary` 與 `secondary` **都是陣列，每個元素是
  background/foreground 配對**（`shop.brand.colors.primary[0].background`）——**不是「一主色一副色」**（R12-V10）。
- **Favicon 不是獨立欄位**：`brand.favicon_url` ＝ square logo 縮成 32×32。
- **fonts/typography：文檔未載**（Brand assets 頁沒有字體欄位）。
- 🔴 **「Brand assets can't be localized based on market or language.」**——品牌資產**不可本地化**，
  與 G13（不做市場級內容覆寫）方向一致，可引為佐證。

### §7.11 商店活動記錄【help 補完實測未進入的頁】
- 入口：General > Resources > Store activity log；權限＝Home ＋ Store settings > Manage settings
- 🔴 **最多顯示 250 筆**，「保留範圍由筆數上限決定，不是天數」；**保留天數＝文檔未載**
- 🔴 **view-only**：不可展開、不可點擊個別事件、**不可匯出、不可篩選**
- 執行者可以是**人員、app 或 sales channel**；顯示「Shopify」通常代表自己觸發的 background job
- **完整事件型錄＝文檔未載**（官方只給三個例子：刪除商品／變更商店設定／授予 app 存取權）

### §7.12 Translate & Adapt
- **是 app 不是內建**，但**新增語言時會自動安裝**（實測「已安裝」與此一致）；官方發行、免費
- **可翻譯資源類型＝Admin GraphQL `TranslatableResourceType` enum 共 30 值**：ARTICLE／ARTICLE_IMAGE／
  BLOG／COLLECTION／COLLECTION_IMAGE／DELIVERY_METHOD_DEFINITION／EMAIL_TEMPLATE／FILTER／LINK／
  MEDIA_IMAGE／MENU／METAFIELD／METAOBJECT／ONLINE_STORE_THEME（＋6 個 theme 子型別）／
  PACKING_SLIP_TEMPLATE／PAGE／PAYMENT_GATEWAY／PRODUCT／PRODUCT_OPTION／PRODUCT_OPTION_VALUE／
  SELLING_PLAN／SELLING_PLAN_GROUP／SHOP／SHOP_POLICY
- 官方土法判定：**匯出翻譯 CSV，欄位不在 CSV 裡就是不可翻譯**（與我方 G14 的 CSV 契約同一條線）
- **明確不可翻譯**：Collection filters／Shopify Forms 表單／手動付款方式說明／商品圖／**Tags**／
  未託管為 translatable resource 的第三方 app 內容
- **自動翻譯最多 2 種語言（免費）**，手動不限；**14 種語言不支援自動翻譯**；政策不自動翻譯
- 🔴 **語言上限：除 Lite 外所有方案一律 20 種——沒有方案階梯**
- **Adapt ＝ 同語言的市場專屬覆寫**（Sweaters vs Jumpers），需 `en-GB` 這類 language+region subtag，
  且**前提是該語言已加入某個 market** ⇒ **adapt 依賴 Markets**
  🔴 這與 G13「不做市場級內容覆寫」**表面相衝**：本尊確實有市場級的**語言變體**覆寫，
  但它走的是「語言 × 市場」而非「翻譯表帶 market_id」——與 R10-DOC2 的結論一致，G13 仍成立（R12-DOC3）。

### §7.13 方案分層表（help 明載者）
| 功能 | 門檻 |
|---|---|
| 自訂 organization 角色 | Plus 或 Partner 組織 |
| 使用者群組 Groups | **Plus 專屬** |
| 組織強制 2FA／代重設 2FA／SAML／SCIM／verified domain | **Plus 專屬** |
| Store role category | Basic／Starter 以上 |
| Locations 上限 | Starter 2／Basic·Grow·Advanced **10**／Plus **200** |
| Carrier-calculated shipping | **Advanced 以上** |
| 計算並收取關稅與進口稅 | **Advanced 以上** |
| per-market 主題自訂／結帳與帳號頁自訂 | Advanced ＋ Plus |
| Checkout Information/Shipping/Payments 頁 app 自訂・Checkout Branding API | **Plus** |
| Customer accounts > Saved payment methods | **Enterprise** |
| B2B 目錄上限 | Basic/Grow/Advanced 3 個 active／Plus 無限 |
| 語言數 | 除 Lite 外一律 **20**（多語言需 Basic 以上） |
| Themes 數量 | Plus 最多 **100** |
| 檔案儲存 | Plus **1 TB/店** |
| Expansion stores | Plus **9 家**＋無限 staging |

### §7.14 help 與實測的矛盾／未載（下輪或 M1 前補）
| # | 主題 | help | 實測 | 處置 |
|---|---|---|---|---|
| 1 | 權限分組數 | 扁平 19 群 | 巢狀 17 群 | UI 照實測、語義照 help（R12-DOC1） |
| 2 | 建立角色的 step-up auth | **未載** | **有**（輸入密碼） | 以實測為準（R12-DOC2） |
| 3 | Predefined roles 7 個 | 有 | **未出現** | 待查顯示條件（R12-V7） |
| 4 | Gift cards 設定頁 | 權限表列為 Settings 項，但無獨立頁；設定散在 Payments（到期日/Apple Wallet）與 General（自動出貨） | 設定樹**無此頁** | 我方 `giftcards` 分頁應拆併（R12-V1 結論明確化） |
| 5 | Brand 是否獨立頁 | 路徑寫 General > Brand assets，但權限表列為獨立項 | **General 子頁** | 以實測為準（R12-STRUCT2） |
| 6 | Files 位置 | Content > Files（非 Settings） | 同 | 與 R9 結論一致 ✅ |
- **文檔未載清單（12 項）**：完整 Settings 導航樹／通知範本完整分類（官方叫你去後台看，本輪**實測已補**）／
  webhook 數量上限／活動記錄完整事件型錄與保留天數／使用者管理記錄保留與匯出／Users 清單完整欄位與狀態／
  重寄與取消邀請／角色數量上限／能否繞過角色直接授權個別使用者／General 各欄位字元上限／
  Brand 字體與讀取品牌資產的管道窮舉／自動翻譯支援語言正面清單。

---

## §8 🔴 設定區的 CSS 量測（補 §5）（層④ CSS 三段式，2026-08-28）

> 全域 token 值表、頁面骨架與視覺規律＝`docs/design/111-shopify-token-baseline.md`。
> 涵蓋排查與缺口＝`docs/design/110-css-measurement-coverage.md`。
> 🔴 **鐵律 9**：只記 `getComputedStyle` 算出來的值，不含本尊樣式表原始碼、選擇器定義或可執行片段。
> 🔴 本尊設定區渲染在 `div#SettingsDialog` 內（**Dialog 形態，右上有 Close 鈕**），不是獨立頁面路由。

### §8.0 量測環境

> 量測日期 2026-08-28。測試店 chill-love-u5q5mnzq（Shopify Plus，dev store）。Chrome，自建分頁（未搶用其他代理的分頁）。`window.innerWidth = 1024`、`window.innerHeight = 551`（🔴 非 1280 桌機階，本輪未 resize——多代理共用同一視窗，resize 會污染他人量測；1024 下設定區仍為左右雙欄，未塌成單欄）。`getComputedStyle(document.documentElement).fontSize = 16px`（根字級預設，無 47 §F 記過的 24px 污染）。`getComputedStyle(document.body).fontSize = 13px`。取值一律 `getComputedStyle()` 之後的 computed 值；shadow DOM 以 `el.shadowRoot.querySelector()` 穿透，穿透路徑逐項記於 selector 欄。設定區整體渲染在 `div#SettingsDialog` 內（Dialog／modal 形態，右上有 Close 鈕），不是獨立頁面路由的一般頁框。

### §8.1 本畫面用到的 token 值

| 類別 | 量測值 | 取值選擇器 |
|---|---|---|
| 底色／表面 | --p-color-bg #f1f1f1；--p-color-bg-surface #fff；--p-color-bg-surface-secondary #f7f7f7；--p-color-bg-surface-tertiary #f3f3f3；--p-color-bg-surface-hover #f7f7f7；--p-color-bg-surface-active #f3f3f3；--p-color-bg-surface-selected #f1f1f1；--p-color-bg-surface-secondary-hover #f1f1f1；--p-color-bg-surface-secondary-active #ebebeb；--p-color-input-bg-surface #fdfdfd。body 實際底色量測＝rgb(241,241,241) | getComputedStyle(document.documentElement) |
| 文字色 | --p-color-text #303030；--p-color-text-secondary #616161；--p-color-text-disabled #b5b5b5；--p-color-text-critical #8e0b21；--p-color-text-caution #4f4700；--p-color-text-success #014b40；--p-color-text-info #003a5a；--p-color-text-brand #4a4a4a。（--p-color-text-emphasis 取回空字串＝未定義） | :root |
| 邊框／圖示色 | --p-color-border #e3e3e3；--p-color-border-secondary #ebebeb；--p-color-border-hover #ccc；--p-color-border-focus #005bd3；--p-color-icon #4a4a4a；--p-color-icon-secondary #8a8a8a；--p-color-icon-disabled #ccc；--p-color-nav-icon #4a4a4a | :root |
| 語義填色 | --p-color-bg-fill-brand #303030；--p-color-bg-fill-success #047b5d；--p-color-bg-fill-critical #c70a24；--p-color-bg-fill-caution #ffe600；--p-color-bg-fill-info #91d0ff | :root |
| 間距階（rem→px @16px 根） | 0/0；025/.0625rem(1)；050/.125rem(2)；100/.25rem(4)；150/.375rem(6)；200/.5rem(8)；250/.625rem(10)；300/.75rem(12)；400/1rem(16)；500/1.25rem(20)；600/1.5rem(24)；700/1.75rem(28)；800/2rem(32)；1000/2.5rem(40)；1200/3rem(48)；1600/4rem(64)；2000/5rem(80)；2400/6rem(96)；2800/7rem(112)；3200/8rem(128) | :root |
| 字級階 | body-x-small .6875rem(11)；body-small .75rem(12)；body-medium .8125rem(13)；body-large .875rem(14)；heading-small .75rem(12)；heading-medium .8125rem(13)；heading-large .875rem(14)；display-small 1.125rem(18)；display-medium 1.5rem(24)；display-large 1.875rem(30) | :root |
| 行高階 | body-x-small .75rem(12)；body-small 1rem(16)；body-medium 1.25rem(20)；body-large 1.25rem(20)；heading-small 1rem(16)；heading-medium 1.25rem(20)；heading-large 1.25rem(20)；display-small 1.5rem(24)；display-medium 2rem(32)；display-large 2.5rem(40) | :root |
| 字重階 | regular 450；details-text 450；input-label 450；input-label-small 450；medium 550；button-label 550；semibold 600；heading-small/medium/large 600；display-small 600；display-medium/large 650；bold 650。🔴 這一階全部是非標準值（450/550/650），不是 400/500/600/700 | :root |
| 圓角階 | 0/0rem；050/.125rem(2)；100/.25rem(4)；150/.375rem(6)；200/.5rem(8)；300/.75rem(12)；400/1rem(16)；500/1.25rem(20)；750/1.875rem(30)；full/624.9375rem | :root |
| 陰影階 | shadow-100＝6 層堆疊（最外 0 0 0 1px #0000000f 邊框層＋5 層 y-offset 遞增的黑色低透明陰影）；shadow-200＝7 層；shadow-300＝6 層（最上層 0 8px 24px -8px #00000047）；shadow-400／shadow-500＝6／7 層；shadow-popover 同 shadow-300 值；shadow-button＝3 層 inset（0 -1px 0 0 #b5b5b5 inset、0 0 0 1px #0000001a inset、0 .5px 0 1.5px #FFF inset）；shadow-inset-100＝2 層 inset；--p-shadow-card 取回空字串（未定義）；--p-shadow-page-button＝none | :root |
| 動效 | duration-100 100ms；duration-150 150ms；duration-200 200ms；duration-250 250ms；ease cubic-bezier(.25,.1,.25,1)；ease-in-out cubic-bezier(.42,0,.58,1) | :root |
| 設定區佈局專用 | --pg-navigation-width 15rem(240)；--pg-layout-width-outer-spacing-max 2rem(32)；--pg-layout-relative-size 2；--pg-bottom-bar-height 0rem；--osui-nav-item-alignment-base-tight .75rem(12)；--osui_nav-item-alignment-common-icon calc(1.25rem + .5rem + .75rem) | :root |

### §8.2 元件量測（33 項）

| # | 元件 | 量測 | 狀態樣式 |
|---:|---|---|---|
| 1 | **設定殼層（Settings Dialog）** | 設定區整體是 Dialog：`div#SettingsDialog`。Layout padding 16px 0 0 32px；`_BodyMarkupContainer_` 內容欄 w=661 起點 x=320。右上 Close 鈕（`button._CloseButton_1ozj5_3`）32×32、padding 6px、圓角 8px、底色 rgba(0,0,0,0.05)、色 #303030、無陰影，位置 x=980 y=68。 | Close 鈕 hover／focus 未量（避免誤觸關閉）＝未取得 |
| 2 | **左側導覽容器** | 容器 w=279（含 margin 8px 9px 48px 0），內部可視欄 x=32；導覽項目寬 255（左右各 12px 內縮）。字級繼承 13px / 行高 20px。無邊框、無陰影、底色透明（坐在 #f1f1f1 頁底上）。 | — |
| 3 | **組織標頭（CHILLING TECH LIMITED / Organization）** | 容器：display flex、gap 8px、padding 12px 16px、h=61、底色 #f3f3f3、border-bottom 1px solid #e3e3e3、圓角 0。主標 h3._Heading_4wlt2_23：13px / 500 / lh 20px / #303030。副標：12px / 500 / lh 16px / #616161。 | — |
| 4 | **導覽搜尋框** | 外框 h=56（含上下留白）；Backdrop h=32、w=255、圓角 8px、底色 #fdfdfd、border 1px solid #8a8a8a、無 box-shadow。input：13px / 500 / lh 24px / h=26 / w=215 / padding 1px 2px 1px 0。焦點環由 `._Backdrop_::after` 承擔：position absolute、inset -1px、圓角 5px、box-shadow 0 0 0 -1px #005bd3（未聚焦時擴散為負值＝不可見）。 | resting 已量；focus 環色 #005bd3（由 ::after spread 量得）。hover 未量＝未取得 |
| 5 | **導覽項目（Settings nav item）** | 列高 28px、列距 32px（相鄰 li y 差 32 ⇒ 列間 4px）、寬 255。`a` 本身 display inline、padding 0、圓角 8px、背景透明。實際列盒＝`._LinkContent_`：display flex、padding 4px、h=28。圖示：`s-internal-icon` 20×20，穿透 `s-internal-icon.shadowRoot > span.icon.color-base.tone-neutral.size-base`（20×20）；圖示與文字間距 8px（`span._Label_` margin-left 8px）。文字 13px / 500 / lh 20px。未選取文字色 #303030；選取態文字＋圖示色 #4a4a4a。🔴 選取／hover 的灰底不是 background，而是 `._LinkContent_::before`：position absolute、inset 0、圓角 8px、w 255 h 28。20 個項目全部共用同一個 `id="settings-nav-item"`（重複 id）。 | resting：::before display none。selected（`._Active_a0klx_25`）：::before display block、底色 #f3f3f3；文字／圖示由 #303030 轉 #4a4a4a。hover（真滑鼠實測）：::before display block、底色 #f1f1f1，文字色不變（#303030），無邊框、無陰影、無底線。selected+hover：底色也是 #f1f1f1。focus-visible（document.hasFocus()=true 下實測）：outline = 瀏覽器預設 `auto 1px`、outline-offset 1px，`._LinkContent_` 與 ::before 皆無自訂焦點環 ⇒ 🔴 導覽項目沒有 Polaris 的 2px #005bd3 焦點環。disabled 態不存在（未見 disabled 導覽項） |
| 6 | **組織區／商店區分隔線** | position absolute、top 68px、left/right 各 16px（w=247）、h=1px、底色 #e3e3e3。🔴 是 pseudo-element，不是 hr、也不是 border——DOM 內查不到對應元素。 | — |
| 7 | **商店標頭（CL 頭像 / CHILL LOVE / chill.deals）** | h=48、margin-bottom 12px、display flex、gap 8px、padding 12px 16px 0、底色 #fff（Plain 變體）。店名 13px / 500 / lh 20px / #303030；網域 12px / 500 / lh 16px / #303030（🔴 與組織標頭副標的 #616161 不同）。頭像為 `s-avatar` 元件。 | — |
| 8 | **導覽清單容器（ul）** | padding 0 0 4px；商店區 20 項共 h=580（20×28＋19×4＝580 吻合）。組織區 ul h=68（2 項）＋容器 margin-bottom 4px。 | — |
| 9 | **底部帳號列** | 外層 Box：border-top 1px solid #e3e3e3、h=65。連結：w=263、h=48、padding 4px 8px、圓角 8px、背景透明。姓名 13px / 500 / lh 20px / #303030；Email 走 `s-internal-text`。 | hover／focus 未量＝未取得 |
| 10 | **設定卡片（Card）** | 🔴 白底與陰影都在 shadow root 裡：`section` 底色 #fff、圓角 12px、padding 0、overflow clip、box-shadow 六層堆疊＝rgba(0,0,0,.03) 0 5px 5px -2.5px, rgba(0,0,0,.02) 0 3px 3px -1.5px, rgba(0,0,0,.02) 0 2px 2px -1px, rgba(0,0,0,.03) 0 1px 1px -.5px, rgba(0,0,0,.04) 0 .5px .5px 0, rgba(0,0,0,.06) 0 0 0 1px（值等同 --p-shadow-100）。外層 `._CardHighlightWrapper_` 本身背景透明、僅帶圓角 12px。卡片寬 629（1024 視窗下）。卡片間距：外層 `.Polaris-BlockStack` gap 16px。卡片內：標頭 Box padding 12px 16px、內容 Box padding 0 16px 16px ⇒ 內容欄寬 597。標題與說明的 BlockStack gap 2px。 | — |
| 11 | **卡片分節標題 H2** | 13px / 500 / lh 20px / #303030 / letter-spacing normal / margin 0 / padding 0 / h=20。 | — |
| 12 | **卡片說明段落（subdued）** | 13px / 450 / lh 20px / #616161。與標題間距 2px（BlockStack gap）。 | — |
| 13 | **卡片底部說明條（footer strip）** | 底色 #f3f3f3、padding 12px 16px、h=45、圓角 0（由卡片 overflow:clip 切出下方圓角）。內含連結：`s-internal-link → shadowRoot > a.link.tone-auto`，圓角 4px（焦點環用）。 | — |
| 14 | **設定列（可點擊 row，Notifications 型）** | 清單容器圓角 8px、背景透明。列：底色 #fff、h=64、列距 65px（含 1px 分隔線）、transition background-color 0.1s ease-in-out。內距 wrapper padding 12px。標題連結 `a._SettingsItem__clickableAction_6hwtm_136`：13px / 500 / #303030、無底線、cursor pointer、display block、h=20；用 ::before（content ""）撐滿整列做 stretched link。說明文字：`s-internal-text → shadowRoot > span.text.color-subdued` 13px / 450 / lh 20px / #616161。右側 chevron：`s-internal-icon` 20×20，穿透 shadow 後 `span.icon.color-base.tone-neutral` 色 #4a4a4a，貼右緣內縮 12px。 | 🔴 hover（真滑鼠移到列上與移到標題文字上，兩處都測）：列底色維持 rgb(255,255,255) 不變、連結不加底線、色不變 ⇒ 本清單沒有 hover 填色，只有 cursor 變化。（列上仍宣告 background-color transition，推測用於 active／focus-within，本輪未觸發＝未取得）。focus 未量＝未取得 |
| 15 | **設定列分隔線** | 外層 h=1、padding 0 12px（inset 12px）；hr h=1、w=571、border-bottom 1px solid #e3e3e3、背景透明、其餘 border 0。外層 transition margin 0.1s ease-in-out。 | — |
| 16 | **設定列（帶主/次兩行＋stretched link，General 型）** | 列內 `.Polaris-InlineGrid` gap 12px（外層）／16px（內層）；主區 `.Polaris-InlineStack` gap 8px；兩行區塊 h=40。可點擊元素同時有 `a`（導頁）與 `button`（開 modal）兩種形態，樣式一致。 | — |
| 17 | **頁首（Page header）** | header-content：display flex、gap 8px、h=28、w=629。標題 `h1.heading`：18px / 600 / lh 24px / letter-spacing -0.14994px / #303030。標題左側圖示：`s-internal-icon` 20×20 外框，穿透 shadow 得 `span.icon`（20×20）內含 svg 16×16、fill #303030。動作區 `div.actions`：display flex、gap 6px、h=28、靠右。 | — |
| 18 | **主要按鈕（Add language）** | h=28、padding 6px 12px、圓角 8px、gap 2px、底色 #303030、字色 #fff、12px / 550 / lh 16px、transition none。box-shadow 3 層 inset：rgba(0,0,0,.8) 0 -1px 0 1px inset、rgb(48,48,48) 0 0 0 1px inset、rgba(255,255,255,.25) 0 .5px 0 1.5px inset。 | hover／focus／active／disabled 未量＝未取得（避免誤觸開啟新增語言流程） |
| 19 | **次要按鈕（Export / Import，頁首新元件系）** | h=28、w=62、padding 6px 12px、圓角 8px、gap 2px、底色 #e3e3e3、字色 #303030、12px / 550 / lh 16px、box-shadow none、transition none。 | hover／focus 未量＝未取得 |
| 20 | **次要按鈕（Adapt / Translate / Open，卡內 Polaris 系）** | 🔴 與頁首次要鈕是兩套不同系統：底色 #fff（不是 #e3e3e3）、圓角 8px、13px / 500 / lh 20px（不是 12px/550）、gap 2px、h=28、padding 4px 12px（`a`）／6px 12px（`button`），box-shadow 3 層 inset＝rgb(181,181,181) 0 -1px 0 0 inset, rgba(0,0,0,.1) 0 0 0 1px inset, rgb(255,255,255) 0 .5px 0 1.5px inset（＝--p-shadow-button）。 | hover／focus 未量＝未取得 |
| 21 | **圖示按鈕（列尾「⋯」More actions）** | 28×28、padding 4px、圓角 8px、底色 #fff、同上 3 層 inset bevel 陰影。 | 未開啟選單（避免誤觸破壞性項目）⇒ popover 樣式＝未取得 |
| 22 | **Languages 語言表（IndexTable）** | 表寬 595（卡內容寬 597 減 1px 左右）。表頭 th：底色 #f7f7f7、12px / 500 / lh 20px / #616161、h=36.5、padding 8px 6px（首欄 8px 6px 8px 12px、末欄 8px 12px 8px 6px）。資料列：底色 #fff、`--unclickable`；兩行列 h=63、單行列 h=48.5。🔴 分隔線走 tr 的 border-top：首列（緊貼表頭）1px solid #e3e3e3、列間 1px solid #ebebeb（兩個不同色）。td padding 6px（首欄 6px 6px 6px 12px、末欄 6px 12px 6px 6px）。欄寬（1024 下）Language 179.86 / Status 133.13 / Domains 120.89 / Actions 161.13。 | 列 hover 未量（`--unclickable`）＝未取得 |
| 23 | **語言名稱＋預設標記** | 語言名 13px / 450 / lh 20px / #303030；下方「Default」13px / 450 / lh 20px / #616161（color-subdued），兩行 y 差 22px。🔴 預設語言標記是純文字副標，不是 badge。 | — |
| 24 | **狀態徽章（Published / Not published）** | 共通：h=20、padding 2px 8px、圓角 8px、gap 4px、12px / 550 / lh 16px、無邊框無陰影。Published（tone-success）底色 rgb(175,254,191)、字色 #014b40、w=72.97。Not published（中性）底色 rgba(0,0,0,0.06)、字色 #616161、w=96.34。 | — |
| 25 | **Domains 揭露鈕（2 domains ⌄）** | h=32、w=110.39、padding 6px 12px、margin -6px -12px（負邊距抵銷內距使文字對齊格線）、圓角 8px、背景透明、字色 #616161、13px / 500 / lh 20px、gap 2px。 | 未展開＝popover 樣式未取得 |
| 26 | **App 卡列（Shopify Translate & Adapt）** | App icon 40×40、圓角 8px。App 名 h3：13px / 500 / lh 20px / #303030。狀態文字「Installed」走 `s-internal-text`（color-subdued 系）。右側 Open 鈕同「卡內 Polaris 次要鈕」規格（h=28、padding 6px 12px、bevel 陰影）。 | — |
| 27 | **頁尾說明段落（Learn more about languages.）** | 12px / 500 / lh 16px / #303030、置中、w=483.41。內嵌連結：`s-internal-link → shadowRoot > a.link.tone-auto`：13px / 450 / lh 20px、色 #303030（與內文同色）、text-decoration underline、圓角 4px。🔴 連結不換色，只加底線。 | 連結 hover／focus 未量＝未取得 |
| 28 | **Radio（單選群組）** | fieldset：display flex、padding 0、無邊框。label.choice：display flex、gap 8px、padding 4px 0、h=28、13px / 450 / lh 20px / #303030；選項列距 28px（無額外 gap，靠 4px 上下內距分隔）。input.radio：16×16、圓角 50%、appearance none。未選：背景透明＋inset ring 0 0 0 0.66px rgb(138,138,138)；`::after` 為 16×16 圓、底色 #fdfdfd、transform scale(0.9375)。已選：底色 #303030、無 ring；`::after` 同圓但 transform scale(0.5) ⇒ 8px 白點。 | focus-visible（實測）：outline 2px solid #005bd3、outline-offset 2px，且 inset ring 由 #8a8a8a 轉 rgb(26,26,26)。hover 未單獨量＝未取得。disabled 本頁無實例＝未取得 |
| 29 | **Checkbox（新元件系 s-checkbox）** | label：display inline-flex、gap 8px、padding 4px 0、h=28。視覺方塊 `div.checkbox`：16×16、圓角 4px、transition background-color .1s cubic-bezier(.19,.91,.38,1) ＋ box-shadow 同曲線。未勾：底色 #fff、inset ring 0 0 0 0.66px rgb(138,138,138)。已勾：底色 #303030、inset ring 0 0 0 0.66px #303030。內含 svg 16×16（fill none，勾號以 path 描邊）。label-text：13px / 450 / lh 20px / #303030，x 位移 24px（16 方塊＋8 gap）。說明列 `div.field-details`：12px / 450 / lh 16px / #616161、gap 2px、padding-left 24px（切齊 label 文字），無說明時整個容器 display:none（class 追加 `display-none`）。 | resting／checked 已量。focus-visible／hover 未單獨量＝未取得（僅量到舊版 Polaris checkbox 的 focus，見下） |
| 30 | **Checkbox（舊 Polaris 系，同頁併存）** | 🔴 與 s-checkbox 併存於同一設定頁。input 16×16（視覺隱藏）。Backdrop 16×16、圓角 4px、已勾底色 #303030＋box-shadow 0 0 0 32px #303030 inset、transition border-color/border-width 0.1s cubic-bezier(.19,.91,.38,1)。Icon 12×12、margin 2px。 | focus-visible（實測）：Backdrop outline 2px solid #005bd3（offset 未取得）；input 自身為瀏覽器預設 auto 1px |
| 31 | **Select（下拉）** | h=32、圓角 8px、底色 #fdfdfd、inset ring 0 0 0 0.66px rgb(138,138,138)、padding 6px 8px 6px 12px、display grid。值文字 `span.value` 13px / 450 / lh 20px / #303030；尾端 `s-icon` 20×20。label 可設 `outside`（顯示）或 `hidden`（配 span.visually-hidden 1×1）。 | hover／focus／disabled 未量＝未取得 |
| 32 | **Text field（label / input / hint 三層）** | input-field（直欄）gap 4px。label.outside：13px / 450 / lh 20px / #303030、h=20；label-content h=16。input-wrapper：h=32、圓角 8px、底色 #fdfdfd、inset ring 0 0 0 0.66px rgb(138,138,138)、padding 0 12px、gap 8px。input：13px / 450 / lh 20px / #303030、h=20、padding 0。hint／error 容器 `div.field-details`：12px / 450 / lh 16px / #616161、gap 2px；無內容時 display:none。整組 label→框 垂直間距 4px（1242+20 → 1266）。另有 `div.prefix-suffix-wrapper` gap 4px。 | resting：底 #fdfdfd、ring 0.66px #8a8a8a。hover（真滑鼠實測）：底 rgb(250,250,250)、ring 0.66px rgb(97,97,97)。focus-visible（實測）：底 rgb(247,247,247)、inset ring 轉 0 0 0 1px rgb(26,26,26)、外加 outline 2px solid #005bd3、outline-offset 1px。🔴 error 態未取得——觸發需輸入非法值並嘗試儲存，違反本輪唯讀約束 |
| 33 | **Banner（資訊橫幅，設定卡片內）** | 外框：底色 rgb(234,244,255)、圓角 8px、gap 8px、無邊框無陰影、w=563。body：display grid、padding 8px、gap 8px。文字／圖示色 #003a5a、13px / 450 / lh 20px。左側圖示區 20×20（圓角 8px）。右側 dismiss 區 w=24、margin -2px -2px -2px 0。 | dismiss 鈕未點（避免改變使用者可見狀態）；hover／focus 未取得 |

### §8.3 觀察到的視覺規律

1. 間距一律 4 的倍數：實測出現 2 / 4 / 6 / 8 / 12 / 16 / 24 px；唯一的 2px 出現在標題與說明的 BlockStack gap、徽章上下內距、field-details gap。6px 只出現在按鈕內距（6px 12px）與頁首動作列 gap。
2. 圓角只有四階在設定區實際用到：4px（checkbox 方塊、連結焦點框、SettingsFlag）／8px（幾乎所有互動元件：按鈕、輸入框、select、徽章、導覽項目 pill、清單容器、banner）／12px（卡片）／50%（radio）。沒有出現 2px、6px、16px 以上的圓角。
3. 控件高度只有兩階：28px（導覽項目、全部按鈕、choice label 列、徽章列所在列）與 32px（輸入框、select、搜尋框、揭露鈕、Close 鈕）。徽章本體 20px、圖示一律 20px 外框內含 16px svg。
4. 🔴 選取／hover 的填色不是 background，而是絕對定位的 ::before 疊層（導覽項目）——複製時若直接寫 background，圓角 8px 的 pill 與 4px padding 的關係會對不上。
5. hover 一律只改底色（與邊框色），不改文字色、不加邊框、不加陰影、不位移。導覽項目 hover #f1f1f1；輸入框 hover 底 #fafafa＋ring 由 #8a8a8a 轉 #616161。
6. 🔴 焦點環有兩制併存：表單控件（text field / radio / Polaris checkbox）＝outline 2px solid #005bd3（offset 1–2px）＋內圈 ring 轉深（#1a1a1a）；導覽項目與 stretched link＝完全沒有自訂焦點環，落回瀏覽器預設 auto 1px。
7. 卡片陰影是六層堆疊（五層 y-offset 遞增的低透明黑＋最外一層 0 0 0 1px rgba(0,0,0,.06) 當邊框），且整組陰影與白底都在 s-internal-section 的 shadow root 裡，外層 wrapper 只留圓角。
8. 分隔線有三種色階，依語義分工：卡片標頭下方／組織區分隔／帳號列上方＝#e3e3e3；設定清單列間＝#e3e3e3（inset 12px）；表格列間＝#ebebeb（表頭下方那條則是 #e3e3e3）。
9. 分隔線的實作有三種形態：真 hr（s-divider shadow 內 border-bottom）、border-top（表格 tr）、pseudo-element（組織／商店區分隔）。沒有統一寫法。
10. 排版階梯（設定區實測，由大到小）：頁標題 18/600/24 → 卡片分節標題 13/500/20 → 正文與欄位 label 13/450/20 → 說明／副標 13/450/20（僅換 #616161）→ 表頭與 hint 與頁尾 12/(500 或 450)/16。🔴 主層級只靠字重＋色階拉開，字級只有 18 / 13 / 12 三階。
11. 色階只有三段文字色在用：#303030（主）／#616161（次、hint、表頭）／#4a4a4a（圖示與選取態導覽文字）。#8a8a8a 只作 resting 邊框／ring。
12. 新舊兩套設計系統在同一設定頁併存：新的 Web Component 系（s-*，shadow root，字重 450/550，次要鈕底 #e3e3e3、無陰影、transition none）與舊 Polaris 系（.Polaris-*，字重 500，次要鈕底 #fff＋三層 inset bevel 陰影）。同一頁的兩顆「次要按鈕」外觀不同。
13. 設定區是 Dialog（div#SettingsDialog）不是獨立頁——複製時要決定我方 SettingsPage 是 modal 還是路由頁，這會連動 URL、返回鍵與 Close 鈕。
14. 設定清單列（Notifications 型）沒有 hover 填色，只有 cursor 變化；整列可點是靠標題連結的 ::before 撐滿（stretched link），不是列本身綁事件。

### §8.4 🔴 與既有量測文件的衝突（照登記，未逕行覆寫）

1. 🔴 與 47／64 可能衝突（字重階）：`:root` 的字重 token 全是非標準值——regular 450、medium 550、semibold 600、bold 650。但 `document.body` 的 computed font-weight 實測是 **500**（`document.documentElement` 是 450），而設定區絕大多數 .Polaris-* 元素（H2、表頭、導覽項目、頁尾段落）繼承到的就是這個 500。也就是說「token 說 450/550/650」與「畫面上實際渲染 500」兩者並存。若 47／64 只登記了 token 值（450/550/650），實作照抄會與本尊畫面差一階字重。建議在 47／64 補一行：Polaris legacy 節點走 500，新 s-* 元件節點走 450/550。

2. 🔴 字級階語義衝突：token `--p-font-size-heading-small` = .75rem(12px)、`--p-font-weight-heading-small` = 600，但設定卡片的分節標題 `h2.Polaris-Text--headingSm` 實測是 **13px / 500**。class 名（headingSm）與 token 名（heading-small）對不上值。實作若用 heading-small token 畫分節標題會偏小一階。

3. 🔴 兩套按鈕系統的次要鈕不同色：頁首 `s-internal-button variant-secondary`（Export／Import）＝底色 #e3e3e3、12px/550、box-shadow none、transition none；卡內 `.Polaris-Button`（Adapt／Translate／Open）＝底色 #fff、13px/500、三層 inset bevel 陰影。若 47／64 只記了其中一套當作「次要按鈕」，另一套會被誤判成 bug。兩者在同一畫面同時可見（Languages 頁）。

4. 🔴 焦點環不是全域一致：47／64 若登記「焦點環 = 2px solid #005bd3」，設定區的導覽項目（`a#settings-nav-item`）實測是**瀏覽器預設 outline auto 1px + offset 1px**，沒有 #005bd3 環（已在 document.hasFocus()=true 下複驗，排除背景分頁造成的假陰性）。表單控件才有 #005bd3。這是本尊自身的不一致，不是我方量測誤差。

5. 🔴 hover 比 selected 更深：導覽項目 selected 底色 #f3f3f3（bg-surface-active），hover 底色 #f1f1f1（bg-surface-selected）。也就是 hover 的灰比選取態的灰更深，且 token 名稱與用途對調（`-selected` token 被用在 hover、`-active` token 被用在 selected）。照 token 名稱直覺實作會做反。

6. 表格分隔線用了兩個不同色：表頭與首列之間 1px solid #e3e3e3，資料列之間 1px solid #ebebeb。若既有量測只記了單一「表格分隔線色」，需補成兩階。

### §8.5 未取得（鐵律 19.3）

- Toggle／Switch 控件的樣式——未取得。實測掃描 5 個設定頁（general / languages / checkout / privacy / notifications）的 light DOM ＋全部開放 shadow root，`[role=switch]` 命中數皆為 0，自訂元素清單中亦無 s-switch / s-toggle。這些頁的開關語義一律由 checkbox（s-checkbox 或 .Polaris-Checkbox）承擔。🔴 這只證明「這 5 頁沒有」，不等於整個 admin 沒有；取得方式＝續掃 shipping / taxes / locations / customer_accounts / sales_channels / domains / custom_data / apps / policies 與各子頁 modal。
- 欄位 error 態（三層中的第三層）的字級／色／間距——未取得。error 容器已定位（`div.field-details`，與 hint 同一容器，無錯誤時 display:none），但要讓它上色需要輸入非法值並觸發驗證，違反本輪「只看不改、不按 Save」的硬約束。取得方式＝另開一輪並取得明示授權後，在測試店輸入非法值走完驗證流程，量 `div.field-details` 的 color 與 `div.input-wrapper` 的 ring 色。
- 1280 桌機階的量測——未取得。本輪固定在 innerWidth=1024（多代理共用同一 Chrome 視窗，resize 會污染他人量測）。1024 下設定區仍為雙欄，但卡片寬 629、內容寬 597 這些值是 1024 專屬，不可外推到 1280。取得方式＝獨占視窗時 resize_window 到 1280×800 後重量卡片寬、內容寬與 actions 是否溢出成 ⋯ 選單。
- 768 平板／390 手機階的形態——未取得（鐵律 13.1 要求三裝置對比，本輪只做一個寬度）。
- 主要按鈕（Add language）、次要按鈕（Export/Import/Adapt/Translate/Open）、圖示按鈕（⋯）、Close 鈕、Domains 揭露鈕、banner dismiss 的 hover／focus／active／disabled 態——未取得。理由：這些控件一按就會開啟新增語言流程、匯出匯入、關閉設定或彈出破壞性選單，本輪唯讀約束下未觸發。取得方式＝hover 可安全補量（真滑鼠 hover 不觸發 click），focus 可用 element.focus() 在 document.hasFocus()=true 下補量；active 需按住不放再量。
- 語言列「⋯ More actions」彈出選單（popover）的樣式——未取得。選單內含 Remove language 等破壞性項目，本輪未開啟。
- s-checkbox 的 hover 與 focus-visible 態——未取得（只量到舊 Polaris checkbox 的 focus 環 2px solid #005bd3）。
- Select（s-internal-select）的 hover／focus／open（選單展開）態——未取得。
- 導覽搜尋框的 hover 與實際 focus 態數值——部分未取得：已由 `._Backdrop_::after` 讀到焦點環色 #005bd3、圓角 5px、inset -1px，但未在真正 focus 下量到 spread 的最終值。
- disabled 態（任何控件）——未取得，本輪掃過的設定頁上沒有 disabled 實例。
- 卡片 shadow 的 dark theme 版本——未量（僅量 light）。
- Polaris checkbox focus 環的 outline-offset 數值——未取得（只讀到 outline 本身）。
