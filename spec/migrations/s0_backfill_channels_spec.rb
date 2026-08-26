# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260826070000_create_channel_identity.rb").to_s

# S0 migration 20260826070000 的 `app_installations` ＋ `channels` 回填。
#
# 🔴 **本檔載入並執行 `CreateChannelIdentity` 本體，不抄邏輯副本**（第 12 包已證明
#   副本綠、本體錯是真的會發生的；見 `spec/migrations/p12_backfill_publications_spec.rb` 檔頭）。
#
# 🔴 **存在理由**（第 11 包部署事故換來的固定處理）：回填迴圈的本體只有在資料庫已有
#   publication 時才執行；CI 跑空庫、開發庫也常剛好沒有 ⇒ 兩處都不執行迴圈本體、
#   `db:migrate` 一路綠，**只有正式環境會炸**。
#
# 🔴 呼叫 `backfill_channel_identity!` 而不是 `up`：`up` 的 `create_table` 會送真 DDL
#   ⇒ MySQL 隱式提交，打斷 RSpec 交易（S0 第一批實測過）。該方法是 `up` 呼叫的
#   同一個本體，不碰 DDL。完整 DDL 往返另立非交易群組，見本檔末。
RSpec.describe CreateChannelIdentity do
  let!(:shop) { create(:shop, subdomain: "s0-chan") }

  def run_migration
    migration = described_class.new
    migration.verbose = false
    migration.backfill_channel_identity!
  end

  def publication_of(shop_record)
    ActsAsTenant.without_tenant { Publication.find_by(shop_id: shop_record.id) }
  end

  def channels_of(shop_record)
    ActsAsTenant.without_tenant { Channel.where(shop_id: shop_record.id).to_a }
  end

  def installations_of(shop_record)
    ActsAsTenant.without_tenant { AppInstallation.where(shop_id: shop_record.id).to_a }
  end

  # 打回 migration 要面對的起始狀態：有 publication、但沒有 channel／installation。
  # 🔴 順序不可倒：channel 指向 installation，先刪 installation 會被外鍵擋住。
  def strip_identity!(shop_record)
    ActsAsTenant.without_tenant do
      Channel.where(shop_id: shop_record.id).delete_all
      AppInstallation.where(shop_id: shop_record.id).delete_all
    end
  end

  before { strip_identity!(shop) }

  it "🔴 在**沒有 current_tenant** 的情境下回填——不得 NoTenantSet" do
    expect(ActsAsTenant.current_tenant).to be_nil
    expect(channels_of(shop)).to be_empty

    expect { run_migration }.not_to raise_error

    expect(channels_of(shop).size).to eq(1)
    expect(installations_of(shop).size).to eq(1)
  end

  # 🔴 行為守衛（不是掃字串）：migration 的回填讀取走 `Publication.find_each`／
  #   `Channel.pluck`，**刻意不加 `.unscoped`** ⇒ default scope 的 raise 是活的
  #   ⇒ 拿掉 `without_tenant` 這一格必紅。
  it "🔴 `current_tenant` 為 nil 且**不在 without_tenant 內**時照樣完成" do
    ActsAsTenant.with_tenant(nil) do
      expect(ActsAsTenant.current_tenant).to be_nil
      expect { run_migration }.not_to raise_error
    end

    expect(channels_of(shop).size).to eq(1)
  end

  # 🔴 比 raise 更危險的形態：租戶是別間店時 default scope 會把來源查詢過濾成 0 列
  #   ⇒ 回填一列都不做**而 migration 回報成功**。
  it "🔴 `current_tenant` 是**別間店**時仍照 publication 自己的 shop_id 回填" do
    other = create(:shop, subdomain: "s0-chan-other")
    strip_identity!(other)

    ActsAsTenant.with_tenant(other) { run_migration }

    expect(channels_of(shop).size).to eq(1)
    expect(channels_of(other).size).to eq(1)
  end

  it "回填的 channel 帶正確的欄位，且 handle 取自 publications.channel_handle" do
    handle = publication_of(shop).channel_handle
    expect(handle).to be_present, "空的 channel_handle 會讓下面的 handle 斷言恆真"

    run_migration

    channel = channels_of(shop).first
    expect(channel.shop_id).to eq(shop.id)
    expect(channel.publication_id).to eq(publication_of(shop).id)
    expect(channel.handle).to eq(handle)
    expect(channel.channel_type).to eq("app")
    expect(channel.app_installation_id).to eq(installations_of(shop).first.id)
  end

  it "回填的 installation 指向字典裡的 app，且是安裝中狀態" do
    run_migration

    installation = installations_of(shop).first
    expect(installation.app_handle).to eq(Shop::DEFAULT_CHANNEL_HANDLE)
    expect(installation.installed_at).to be_present
    expect(installation.uninstalled_at).to be_nil
    expect(installation).to be_installed
    expect(PlatformApp.exists?(handle: installation.app_handle)).to be(true)
  end

  # 🔴 **半途死掉的重跑**：MySQL DDL 非交易，migration 死在中間是真的會發生的
  #   （第 11 包就是這樣——建完表、回填炸掉、`schema_migrations` 沒記上）。
  #   那之後的狀態是「installation 已建、channel 還沒建」，重跑必須**沿用**既有的
  #   installation。用 `create!` 而不是 `find_or_create_by!` 的話這一格會撞
  #   `uq_app_installations_app` 而紅。
  it "🔴 installation 已存在、channel 還沒建時，重跑沿用既有 installation" do
    run_migration
    existing = installations_of(shop).first
    expect(existing).to be_present

    # 只砍 channel，留下 installation——這正是 migration 死在兩者之間的狀態。
    ActsAsTenant.without_tenant { Channel.where(shop_id: shop.id).delete_all }

    expect { run_migration }.not_to raise_error

    expect(installations_of(shop).map(&:id)).to eq([ existing.id ])
    expect(channels_of(shop).first.app_installation_id).to eq(existing.id)
  end

  it "冪等：跑兩次不會重複建 channel" do
    run_migration
    first = channels_of(shop).map(&:id)
    expect(first.size).to eq(1)

    expect { run_migration }.not_to raise_error
    expect(channels_of(shop).map(&:id)).to eq(first)
  end

  # 🔴 這一格盯的是「字典缺項時不得自己造字典列」。
  #   讓正式環境的既有資料反過來定義平台目錄，是把字典表的意義整個抹掉。
  it "🔴 `platform_apps` 沒有對應 handle 時**跳過**該筆，不自動建字典列" do
    ActsAsTenant.without_tenant do
      Publication.where(shop_id: shop.id).update_all("channel_handle = 'not_in_catalog'")
    end
    before_count = PlatformApp.count

    expect { run_migration }.not_to raise_error

    expect(channels_of(shop)).to be_empty
    expect(installations_of(shop)).to be_empty
    expect(PlatformApp.count).to eq(before_count)
    expect(PlatformApp.exists?(handle: "not_in_catalog")).to be(false)
  end

  it "🔴 跨租戶：兩間店各自拿到自己的 channel 與 installation" do
    other = create(:shop, subdomain: "s0-chan-cross")
    strip_identity!(other)

    run_migration

    mine = channels_of(shop)
    theirs = channels_of(other)
    expect(mine.size).to eq(1)
    expect(theirs.size).to eq(1)
    expect(mine.first.id).not_to eq(theirs.first.id)
    expect(mine.first.publication_id).to eq(publication_of(shop).id)
    expect(theirs.first.publication_id).to eq(publication_of(other).id)
  end

  # 🔴 DB 層守衛，不是 model 層：複合外鍵讓「指向別間店的 publication／installation」
  #   在資料庫層不可能。`update_all` 不跑 validation，外鍵照樣擋。
  it "🔴 channel 指向**別間店**的 publication 會被複合外鍵擋下" do
    other = create(:shop, subdomain: "s0-chan-fk")
    run_migration

    other_publication_id = publication_of(other).id
    expect {
      ActsAsTenant.without_tenant do
        Channel.where(shop_id: shop.id)
               .update_all("publication_id = #{other_publication_id.to_i}")
      end
    }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  # 🔴 同一個 publication 不得有兩個 channel（`uq_channels_publication`）。
  #   本尊官方 SDL 是 1:N，但實測第一方管道 `Channel.id == Publication.id` ⇒ 退化成 1:1，
  #   我方取實測形態。這一格釘住它，順便擋住「回填或建店重複建 channel」。
  it "🔴 同一 publication 只能有一個 channel" do
    run_migration
    publication = publication_of(shop)

    expect {
      ActsAsTenant.without_tenant do
        Channel.create!(shop_id: shop.id, publication_id: publication.id,
                        app_installation_id: installations_of(shop).first.id,
                        handle: "second-channel", channel_type: "app")
      end
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "DDL 往返（up → down → up）" do
    self.use_transactional_tests = false

    let!(:ddl_shop) { create(:shop, subdomain: "s0-chan-ddl") }

    # 收尾要連外層 `let!(:shop)` 建的那間一起收（本群組非交易，外層 let! 同樣不回滾）。
    after do
      ActsAsTenant.without_tenant do
        Shop.where(subdomain: %w[s0-chan-ddl s0-chan]).find_each(&:destroy)
      end
      PlatformApp.seed!
    end

    # 🔴 一律走 `migrate(:up)` / `migrate(:down)`，不直呼——直呼不設方向，
    #   `strong_migrations` 會把 `down` 的 DDL 當成正在新增的危險操作擋下。
    def migration
      described_class.new.tap { |m| m.verbose = false }
    end

    it "🔴 down 之後重跑 up：三張表重建、字典重新 seed、回填照樣執行" do
      expect(ActsAsTenant.without_tenant { Channel.where(shop_id: ddl_shop.id).count }).to eq(1)

      migration.migrate(:down)

      %i[channels app_installations platform_apps].each do |table|
        expect(ActiveRecord::Base.connection.table_exists?(table)).to be(false), "#{table} 應已被 down 移除"
      end

      migration.migrate(:up)
      [ Channel, AppInstallation, PlatformApp ].each(&:reset_column_information)

      expect(PlatformApp.count).to eq(PlatformApp::CATALOG_SEED.size)
      channel = ActsAsTenant.without_tenant { Channel.find_by(shop_id: ddl_shop.id) }
      expect(channel).to be_present, "回填沒有為既有 publication 重建 channel"
      expect(channel.handle).to eq(Shop::DEFAULT_CHANNEL_HANDLE)
    end

    it "🔴 up 冪等：連跑兩次不炸、不重複建列" do
      expect { migration.migrate(:up) }.not_to raise_error
      expect { migration.migrate(:up) }.not_to raise_error

      expect(ActsAsTenant.without_tenant { Channel.where(shop_id: ddl_shop.id).count }).to eq(1)
      expect(PlatformApp.count).to eq(PlatformApp::CATALOG_SEED.size)
    end
  end
end
