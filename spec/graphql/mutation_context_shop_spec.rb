# frozen_string_literal: true

require "rails_helper"

# 🔴 第 25 包線上驗收抓到的形態：mutation 取租戶必須用 **`context[:current_shop]`**，
#    不得用 `Current.shop`（thread-local）。request spec 走 controller 會設 Current ⇒
#    兩種寫法都綠；**直呼 `ChillloveSchema.execute`（rails runner／背景 job／未來的
#    內部呼叫）Current 是 nil ⇒ 500**。本 spec 兩道：靜態掃描 ＋ 直呼冒煙。
RSpec.describe "Mutation 的租戶取用" do
  it "🔴 app/graphql 下不得出現 Current.shop（一律 context[:current_shop]）" do
    hits = Dir[Rails.root.join("app/graphql/**/*.rb")].select do |path|
      File.read(path).include?("Current.shop")
    end
    expect(hits).to be_empty, "改用 context.fetch(:current_shop)：#{hits.join(", ")}"
  end

  it "直呼 schema（無 controller、Current 未設）也能執行 mutation" do
    shop = create(:shop, subdomain: "ctx-shop")
    staff = ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
    doc = <<~GRAPHQL
      mutation($input: [StagedUploadInput!]!) {
        stagedUploadsCreate(input: $input) {
          stagedTargets { url resourceUrl }
          userErrors { code }
        }
      }
    GRAPHQL
    result = ActsAsTenant.with_tenant(shop) do
      ChillloveSchema.execute(doc, context: { current_shop: shop, current_staff: staff },
        variables: { input: [ { filename: "a.png", mimeType: "image/png", fileSize: 10 } ] }).to_h
    end
    expect(result["errors"]).to be_nil
    data = result.dig("data", "stagedUploadsCreate")
    expect(data["userErrors"]).to eq([])
    expect(data["stagedTargets"].sole["resourceUrl"]).to include("shops/#{shop.id}/staged/")
  end
end
