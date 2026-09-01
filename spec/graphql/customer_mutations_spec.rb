# frozen_string_literal: true

require "rails_helper"

# G6 步 8a：顧客 mutation 面（官方 11 支對位）。
#
# 🔴 假綠殺手：
#   M4 有訂單擋刪（殺：照刪——官方 "You can only delete customers who haven't
#      placed any orders."）
#   M6 抹除窗＝limits customer.erasure_cancel_days（殺：硬編碼/忽略 limits）
#   M5d 預設地址讓渡（殺：刪預設後地址簿無預設——checkout 預填斷）
RSpec.describe "customer mutations", type: :request do
  let(:shop) { create(:shop, subdomain: "custmut") }
  let!(:owner) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "custmut.lvh.me"
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

  CUSTMUT_CREATE_GQL = <<~GQL
    mutation($email: String, $firstName: String, $phone: String, $tags: [String!], $emailMarketingConsent: MarketingConsentInput) {
      customerCreate(email: $email, firstName: $firstName, phone: $phone, tags: $tags,
                     emailMarketingConsent: $emailMarketingConsent) {
        customer { id email emailMarketingState tags }
        userErrors { field message code }
      }
    }
  GQL

  def create_customer!(email: "a@example.com", **kw)
    payload = gql!(CUSTMUT_CREATE_GQL, { email:, firstName: "客", **kw })
    expect(payload.dig("data", "customerCreate", "userErrors")).to eq([])
    payload.dig("data", "customerCreate", "customer", "id")
  end

  it "M1 建立（帶 consent）⇒ 事件落表＋狀態投影；同 email 再建 ⇒ TAKEN" do
    gid = create_customer!(emailMarketingConsent: { marketingState: "SUBSCRIBED" })
    numeric = gid[%r{/(\d+)\z}, 1].to_i
    ActsAsTenant.without_tenant do
      expect(Customer.find(numeric).email_marketing_state).to eq("subscribed")
      expect(CustomerMarketingConsent.where(customer_id: numeric).count).to eq(1)
    end

    dup = gql!(CUSTMUT_CREATE_GQL, { email: "a@example.com", firstName: "重" })
    expect(dup.dig("data", "customerCreate", "userErrors", 0, "code")).to eq("TAKEN")
  end

  it "M2 三擇一必填：全空 ⇒ INVALID（官方底線句）" do
    payload = gql!(CUSTMUT_CREATE_GQL, {})
    expect(payload.dig("data", "customerCreate", "userErrors", 0, "code")).to eq("INVALID")
  end

  it "M3 update：tags 覆寫語義（官方逐字）；省略欄不變" do
    gid = create_customer!(tags: [ "vip", "old" ])
    payload = gql!(<<~GQL, { id: gid, tags: [ "new" ] })
      mutation($id: ID!, $tags: [String!]) {
        customerUpdate(id: $id, tags: $tags) {
          customer { tags email }
          userErrors { field message code }
        }
      }
    GQL
    customer = payload.dig("data", "customerUpdate", "customer")
    expect(customer["tags"]).to eq([ "new" ])
    expect(customer["email"]).to eq("a@example.com")
  end

  CUSTMUT_DELETE_GQL = <<~GQL
    mutation($id: ID!) {
      customerDelete(id: $id) {
        deletedCustomerId
        userErrors { field message code }
      }
    }
  GQL

  it "🔴 M4 有訂單 ⇒ INVALID_STATE 不刪；無訂單 ⇒ 刪除＋附屬清乾淨" do
    gid = create_customer!
    numeric = gid[%r{/(\d+)\z}, 1].to_i
    ActsAsTenant.with_tenant(shop) do
      Order.create!(
        shop_id: shop.id, customer_id: numeric, name: "#9901", order_number: 9901,
        currency: "HKD", presentment_currency: "HKD", subtotal_cents: 1000,
        total_cents: 1000, presentment_total_cents: 1000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
    end
    blocked = gql!(CUSTMUT_DELETE_GQL, { id: gid })
    expect(blocked.dig("data", "customerDelete", "userErrors", 0, "code")).to eq("INVALID_STATE")

    gid2 = create_customer!(email: "b@example.com")
    ok = gql!(CUSTMUT_DELETE_GQL, { id: gid2 })
    expect(ok.dig("data", "customerDelete", "deletedCustomerId")).to eq(gid2)
    numeric2 = gid2[%r{/(\d+)\z}, 1].to_i
    ActsAsTenant.without_tenant { expect(Customer.find_by(id: numeric2)).to be_nil }
  end

  CUSTMUT_ADDR_CREATE_GQL = <<~GQL
    mutation($customerId: ID!, $address: CustomerAddressInput!, $setAsDefault: Boolean) {
      customerAddressCreate(customerId: $customerId, address: $address, setAsDefault: $setAsDefault) {
        customerAddress { id default }
        userErrors { field message code }
      }
    }
  GQL

  it "🔴 M5 地址簿：首址自動預設；setDefault 切換；刪預設 ⇒ 讓給存活者" do
    gid = create_customer!(email: "addr@example.com")
    first = gql!(CUSTMUT_ADDR_CREATE_GQL, { customerId: gid,
      address: { address1: "1 First St", city: "HK", countryCode: "HK" } })
    a1 = first.dig("data", "customerAddressCreate", "customerAddress")
    expect(a1["default"]).to be(true) # 首址自動預設

    second = gql!(CUSTMUT_ADDR_CREATE_GQL, { customerId: gid, setAsDefault: true,
      address: { address1: "2 Second St", city: "KLN", countryCode: "HK" } })
    a2 = second.dig("data", "customerAddressCreate", "customerAddress")
    expect(a2["default"]).to be(true)

    deleted = gql!(<<~GQL, { customerId: gid, addressId: a2["id"] })
      mutation($customerId: ID!, $addressId: ID!) {
        customerAddressDelete(customerId: $customerId, addressId: $addressId) {
          deletedAddressId
          userErrors { field message code }
        }
      }
    GQL
    expect(deleted.dig("data", "customerAddressDelete", "deletedAddressId")).to eq(a2["id"])
    numeric = gid[%r{/(\d+)\z}, 1].to_i
    survivor_default = ActsAsTenant.without_tenant do
      CustomerAddress.find_by(customer_id: numeric).default_address
    end
    expect(survivor_default).to be(true), "刪預設後無預設＝checkout 預填斷鏈"
  end

  it "🔴 M6 抹除請求 ⇒ 排程 10 天後（limits）；取消清空；重複請求 INVALID_STATE" do
    gid = create_customer!(email: "erase@example.com")
    req = gql!(<<~GQL, { customerId: gid })
      mutation($customerId: ID!) {
        customerRequestDataErasure(customerId: $customerId) {
          customer { redactionScheduledAt }
          userErrors { field message code }
        }
      }
    GQL
    at = req.dig("data", "customerRequestDataErasure", "customer", "redactionScheduledAt")
    expect(at).to be_present
    days = Limits.fetch(:customer, :erasure_cancel_days).to_i
    expect(Time.iso8601(at)).to be_within(5.minutes).of(days.days.from_now)

    dup = gql!(<<~GQL, { customerId: gid })
      mutation($customerId: ID!) {
        customerRequestDataErasure(customerId: $customerId) {
          customer { id }
          userErrors { field message code }
        }
      }
    GQL
    expect(dup.dig("data", "customerRequestDataErasure", "userErrors", 0, "code")).to eq("INVALID_STATE")

    cancel = gql!(<<~GQL, { customerId: gid })
      mutation($customerId: ID!) {
        customerCancelDataErasure(customerId: $customerId) {
          customer { redactionScheduledAt }
          userErrors { field message code }
        }
      }
    GQL
    expect(cancel.dig("data", "customerCancelDataErasure", "customer", "redactionScheduledAt")).to be_nil
  end

  it "consent mutation：SMS 無電話 ⇒ INVALID_STATE（官方前置）" do
    gid = create_customer!(email: "nophone@example.com")
    payload = gql!(<<~GQL, { customerId: gid, smsMarketingConsent: { marketingState: "SUBSCRIBED" } })
      mutation($customerId: ID!, $smsMarketingConsent: MarketingConsentInput!) {
        customerSmsMarketingConsentUpdate(customerId: $customerId, smsMarketingConsent: $smsMarketingConsent) {
          customer { smsMarketingState }
          userErrors { field message code }
        }
      }
    GQL
    expect(payload.dig("data", "customerSmsMarketingConsentUpdate", "userErrors", 0, "code"))
      .to eq("INVALID_STATE")
  end


  it "🔴 步 8b customerMerge：搬移＋保留 email 方；待抹除方 ⇒ INVALID_STATE" do
    kept_gid = create_customer!(email: "merge-kept@example.com")
    gone_gid = create_customer!(email: "merge-gone@example.com")
    gone_numeric = gone_gid[%r{/(\d+)\z}, 1].to_i
    ActsAsTenant.without_tenant do
      Customer.where(id: gone_numeric).update_all(email: nil) # 變成無 email 方
    end

    m = <<~GQL
      mutation($customerOneId: ID!, $customerTwoId: ID!) {
        customerMerge(customerOneId: $customerOneId, customerTwoId: $customerTwoId) {
          customer { id }
          userErrors { field message code }
        }
      }
    GQL
    ok = gql!(m, { customerOneId: gone_gid, customerTwoId: kept_gid })
    expect(ok.dig("data", "customerMerge", "userErrors")).to eq([])
    expect(ok.dig("data", "customerMerge", "customer", "id")).to eq(kept_gid)

    blocked_gid = create_customer!(email: "merge-blocked@example.com")
    blocked_numeric = blocked_gid[%r{/(\d+)\z}, 1].to_i
    ActsAsTenant.without_tenant do
      Customer.where(id: blocked_numeric).update_all(redaction_scheduled_at: 3.days.from_now)
    end
    blocked = gql!(m, { customerOneId: kept_gid, customerTwoId: blocked_gid })
    expect(blocked.dig("data", "customerMerge", "userErrors", 0, "code")).to eq("INVALID_STATE")
  end

  it "步 8b locale：create 帶 locale 落庫、update 可改（Edit customer modal 對位）" do
    gid = create_customer!(email: "locale@example.com")
    payload = gql!(<<~GQL, { id: gid, locale: "zh-Hant" })
      mutation($id: ID!, $locale: String) {
        customerUpdate(id: $id, locale: $locale) {
          customer { locale }
          userErrors { field message code }
        }
      }
    GQL
    expect(payload.dig("data", "customerUpdate", "customer", "locale")).to eq("zh-Hant")
  end
end
