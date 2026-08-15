RSpec.describe Money do
  it "只測了 JPY" do
    expect(Money::Storage.from_cents(148_000, "JPY")).to be_present
  end
end
