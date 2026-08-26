# frozen_string_literal: true

require "rails_helper"

# S0 第二批的三個模型：`PlatformApp`（平台字典）／`AppInstallation`／`Channel`。
# 官方形狀的取證見各 model 檔頭（shopify.dev，2026-08-26）。
RSpec.describe "管道身分模型（S0 第二批）" do
  let!(:shop) { create(:shop, subdomain: "chan-ident") }

  describe PlatformApp do
    # 🔴 這是**平台字典表**：沒有 shop_id、跨租戶共用。
    #   判準逐字＝「表裡一列都不屬於任何一家店」（CLAUDE.md 鐵律 2 平台字典表段）。
    it "🔴 沒有 shop_id 欄——它不是租戶資料" do
      expect(described_class.column_names).not_to include("shop_id")
    end

    it "🔴 在**沒有租戶**的情境下可以自由讀取（與租戶表相反）" do
      expect(ActsAsTenant.current_tenant).to be_nil
      expect { described_class.count }.not_to raise_error
      expect(described_class.count).to be_positive
    end

    it "自然主鍵是 handle" do
      expect(described_class.primary_key).to eq("handle")
    end

    it "seed! 冪等：跑兩次列數不變" do
      before_count = described_class.count
      described_class.seed!
      expect(described_class.count).to eq(before_count)
    end

    # 🔴 `PlatformLocale.seed!` 是 `next false if exists?`（純新增）；本表刻意不同。
    #   app 的 title 會改（改名、換開發者），跳過會讓改動**靜默不生效**而部署看起來成功。
    it "🔴 seed! 會**更新**既有列，不是跳過" do
      record = described_class.find(PlatformApp::CATALOG_SEED.first[:handle])
      record.update!(title: "被改壞的名字")

      described_class.seed!

      expect(record.reload.title).to eq(PlatformApp::CATALOG_SEED.first[:title])
    end

    it "🔴 CATALOG_SEED 的每一列都通過 validation（seed 不繞過驗證）" do
      PlatformApp::CATALOG_SEED.each do |row|
        expect(described_class.new(row)).to be_valid, "字典列不合法：#{row.inspect}"
      end
    end

    it "handle 格式受限（避免字典被寫進奇怪的鍵）" do
      expect(described_class.new(handle: "Bad Handle", title: "x")).not_to be_valid
      expect(described_class.new(handle: "good_handle-2", title: "x")).to be_valid
    end
  end

  describe AppInstallation do
    it "建店時自動安裝預設管道 app" do
      installation = ActsAsTenant.with_tenant(shop) { described_class.sole }

      expect(installation.app_handle).to eq(Shop::DEFAULT_CHANNEL_HANDLE)
      expect(installation.installed_at).to be_present
      expect(installation).to be_installed
      expect(described_class.column_names).to include("shop_id")
    end

    it "🔴 沒有租戶時 fail-closed（它是業務資料，不是字典）" do
      expect { described_class.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end

    it "每店每 app 只有一列（重裝＝清 uninstalled_at，不是再插一列）" do
      ActsAsTenant.with_tenant(shop) do
        duplicate = described_class.new(app_handle: Shop::DEFAULT_CHANNEL_HANDLE, installed_at: Time.current)
        expect(duplicate).not_to be_valid
      end
    end

    # 🔴 `installed` 是**明確 scope 不是 default_scope**：後者會被 `unscoped` 繞過，
    #   而本倉庫的 migration 與 without_tenant 區塊到處在用 unscoped。
    it "🔴 installed scope 濾掉已卸載的，而 `all` 仍看得到（軟刪不是隱形）" do
      ActsAsTenant.with_tenant(shop) do
        record = described_class.sole
        record.update!(uninstalled_at: Time.current)

        expect(record).not_to be_installed
        expect(described_class.installed.count).to eq(0)
        expect(described_class.count).to eq(1)
      end
    end

    it "🔴 app_handle 對不上字典時被外鍵擋下" do
      ActsAsTenant.with_tenant(shop) do
        record = described_class.new(app_handle: "no_such_app", installed_at: Time.current)
        # model 層先擋（belongs_to 預設必填）
        expect(record).not_to be_valid
      end

      # 繞過 validation 也擋得住——防線在資料庫
      expect {
        ActsAsTenant.without_tenant do
          described_class.where(shop_id: shop.id).update_all("app_handle = 'no_such_app'")
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe Channel do
    it "建店時自動建立，並綁上 publication 與 installation" do
      ActsAsTenant.with_tenant(shop) do
        channel = described_class.sole

        expect(channel.handle).to eq(Shop::DEFAULT_CHANNEL_HANDLE)
        expect(channel.channel_type).to eq("app")
        expect(channel.publication).to eq(Publication.online_store!)
        expect(channel.app_installation).to eq(AppInstallation.sole)
      end
    end

    it "🔴 沒有租戶時 fail-closed" do
      expect { described_class.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end

    it "handle 每店唯一" do
      ActsAsTenant.with_tenant(shop) do
        publication = Publication.online_store!
        duplicate = described_class.new(publication:, app_installation: AppInstallation.sole,
                                        handle: Shop::DEFAULT_CHANNEL_HANDLE, channel_type: "app")
        expect(duplicate).not_to be_valid
      end
    end

    it "channel_type 恰兩值" do
      expect(described_class::TYPES).to contain_exactly("app", "agentic")

      ActsAsTenant.with_tenant(shop) do
        channel = described_class.sole
        channel.channel_type = "marketplace"
        expect(channel).not_to be_valid
      end
    end

    # 🔴 本尊 `Channel.app: App!` 是**非 null**。我方的外鍵可為 NULL 只為了 agentic
    #   那個「不在已安裝清單卻在發布 modal」的實測形態（`82` §10.1）。
    #   ⇒ `app` 型管道仍然必須有安裝，否則就是把本尊的非 null 悄悄放寬了。
    it "🔴 app 型管道沒有 installation 一定不合法（對位本尊 Channel.app 非 null）" do
      ActsAsTenant.with_tenant(shop) do
        channel = described_class.sole
        channel.app_installation = nil

        expect(channel).not_to be_valid
        expect(channel.errors[:app_installation].join).to include("非 null")
      end
    end

    it "🔴 agentic 型管道**可以**沒有 installation" do
      ActsAsTenant.with_tenant(shop) do
        channel = described_class.sole
        channel.assign_attributes(app_installation: nil, channel_type: "agentic")

        expect(channel).to be_valid
      end
    end

    # 🔴 刻意不建的官方欄——寫成正向斷言，讓「有人順手加回去」時這一格轉紅並讀到理由。
    it "🔴 不建 name／supports_future_publishing（顯示名與排程能力各只有一個產生處）" do
      expect(described_class.column_names).not_to include("name"),
        "顯示名的權威是 sales_catalogs.title（本尊 Publication.name 已 deprecated → Catalog.title）"
      expect(described_class.column_names).not_to include("supports_future_publishing"),
        "本尊 Publication 與 Channel 兩邊都有這個旗標；我方只在 publications 留一份（鐵律 7）"
    end
  end

  describe "整店刪除" do
    # 🔴 四個關聯的宣告順序由外鍵決定（`shop.rb`）。順序錯了不是「刪不掉」而是
    #   **錯誤訊息指不出根因**。這一格是那段註釋的可執行版本。
    it "空店仍然刪得掉，四張表都跟著走" do
      target = create(:shop, subdomain: "chan-ident-drop")
      id = target.id

      expect { target.destroy }.not_to raise_error

      ActsAsTenant.without_tenant do
        expect(Channel.where(shop_id: id).count).to eq(0)
        expect(Publication.where(shop_id: id).count).to eq(0)
        expect(SalesCatalog.where(shop_id: id).count).to eq(0)
        expect(AppInstallation.where(shop_id: id).count).to eq(0)
      end
    end

    it "🔴 刪店不會動到平台字典（它不屬於任何一家店）" do
      before_count = PlatformApp.count
      create(:shop, subdomain: "chan-ident-drop2").destroy

      expect(PlatformApp.count).to eq(before_count)
    end
  end
end
