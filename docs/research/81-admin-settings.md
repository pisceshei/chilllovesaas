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
