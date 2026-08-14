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

  # 🔴 這個測試在裁定 D8（身分表升組織層）之後**改變了要證明的東西**。
  #
  # 舊模型：session 帶 shop_id，跨店 token 在資料庫層就解析不到——由 acts_as_tenant 擋。
  # 新模型：session 是組織層的，一次登入對應一個「人」，所以 token **本來就解析得到**；
  #        「這個人能不能進這間店」改由 Current.can_access_shop? 在每個 request 判定。
  #
  # 所以這裡不再測「解析不到」（那會是測一個已經不存在的機制），
  # 改測**安全網本身**：token 解析得到 ✓，但對未指派的店 fail-closed ✗。
  # 這一條就是 docs/specs/85 §4「把配套條款②從紀律變成機制」的驗收點。
  it "resolves org-level tokens but denies shops the staff has no assignment for" do
    _record, raw_token = described_class.issue!(staff_member: staff, request:)
    other_shop = create(:shop)

    resolved = described_class.authenticate(raw_token)
    expect(resolved).to be_present
    expect(resolved.staff_member).to eq(staff)

    Current.staff = staff
    expect(Current.can_access_shop?(shop.id)).to be(true)
    expect(Current.can_access_shop?(other_shop.id)).to be(false)
  ensure
    Current.reset
  end

  it "fails closed when the staff has no store assignment at all" do
    orphan = create(:staff_member) # 不傳 shop: ⇒ 沒有任何 UserStoreAssignment

    Current.staff = orphan
    expect(Current.accessible_shop_ids).to eq([])
    expect(Current.can_access_shop?(shop.id)).to be(false)
    expect(Current.can_access_shop?(nil)).to be(false)
  ensure
    Current.reset
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
