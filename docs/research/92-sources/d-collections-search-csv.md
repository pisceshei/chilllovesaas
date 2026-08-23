# 92-D — collections／admin 搜尋篩選／CSV 匯入匯出（help 深讀，取證 2026-08-23）

> 92 號研究的來源分冊 D。重要前提：collections 分支已全面改寫為**新 collections model**（legacy manual/smart 標記 Legacy）；舊 URL `/collections/automated-collections` 等已不存在。

## 分支 1：Collections

### 總覽（…/products/collections）
- Collections 需 Basic 以上（**Starter 不支援**）；自動條件、手動、混合；**多個獨立 source**（各有條件）；**巢狀集合**（集合包集合）。
- 子頁（9）：create-collection／conditions／manage-sources／collection-layout／collection-settings／make-collections-findable／search-view／smart-collections（legacy）／manual-shopify-collection（legacy）。

### create-collection
- 流程：Products > Collections → Add collection → title → rich text 描述 → featured image → 加 sources → sort →（選配）channels/metafields/theme template/SEO → Save → 到選單加連結。
- **Source 四型**：①Products（手動或條件）②Variants（**變體層級**）③Collection（巢狀，Connect a collection）④App。
- **Exclude 三型**：條件排除／手動選品排除／整集合排除。**排除永遠壓過任何納入**。
- 規則：多 source 納入同品**只顯示一次**；條件內多值 OR/AND＋條件層級 Match any/all；商品詳情頁的 Collections 欄**只適用手動納入**（條件進來的不能從那裡移除）；新集合**預設未發布**、可設發布日期、可保持未發布專供 tax override/折扣定向；Duplicate 產生「原名 (Copy)」**不自動進 channels**；Delete 永久、選單連結自動移除。
- **上限（全店擁有此類集合的總數）**：含條件的集合 ≤**5,000**；含（手動或自動）變體的集合 ≤**100**；含另一集合的 ≤**50**；排除另一集合的 ≤**5**。

### conditions
- 每集合 ≤**60 條件**；條件只用於 Products/Variants source。
- **欄位×運算子矩陣**：
  - Title/Variant title/Type/Vendor：is equal/is not equal/starts with/ends with/contains/does not contain（contains 系**最少 3 字元**、禁前後空白）
  - Category：is equal/is not equal＋**Include subcategories** 選項
  - Tag：includes/does not include（特殊字元正規化：`red-new`＝`red_new`＝`red+new`）
  - Status：is equal/is not equal（不能單靠 Match any 過濾 archived）
  - Price/Compare-at price/Weight/Inventory stock：=/≠/>/<；Compare-at 另有 **is set/is not set**（is set 含 $0.00）；Products source 下「任一變體符合即符合」；價格區間＝兩條件＋Match all
  - Metafield（definition 須開 collections 條件；每型別 ≤**128 definition**）：boolean is equal；integer/decimal/rating =/>/<；single line text is equal；Variants source 時 category metafield 需連商品選項
  - Metaobject reference metafield：is equal（支援 product/variant reference）
- Exclude 段可用欄位：Category（is not equal）/Tag（does not include）/Type/Vendor。
- 條件**不回溯排除**手動加入的商品；Archive 不移出集合（僅前台隱藏）。
- **自動更新時效：官方無 SLA 敘述**；強制刷新 workaround（複製後刪一條件／小改商品再改回／條件值 ±$0.01）side 證明更新由儲存事件觸發。

### manage-sources
- 移除單一條件／修改條件（即時重算）／移除手動品（不刪商品）／移除整個 source／Collection、App source 可換綁／移除排除即恢復納入。協作提示：先確認無他人同時編輯。

### collection-layout
- 改名/描述/featured image。
- **Sort order 六項**：①Most relevant（依銷售表現；**新集合預設**）②Best selling（全時訂單數；無銷售退化新→舊）③Product title A-Z/Z-A ④Price 高低 ⑤Date created 新舊 ⑥Manually。
- 手動排序：拖曳；多選 Move：To the beginning/To the end/To position。手動排序上限與「條件集合可否手動排」**未取得**（本尊實測待補）。
- Admin Collection items 分頁 **60 品/頁**；list 或 3–6 欄網格。
- 前台主題按集合 sort order 渲染。

### collection-settings
- 可用性（Channels 勾選）；排程發布（日曆 icon）；theme template 下拉。
- **SEO**：Page title ≤**70**；Meta description ≤**320**；handle 可改且**可選擇建立舊 URL redirect**。
- 集合對 Online Store 可見 ≠ 自動進選單；集合可用性不影響個別商品可用性。

