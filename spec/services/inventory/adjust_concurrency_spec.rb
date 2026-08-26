# frozen_string_literal: true

require "rails_helper"

# 排程第 17 包：唯一寫入入口的執行緒級測試（驗收基準：併發要害必須有測試）。
#
# 🔴 `use_transactional_tests = false`：要驗的是跨連線的列鎖與唯一索引互斥，
# transactional fixtures 下其他執行緒看不到未 commit 的資料（同 idempotency_key_concurrency_spec 的骨架）。
RSpec.describe Inventory::Adjust, "concurrency" do
  self.use_transactional_tests = false

  def purge!
    # 第 19 包起 Adjust 在同 transaction 寫 event_outbox（FK → shops），purge 必含它
    EventOutbox.unscoped.delete_all
    InventoryAdjustment.unscoped.delete_all
    InventoryAdjustmentGroup.unscoped.delete_all
    IdempotencyKey.unscoped.delete_all
    InventoryLevel.unscoped.delete_all
    InventoryItem.unscoped.delete_all
    Location.unscoped.delete_all
    ProductVariant.unscoped.delete_all
    Product.unscoped.delete_all
    # 🔴 發布列必須排在 Publication 之前刪（第 12 包）：Product／ProductVariant／
    #    Collection 的 after_create 會建 resource_publications，而本幫手用的是
    #    `delete_all`（繞過 dependent: :destroy）⇒ 殘列讓 fk_res_pub_publication_id 擋住刪除。
    ResourcePublication.unscoped.delete_all
    Publication.unscoped.delete_all
    # 2026-08-26 S0：`sales_catalogs` 必須排在 `publications` **之後**
    #   （FK `fk_publications_sales_catalog_id`；反過來刪會被外鍵擋住）。
    SalesCatalog.unscoped.delete_all
    Translation.unscoped.delete_all
    TranslationStatus.unscoped.delete_all
    ShopLocale.unscoped.delete_all
    UserStoreAssignment.unscoped.delete_all
    StaffMember.unscoped.delete_all
    Shop.delete_all
  end

  before { purge! }
  after { purge! }

  let!(:shop) { create(:shop, subdomain: "inv-conc-shop") }
  let!(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) } }
  let!(:item) { ActsAsTenant.with_tenant(shop) { variant.inventory_item } }
  let!(:location) { ActsAsTenant.with_tenant(shop) { Location.where(shop_id: shop.id).first! } }
  let!(:level) { ActsAsTenant.with_tenant(shop) { item.inventory_levels.first! } }

  def call(key:, delta: 1, cas: nil, mode: "adjust", quantity: nil, compare: nil)
    change = if mode == "set"
      { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
        location_id: "gid://chilllove/Location/#{location.id}",
        quantity: quantity, compare_quantity: compare, ignore_compare_quantity: compare.nil? }
    else
      { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
        location_id: "gid://chilllove/Location/#{location.id}",
        delta: delta, change_from_quantity: cas }
    end
    described_class.call(shop:, mode:, input: {
      idempotency_key: key, reason: "received", name: "available", changes: [ change ]
    })
  end

  def in_threads(count)
    barrier = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        barrier.pop
        yield(index)
      end
    end
    count.times { barrier << true }
    threads.map(&:value)
  end

  it "①同 key 併發：恰一次寫入（另一邊 replay 或 CONCURRENT），現值只加一次" do
    results = in_threads(2) { call(key: "same-key", delta: 5) }
    expect(level.reload.available).to eq(5)
    expect(InventoryAdjustment.unscoped.count).to eq(1)
    codes = results.flat_map { |r| r.user_errors.map { |e| e[:code] } }
    # 允許的形態：兩邊都拿到 group（一寫一 replay），或一邊 IDEMPOTENCY_CONCURRENT_REQUEST
    expect(codes - [ "IDEMPOTENCY_CONCURRENT_REQUEST" ]).to eq([])
    # 正向面（對抗審查 #24）：至少一邊成功拿到 group；兩邊都成功時必是同一個 group
    groups = results.map(&:group).compact
    expect(groups.length).to be >= 1
    expect(groups.map(&:id).uniq.length).to eq(1)
  end

  it "②不同 key 併發加總：列鎖序列化，最終值＝兩次之和、ledger 兩列" do
    in_threads(2) { |i| call(key: "k-#{i}", delta: 3) }
    expect(level.reload.available).to eq(6)
    expect(InventoryAdjustment.unscoped.count).to eq(2)
    # 對帳同步驗證：ledger SUM ＝ 現值
    expect(Inventory::Reconcile.call(shop:)).to eq([])
  end

  it "③CAS 競態：兩邊都以 change_from_quantity=0 出發，恰一個成功、另一個 STALE 且不落列" do
    results = in_threads(2) { |i| call(key: "cas-#{i}", delta: 4, cas: 0) }
    winners = results.count { |r| r.user_errors.empty? }
    stales = results.flat_map { |r| r.user_errors.map { |e| e[:code] } }.count("CHANGE_FROM_QUANTITY_STALE")
    expect(winners).to eq(1)
    expect(stales).to eq(1)
    expect(level.reload.available).to eq(4)
    expect(InventoryAdjustment.unscoped.count).to eq(1)
  end

  it "④adjust 與 set 併發：無論先後，最終現值與 ledger 對帳恆平" do
    call(key: "seed", delta: 10)
    in_threads(2) do |i|
      if i.zero?
        call(key: "race-adjust", delta: 5)
      else
        call(key: "race-set", mode: "set", quantity: 3, compare: nil).tap do
          # set 帶 ignore（顯式）以聚焦本測試在交錯一致性，CAS 競態已由 ③ 覆蓋
        end
      end
    end
    # set(ignore) 與 adjust 的兩種交錯：set→adjust ⇒ 8；adjust→set ⇒ 3。兩者都合法，
    # 但**現值必須等於 ledger 總和**——一致性是不變量，順序不是。
    final = level.reload.available
    expect([ 8, 3 ]).to include(final)
    expect(Inventory::Reconcile.call(shop:)).to eq([])
  end
end
