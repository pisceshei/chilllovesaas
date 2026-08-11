require "rails_helper"

RSpec.describe "Admin GraphQL products contract", type: :request do
  let(:shop) { create(:shop, subdomain: "graphql-shop") }
  let(:other_shop) { create(:shop, subdomain: "other-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "graphql-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "returns HTTP 200 ACCESS_DENIED and cost when unauthenticated" do
    post admin_graphql_path, params: { query: "{ products(first: 1) { nodes { id } } }" }

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-CL-API-Version"]).to eq("2026-08")
    expect(payload.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
    expect(payload.dig("extensions", "cost")).to include(
      "requestedQueryCost", "actualQueryCost", "throttleStatus"
    )
  end

  it "uses opaque keyset cursors, GIDs, and never leaks another shop's product" do
    first_product = create_product(shop, title: "第一件", created_at: 2.minutes.ago)
    second_product = create_product(shop, title: "第二件", created_at: 1.minute.ago)
    other_product = create_product(other_shop, title: "別店商品", created_at: Time.current)
    login!

    sql = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      sql << payload[:sql] if payload[:sql].to_s.match?(/\bproducts\b/i)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      post_graphql(<<~GRAPHQL)
        query {
          products(first: 1) {
            nodes { id legacyResourceId title status }
            pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
          }
        }
      GRAPHQL
    end

    payload = response.parsed_body
    connection = payload.dig("data", "products")
    expect(connection.fetch("nodes").map { |node| node.fetch("title") }).to eq([ second_product.title ])
    expect(connection.dig("nodes", 0, "id")).to eq("gid://chilllove/Product/#{second_product.id}")
    expect(connection.dig("nodes", 0, "legacyResourceId")).to eq(second_product.id.to_s)
    expect(connection.dig("nodes", 0, "status")).to eq("DRAFT")
    expect(connection.dig("pageInfo", "hasNextPage")).to be(true)
    expect(sql.grep(/\bOFFSET\b/i)).to be_empty

    cursor = connection.dig("pageInfo", "endCursor")
    post_graphql(
      "query($cursor: String!) { products(first: 1, after: $cursor) { nodes { title } pageInfo { hasNextPage } } }",
      variables: { cursor: }
    )
    expect(response.parsed_body.dig("data", "products", "nodes", 0, "title")).to eq(first_product.title)
    expect(response.parsed_body.to_s).not_to include("別店商品")

    post_graphql(
      "query($id: ID!) { node(id: $id) { id ... on Product { title } } }",
      variables: { id: "gid://chilllove/Product/#{other_product.id}" }
    )
    expect(response.parsed_body.dig("data", "node")).to be_nil
  end

  it "enforces the configured maximum page size as a top-level HTTP 200 error" do
    login!

    post_graphql("{ products(first: 251) { nodes { id } } }")

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(payload.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    expect(payload.dig("extensions", "cost", "throttleStatus", "maximumAvailable"))
      .to eq(GraphqlLimits.fetch(:bucket_capacity))
  end

  it "rejects a revoked session immediately" do
    login!
    ActsAsTenant.with_tenant(shop) { Session.find_by!(staff_member: staff).revoke! }

    post_graphql("{ products(first: 1) { nodes { id } } }")

    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
  end

  it "enforces the server-side product policy inside the resolver" do
    ActsAsTenant.with_tenant(shop) { staff.update!(owner: false) }
    login!

    post_graphql("{ products(first: 1) { nodes { id } } }")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
  end

  it "requires CSRF for the session-authenticated endpoint" do
    login!
    controller = Admin::Api::V202608::GraphqlController
    original = controller.allow_forgery_protection
    controller.allow_forgery_protection = true

    post_graphql("{ products(first: 1) { nodes { id } } }")

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-CL-API-Version"]).to eq("2026-08")
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
  ensure
    controller.allow_forgery_protection = original if controller
  end

  it "redacts database failure details in an HTTP 200 INTERNAL error" do
    login!
    allow(ChillloveSchema).to receive(:execute)
      .and_raise(ActiveRecord::StatementInvalid, "secret database detail")

    post_graphql("{ products(first: 1) { nodes { id } } }")

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(payload.dig("errors", 0, "extensions", "code")).to eq("INTERNAL")
    expect(payload.dig("errors", 0, "extensions", "requestId")).to be_present
    expect(payload.dig("errors", 0, "message")).to eq("伺服器暫時無法完成請求。")
    expect(response.body).not_to include("secret database detail")
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path,
      params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end

  def create_product(owner_shop, **attributes)
    ActsAsTenant.with_tenant(owner_shop) do
      create(:product, shop: owner_shop, **attributes)
    end
  end
end