### make-collections-findable
- 前置：集合須先在 Online Store 可用。Content > Menus → Add menu item → Collections → 選集合 → Label → Save。
- 選單連結可**附 tag 過濾**（顯示同時符合全部輸入 tag 的商品）。

### search-view
- 搜尋比對 title＋description；排序僅 Title/Updated 兩軸；篩選 **Channel**（included/excluded；is/is not；and/or）；saved views 全套（Duplicate/Rename/Delete 不可復原）。

### legacy 兩頁
- smart-collections：≤60 條件；AND/OR；被新 model 取代中。
- manual-shopify-collection：**只能加整個商品（變體層級只有新 model 支援）**；「不能把自動集合轉手動」。

### Featured collections
- 現行 IA **無專頁**；屬 theme editor 的 Featured collection section；vintage 舊頁已 302。

## 分支 2：admin 商品搜尋與篩選（…/products/searching-filtering）

- 列表 **50 品/頁**；admin 排序/篩選**不影響前台**。
- **排序 7 軸**：Product A-Z/Z-A、**Created（新→舊，預設）**、Updated、Inventory、Product type、Publishing、Vendor。desktop 改排序**刷新即回預設**；mobile app 才保存。
- 欄位自訂：Columns 拖曳重排＋眼睛顯隱；只作用當前 view。
- **篩選器 16 項**：Vendors／Tag／Statuses（archived, active, draft）／Categories／Sales channel（included-excluded）／Region catalog／B2B catalog／Company location catalog／Retail catalog／Unassigned catalog／Types／Collection／Publishing error／Gift card／Combined listings／**Metafields**（definition 開 "Use as filter in admin"）。
- 多篩選器一律 **AND**；同篩選器內多值＝逗號＝OR。
- **搜尋語法**：關鍵字比對 title/description/tags；`title:Pitcher`；前綴星號 `title:ani*`；`metafields.custom.material:silk`；`tag:new AND NOT tag:"new zealand"`；完整語法在 shopify.dev search-syntax。
- **Saved views**：預設四＝All/Active/Draft/Archived（不可改刪）；自訂 view＝篩選＋欄位＋排序快照；管理**僅 desktop**。
- 找「無 tag 商品」官方解法＝**繞道 CSV export**（admin 搜尋不可靠支援缺屬性查詢）。

## 分支 3：CSV 匯入匯出（…/products/import-export）

### using-csv（格式全欄）
- 檔案：UTF-8、LF、首列 header、逗號分隔；**15 MB**（明文出處在 import-products）。
- 列結構：無變體＝首列全欄＋第 1 圖，其後列只有 handle＋追加圖；有變體＝首列商品欄，後續列 handle＋變體欄＋圖。
- ⚠️ **兩套 header 並存**：本頁新格式欄名（`Title`、`URL handle`、`Description`、`Product image URL`…）vs common-import-issues 列的舊格式必要 header（`Handle,Title,Body (HTML),…,Image Src,Image Alt Text`）。實作對照必須兩套都認。
- **逐欄值域重點**：
  - URL handle：**create vs update 判定鍵**；字母數字連字號。
  - Tags：逗號分隔；**250/商品**。
  - Published on online store：true（預設）/false。Status：active（預設）/draft/archived。
  - Option1-3 name/value：**≤3 選項**；🔴 **改 Option value＝刪舊 variant ID 生新 ID**（紅字級警告，炸第三方依賴）。Option LinkedTo：`product.metafields.shopify.{attr}`。
  - Price／Compare-at／Cost per item：數字無符號；Price 空白→0.00。**Price / International**＋**Included / [市場名]**：header 依市場設定動態變化。
  - Charge tax：true 預設。Inventory tracker：`shopify`/`shipwire`/`amazon_marketplace_web`/空白（＝不追蹤）。Inventory quantity：整數、**僅單一地點**（多地點用 inventory CSV）；空白→0。Continue selling…：`deny`（預設）/`continue`。
  - Weight value (grams)：整數克。Weight unit for display：g/kg（預設）/lb/oz。Requires shipping：true 預設。
  - Fulfillment service：`manual`（預設）/自訂 handle。
  - Product image URL：公開 HTTPS 直鏈；**250 圖/商品**；Image position 排序；禁 `_thumb/_small/_medium` 後綴。Image alt text：**512 字元**（建議 ≤125）。Variant image URL 同規則。
  - Gift card：false 預設；🔴 **CSV 不能建立禮品卡**。
  - SEO title：**70**；SEO description：**320**；空白→fallback Title/Description。
  - Google Shopping 系列欄（Product Category/Gender/Age Group/MPN/Condition/Custom Product/Custom Label 0–4）。
  - **Collection 欄**：**唯一允許的自訂欄**；**每商品僅一個集合**；**255 字元**；不存在→**自動建立**；已存在條件集合→商品仍須符合條件；**export 不含此欄**。
  - Metafields 自訂欄：`Name (product.metafields.ns.key)` 形態；**變體 metafield 不支援 CSV**。
