# frozen_string_literal: true

require "rails_helper"

# G6-3（步 2）：付款設定本體——capture 模式／manual 付款方式／provider 啟用狀態機。
#
# 🔴 假綠殺手（鐵律 20.2⑤，逐格對應突變）：
#   S1 capture 值域拒絕（殺：拿掉 INCLUSION 檢查——任意字串落庫）
#   S2 Plus 專屬值誠實拒絕（殺：four-value 全收——收下一個沒有行為的設定）
#   S3 provider activate 前置＝憑證指紋（殺：無憑證也可 active——結帳段炸在 API 呼叫）
#   S4 deactivate 保留設定值（殺：停用改成刪列——86 §3 逐字「will be saved」）
#   S5 內建型別每店恰一（殺：重複建列——⊕ 選單消失語義破功）
#   S6 custom 保留名擋下（殺：放行「cash」——與官方保留名撞名）
RSpec.describe "payment settings（G6-3 步 2）", type: :request do
  let(:shop) { create(:shop, subdomain: "payset") }
  let!(:owner) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "payset.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    post login_path, params: { email: owner.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def gql!(query, variables = {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  # ── capture method ──────────────────────────────────────────────

  PAYSET_CAPTURE_GQL = <<~GQL
    mutation($captureMethod: String!) {
      paymentCaptureMethodUpdate(captureMethod: $captureMethod) {
        paymentCaptureMethod
        userErrors { field message code }
      }
    }
  GQL

  it "預設值＝automatic_at_checkout（migration default；86 §2 radio 預設✓）" do
    payload = gql!("query { paymentCaptureMethod }")
    expect(payload.dig("data", "paymentCaptureMethod")).to eq("automatic_at_checkout")
  end

  it "更新為 manual ⇒ 落庫且 query 讀得回" do
    payload = gql!(PAYSET_CAPTURE_GQL, { captureMethod: "manual" })
    expect(payload.dig("data", "paymentCaptureMethodUpdate", "userErrors")).to eq([])
    expect(shop.reload.payment_capture_method).to eq("manual")
    expect(gql!("query { paymentCaptureMethod }").dig("data", "paymentCaptureMethod")).to eq("manual")
  end

  it "🔴 S1 值域外字串 ⇒ INCLUSION 且不落庫" do
    payload = gql!(PAYSET_CAPTURE_GQL, { captureMethod: "whenever_i_feel_like_it" })
    expect(payload.dig("data", "paymentCaptureMethodUpdate", "userErrors", 0, "code")).to eq("INCLUSION")
    expect(shop.reload.payment_capture_method).to eq("automatic_at_checkout")
  end

  it "🔴 S2 automatic_per_fulfillment（Plus 專屬）⇒ FEATURE_NOT_ENABLED——它在 limits 值域內，靠 INCLUSION 殺不到" do
    payload = gql!(PAYSET_CAPTURE_GQL, { captureMethod: "automatic_per_fulfillment" })
    expect(payload.dig("data", "paymentCaptureMethodUpdate", "userErrors", 0, "code")).to eq("FEATURE_NOT_ENABLED")
    expect(shop.reload.payment_capture_method).to eq("automatic_at_checkout")
  end

  # ── manual payment methods ──────────────────────────────────────

  PAYSET_METHOD_CREATE_GQL = <<~GQL
    mutation($methodType: String!, $name: String, $additionalDetails: String, $paymentInstructions: String) {
      shopPaymentMethodCreate(methodType: $methodType, name: $name,
                              additionalDetails: $additionalDetails, paymentInstructions: $paymentInstructions) {
        shopPaymentMethod { id methodType name active }
        userErrors { field message code }
      }
    }
  GQL

  it "內建型別省略 name ⇒ 正典顯示名（86 §3 選單逐字）＋預設啟用" do
    payload = gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "bank_deposit" })
    method = payload.dig("data", "shopPaymentMethodCreate", "shopPaymentMethod")
    expect(payload.dig("data", "shopPaymentMethodCreate", "userErrors")).to eq([])
    expect(method["name"]).to eq("Bank Deposit")
    expect(method["active"]).to be(true)
  end

  it "🔴 S5 同店第二個 bank_deposit ⇒ userError（每店至多一列＝選單消失語義）" do
    gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "bank_deposit" })
    payload = gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "bank_deposit" })
    expect(payload.dig("data", "shopPaymentMethodCreate", "userErrors")).not_to be_empty
    count = ActsAsTenant.with_tenant(shop) { ShopPaymentMethod.where(method_type: "bank_deposit").count }
    expect(count).to eq(1)
  end

  it "custom 未命名 ⇒ BLANK" do
    payload = gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "custom" })
    expect(payload.dig("data", "shopPaymentMethodCreate", "userErrors", 0, "code")).to eq("BLANK")
  end

  it "🔴 S6 custom 撞官方保留名（大小寫不敏感）⇒ userError" do
    payload = gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "custom", name: "CASH" })
    expect(payload.dig("data", "shopPaymentMethodCreate", "userErrors")).not_to be_empty
  end

  it "值域外 methodType ⇒ INCLUSION" do
    payload = gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "carrier_pigeon" })
    expect(payload.dig("data", "shopPaymentMethodCreate", "userErrors", 0, "code")).to eq("INCLUSION")
  end

  it "🔴 S4 deactivate 保留設定值（86 §3 逐字語義）；activate 還原；列不刪" do
    created = gql!(PAYSET_METHOD_CREATE_GQL,
                   { methodType: "cash_on_delivery",
                     additionalDetails: "門市取貨付現", paymentInstructions: "請備妥零錢" })
    gid = created.dig("data", "shopPaymentMethodCreate", "shopPaymentMethod", "id")

    off = gql!(<<~GQL, { id: gid })
      mutation($id: ID!) {
        shopPaymentMethodDeactivate(id: $id) {
          shopPaymentMethod { id active additionalDetails paymentInstructions }
          userErrors { field message code }
        }
      }
    GQL
    method = off.dig("data", "shopPaymentMethodDeactivate", "shopPaymentMethod")
    expect(method["active"]).to be(false)
    expect(method["additionalDetails"]).to eq("門市取貨付現")
    expect(method["paymentInstructions"]).to eq("請備妥零錢")

    on = gql!(<<~GQL, { id: gid })
      mutation($id: ID!) {
        shopPaymentMethodActivate(id: $id) {
          shopPaymentMethod { id active }
          userErrors { field message code }
        }
      }
    GQL
    expect(on.dig("data", "shopPaymentMethodActivate", "shopPaymentMethod", "active")).to be(true)
  end

  it "update 省略的欄不變（部分更新協定）；不存在的 id ⇒ NOT_FOUND" do
    created = gql!(PAYSET_METHOD_CREATE_GQL,
                   { methodType: "money_order", additionalDetails: "原始說明" })
    gid = created.dig("data", "shopPaymentMethodCreate", "shopPaymentMethod", "id")

    updated = gql!(<<~GQL, { id: gid, paymentInstructions: "新指示" })
      mutation($id: ID!, $paymentInstructions: String) {
        shopPaymentMethodUpdate(id: $id, paymentInstructions: $paymentInstructions) {
          shopPaymentMethod { additionalDetails paymentInstructions }
          userErrors { field message code }
        }
      }
    GQL
    method = updated.dig("data", "shopPaymentMethodUpdate", "shopPaymentMethod")
    expect(method["additionalDetails"]).to eq("原始說明")
    expect(method["paymentInstructions"]).to eq("新指示")

    missing = gql!(<<~GQL, { id: "gid://chilllove/ShopPaymentMethod/999999" })
      mutation($id: ID!) {
        shopPaymentMethodActivate(id: $id) {
          shopPaymentMethod { id }
          userErrors { field message code }
        }
      }
    GQL
    expect(missing.dig("data", "shopPaymentMethodActivate", "userErrors", 0, "code")).to eq("NOT_FOUND")
  end

  it "shopPaymentMethods query 含停用列（admin 端要顯示兩段）" do
    gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "bank_deposit" })
    created = gql!(PAYSET_METHOD_CREATE_GQL, { methodType: "money_order" })
    gid = created.dig("data", "shopPaymentMethodCreate", "shopPaymentMethod", "id")
    gql!(<<~GQL, { id: gid })
      mutation($id: ID!) {
        shopPaymentMethodDeactivate(id: $id) { shopPaymentMethod { id } userErrors { code } }
      }
    GQL

    payload = gql!("query { shopPaymentMethods { name active } }")
    rows = payload.dig("data", "shopPaymentMethods")
    expect(rows.map { |row| row["name"] }).to contain_exactly("Bank Deposit", "Money Order")
    expect(rows.map { |row| row["active"] }).to contain_exactly(true, false)
  end

  # ── provider activation 狀態機 ──────────────────────────────────

  PAYSET_PROVIDER_ACTIVATE_GQL = <<~GQL
    mutation($provider: String!) {
      shopPaymentProviderActivate(provider: $provider) {
        shopPaymentProvider { provider status }
        userErrors { field message code }
      }
    }
  GQL

  def create_provider!(with_secret:)
    ActsAsTenant.with_tenant(shop) do
      row = ShopPaymentProvider.new(provider: "airwallex", client_id: "cid")
      row.api_secret = "key" if with_secret
      row.save!
      row
    end
  end

  it "🔴 S3 無憑證的 activate ⇒ INVALID_STATE 且 status 不動" do
    row = create_provider!(with_secret: false)
    payload = gql!(PAYSET_PROVIDER_ACTIVATE_GQL, { provider: "airwallex" })
    expect(payload.dig("data", "shopPaymentProviderActivate", "userErrors", 0, "code")).to eq("INVALID_STATE")
    expect(row.reload.status).to eq("inactive")
  end

  it "有憑證 ⇒ activate 成功；deactivate 回 inactive 且憑證保留" do
    row = create_provider!(with_secret: true)
    payload = gql!(PAYSET_PROVIDER_ACTIVATE_GQL, { provider: "airwallex" })
    expect(payload.dig("data", "shopPaymentProviderActivate", "userErrors")).to eq([])
    expect(row.reload.status).to eq("active")

    off = gql!(<<~GQL, { provider: "airwallex" })
      mutation($provider: String!) {
        shopPaymentProviderDeactivate(provider: $provider) {
          shopPaymentProvider { provider status }
          userErrors { field message code }
        }
      }
    GQL
    expect(off.dig("data", "shopPaymentProviderDeactivate", "userErrors")).to eq([])
    row.reload
    expect(row.status).to eq("inactive")
    expect(row.api_secret_fingerprint).to be_present
  end

  it "未落列的 provider ⇒ NOT_FOUND" do
    payload = gql!(PAYSET_PROVIDER_ACTIVATE_GQL, { provider: "airwallex" })
    expect(payload.dig("data", "shopPaymentProviderActivate", "userErrors", 0, "code")).to eq("NOT_FOUND")
  end
end
