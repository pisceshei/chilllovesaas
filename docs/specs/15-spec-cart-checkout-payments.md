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
