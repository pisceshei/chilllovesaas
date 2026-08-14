# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductVariant, type: :model do
  let(:shop) { create(:shop) }
  let(:product) { create(:product, shop:) }

  # ── SKU 是軟唯一（61 §1.5 / limits.yml:2504）──────────────────────────────
  #
  # 🔴 這一組**不用執行緒**，而且不是偷懶：唯一索引會在**第二筆 INSERT** 就 raise，
  # 與併發無關。順序寫入寫得進去，就證明 DB 層的唯一索引真的不在了。
  # 為併發而併發會寫出一條看起來嚴謹、實際上不多測任何東西的測試。
  # （真正需要執行緒的那一條在下面「唯一索引沒有被誤傷」——理由寫在那裡。）
  describe "SKU 軟唯一" do
    it "同一間店允許重複 SKU（同款不同包裝共用庫存編號，61 §1.5）" do
      ActsAsTenant.with_tenant(shop) do
        first = create(:product_variant, product:, sku: "LIP-001")
        second = create(:product_variant, product:, sku: "LIP-001")

        expect([ first, second ].map(&:persisted?)).to eq([ true, true ])
        expect(described_class.where(sku: "LIP-001").count).to eq(2)
      end
    end

    it "CSV 批次匯入形態：同一批次多筆重複 SKU 全部寫入，不中途失敗" do
      ActsAsTenant.with_tenant(shop) do
        expect {
          5.times { create(:product_variant, product:, sku: "BULK-1") }
        }.not_to raise_error

        expect(described_class.where(sku: "BULK-1").count).to eq(5)
      end
    end

    it "SKU 長度不驗證（官方 16 字元是建議不是上限，limits.yml:2509）" do
      ActsAsTenant.with_tenant(shop) do
        variant = build(:product_variant, product:, sku: "A" * 120)
        expect(variant).to be_valid
      end
    end
  end

  # ── 租戶隔離（鐵律 2）─────────────────────────────────────────────────────
  describe "租戶隔離" do
    it "兩間店可以各有同一組 SKU，且互相看不見" do
      other_shop = create(:shop)
      # 🔴 `Product` 受 acts_as_tenant fail-closed（require_tenant=true），
      # 在 tenant 之外 create 會 raise NoTenantSet——這是設計要的，不是測試的麻煩。
      other_product = ActsAsTenant.with_tenant(other_shop) { create(:product, shop: other_shop) }

      ActsAsTenant.with_tenant(shop) { create(:product_variant, product:, sku: "SHARED") }
      ActsAsTenant.with_tenant(other_shop) { create(:product_variant, product: other_product, sku: "SHARED") }

      ActsAsTenant.with_tenant(shop) do
        expect(described_class.where(sku: "SHARED").count).to eq(1)
      end
      ActsAsTenant.with_tenant(other_shop) do
        expect(described_class.where(sku: "SHARED").count).to eq(1)
      end
    end
  end

  # ── 索引形狀（鐵律 2：複合索引以 shop_id 開頭）───────────────────────────
  describe "sku 索引" do
    let(:index) do
      ActiveRecord::Base.connection.indexes(:product_variants).find { |i| i.name == "ix_product_variants_sku" }
    end

    it "存在、非唯一、且以 shop_id 開頭" do
      expect(index).to be_present
      expect(index.unique).to be(false)
      expect(index.columns).to eq(%w[shop_id sku])
    end

    it "舊的唯一索引已經不在（防止有人在別的 migration 裡把它加回來）" do
      names = ActiveRecord::Base.connection.indexes(:product_variants).map(&:name)
      expect(names).not_to include("uq_product_variants_sku")
    end

    it "沒有誤傷 product_variants 的其他索引" do
      names = ActiveRecord::Base.connection.indexes(:product_variants).map(&:name)
      expect(names).to include(
        "uq_product_variants_tenant_id",
        "uq_product_variants_product_id_position",
        "ix_product_variants_product_id",
        "ix_product_variants_barcode"
      )
    end
  end
end

