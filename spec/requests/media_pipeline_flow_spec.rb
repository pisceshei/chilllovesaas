# frozen_string_literal: true

require "rails_helper"

# 第 26 包端到端：fileCreate → outbox → relay → 消費者 → 衍生 → 讀取面。
# 🔴 這條鏈是 `Events::Consumers::REGISTRY` 第一個真實住戶的驗收（63 §L-4 已結清）。
RSpec.describe "媒體處理管線端到端", type: :request do
  let(:shop) { create(:shop, subdomain: "mpflow-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  MPF_PNG = [
    "89504e470d0a1a0a0000000d49484452000000010000000101030000002562d82200000006504c5445ffffff",
    "ffffff55c2d37e0000000a4944415408d76360000000020001e221bc330000000049454e44ae426082"
  ].join.scan(/../).map(&:hex).pack("C*").freeze

  before do
    host! "mpflow-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def stub_backend!(behaviour: :ok)
    source = Object.new
    def source.width = 2000
    def source.height = 1000
    def source.derive(spec) = [ "WEBP#{spec[:width]}", spec[:width], spec[:height] ]

    backend = Object.new
    backend.instance_variable_set(:@behaviour, behaviour)
    backend.instance_variable_set(:@source, source)
    def backend.open(_bytes)
      raise MediaPipeline::VipsBackend::DecodeFailed, "corrupt" if @behaviour == :decode_failed

      @source
    end
    MediaPipeline::ProcessFile.backend = backend
    backend
  end

  after { MediaPipeline::ProcessFile.reset_backend! }

  def create_file!
    login!
    target = ActsAsTenant.with_tenant(shop) do
      Storage::SignedUpload.issue(shop:, filename: "photo.png", byte_size: MPF_PNG.bytesize)
    end
    ActsAsTenant.with_tenant(shop) { Storage::LocalDisk.write(target.key, StringIO.new(MPF_PNG)) }
    post_graphql(<<~GRAPHQL, variables: { files: [ { originalSource: target.resource_url } ],
      mutation fileCreate($files: [FileCreateInput!]!, $idempotencyKey: String) {
        fileCreate(files: $files, idempotencyKey: $idempotencyKey) {
          files { id status } userErrors { code }
        }
      }
    GRAPHQL
                                          idempotencyKey: SecureRandom.uuid })
    data = response.parsed_body.dig("data", "fileCreate")
    expect(data["userErrors"]).to eq([])
    ActsAsTenant.with_tenant(shop) { StoredFile.find(data["files"].sole["id"][%r{/(\d+)\z}, 1].to_i) }
  end

  it "🔴 端到端：fileCreate（UPLOADED）→ relay drain → 消費者產四衍生 → READY，delivery 記 done" do
    stub_backend!
    file = create_file!
    expect(file.status).to eq("uploaded")

    Events::Relay.drain!

    file.reload
    expect(file.status).to eq("ready")
    expect(file.derivatives.keys).to match_array(%w[thumb card detail og])
    expect(file.width).to eq(2000)

    ActsAsTenant.without_tenant do
      event = EventOutbox.find_by!(topic: Events::Topics::MEDIA_UPLOADED, aggregate_id: file.id)
      expect(event.status).to eq("published")
      delivery = EventDelivery.find_by!(event_id: event.event_id, consumer: "media.process")
      expect(delivery.state).to eq("done")
    end
  end

  it "🔴 損壞檔：檔案 FAILED 但事件仍 published、delivery done（不無限重試）" do
    stub_backend!(behaviour: :decode_failed)
    file = create_file!
    Events::Relay.drain!

    file.reload
    expect(file.status).to eq("failed")
    expect(file.processing_error).to include("corrupt")
    ActsAsTenant.without_tenant do
      event = EventOutbox.find_by!(topic: Events::Topics::MEDIA_UPLOADED, aggregate_id: file.id)
      expect(event.status).to eq("published")
      expect(event.attempts).to eq(0)
      expect(EventDelivery.find_by!(event_id: event.event_id).state).to eq("done")
    end
  end

  it "衍生 blob 走同一支 blob 端點的 variant 參數；未知 variant 404" do
    stub_backend!
    file = create_file!
    Events::Relay.drain!
    login!

    get "/admin/files/#{file.id}/blob?variant=thumb"
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("WEBP160")
    expect(response.media_type).to eq("image/webp")

    get "/admin/files/#{file.id}/blob?variant=nope"
    expect(response).to have_http_status(:not_found)

    get "/admin/files/#{file.id}/blob"
    expect(response.body).to eq(MPF_PNG)
  end

  it "讀取面：featuredImage 帶四個衍生 URL；缺 alt 數如實計算；未處理完的媒體 thumbUrl 為 null" do
    stub_backend!
    file = create_file!
    Events::Relay.drain!
    product = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product }
    unprocessed = ActsAsTenant.with_tenant(shop) do
      key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
      Storage::LocalDisk.write(key, StringIO.new(MPF_PNG))
      StoredFile.create!(filename: "pending.png", content_type: "image/png", byte_size: 10,
                         checksum: "y" * 64, storage_key: key, status: "uploaded")
    end
    ActsAsTenant.with_tenant(shop) do
      Media.create!(shop_id: shop.id, product_id: product.id, position: 1, media_type: "image",
                    source_url: "/admin/files/#{file.id}/blob", file_id: file.id,
                    alt_text: "有 alt", status: "ready")
      Media.create!(shop_id: shop.id, product_id: product.id, position: 2, media_type: "image",
                    source_url: "/admin/files/#{unprocessed.id}/blob", file_id: unprocessed.id,
                    alt_text: nil, status: "uploaded")
    end

    login!
    post_graphql(<<~GRAPHQL, variables: { id: "gid://chilllove/Product/#{product.id}" })
      query($id: ID!) {
        product(id: $id) {
          mediaMissingAltCount
          featuredImage { id url status width height thumbUrl cardUrl detailUrl ogUrl alt }
        }
      }
    GRAPHQL
    data = response.parsed_body.dig("data", "product")
    expect(data["mediaMissingAltCount"]).to eq(1)
    image = data["featuredImage"]
    expect(image["status"]).to eq("READY")
    expect(image["alt"]).to eq("有 alt")
    expect(image["thumbUrl"]).to eq("/admin/files/#{file.id}/blob?variant=thumb")
    expect(image["ogUrl"]).to eq("/admin/files/#{file.id}/blob?variant=og")
    expect(image["width"]).to eq(2000)

    # 未處理完的檔案：衍生 URL 一律 null（不得拿原圖冒充縮圖）
    expect(unprocessed.reload.derivative_url("thumb")).to be_nil
  end

  it "🔴 審查 C12：列表路徑的 featuredImage／缺 alt 數不得 N+1（preload 生效）" do
    stub_backend!
    file = create_file!
    Events::Relay.drain!
    ActsAsTenant.with_tenant(shop) do
      3.times do |index|
        product = create(:product_variant, shop:).product
        Media.create!(shop_id: shop.id, product_id: product.id, position: 1, media_type: "image",
                      source_url: "/admin/files/#{file.id}/blob", file_id: file.id,
                      alt_text: index.zero? ? nil : "alt", status: "ready")
      end
    end

    login!
    queries = []
    counter = ->(_n, _s, _f, _id, payload) { queries << payload[:sql] if payload[:sql] =~ /\ASELECT/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      post_graphql(<<~GRAPHQL, variables: { first: 10 })
        query($first: Int!) {
          products(first: $first) {
            nodes { id mediaMissingAltCount featuredImage { thumbUrl } }
          }
        }
      GRAPHQL
    end
    expect(response.parsed_body.dig("data", "products", "nodes").length).to be >= 3
    # 三個商品 ⇒ media 與 files 各一次批次查詢（不是每列一次）
    expect(queries.count { |q| q.include?("`media`") }).to be <= 1
    expect(queries.count { |q| q.include?("`files`") }).to be <= 1
  end

  def login!(email: staff.email)
    post login_path, params: { email:, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path,
      params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end
end
