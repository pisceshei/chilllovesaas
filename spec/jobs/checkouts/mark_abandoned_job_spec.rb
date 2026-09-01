# frozen_string_literal: true

require "rails_helper"

# G6 步 7：棄單判定 job（官方 10 分鐘規則；89 §6 逐字）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   A1 閾值生效（殺：不看時間——剛開的結帳被標棄單）
#   A2 email 前置（殺：無 email 也標——官方判定以「提供 email 後」起算）
RSpec.describe Checkouts::MarkAbandonedJob do
  let(:shop) { create(:shop, subdomain: "abnd") }

  def build_checkout(email:, age_minutes:, status: "open")
    checkout = ActsAsTenant.with_tenant(shop) do
      Checkout.create!(shop_id: shop.id, token: SecureRandom.hex(24), status:,
                       currency: "HKD", email:,
                       line_items_snapshot: [ { "title" => "品", "quantity" => 1,
                                                "unit_price_cents" => 5000 } ])
    end
    ActsAsTenant.without_tenant do
      Checkout.where(id: checkout.id).update_all([ "updated_at = ?", age_minutes.minutes.ago ])
    end
    checkout
  end

  it "🔴 A1 逾 10 分鐘（limits checkout.abandoned_after_minutes）才標；9 分鐘不標" do
    stale = build_checkout(email: "a@example.com", age_minutes: 11)
    fresh = build_checkout(email: "b@example.com", age_minutes: 9)

    described_class.perform_now

    ActsAsTenant.without_tenant do
      expect(stale.reload.abandoned_at).to be_present
      expect(fresh.reload.abandoned_at).to be_nil,
        "未逾閾值就標棄單＝顧客還在打字就收到挽回信"
    end
  end

  it "🔴 A2 無 email 不標（官方：判定自「提供 email」起算）" do
    no_email = build_checkout(email: nil, age_minutes: 60)
    described_class.perform_now
    ActsAsTenant.without_tenant { expect(no_email.reload.abandoned_at).to be_nil }
  end

  it "A3 completed 不標；已標者時戳不動（冪等）" do
    done = build_checkout(email: "c@example.com", age_minutes: 60, status: "completed")
    marked = build_checkout(email: "d@example.com", age_minutes: 60)
    described_class.perform_now
    first_mark = ActsAsTenant.without_tenant { marked.reload.abandoned_at }

    travel_to(5.minutes.from_now) { described_class.perform_now }

    ActsAsTenant.without_tenant do
      expect(done.reload.abandoned_at).to be_nil
      expect(marked.reload.abandoned_at).to be_within(1.second).of(first_mark)
    end
  end
end
