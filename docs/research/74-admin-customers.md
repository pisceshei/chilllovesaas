# 74 — 顧客線 按鈕級 teardown（R5，2026-08-13 實測 chill-love-u5q5mnzq＋help 六路）

> 雙源：實測（test）＋help 工作流 wf_be1c9827-467（4 主題＋2 critic，6/6 全收）。
> CSS：列表/表格/選單量測與 R4（73 §5）同一系統，未見新 token——本輪不重複量測，僅記結構差異。

## §1 顧客列表 `/customers`＝ShopifyQL 查詢視圖 🔴（本輪最大結構發現）

- 頂部「🤖 描述您的分群」AI 列 **⌄ 展開＝五行查詢編輯器**：`FROM customers／SHOW 欄位清單／WHERE
  條件／GROUP／ORDER`＋icon 條（範本🗔/鍵盤⌨/說明?/復原↶/重做↷/執行▷/收合⌃）＋**autocomplete**
  （每欄位帶官方描述）＋底部「調整您的分群（條件）」AI 列＋↑。
- 編輯器上方**即時人數列**：「3 位顧客｜佔客群的 100%」（隨編輯重估）。
- 語法錯誤紅底線＋hover 提示；點選式篩選選單與文字編輯互通（WHERE 即時同步）；AND 先於 OR，官方建議括號。
- **欄位選擇器＝SHOW 子句 UI 化**：排序依據 select＋欄清單（拖曳排序＋眼睛顯隱）。
  預設顯示：顧客名稱（恆第一欄不可調）/電子郵件訂閱/地點/訂單/消費金額；
  隱藏 14：電子郵件/電話/名字/姓氏/郵遞區號/顧客語言/ID/新增顧客日期/顧客更新日期/SMS 訂閱/
  **WhatsApp 訂閱**/稅額豁免/可刪除/可合併。
- 排序鍵 7×2：消費金額/訂單/新增顧客日期/**顧客更新日期（預設）**/最新訂單日期/首次訂單日期/
  最新放棄訂單日期 × 從舊到新/從新到舊。
- 本尊列表**無 view tabs**；匯出（四範圍/含標籤與中繼欄位/兩格式/>50 email 寄送）；匯入（UTF-8/
  ≤15MB/覆寫現有顧客＋建立區段與標籤兩勾選/email-電話為鍵，重複取最後一筆）；CSV 欄位表與錯誤
  規則見 help import-export-customers。
- 大量動作：Edit customers（名字/姓氏/email/標籤/三通道行銷同意/任何中繼欄位）＋大量刪除
  （不可刪者自動保留）＋「選取此區段/查詢中的 50 位以上顧客」。

## §2 分群條件目錄（實測 autocomplete DOM 收割＋help reference-guide 互證）

- **18 屬性**：abandoned_checkout_date/amount_spent/companies/created_by_app_id/customer_account_status/
  customer_added_date/customer_cities/customer_countries/customer_email_domain/customer_language/
  customer_regions/customer_tags/email_subscription_status/first_order_date/last_order_date/
  number_of_orders/rfm_group/sms_subscription_status（各附官方一句話描述，已入原型 SEG_FILTERS）。
- **函式與事件族**：anniversary()/customer_within_distance()/orders_placed()/products_purchased()/
  shopify_email.{bounced,clicked,delivered,marked_as_spam,opened,unsubscribed}()/
  storefront.{collection_viewed,product_viewed}()/store_credit_accounts()。
- help 補：**predicted_spend_tier**（HIGH/MEDIUM/LOW；>100 筆銷售啟用）、product_subscription_status、
  **metafield 條件** `customer.[ns]_[key]`（限 日期時間/數值/文字/是或否）。
- 運算子全集：= != > < <= >= BETWEEN CONTAINS NOT CONTAINS MATCHES NOT_MATCHES IS NULL IS NOT NULL。
- 測試訂單與已刪除訂單不計入條件計算。

## §3 分群列表與編輯器

- 列表欄：名稱/顧客百分比/上次活動⇅/建立者；**系統預設 5 群**（建立者=Shopify，名稱保留英文）：
  purchased at least once／Email subscribers／Abandoned checkouts in the last 30 days／purchased
  more than once／haven't purchased。
- 列 ⋯：使用分群/複製/匯出/重新命名/刪除。詳情頁動作列：複製/使用分群⌄/更多動作⌄；
  「使用顧客群」出口＝Email 行銷活動＋折扣（四型）；另存為新顧客群；匯出兩格式。
- 自動化掛鉤：「顧客已加入區段」觸發工作流程＋「Look up customer in segment」動作。

## §4 顧客詳情

