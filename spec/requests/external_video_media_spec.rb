# frozen_string_literal: true

require "rails_helper"

# 第 37 包：外嵌 ExternalVideo（YouTube／Vimeo）的讀寫面。
#
# 射程＝B9 的收斂面：**只做外嵌**，影片／3D 上傳仍然擋（伺服器僅 libvips、無轉碼器）。
RSpec.describe "Admin GraphQL 外嵌影片", type: :request do
  let(:shop) { create(:shop, subdomain: "extvid-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "extvid-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  CREATE = <<~GRAPHQL
    mutation($productId: ID!, $media: [CreateMediaInput!]!, $idempotencyKey: String) {
      productCreateMedia(productId: $productId, media: $media, idempotencyKey: $idempotencyKey) {
        media { id mediaContentType status alt
                externalVideo { host externalId embedUrl originUrl alt } }
        userErrors { field message code }
      }
    }
  GRAPHQL

  UPDATE = <<~GRAPHQL
    mutation($productId: ID!, $media: [UpdateMediaInput!]!) {
      productUpdateMedia(productId: $productId, media: $media) {
        media { id alt externalVideo { alt } }
        userErrors { field message code }
      }
    }
  GRAPHQL

  def product! = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product }
  def gid(p) = "gid://chilllove/Product/#{p.id}"

  def create_media(product, entries)
    post_graphql(CREATE, variables: { productId: gid(product), media: entries,
                                      idempotencyKey: SecureRandom.uuid })
    response.parsed_body.dig("data", "productCreateMedia")
  end

  it "🔴 顯式 EXTERNAL_VIDEO：落庫的是**重建**的 URL，不是使用者原字串" do
    product = product!
    login!
    body = create_media(product, [ { originalSource: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL&si=track",
                                     mediaContentType: "EXTERNAL_VIDEO", alt: "示範影片" } ])
    expect(body["userErrors"]).to be_empty
    node = body["media"].sole
    expect(node["mediaContentType"]).to eq("EXTERNAL_VIDEO")
    expect(node.dig("externalVideo", "host")).to eq("YOUTUBE")
    expect(node.dig("externalVideo", "externalId")).to eq("dQw4w9WgXcQ")
    # 🔴 追蹤參數不得存活——這是注入面的主防線（見 ExternalVideoUrl 檔頭②）
    expect(node.dig("externalVideo", "originUrl")).to eq("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    # embed URL 走隱私強化網域，且是**導出**的（DB 裡沒有這個字串）
    expect(node.dig("externalVideo", "embedUrl")).to eq("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")
    ActsAsTenant.with_tenant(shop) do
      row = product.media.sole
      expect(row.file_id).to be_nil
      expect(row.source_url).to eq("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      expect(Media.where(shop_id: shop.id).pluck(:source_url).join).not_to include("nocookie")
    end
  end

  it "省略 mediaContentType 時依 URL 形態判定（ours）" do
    product = product!
    login!
    body = create_media(product, [ { originalSource: "https://vimeo.com/76979871" } ])
    expect(body["userErrors"]).to be_empty
    expect(body["media"].sole.dig("externalVideo", "host")).to eq("VIMEO")
    # 🔴 沒有這條規則的話，貼 YouTube URL 會掉進 Storage::FileCreate 去抓一份 HTML，
    #    使用者看到的錯誤訊息與真實原因完全無關。
  end

  it "🔴 非法 URL 走 userErrors 而不是 500（鐵律 4 第①層）" do
    product = product!
    login!
    {
      "https://dailymotion.com/video/x1" => "EXTERNAL_VIDEO_UNSUPPORTED_HOST",
      "https://www.youtube.com/shorts/abc" => "EXTERNAL_VIDEO_INVALID_URL",
      "javascript:alert(1)" => "EXTERNAL_VIDEO_INVALID_URL"
    }.each do |url, code|
      body = create_media(product, [ { originalSource: url, mediaContentType: "EXTERNAL_VIDEO" } ])
      expect(response.parsed_body["errors"]).to be_nil, "#{url} 漏成 top-level 錯誤"
      expect(body["userErrors"].map { |e| e["code"] }).to eq([ code ]), "#{url} 的 code 不符"
      expect(body["userErrors"].sole["field"]).to eq(%w[media 0 originalSource])
    end
    ActsAsTenant.with_tenant(shop) { expect(product.media.count).to eq(0) }
  end

  it "外嵌影片不能同時給 fileId（語義矛盾）" do
    product = product!
    login!
    body = create_media(product, [ { fileId: "gid://chilllove/File/1", mediaContentType: "EXTERNAL_VIDEO" } ])
    expect(body["userErrors"].sole["field"]).to eq(%w[media 0 fileId])
  end

  it "🔴 alt 落在媒體列——D48 的窄縫（外嵌沒有檔案，沒有別的地方可寫）" do
    product = product!
    login!
    created = create_media(product, [ { originalSource: "https://vimeo.com/76979871",
                                        mediaContentType: "EXTERNAL_VIDEO", alt: "原說明" } ])
    media_id = created["media"].sole["id"]

    post_graphql(UPDATE, variables: { productId: gid(product), media: [ { id: media_id, alt: "改過的說明" } ] })
    body = response.parsed_body.dig("data", "productUpdateMedia")
    # 沒有那個窄縫的話這裡會回 NOT_FOUND（落到「無處可寫 alt」分支），
    # 而那個訊息與真實原因完全無關。
    expect(body["userErrors"]).to be_empty
    expect(body["media"].sole["alt"]).to eq("改過的說明")
    ActsAsTenant.with_tenant(shop) do
      row = product.media.sole
      expect(row.alt_text).to eq("改過的說明")
      expect(row.stored_file).to be_nil
    end
  end

  it "🔴 D48 的窄縫只開給外嵌影片——沒有檔案的圖片列仍然回 nil" do
    product = product!
    ActsAsTenant.with_tenant(shop) do
      # M0 遺產形態：media_type=image 但 file_id 為 nil，且 media.alt_text 有舊值
      Media.create!(shop_id: shop.id, product_id: product.id, media_type: "image", position: 1,
                    source_url: "/legacy", status: "ready", alt_text: "D48 停用的舊值")
    end
    login!
    post_graphql("query($id: ID!) { product(id: $id) { media { alt externalVideo { host } } } }",
                 variables: { id: gid(product) })
    node = response.parsed_body.dig("data", "product", "media").sole
    # 放寬成「file 為 nil 就回落」的話，D48 停用的舊語義會從後門復活
    expect(node["alt"]).to be_nil
    expect(node["externalVideo"]).to be_nil
  end

  it "外嵌影片建立即 ready，不顯示永遠不會結束的「處理中」" do
    product = product!
    login!
    body = create_media(product, [ { originalSource: "https://vimeo.com/76979871",
                                     mediaContentType: "EXTERNAL_VIDEO" } ])
    expect(body["media"].sole["status"]).to eq("READY")
  end

  it "🔴 變體掛圖仍然拒收影片（官方：3D 與影片不能當變體圖）" do
    product = product!
    variant = ActsAsTenant.with_tenant(shop) { product.product_variants.sole }
    login!
    created = create_media(product, [ { originalSource: "https://vimeo.com/76979871",
                                        mediaContentType: "EXTERNAL_VIDEO" } ])
    append = <<~G
      mutation($productId: ID!, $variantId: ID!, $mediaId: ID, $idempotencyKey: String) {
        productVariantAppendMedia(productId: $productId, variantId: $variantId,
                                  mediaId: $mediaId, idempotencyKey: $idempotencyKey) {
          userErrors { field message code }
        }
      }
    G
    post_graphql(append, variables: {
      productId: gid(product),
      variantId: "gid://chilllove/ProductVariant/#{variant.id}",
      mediaId: created["media"].sole["id"],
      idempotencyKey: SecureRandom.uuid
    })
    errors = response.parsed_body.dig("data", "productVariantAppendMedia", "userErrors")
    expect(errors).not_to be_empty
    ActsAsTenant.with_tenant(shop) { expect(product.media.sole.product_variant_id).to be_nil }
  end

  # ── model 層第二道 ────────────────────────────────────────────────
  # 🔴 這幾條**必須直接打 model**：服務層已經先把壞 URL 擋掉了，所以只走 GraphQL
  #   的測試碰不到這道守衛——把 model validation 整條刪掉，上面九條仍然全綠（實測）。
  #   它守的是繞過 `MediaSync` 的路徑（直接 `Media.create!`、未來的匯入器、
  #   console 手動修資料）。半個外嵌影片（有 host 沒有 id）會讓
  #   `ExternalVideoUrl.embed_url` 產出 `.../embed/` 這種殘缺 URL，
  #   而那是個會被前台當成合法 iframe src 的字串。

  it "model：外嵌影片缺 host 或 id 一律不得落庫" do
    product = product!
    ActsAsTenant.with_tenant(shop) do
      base = { shop_id: shop.id, product_id: product.id, media_type: "external_video",
               position: 9, source_url: "https://vimeo.com/1", status: "ready" }
      expect { Media.create!(**base) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { Media.create!(**base, external_host: "vimeo") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { Media.create!(**base, external_id: "1") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { Media.create!(**base, external_host: "vimeo", external_id: "1") }.not_to raise_error
    end
  end

  it "model：host 只收白名單（值域來自 limits，不是硬編）" do
    product = product!
    ActsAsTenant.with_tenant(shop) do
      expect do
        Media.create!(shop_id: shop.id, product_id: product.id, media_type: "external_video",
                      position: 9, source_url: "https://x/1", status: "ready",
                      external_host: "dailymotion", external_id: "1")
      end.to raise_error(ActiveRecord::RecordInvalid, /external host/i)
    end
  end

  it "model：不是外嵌影片就不得帶外嵌欄位（避免圖片列被讀取面誤判成影片）" do
    product = product!
    ActsAsTenant.with_tenant(shop) do
      expect do
        Media.create!(shop_id: shop.id, product_id: product.id, media_type: "image",
                      position: 9, source_url: "/blob", status: "ready", external_host: "youtube")
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it "🔴 B9 的上傳閘門沒有被鬆掉：可上傳型別仍然只有 image" do
    # 加外嵌**一個字都不動** upload_media_types_enabled——兩鍵是不同的事。
    expect(Limits.enum(:media, :upload_media_types_enabled)).to eq(%w[IMAGE])
    expect(Limits.enum(:media, :embed_media_types_enabled)).to eq(%w[EXTERNAL_VIDEO])
    expect(ChillloveSchema.types["MediaContentType"].values.keys).to contain_exactly("IMAGE", "EXTERNAL_VIDEO")
    expect(ChillloveSchema.types["MediaHost"].values.keys).to contain_exactly("YOUTUBE", "VIMEO")
  end

  def login!(email: staff.email)
    post login_path, params: { email:, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end
end
