# frozen_string_literal: true

require "rails_helper"

# 第 25 包審查回歸：FileCreate 的檔案系統×transaction 原子性（C2/C3/C4/C8）＋
# magic-byte 嗅探（C5）。
RSpec.describe Storage::FileCreate do
  let(:shop) { create(:shop, subdomain: "fc-shop") }

  PNG = [
    "89504e470d0a1a0a0000000d49484452000000010000000101030000002562d82200000006504c5445ffffff",
    "ffffff55c2d37e0000000a4944415408d76360000000020001e221bc330000000049454e44ae426082"
  ].join.scan(/../).map(&:hex).pack("C*").freeze

  def staged!(bytes: PNG)
    ActsAsTenant.with_tenant(shop) do
      target = Storage::SignedUpload.issue(shop:, filename: "a.png", byte_size: bytes.bytesize)
      Storage::LocalDisk.write(target.key, StringIO.new(bytes))
      target.resource_url
    end
  end

  it "🔴 審查 C2/C3/C8：DB commit 失敗時不留孤兒 blob，且 staged 原檔不被吞（fs 在 txn 外）" do
    resource_url = staged!
    staged_key = Storage::SignedUpload.staged_key_from(resource_url, shop:)

    # 讓 event 寫入炸掉 ⇒ 整個 txn rollback
    allow(EventOutbox).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")

    written = []
    deleted = []
    allow(Storage::LocalDisk).to receive(:write).and_wrap_original do |m, key, io|
      written << key
      m.call(key, io)
    end
    allow(Storage::LocalDisk).to receive(:delete).and_wrap_original do |m, key|
      deleted << key
      m.call(key)
    end

    result = ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, files_input: [ { original_source: resource_url } ])
    end
    expect(result.user_errors.sole[:code]).to eq("INVALID")
    ActsAsTenant.with_tenant(shop) { expect(StoredFile.count).to eq(0) }
    # 剛寫的新 blob 被補償刪除（不留孤兒）
    expect(deleted).to include(*written)
    written.each { |k| expect(Storage::LocalDisk.exist?(k)).to be(false) }
    # staged 原檔沒被 move 走（不 move ⇒ 仍在，留給孤兒清掃）
    expect(Storage::LocalDisk.exist?(staged_key)).to be(true)
  end

  it "🔴 審查 C4：batch 中一列 raise 不炸整批、不留孤兒；其餘列照常" do
    good1 = staged!
    good2 = staged!
    # 中間插一個會 raise 的來源（staged 檔在 exist? 後被刪 ⇒ read ENOENT）
    ghost = staged!
    ghost_key = Storage::SignedUpload.staged_key_from(ghost, shop:)
    allow(Storage::LocalDisk).to receive(:read).and_wrap_original do |m, key|
      key == ghost_key ? raise(Errno::ENOENT) : m.call(key)
    end

    result = ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, files_input: [
        { original_source: good1 }, { original_source: ghost }, { original_source: good2 } ])
    end
    expect(result.files.length).to eq(2)
    expect(result.user_errors.sole[:field]).to eq([ "files", "1", "originalSource" ])
    ActsAsTenant.with_tenant(shop) { expect(StoredFile.count).to eq(2) }
  end

  it "🔴 審查 C5：magic-byte 決定型別——宣告 image/png 實傳 HTML ⇒ UNACCEPTABLE_ASSET" do
    resource_url = staged!(bytes: "<html><script>alert(1)</script></html>")
    result = ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, files_input: [ { original_source: resource_url } ])
    end
    expect(result.files).to be_empty
    expect(result.user_errors.sole[:code]).to eq("UNACCEPTABLE_ASSET")
  end

  it "replace 模式：commit 後才刪舊 blob；rollback 時舊 blob 保留、row 仍指舊 key" do
    first = ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, files_input: [ { original_source: staged! } ]).files.sole
    end
    old_key = first.storage_key
    expect(Storage::LocalDisk.exist?(old_key)).to be(true)

    # 第二次 replace 但讓 event 炸 ⇒ rollback ⇒ 舊 blob 不得被刪、row 不得改
    allow(EventOutbox).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
    ActsAsTenant.with_tenant(shop) do
      described_class.call(shop:, files_input: [
        { original_source: staged!, filename: "a.png", duplicate_resolution_mode: "replace" } ])
      expect(first.reload.storage_key).to eq(old_key)
    end
    expect(Storage::LocalDisk.exist?(old_key)).to be(true)
  end
end
