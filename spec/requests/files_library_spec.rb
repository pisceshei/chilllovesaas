# frozen_string_literal: true

require "rails_helper"

# 第 28 包（整合規格 §4-28）：檔案庫的 `files` query＋`fileUpdate`／`fileDelete`。
#
# 🔴 本檔釘住的核心是**刪檔的官方語義**（取證 2026-08-25）：
#   "When you delete files that are referenced by products, the mutation
#    automatically removes those references and reorders any remaining media
#    to maintain proper positioning."
#   ⇒ 引用中的檔案**可以刪**（不是錯誤），而且**剩下的媒體必須補位**。
#   來源：<https://shopify.dev/docs/api/admin-graphql/latest/mutations/fileDelete>
RSpec.describe "Admin GraphQL 檔案庫", type: :request do
  let(:shop) { create(:shop, subdomain: "flib-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let(:product) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product } }

  before do
    host! "flib-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  FILES_QUERY = <<~GRAPHQL
    query($query: String, $status: FileStatus, $usedIn: FileUsedInFilter) {
      files(first: 50, query: $query, status: $status, usedIn: $usedIn) {
        nodes { id filename status alt usageCount thumbUrl }
        pageInfo { hasNextPage }
      }
    }
  GRAPHQL

  FILE_UPDATE = <<~GRAPHQL
    mutation($files: [FileUpdateInput!]!) {
      fileUpdate(files: $files) {
        files { id alt filename }
        userErrors { field message code }
      }
    }
  GRAPHQL

  FILE_DELETE = <<~GRAPHQL
    mutation($fileIds: [ID!]!) {
      fileDelete(fileIds: $fileIds) {
        deletedFileIds
        userErrors { field message code }
      }
    }
  GRAPHQL

  # 建一個檔案列＋真的落一份 blob（刪除路徑要驗 blob 也被清掉）。
  def make_file!(filename: "a.png", status: "ready", alt: nil, derivatives: nil)
    ActsAsTenant.with_tenant(shop) do
      key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
      Storage::LocalDisk.write(key, StringIO.new("BYTES"))
      StoredFile.create!(filename:, content_type: "image/png", byte_size: 5,
                         checksum: SecureRandom.hex(32), storage_key: key,
                         status:, alt_text: alt, derivatives:)
    end
  end

  def attach!(file, position)
    ActsAsTenant.with_tenant(shop) do
      row = Media.create!(shop_id: shop.id, product_id: product.id, file_id: file.id,
                          media_type: "image", position:,
                          source_url: "/admin/files/#{file.id}/blob", status: file.status)
      FileUsage.create!(shop_id: shop.id, file_id: file.id, owner_type: "Media", owner_id: row.id)
      row
    end
  end

  def gid(file) = "gid://chilllove/File/#{file.id}"

  it "files query：列表帶引用計數與縮圖，檔名子字串／狀態可篩" do
    a = make_file!(filename: "cat-photo.png", alt: "貓")
    make_file!(filename: "dog.png", status: "failed")
    attach!(a, 1)
    login!

    post_graphql(FILES_QUERY)
    nodes = response.parsed_body.dig("data", "files", "nodes")
    expect(nodes.map { |n| n["filename"] }).to contain_exactly("cat-photo.png", "dog.png")
    cat = nodes.find { |n| n["filename"] == "cat-photo.png" }
    expect(cat["usageCount"]).to eq(1)
    expect(cat["alt"]).to eq("貓")
    # 衍生未產出 ⇒ thumbUrl 為 null（不得拿原圖冒充縮圖）
    expect(cat["thumbUrl"]).to be_nil

    post_graphql(FILES_QUERY, variables: { query: "cat" })
    expect(response.parsed_body.dig("data", "files", "nodes").sole["filename"]).to eq("cat-photo.png")

    post_graphql(FILES_QUERY, variables: { status: "FAILED" })
    expect(response.parsed_body.dig("data", "files", "nodes").sole["filename"]).to eq("dog.png")
  end

  it "🔴 LIKE 的萬用字元必須跳脫——搜 `%` 不得匹配整表" do
    make_file!(filename: "100%_final.png")
    make_file!(filename: "plain.png")
    login!

    post_graphql(FILES_QUERY, variables: { query: "%" })
    names = response.parsed_body.dig("data", "files", "nodes").map { |n| n["filename"] }
    expect(names).to eq([ "100%_final.png" ])
  end

  it "usedIn：NONE 只回沒有任何引用的檔（＝檔案庫「可安全刪除」那一批）" do
    used = make_file!(filename: "used.png")
    make_file!(filename: "orphan.png")
    attach!(used, 1)
    login!

    post_graphql(FILES_QUERY, variables: { usedIn: "NONE" })
    expect(response.parsed_body.dig("data", "files", "nodes").sole["filename"]).to eq("orphan.png")

    post_graphql(FILES_QUERY, variables: { usedIn: "PRODUCT" })
    expect(response.parsed_body.dig("data", "files", "nodes").sole["filename"]).to eq("used.png")
  end

  it "🔴 fileUpdate 改檔案層 alt，**不回寫既有 media 的 alt**（我方與本尊的已知分歧）" do
    file = make_file!(alt: "舊檔案 alt")
    row = attach!(file, 1)
    ActsAsTenant.with_tenant(shop) { row.update!(alt_text: "這個商品專屬的 alt") }
    login!

    post_graphql(FILE_UPDATE, variables: { files: [ { id: gid(file), alt: "新檔案 alt" } ] })
    expect(response.parsed_body.dig("data", "fileUpdate", "userErrors")).to be_empty
    ActsAsTenant.with_tenant(shop) do
      expect(file.reload.alt_text).to eq("新檔案 alt")
      # 使用者針對這個商品寫的 alt 不得被檔案庫的一次編輯蓋掉
      expect(row.reload.alt_text).to eq("這個商品專屬的 alt")
    end
  end

  it "fileUpdate 改檔名：同店撞名 ⇒ FILENAME_ALREADY_EXISTS；改成原值不算撞名" do
    a = make_file!(filename: "a.png")
    make_file!(filename: "b.png")
    login!

    post_graphql(FILE_UPDATE, variables: { files: [ { id: gid(a), filename: "b.png" } ] })
    expect(response.parsed_body.dig("data", "fileUpdate", "userErrors").sole["code"])
      .to eq("FILENAME_ALREADY_EXISTS")

    post_graphql(FILE_UPDATE, variables: { files: [ { id: gid(a), filename: "a.png" } ] })
    expect(response.parsed_body.dig("data", "fileUpdate", "userErrors")).to be_empty
  end

  it "🔴 fileUpdate 要求 ready（官方前置）：uploaded ⇒ NON_READY_STATE、failed ⇒ INVALID_FAILED_MEDIA_STATE" do
    pending_file = make_file!(status: "uploaded")
    failed = make_file!(filename: "bad.png", status: "failed")
    login!

    post_graphql(FILE_UPDATE, variables: { files: [ { id: gid(pending_file), alt: "x" } ] })
    expect(response.parsed_body.dig("data", "fileUpdate", "userErrors").sole["code"]).to eq("NON_READY_STATE")

    post_graphql(FILE_UPDATE, variables: { files: [ { id: gid(failed), alt: "x" } ] })
    expect(response.parsed_body.dig("data", "fileUpdate", "userErrors").sole["code"])
      .to eq("INVALID_FAILED_MEDIA_STATE")
  end

  it "🔴 fileDelete 刪引用中的檔：解除引用 ∧ 剩下的媒體補位 1..n（官方明載副作用）" do
    files = 3.times.map { |i| make_file!(filename: "f#{i}.png") }
    rows = files.each_with_index.map { |f, i| attach!(f, i + 1) }
    login!

    # 刪中間那一張——補位沒做的話會留下 [1,3]
    post_graphql(FILE_DELETE, variables: { fileIds: [ gid(files[1]) ] })
    body = response.parsed_body.dig("data", "fileDelete")
    expect(body["userErrors"]).to be_empty
    expect(body["deletedFileIds"]).to eq([ gid(files[1]) ])

    ActsAsTenant.with_tenant(shop) do
      expect(StoredFile.where(id: files[1].id)).to be_empty
      expect(Media.where(id: rows[1].id)).to be_empty
      expect(FileUsage.where(file_id: files[1].id).count).to eq(0)
      expect(Media.where(product_id: product.id).order(:position).pluck(:position)).to eq([ 1, 2 ])
    end
  end

  it "🔴 fileDelete 刪 blob 與衍生（commit 之後），且衍生的空目錄一併收掉" do
    file = make_file!
    # 衍生 key 的真實形狀＝shops/{id}/derivatives/{file_id}/{checksum}/{variant}.webp
    # ——每個檔案自己一棵樹，只 rm 檔案會留下兩層空目錄（2026-08-25 bt3 實測發現）。
    derivative_key = "shops/#{shop.id}/derivatives/#{file.id}/abc123/thumb.webp"
    ActsAsTenant.with_tenant(shop) do
      file.update!(derivatives: { "thumb" => { "key" => derivative_key, "width" => 160,
                                              "height" => 160, "byte_size" => 4 } })
    end
    Storage::LocalDisk.write(derivative_key, StringIO.new("WEBP"))
    key = file.storage_key
    login!

    expect(Storage::LocalDisk.exist?(key)).to be(true)
    post_graphql(FILE_DELETE, variables: { fileIds: [ gid(file) ] })
    expect(response.parsed_body.dig("data", "fileDelete", "userErrors")).to be_empty
    expect(Storage::LocalDisk.exist?(key)).to be(false)
    expect(Storage::LocalDisk.exist?(derivative_key)).to be(false)
    # 🔴 空目錄不得留下——這是單元測試看不到、累積才顯形的洩漏
    expect(Storage::LocalDisk.root.join("shops/#{shop.id}/derivatives/#{file.id}")).not_to exist
  end

  it "🔴 處理中的檔不得刪（管線正在寫衍生）⇒ FILE_LOCKED，且 row 與 blob 都還在" do
    file = make_file!(status: "processing")
    login!

    post_graphql(FILE_DELETE, variables: { fileIds: [ gid(file) ] })
    expect(response.parsed_body.dig("data", "fileDelete", "userErrors").sole["code"]).to eq("FILE_LOCKED")
    ActsAsTenant.with_tenant(shop) { expect(StoredFile.where(id: file.id)).to be_present }
    expect(Storage::LocalDisk.exist?(file.storage_key)).to be(true)
  end

  it "跨店隔離：他店檔案的 GID ⇒ FILE_DOES_NOT_EXIST（不得刪、不得讀）" do
    other = create(:shop, subdomain: "flib-other")
    stranger = ActsAsTenant.with_tenant(other) do
      key = "shops/#{other.id}/files/#{SecureRandom.uuid}.png"
      Storage::LocalDisk.write(key, StringIO.new("BYTES"))
      StoredFile.create!(filename: "other.png", content_type: "image/png", byte_size: 5,
                         checksum: SecureRandom.hex(32), storage_key: key, status: "ready")
    end
    login!

    post_graphql(FILE_DELETE, variables: { fileIds: [ gid(stranger) ] })
    expect(response.parsed_body.dig("data", "fileDelete", "userErrors").sole["code"])
      .to eq("FILE_DOES_NOT_EXIST")
    ActsAsTenant.with_tenant(other) { expect(StoredFile.where(id: stranger.id)).to be_present }
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
