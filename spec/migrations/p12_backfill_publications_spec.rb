# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260826060000_backfill_resource_publications.rb").to_s

# 第 12 包 migration 20260826060000 的 `resource_publications` 回填。
#
# 🔴 **本檔載入並執行 `BackfillResourcePublications` 本體，不抄邏輯副本。**
#
#   前一版抄了一份 `run_backfill`，兩位對抗審查員以不同方法各自證明了它守不住任何東西：
#     - 把 migration 的 `where(shop_id:)` 刪掉一個 token ⇒ 回填寫出跨租戶的列
#       （`insert_all` 繞過 validation、多型欄位無外鍵，兩層都不擋），spec 全綠；
#     - 把 migration 的 `auto_publish: true` 拿掉 ⇒ 回填成完全相反的管道集合，spec 全綠。
#   當時副本與本體之間唯一的機械連結是一個掃字串的 source-guard，
#   而那種守衛**可以被一行註釋騙過**（實測：把 `ActsAsTenant.without_tenant do` 換成
#   `begin # ActsAsTenant.without_tenant` ⇒ 守衛照樣過）。
#   ⇒ 字串守衛全數退場，改由**行為**守住。
#
# 🔴 **這支 spec 的第二個理由**（第 11 包部署事故換來的固定處理）：回填迴圈的**本體**
#   只有在資料庫裡已經有既有資料時才會被執行到。CI 的 `db:migrate` 跑在**空資料庫**上，
#   開發庫也常剛好沒有 ⇒ 兩處都不執行迴圈本體，`db:migrate` 一路綠，只有正式環境會炸。
#   **本次當場複驗到**：同一支 migration 在本機開發庫回填 3 列、在測試庫回填 0 列，
#   兩次都 exit 0。⇒ 本檔一律**先種既有資料**再跑。
RSpec.describe BackfillResourcePublications do
  let!(:shop) { create(:shop, subdomain: "backfill-pub") }

  # 執行**真的** migration。
  def run_backfill
    migration = described_class.new
    migration.verbose = false
    migration.up
  end

  def rows_for(shop_record)
    ActsAsTenant.without_tenant do
      ResourcePublication.where(shop_id: shop_record.id)
                         .pluck(:publishable_type, :publishable_id, :publication_id, :published_at)
    end
  end

  def online_store_of(shop_record)
    ActsAsTenant.with_tenant(shop_record) { Publication.online_store }
  end

  # 「回填前既有、且沒有發布列」的資源——正是正式環境的形態
  # （線上實測 2026-08-26：`resource_publications` 共 0 列）。
  # 🔴 用 `delete_all` 清掉 callback 剛建好的列，才回到 migration 要面對的起始狀態；
  #    不清就等於在測「已經有列時回填不重複建」，那是另一格。
  let!(:product) { ActsAsTenant.with_tenant(shop) { create(:product, shop:) } }
  let!(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, product:) } }

  before do
    ActsAsTenant.without_tenant { ResourcePublication.where(shop_id: shop.id).delete_all }
  end

  it "🔴 在**沒有 current_tenant** 的情境下回填既有資源——不得 NoTenantSet" do
    expect(ActsAsTenant.current_tenant).to be_nil

    expect { run_backfill }.not_to raise_error

    targets = rows_for(shop).map { |type, id, _, _| [ type, id ] }
    expect(targets).to contain_exactly([ "Product", product.id ], [ "ProductVariant", variant.id ])
  end

  # 🔴 `without_tenant` 的**行為**守衛（取代掃字串的 source-guard）。
  #   `backfill_all!` 的查詢刻意**不走 `.unscoped`**，所以 default scope 的
  #   `NoTenantSet` raise 是活的 ⇒ 拿掉 `without_tenant` 這一格必紅。
  #   ⚠️ 前一版的 migration 讀取走 `.unscoped`、寫入走 `insert_all`，兩者都繞過
  #   default scope ⇒ 拿掉 `without_tenant` **不會**炸，所以當時的因果宣稱是錯的。
  it "🔴 `current_tenant` 為 nil 且**不在 without_tenant 內**時照樣完成" do
    ActsAsTenant.with_tenant(nil) do
      expect(ActsAsTenant.current_tenant).to be_nil
      expect { run_backfill }.not_to raise_error
    end

    expect(rows_for(shop).size).to eq(2)
  end

  it "🔴 `current_tenant` 是**別間店**時仍照 publishable 自己的 shop_id 回填" do
    other = create(:shop, subdomain: "backfill-pub-tenant")

    ActsAsTenant.with_tenant(other) { run_backfill }

    # 別間店的租戶脈絡不得讓本店的回填靜默變成 0 列
    # （「回報成功但什麼都沒做」比直接炸危險得多）。
    expect(rows_for(shop).size).to eq(2)
  end

  it "回填的列是**已發布**狀態（published_at 不為 NULL 且不在未來）" do
    run_backfill

    stamps = rows_for(shop).map(&:last)
    expect(stamps).not_to be_empty, "空集合會讓下面兩個 all(...) 恆真"
    expect(stamps).to all(be_present)
    expect(stamps).to all(be <= Time.current)
  end

  it "冪等：回填跑兩次不會重複建列" do
    run_backfill
    first = rows_for(shop).size
    expect(first).to be_positive

    expect { run_backfill }.not_to raise_error
    expect(rows_for(shop).size).to eq(first)
  end

  it "🔴 `auto_publish = false` 的管道不被回填" do
    manual = ActsAsTenant.with_tenant(shop) do
      Publication.create!(shop_id: shop.id, name: "手動管道", channel_handle: "manual-ch",
                          auto_publish: false, supports_future_publishing: false)
    end

    run_backfill

    ids = rows_for(shop).map { |_, _, publication_id, _| publication_id }
    expect(ids).not_to be_empty, "空集合會讓下面的 not_to include 恆真"
    expect(ids.uniq).to eq([ online_store_of(shop).id ])
    expect(ids).not_to include(manual.id)
  end

  # 🔴 **正向斷言，不用「找不到違規列」**。
  #   前一版斷言的是「JOIN publications 後 p.shop_id <> rp.shop_id 的列數為 0」——
  #   而 `fk_res_pub_publication_id` 這個複合外鍵讓該謂詞在 DB 層**永遠不可滿足**
  #   （實測：刻意用 `insert_all` 造污染列會被 FK 直接擋掉）
  #   ⇒ 那一格在任何實作、任何測資下都是 0，**結構上不可能失敗**。
  it "🔴 跨租戶：每間店只拿到自己的管道，且 publishable 確實屬於該店" do
    other = create(:shop, subdomain: "backfill-pub-other")
    other_product = ActsAsTenant.with_tenant(other) { create(:product, shop: other) }
    ActsAsTenant.without_tenant { ResourcePublication.where(shop_id: other.id).delete_all }

    run_backfill

    [ [ shop, [ [ "Product", product.id ], [ "ProductVariant", variant.id ] ] ],
      [ other, [ [ "Product", other_product.id ] ] ] ].each do |shop_record, expected|
      rows = rows_for(shop_record)
      expect(rows).not_to be_empty

      # ①管道集合恰等於該店的 auto_publish 集合
      expect(rows.map { |_, _, pid, _| pid }.uniq).to eq([ online_store_of(shop_record).id ])
      # ②publishable 恰等於該店自己的資源（少一個或多一個都紅）
      expect(rows.map { |type, id, _, _| [ type, id ] }).to match_array(expected)
    end

    # ③逐列複驗 publishable 的**實際歸屬**與列上的 shop_id 相同。
    #   這一條才是「刪掉 `where(shop_id:)`」那個突變的直接殺手——
    #   FK 只保證 rp.shop_id 與 publication 一致，**管不到 publishable 屬於誰**。
    mismatched = ActsAsTenant.without_tenant do
      ResourcePublication.all.reject do |row|
        row.publishable_type.constantize.where(id: row.publishable_id).pick(:shop_id) == row.shop_id
      end
    end
    expect(mismatched).to be_empty,
      "回填寫出了 shop_id 與 publishable 實際歸屬不符的列：#{mismatched.map { |r| [ r.shop_id, r.publishable_type, r.publishable_id ] }}"
  end
end
