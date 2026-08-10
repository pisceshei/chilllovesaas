# 17 — 功能規格：折扣引擎（生產級）

> 覆蓋功能：折扣 CRUD、code/automatic、四類型、組合規則、用量限制、結帳求值。規格對照研究 01 §5，基線見 11。折扣是「金額正確性 × 併發 × 濫用防護」三線交匯點，坑最密。

## F1. 資料模型與 CRUD

**生產級做法**：
1. 單表多型：`discounts`（class: product/order/shipping；method: code/automatic；value_type: percentage/fixed；value；combines_with JSON {product:bool, order:bool, shipping:bool}；條件欄位：min_subtotal_cents/min_quantity、customer_eligibility、usage_limit、once_per_customer、starts_at/ends_at；BxGy 專屬條件 JSON）。
2. code 正規化：upcase + trim + 唯一索引 `(shop_id, code)`；產碼器排除易混字元（0/O、1/I/L）；status（scheduled/active/expired）**由時間欄位求值推導**，不落庫、不用 cron 翻牌（消滅時鐘競態）。
3. 適用範圍：products/collections 多對多（`discount_entitlements`），求值時展開為 variant id 集合（快取）。

**⚠️ 坑**：status 落庫 + cron 更新 = 到期瞬間的競態與時區 bug 溫床，推導制一勞永逸；fixed 金額有幣別語意（欄位帶 currency，跨幣別直接不適用——P2 Markets 前不會踩到，但 schema 先留）。

## F2. 結帳求值管線（Discounts::Engine）

**生產級做法**：
1. 求值順序固定：**product 類 → order 類 → shipping 類**（後級以前級折後價為基礎）——寫成 pipeline，每級輸出不可變中間結果。
2. 收集候選：automatic 全撈（≤25 active 的上限在存檔端限制）+ 輸入的 code（單一 code 起步；多 code P1）。
3. 過濾：時間窗、最低消費/件數（以**當前折後小計**判斷，語意寫進測試）、customer eligibility（登入/email 匹配 + segment）、usage_limit 預檢（軟檢，硬保證在 F3）。
4. 組合裁決：依 combines_with **雙向同意**建立可共存集合；不可共存時**取買家利益最大**組合（best discount wins；同 line 重疊比較「該行折讓金額」）。
5. 分攤：每個生效折扣產生 `discount_applications`（target、金額、行級 allocations——15-F2 最大餘數法）；shipping 折扣單獨作用於運費項。
6. Engine 輸出進 Calculator 的 Result，checkout 摘要與訂單快照都引用 applications（退款要用，16-F5）。

**代碼**：

```ruby
class Discounts::Engine
  def apply(ctx) # ctx: lines, subtotal, code, customer, shipping
    cands = candidates(ctx)                       # automatic + code，過時間窗
    eligible = cands.select { |d| meets_conditions?(d, ctx) }
    chosen = resolve_combinations(eligible)       # combinesWith 矩陣 + best-wins
    chosen.each_with_object(Applications.new) do |d, apps|
      apps << allocate(d, ctx)                    # 行級分攤（最大餘數法）
      ctx = ctx.after(apps.last)                  # 後級以折後價續算
    end
  end
end
```

**⚠️ 坑**：
- 「最低消費」判定基準（折前 or 折後）必須定死並測試——本尊語意：order 級門檻看**套用 product 折扣後**的小計。
- 百分比疊加不是相加（20%+10% = 72 折不是 7 折）——pipeline 序列計算天然正確，別寫成累加百分比。
- BxGy 的「得」件免費仍佔庫存、仍出現在行項（金額 0 + application 標記）；「買」與「得」同商品時的循環判定：一件商品不能同時當 buys 與 gets 計數（集合分割先 buys 後 gets）。
- 折扣絕不能把行金額打到負數；每級後斷言 `line_total >= 0`。
- gift card 商品行排除在一切折扣外（13-F1 的 isGiftCard 旗標）。

## F3. 用量限制與併發

**生產級做法**：
1. `usage_limit` 硬保證：訂單成立 transaction 內（15-F5）`UPDATE discounts SET usage_count = usage_count + 1 WHERE id = ? AND (usage_limit IS NULL OR usage_count < usage_limit)`——affected 0 → 折扣失效 → 整單重算或失敗回結帳（明確報「折扣已被用完」）。
2. `once_per_customer`：`discount_redemptions(discount_id, customer_key)` 唯一索引（customer_key = customer_id 或 email hash），insert 失敗 = 已用過。
3. 求值期（F2）只做軟檢（UX 提前提示），**成立期的原子操作才是真相**——兩段式明確分工。
4. 取消/整單退款是否返還用量：預設不返還（防刷），做成折扣層設定（P1）。

**⚠️ 坑**：只在求值期檢查 = 高併發下超發（經典事故）；redemption 的 email hash 要正規化後再 hash（大小寫繞過）；usage_count 顯示用，對帳以 redemptions/applications 聚合為準（nightly 對帳同 13-F5 精神）。

## F4. 濫用防護與後台體驗

**生產級做法**：
1. 結帳輸入 code 限流：每 checkout 10 次/分、每 IP 30 次/分（防枚舉爬碼）；錯誤文案統一「折扣碼無效或不適用」（不區分不存在/過期/不符條件——**枚舉防護優先於 UX 精確**，這點刻意與本尊取捨不同並記錄原因）。
2. 產碼批量（P1）：一次生成 N 個一次性碼（行銷用）走 job + 唯一索引忽略衝突重試。
3. 後台列表：Used 欄顯示 `usage_count/limit`；詳情頁 performance 區（applications 聚合：使用次數、折讓總額、帶動營收）。
4. 刪除：有 applications 的折扣不可硬刪 → 停用（ends_at = now）。

**⚠️ 坑**：批量產碼直接同步生成 10 萬筆會卡死請求——job 化；折讓總額報表要從 applications 算（快照），不能從現行折扣設定反推（設定會被改）。

## 本篇驗收（對照 11 §0）

組合矩陣測試表（product/order/shipping × code/automatic 全組合）全綠；100 執行緒搶 usage_limit=10 的碼恰好 10 單成立；once_per_customer 大小寫/加點 gmail 變體繞不過；BxGy 庫存佔用正確；退款按 applications 分攤誤差 0；枚舉腳本跑 1000 碼被限流擋下；折後行金額永不為負（property test）。
