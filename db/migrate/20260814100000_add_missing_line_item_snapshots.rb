# 補齊 line_items 的商品快照欄（裁定 84 §1 A-3／71-R11-V7；契約全文＝docs/specs/87）。
#
# 為什麼現在做：`line_items` 的表註釋本來就寫著「下單當下不可回溯改寫的商品與金額快照」，
# 意圖是對的，但**只做了本尊 5 個快照維度裡的 3 個**：
#   ✓ title（售出時的產品名稱）／variant_title（售出時的子類選項名稱）／sku（售出時的子類選項 SKU）
#   ✗ vendor（售出時的產品廠商）／product_type（售出時的產品類型）
#
# 🔴 這是 84 號分流裡**唯一「錯過就永久遺失資料」**的一條：商品的 vendor 與 type 隨時可被編輯，
# 沒在下單當下存下來，事後 join 回去拿到的是**改過之後的值**，歷史報表會失真。
# help 明載本尊 2024 改版後分析預設用**當前值**，要貼近歷史必須改用「售出時的」那組欄位——
# 那組欄位存在的前提就是下單時有存。
#
# 為什麼是 nullable：M0 既有列（若有）補不出正確的歷史值，**寧可留 NULL 表示「不知道」，
# 也不要用當前值回填假裝知道**——回填會製造看起來正確、實際錯誤的歷史資料。
class AddMissingLineItemSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :line_items, :vendor, :string,
      comment: "售出時的產品廠商（快照，不隨商品編輯而變）"
    add_column :line_items, :product_type, :string,
      comment: "售出時的產品類型（快照，不隨商品編輯而變）"
  end
end
