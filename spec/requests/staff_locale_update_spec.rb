# frozen_string_literal: true

require "rails_helper"

# ML-1：介面語言＝員工屬性（67 §E.1）；伺服端 userErrors.message 依員工語言（docs/plans/2026-08-23-多語言方案.md §5.2）。
RSpec.describe "Admin GraphQL staffLocaleUpdate", type: :request do
  let(:shop) { create(:shop, subdomain: "locale-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  # 🔴 用 let 不用常數：describe 內的常數會洩漏到頂層，與 product_set_spec 的 MUTATION 撞名（實測互相蓋掉）。
  let(:mutation) { <<~GRAPHQL }
    mutation staffLocaleUpdate($locale: String!) {
      staffLocaleUpdate(locale: $locale) {
        locale
        userErrors { field message code }
      }
    }
  GRAPHQL

  let(:product_set_mutation) { <<~GRAPHQL }
    mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
      productSet(input: $input, idempotencyKey: $idempotencyKey) {
        product { id }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "locale-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "新員工預設 en（裁定 C3）" do
    expect(staff.locale).to eq("en")
  end

  it "切到 ja：落庫、正規化大小寫、回傳新值" do
    login!
    post_graphql(mutation, variables: { locale: "JA" })
    data = response.parsed_body.dig("data", "staffLocaleUpdate")
    expect(data["userErrors"]).to eq([])
    expect(data["locale"]).to eq("ja")
    expect(staff.reload.locale).to eq("ja")
  end

  it "值域外（de）⇒ INVALID，不落庫" do
    login!
    post_graphql(mutation, variables: { locale: "de" })
    data = response.parsed_body.dig("data", "staffLocaleUpdate")
    expect(data["locale"]).to be_nil
    expect(data["userErrors"]).to contain_exactly(a_hash_including("field" => [ "locale" ], "code" => "INVALID"))
    expect(staff.reload.locale).to eq("en")
  end

  it "伺服端 userErrors.message 依員工介面語言：en 員工收英文，zh-Hant 員工收繁中" do
    login!
    post_graphql(product_set_mutation, variables: { idempotencyKey: SecureRandom.uuid, input: { title: "", variants: [ { price: "1.00" } ] } })
    message_en = response.parsed_body.dig("data", "productSet", "userErrors").find { |e| e["code"] == "BLANK" && e["field"] == [ "title" ] }["message"]
    expect(message_en).to eq(I18n.t("errors.product.title_blank", locale: :en))

    staff.update!(locale: "zh-Hant")
    post_graphql(product_set_mutation, variables: { idempotencyKey: SecureRandom.uuid, input: { title: "", variants: [ { price: "1.00" } ] } })
    message_zh = response.parsed_body.dig("data", "productSet", "userErrors").find { |e| e["code"] == "BLANK" && e["field"] == [ "title" ] }["message"]
    expect(message_zh).to eq("標題不能為空白。")
    expect(message_zh).not_to eq(message_en)
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