- KPI 條：消費總額/訂單/成為顧客日期/**RFM 群組**（無 AOV 格）。
- 「最近一筆已下訂單」單卡（訂單號＋付款/出貨 badge＋金額＋日期來源＋首個 line item）＋
  檢視所有訂單/建立訂單。
- **交易時間軸**：composer（😊 @ # 🔗＋發佈）＋「只有您和其他員工可以看見備註」＋日期分組事件流；
  留言 5 分鐘內可編輯、刪除不可復原；@ 提及寄通知（自提/無權限者無效）；# 連結訂單/草稿/顧客/
  商品/子類/轉移/採購單；附件可傳。自動 email 顯示投遞狀態可重寄（顧客/您自己），手動信不可。
- 右欄：顧客卡 ⋯（聯絡資訊＋通知語言/預設地址/行銷訂閱/稅務詳情/標籤/備註 ≤5,000 字）；
  寄送 email 表單（主旨支援 shop.name 代碼/內文/密件副本/檢閱/傳送通知）；付款方式卡 ⋯
  （傳送更新卡片連結/取代卡片）。
- **更多動作**：發放商店抵用金/合併顧客/要求顧客資料/清除個人資料/刪除顧客（紅）。
- 抵用金：發放（金額+幣別+到期）＋編輯（入帳/扣帳+通知顧客）；<US$15,000/顧客；結帳只顯示
  結帳幣別餘額；優先用最早到期；不可用於草稿/編輯訂單/訂閱扣款；B2B 個檔發放僅限 D2C。
- 合併：email 決定保留檔；**不可合併 8 條**（訂閱合約/活躍 B2B/vaulted 卡/抵用金帳戶/Multipass/
  已刪除/已遮蓋或遮蓋中/處理中）；合併保留 14 類資料；不可復原。
- 刪除：不可刪 4 條（待遮蓋/未送達禮品卡收件人/曾有訂閱合約/有訂單）；redact=遮蓋個資保留
  個檔與訂單，**10 天可取消窗**（「已提交刪除要求」區塊）。
- 稅務：收取/不收取/除非符合豁免否則收取＋豁免下拉（加拿大類別清單）；豁免按已註冊稅籍省份生效。

## §5 新增顧客 `/customers/new`

顧客總覽（名字/姓氏/語言〔通知語言〕/電子郵件/電話＋國碼旗選擇器）＋行銷同意三通道勾選
（「您應先取得顧客同意，再為他們訂閱您的行銷電子郵件、簡訊或 WhatsApp 訊息」）＋預設地址
（⊕新增地址›）＋稅務詳情（稅金設定）＋右欄 備註（不公開）/標籤。

## §6 B2B 公司

- 空態：「為您的 B2B 業務帶來強大的自訂功能」＋新增公司；我方原型空態文案已同文。
- 建立式：公司名稱（顯示在顧客帳號和結帳頁面）/公司 ID（外部或唯一）/主要聯絡人（搜尋顧客）/
  地點（運送地址⊕＋清除/帳單地址與運送地址相同 ☑/地點 ID）/市場 chip（依地址推導）/
  **允許顧客運送至任何一次性地址 ☐**/訂單提交（自動提交〔無運地址→草稿〕⊙/全部作為草稿供審核○）/
  稅務詳細資訊（稅籍編號+稅金設定）。本尊建立式無目錄/付款條件卡（地點詳情才設）。
- 方案限制：非 Plus 全部 B2B 市場合計 **3 個啟用中目錄**；每公司地址 ≤**25 目錄**（多目錄取最低價）；
  按量定價 ≤**10 級距**（門檻>最低訂購量且為遞增倍數；套用後價格固定不疊目錄折扣）；
  數量規則三欄（遞增/最低/最高）。折扣可疊在目錄價上、可限定 B2B 市場。
- 員工權限：檢視公司/指派至公司地址/限制在指派地址（僅顧客/訂單/草稿/公司四頁被篩選——
  分析與行銷頁**不會**依指派過濾，官方建議別發這些權限給銷售代表）。

## §7 顧客帳號與同意（與 R12 設定輪銜接）

- 新版帳號：無密碼（6 位驗證碼/Shop/社群/passkey；Plus 可接 OIDC IdP）；**無停用語義**——刪除後同
  email 再登入自動重建；升級後 30 天可還原、Multipass 失效。
- 設定開關（settings/customer_accounts）：顯示登入連結/自助退貨/商店抵用金/帳號子網域/
  已儲存的付款方式（Enterprise）/Google・Facebook・Shop 登入。
- 行銷同意：商家可在個檔手改（管理→編輯行銷設定）；double opt-in 啟用後新訂閱需點信確認；
  退訂自動（點退訂/標垃圾/帳號退出/硬退信抑制）。
- Email subscribers 系統分群＝訂閱者清單載體。

## §8 我方裁定面與遞延

- 已修（71-R5）：KPI 四格/最近訂單卡/時間軸 composer/更多動作五項/SEG_FILTERS 全量目錄/
  查詢編輯器五行模型/分群列表欄與 ⋯/系統預設 5 群/欄位選擇器/匯出入語義/抵用金表單/
  B2B 一次性地址勾選；limits.yml customers（10 鍵）＋b2b（3 鍵）。
- 遞延：V1 顧客列表 view tabs 歸屬（本尊無 tabs；「更多檢視」字樣出於帳單頁——顧客頁是否有
  saved views 未證實）；V2 CLV 欄與 predicted_spend_tier 的 UI 呈現位置；V3 建立式目錄/付款條件
  二卡前置（我方簡化 vs 本尊地點詳情後置）；V4 付款方式卡/寄送 email 表單原型未建
  （dev 店無 vaulted 卡）；V5 metafield 分群條件的建立器 UI。
