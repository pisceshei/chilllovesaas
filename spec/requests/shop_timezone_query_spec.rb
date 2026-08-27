# frozen_string_literal: true

require "rails_helper"

# S6b-2：`Query.shop.ianaTimezone`（排程發布的時區來源）。
#
# 🔴 本檔的核心是**一格反例**：`shops.timezone` 與 `staff_members.timezone` 兩張表都有
# 同名欄位、default 都是 `Asia/Hong_Kong` ⇒ **拿錯那一個，在 default 環境下 100% 測綠**。
# 因此下面刻意把兩者設成不同值。症狀（若拿錯）是商品在錯的時區時刻上架，
# 而商家看到的排程時間與實際發布時間差好幾個小時。
RSpec.describe "Admin GraphQL shop timezone", type: :request do
  # 🔴 兩個時區刻意不同，且刻意都不是 default（`Asia/Hong_Kong`）——
  #   若實作寫死 default 或回退到它，兩格都會紅。
  let(:shop) { create(:shop, subdomain: "tz-shop", timezone: "Europe/Paris") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true, timezone: "America/New_York") }
  end

  let(:query) { <<~GRAPHQL }
    query shopTimezone { shop { ianaTimezone } }
  GRAPHQL

  before do
    host! "tz-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  it "🔴 回的是**店鋪級**時區，不是登入員工的（兩者同名同 default，拿錯測不出來）" do
    post_graphql(query)

    body = response.parsed_body
    expect(body["errors"]).to be_nil
    expect(body.dig("data", "shop", "ianaTimezone")).to eq("Europe/Paris")
    # 明確釘住「不是員工的那個」——這格才是本檔存在的理由
    expect(body.dig("data", "shop", "ianaTimezone")).not_to eq(staff.timezone)
  end

  # 🔴 本格釘住的是**安全判準**（未登入不得讀到店鋪資料），不是 HTTP 狀態碼。
  #
  # ⚠️ **與鐵律 4 第三層的既有分歧，本包不修但明文登記**：鐵律 4 要求
  # 「認證失敗、租戶停用、payload 格式錯誤回**非 200**」，而本倉庫現況是
  # **HTTP 200 ＋ top-level `errors` ＋ `code: ACCESS_DENIED`**（本輪實測）。
  # 這是**認證層的既有行為**，不是本包引入的——`Query.shop` 只是它的新消費端；
  # 改它會動到每一支 GraphQL 端點與全部既有 request spec ⇒ 依鐵律 20.5 只登記
  # （`docs/specs/91` §3.25），不在本包擴修。
  #
  # ⚠️ 附帶登記：對一個**完全沒帶憑證**的請求回「帳號或密碼錯誤。」是誤導的訊息
  # （它描述的是憑證錯誤，不是憑證缺席）。同上，登記不修。
  it "未登入時不得讀到店鋪資料（現況：200＋ACCESS_DENIED，與鐵律 4 第三層分歧，見註釋）" do
    reset!
    host! "tz-shop.lvh.me"
    https!
    post_graphql(query)

    body = response.parsed_body
    # 真正承重的兩條：沒有資料外洩、錯誤碼可機器判別
    expect(body["data"]).to be_nil
    expect(body.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
  end

  # 🔴 由審查開出：`authorize_products!` 是 `Query#shop` 的**活的授權分支**，
  #   而原本兩格都用 owner ⇒ 移掉那行照樣全綠。本格用一個沒有 `products.view` 的 staff。
  #   ⚠️ 這條也是「日後若加入與商品無關的欄位必須改成該欄位自己的 policy」的提醒：
  #   現在讀得到時區的人，恰好就是讀得到商品的人。
  it "🔴 沒有 products.view 權限的員工讀不到（authorize_products! 是活的分支）" do
    stranger = ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: false) }
    reset!
    host! "tz-shop.lvh.me"
    https!
    post login_path, params: { email: stranger.email, password: "long-password-123" }
    post_graphql(query)

    body = response.parsed_body
    expect(body.dig("data", "shop")).to be_nil
    expect(body.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
