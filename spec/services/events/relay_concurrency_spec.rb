# frozen_string_literal: true

require "rails_helper"

# 第 19 包 §6-1：SKIP LOCKED 併發不重複取件。
# 🔴 跨連線列鎖：transactional fixtures 下另一連線看不到未 commit 資料
#    （同 adjust_concurrency_spec 骨架）；殘留清理照該檔的 purge 全表清單。
RSpec.describe Events::Relay, "concurrency" do
  self.use_transactional_tests = false

  def purge!
    ActsAsTenant.without_tenant { EventOutbox.delete_all }
    # 🔴 發布列必須排在 Publication 之前刪（第 12 包）：Product／ProductVariant／
    #    Collection 的 after_create 會建 resource_publications，而本幫手用的是
    #    `delete_all`（繞過 dependent: :destroy）⇒ 殘列讓 fk_res_pub_publication_id 擋住刪除。
    ResourcePublication.unscoped.delete_all
    # 2026-08-26 S0：四張新表的刪除順序由外鍵決定，等於建立順序的**反序**：
    #   channels → publications → sales_catalogs → app_installations
    #   （同 `app/models/shop.rb` 的關聯宣告順序，完整理由見該處）。
    Channel.unscoped.delete_all
    Publication.unscoped.delete_all
    SalesCatalog.unscoped.delete_all
    AppInstallation.unscoped.delete_all
    UserStoreAssignment.unscoped.delete_all
    StaffMember.unscoped.delete_all
    Location.unscoped.delete_all
    TranslationStatus.unscoped.delete_all
    ShopLocale.unscoped.delete_all
    Shop.delete_all
  end

  before { purge! }
  after { purge! }

  it "兩個並行 drain 不重複取件（FOR UPDATE SKIP LOCKED）" do
    shop = create(:shop, subdomain: "ev-relay-conc")
    ActsAsTenant.with_tenant(shop) do
      5.times do |i|
        EventOutbox.create!(event_id: SecureRandom.uuid, topic: "products/update",
                            aggregate_type: "Product", aggregate_id: i,
                            payload: {}, available_at: Time.current, status: "pending")
      end
    end
    slow = Object.new
    slow.instance_variable_set(:@x, nil)
    def slow.name = "test.slow"
    def slow.call(_event) = sleep(0.05)
    allow(described_class).to receive(:consumers_for).and_return([ slow ])
    counts = []
    threads = 2.times.map { Thread.new { counts << described_class.drain! } }
    threads.each(&:join)
    published = ActsAsTenant.without_tenant { EventOutbox.where(status: "published").count }
    expect(published).to eq(5)
    expect(counts.sum).to eq(5)
  end
end
