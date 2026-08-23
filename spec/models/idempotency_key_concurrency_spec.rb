# frozen_string_literal: true

require "rails_helper"

# claim 搶佔的執行緒級測試（11 §2.1：唯一索引是併發防線的本體）。
#
# 🔴 `use_transactional_tests = false`：預設的 transactional fixtures 讓每個 example
# 包在未 commit 的 transaction 裡，其他執行緒的連線**看不到**主執行緒建的資料、
# 唯一索引的互斥也要等 commit 才對外發生——這個測試要驗的正是跨連線的索引互斥，
# 所以必須用真 commit ＋ 事後清理（同 spec/models/product_variant_spec.rb 的骨架）。
RSpec.describe IdempotencyKey, "concurrency" do
  self.use_transactional_tests = false

  # 刪除順序由葉往根（同 product_variant_spec 的骨架與教訓）：
  # Shop 建立時的 callback 會生出 publications 列，delete_all 不跑 callback，
  # 先刪 shops 會撞 fk_publications_shop。
  def purge!
    ActsAsTenant.without_tenant do
      IdempotencyKey.delete_all
      UserStoreAssignment.unscoped.delete_all
      Publication.unscoped.delete_all if defined?(Publication)
      Shop.delete_all
    end
  end

  before { purge! }
  after { purge! }

  it "同 key 並發 claim：恰一個 INSERT 成功，另一個被唯一索引擋下" do
    shop = ActsAsTenant.without_tenant { create(:shop, subdomain: "idem-race") }
    fingerprint = Idempotency::CanonicalJson.fingerprint({ "t" => "1" })
    ok = Queue.new
    errors = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActsAsTenant.with_tenant(shop) do
            IdempotencyKey.create!(
              key: "race-key", mutation_name: "ProductSet", state: "processing",
              params_fingerprint: fingerprint, expires_at: 1.hour.from_now
            )
            ok << true
          end
        end
      rescue ActiveRecord::RecordNotUnique => error
        errors << error
      end
    end
    threads.each(&:join)

    expect(ok.size).to eq(1)
    expect(errors.size).to eq(1)
    ActsAsTenant.without_tenant do
      expect(IdempotencyKey.where(key: "race-key").count).to eq(1)
    end
  end
end
