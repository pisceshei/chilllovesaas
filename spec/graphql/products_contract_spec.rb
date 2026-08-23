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

  # 反向分頁（last/before）與正向走的是不同一支條件（apply_before vs apply_after）。
  # 2026-08-23 把兩支從 SQL 字串內插改成 Arel 時發現只有正向有覆蓋——
  # 改一個沒人測的分支，綠燈只證明另一半沒壞。
  it "paginates backwards with last/before and keeps hasPreviousPage honest" do
    oldest = create_product(shop, title: "最舊", created_at: 3.minutes.ago)
    middle = create_product(shop, title: "中間", created_at: 2.minutes.ago)
    newest = create_product(shop, title: "最新", created_at: 1.minute.ago)
    login!

    post_graphql("{ products(first: 3) { edges { cursor node { title } } } }")
    edges = response.parsed_body.dig("data", "products", "edges")
    expect(edges.map { |edge| edge.dig("node", "title") }).to eq([ newest.title, middle.title, oldest.title ])

    # 游標指向最舊那筆：往回要拿到「比它新」的兩筆，且順序仍是新→舊。
    post_graphql(
      "query($cursor: String!) { products(last: 2, before: $cursor) { nodes { title } pageInfo { hasPreviousPage hasNextPage } } }",
      variables: { cursor: edges.last.fetch("cursor") }
    )
    connection = response.parsed_body.dig("data", "products")
    expect(connection.fetch("nodes").map { |node| node.fetch("title") }).to eq([ newest.title, middle.title ])
    expect(connection.dig("pageInfo", "hasNextPage")).to be(true)
    expect(connection.dig("pageInfo", "hasPreviousPage")).to be(false)
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
      .to eq(GraphqlLimits.fetch(:cost_bucket_capacity))
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

  # 🔴 UNLISTED 走完整的 request → schema → JSON 路徑。
  # `spec/models/product_spec.rb` 已經斷言 enum 的值域，但那是**類別層**的斷言——
  # 它證明不了「第四個值真的能穿過 GraphQL 序列化出去」。
  # 本輪之前 enum 只有三值，任何 status 為 unlisted 的商品查詢都會拿到序列化錯誤，
  # 而**沒有任何測試會發現**（既有 7 條全部只用 draft 的商品）。
  it "serialises the fourth product status (UNLISTED) end to end" do
    create_product(shop, title: "未列出品", status: "unlisted")
    login!

    post_graphql("{ products(first: 1) { nodes { title status } } }")

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(payload["errors"]).to be_nil
    expect(payload.dig("data", "products", "nodes", 0, "status")).to eq("UNLISTED")
  end

  it "exposes all four ProductStatus values in the introspected schema" do
    login!

    post_graphql(<<~GRAPHQL)
      query { __type(name: "ProductStatus") { enumValues { name } } }
    GRAPHQL

    names = response.parsed_body.dig("data", "__type", "enumValues").map { |value| value.fetch("name") }
    expect(names).to match_array(%w[ACTIVE DRAFT ARCHIVED UNLISTED])
  end

  # ── controller 的 rescue 收窄（2026-08-15）────────────────────────────────
  #
  # 🔴 原本 `execute` 的 rescue 子句是 `rescue JSON::ParserError, TypeError`，
  # 而它是**方法層 rescue**——`ChillloveSchema.execute` 就在方法體裡面。
  # ⇒ 任何 resolver 內部拋出的 `TypeError` 都會被渲染成 `BAD_USER_INPUT`。
  # 鐵律 3 的金額型別閘門（65 §C L3）正是靠 `raise TypeError` 擋住
  # 「把儲存值直接送 PSP」——那是 P1 級送款事故，卻會顯示成
  # 「variables 必須是有效的 JSON 物件」。
  it "still returns BAD_USER_INPUT when variables is not a JSON object" do
    login!

    post admin_graphql_path,
      params: { query: "{ products(first: 1) { nodes { id } } }", variables: "[]" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
  end

  it "still returns BAD_USER_INPUT when variables is malformed JSON" do
    login!

    post admin_graphql_path,
      params: { query: "{ products(first: 1) { nodes { id } } }", variables: "{not json" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
  end

  it "does not disguise a resolver TypeError as BAD_USER_INPUT" do
    login!
    allow(ChillloveSchema).to receive(:execute).and_raise(TypeError, "金額型別閘門")

    expect {
      post_graphql("{ products(first: 1) { nodes { id } } }")
    }.to raise_error(TypeError, "金額型別閘門")
  end

  # ── AR rescue 的收窄（2026-08-15）─────────────────────────────────────────
  #
  # 🔴 原本是 `rescue ActiveRecord::ActiveRecordError`，而它是**方法層** rescue
  # ⇒ resolver 內部拋出的**任何** AR 例外都被渲染成 `INTERNAL`／HTTP 200，
  # 而 `render_internal_error` 只 log `error_class`，訊息一個字都不留。
  # 這與上面那條 `TypeError` 是同一種病，只是型別換了一個。
  #
  # ℹ️ 這些例外今天還不可達（`ChillloveSchema.mutation` 為 `nil`，唯讀 schema），
  # 但**第一支 mutation 掛上 root 當天就引爆** ⇒ 現在就把契約釘住。
  # 🔴 斷言直接陳述「有沒有被吞」，**不假設它會往外拋**——
  # Rails 在 test 環境對部分 AR 例外有自己的 `rescue_responses` 對映
  # （`RecordNotFound` → 404 等），會由框架 render 而不是往外拋。
  # 那**同樣不是「被吞成 INTERNAL」**，本檔在意的是後者。
  def swallowed_as_internal?
    post_graphql("{ products(first: 1) { nodes { id } } }")
    response.status == 200 &&
      response.parsed_body.dig("errors", 0, "extensions", "code") == "INTERNAL"
  rescue ActiveRecord::ActiveRecordError
    false # 往外拋 ＝ 沒被吞
  end

  {
    "RecordInvalid（業務驗證失敗）" => -> { ActiveRecord::RecordInvalid.new },
    "StaleObjectError（樂觀鎖，28 §0.3.2 應走 STALE_OBJECT userErrors）" =>
      -> { ActiveRecord::StaleObjectError.new(nil, "update") },
    "RecordNotFound" => -> { ActiveRecord::RecordNotFound.new("nope") },
    # 🔴 `RecordNotUnique <= StatementInvalid` 為 **true**（實測）⇒ 它需要**專屬子句**，
    # 否則會被基礎設施那條原封不動再吞一次，而 `63` §A.1 ④ 明文要求它轉成
    # userErrors、「不得漏成 500」。
    "RecordNotUnique（63 §A.1 ④；它是 StatementInvalid 的子類）" =>
      -> { ActiveRecord::RecordNotUnique.new("Duplicate entry") }
  }.each do |label, build|
    it "不把 #{label} 吞成 INTERNAL" do
      login!
      allow(ChillloveSchema).to receive(:execute).and_raise(build.call)

      expect(swallowed_as_internal?).to be(false)
    end
  end

  it "仍然把基礎設施錯誤轉成去敏 INTERNAL（ConnectionNotEstablished）" do
    login!
    allow(ChillloveSchema).to receive(:execute)
      .and_raise(ActiveRecord::ConnectionNotEstablished, "secret host detail")

    post_graphql("{ products(first: 1) { nodes { id } } }")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("INTERNAL")
    expect(response.body).not_to include("secret host detail")
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
