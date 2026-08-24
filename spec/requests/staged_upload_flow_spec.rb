# frozen_string_literal: true

require "rails_helper"

# 第 25 包（整合規格 §4-25 判準）：兩段式上傳三步走完＋SSRF 反例被拒＋撞名三模式。
RSpec.describe "Staged upload 兩段式", type: :request do
  let(:shop) { create(:shop, subdomain: "staged-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  # 1×1 PNG（真實 header——content-type 推斷與未來 magic sniff 都吃得下）
  PNG_BYTES = [
    "89504e470d0a1a0a0000000d49484452000000010000000101030000002562d82200000006504c5445ffffff",
    "ffffff55c2d37e0000000a4944415408d76360000000020001e221bc330000000049454e44ae426082"
  ].join.scan(/../).map(&:hex).pack("C*").freeze

  before do
    host! "staged-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  STAGED_MUTATION = <<~GRAPHQL
    mutation stagedUploadsCreate($input: [StagedUploadInput!]!) {
      stagedUploadsCreate(input: $input) {
        stagedTargets { url resourceUrl parameters { name value } }
        userErrors { field message code }
      }
    }
  GRAPHQL

  FILE_CREATE_MUTATION = <<~GRAPHQL
    mutation fileCreate($files: [FileCreateInput!]!, $idempotencyKey: String) {
      fileCreate(files: $files, idempotencyKey: $idempotencyKey) {
        files { id filename contentType byteSize status alt url }
        userErrors { field message code }
      }
    }
  GRAPHQL

  def staged_targets!(declarations)
    post_graphql(STAGED_MUTATION, variables: { input: declarations })
    data = response.parsed_body.dig("data", "stagedUploadsCreate")
    expect(data["userErrors"]).to eq([])
    data["stagedTargets"]
  end

  def upload!(target, bytes: PNG_BYTES, filename: "貓咪.png")
    params = target["parameters"].to_h { |p| [ p["name"], p["value"] ] }
    file = Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/png", original_filename: filename)
    post admin_staged_upload_path, params: params.merge(file: file)
  end

  def file_create!(files)
    post_graphql(FILE_CREATE_MUTATION, variables: { files:, idempotencyKey: SecureRandom.uuid })
    response.parsed_body.dig("data", "fileCreate")
  end

  it "🔴 三步走完：簽發→直傳→fileCreate；檔案 READY、事件同 transaction 落 outbox、blob 端點可讀" do
    login!
    target = staged_targets!([ { filename: "貓咪.png", mimeType: "image/png",
                                 fileSize: PNG_BYTES.bytesize } ]).sole
    expect(target["url"]).to eq("/admin/uploads/staged")

    upload!(target)
    expect(response).to have_http_status(:created)
    resource_url = response.parsed_body.fetch("resourceUrl")
    expect(resource_url).to eq(target["resourceUrl"])

    data = file_create!([ { originalSource: resource_url, alt: "一隻貓" } ])
    expect(data["userErrors"]).to eq([])
    file = data["files"].sole
    expect(file["status"]).to eq("READY")
    expect(file["filename"]).to end_with(".png")
    expect(file["byteSize"].to_i).to eq(PNG_BYTES.bytesize)

    ActsAsTenant.with_tenant(shop) do
      row = StoredFile.sole
      expect(row.checksum).to eq(Digest::SHA256.hexdigest(PNG_BYTES))
      expect(Storage::LocalDisk.read(row.storage_key)).to eq(PNG_BYTES)
      event = EventOutbox.find_by!(topic: Events::Topics::MEDIA_UPLOADED)
      expect(event.payload["file_id"]).to eq(row.id)
    end

    get file["url"]
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(PNG_BYTES)
  end

  it "上傳端點防線：竄改簽名 403；超簽名大小 400；他店 key 403" do
    login!
    target = staged_targets!([ { filename: "a.png", mimeType: "image/png", fileSize: 16 } ]).sole
    params = target["parameters"].to_h { |p| [ p["name"], p["value"] ] }

    file = Rack::Test::UploadedFile.new(StringIO.new("x" * 8), "image/png", original_filename: "a.png")
    post admin_staged_upload_path, params: params.merge("signature" => params["signature"].reverse, file: file)
    expect(response).to have_http_status(:forbidden)

    big = Rack::Test::UploadedFile.new(StringIO.new("x" * 64), "image/png", original_filename: "a.png")
    post admin_staged_upload_path, params: params.merge(file: big)
    expect(response).to have_http_status(:bad_request)

    other = create(:shop, subdomain: "staged-other")
    foreign = ActsAsTenant.with_tenant(other) do
      Storage::SignedUpload.issue(shop: other, filename: "b.png", byte_size: 16)
    end
    foreign_params = foreign.parameters.to_h { |p| [ p[:name], p[:value] ] }
    post admin_staged_upload_path, params: foreign_params.merge(file: file)
    expect(response).to have_http_status(:forbidden)
  end

  it "簽發預檢：mimeType 白名單、fileSize 超上限、檔名規則（保留字尾／HTML／點開頭）" do
    login!
    post_graphql(STAGED_MUTATION, variables: { input: [
      { filename: "a.mp4", mimeType: "video/mp4", fileSize: 10 },
      { filename: "big.png", mimeType: "image/png",
        fileSize: Limits.fetch(:content, :files_image_max_mb) * 1024 * 1024 + 1 },
      { filename: "photo_thumb.png", mimeType: "image/png", fileSize: 10 },
      { filename: "evil.html", mimeType: "image/png", fileSize: 10 },
      { filename: ".hidden.png", mimeType: "image/png", fileSize: 10 }
    ] })
    errors = response.parsed_body.dig("data", "stagedUploadsCreate", "userErrors")
    expect(errors.map { |e| e["code"] }).to contain_exactly(
      "UNACCEPTABLE_ASSET", "INVALID", "INVALID", "UNACCEPTABLE_ASSET", "INVALID")
    expect(response.parsed_body.dig("data", "stagedUploadsCreate", "stagedTargets")).to eq([])
  end

  it "撞名三模式：append_uuid 改名共存（引 uq 檔名非唯一）；raise_error INVALID；replace 保原 id 換 blob" do
    login!
    make = lambda do |mode|
      target = staged_targets!([ { filename: "同名.png", mimeType: "image/png",
                                   fileSize: PNG_BYTES.bytesize } ]).sole
      upload!(target)
      entry = { originalSource: response.parsed_body.fetch("resourceUrl"), filename: "同名.png" }
      entry[:duplicateResolutionMode] = mode if mode
      file_create!([ entry ])
    end

    first = make.call(nil)
    expect(first["userErrors"]).to eq([])
    original_id = first["files"].sole["id"]

    second = make.call("APPEND_UUID")
    expect(second["userErrors"]).to eq([])
    expect(second["files"].sole["filename"]).to match(/\A同名-\h{8}\.png\z/)

    third = make.call("RAISE_ERROR")
    expect(third["files"]).to eq([])
    expect(third["userErrors"].sole["code"]).to eq("INVALID")

    replaced = make.call("REPLACE")
    expect(replaced["userErrors"]).to eq([])
    expect(replaced["files"].sole["id"]).to eq(original_id)
    ActsAsTenant.with_tenant(shop) { expect(StoredFile.count).to eq(2) }
  end

  it "外部 URL 走 SSRF 防線：私網 host 被 Blocked ⇒ INVALID；staged 檔不存在 ⇒ FILE_DOES_NOT_EXIST" do
    login!
    allow(Resolv).to receive(:getaddresses).with("internal.test").and_return([ "10.0.0.5" ])
    data = file_create!([ { originalSource: "https://internal.test/x.png" } ])
    expect(data["files"]).to eq([])
    expect(data["userErrors"].sole["code"]).to eq("INVALID")

    ghost = Storage::SignedUpload.resource_url("shops/#{shop.id}/staged/#{SecureRandom.uuid}/g.png")
    data2 = file_create!([ { originalSource: ghost } ])
    expect(data2["userErrors"].sole["code"]).to eq("FILE_DOES_NOT_EXIST")
  end

  it "🔴 審查 C7：fileCreate 無 idempotencyKey ⇒ IDEMPOTENCY_KEY_REQUIRED（建立型強制帶 key）" do
    login!
    post_graphql(FILE_CREATE_MUTATION, variables: { files: [ { originalSource: "x" } ] })
    errors = response.parsed_body["errors"]
    expect(errors.sole.dig("extensions", "code")).to eq("IDEMPOTENCY_KEY_REQUIRED")
  end

  it "🔴 審查 C6：node/product 查詢 File GID 回 null（不 500、不型別混淆）" do
    login!
    q = "query($id: ID!) { product(id: $id) { id } }"
    post_graphql(q, variables: { id: "gid://chilllove/File/1" })
    expect(response.parsed_body.dig("data", "product")).to be_nil
    expect(response.parsed_body["errors"]).to be_nil
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
