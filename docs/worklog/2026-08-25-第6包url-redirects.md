# 2026-08-25 第 6 包：url_redirects＋handle 變更解鎖

對應規格：62 §B.5（表形狀）／§F.3（改名 301 語義）；整合執行規格 §4-6。
🔴 **301 引擎不在本包**（第 36 包——掛前台 404/410 handler 之前）；本包是表＋寫入端。

## 已完成的工作 (Done)

### 表與 limits

`url_redirects(shop_id, from_path, to_path, status_code, source)`，
unique [shop_id, from_path]＋to_path 反查索引（鏈坍縮用）。
🔴 **路徑存正規形（無 locale 前綴）**——62 §F.3：路由層剝前綴查表、命中後把前綴
加回去再 301；存帶前綴＝每語言一列。
limits 落三鍵：`redirect_sources`（62 §B.5 逐字四值）、`redirect_status_codes`
（[301, 410]——302 未在規格出現，manual 值域待第 36 包取證）、
`redirect_path_max_chars`（ours 防呆；unique 索引 utf8mb4 鍵長上限內）。

### 🔴 核心不變量：表裡永遠沒有鏈、沒有迴圈

兩件事合起來保證（spec 以「無任何列的 to_path 是別列的 from_path」釘住）：
1. **寫入時鏈坍縮**：B 改名 C 時把所有指向 /…/B 的列改指 /…/C（A→B 變 A→C）。
   不坍縮的話鏈隨改名次數線性成長，逼近 `seo.redirect_max_chain`（Google ≤10 hops）
   才爆——爆的時候已不知道是哪幾次改名疊出來的。
2. **舊 handle 永不回收**（62 §F.3 逐字）：新路徑不得是既有 from_path
   （迴圈需要「新 from＝某列的 to ∧ 新 to＝某列的 from」兩件同時成立，本條擋掉
   後半；形式論證見 `url_redirects_spec` 檔頭，機械複驗＝該檔的不變量斷言）。
   `Catalog::HandleChange.path_reserved?` 是判準入口（複驗全部呼叫端＝
   `git grep -n "path_reserved?" app/`，應恰為 SaveProduct×2、SaveCollection×2）——
   手填驗證、**handle 生成器**（生成出的 handle 撞舊網址要自動跳號）、
   商品與系列共用同一個。

### 解鎖三個寫入面

- **SaveProduct**：拆掉 `HandleChangePending` 硬拒 ⇒ 改名＋`register!` **同一個
  transaction**（redirect 沒寫成＝舊網址 404；寫了、改名回滾＝好網址被轉走——
  spec 用「變體被拒 ⇒ redirect 一併回滾」釘住原子性）。同值＝no-op 不落列。
- **SaveCollection**：先前對 handle 是**靜默忽略**（比硬拒更糟——商家以為改了、
  其實沒改）⇒ 同一套語義，/collections 前綴。
- **前端**：handle 欄在編輯態解鎖、兩態都送（同值伺服端 no-op）；hintEdit 文案
  從「不可變」改成「改 handle 會自動建立舊網址的 301 轉向」×5 語言。

### 錯誤面

`handle_redirected`（product＋collection ×5 語言）：「舊 handle 不回收」要說得出
原因，不能只回一句 taken。`handle_change_pending` 五語言全部移除（死鍵）。
🔴 更新態撞另一商品的現任 handle **不另寫檢查**：model 的 `validates :handle,
uniqueness` → RecordInvalid → HANDLE_TAKEN 承接（紅測＝`url_redirects_spec` 的
「撞現任 handle」例），DB 唯一索引 `uq_products_handle` 是併發窗的第二道——
再寫一份是突變測不出差異的冗餘（本包實測：寫了又刪）。

### 測試

`spec/requests/url_redirects_spec.rb`（7 例）：改名落列／鏈坍縮不變量／改回去被拒／
建立不得佔用 from_path（手填拒＋生成跳號）／撞現任 handle 零副作用／
**回滾原子性**／系列前綴。既有 product_set_spec 的「暫拒」例改寫成新契約。
🔴 六道守衛突變驗證（五紅；一道證實冗餘後移除）。

## 修改的檔案與核心邏輯 (Changes)

- `db/migrate/20260826056500_create_url_redirects.rb`、`app/models/url_redirect.rb`、
  `app/services/catalog/handle_change.rb`（皆新）。
- `app/services/catalog/{save_product,save_collection}.rb`（解鎖＋掛鉤＋生成器擋位）。
- `app/frontend/admin/pages/ProductDetailPage.tsx`（欄位解鎖＋兩態送 handle）。
- `config/limits.yml`（seo 三鍵）；i18n：`config/locales` ×5（+2 鍵 −1 鍵）、
  前端 hintEdit ×5。
- `spec/requests/url_redirects_spec.rb`（新）；`product_set_spec` 一例改寫；
  `ProductDetailPage.test.tsx` 一斷言改新契約。

## 尚未完成或需注意的風險 (Pending / TODO)

- **301 引擎與後台重導管理＝第 36 包**：本包只有寫入端。在那之前 redirect 列
  存而不用——這是排程的刻意順序（此刻沒有任何顧客可見 URL 會斷）。
- **manual／domain_move／import 三種 source 無寫入者**（第 36 包／匯入包）。
- **410（下架）不在本包**：`redirect_status_codes` 已含 410，寫入者隨下架流程。
- **系列頁前端未動**：`CollectionDetailPage` 的 handle 欄位現況（唯讀與否）
  未在本包射程內驗證——服務端已支援，前端解鎖屬第 23 包同型小改，登記待辦。
- **spec 常數撞名的坑**（新踩）：describe 區塊裡的常數定義在 Object 上，
  後載檔覆蓋先載檔——第一版的 `SET` 撞 `inventory_adjust_spec` 的 `SET`，
  那邊兩例只在**整套跑**時炸（單跑全綠）。同型風險存在於既有 spec 的
  `MUTATION`／`CREATE`／`UPDATE` 這類通用名——只登記，不在本包順手全改（20.5）。