# ── 唯一索引沒有被誤傷（真併發）────────────────────────────────────────────
#
# 🔴 **為什麼這一條非用執行緒不可**：`Product` 有 model 層的
# `validates :handle, uniqueness:`，順序寫入時它自己就會擋下來——
# 於是「唯一索引還在不在」在順序測試裡**永遠測不到**（validation 先擋，索引沒機會發言）。
# 只有兩條連線同時通過 validation 再同時 INSERT，才會逼 DB 的
# `uq_products_handle` 出面。降級 SKU 索引時最容易的誤操作就是連帶動到別的索引，
# 而那種誤操作**只會在併發下顯形**——正是 CLAUDE.md「併發要害必須有測試」要防的形態。
#
# 🔴 `use_transactional_tests = false`：預設的 transactional fixtures 讓每個 example
# 跑在一個未 commit 的交易裡，另一條連線**看不到**它的資料 ⇒ 兩個執行緒各寫各的，
# 兩邊都成功，測試永遠綠。那會是一條假的併發測試。
RSpec.describe "唯一索引在併發下仍然有效", type: :model do
  self.use_transactional_tests = false

  # 🔴 刪除順序必須由葉往根：`product_variants` 對 `products` 有複合外鍵
  # （`fk_product_variants_product_id (shop_id, product_id)`），先刪 products 會撞 FK。
  # 這是關掉 transactional fixtures 的代價——清理要自己做對，做錯會讓**下一個** example
  # 帶著髒資料跑，而錯誤訊息會出現在無辜的地方。
  #
  # 🔴 **before 也要清一次**，不是只清 after：`after` 自己失敗過一次（外鍵順序寫錯），
  # 於是殘留的 shops 讓**下一次整個 rspec 程序**在 subdomain sequence 重新從 1 開始時撞唯一索引，
  # 而失敗訊息出現在一條與它無關的 example 上。非交易式測試必須能自我修復，
  # 否則一次崩潰會污染之後每一次執行。
  def purge!
    ProductVariant.unscoped.delete_all
    Product.unscoped.delete_all
    Publication.unscoped.delete_all if defined?(Publication)
    Shop.delete_all
  end

  before { purge! }
  after { purge! }

  it "同一間店同時寫入相同 handle：恰好一筆成功，另一筆被 DB 擋下" do
    shop = ActsAsTenant.without_tenant { create(:shop) }
    errors = Queue.new
    ok = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActsAsTenant.with_tenant(shop) do
            # 繞過 model validation，直接讓 DB 索引發言——本測試要驗的是索引不是 validation。
            Product.insert!({
              shop_id: shop.id, title: "併發", handle: "race-handle",
              description_html: "", status: "draft", tags: [],
              created_at: Time.current, updated_at: Time.current
            })
            ok << true
          end
        end
      rescue ActiveRecord::RecordNotUnique => e
        errors << e
      end
    end
    threads.each(&:join)

    expect(ok.size).to eq(1)
    expect(errors.size).to eq(1)
    expect(ActsAsTenant.without_tenant { Product.where(handle: "race-handle").count }).to eq(1)
  end

  it "同一間店同時寫入相同 SKU：兩筆都成功（降級後的預期行為）" do
    shop = ActsAsTenant.without_tenant { create(:shop) }
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    ok = Queue.new
    errors = Queue.new

    threads = 2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActsAsTenant.with_tenant(shop) do
            ProductVariant.insert!({
              shop_id: shop.id, product_id: product.id, title: "併發變體 #{i}",
              position: i + 1, sku: "RACE-SKU", price_cents: 0, currency: "HKD",
              created_at: Time.current, updated_at: Time.current
            })
            ok << true
          end
        end
      rescue ActiveRecord::RecordNotUnique => e
        errors << e
      end
    end
    threads.each(&:join)

    expect(errors.size).to eq(0)
    expect(ok.size).to eq(2)
    expect(ActsAsTenant.without_tenant { ProductVariant.where(sku: "RACE-SKU").count }).to eq(2)
  end
end
