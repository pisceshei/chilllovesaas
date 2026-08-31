# frozen_string_literal: true

# 結帳線第二包：運送三表接上消費者（85 號實測正典）。
#
# ①products.shipping_profile_id：商品→自訂設定檔歸屬。🔴 NULL＝General（補集語義，
#   85 §2「All products not in other profiles」）⇒ FK `on_delete: :nullify`＝
#   刪 profile 商品自動回落 General（85 §5.4 刪除對話逐字語義）。
# ②shipping_rates transit 區間：85 §3 實測 select value＝base64 JSON {min,max} **秒制**；
#   None＝雙 NULL（本尊 None 是顯式選項，不是缺值）。
# ③checkouts.shipping_lines：選定運費快照（per-shipment 名稱＋價格＋rate id——
#   訂單成立與棄單挽回都要能回放當時的選擇，不能只有 shipping_cents 一個總數）。
# ④shops.split_shipping_enabled：85 §5.3 admin「Manage split shipping」開關，預設 On。
# ⑤🔴 checkouts.status enum 更正：90-blueprint/03 §B.2＝open/completed/deleted 三值
#   （abandoned＝abandoned_at 時戳旗標，不是狀態）。第一包誤用 "active"——預設值
#   與既有列一併更正（85 §6 末條）。
class WireShippingIntoCheckout < ActiveRecord::Migration[8.1]
  def change
    # 🔴 各步帶存在性 guard：MySQL DDL 非交易式——中途失敗重跑時，已生效的步驟
    #   不得再炸 Duplicate column（本檔首輪即在 add_foreign_key 被 strong_migrations
    #   擋下、前兩步已落庫的實錘）。
    unless column_exists?(:products, :shipping_profile_id)
      add_column :products, :shipping_profile_id, :bigint, null: true,
                 comment: "自訂運送設定檔歸屬；NULL＝General 補集（85 §2）"
    end
    unless index_exists?(:products, [ :shop_id, :shipping_profile_id ], name: "ix_products_shipping_profile")
      add_index :products, [ :shop_id, :shipping_profile_id ], name: "ix_products_shipping_profile"
    end
    # 🔴 刻意用**單欄** FK 而不是本倉庫慣用的複合 (shop_id, id)：MySQL 的 ON DELETE SET NULL
    #   會把**全部**引用欄設 NULL——複合形會試圖 NULL 掉 not-null 的 shop_id，
    #   刪 profile 直接炸 FK 錯誤，「回落 General」語義整個失效。跨租戶錯綁由
    #   admin 寫入路徑的租戶包裹擋（與其他單欄 FK 同一防線）。
    # safety_assured：新欄全 NULL、引用表當下為空集合關聯，FK 驗證無鎖風險
    #   （strong_migrations 對既有表 add_foreign_key 一律要求顯式確認）。
    unless foreign_key_exists?(:products, :shipping_profiles)
      safety_assured { add_foreign_key :products, :shipping_profiles, on_delete: :nullify }
    end

    unless column_exists?(:shipping_rates, :min_transit_seconds)
      add_column :shipping_rates, :min_transit_seconds, :bigint,
                 comment: "運達區間下限（秒；85 §3 base64 JSON {min,max}）；與 max 同 NULL＝None"
    end
    unless column_exists?(:shipping_rates, :max_transit_seconds)
      add_column :shipping_rates, :max_transit_seconds, :bigint
    end

    # safety_assured：strong_migrations 不會檢視 callable default（MySQL json 欄的
    #   default 只能是表達式）；json_array() 是常量表達式、MySQL 8 INSTANT DDL，無鎖風險
    #   ——與 M0 既有 json 欄（line_items_snapshot 等）同一形。
    unless column_exists?(:checkouts, :shipping_lines)
      safety_assured do
        add_column :checkouts, :shipping_lines, :json, null: false, default: -> { "(json_array())" },
                   comment: "選定運費快照：[{shipment_index,profile_id,rate_id,name,price_cents}]"
      end
    end

    unless column_exists?(:shops, :split_shipping_enabled)
      add_column :shops, :split_shipping_enabled, :boolean, null: false, default: true,
                 comment: "split shipping（85 §5.3 Manage split shipping；預設 On）"
    end

    change_column_default :checkouts, :status, from: "active", to: "open"
    # safety_assured：單表 UPDATE、條件命中集合＝第一包誤寫的 active 列（enum 值域外，
    #   除本更正外無其他寫入者）；strong_migrations 看不進 execute 一律要求確認。
    reversible do |dir|
      dir.up { safety_assured { execute(<<~SQL.squish) } }
        UPDATE checkouts SET status = 'open' WHERE status = 'active'
      SQL
      dir.down { safety_assured { execute(<<~SQL.squish) } }
        UPDATE checkouts SET status = 'active' WHERE status = 'open'
      SQL
    end
  end
end
