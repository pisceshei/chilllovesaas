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

### 🔴 核心不變量與它的**修正史**

不變量＝**「redirect 的 from_path 永遠不是一個還活著的資源網址」**。它同時擋掉
「鏈」（`{a→b, x→a}` 之所以是鏈，正因 `a` 同時是 from_path 與 P2 的活 handle）
與「活頁被遮蔽」。純表內的鏈由**鏈坍縮**在寫入時消掉。

🔴 **第一版把它寫成保證，而對抗審查（R6-3／P6-3）用實跑推翻了**：
pre-flight 檢查在 transaction 外、跨兩張表（活 handle 在 products／collections、
from_path 在 url_redirects），沒有任何 DB 約束能跨表擋 ⇒ check-then-act 在併發下
必破，複驗方撐開窗後表裡真的出現了鏈。
〔2026-08-25 更正：本節原文宣稱「兩件事合起來保證表裡永遠沒有鏈也沒有迴圈」，
且據此告訴第 36 包「不需要迴圈偵測」——**該保證在修法前不成立**。〕

**修法＝單一序列化點**：改名操作在**店級鎖**（`HandleChange.serialize!`）下序列化，
鎖內以**鎖定讀**複查兩件事（新路徑未被佔／舊 handle 未被別人拿走）。
代價＝同店改名彼此排隊；改名是商家手動低頻動作，這個代價買到可證明的正確性。

🔴 **兩個被實測推翻的直覺，一併記下**：
- **InnoDB 的 gap lock 關不了這個窗**：gap lock 彼此**相容**，兩個
  `SELECT … FOR UPDATE` 都會通過（實測）；只有 INSERT 會被擋，而那只涵蓋兩種
  到達順序中的一種。審查建議的「txn 內重查」只縮窗不關窗。
- **複查必須用鎖定讀**：REPEATABLE READ 下普通讀吃本 txn 快照，看不到等鎖期間
  對方 commit 的資料。

### 🔴 併發測試的假綠（本包第二個方法論教訓）

第一版的併發 spec 只是開兩個執行緒——MRI 的 GIL ＋ 查詢太快，它們幾乎必然自然
序列化：**四道守衛刪掉三道仍然全綠**。修法＝人工把窗撐在兩個不同位置（順序 A：
gate 在 pre-flight 之後；順序 B：gate 在 R1 的 txn 內、redirect 已插入未 commit）。

即使如此，逐一刪除仍證明不了每道守衛都承重——因為 `複查一` 的鎖定讀在 unique
index 上取的 gap lock **恰好**也擋住順序 B 的 INSERT。所以另加一格直接測
**序列化性質本身**（兩個 register! 的臨界區不得重疊），它對「刪掉店級鎖」穩定轉紅。
⚠️ `複查二` 在店級鎖下**構造上不可達**（刪掉不會紅）——檔內已誠實標為
fail-closed 第二道，**不宣稱它承重**。

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
「撞現任 handle」例），併發窗另有 DB 索引 `uq_products_handle`
（複驗＝`grep -n uq_products_handle db/schema.rb`）——
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
- **系列頁前端已一併解鎖**（審查 P6-4）：第一版只改服務端、前端仍 `disabled`，
  而我又把**共用的** `product.seo.handle.hintEdit` 改成「改 handle 會建立 301」
  ——鎖死的欄位上掛著描述改名行為的提示。既然服務端已支援，補齊前端比另立一個
  描述「為何鎖住」的鍵誠實。
- **spec 常數撞名的坑**（新踩）：describe 區塊裡的常數定義在 Object 上，
  後載檔覆蓋先載檔——第一版的 `SET` 撞 `inventory_adjust_spec` 的 `SET`，
  那邊兩例只在**整套跑**時炸（單跑全綠）。同型風險存在於既有 spec 的
  `MUTATION`／`CREATE`／`UPDATE` 這類通用名——只登記，不在本包順手全改（20.5）。
