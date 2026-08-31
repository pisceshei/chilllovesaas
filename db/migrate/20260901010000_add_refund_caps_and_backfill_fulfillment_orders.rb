# frozen_string_literal: true

# G6-8（步 5）：退款軟上限的物化欄 ＋ fulfillment_orders 回填。
#
# ①`orders.captured_total_cents`／`refunded_total_cents`：16 §F5.1 條件式 UPDATE 的
#   載體（`limits.refund.cumulative_cap_column` 正典宣告已存在、欄位至今未建——
#   本支補齊）。軟上限＝應用層條件式 UPDATE，**不加 DB CHECK**（16 §F5.1(e)：
#   CHECK 會擋掉 46c:223 明載的合法超額退款）；唯一硬約束是兩欄 >= 0（應用層驗證）。
# ②fulfillment_orders 回填：本尊訂單一成立就有 FulfillmentOrder（ord-2 §1.1 官方句
#   "Fulfillment orders represent the work which is intended to be done in relation to
#   an order."）；我方 G6-0 建單時未物化 ⇒ 本支補回填，CreateFromCheckout 同批改為
#   建單即建 FO。v1＝每單一張 FO（單地點形）。
class AddRefundCapsAndBackfillFulfillmentOrders < ActiveRecord::Migration[8.1]
  def up
    # 防重入：DDL 在 MySQL 隱式提交，migration 中途失敗重跑會撞 duplicate column
    #（本支第一版實踩：strong_migrations 擋 execute 時兩欄已加上）。
    unless column_exists?(:orders, :captured_total_cents)
      add_column :orders, :captured_total_cents, :bigint, null: false, default: 0,
        comment: "Σ success 的 sale/capture 交易額（16 F5.1 軟上限的分母；nightly 與明細對帳）"
    end
    unless column_exists?(:orders, :refunded_total_cents)
      add_column :orders, :refunded_total_cents, :bigint, null: false, default: 0,
        comment: "Σ 已退金額（16 F5.1 條件式 UPDATE 的累計欄；不加 DB CHECK——軟上限）"
    end

    # safety_assured：strong_migrations 對 execute 一律報 unsafe；此處為一次性回填
    # （冪等：totals 依明細重算、FO 回填帶 NOT EXISTS），非 schema 變更。
    safety_assured do
      backfill_captured_totals!
      backfill_fulfillment_orders!
    end
  end

  def down
    remove_column :orders, :captured_total_cents
    remove_column :orders, :refunded_total_cents
    # FO 回填不反向刪除：down 只還原 schema，資料列留存（與第 12 包回填同紀律——
    # 反向刪列會把 up 之後正常業務建立的列一起殺掉，無法區分）。
  end

  # captured_total_cents 回填＝Σ success 的 sale/capture 交易（16 §F4.3 聚合推導的
  # 物化快照）。refunded_total_cents 既有庫存量＝0（refund 交易 kind 在 v1 尚無
  # 生產寫入者），仍照公式回填以防移轉庫有手工資料。
  def backfill_captured_totals!
    execute <<~SQL.squish
      UPDATE orders o
        SET o.captured_total_cents = COALESCE((
              SELECT SUM(t.amount_cents) FROM order_transactions t
               WHERE t.shop_id = o.shop_id AND t.order_id = o.id
                 AND t.kind IN ('sale', 'capture') AND t.status = 'success'), 0),
            o.refunded_total_cents = COALESCE((
              SELECT SUM(t.amount_cents) FROM order_transactions t
               WHERE t.shop_id = o.shop_id AND t.order_id = o.id
                 AND t.kind = 'refund' AND t.status = 'success'), 0)
    SQL
  end

  # 每張既有訂單補一張 FO：location＝該店 priority 最高（同 CreateFromCheckout 的
  # level 選擇規則）；已全出貨的單 status=closed、其餘 open。
  # 冪等：已有 FO 的訂單跳過（NOT EXISTS）。
  def backfill_fulfillment_orders!
    execute <<~SQL.squish
      INSERT INTO fulfillment_orders
        (shop_id, order_id, location_id, status, request_status, created_at, updated_at)
      SELECT o.shop_id, o.id,
             (SELECT l.id FROM locations l WHERE l.shop_id = o.shop_id
               ORDER BY l.priority DESC, l.id ASC LIMIT 1),
             CASE WHEN o.fulfillment_status = 'fulfilled' THEN 'closed' ELSE 'open' END,
             'unsubmitted', NOW(6), NOW(6)
        FROM orders o
       WHERE EXISTS (SELECT 1 FROM locations l2 WHERE l2.shop_id = o.shop_id)
         AND NOT EXISTS (SELECT 1 FROM fulfillment_orders fo
                          WHERE fo.shop_id = o.shop_id AND fo.order_id = o.id)
    SQL
  end
end
