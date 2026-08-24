# frozen_string_literal: true

# 庫存 ledger 形狀總裁定的落地（docs/plans/2026-08-24-庫存ledger形狀總裁定.md §三）。
#
# 三件事：
#   ① 新表 `inventory_adjustment_groups`（＝本尊 InventoryAdjustmentGroup）：一次呼叫＝一把
#      idempotencyKey＝一列 group＝N 列 ledger 子行。呼叫層欄位（reason／參考文件／actor）在這裡。
#   ② `inventory_adjustments` 改為 group 的子行：一列＝該 group 對某個 inventory_level 的
#      全部 delta（六個 leaf 實體欄）。`unavailable_delta`／`on_hand_delta` 改 STORED GENERATED
#      ——衍生量永不落庫，想雙寫也寫不進去（機制，不是紀律）。
#   ③ `inventory_levels` 補四個 leaf 實體欄；`unavailable`／`on_hand` 同樣改 STORED GENERATED。
#      本尊恆等式（機器可讀）：on_hand.comprises = [available, committed, damaged,
#      quality_control, reserved, safety_stock]，**不含 incoming**（docs/research/95 §2）。
#
# 🔴 兩個 generated 各自**直接引用基礎欄**，不寫成「available + committed + unavailable」——
#    generated 引用 generated 有定義順序相依，且兩式各自獨立才能各自驗證。
# 🔴 選 STORED 不選 VIRTUAL：列表排序與低庫存查詢要建索引（(shop_id, on_hand) 等），
#    VIRTUAL 在部分路徑建不了索引且每讀重算。
# 🔴 idempotency_key 從 ledger 行**整欄移除**：它留在行上就是第二套平行冪等
#    （與 idempotency_keys 表無外鍵、TTL 語義相反），且一把鍵對 N 筆子行時第 2 筆直接撞唯一鍵
#    ——這是「每一次多筆調整都必然失敗」的根源（總裁定 §二-2）。
#
# 安全性：三張表在本機與 bt3 生產皆為 0 列（2026-08-24 兩端實查），
# 所有 remove/add 皆無資料負擔 ⇒ safety_assured 的理由是「空表」，不是「趕時間」。
class ReshapeInventoryLedger < ActiveRecord::Migration[8.1]
  def up
    create_table :inventory_adjustment_groups,
                 comment: "一次庫存異動呼叫的批次頭（＝本尊 InventoryAdjustmentGroup）" do |t|
      t.bigint  :shop_id, null: false
      # 冪等鍵在批次頭，不在子行。@idempotent 對齊：本尊 2026-04 起強制（95 §4）；
      # 我方 GraphQL 契約層 String! 加嚴＝71 §A G28（使用者 2026-08-24 裁定）。
      t.string  :idempotency_key, null: false, limit: 255
      # 呼叫層的目標數量名（inventorySetQuantities 只收 available|on_hand；adjust 收 leaf）。
      t.string  :quantity_name, null: false, limit: 32
      # 17 值全集＝limits.inventory.adjustment_reasons（95 §3）；驗證在服務層（M1 第 16 包）。
      t.string  :reason, null: false, limit: 64
      # 哪支 mutation 進來的（adjust|move|set|activate）——稽核欄，與 reason 正交。
      t.string  :mutation_kind, null: false, limit: 16
      # parity：答「為什麼動」；純稽核、不去重（本尊文檔零 dedup 語義，95 §4）。
      t.string  :reference_document_uri, limit: 255
      # ours：內部來源多型（訂單／轉移／匯入……）；本尊只有 URI，我方加結構化引用便於 join。
      t.string  :reference_type, limit: 64
      t.bigint  :reference_id
      # actor 兩欄分開、不用多型：本尊 group 上 staffMember 與 app 是兩個欄位、可同時存在。
      # 🔴 staff_members 依鐵律 2 白名單無 shop_id ⇒ 不建複合租戶 FK，只建索引。
      t.bigint  :staff_member_id
      # app 欄位的過渡承載（admin_web／api／import…）；M5 apps 落地後補 app_id（V-96.2）。
      t.string  :client_source, limit: 32
      # 快取欄：GraphQL 分頁計數來源；Reconcile 八式之一驗它（總裁定 §四-2）。
      t.integer :changes_count, null: false, default: 0
      t.timestamps

      t.index %i[shop_id id],              unique: true, name: "uq_inventory_adjustment_groups_tenant_id"
      t.index %i[shop_id idempotency_key], unique: true, name: "uq_inventory_adjustment_groups_idem_key"
      t.index %i[shop_id reference_type reference_id], name: "ix_inventory_adjustment_groups_reference"
      t.index %i[shop_id created_at],      name: "ix_inventory_adjustment_groups_created_at"
      t.index %i[shop_id staff_member_id], name: "ix_inventory_adjustment_groups_staff"
      t.foreign_key :shops, name: "fk_inventory_adjustment_groups_shop"
    end

    safety_assured do
      change_table :inventory_adjustments, bulk: true do |t|
        # 舊唯一鍵（一把鍵一列）與呼叫層欄位（已上移 group）一併移除。
        t.remove_index name: "uq_inventory_adjustments_idempotency_key"
        t.remove_index name: "ix_inventory_adjustments_reference_type_reference_id"
        t.remove :idempotency_key, :reason, :reference_type, :reference_id
        # 衍生量的實體欄移除，稍後以 STORED GENERATED 重建同名欄。
        t.remove :on_hand_delta, :unavailable_delta

        t.bigint  :inventory_adjustment_group_id, null: false
        t.integer :reserved_delta,        null: false, default: 0
        t.integer :damaged_delta,         null: false, default: 0
        t.integer :safety_stock_delta,    null: false, default: 0
        t.integer :quality_control_delta, null: false, default: 0
        # per-change 稽核（除 available 外必填、禁 gid://shopify/*——驗證在服務層，95 §4）。
        t.string  :ledger_document_uri, limit: 255
        # group 內順序：API changes[] 的排序來源（冪等指紋對順序敏感）。
        t.integer :position, null: false, default: 0
      end

      change_table :inventory_adjustments, bulk: true do |t|
        t.virtual :unavailable_delta, type: :integer, stored: true, null: false,
                  as: "reserved_delta + damaged_delta + safety_stock_delta + quality_control_delta"
        t.virtual :on_hand_delta, type: :integer, stored: true, null: false,
                  as: "available_delta + committed_delta + reserved_delta + damaged_delta + safety_stock_delta + quality_control_delta"
        # 一列＝一個 (group, level)。同呼叫重複 (item, location) ⇒ 服務層 reject（V-96.1 fail-closed）。
        t.index %i[shop_id inventory_adjustment_group_id inventory_level_id],
                unique: true, name: "uq_inv_adjustments_group_level"
      end

      add_foreign_key :inventory_adjustments, :inventory_adjustment_groups,
                      column: %i[shop_id inventory_adjustment_group_id],
                      primary_key: %i[shop_id id],
                      name: "fk_inventory_adjustments_group_id"

      change_table :inventory_levels, bulk: true do |t|
        t.remove :on_hand, :unavailable
        t.integer :reserved,        null: false, default: 0
        t.integer :damaged,         null: false, default: 0
        t.integer :safety_stock,    null: false, default: 0
        t.integer :quality_control, null: false, default: 0
      end

      change_table :inventory_levels, bulk: true do |t|
        t.virtual :unavailable, type: :integer, stored: true, null: false,
                  as: "reserved + damaged + safety_stock + quality_control"
        t.virtual :on_hand, type: :integer, stored: true, null: false,
                  as: "available + committed + reserved + damaged + safety_stock + quality_control"
        t.index %i[shop_id on_hand],   name: "ix_inventory_levels_on_hand"
        t.index %i[shop_id available], name: "ix_inventory_levels_available"
      end
    end
  end

  def down
    safety_assured do
      change_table :inventory_levels, bulk: true do |t|
        t.remove_index name: "ix_inventory_levels_on_hand"
        t.remove_index name: "ix_inventory_levels_available"
        t.remove :on_hand, :unavailable, :reserved, :damaged, :safety_stock, :quality_control
        t.integer :on_hand,     null: false, default: 0
        t.integer :unavailable, null: false, default: 0
      end

      remove_foreign_key :inventory_adjustments, name: "fk_inventory_adjustments_group_id"
      change_table :inventory_adjustments, bulk: true do |t|
        t.remove_index name: "uq_inv_adjustments_group_level"
        t.remove :on_hand_delta, :unavailable_delta, :inventory_adjustment_group_id,
                 :reserved_delta, :damaged_delta, :safety_stock_delta, :quality_control_delta,
                 :ledger_document_uri, :position
        t.integer :on_hand_delta,     null: false, default: 0
        t.integer :unavailable_delta, null: false, default: 0
        t.string  :idempotency_key, null: false
        t.string  :reason, null: false, limit: 64
        t.string  :reference_type, limit: 64
        t.bigint  :reference_id
        t.index %i[shop_id idempotency_key], unique: true, name: "uq_inventory_adjustments_idempotency_key"
        t.index %i[shop_id reference_type reference_id], name: "ix_inventory_adjustments_reference_type_reference_id"
      end
    end

    drop_table :inventory_adjustment_groups
  end
end
