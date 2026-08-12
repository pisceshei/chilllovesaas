# 15 — 功能規格：購物車、結帳、金流（生產級）

> 全專案風險最高、最不能出錯的一條線。覆蓋功能：cart、金額引擎、one-page checkout、Stripe 整合、訂單成立、訂單編號、thank you/order status、棄單。規格對照研究 04/06/08，基線見 11。

## F1. Cart

**生產級做法**：
1. `carts`（token 簽名 cookie `_cl_buyer`，host-only 綁店網域）+ `cart_line_items`（variant_id、quantity、加入當下價格僅供顯示）。
2. 寫入 API：add/change/update/clear（對齊 03 的 Ajax 慣例），全部回 turbo_stream 局部更新；**兩層數量限制並存**：
   - **`cart_item_limit`（官方概念）＝購物車「總件數」上限**，系統建議值 **50**，可由商家在「結帳 › 進階偏好設定 › 加入購物車數量上限」開關與調整；**例外：POS／草稿單／B2B／不追蹤庫存的品項不受限**。值取自 `limits.cart.item_limit_suggested`。
   - **本專案防呆上限**：每行 999、行數 100（`limits.cart.max_quantity_per_line` / `max_lines`）——這是防呆，**不是** `cart_item_limit`。
   <!-- 依 44:378、24:230 修正，原文：後台 modal 實測 toggle（開）＋ stepper=50 ＋灰字「您商店的建議上限為 50」，用途「保護您可用的庫存數量不外洩」，
        例外為 POS/draft/B2B/不追蹤庫存。
        🔴 此處原本寫錯：15:9 原本只有「每行 999、行數 100」，把「總件數上限」與「單行/行數上限」混為一談，
        且官方的 `cart_item_limit` 概念完全缺席。兩者是不同概念，必須並存。任何人翻舊版都不要刪掉 cart_item_limit。 -->
3. **價格以當下為準**：cart 顯示即時價（查 variant），進 checkout 時重新快照；商品下架/售罄 → cart 行標記不可購並擋結帳。
4. 過期：90 天未動的 cart purge job。
5. 併發：同 token 兩個分頁同時加購 → 行級 upsert（唯一索引 `(cart_id, variant_id)` + `ON DUPLICATE KEY UPDATE quantity = quantity + ?`）。

**⚠️ 坑**：cart cookie 設在 `.主網域` 會跨店共享——必須 host-only（11 §8）；變體被刪後 cart 行殘留 → FK `ON DELETE CASCADE` 或渲染時濾掉；別在 cart 階段扣庫存（只在付款成功時扣，見 F5）。

## F2. 金額引擎（Checkout::Calculator）

**生產級做法**：
1. 純函式 PORO：輸入（line items 快照、地址、折扣碼、shipping 選擇）→ 輸出不可變 Result（subtotal、discount 分攤明細、shipping、tax、total，全 integer cents）。
2. **一處實作、四處重用**：checkout 預覽、訂單成立、draft order、退款計算全用它；任何頁面顯示的金額都來自同一 Result，杜絕「兩處算出不同總計」。
3. 分攤規則（寫死並測試）：訂單級折扣按各行金額比例分攤，**餘數用最大餘數法**（largest remainder）分給金額最大行——保證 `Σ 行分攤 = 折扣總額` 恆等。
4. 稅：demo 為未稅價 + 單一稅率；**含稅模式**（台灣常態）：行級反推 `tax = total - total / (1+rate)`，每行四捨五入後加總（選定「行級進位」策略並全域一致）。
5. 表格驅動測試 ≥40 組（含 1 元、999999999、折扣大於小計、免運邊界、含稅反推 ±1 分錢案例）+ property test：隨機 cart 驗證三不變量（總計非負、分攤總和相等、行金額和=小計）。

**代碼**：

```ruby
def allocate(total_cents, weights)  # 最大餘數法
  base = weights.map { |w| total_cents * w / weights.sum }        # 整數除法向下
  rem  = total_cents - base.sum
  order = weights.each_index.sort_by { |i| -(weights[i] * total_cents % weights.sum) }
  order.first(rem).each { |i| base[i] += 1 }
  base
end
```

**⚠️ 坑**：
- 任何地方出現 Float 算錢即 bug（rubocop 自訂 cop 掃 `to_f` 出現在 *_cents 附近）。
- 分攤各行後再退款時，退某一行的金額必須查 `discount_applications` 的行級分攤，不能按比例重算（會與原分攤差 1 分錢）。
- 含稅/未稅切換是「顯示+計算」雙重語意，設定變更不回溯舊訂單（訂單存快照）。

