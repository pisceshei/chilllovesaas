# frozen_string_literal: true

require "rails_helper"

# 庫存 ledger 形狀的 schema 不變量（docs/plans/2026-08-24-庫存ledger形狀總裁定.md §一／§三）。
#
# 🔴 這支測的是 **DB 層機制**，不是模型行為（模型屬排程第 16 包，本輪刻意不建）——
# 所以全部走裸 SQL。要證明的是：「衍生量不落庫」已經從紀律變成機制，
# 想雙寫也寫不進去；恆等式由 STORED GENERATED 保證，不依賴任何 Ruby 代碼。
RSpec.describe "inventory ledger schema invariants", type: :model do
  let(:conn) { ActiveRecord::Base.connection }
  let(:shop) { create(:shop, subdomain: "ledger-schema-shop") }
  let(:variant) do
    ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) }
  end

  # 第 16 包起 item／level 由 callback 自動誕生（Shop→預設地點、Variant→item＋levels）；
  # 本 helper 改為：取 callback 建好的 level，UPDATE 出測試值。
  # UPDATE 刻意**不含** on_hand/unavailable——它們是 generated，含了就是本 spec 要抓的錯。
  def insert_chain!
    level = ActsAsTenant.with_tenant(shop) { variant.inventory_item.inventory_levels.first! }
    conn.execute(<<~SQL)
      UPDATE inventory_levels
         SET available = 7, committed = 2, reserved = 1, damaged = 3,
             safety_stock = 0, quality_control = 0, incoming = 99
       WHERE id = #{level.id}
    SQL
    level.id
  end

  def insert_group!(key: "idem-1")
    conn.execute(<<~SQL)
      INSERT INTO inventory_adjustment_groups
        (shop_id, idempotency_key, quantity_name, reason, mutation_kind, created_at, updated_at)
      VALUES (#{shop.id}, '#{key}', 'available', 'received', 'adjust', NOW(), NOW())
    SQL
    conn.select_value("SELECT LAST_INSERT_ID()").to_i
  end

  it "levels：on_hand 與 unavailable 由六個 leaf 算出，incoming 不在恆等式內" do
    level_id = insert_chain!
    row = conn.select_one("SELECT available, committed, unavailable, on_hand, incoming FROM inventory_levels WHERE id = #{level_id}")
    # unavailable = reserved(1) + damaged(3) + safety_stock(0) + quality_control(0)
    expect(row.fetch("unavailable")).to eq(4)
    # on_hand = available(7) + committed(2) + 4 —— incoming(99) 不得進來
    expect(row.fetch("on_hand")).to eq(13)
  end

  it "🔴 levels：on_hand 是 generated，直接寫入被 DB 拒絕（機制不是紀律）" do
    level_id = insert_chain!
    expect {
      conn.execute("UPDATE inventory_levels SET on_hand = 999 WHERE id = #{level_id}")
    }.to raise_error(ActiveRecord::StatementInvalid, /generated column/i)
    expect {
      conn.execute("UPDATE inventory_levels SET unavailable = 999 WHERE id = #{level_id}")
    }.to raise_error(ActiveRecord::StatementInvalid, /generated column/i)
  end

  it "ledger 行：on_hand_delta 由六個 leaf delta 算出；狀態間移動一列自含（和為 0）" do
    level_id = insert_chain!
    group_id = insert_group!
    # damaged → available 的移動：兩個相反符號 delta 在同一列
    conn.execute(<<~SQL)
      INSERT INTO inventory_adjustments
        (shop_id, inventory_adjustment_group_id, inventory_level_id,
         available_delta, committed_delta, reserved_delta, damaged_delta,
         safety_stock_delta, quality_control_delta, incoming_delta, position, created_at, updated_at)
      VALUES (#{shop.id}, #{group_id}, #{level_id}, 3, 0, 0, -3, 0, 0, 0, 0, NOW(), NOW())
    SQL
    row = conn.select_one("SELECT unavailable_delta, on_hand_delta FROM inventory_adjustments WHERE inventory_adjustment_group_id = #{group_id}")
    expect(row.fetch("unavailable_delta")).to eq(-3)
    expect(row.fetch("on_hand_delta")).to eq(0)   # 狀態間移動不改 on_hand
  end

  it "🔴 唯一鍵：同 group 對同 level 第二列被拒（一列＝一個 (group, level)）" do
    level_id = insert_chain!
    group_id = insert_group!
    insert_row = ->(pos) do
      conn.execute(<<~SQL)
        INSERT INTO inventory_adjustments
          (shop_id, inventory_adjustment_group_id, inventory_level_id,
           available_delta, committed_delta, reserved_delta, damaged_delta,
           safety_stock_delta, quality_control_delta, incoming_delta, position, created_at, updated_at)
        VALUES (#{shop.id}, #{group_id}, #{level_id}, 1, 0, 0, 0, 0, 0, 0, #{pos}, NOW(), NOW())
      SQL
    end
    insert_row.call(0)
    expect { insert_row.call(1) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "🔴 冪等鍵唯一性在 group 頭（同店同鍵第二列被拒；ledger 行已無 idempotency_key 欄）" do
    insert_group!(key: "dup-key")
    expect { insert_group!(key: "dup-key") }.to raise_error(ActiveRecord::RecordNotUnique)

    columns = conn.columns("inventory_adjustments").map(&:name)
    expect(columns).not_to include("idempotency_key")
    expect(columns).not_to include("reason")   # 呼叫層欄位已上移 group
  end
end
