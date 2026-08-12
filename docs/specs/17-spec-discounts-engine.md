# 17 — 功能規格：折扣引擎（生產級）

> 覆蓋功能：折扣 CRUD、code/automatic、四類型、組合規則、用量限制、結帳求值。規格對照研究 01 §5，基線見 11。折扣是「金額正確性 × 併發 × 濫用防護」三線交匯點，坑最密。

## F1. 資料模型與 CRUD

**生產級做法**：
1. 單表多型：`discounts`（class: product/order/shipping；method: code/automatic；value_type: percentage/fixed；value；combines_with JSON {product:bool, order:bool, shipping:bool}；條件欄位：min_subtotal_cents/min_quantity、customer_eligibility、usage_limit、once_per_customer、starts_at/ends_at；BxGy 專屬條件 JSON）。
2. code 正規化：upcase + trim + 唯一索引 `(shop_id, code)`；產碼器排除易混字元（0/O、1/I/L）；status（scheduled/active/expired）**由時間欄位求值推導**，不落庫、不用 cron 翻牌（消滅時鐘競態）。
3. 適用範圍：products/collections 多對多（`discount_entitlements`），求值時展開為 variant id 集合（快取）。

4. **`combines_with` 三旗標不是對稱的**——按 discount class 有兩條 schema 級約束（P1-01／H-41、H-42）：
   - **class = `shipping` 的折扣：`combines_with.shipping` 欄位不存在**（不是 false，是**不提供**）。免運折扣的 `combinesWith` 官方**只有 `orderDiscounts` / `productDiscounts` 兩個旗標**。
   - **引擎級硬規則：運費折扣不可疊運費折扣**——由 F2 的引擎強制，**不由旗標控制**（`limits.discount.shipping_plus_shipping_allowed: false`）。
   - 落地：`discount_combines_with` 子表以 `(discount_id, target_class)` 為唯一鍵，**寫入 `(shipping 類折扣, shipping)` 這組即回 `INVALID_COMBINES_WITH_FOR_DISCOUNT_CLASS`**（46b:344 的官方錯誤碼）。做成對稱三旗欄位就會允許非法組合。
   <!-- 依 46b:197、46b:285、46b:374、46c:716 修正，原文：「免運折扣的 combinesWith 只有 order/product 兩個旗標（無 shippingDiscounts）」＋「Multiple shipping discounts can't apply to the same order.」（硬規則，非 combinesWith 旗標可控）。
        原文（我方）：17:8 原本寫 `combines_with JSON {product:bool, order:bool, shipping:bool}` **三旗標一律對稱**——照此實作即可疊兩張運費折扣。
        P0 輪已在 17-F2 寫了引擎級硬規則，但**資料模型這一層仍是對稱三旗標**，本輪補上 schema 級約束。 -->

**⚠️ 坑**：status 落庫 + cron 更新 = 到期瞬間的競態與時區 bug 溫床，推導制一勞永逸；fixed 金額有幣別語意（欄位帶 currency，跨幣別直接不適用——P2 Markets 前不會踩到，但 schema 先留）；`combines_with` 做成對稱三旗標是 H-41／H-42 的直接成因——**旗標集合依 class 而異**。

## F2. 結帳求值管線（Discounts::Engine）

**生產級做法**：
1. 求值順序固定：**product 類 → order 類 → shipping 類**（後級以前級折後價為基礎）——寫成 pipeline，每級輸出不可變中間結果。
   **但同一級之內（尤其 order 級）的多個折扣一律共用同一個基數，不得互相串接**——見 F2.1。
   **運費折扣在「配送選項生成之後」才作用**（官方 7 步中的第 5 步，第 4 步才產生配送選項）→「滿額免運」這類跨階段規則必須在選項生成後求值，否則會算錯。
   🔴 **「配送選項生成」包含 15-F2.1 的跨設定檔合併**——運費折扣打在**合併後**的單一金額上。若對每個運送設定檔的費率各自先套免運折扣再合併，免運會被套用 N 次，金額直接錯（NP1-E，本輪新發現）。
   <!-- 依 46b:38–50、46b:134 補寫，原文：結帳 Function 7 步執行順序 Cart Transform → 商品/訂單折扣 → 履行約束+路由 → 配送客製 → **運費折扣** → 付款客製 → 驗證；我方 17:18 原本只寫 product → order → shipping，缺「運費折扣在配送選項生成之後」這一層 -->
   **硬規則：運費折扣不可疊運費折扣**（`limits.discount.shipping_plus_shipping_allowed: false`）——這**不是** `combines_with` 旗標可控的，是引擎級硬約束；免運折扣的 `combinesWith` **只有 order／product 兩個旗標**（無 shippingDiscounts）。
   <!-- 依 46b:197、46b:285、46b:374、46c:716 補寫，原文：「Multiple shipping discounts can't apply to the same order.」；我方 17:8 的三旗標對稱模型若照實作即可疊兩張運費折扣 -->
   `combines_with` 三旗標**預設值全 false**（46c:705：組合不會自動發生，商家須逐折扣開啟）。
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