### F2.1 跨運送設定檔的合併運費（P1-23／原 NP0-F，金額正確性）

> <!-- 依 46c:867–876（H42 zh-TW）修正，原文（逐字四條）：
>      ①「系統會將各商品的運費合併，並在結帳頁面只向顧客顯示一筆運費」
>      ②「名稱相同的運費費率會相加，並在結帳頁面顯示給顧客」
>      ③「若所有費率的名稱都不同，系統會將**最便宜的選項**相加」
>      ④「（同一 location group 內多地點出貨）系統會只收取一次單一費率」
>      ⑤重量制「逐品項加上商店預設包裹重量後再相加，**可能算出比單一設定檔更高的總額**」
>      46c:876 逐字實作含意：「費率名稱是**合併鍵**。名稱一字之差就會從『相加』變成『取最便宜相加』」。
>      我方原本只有 22:150（現 22:182）「跨方案購物車運費相加」一句，**合併鍵完全沒寫** → 跨設定檔購物車的運費直接算錯。
>      52 號（P0 輪）僅在 22 §8 補了規則描述，公式與算例留在此處補齊。 -->

**為什麼這條與 P0-01／P0-03 同級**：它是「金額直接算錯」，只是缺口在運費側。同一個購物車，只因商家把某張費率命名為 `快遞` 而不是 `快遞配送`，結帳運費就會從「相加」跳成「取最便宜相加」，兩者可以差好幾百元（見算例 3）。

**(a) 參與者（participant）的定義——合併的最小單位不是「設定檔」而是 `(設定檔 × location group)`**

```
participants P = { (profile_id, location_group_id) | 該 pair 至少負責購物車中一個 line item 的出貨 }
```
同一個 location group 內即使跨兩個實體地點出貨，**也只算一個 participant、只收一次費率**（46c:873）。
`|P| = 1` 時本節退化為單一設定檔的一般費率解析（無合併行為）。

**(b) 每個 participant 各自產生候選費率集合**

```
Rates(p) = { (name, price_cents) | 該 rate 屬於 p 的 zone 且條件成立 }
```
- 條件（重量區間／金額區間）以 **p 自己負責的那批 line item** 判斷，不是整車。
- **重量制**：`parcel_weight_grams(p) = Σ_i(item_weight_grams[i] × qty[i]) + shop.default_package_weight_grams`
  ——包裹重量**每個 participant 各加一次**。這正是 46c 說「可能算出比單一設定檔更高的總額」的原因（見算例 4）。
- 「滿 X 免運」是一張 `price_cents = 0` 的條件費率，**照常參與合併**（不是把整筆運費歸零）。
- `Rates(p) = ∅`（該 participant 在此目的地無可用費率）→ **整車不可配送到此地址**，結帳擋下（不是當作 0 元）。

**(c) 合併鍵與合併公式（唯一實作，`Checkout::ShippingRateMerger`）**

```
key(rate)      = normalize(rate.name)                    # 合併鍵＝費率名稱，不是 rate id、不是 service code
Names(p)       = { key(r) | r ∈ Rates(p) }
CommonNames    = ⋂_{p ∈ P} Names(p)                      # 交集：必須「每一個」participant 都有這個名字

# 分支 1：有共同名稱 → 逐名相加，每個共同名稱成為結帳的一個運送選項
if CommonNames ≠ ∅:
    for n in CommonNames:
        option[n].price_cents = Σ_{p ∈ P} price_of(p, n)          # 純整數加總，無捨入
    options = { option[n] | n ∈ CommonNames }                     # 不在交集內的名稱一律丟棄

# 分支 2：沒有任何共同名稱 → 併成單一選項，取每個 participant 最便宜者相加
else:
    options = { single_option }
    single_option.price_cents = Σ_{p ∈ P} min{ r.price_cents | r ∈ Rates(p) }
```

**捨入位置（鐵律 3）**：全程 **integer cents**，加總與取最小值都是精確整數運算，**本節沒有任何捨入點**。
唯一與幣別有關的處理在序列化層（零小數幣別由 15-F4 `stripe_amount()` 處理）；presentment 換匯在 29 §3 的 money service，**不得在合併階段換匯**（會產生「先換匯再相加」與「先相加再換匯」差 1 分錢的兩套答案）。

