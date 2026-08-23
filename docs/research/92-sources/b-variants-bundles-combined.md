# 92-B — variants／bundles／combined listings（help 深讀，取證 2026-08-23）

> 92 號研究的來源分冊 B（研究代理原始報告）。覆蓋：variants 主頁＋5 子頁＋bulk-editing 工具頁；bundles 主頁＋4 子頁；combined-listings-app 單頁。共 13 頁。

## 分支 1：Variants

### Variants 總覽（https://help.shopify.com/en/manual/products/variants，取證 2026-08-23）
- 變體＝選項值的組合（size×color 每組合一變體）。
- Metafields 可為變體存放專用資料，但「目前無法顯示給顧客」（相容主題可經 theme editor 顯示引用）。
- Category metafields 可連接到變體選項以跨商品重用資料。
- Plus 商家可用 Combined Listings app 把多個獨立商品合併為單一 listing。
- **子頁清單**：`add-variants`、`edit-variants`、`publish-variants`、`find-variant-id`、`searching-filtering`。
  ⚠️ 不存在獨立「variant limits」頁——上限全登記在 add-variants；`/variants/publishing-product-variants` 會回總覽（非真實路由），真實路由是 `/variants/publish-variants`。

### Adding variants（…/variants/add-variants，取證 2026-08-23）
- 流程（desktop）：Products → 商品 → Variants 區「+ Add options like size or color」→ 選項名 → 選項值 → 可「+ Add another option」（最多 3）→ Done → Save。
- **四種追加變體方式**：①對既有選項加值（自動生成所有組合）②手動單獨新增（要求至少一個新的選項值）③複製變體（儲存前必須改至少一個選項值）④批量複製（bulk actions）。
- 上限（原文）：
  - 「You can create up to 2,048 variants for a product.」
  - 「Each product can have up to three options.」
  - 「You can have up to 250 media items, such as images, per product.」
  - 「If you have 500,000 or more variants in your store, then you're subject to a daily rate limit … You can add up to 10,000 new variants in a day」——只限 app／CSV import 途徑。
  - 「If you're on the Shopify Plus plan, then the daily rate limit … doesn't apply.」
- **>100 變體相容性四條**：①部分第三方主題不支援 ②某些 theme app extensions、public apps、銷售渠道可能不支援 ③ Stocky 與 legacy Order Printer 不支援 ④依賴 REST Admin API 的 custom apps 必須遷移 GraphQL。

### Editing variants（…/variants/edit-variants，取證 2026-08-23）
- 單一變體編輯：Variants 區點變體 → 改選項/價格/庫存/運送 → Save。
- 商品詳情頁 inline 直改：變體圖（點列表圖）、變體價（點價格欄）、各 location 可售庫存（先按 location 過濾）。
- Bulk editor：勾選變體 → Bulk edit → 修改 → Save。
- 選項編輯：加選項／改選項名（Edit → 新名）／刪選項值（Edit → 值旁垃圾桶）／刪整個選項（選項名旁垃圾桶）。
- 重排：選項用拖曳把手重排；值先點 Edit 再拖曳 → Save。
- 刪除變體：變體詳情 → Delete variant（再確認）；批量走 bulk actions。
- 🔴 **群組頂層列不是變體**：「If you adjust the top level listing's price or image, then all variant prices and images within the group change as well.」——組頭編輯＝廣播到組內全部變體。
- 🔴 **停售 vs 刪除**：想保留歷史或日後重上架 → 用 publish/unpublish 不要刪。
- 🔴 **回到無變體商品**：必須刪光所有選項與值（含 default），否則前台仍顯示變體下拉。
- 變體 metafields 以可編輯表格出現在變體詳情頁。

### Publishing variants（…/variants/publish-variants，取證 2026-08-23）
- 入口：變體的 Publishing 欄（或勾多變體 → Manage publishing）→ 對話框勾/取消 **Sales Channels 或 Catalogs** → Done → Save。
- **預設**：新變體預設已發布，除非父商品未發布或首次儲存前手動取消。
- **可見性＝AND**：父商品與變體都已發布才可見。
- **全滅規則**：某渠道所有變體都未發布 ⇒ 整商品從該渠道隱藏。
- 商品 Publishing 區顯示「Excludes some variants」提示。
- 🔴 變體**不能**設個別發布日期（future publishing 只有商品級）。
- Catalog 自訂定價——未發布到該 catalog 的變體不取得 custom pricing。

### Find a variant ID（…/variants/find-variant-id，取證 2026-08-23）
- ①URL `/variants/` 後數字 ②無變體商品：詳情 URL 加 `.json` 讀 `product>variants>id` ③Analytics 自訂報表加 Product variant ID dimension。
- 無變體商品 JSON：`"title": "Default Title"`、`"option1": "Default Title"`，顧客不可見——預設變體語義官方表述。

