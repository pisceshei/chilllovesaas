# frozen_string_literal: true

require "rails_helper"

# 第 27 包（整合規格 §4-27）：媒體五支 mutation。
# 🔴 核心：`uq_media_product_id_position` 是 **unique**（系列的同型索引不是）——
#    交換兩張圖的重排會撞 1062，必須兩階段落位（§1.4／§8-3）。
RSpec.describe "Admin GraphQL 商品媒體", type: :request do
  let(:shop) { create(:shop, subdomain: "pmedia-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let(:product) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product } }

  PM_PNG = [
    "89504e470d0a1a0a0000000d49484452000000010000000101030000002562d82200000006504c5445ffffff",
    "ffffff55c2d37e0000000a4944415408d76360000000020001e221bc330000000049454e44ae426082"
  ].join.scan(/../).map(&:hex).pack("C*").freeze

  before do
    host! "pmedia-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    # 管線後端替身（libvips 本機無）——本包測的是 media 寫入不是影像處理
    source = Object.new
    def source.width = 800
    def source.height = 600
    def source.derive(spec) = [ "WEBP", spec[:width], spec[:height] ]
    backend = Object.new
    backend.instance_variable_set(:@source, source)
    def backend.open(_bytes) = @source
    MediaPipeline::ProcessFile.backend = backend
  end

  after { MediaPipeline::ProcessFile.reset_backend! }

  CREATE_MEDIA = <<~GRAPHQL
    mutation($productId: ID!, $media: [CreateMediaInput!]!, $idempotencyKey: String) {
      productCreateMedia(productId: $productId, media: $media, idempotencyKey: $idempotencyKey) {
        media { id position alt mediaContentType status image { url } }
        userErrors { field message code }
      }
    }
  GRAPHQL

  REORDER_MEDIA = <<~GRAPHQL
    mutation($productId: ID!, $mediaIds: [ID!]!) {
      productReorderMedia(productId: $productId, mediaIds: $mediaIds) {
        media { id position alt }
        userErrors { field message code }
      }
    }
  GRAPHQL

  def staged_url!(filename)
    ActsAsTenant.with_tenant(shop) do
      target = Storage::SignedUpload.issue(shop:, filename:, byte_size: PM_PNG.bytesize)
      Storage::LocalDisk.write(target.key, StringIO.new(PM_PNG))
      target.resource_url
    end
  end

  def create_media!(count: 1, alt: nil)
    entries = Array.new(count) { |index| { originalSource: staged_url!("m#{index}.png"), alt: } }
    post_graphql(CREATE_MEDIA, variables: { productId: product_gid, media: entries,
                                            idempotencyKey: SecureRandom.uuid })
    data = response.parsed_body.dig("data", "productCreateMedia")
    expect(data["userErrors"]).to eq([])
    data["media"]
  end

  def product_gid = "gid://chilllove/Product/#{product.id}"

  it "🔴 productCreateMedia：staged 檔入庫、position 1-based 遞增、引用計數落 file_usages" do
    login!
    media = create_media!(count: 3, alt: "貓")
    expect(media.map { |m| m["position"] }).to eq([ 1, 2, 3 ])
    expect(media.map { |m| m["alt"] }).to eq([ "貓", "貓", "貓" ])
    expect(media.first["mediaContentType"]).to eq("IMAGE")
    expect(media.first["image"]["url"]).to match(%r{/admin/files/\d+/blob})

    ActsAsTenant.with_tenant(shop) do
      expect(Media.where(product_id: product.id).count).to eq(3)
      expect(FileUsage.where(owner_type: "Media").count).to eq(3)
      # 每一列都指向真的 file
      expect(Media.where(product_id: product.id).map(&:file_id)).to all(be_present)
    end
  end

  it "🔴 productReorderMedia：交換兩張圖不撞 unique 索引（兩階段落位）；宣告式全量" do
    login!
    media = create_media!(count: 3)
    ids = media.map { |m| m["id"] }

    # 完全反轉（最容易撞 1062 的形態）
    post_graphql(REORDER_MEDIA, variables: { productId: product_gid, mediaIds: ids.reverse })
    data = response.parsed_body.dig("data", "productReorderMedia")
    expect(data["userErrors"]).to eq([])
    expect(data["media"].map { |m| m["id"] }).to eq(ids.reverse)
    expect(data["media"].map { |m| m["position"] }).to eq([ 1, 2, 3 ])

    # 相鄰交換（第二種撞法）
    swapped = [ ids[2], ids[0], ids[1] ]
    post_graphql(REORDER_MEDIA, variables: { productId: product_gid, mediaIds: swapped })
    expect(response.parsed_body.dig("data", "productReorderMedia", "userErrors")).to eq([])
    ActsAsTenant.with_tenant(shop) do
      expect(Media.where(product_id: product.id).order(:position).pluck(:position)).to eq([ 1, 2, 3 ])
    end
  end

  it "reorder 缺項／多項 ⇒ INVALID（不靜默錯位）" do
    login!
    ids = create_media!(count: 3).map { |m| m["id"] }
    post_graphql(REORDER_MEDIA, variables: { productId: product_gid, mediaIds: ids.take(2) })
    errors = response.parsed_body.dig("data", "productReorderMedia", "userErrors")
    expect(errors.sole["code"]).to eq("INVALID")
  end

  it "productDeleteMedia：釋放引用計數、position 補位連續" do
    login!
    ids = create_media!(count: 3).map { |m| m["id"] }
    post_graphql(<<~GRAPHQL, variables: { productId: product_gid, mediaIds: [ ids[1] ] })
      mutation($productId: ID!, $mediaIds: [ID!]!) {
        productDeleteMedia(productId: $productId, mediaIds: $mediaIds) {
          deletedMediaIds userErrors { code }
        }
      }
    GRAPHQL
    data = response.parsed_body.dig("data", "productDeleteMedia")
    expect(data["userErrors"]).to eq([])
    expect(data["deletedMediaIds"]).to eq([ ids[1] ])

    ActsAsTenant.with_tenant(shop) do
      expect(Media.where(product_id: product.id).order(:position).pluck(:position)).to eq([ 1, 2 ])
      expect(FileUsage.where(owner_type: "Media").count).to eq(2)
      # blob 與 file 列都還在（檔案可能還掛在別的商品，清掃是檔案庫的事）
      expect(StoredFile.count).to eq(3)
    end
  end

  it "🔴 D48：productUpdateMedia 的 alt 寫進**檔案**（改一次處處生效）；超長 ⇒ ALT_VALUE_LIMIT_EXCEEDED" do
    login!
    media = create_media!(count: 1, alt: "原始")
    id = media.sole["id"]
    update = <<~GRAPHQL
      mutation($productId: ID!, $media: [UpdateMediaInput!]!) {
        productUpdateMedia(productId: $productId, media: $media) {
          media { id alt } userErrors { code field }
        }
      }
    GRAPHQL
    post_graphql(update, variables: { productId: product_gid, media: [ { id:, alt: "新 alt" } ] })
    expect(response.parsed_body.dig("data", "productUpdateMedia", "media").sole["alt"]).to eq("新 alt")
    ActsAsTenant.with_tenant(shop) do
      # 🔴 **權威在檔案**（D48，2026-08-25 使用者裁定「所有的都跟 Shopify」）：
      #    在商品頁改 alt ＝ 改這個檔案的 alt ＝ 所有用到它的商品都跟著變。
      #    本例在 D48 之前斷言的是相反的事（「檔案層不受影響」），
      #    那是第 26／27 包 per-product 裁定的化身，隨該裁定被推翻而反轉。
      expect(StoredFile.sole.alt_text).to eq("新 alt")
      # 停用的 `media.alt_text` 不再被寫入（欄位保留，但不是權威）
      expect(Media.sole.alt_text).to be_nil
    end

    post_graphql(update, variables: { productId: product_gid, media: [ { id:, alt: "x" * 513 } ] })
    expect(response.parsed_body.dig("data", "productUpdateMedia", "userErrors").sole["code"])
      .to eq("ALT_VALUE_LIMIT_EXCEEDED")
  end

  it "productVariantAppendMedia：掛圖／換圖（每變體上限 1）／卸圖" do
    login!
    ids = create_media!(count: 2).map { |m| m["id"] }
    variant = ActsAsTenant.with_tenant(shop) { product.product_variants.sole }
    variant_gid = "gid://chilllove/ProductVariant/#{variant.id}"
    append = <<~GRAPHQL
      mutation($productId: ID!, $variantId: ID!, $mediaId: ID) {
        productVariantAppendMedia(productId: $productId, variantId: $variantId, mediaId: $mediaId) {
          media { id productVariantId } userErrors { code }
        }
      }
    GRAPHQL

    post_graphql(append, variables: { productId: product_gid, variantId: variant_gid, mediaId: ids[0] })
    expect(response.parsed_body.dig("data", "productVariantAppendMedia", "media").sole["productVariantId"])
      .to eq(variant_gid)

    # 換第二張：上限 1 ⇒ 第一張自動卸下
    post_graphql(append, variables: { productId: product_gid, variantId: variant_gid, mediaId: ids[1] })
    expect(response.parsed_body.dig("data", "productVariantAppendMedia", "userErrors")).to eq([])
    ActsAsTenant.with_tenant(shop) do
      expect(Media.where(product_variant_id: variant.id).count).to eq(1)
    end

    # 卸下
    post_graphql(append, variables: { productId: product_gid, variantId: variant_gid, mediaId: nil })
    ActsAsTenant.with_tenant(shop) do
      expect(Media.where(product_variant_id: variant.id).count).to eq(0)
    end
  end

  it "productCreateMedia 無 idempotencyKey ⇒ IDEMPOTENCY_KEY_REQUIRED（建立型契約）" do
    login!
    post_graphql(CREATE_MEDIA, variables: { productId: product_gid,
                                            media: [ { originalSource: staged_url!("x.png") } ] })
    expect(response.parsed_body["errors"].sole.dig("extensions", "code"))
      .to eq("IDEMPOTENCY_KEY_REQUIRED")
  end

  it "originalSource 與 fileId 二選一：both／neither 都是 INVALID" do
    login!
    file = ActsAsTenant.with_tenant(shop) do
      Storage::FileCreate.call(shop:, files_input: [ { original_source: staged_url!("f.png") } ]).files.sole
    end
    file_gid = "gid://chilllove/File/#{file.id}"

    [ { originalSource: staged_url!("y.png"), fileId: file_gid }, {} ].each do |entry|
      post_graphql(CREATE_MEDIA, variables: { productId: product_gid, media: [ entry ],
                                              idempotencyKey: SecureRandom.uuid })
      expect(response.parsed_body.dig("data", "productCreateMedia", "userErrors").sole["code"])
        .to eq("INVALID")
    end

    # fileId 單獨給＝用既有檔（第 28 包選檔的路徑）
    post_graphql(CREATE_MEDIA, variables: { productId: product_gid, media: [ { fileId: file_gid } ],
                                            idempotencyKey: SecureRandom.uuid })
    expect(response.parsed_body.dig("data", "productCreateMedia", "userErrors")).to eq([])
    ActsAsTenant.with_tenant(shop) { expect(Media.sole.file_id).to eq(file.id) }
  end

  it "跨店隔離：他店商品的 GID ⇒ NOT_FOUND（不得寫入）" do
    other = create(:shop, subdomain: "pmedia-other")
    foreign = ActsAsTenant.with_tenant(other) { create(:product_variant, shop: other).product }
    login!
    post_graphql(CREATE_MEDIA, variables: { productId: "gid://chilllove/Product/#{foreign.id}",
                                            media: [ { originalSource: staged_url!("z.png") } ],
                                            idempotencyKey: SecureRandom.uuid })
    expect(response.parsed_body["errors"].sole.dig("extensions", "code")).to eq("NOT_FOUND")
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