**(d) 合併鍵的正規化**：`normalize(name) = Unicode NFC → 去除前後空白`，**大小寫敏感**、中間空白不壓縮。
**⚠ 待查證（來源未載明）**：Shopify 對費率名稱比對是否 case-insensitive、是否 trim——`46c:869–876` 只說「名稱相同」，未定義正規化規則。上式為**本專案決策**（`limits.shipping.rate_merge_key_normalization`，`verify_rate_name_case_sensitivity: true`）。
**UI 硬要求（46c:876 明確點名）**：運送設定檔編輯畫面必須對「跨設定檔的近似但不相同名稱」（正規化後編輯距離 ≤2，或僅大小寫/空白差異）出警示——這是文檔唯一主動要求做的防呆。

**(e) 與其他階段的先後順序（不可對調）**
1. 折扣 pipeline 的 **第 4 步產生配送選項**（本節）→ **第 5 步才套運費折扣**（17-F2）。合併**先於**運費折扣，免運折扣打在合併後的金額上。
2. 稅：運費是否課稅依 22 §8 稅設定，稅在合併後計算。
3. `limits.discount.max_codes_per_checkout_shipping: 1`；運費折扣不可疊運費折扣（17-F2）。

**(f) 三＋一個算例（驗收測試向量，幣別 TWD，integer cents）**

**算例 1 — 兩檔名稱相同 → 相加**
| participant | 候選費率 |
|---|---|
| P1（一般設定檔 × LG-北區） | `標準宅配` 8000 |
| P2（大型商品設定檔 × LG-北區） | `標準宅配` 12000 |

`CommonNames = {標準宅配}` → 結帳顯示 **1 個選項** `標準宅配 = 8000 + 12000 = 20000`（NT$200）。

**算例 2 — 三檔名稱全不同 → 各取最便宜再相加**
| participant | 候選費率 | 該檔最便宜 |
|---|---|---|
| P1（一般設定檔） | `標準宅配` 8000／`快遞` 15000 | 8000 |
| P2（冷凍設定檔） | `低溫宅配` 18000 | 18000 |
| P3（大型商品設定檔） | `大型物流` 35000／`大型物流-偏遠` 45000 | 35000 |

`CommonNames = {標準宅配,快遞} ∩ {低溫宅配} ∩ {大型物流,大型物流-偏遠} = ∅` → 走分支 2 →
**單一選項 = 8000 + 18000 + 35000 = 61000**（NT$610）。
**⚠ 待查證（來源未載明）**：此合併選項對顧客顯示的**名稱**，46c 未載明。本專案暫用商家可設的通用字串（預設「運費」），標 `limits.shipping.merged_option_fallback_label`，見 §待查證 V-15。

**算例 3 — 部分同名、部分不同（合併鍵的踩雷點）**
| participant | 候選費率 |
|---|---|
| P1 | `標準宅配` 8000／`快遞` 15000 |
| P2 | `標準宅配` 6000／`貨到付款專用` 9000 |
| P3 | `標準宅配` 5000／`快遞` 12000 |

`CommonNames = {標準宅配}`（`快遞` 只存在於 P1、P3，**P2 沒有 → 不在交集**）→
- `標準宅配 = 8000 + 6000 + 5000 = 19000`（唯一選項）
- **`快遞` 不會出現在結帳頁**，即使兩個設定檔都有它。

> 🔴 **對照組（同一批費率、只改一個名字）**：把 P2 的 `貨到付款專用` 改名為 `快遞`（價格仍 9000）→
> `CommonNames = {標準宅配, 快遞}` → 多出一個選項 `快遞 = 15000 + 9000 + 12000 = 36000`。
> **改一個字 = 結帳多一個選項、金額多 17000**。這就是 46c:876 要求 UI 警示的理由，也是本條被判為「金額直接算錯」的理由。

**算例 4 — 重量制：每個 participant 各加一次包裹重量（總額高於單一設定檔）**
商店預設包裹重量 500g；費率名稱兩檔皆為 `標準宅配`；級距 `0–1kg = 5000`／`1–2kg = 8000`。
| participant | 品項重量 | ＋包裹重 | 落在級距 | 費率 |
|---|---|---|---|---|
| P1 | 1200g | 1700g | 1–2kg | 8000 |
| P2 | 300g | 800g | 0–1kg | 5000 |

合併（同名相加）＝ **13000**。
若同樣的商品全部落在**一個**設定檔：`1500g + 500g = 2000g` → 1–2kg → **8000**。
**13000 > 8000** ✅ 與 46c:874 逐字「可能算出比單一設定檔更高的總額」一致——**這不是 bug，不要在實作時「修正」成 8000**。

