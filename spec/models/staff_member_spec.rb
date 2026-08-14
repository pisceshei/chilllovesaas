require "rails_helper"

RSpec.describe StaffMember, type: :model do
  let(:shop) { create(:shop) }

  it "requires a password of at least ten characters" do
    ActsAsTenant.with_tenant(shop) do
      staff = described_class.new(
        email: "short@example.test",
        password: "short",
        password_confirmation: "short",
        status: "active"
      )

      expect(staff).not_to be_valid
      expect(staff.errors[:password]).to be_present
    end
  end

  it "normalizes email and accepts only active non-deactivated accounts" do
    staff = ActsAsTenant.with_tenant(shop) do
      create(:staff_member, shop:, email: "  OWNER@EXAMPLE.TEST ")
    end

    expect(staff.email).to eq("owner@example.test")
    expect(staff).to be_active_for_authentication

    ActsAsTenant.with_tenant(shop) { staff.update!(deactivated_at: Time.current) }
    expect(staff).not_to be_active_for_authentication
  end
end