### Search, filter, group variants（…/variants/searching-filtering，取證 2026-08-23）
- Variants 區搜尋/過濾 icon：按 title 搜尋、按選項值過濾（多過濾器＝**AND**）；「All locations」→ 選 location（預設 All，顯示合計）。
- **Group by**：多選項時可改分組依據；預設按第一選項分組，組頭顯示組內變體總數；分組順序跟隨第一選項顯示順序。
- 選定特定 location 後才能 inline 編輯該 location 庫存。
- 需 desktop 或 mobile 瀏覽器版 admin。

### Bulk editing 工具頁（…/shopify-admin/productivity-tools/bulk-editing，取證 2026-08-23）
- variants 分支無獨立 bulk 子頁；本工具頁承載跨商品批量編輯。
- 多變體商品「只能從 Inventory 區批量編輯商品的庫存」。
- 交互：方向鍵移動；Alt/Command＋點＝非相鄰多格；Shift＋點＝範圍；拖曳跨格；fill handle 複製；拖欄分隔線調寬。
- 無明示最大列數上限；Edge 可能出 URL 錯誤，建議 Chrome/Firefox/Safari。

## 分支 2：Product bundles

### 總覽（…/products/bundles，取證 2026-08-23）
- 必要條件：「you must have a bundles app installed」。
- 可售渠道＝Online Store、Shop、Shopify POS、Google & YouTube（後者**只支援 fixed bundles**）。
- 子頁：eligibility-and-considerations／scripts／shopify-bundles／bundles-grouped-view-email-template-updates。

### Eligibility and considerations（…/bundles/eligibility-and-considerations，取證 2026-08-23）
- **三種類型**：Fixed bundle（預定集合；多選項時顧客可選變體）｜Multipack（同一商品多件）｜Mix-and-match（顧客自行組合）。
- **資格三條件**：①Online Store 或 custom storefront ②裝了 bundles app ③升級版 checkout（與 checkout.liquid 不相容）。
- **失格後果**：fixed bundles 退回 **Draft**；客製 bundles 在購物車/結帳拆成個別項目。
- 🔴 **庫存演算法**：各成分可售量 ÷ 所需數量 → 向下取整 → 取最小值（例：2 椅需求有 15 ⇒ 7；1 桌有 8 ⇒ 8；bundle 可售 7）。**排除**：關閉追蹤或開了 oversell 的商品不參與。即時更新。
- **退貨**：bundle 本身不能標 final sale；由成分的 final-sale 決定；self-serve returns 顧客只能對非 final-sale 項申請。
- **SKU**：bundle SKU 獨立；**成分 SKU 變更 ⇒ 必須整個重建 bundle**。
- **不相容**：purchase options（subscriptions/pre-orders/TBYB）、Shopify Subscriptions app、custom products、bundle 套 bundle、**exchange 交易（換同一 bundle 也不行）**。
- 運費按成分各自 shipping profile；**無 import/export、無批量編輯**。
- 辨識：庫存欄「Bundle with XX variants」；詳情頁「Bundled products」區塊；訂單側巢狀 line-item 群組；**拆分履行與退貨時成分以個別 line items 顯示**。
- Fixed/Multipack：免費 Shopify Bundles app 全 plan；Mix-and-match：第三方 app 或 Bundles APIs 自建（**自建限 Plus**）；Cart Transform API update 操作在 Plus trial 不可用。

### Shopify Bundles app（…/bundles/shopify-bundles，取證 2026-08-23）
- 建立：Apps → Bundles → Create bundle → 標題 → 選品 → 可調（數量、變體、數量做成選項、複製成 multipack、合併同名選項）→ Save and continue → 補商品資料 → 狀態設 Active。**預設 Draft**。
- 上限（原文）：「Fixed bundles: Up to 30 components」｜「Dynamic bundles: Up to 150 components」｜「Up to 2000 units per component」｜「Maximum of 3 options and 100 variants total per bundle」——🔴 bundle 變體上限 **100** 非 2,048。
- 合併同名選項：前提＝各商品選項值相符；**合併後佔 3 個選項額度之一**。
- 🔴 **Draft 回退狀態機**：成分變體/選項被刪或改名 ⇒ bundle 自動 Active→Draft。修復：Bundled products 區點 app icon → 更新，或移除受影響商品重加。
- 同步技巧：某成分數量 +1 → 存 → 改回，觸發 re-sync。
- 折扣：支援 codes＋automatic＋組合；集合/指定商品折扣要納入 **bundle 父商品**；**折扣先算 bundle 再按加權價分配成分**；**稅按個別成分計算**。
- 定價：成分價變動 bundle 價**不自動更新**。
- 庫存：「Bundles don't track inventory by location, but by overall stock」。
- 訂單：SKU 列成分 SKU；重量由成分推導。
- Search & Discovery：被 bundle 的商品不出現在選項過濾器。
- 全 plan 免費；渠道僅 **Online Store 與 Headless**。