- **CSV 支援 metafield 型別**：boolean/color/date/date_time/dimension（`25.0cm`）/money（`5.99 CAD`）/number_decimal/number_integer/single_line_text/multi_line_text/url/volume/weight/product_reference/shopify.disclosure；list 型**分號分隔**（list.color/date/date_time/dimension/metaobject_reference/number_decimal/number_integer/product_reference/url/volume/weight）。
- **覆寫語義（Overwrite 勾選時）四分法**：
  1. handle 相符 → CSV 值取代；
  2. **有該欄但儲存格空白 → 欄位被清空**；
  3. **整欄缺席 → 既有值保留**；
  4. **有欄但缺依賴欄 → 既有資料被刪**（例：放 SKU 缺 Option name/value → 選項被刪、變體重建為 default）。
- 未勾 Overwrite：handle 相符的列被**忽略**。CSV 不能批次刪商品、不能改其他頻道可用性。

### import-products
- 流程：Products → Import → Add file →（選配）取消「Publish new products to all sales channels」→（選配）勾 Overwrite → Upload and continue → 摘要 → Import。完成寄 email。
- **判定鍵＝Handle**。**15 MB**。🔴 **啟動後不可取消、無匯入歷史**——先 export 備份。
- 新商品預設發布到**所有**頻道。指定 fulfillment service 匯入後再匯出顯示 `manual`。
- 換選項位置（Size 從 Option1 挪 Option2）會撞 "Line is invalid"；官方解法＝臨時選項名兩段匯入。

### export-products
- 範圍四選：Current page/All/Selected/**Current search and filters**；格式 CSV for Excel/Plain CSV。
- **交付**：全部變體 <100 且範圍 Current page 或 Selected → 瀏覽器直接下載；否則寄 email。
- **圖片檔不隨 CSV 匯出**（只有 URL）；**Collection 欄不匯出**；SEO 欄只有手動自訂過才有值；數千變體會逾時→分批。

### common-import-issues（錯誤訊息→規則）
- "Daily variant creation limit reached"：≥500,000 變體的店（Plus 除外）CSV＋API 24h 新建 ≤10,000。
- "Fulfillment service can't be blank"→填 `manual`；"Ignored line … handle already exists"→檔內 handle 唯一；"…did not contain product data"→有 handle 必須有 title。
- "Illegal quoting"→UTF-8＋直引號；"Invalid CSV header"→首列精確等於舊格式 26 欄 header（**大小寫敏感**）。
- "Inventory policy…"→僅 deny/continue；"Not a valid product category"→精確匹配 taxonomy。
- 🔴 **文檔內部矛盾**：錯誤訊息說 **20 MP** 上限，解法段卻寫 "up to 5000 x 5000 px, or **25 megapixels**"——兩句皆逐字取證；實作按嚴（20MP）驗，矛盾留 V 項。
- metafield product reference 必須指向既有商品→官方解法＝**分兩段匯入**。

## 跨模塊互動總表
- 集合→前台：按 sort order 渲染；feature 走 theme section；per-collection template。
- 集合→選單：須手動加 menu item；menu item 可帶 tag 過濾（AND）。
- 集合→折扣/稅：未發布集合可專供 tax override 與 discount。
- CSV→Markets：Price/Included 欄 header 動態；CSV→變體 ID 穩定性：改 Option value 炸 ID。
- admin 篩選→CSV：缺屬性查詢繞道 export。

## 未取得清單
1. 自動集合更新時效/SLA。
2. 手動排序商品數上限；條件集合可否手動排。
3. Featured collections 專頁（IA 不存在）。
4. Legacy smart collections 舊條件矩陣（被新 model 取代）。
5. 15 MB 在 using-csv 頁標 implied，明文在 import-products。