**算例 5 — 同一 location group 多地點只收一次**
一般設定檔的 LG-北區含「台北倉」「桃園倉」；商品 X 從台北倉、商品 Y 從桃園倉出。
participants 只有 **1 個** `(一般設定檔, LG-北區)` → `標準宅配 = 8000`（**不是 16000**）。

**(g) 必測性質**
1. **交換律／結合律**：participants 的枚舉順序不影響結果（property test）。
2. **無捨入**：任一中間值出現 float 即測試失敗；`Σ` 與 `min` 全程 integer。
3. **分支切換測試**：算例 3 的對照組——只改名稱、不改價格，結帳選項集合與金額必須跟著變（這是最容易被實作者「順手優化掉」的行為）。
4. **交集語義**：名稱只被「部分」participant 擁有時**必須丟棄**，不得退化為「該名稱只加有它的那幾檔」。
5. **無可用費率**：任一 participant 的 `Rates(p) = ∅` → 整車擋下，**不得**把該檔當 0 元。
6. **location group 去重**：同 group 兩地點 → 只收一次。
7. **重量制回歸**：算例 4 的 13000 必須成立（防「修正成 8000」的回歸）。
8. 與 17-F2 的順序：先合併、後套運費折扣（免運碼打在 20000 上而不是 8000 上）。

### F2.2 zone ≠ market：運送區域不等於可販售國家（P1-24）

> <!-- 依 44:524、44:622 補寫，原文：運送設定檔 zone 頁的黃色警示橫幅逐字「⚠ 若要在此區域開始銷售至 27 個國家/地區，請將這些國家/地區加入市場」；
>      44 行動項 38 逐字「**zone ≠ market**：建了運送區域不代表能賣，必須同時加進 Markets。這是一條跨模組硬約束，我們 29 號 Markets 與 15 號 Shipping 都沒寫」。
>      複核更正：29:118 其實已寫了**反方向**的一句「shipping zones 與市場國家對齊，未涵蓋國家=不可結帳」，
>      50 號「29 與 15 都沒有」不完全成立；真正缺的是①正方向（有 zone、不在 market → 不可販售）②admin 警示 ③15 側 RateResolver 的 guard。 -->

**兩個方向都要有 guard（同一條約束的兩端）**：

| 方向 | 判定 | 行為 | 出處 |
|---|---|---|---|
| 有 zone、國家不在任何 active market | `country ∈ shipping_zone.countries` 且 `country ∉ ⋃ active_market.regions` | **不可販售**：前台該國訪客走 backup region（可看不可買）；admin 運送 zone 頁出黃色警示橫幅「若要在此區域開始銷售至 N 個國家/地區，請將這些國家/地區加入市場」＋直達 Markets 的連結 | 44:524（live） |
| 在 market、無任何 zone 涵蓋 | `country ∈ active_market.regions` 且 `∄ participant` 有可用費率 | **可瀏覽、結帳到運送階段被擋**（F2.1(b) 的 `Rates(p) = ∅` 分支） | 29 §5（我方既有） |

`limits.shipping.zone_requires_market: true`。**兩個方向的差集數量必須在 admin 可見**（Markets 頁與 Shipping 頁各顯示對方的缺口計數），否則商家只會在客訴時才發現。
**跨模組落點**：Markets 側規格見 29 §5；本節是 15 側的 RateResolver guard。

### F2.3 COD（貨到付款）代收手續費行項（P1-08／TW-7）

> <!-- 依 42:542 補寫，原文逐字：「**超商取貨付款**（同 12.2 IsCollection=Y，取貨時付現）與**宅配貨到付款**（黑貓/新竹到府代收，常加手續費 NT$30–60 顯示於摘要「代收手續費」行）。
>      邏輯：COD 訂單付款狀態＝pending（`manual` gateway），出貨後由物流代收→對帳回寫 paid（16 號）」。
>      我方原本 F2 的 Result 結構（15:25）只有 subtotal／discount／shipping／tax／total **五個欄位，沒有代收手續費的落腳處**；
>      COD 上限 NT$20,000 已於 P0 輪進 `limits.pickup_point.cod_max_amount_twd`，但手續費行項仍缺。 -->

**(a) Result 結構新增一個獨立行項**（**不是**併進 shipping，也**不是**併進 total 後才算）：