### Scripts 與 bundles（…/bundles/scripts，取證 2026-08-23）
- 🔴 「As of June 30, 2026, Shopify Scripts has been deprecated.」已停用，轉 Shopify Functions。
- 歷史事實：line item scripts 對 bundle line items 只有唯讀方法生效；變更類（change_line_price/change_properties/split/delete_if）被忽略；成分在 cart 不可讀。

### Bundles email template updates（…/bundles/bundles-grouped-view-email-template-updates，取證 2026-08-23）
- 2024-12-06 起預設通知模板改巢狀群組顯示；已客製模板須手動更新。
- Grouped view 模板：Order confirmation／Order invoice／Pending payment error/success／POS email／POS and mobile receipt／Abandoned checkout；員工側 New order／New draft order。
- Flat view 模板：Return created／Return request received/approved/declined；員工側 New return request／Sales attribution edited。
- 改碼要點：`{% if line.groups.size == 0 %}` 包舊邏輯＋`line_item_groups` 迴圈；draft/棄單模板 `{% assign expand_bundles = true %}`＋`line.bundle_parent?`＋`line.bundle_components`。
- 🔴 「If you revert a template without backing up your customizations, then your customizations will be lost and can't be recovered.」

## 分支 3：Combined listings（…/products/combined-listings-app，取證 2026-08-23；單頁）

- 建立：Apps → Combined Listings → Create combined listing → 標題 → Add products → 加最多 3 個唯一選項名 → 每商品指定選項值（手動或連 category metafields）→ Save（**預設 Draft**）→ 可改 Active 或 Unlisted。
- 編輯：加/移除子商品、加/改/刪選項、改值、**重排選項**（⇆ Reorder → 拖曳 → Confirm → Save）。
- 刪除：Delete combined listing → 確認；「Child products … aren't deleted」。
- 上限：**60 商品/listing**；**3 個追加選項**；**全子商品合計 2,000 個變體選項值**。
- 狀態值域：Draft／Active／Unlisted（「Hidden from collections and storefront search, but its product page remains accessible by direct URL」）。
- 結構＝parent product＋child products（各自保留 title/description/URL/圖庫），以共享選項連接。
- 約束：選項名 parent/child 間唯一；一商品不能屬多個 listings；只能加既有商品；不能巢狀。
- Category metafields：至少一子商品有 category 才能連；多 category 條目只連第一值；metafield 變更不回寫子商品 category。
- Unlisted parent 不出現在搜尋與自動推薦（無論 S&D 設定）。
- 不相容：只在 online storefront；不能作 featured products、bundles、subscriptions；S&D 選項過濾不含子商品。
- S&D 設定：只顯示子商品／只顯示 parent／兩者都顯示。
- 主題門檻：免費主題 **15.0.0+**；需要時 admin 顯示 banner。
- 🔴 **僅 Plus 與 enterprise commerce plans**。

## 關鍵數字彙總表（全部帶出處）

| 上限 | 值 | 出處 |
|---|---|---|
| 每商品變體數 | 2,048 | /variants/add-variants |
| 每商品選項數 | 3 | /variants/add-variants、/variants/edit-variants |
| 每商品媒體數 | 250 | /variants/add-variants |
| 日增變體限流（app/CSV，店內 ≥500,000 變體時） | 10,000/日；Plus 豁免 | /variants/add-variants |
| 主題/app 相容門檻 | >100 變體（Stocky、legacy Order Printer 不支援） | /variants/add-variants |
| Fixed bundle 成分數 | 30 | /bundles/shopify-bundles |
| Dynamic bundle 成分數 | 150 | /bundles/shopify-bundles |
| 每成分單位數 | 2,000 | /bundles/shopify-bundles |
| 每 bundle 選項/變體 | 3 選項、100 變體 | /bundles/shopify-bundles |
| Combined listing 子商品數 | 60 | /combined-listings-app |
| Combined listing 追加選項數 | 3 | /combined-listings-app |
| Combined listing 全子商品選項值總數 | 2,000 | /combined-listings-app |

## 未取得項
- bulk-editing 工具頁未列可批量編輯的變體欄位完整清單（頁面本身不含）。
- variants 分支不存在獨立「variant limits」子頁。
- combined-listings-app 未發現子頁（單頁）。