### F2.1 訂單級多個百分比折扣的基數（P0-03，金額正確性）

> <!-- 依 46b:284、46c:720 修正，原文（三方一致）：
>      46b:284 逐字「both percentages are calculated on the **original subtotal**」（10% + 20% = 30%，**非**複利 28%）；
>      46c:720（H28 zh-TW）逐字「各折扣的百分比皆以**原始小計**計算」。
>      🔴 此處原本寫錯：17:42 原寫「百分比疊加不是相加（20%+10% = 72 折不是 7 折）——pipeline 序列計算天然正確，別寫成累加百分比」。
>      這與官方三方一致的結論**直接相反**，且與我方自己的 22:105 自相矛盾。任何人翻舊版看到「72 折」都不要改回去。 -->

**定義**：令 `S₀` ＝ **order 級折扣開始求值時的基數** ＝「套用完 product 級折扣後的小計」（此點不變，46c:720 逐字「訂單折扣會在商品折扣之後，套用至調整後的小計」）。

```
# order 級的 N 個百分比折扣 d₁..dₙ（bp = basis points，0–10000 整數）
# 🔴 全部以同一個 S₀ 為基數，彼此不串接（不複利）
order_discount[k]   = floor( S₀ * bp[k] / 10000 )         # 逐筆 floor 到分
order_discount_total= min( Σ_k order_discount[k], S₀ )     # 合計不得超過基數（不可為負）
subtotal_after_order= S₀ - order_discount_total
```

**算例（S₀ = 100000 cents，即 NT$1,000）**

| 折扣組合 | ✅ 正確（官方：各以原始小計計） | ❌ 修正前的錯誤做法（序列複利） | 差額 |
|---|---|---|---|
| 10% ＋ 20% | `10000 + 20000 = 30000` → 付 **70000** | `100000×0.9×0.8 = 72000` → 付 72000 | **少折 2000（NT$20）** |
| 20% ＋ 10% | 同上 **30000**（**順序無關**，可交換） | `100000×0.8×0.9 = 72000` | 同上 |
| 60% ＋ 60% | `60000+60000 = 120000` → `min(120000, 100000) = 100000` → 付 **0** | `100000×0.4×0.4 = 16000` | 鉗制生效，行金額不為負 |

**必測性質**：
1. **可交換律**：任意排列 order 級折扣，結果金額完全相同（property test）。
2. **product 級仍序列**：product → order → shipping 的**跨級**關係不變（order 級基數是 product 折後小計）。
3. **鉗制**：`order_discount_total ≤ S₀`，且每行分攤後 `line_total ≥ 0`。
4. 百分比一律以 **basis points 整數**運算，逐筆 `floor` 後再加總（**不是**先加總百分比再算一次——先加總會在 `Σbp > 10000` 時失去鉗制點）。
5. 行級分攤仍走 15-F2 的**最大餘數法**，`Σ 行分攤 == order_discount_total`。

**值域**：折扣 `percentage` 在 API 線上格式為 **0–1 的 Float**（不是 0–100）；內部一律存 basis points，序列化除以 10000。
<!-- 依 46b:189、46b:272 補寫，原文：percentage 值域 0–1 Float；46b §2⑥-2 建議存 basis points、序列化除 10000 → 不寫會有 100 倍誤差風險 -->

**⚠️ 坑**：
- 「最低消費」判定基準（折前 or 折後）必須定死並測試——本尊語意：order 級門檻看**套用 product 折扣後**的小計。
- **同一級（order 級）的多個百分比折扣一律以同一基數相加，不得序列複利**——見 F2.1（此處原本寫反）。
- 單次結帳可用 **5 個 product/order 碼 ＋ 1 個運費碼**（`limits.discount.max_codes_per_checkout_*`）——F2 收集候選階段的「單一 code 起步」與此不一致，多 code 支援提前到 M4。
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

**本次新增（P0-03 修正對應）**：
- **F2.1 算例逐一斷言**：S₀=100000 時「10%＋20%」必須折 30000（不是 28000）。
- **可交換律 property test**：order 級折扣任意排列結果相同。
- **鉗制**：`Σ order 折扣 ≤ S₀`；60%＋60% 收斂到付 0 而非負數。
- **運費折扣不可疊運費折扣**：兩張 shipping 折扣同時符合條件時只取一張（且不是靠 `combines_with` 旗標）。
- **`combines_with` 預設全 false**：新建折扣未手動開啟組合時不與任何折扣共存。