```
Result = { subtotal, discount_allocations[], shipping_cents, cod_fee_cents, tax_cents, total_cents }
total_cents = subtotal - discount_total + shipping_cents + cod_fee_cents + tax_cents
```
- `cod_fee_cents` 只在 `payment_method = COD`（`manual` gateway，含超商取貨付款與宅配到府代收）時 > 0，其餘恆為 0。
- 費用來源：`shipping_rates.cod_fee_cents`（per 通路可設，`limits.cod.fee_cents_default_range` 記錄業界區間 3000–6000 供 UI 預設值提示，**不是硬約束**）。
- **integer cents、無捨入**；不參與任何折扣分攤（訂單級折扣的基數不含 COD 手續費）；**不可被免運折扣抵銷**（免運折扣只作用於 `shipping_cents`）。
- 是否課稅：**⚠ 待查證（來源未載明）**——代收手續費的稅務屬性台灣實務有兩種做法，官方文檔無載，暫定不課稅並標旗標 `limits.cod.fee_taxable`（見 §待查證 V-16）。

**(b) 結帳期硬驗證**（與 F3.1(c) 同一道 gate）：`total_cents`（含手續費）> `limits.pickup_point.cod_max_amount_twd`（NT$20,000）→ **隱藏 COD 選項並擋下提交**。
上限比較的基數是**顧客實際要付的代收金額**（含手續費），不是商品小計——用小計比較會讓 19,900 + 60 的單超出物流商上限而被退件。

**(c) 下游對帳**：COD 訂單成立時 `financial_status = PENDING`、`gateway = manual`；出貨後由物流代收，**對帳回寫 `paid` 的流程見 16-F4.4**。

## F3. Checkout 流程（one-page）

**生產級做法**：
1. 進入結帳 → 建 `checkouts` 列（token、line items **快照**、email、addresses、shipping 選擇、discount code、狀態 active）；URL `/checkouts/<token>`（簽名、不可枚舉）。
2. 表單體驗照 04 §1.2 欄位順序；每步 PATCH 更新 checkout + 即時重算（Calculator）右欄摘要。
3. shipping 選項：地址完整才計算（05 的 RateResolver）；**提交付款時 server 重驗**「所選 rate 仍屬於可用集合且價格一致」，不信任先前寫入。
4. 提交前 server 端全量重驗：商品仍 active、價格未變（變了 → 提示並刷新快照）、折扣仍有效、庫存粗檢（軟檢查，硬保證在 F5）。
5. email 正規化（downcase/trim）+ 格式驗證；地址國家白名單（demo：TW/US/HK/JP…可配置）。
6. 限流：每 IP 建 checkout 30/小時、折扣碼嘗試 10/分（防枚舉）。

**⚠️ 坑**：checkout 快照後商品改價 → 以快照價成交是行規（防買家頁面停留期間被漲價），但快照要有效期（24h 後重新快照）；後退鍵/多分頁重複提交 → F5 冪等鍵兜底；別把 checkout token 記進一般 log。

### F3.1 取貨點（超商取貨）的結帳 → admin 交接（P0-13）

> <!-- 依 44:322 補寫，原文：Shopify 後台「其他配送方式」三列＝`🚚 當地配送` / `🏠 到店取貨` / **`📍 取貨點`**（44 逐字標「這正是台灣超商取貨的對應概念；我們 42 號前台的超商取貨流程在 admin 側要對應此設定」）。
>      46b:551–552 佐證 `purchase.checkout.pickup-point-list.*` 與 `pickup-location-list.*`（到店取貨）是兩組不同的結帳擴充點 → pickup point 是獨立的第三種配送方式。
>      我方原本只有 42 §12.2 的前台流程，15/16/22/28 的 admin 與資料模型側完全空白 → 前台選了門市，後台無處存、無法出貨 -->

**(a) 配送方式三分法**（寫進 `checkouts.delivery_method_type` 與 `shipping_lines`）：`SHIPPING` / `LOCAL_PICKUP` / **`PICKUP_POINT`**。三者的結帳表單不同：`PICKUP_POINT` **隱藏收件地址表單**，只收「取件人姓名 ＋ 手機」（超商以手機號＋證件領件）。

**(b) 門市選擇的交接契約**（前台流程細節見 42 §12.2）：
1. 買家選超商通路 → 「選擇門市」按鈕（**未選前結帳鈕 disabled**，提示「請先選擇取貨門市」）。
2. 開啟物流商電子地圖 → 回拋 `CVSStoreID / CVSStoreName / CVSAddress / CVSTelephone / CVSOutSide`。
3. 回拋端點呼叫 **`checkoutPickupPointSet`**（28 §11）→ 寫入 `checkouts.pickup_point_*` **快照欄位**。
4. 訂單成立時，快照原樣複製到 `order_pickup_points`（**快照不是外鍵**——門市會關店，外鍵會斷）。

