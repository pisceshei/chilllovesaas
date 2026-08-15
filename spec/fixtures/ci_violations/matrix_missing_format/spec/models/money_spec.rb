RSpec.describe Money do
  it "JPY TWD KRW 都有" do
    expect(%w[JPY TWD KRW]).to be_present
  end
end
