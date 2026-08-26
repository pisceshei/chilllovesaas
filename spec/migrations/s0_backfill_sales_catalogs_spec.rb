# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260826062000_create_sales_catalogs_and_publication_capabilities.rb").to_s

# S0 migration 20260826062000 的 `sales_catalogs` 回填。
#
# 🔴 **本檔載入並執行 `CreateSalesCatalogsAndPublicationCapabilities` 本體，不抄邏輯副本。**
#   抄副本的失敗形態已由第 12 包當場證明過兩次（見
#   `spec/migrations/p12_backfill_publications_spec.rb` 檔頭）：副本綠、本體錯。
#
# 🔴 **這支 spec 的存在理由**（第 11 包部署事故換來的固定處理）：回填迴圈的**本體**
#   只有在資料庫已經有既有 publication 時才會被執行到。CI 的 `db:migrate` 跑在**空資料庫**、
#   開發庫也常剛好沒有 ⇒ 兩處都不執行迴圈本體、`db:migrate` 一路綠，**只有正式環境會炸**。
#   ⇒ 本檔一律**先種既有資料、再把它打回 migration 要面對的起始狀態**，然後才跑。
#
# 🔴 **為什麼呼叫 `backfill_sales_catalogs!` 而不是 `up`**：`up` 的第一句
#   `create_table ... if_not_exists: true` 會真的送出 `CREATE TABLE IF NOT EXISTS`
#   ⇒ MySQL **隱式提交**，RSpec 的測試交易當場被打斷，每一格都會看到前一格的殘留
#   （實測：第二格起全部撞 `Subdomain has already been taken`）。
#   `backfill_sales_catalogs!` 是 `up` **自己呼叫的那個方法本體**，不是副本，且不碰 DDL。
#   DDL 往返（up→down→up）另立非交易群組，見本檔末。
#
# @see docs/plans/2026-08-26-S0-方案D-schema設計.md
RSpec.describe CreateSalesCatalogsAndPublicationCapabilities do
  let!(:shop) { create(:shop, subdomain: "s0-backfill") }

  # 執行**真的** migration 的回填本體。
  def run_migration
    migration = described_class.new
    migration.verbose = false
    migration.backfill_sales_catalogs!
  end

  def publication_of(shop_record)
    ActsAsTenant.without_tenant { Publication.find_by(shop_id: shop_record.id) }
  end

  def catalogs_of(shop_record)
    ActsAsTenant.without_tenant { SalesCatalog.where(shop_id: shop_record.id).to_a }
  end

  # 把 `Shop#after_create` 剛建好的 catalog 拆掉，回到 migration 要面對的起始狀態：
  # 「有 publication、但 `sales_catalog_id` 是 NULL、且沒有任何 catalog 列」。
  # 🔴 順序不可倒：先清外鍵欄再刪表列，反過來會被 `fk_publications_sales_catalog_id` 擋住。
  def strip_catalogs!(shop_record)
    ActsAsTenant.without_tenant do
      Publication.where(shop_id: shop_record.id).update_all("sales_catalog_id = NULL")
      SalesCatalog.where(shop_id: shop_record.id).delete_all
    end
  end

  before { strip_catalogs!(shop) }

  it "🔴 在**沒有 current_tenant** 的情境下回填既有 publication——不得 NoTenantSet" do
    expect(ActsAsTenant.current_tenant).to be_nil
    expect(catalogs_of(shop)).to be_empty

    expect { run_migration }.not_to raise_error

    expect(catalogs_of(shop).size).to eq(1)
    expect(publication_of(shop).sales_catalog_id).to eq(catalogs_of(shop).first.id)
  end

  # 🔴 `without_tenant` 的**行為**守衛（不是掃字串的 source-guard——那種守衛
  #   可以被一行註釋騙過，第 12 包已實測）。
  #   migration 的回填讀取走 `Publication.where(...)`，**刻意不加 `.unscoped`**
  #   ⇒ default scope 的 `NoTenantSet` raise 是活的 ⇒ 拿掉 `without_tenant` 這一格必紅。
  it "🔴 `current_tenant` 為 nil 且**不在 without_tenant 內**時照樣完成" do
    ActsAsTenant.with_tenant(nil) do
      expect(ActsAsTenant.current_tenant).to be_nil
      expect { run_migration }.not_to raise_error
    end

    expect(catalogs_of(shop).size).to eq(1)
  end

  # 🔴 這一格盯的是**比 raise 更危險的失敗形態**：租戶是別間店時，default scope 會把
  #   `Publication.where(sales_catalog_id: nil)` 過濾成 0 列 ⇒ 回填**一列都不做、
  #   而 migration 回報成功**。正式環境跑完會得到一個「migrate 綠、第三層全空」的庫。
  it "🔴 `current_tenant` 是**別間店**時仍照 publication 自己的 shop_id 回填" do
    other = create(:shop, subdomain: "s0-backfill-other")
    strip_catalogs!(other)

    ActsAsTenant.with_tenant(other) { run_migration }

    expect(catalogs_of(shop).size).to eq(1)
    expect(catalogs_of(other).size).to eq(1)
  end

  it "回填出來的 catalog 帶方案 D 規定的值，且 title 取自 publication.name" do
    name = publication_of(shop).name
    expect(name).to be_present, "空的 name 會讓下面的 title 斷言恆真"

    run_migration

    catalog = catalogs_of(shop).first
    expect(catalog.shop_id).to eq(shop.id)
    expect(catalog.catalog_type).to eq("app")
    expect(catalog.status).to eq("active")
    expect(catalog.title).to eq(name)
    # 本尊表單的 Automatically include new products 預設**開**（82 §9.5c 實測）。
    expect(catalog.auto_include_new_products).to be(true)
  end

  it "冪等：跑兩次不會重複建 catalog" do
    run_migration
    first = catalogs_of(shop).map(&:id)
    expect(first.size).to eq(1)

    expect { run_migration }.not_to raise_error
    expect(catalogs_of(shop).map(&:id)).to eq(first)
  end

  it "🔴 已經有 catalog 的 publication 不被動到（回填只補 NULL 的）" do
    run_migration
    original = catalogs_of(shop).first
    ActsAsTenant.without_tenant { original.update!(title: "商家改過的名字") }

    run_migration

    expect(catalogs_of(shop).size).to eq(1)
    expect(catalogs_of(shop).first.title).to eq("商家改過的名字")
  end

  it "🔴 跨租戶：兩間店各自拿到自己的 catalog，不共用也不錯配" do
    other = create(:shop, subdomain: "s0-backfill-cross")
    strip_catalogs!(other)

    run_migration

    mine = catalogs_of(shop)
    theirs = catalogs_of(other)
    expect(mine.size).to eq(1)
    expect(theirs.size).to eq(1)
    expect(mine.first.id).not_to eq(theirs.first.id)

    expect(publication_of(shop).sales_catalog_id).to eq(mine.first.id)
    expect(publication_of(other).sales_catalog_id).to eq(theirs.first.id)
  end

  # 🔴 **DB 層的租戶守衛**，不是 model 層。複合外鍵
  #   `(shop_id, sales_catalog_id) → sales_catalogs(shop_id, id)` 的作用就是讓
  #   「指向別間店的 catalog」在資料庫層直接不可能——model validation 繞得過
  #   （`update_columns`／`insert_all` 都不跑 validation），外鍵繞不過。
  it "🔴 publication 指向**別間店**的 catalog 會被複合外鍵擋下" do
    other = create(:shop, subdomain: "s0-backfill-fk")
    run_migration

    other_catalog_id = catalogs_of(other).first.id
    expect(other_catalog_id).to be_present

    expect {
      ActsAsTenant.without_tenant do
        Publication.where(shop_id: shop.id).update_all("sales_catalog_id = #{other_catalog_id.to_i}")
      end
    }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  # 🔴 這一格盯的是 `down` 的一個具體坑：先移除外鍵、卻沒清掉殘留的 `sales_catalog_id`，
  #   重跑的 `up` 就會因為「欄位不是 NULL」而**跳過回填**，得到一個指向已刪除 catalog
  #   的懸空 id。`down` 裡那句 `update_all(sales_catalog_id: nil)` 就是為這件事存在的。
  #
  # ⚠️ **本群組非交易**（`use_transactional_tests = false`）：`up`／`down` 都送 DDL，
  #   MySQL 的隱式提交會把測試交易打斷 ⇒ 只能自己收尾。收尾用 `shop.destroy`，
  #   它會走 `Shop#around_destroy` 的租戶包裹與整條 `dependent:` 鏈（含本次新增的
  #   `sales_catalogs`，順序由 `shop.rb` 的關聯宣告順序保證）。
  #
  # 🔴 這是本檔唯一跑**完整 `up`／`down`** 的地方，也是唯一能證明
  #   「DDL 守衛真的冪等」的地方——上面那些格子跑的是回填本體，碰不到 DDL。
  describe "DDL 往返（up → down → up）" do
    self.use_transactional_tests = false

    let!(:ddl_shop) { create(:shop, subdomain: "s0-backfill-ddl") }

    # 🔴 收尾要連**外層 `let!(:shop)` 建的那間**一起收：本群組非交易，外層的
    #   `let!` 在這裡同樣是真寫入、同樣不回滾。只收自己那間會讓下一次跑測試撞
    #   `Subdomain has already been taken`（實測踩過）。
    after do
      ActsAsTenant.without_tenant do
        Shop.where(subdomain: %w[s0-backfill-ddl s0-backfill]).find_each(&:destroy)
      end
    end

    # 🔴 一律走 `migrate(:up)`／`migrate(:down)`，**不直接呼叫 `up`／`down`**：
    #   直呼不會設定 migration 的方向，於是 `strong_migrations` 會把 `down` 裡的
    #   `remove_column` 當成正在**新增**的危險操作而擋下（實測拿到
    #   `StrongMigrations::UnsafeMigration`）。`migrate(:down)` 才是正式 API，
    #   與 `bin/rails db:rollback` 走同一條路。
    def migration
      described_class.new.tap { |m| m.verbose = false }
    end

    it "🔴 down 之後重跑 up：DDL 重建、回填照樣執行，不留懸空 id" do
      # 起始狀態：`Shop#after_create` 已經建好 catalog。
      first_catalog_id = ActsAsTenant.without_tenant do
        Publication.find_by(shop_id: ddl_shop.id).sales_catalog_id
      end
      expect(first_catalog_id).to be_present

      migration.migrate(:down)

      # down 之後：表沒了、欄位改回舊名、殘留 id 已清空。
      expect(ActiveRecord::Base.connection.table_exists?(:sales_catalogs)).to be(false)
      expect(ActiveRecord::Base.connection.column_exists?(:publications, :catalog_id)).to be(true)

      migration.migrate(:up)

      # up 之後：表回來了，且該店的 publication 重新拿到一個**新的**有效 catalog。
      SalesCatalog.reset_column_information
      Publication.reset_column_information
      refilled = ActsAsTenant.without_tenant do
        Publication.find_by(shop_id: ddl_shop.id).sales_catalog_id
      end
      expect(refilled).to be_present
      expect(
        ActsAsTenant.without_tenant { SalesCatalog.where(shop_id: ddl_shop.id, id: refilled).exists? }
      ).to be(true), "回填寫出了指向不存在 catalog 的懸空 id"
    end

    it "🔴 up 冪等：連跑兩次不炸、不重複建表" do
      expect { migration.migrate(:up) }.not_to raise_error
      expect { migration.migrate(:up) }.not_to raise_error
      expect(
        ActsAsTenant.without_tenant { SalesCatalog.where(shop_id: ddl_shop.id).count }
      ).to eq(1)
    end
  end
end
