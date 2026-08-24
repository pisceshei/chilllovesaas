# frozen_string_literal: true

require "rails_helper"

# 第 19 包 §6-1：SKIP LOCKED 併發不重複取件。
# 🔴 跨連線列鎖：transactional fixtures 下另一連線看不到未 commit 資料
#    （同 adjust_concurrency_spec 骨架）；殘留清理照該檔的 purge 全表清單。
RSpec.describe Events::Relay, "concurrency" do
  self.use_transactional_tests = false

  def purge!
    ActsAsTenant.without_tenant { EventOutbox.delete_all }
    Publication.unscoped.delete_all
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
    slow = ->(_e) { sleep 0.05 }
    allow(described_class).to receive(:consumers_for).and_return([ slow ])
    counts = []
    threads = 2.times.map { Thread.new { counts << described_class.drain! } }
    threads.each(&:join)
    published = ActsAsTenant.without_tenant { EventOutbox.where(status: "published").count }
    expect(published).to eq(5)
    expect(counts.sum).to eq(5)
  end
end
