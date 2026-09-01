# G6 步 9a：折扣引擎核心（Engine＋Calculator 管線＋用量硬保證）

> 規格正典＝`docs/specs/17-spec-discounts-engine.md`（F2.1 官方修正版：order 級
> **同基數不複利**）。API/admin/前台 UI＝步 9b。

## 1. 分工（鐵律 7）

- **Engine（`app/services/discounts/engine.rb`）＝解析半場**：讀 DB（automatic 候選
  ／code 查找／條件／組合裁決）→ 產純資料清單。**不算錢。**
- **Calculator（`discounts:` 新參數）＝金額半場**：F2.1 全數學（product→order→
  shipping 管線；order 級同基數逐筆 floor＋鉗制 ≤S₀；最大餘數分攤；先折後稅）。
  legacy `discount:` 參數原樣保留（互斥檢查）；既有 checkout 測試零改動全綠。
- 表＝M0 既有 discounts／discount_applications 採用＋新 discount_redemptions
  ＋checkouts.discount_code/discount_applications_snapshot。

## 2. 關鍵語義（突變紅證逐條）

- **F2.1 同基數**：10%+20% 於 S₀=100000 ⇒ 折 30000（複利 28000＝MD1 紅）；
  可交換律 property（20 隨機排列）；60%+60% 鉗到付 0（MD2）。
- **跨級序列**：order 基數＝product 折後小計（MD3）。
- **組合＝雙向同意**（MD4）；**shipping 疊 shipping＝引擎硬規則**——model 驗證
  （shipping 類禁 combines_shipping，官方 combinesWith 無此旗標）之上的縱深防禦
  （E5 用 update_all 打穿旗標層單測；MD5）。
- **枚舉防護**：碼不存在/過期/停用/不符條件**同一句**「折扣碼無效或不適用」
  （17-F4.1 刻意取捨；MD6）。
- **F3 用量硬保證**：成單交易內條件式 UPDATE（`times_used < usage_limit` 進
  WHERE；affected 0 ⇒ 整單 rollback；MD7）；once_per_customer＝redemptions 唯一
  索引（email **正規化後 hash**——大小寫變體繞不過；MD8）；applications 快照
  回放成列（退款 16-F5 與報表讀它；MD9）。
- status 推導制：DB status＝商家生命週期（draft/active/archived）；
  scheduled/expired 由時間欄求值（`effective_status`）——不落庫不 cron（17-F1.2）。

## 3. 求值流

結帳 delivery 步 recompute（checkouts_controller）→ Engine.evaluate（code 從
checkouts.discount_code）→ Calculator（discounts:）→ checkout 落
discount_cents＋discount_applications_snapshot → 成單（CreateFromCheckout
`claim_discounts!`）：條件式 UPDATE＋redemption＋applications 列。
求值期＝軟檢（UX），成立期原子操作＝真相（17-F3.3 兩段式）。

## 4. v1 邊界（91 §3.54）

entitlements 走 conditions.entitled_variant_ids（正規化表 ⚪）；BxGy／多 code／
批量產碼／limits 全鍵消費 ⚪；min_subtotal 判定基準 v1＝原始小計（product 折扣
疊加場景的官方「product 折後」分層隨 entitlements 展開）；併發實測＝條件式
UPDATE 同 refunds C1 序列化先例（threads 實跑 ⚪）。
