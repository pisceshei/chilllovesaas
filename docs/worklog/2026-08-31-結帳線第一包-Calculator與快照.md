# 2026-08-31 結帳線第一包：Checkouts::Calculator＋cart→checkout 快照

## 已完成的工作 (Done)

- **`Checkouts::Calculator`**（15 F2；🔴 命名對映：規格名 `Checkout::Calculator`——
  `Checkout` 已是 AR model 類，module/class 同名不能並存 ⇒ 服務命名空間取複數
  `Checkouts::`（倉內 `UrlRedirects::`／`Translations::` 同慣例），功能契約不變）：
  - 純函式 PORO：行快照／運費／折扣／稅 → 不可變 Result，**全程 integer cents**；
    🔴 任何 Float（單價／運費／固定折扣／稅率）⇒ TypeError（F2 坑 1；比率用 Rational/BigDecimal）。
  - 分攤（F2-3）：**最大餘數法**、確定性排序（餘數大→行金額大→行序）；
    `Σ行分攤 = 折扣總額` 恆等；折扣 > 小計 ⇒ 收斂到小計（總計非負）。
  - 稅（F2-4）：未稅＝行級 `round(taxable×rate)` 加總；含稅＝行級反推
    `taxable − round(taxable/(1+rate))` 加總——**行級進位全域一致**（退款查行級分攤
    不重算的前提）。課稅基礎＝先折後稅。運費 v1 不課稅（HK 基準無銷售稅；法域 pack
    接上時由呼叫端供運費稅——登記）。
  - 無任何 DB 讀取（快照進 Result 出）＝「設定變更不回溯」結構性成立（F2 坑 3）。
- **`Checkouts::CreateFromCart`＋`Checkout` model**（15 F1 #3／F3；M0 空表的第一個
  消費者）：進入結帳**重新快照即時價**（cart 行的 unit_price_cents 是合併鍵快照，
  不是結帳價）；🔴 **不扣庫存**（訂單成立事件才扣——F5）；token／recovery_token
  雙鑰（挽回信外洩 ≠ 結帳被接管）；金額欄全由 Calculator Result 填。
- **端點**：POST /checkout（裸＋帶前綴；空車回 /cart）⇒ 303 /checkouts/<token>；
  GET /checkouts/:token＝v1 佔位摘要頁（非主題化、noindex；金額字串走 Money::Display
  同一 cents——鐵律 7）；跨店 token 404（host 租戶隔離）。限流併入 storefront-cart/ip。

## 修改的檔案與核心邏輯 (Changes)

- `app/services/checkouts/{calculator,create_from_cart}.rb`、`app/models/checkout.rb`（新）
- `app/controllers/storefront/checkouts_controller.rb`（新）；`config/routes.rb`；
  `config/initializers/rack_attack.rb`（/checkout 入 cart throttle）
- specs：`spec/services/checkouts/calculator_spec.rb`（**44 組表格**＋property 200 組
  ＋型別閘＋輸入驗證＋frozen——50 例）；`spec/requests/storefront_checkout_spec.rb`
  （C1–C5）。表格期望值**全部手算**（非跑碼回填；質數組首算錯誤在跑前以手算複核抓出）。

**突變驗證（20.2⑤／20.3）**：
| # | 突變 | 預期紅 | 結果 |
|---|---|---|---|
| MUT-c1 | 分攤拿掉餘數修補 | Σ恆等格＋property | 5 failures ✅ |
| MUT-c2 | 折扣上限拿掉 | 折扣>小計格＋property 非負 | 3 failures ✅ |
| MUT-c3 | 含稅行級反推砍除 | 含稅格群 | 7 failures ✅ |
| MUT-c4 | Float 靜默轉整 | T-float | 1 failure ✅ |
| MUT-c5 | 快照抄 cart 價 | C2 | 1 failure ✅ |

## 尚未完成或需注意的風險 (Pending / TODO)

- **F2.1 合併運費（ShippingRateMerger）**：運送設定檔／zone／費率表未建——Calculator
  收「已選運費 cents」；費率解析與合併鍵（名稱相同相加、相異取最便宜相加）＝運送包。
- **折扣碼接線**：Calculator 收折扣定義；discount codes 資料面（M4 折扣線）接上時
  只換輸入來源。行級折扣／多重折扣疊加不在 v1 值域（F2-3 是訂單級）。
- **F3 one-page UI／地址／email／F4 Stripe／F5 訂單成立／F7 棄單挽回**＝後續結帳包；
  checkouts.expires_at／abandoned_at 無寫入者（棄單判定 10 分鐘規則在 limits 既有）。
- 結帳頁 v1 佔位不吃主題（本尊同形——checkout 非主題化）；presentment 雙欄與店幣同值
  （多幣別隨 markets 幣別包）。
- 🔴 訂單成立時**必須**沿用同一 Result（四處重用）——訂單包不得自算總計。
- Shop#destroy 未掛 checkouts 清理（空店刪除不受影響——無 FK；掛 dependent 隨訂單線）。
