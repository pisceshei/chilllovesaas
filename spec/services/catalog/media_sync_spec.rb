# frozen_string_literal: true

require "rails_helper"

# 第 27 包審查回歸（C0/C1/C2/C5/C6/C15/C24）：MediaSync 的併發、狀態與引用計數。
# 🔴 建這一檔本身就是審查 C24 的處置：原本只靠 request spec，容量／併發／
#    引用計數的邊界全部沒被直接覆蓋。
RSpec.describe Catalog::MediaSync do
  let(:shop) { create(:shop, subdomain: "msync-shop") }
  let(:product) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product } }

  def make_file!(status: "uploaded")
    ActsAsTenant.with_tenant(shop) do
      key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
      Storage::LocalDisk.write(key, StringIO.new("BYTES"))
      StoredFile.create!(filename: "a.png", content_type: "image/png", byte_size: 5,
                         checksum: SecureRandom.hex(32), storage_key: key, status:,
                         width: 100, height: 80)
    end
  end

  def create!(count: 1, alt: nil)
    ActsAsTenant.with_tenant(shop) do
      described_class.create(shop:, product:,
                             entries: Array.new(count) { { file_id: make_file!.id, alt: } })
    end
  end

  it "🔴 審查 C2：media.status 是建立當下的快照，讀取面必須讀 files.status" do
    ActsAsTenant.with_tenant(shop) do
      file = make_file!(status: "uploaded")
      row = described_class.create(shop:, product:, entries: [ { file_id: file.id } ]).media.sole
      expect(row.status).to eq("uploaded")

      # 管線把檔案轉 ready——媒體列**不會**跟著改（這正是不能讀它的原因）
      file.update!(status: "ready")
      expect(row.reload.status).to eq("uploaded")
      # 讀取面走 stored_file ⇒ 看得到真實狀態。GraphQL type 不能裸實例化，
      # 這裡驗它讀的來源；端到端（卡片不會卡在「處理中」）由
      # spec/requests/product_media_spec.rb 的 media { status } 查詢覆蓋。
      expect(row.stored_file.reload.status).to eq("ready")
    end
  end

  it "🔴 審查 C0：位置衝突不得漏成例外——RecordNotUnique 轉 CONFLICT userError" do
    create!(count: 1)
    file = make_file!
    # 模擬鎖之外的並發：插入時撞唯一索引
    allow(Media).to receive(:create!).and_raise(
      ActiveRecord::RecordNotUnique.new("Duplicate entry for key 'uq_media_product_id_position'"),
    )
    result = ActsAsTenant.with_tenant(shop) do
      described_class.create(shop:, product:, entries: [ { file_id: file.id } ])
    end
    expect(result.media).to be_empty
    expect(result.user_errors.sole[:code]).to eq("CONFLICT")
  end

  it "🔴 審查 C1：容量檢查在鎖內——超過 max_media 回 MEDIA_LIMIT_EXCEEDED" do
    allow(Limits).to receive(:fetch).and_call_original
    allow(Limits).to receive(:fetch).with(:product, :max_media).and_return(2)
    expect(create!(count: 2).user_errors).to be_empty

    result = create!(count: 1)
    expect(result.media).to be_empty
    expect(result.user_errors.sole[:code]).to eq("MEDIA_LIMIT_EXCEEDED")
    ActsAsTenant.with_tenant(shop) { expect(Media.count).to eq(2) }
  end

  it "🔴 審查 C5：fileId 分支也驗 alt 長度（不得漏成 RecordInvalid）" do
    file = make_file!
    result = ActsAsTenant.with_tenant(shop) do
      described_class.create(shop:, product:, entries: [ { file_id: file.id, alt: "x" * 513 } ])
    end
    expect(result.user_errors.sole[:code]).to eq("ALT_VALUE_LIMIT_EXCEEDED")
    ActsAsTenant.with_tenant(shop) do
      expect(Media.count).to eq(0)
      # 🔴 D48：alt 現在寫檔案層 ⇒ 超長被擋下時**檔案也不得被污染**。
      #    舊版沒有這條，因為當年 alt 根本不碰 files。
      expect(file.reload.alt_text).to be_nil
    end
  end

  it "🔴 D48：建立時的 alt 落在**檔案**上，不落媒體列（停用欄）" do
    ActsAsTenant.with_tenant(shop) do
      file = make_file!
      row = described_class.create(shop:, product:,
                                   entries: [ { file_id: file.id, alt: "貓在窗邊" } ]).media.sole
      expect(file.reload.alt_text).to eq("貓在窗邊")
      expect(row.reload.alt_text).to be_nil
      # 讀取面看得到（權威在檔案 ⇒ 媒體讀它）
      expect(row.stored_file.alt_text).to eq("貓在窗邊")
    end
  end

  it "🔴 D48：掛既有檔案而**不送 alt** 時，不得清掉檔案庫已寫好的說明" do
    ActsAsTenant.with_tenant(shop) do
      file = make_file!
      file.update!(alt_text: "檔案庫寫好的說明")
      described_class.create(shop:, product:, entries: [ { file_id: file.id } ])
      expect(file.reload.alt_text).to eq("檔案庫寫好的說明")
    end
  end

  it "🔴 審查 C6：product.destroy!（不經 MediaSync.delete）也釋放引用計數" do
    create!(count: 2)
    ActsAsTenant.with_tenant(shop) do
      expect(FileUsage.where(owner_type: "Media").count).to eq(2)
      product.destroy!
      expect(FileUsage.where(owner_type: "Media").count).to eq(0)
    end
  end

  it "🔴 審查 C15：外部抓檔在 transaction 之外（鐵律 5：交易內禁外部 IO）" do
    # 🔴 判準不能用 `transaction_open?`——rspec 本身把每個 example 包在測試交易裡，
    #    它恆為 true。改測**巢狀深度**：FileCreate 被呼叫時不得比 example 起點更深。
    baseline = ActiveRecord::Base.connection.open_transactions
    depth_at_call = nil
    allow(Storage::FileCreate).to receive(:call) do
      depth_at_call = ActiveRecord::Base.connection.open_transactions
      Storage::FileCreate::Result.new(files: [ make_file! ], user_errors: [])
    end
    ActsAsTenant.with_tenant(shop) do
      described_class.create(shop:, product:, entries: [ { original_source: "https://x.test/a.png" } ])
    end
    expect(depth_at_call).to eq(baseline)
  end

  it "重排＋刪除後 position 恆為 1..n 連續且無重複" do
    ids = create!(count: 4).media.map(&:id)
    ActsAsTenant.with_tenant(shop) do
      described_class.reorder(shop:, product:, media_ids: ids.reverse)
      described_class.delete(shop:, product:, media_ids: [ ids[1] ])
      positions = Media.where(product_id: product.id).order(:position).pluck(:position)
      expect(positions).to eq([ 1, 2, 3 ])
    end
  end
end