**(c) 結帳期硬驗證**（提交前 server 端重驗，與 F3.4 同一道 gate）：
- `delivery_method_type = PICKUP_POINT` 但 `pickup_point` 為空 → 擋下（`userErrors`）。
- COD（取貨付款）金額 > `limits.pickup_point.cod_max_amount_twd`（NT$20,000）→ **隱藏 COD 選項**並擋下。
- 購物車含超材積商品（三邊和 > 105cm 或 > 5kg）→ 購物車階段即擋「含大型商品不可超商取貨」。
- 外島門市（`CVSOutSide=1`）→ 依商家設定提示不可選或加天數。

**(d) 下游**：admin 側資料模型、出貨畫面差異、`READY_FOR_PICKUP` 事件與退貨「已送達」判定 → 見 **16-F3.3**；API 契約 → 見 **28 §11**。
**⚠ 待查證（來源未載明）**：Shopify 官方對 pickup point 的 admin 側是否有對應 GraphQL 型別、以及台灣各物流商的 COD／材積合約值——三方文檔皆未載明（V-11）。

### F3.2 結帳表單欄位配置與欄位聯動（P1-29／H-106）

> <!-- 依 46c:756–768、44:369–371 補寫，原文：結帳表單欄位三態（不顯示／選填／必填）；**「要求登入」⇒ 強制 email 通道**（兩欄位聯動）；
>      SMS 行銷同意**永不可預先勾選**；email 行銷同意**可依地區自動預勾**。
>      複核更正：50 號寫「15/19 號 spec 無 `checkout_field_config` 模型」——19-F4 其實已有「輕量開關走 `shops.settings` JSON ＋ 逐鍵 schema 驗證（settings key 註冊表）」的通用機制，
>      22:180 也明寫「checkout 欄位配置＝settings JSON（S19-F4 schema 驗證）」。真正缺的是①key 註冊表的實際條目 ②三條**聯動硬規則**。本節補這兩項。 -->

**(a) 欄位三態**（`limits.checkout.field_visibility_modes`）：`hidden` / `optional` / `required`。存放位置＝ 19-F4 的 `shops.settings` JSON，key 註冊表新增以下條目（型別皆為上述三態 enum，預設值取自 24 §5 實測）：
`checkout.field.company` / `.address2` / `.phone` / `.last_name`（`first_name` 恆 required，不可配置）。

**(b) 三條聯動硬規則（server-side 驗證，不是 UI 提示）**

| # | 規則 | 判定式 | 違反時 |
|---|---|---|---|
| L1 | **「要求登入」⇒ 強制 email 通道** | `settings["checkout.require_login"] == true` ⟹ `settings["checkout.contact_method"] == "email"` | `checkoutSettingsUpdate` 回 `userErrors`；**不可**只在前端灰化（`limits.checkout.require_login_forces_email_contact: true`） |
| L2 | **SMS 行銷同意永不可預先勾選** | `settings["checkout.sms_consent_prechecked"]` **不存在於 key 註冊表**——常數 `false`，連設定入口都不提供 | 任何寫入嘗試回 `userErrors`（`limits.checkout.sms_consent_never_prechecked: true`） |
| L3 | email 行銷同意**可**依地區自動預勾 | 依買家所在地區白名單決定預設勾選；白名單為商家可設 | — |

**(c) 為什麼 L1／L2 必須在 server 端**：兩者都是合規約束而非偏好——L2 若做成可設定的 toggle，商家開啟後即違反行銷同意法規；L1 若只在前端聯動，用 API 直接寫入就能繞過，產生「要求登入但沒有 email 通道」的無法完成結帳狀態。

## F4. Stripe 整合

