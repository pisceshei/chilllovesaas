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

  SORTED_QUERY = <<~GRAPHQL
    query($sortKey: FileSortKeys, $reverse: Boolean, $first: Int!, $after: String) {
      files(first: $first, after: $after, sortKey: $sortKey, reverse: $reverse) {
        nodes { filename byteSize }
        pageInfo { hasNextPage endCursor }
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
                         status:, alt_text: alt, derivatives:, width: 100, height: 80)
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

  it "🔴 D48：三種排序鍵各可升降，且**預設方向依鍵而異**" do
    ActsAsTenant.with_tenant(shop) do
      [ [ "banana.png", 300 ], [ "apple.png", 100 ], [ "cherry.png", 200 ] ].each do |name, size|
        key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
        Storage::LocalDisk.write(key, StringIO.new("B" * size))
        StoredFile.create!(filename: name, content_type: "image/png", byte_size: size,
                           checksum: SecureRandom.hex(32), storage_key: key, status: "ready",
                           width: 100, height: 80)
      end
    end
    login!

    def names(vars)
      post_graphql(SORTED_QUERY, variables: { first: 50 }.merge(vars))
      response.parsed_body.dig("data", "files", "nodes").map { |n| n["filename"] }
    end

    # 🔴 檔名預設**由小到大**（不是 desc）：檔名 desc 開頭是 z，沒人期待那個。
    expect(names(sortKey: "FILENAME")).to eq([ "apple.png", "banana.png", "cherry.png" ])
    expect(names(sortKey: "FILENAME", reverse: true)).to eq([ "cherry.png", "banana.png", "apple.png" ])

    expect(names(sortKey: "ORIGINAL_UPLOAD_SIZE")).to eq([ "apple.png", "cherry.png", "banana.png" ])
    expect(names(sortKey: "ORIGINAL_UPLOAD_SIZE", reverse: true))
      .to eq([ "banana.png", "cherry.png", "apple.png" ])

    # 🔴 日期預設**新到舊**（本尊逐字 "from newest to oldest"）——與上面兩鍵相反。
    expect(names(sortKey: "CREATED_AT")).to eq([ "cherry.png", "apple.png", "banana.png" ])
    expect(names({})).to eq(names(sortKey: "CREATED_AT")) # 不指定＝CREATED_AT
  end

  it "🔴 D48：非預設排序鍵的 cursor 分頁不得跳列或重複" do
    ActsAsTenant.with_tenant(shop) do
      %w[e d c b a].each_with_index do |name, index|
        key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
        Storage::LocalDisk.write(key, StringIO.new("B"))
        StoredFile.create!(filename: "#{name}.png", content_type: "image/png",
                           byte_size: 10 + index, checksum: SecureRandom.hex(32),
                           storage_key: key, status: "ready", width: 100, height: 80)
      end
    end
    login!

    seen = []
    cursor = nil
    3.times do
      post_graphql(SORTED_QUERY, variables: { first: 2, after: cursor, sortKey: "FILENAME" })
      page = response.parsed_body.dig("data", "files")
      seen.concat(page["nodes"].map { |n| n["filename"] })
      cursor = page.dig("pageInfo", "endCursor")
      break unless page.dig("pageInfo", "hasNextPage")
    end
    expect(seen).to eq(seen.uniq)                # 不重複
    expect(seen).to eq(seen.sort)                # 跨頁仍是全序
    expect(seen.first(5)).to eq(%w[a.png b.png c.png d.png e.png])
  end

  it "🔴 D48：字串排序鍵的 cursor 必須驗型別（數字 payload 不得被隱式轉型吞掉）" do
    login!
    # 把 filename 位置塞一個數字——`Integer()` 那種天然 fail-closed 在字串鍵上不存在
    bad = Base64.urlsafe_encode64(JSON.generate([ 123, 1 ]), padding: false)
    post_graphql(SORTED_QUERY, variables: { first: 5, after: bad, sortKey: "FILENAME" })
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
  end

  it "🔴 審查 S1：cursor 綁定它的排序鍵——換鍵重用一律 BAD_USER_INPUT，不得靜默回錯頁" do
    ActsAsTenant.with_tenant(shop) do
      # 數字開頭的檔名排在 ISO8601 時間戳字串**之前**——正是會被靜默吞掉的那些
      [ "0001-invoice.png", "1099-form.png", "yak.png", "zebra.png" ].each do |name|
        key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
        Storage::LocalDisk.write(key, StringIO.new("B"))
        StoredFile.create!(filename: name, content_type: "image/png", byte_size: 10,
                           checksum: SecureRandom.hex(32), storage_key: key, status: "ready",
                           width: 100, height: 80)
      end
    end
    login!

    # 先用預設鍵（CREATED_AT）取一個 cursor
    post_graphql(SORTED_QUERY, variables: { first: 2 })
    created_cursor = response.parsed_body.dig("data", "files", "pageInfo", "endCursor")
    expect(created_cursor).to be_present

    # 🔴 拿它去當 FILENAME 的 after：必須被擋，而不是回一頁少了兩筆的結果
    post_graphql(SORTED_QUERY,
                 variables: { first: 10, after: created_cursor, sortKey: "FILENAME" })
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")

    # 反方向同樣要擋
    post_graphql(SORTED_QUERY, variables: { first: 2, sortKey: "FILENAME" })
    filename_cursor = response.parsed_body.dig("data", "files", "pageInfo", "endCursor")
    post_graphql(SORTED_QUERY, variables: { first: 10, after: filename_cursor })
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")

    # 同鍵照常可用（守衛不得誤傷正常翻頁）
    post_graphql(SORTED_QUERY,
                 variables: { first: 10, after: filename_cursor, sortKey: "FILENAME" })
    expect(response.parsed_body["errors"]).to be_nil
  end

  it "🔴 byte_size cursor 超出 bigint ⇒ BAD_USER_INPUT，不得漏成 500" do
    login!
    # `Integer(10**20)` 本身不會 raise，會一路帶到 bind 參數才炸 RangeError ⇒ 500。
    huge = Base64.urlsafe_encode64(JSON.generate([ 10**20, 1 ]), padding: false)
    post_graphql(SORTED_QUERY,
                 variables: { first: 5, after: huge, sortKey: "ORIGINAL_UPLOAD_SIZE" })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
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

  it "🔴 D48：fileUpdate 改 alt ⇒ **所有引用這個檔的商品媒體都跟著變**（本尊語義）" do
    file = make_file!(alt: "舊檔案 alt")
    # 同一個檔掛在兩個不同商品上——這正是「一份 alt 還是多份 alt」分野的場景
    row_a = attach!(file, 1)
    other = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product }
    row_b = ActsAsTenant.with_tenant(shop) do
      r = Media.create!(shop_id: shop.id, product_id: other.id, file_id: file.id,
                        media_type: "image", position: 1,
                        source_url: "/admin/files/#{file.id}/blob", status: file.status)
      FileUsage.create!(shop_id: shop.id, file_id: file.id, owner_type: "Media", owner_id: r.id)
      r
    end
    login!

    post_graphql(FILE_UPDATE, variables: { files: [ { id: gid(file), alt: "新檔案 alt" } ] })
    expect(response.parsed_body.dig("data", "fileUpdate", "userErrors")).to be_empty

    # 兩個商品的媒體讀出來都是新值——因為它們讀的是同一個 files 列
    [ row_a, row_b ].each do |row|
      post_graphql(<<~GRAPHQL, variables: { id: "gid://chilllove/Product/#{row.product_id}" })
        query($id: ID!) { product(id: $id) { media { alt } } }
      GRAPHQL
      expect(response.parsed_body.dig("data", "product", "media").sole["alt"]).to eq("新檔案 alt")
    end
    ActsAsTenant.with_tenant(shop) { expect(file.reload.alt_text).to eq("新檔案 alt") }
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
                         checksum: SecureRandom.hex(32), storage_key: key, status: "ready",
                         width: 100, height: 80)
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
