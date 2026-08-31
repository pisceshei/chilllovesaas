# frozen_string_literal: true

# 結帳線第三包：manual 付款方式資料層＋checkout 付款快照（86 號實測正典）。
#
# ①shop_payment_methods：本尊 Settings→Payments→Manual payment methods 的對位
#   （86 §3：⊕ 選單恰四值；同型別每店至多一列——已啟用者從選單消失的實測語義）。
#   🔴 15-F4.2 定位不變：PSP 付款方式＝capability 查詢不落此表；本表只承載 manual
#   （商家自行收款，F4.2(d) 明文不經 PSP capability）。停用＝active=false 不刪列
#   （86 §3 Deactivate 確認逐字「account details will be saved…reactivate at any time」；
#   Medusa MIT 同語義：歷史引用不斷）。
# ②builtin_guard 虛擬欄：內建型別每店唯一（custom 可多列）——同 markets 的
#   virtual guard 慣例（MySQL 無 partial unique index）。
# ③checkouts.payment_method_snapshot：選定付款方式快照（含 payment_instructions
#   ——下單確認頁要顯示它〔86 §3 helper 第二句〕，訂單成立時方法可能已被商家改文案，
#   快照原則同 shipping_lines）。
class ManualPaymentMethodsAndCheckoutPayment < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:shop_payment_methods)
      create_table :shop_payment_methods,
                   comment: "manual 付款方式（86 §3；PSP 方式不落表——15-F4.2 capability 查詢）" do |t|
        t.bigint :shop_id, null: false
        t.string :method_type, limit: 32, null: false,
                 comment: "恰四值 bank_deposit/money_order/cash_on_delivery/custom（86 §3 DOM）"
        t.string :name, null: false, comment: "顯示名；內建型別＝正典名，custom＝商家自訂（保留名單擋）"
        t.text :additional_details, comment: "checkout 選擇付款方式時顯示（86 §3 helper①）"
        t.text :payment_instructions, comment: "下單確認頁顯示（86 §3 helper②）"
        t.boolean :active, default: true, null: false, comment: "停用不刪列（86 §3 Deactivate 語義）"
        t.integer :position, default: 0, null: false
        t.virtual :builtin_guard, type: :string, limit: 32,
                  as: "if(`method_type` = 'custom', NULL, `method_type`)", stored: true,
                  comment: "內建型別每店唯一的物化 guard（custom 多列合法）"
        t.timestamps

        t.index [ :shop_id, :id ], unique: true, name: "uq_shop_payment_methods_tenant_id"
        t.index [ :shop_id, :builtin_guard ], unique: true, name: "uq_shop_payment_methods_builtin"
        t.index [ :shop_id, :name ], unique: true, name: "uq_shop_payment_methods_name"
        t.index [ :shop_id, :active, :position ], name: "ix_shop_payment_methods_active_position"
      end
      # safety_assured：本表同一 migration 內剛建、恆空——FK 驗證無鎖風險。
      safety_assured do
        add_foreign_key :shop_payment_methods, :shops, name: "fk_shop_payment_methods_shop"
      end
    end

    unless column_exists?(:checkouts, :payment_method_snapshot)
      # safety_assured：json 欄 default 只能是表達式（同 20260831210000 shipping_lines 的形）
      safety_assured do
        add_column :checkouts, :payment_method_snapshot, :json, null: false,
                   default: -> { "(json_object())" },
                   comment: "選定付款方式快照：{id,method_type,name,additional_details,payment_instructions}"
      end
    end
  end
end