**生產級做法**：
1. 建立 PaymentIntent：金額只取 Calculator 結果；`idempotency_key = "pi-#{checkout.token}-#{amount_cents}"`（金額變了 = 新 key，舊 PI cancel）；metadata 帶 checkout_token、shop_id。**呼叫在 transaction 外**。
2. 前端 Payment Element（自動處理 3DS/SCA）；`return_url = /checkouts/<token>/complete`。
3. **雙路徑完成，先到先贏、都冪等**：(a) buyer 回到 return_url → server 以 PI id 向 Stripe 查狀態；(b) webhook `payment_intent.succeeded`。兩路都呼叫 `Orders::CreateFromCheckout`（見 F5）。
4. webhook endpoint：驗簽（`Stripe::Webhook.construct_event`，容忍 5 分鐘時鐘偏差）、**立即 200 + 丟 job 處理**（Stripe 超時會重送）、以 event.id 去重表冪等。
5. 幣別：`stripe_amount()` helper 統一處理小數位（JPY 等零小數幣別不乘 100、個別幣別有整除規則）——**不准在業務代碼手寫 ×100**。
6. 退款：`Stripe::Refund.create(payment_intent:, amount:)` + 冪等 key = refund 內部 id；本地 transaction 列先建 pending、webhook `charge.refunded` 確認 success。
7. 金鑰：test/live 分開存 credentials；webhook secret 獨立；後台 Payments 設定頁顯示模式 badge（TEST 橘色橫幅，防真店誤跑測試模式）。

**⚠️ 坑**：
- **成功頁比 webhook 先到**（常態）：return_url handler 必須自己查 PI 並能建單，不能傻等 webhook；反之 webhook 也不能假設 buyer 有回來。
- 金額不一致攻擊：PI 建立後 buyer 改購物車再付 → PI 金額與 checkout 現值必須在建單時比對，不符 → 不建單、自動退款、告警。
- webhook handler 拋錯回 500 → Stripe 重送風暴：接收層永遠 200，錯誤在 job 裡處理與告警。
- 測試用 Stripe CLI 轉發 webhook（`stripe listen --forward-to`）；上生產前打開 Stripe Dashboard 的 webhook 失敗告警。

### F4.1 請款模式、授權效期與「逾期請款附加費」的處置（P1-06／P1-07）

> <!-- 依 46c:508–514、46c:516–527 補寫，原文：請款四模式表（結帳時自動〔預設〕／履行時自動／每次履行時自動〔僅 Plus〕／手動）；
>      授權效期表（Shopify Payments 預設 7 天；Plus 延長 Visa/MC/Amex 30 天、Discover/JCB 10 天、Diners/CUP 7 天）；
>      pending hold 最長顯示 30 天；逐字「超過授權期限後才請款，需付 1.75% 附加費」。 -->

**(a) 四模式的落地**：值域與 Plus 限定見 `limits.capture.modes` / `plus_only_modes`（P0-12 已定案，22 §8）。本節只補金流側行為：
- `automatic_per_fulfillment`（Plus 專屬）在 Stripe 上＝**同一 PaymentIntent 多次部分 capture**；Stripe 對此有金流商層級的支援差異，設定頁必須先探測 `payment_intent.capture_method` 能力再開放選項，**不是只看方案旗標**。
- 每次 capture 各自帶冪等鍵（`capture-{fulfillment_id}`），防重複請款。

**(b) 授權效期是 PSP／卡組織屬性，不是方案旗標**
`limits.capture.authorization_days_default`(7) 與 `authorization_days_plus`（30/10/7）**照抄自 46c 的 Shopify Payments 表**，在 CHILL LOVE 只作為 **UI 顯示與到期提醒 job 的預設值**（`expiry_warning_days_before: 2`）。
🔴 **實際上界由買家的 PSP（Stripe）與卡組織決定，不由商店方案決定**——實作時必須以 PaymentIntent 上的實際效期為準，`limits` 只是 fallback。把「Plus ⇒ 30 天」寫成硬邏輯會產生「系統說還能請款、Stripe 已經 declined」的錯誤狀態。

**(c) 🔻 逾期請款 1.75% 附加費：降級／不實作（P1-06 的處置）**
`46c:526` 的 1.75% 是 **Shopify Payments 對商家的收單定價**，不是任何一方可複製的業務規則。CHILL LOVE 依 **TW-9 電支條例鐵律**（37 §3、37 §479–491）**不代收代付、不是收單機構**，租戶貨款直接進租戶自持的 Stripe 商戶號——我方既不收這筆費用、也無權對租戶加收。
處置：`limits.capture.late_capture_surcharge_rate_informational_only`（鍵名即宣告用途）**不參與任何計算**，僅供「若未來自營收單」時的參考；22 §8 的敘述同步標註。**不得**在帳單或訂單金額引擎產生 1.75% 行項。
> 這是「本尊有、我方刻意不做」的一條，依 46a §6⑦-33 的先例明文標註，避免下一輪稽核把它當成遺漏重新開單。

## F5. 訂單成立（付款成功 → Order）

