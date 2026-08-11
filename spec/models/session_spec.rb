require "rails_helper"

RSpec.describe Session, type: :model do
  let(:shop) { create(:shop) }
  let(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:) }
  end
  let(:request) do
    ActionDispatch::TestRequest.create.tap do |value|
      value.remote_addr = "203.0.113.9"
      value.user_agent = "RSpec browser"
    end
  end

  it "persists only a SHA-256 digest and revokes immediately" do
    record, raw_token = ActsAsTenant.with_tenant(shop) do
      described_class.issue!(staff_member: staff, request:)
    end

    expect(record.token_digest).to eq(described_class.digest(raw_token))
    expect(record.attributes.values).not_to include(raw_token)
    expect(record.ip_address).to eq("203.0.113.9")
    expect(record.user_agent).to eq("RSpec browser")

    ActsAsTenant.with_tenant(shop) do
      expect(described_class.authenticate(raw_token)).to eq(record)
      record.revoke!
      expect(described_class.authenticate(raw_token)).to be_nil
    end
  end

  it "rejects expired sessions" do
    record, raw_token = ActsAsTenant.with_tenant(shop) do
      described_class.issue!(staff_member: staff, request:, expires_in: -1.second)
    end

    expect(record).not_to be_usable
    ActsAsTenant.with_tenant(shop) do
      expect(described_class.authenticate(raw_token)).to be_nil
    end
  end

  it "never resolves a raw token in another tenant" do
    _record, raw_token = ActsAsTenant.with_tenant(shop) do
      described_class.issue!(staff_member: staff, request:)
    end
    other_shop = create(:shop)

    ActsAsTenant.with_tenant(other_shop) do
      expect(described_class.authenticate(raw_token)).to be_nil
    end
  end

  it "coalesces last-active writes into five-minute windows" do
    record, = ActsAsTenant.with_tenant(shop) do
      described_class.issue!(staff_member: staff, request:)
    end

    ActsAsTenant.with_tenant(shop) do
      record.update_column(:last_active_at, 10.minutes.ago)
      expect { record.record_activity! }
        .to change { record.reload.last_active_at }

      expect(record.record_activity!).to be_nil
    end
  end
end
