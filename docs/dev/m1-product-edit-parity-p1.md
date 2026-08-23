# m1 — 商品編輯頁對齊 P1：組織分類＋SEO＋狀態 picker＋封存動作

> 依據：`docs/research/91-product-edit-live-teardown.md` §18 差距表 G1/G2/G3（P1 包）。
> 對應規格：63 §B.4（productSet 宣告式）、13 §F1.2（四態真值表）、28 §0.3（錯誤路徑）。
> 每控件四件事（鐵律 12.4）：①是什麼 ②功能與值域 ③怎麼做 ④跨功能影響。

## 1. GraphQL 契約增量

- `ProductSetInput` 新增 `vendor`／`productType`／`tags: [String]`／`seo: SEOInput{title,description}`。
  **宣告式語義**：缺席（nil）＝更新態保持現值（與 `status` 同）；空字串／空陣列＝清除。
  admin SPA 恆送全量；缺席只發生在 API 直呼叫。
- `Product` type 新增讀取面：`vendor`／`productType`（nullable）、`tags`（恆陣列）、
  `seo`（物件恆在、子欄位 null＝未覆寫；resolver 直接以 product 為 object，零額外查詢）。
- Query root 新增 `productVendors`／`productTypes`：本店 distinct＋DB collation 序＋
  上限 `api.pagination_max_page_size`；CJK 按碼位排（utf8mb4_0900_ai_ci，spec 有註）。
  ④影響：組織分類卡 autocomplete 的資料源；之後商品列表的 vendor 篩選器可直接複用。

## 2. 服務層（Catalog::SaveProduct#normalize_organization）

- ②值域：vendor／productType ≤ `product.vendor_max_chars`／`product.product_type_max_chars`
  （255，ours 非官方，對齊 DB varchar）；tags strip→去空→**去重保序**，總數 ≤ `product.max_tags`(250)、
  單標籤 ≤ `product.tag_max_chars`(255)；seo.title ≤ `content.seo_title_max_chars`(70)、
  seo.description ≤ `content.seo_meta_description_max_chars`(320)。
- 🔴 **160 不是上限**：本尊 Meta 描述 203/160 照樣可存（91 §11 實測）；160＝SERP 建議值
  （前端計數器分母），320 才是 reject 線。spec 有「200 字可存」的守門測試。
- 錯誤路徑（28 §0.3）：`vendor`／`productType`／`tags`／`seo.title`／`seo.description`，
  code 一律 `TOO_LONG`。
- ③實作：回傳 hash 只含**有提供的鍵**；create 直接 merge、update `assign_attributes` 展開
  ⇒ 缺席鍵天然「保持現值」。④影響：冪等 fingerprint 含新欄位（input.to_h 全量），
  同 key 改組織欄位重放會回 FINGERPRINT_MISMATCH——契約本來如此。

## 3. 前端（ProductDetailPage）

- **組織分類卡**（右欄第三卡，91 §12）：
  - 產品類型：①search-or-create combobox ②自由文字＋既有值建議 ③TextField＋datalist
    （`productTypes` query，失敗靜默降級成純輸入）④寫 `products.product_type`，
    之後分類篩選／報表 group by 用同欄。
  - 廠商：同型態，datalist 源 `productVendors`。
  - 標籤：①token 多值欄 ②Enter／逗號提交、chip × 移除、重複自動忽略 ③draft 輸入獨立 state
    ——**打到一半的標籤不弄髒 SaveBar**；逗號提交做在 onChange 尾端偵測（IME 組字期間
    不會產生裸逗號，中文輸入安全）④寫 `products.tags`（json）；前台 Liquid `product.tags`
    與之後的標籤篩選同源。
  - 佈景主題範本：select disabled「預設商品」（主題里程碑，G11）。
- **SEO 卡**（91 §11 形態）：收合態＝SERP 預覽（站名→`host › products › handle`→標題→描述→
  價格列 `HK$X.XX HKD`；覆寫值優先、留空 fallback 商品標題／說明前 160 字）；✏️ 展開＝
  頁面標題（計數器 `已使用 X / 70`，maxLength 70）＋Meta 描述（計數器 `X / 160`，
  **可超過**，硬上限 320）＋網址 handle（編輯態仍鎖定，301 屬 URL 包）。
  ④影響：`seo_title`／`seo_description` 是 G12 前台 `<title>`／`<meta name=description>`
  的資料源（62 號）；SERP 預覽的 fallback 規則將來要與前台渲染規則同源。
- **狀態 listbox**（91 §2 形態）：①按鈕＋popover listbox ②三選項各帶副行——啟用中／草稿／
  未列出（副行為我方措辭，鐵律 9 不抄本尊文案；語義取 13 §F1.2）；**封存不在清單**
  ③自訂元件（原生 option 放不下副行），aria-labelledby 掛卡內 label；ARCHIVED 現值時
  清單多顯示「已封存」項 ④status 寫入走同一 productSet；ProductsPage badge 表同源
  STATUS_PRESENTATION。
- **更多動作▾**（頁首，編輯態限定）：複製商品（disabled，P3）／封存商品⇄取消封存商品
  （**立即儲存**：pendingAutoSave ref＋status effect，本尊為即時動作不停 SaveBar；
  取消封存回 DRAFT）／刪除商品（disabled 紅字，P3）。
  ④影響：封存後列表 badge、狀態卡、可購買性讀值全部即時一致（同一 STATUS_* 表）。

## 4. 測試佈局

- 後端：`spec/requests/product_set_spec.rb`「組織分類＋SEO」describe——四欄位建立／
  缺席鍵保持現值＋空值清除／70 超限 reject＋200 字可存／suggestions 去重排序與租戶隔離。
- 前端：`ProductDetailPage.test.tsx` 全面改**路由式 fetch stub**（`stubRoutedFetch`）——
  🔴 教訓：掛載時 suggestions 查詢與商品載入並發，順序式 `mockResolvedValueOnce` 會互搶，
  哪個先發不保證；以後任何頁面測試新增並發請求一律路由式。

## 5. 已知邊界（後續包）

- 佈景範本值域（V-91.11）、管理發布（V-91.12）、複製／刪除（G8）、SERP 預覽與前台渲染
  同源化（G12 開工時把 fallback 規則抽 shared 模組）。
- 標籤「編輯」對話框（本尊右上入口，V-91.10）未做；現行 chips 內聯移除已覆蓋主流程。