**生產級做法**（整條線最關鍵的一個 transaction）：
1. `Orders::CreateFromCheckout.call(checkout_token:, payment_intent_id:)`——**以 checkout 唯一鍵冪等**：orders 表 `checkout_id` 唯一索引，重入直接回傳既有訂單。
2. 單一 transaction 內：鎖 checkout（FOR UPDATE，狀態 active→completed 條件轉移）→ 逐行**條件式扣庫存**（13-F5：available−/committed+）→ 建 order + line_items（快照）+ transaction 列（kind=sale, gateway=stripe, 金額=PI 實收）→ 折扣 usage_count 原子 +1 → timeline event + outbox（orders/create、orders/paid）。
3. 庫存不足時的策略（寫進規格）：整單失敗 → transaction 回滾 → **自動全額退款 + 致歉頁 + 告警**（demo/初期最誠實的做法；超賣接受度是商業決策，預設不允許）。
4. 訂單編號：**每店連號** `shops.order_counter` 一欄，transaction 內 `UPDATE shops SET order_counter = order_counter + 1` 後讀回（同鎖序）；顯示為 `#{prefix}{counter}{suffix}`。
5. 成立後（transaction 外）：寄確認信 job、清 cart、棄單標記解除。

**⚠️ 坑**：
- 訂單號用全域自增 = **向所有租戶洩漏平台總量**（經典多租戶錯誤）→ 必須每店計數。
- counter 行鎖與庫存行鎖的順序全專案固定（先 shop counter 後 inventory），防死鎖。
- outbox 必須與訂單同 transaction（11 §8），寄信必須在 transaction 外（job）。
- PI 實收金額 vs Calculator 金額以 PI 為準入帳（來源真相是金流），不一致要標記 review。

## F6. Thank you / Order Status 頁

**生產級做法**：`/checkouts/<token>/complete`：訂單已建 → thank you（單號+摘要）；PI processing → 「處理中」頁自動輪詢（3s，最多 2 分鐘）；失敗 → 回結帳表單帶錯誤。order status 頁 `/orders/<signed_token>`（確認信連結），無登入可看但 token 簽名長效、不含 PII 於 URL 明文。

**⚠️ 坑**：輪詢頁要防搜尋引擎（noindex）與快取；status 頁顯示的地址等 PII——token 一旦洩漏即可看，額外做「email 後四碼驗證」的軟門檻（P1）。

## F7. 棄單（abandoned checkout）

**生產級做法**：checkout **留下 email 後 10 分鐘未完成** → 列入後台棄單列表（`limits.abandoned_checkout.qualify_after_minutes: 10`）；recovery URL = 簽名 token 恢復該 checkout；90 天 purge job（隱私保存期限）；自動挽回信：
1. **延遲四檔 `1 / 6 / 10 / 24` 小時，預設 10 小時**（官方在 UI 上標「建議」）——`limits.abandoned_checkout.recovery_delay_hour_options` / `recovery_delay_default_hours`。
2. **寄送對象二選一**：`任何未完成結帳的顧客` ／ `未完成結帳的電子郵件訂閱者`（`recovery_audience_options`）。
3. 每 checkout 只寄一次、內含退訂連結。

<!-- 依 44:373、24:228 修正，原文：後台「未完成結帳作業電子郵件」卡片實測——傳送對象 radio 兩選項；傳送時間 radio `1 小時`/`6 小時`/**`10 小時 (建議)`**/`24 小時`。
     棄單判定門檻見 22:60「留 email、≥10 分鐘」。
     🔴 此處原本寫錯：15:94 原寫「active 超過 1 小時 →（研究說 10 分鐘，demo 取 1 小時降噪）」——與官方及我方 22:60／24:228 三處門檻不一致，
     且四檔延遲與兩種對象完全未寫。已統一至 config/limits.yml。任何人翻舊版都不要改回 1 小時。 -->

**⚠️ 坑**：挽回信屬行銷邊緣——只寄給 marketing consent 或至少提供退訂（合規底線）；recovery 連結點開時商品可能已售罄/改價 → 重新驗證 + 明確提示，不能默默改金額。

## 本篇驗收（對照 11 §0）

併發 50 執行緒對同一 checkout 重複提交 → 恰好 1 張訂單；webhook 重放 10 次 → 冪等；成功頁先於 webhook 與相反順序都建單成功；金額引擎 property test 10k 隨機 case 三不變量成立；Stripe test 全卡種（成功/拒絕/3DS/餘額不足）走通；每店訂單連號無跳號（正常路徑）；棄單 90 天 purge 驗證；`transaction 內無外部 IO` 靜態掃描通過。
