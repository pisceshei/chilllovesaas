# frozen_string_literal: true

require "rails_helper"

# 第 11 包：規則編輯 vs 增量重算的併發（研究 §5 的序列化點＝collection 列鎖）。
#
# 🔴 競態窗必須人工撐開（第 6 包教訓：MRI 的 GIL 下兩執行緒自然序列化＝假綠）。
# 危險交錯：resync 在規則編輯 commit 前讀舊規則、在編輯後才落庫 ⇒ 舊蓋新且無錯誤。
# 防線＝resync 的逐系列短 txn 內 `Collection.lock`（鎖定讀讀最新已提交規則）。
RSpec.describe "智慧系列引擎併發" do
  self.use_transactional_tests = false

  def purge!
    EventOutbox.unscoped.delete_all
    CollectionMembership.unscoped.delete_all
    CollectionSourceRule.unscoped.delete_all
    CollectionSource.unscoped.delete_all
    ProductTag.unscoped.delete_all
    IdempotencyKey.unscoped.delete_all
    InventoryLevel.unscoped.delete_all
    InventoryItem.unscoped.delete_all
    Location.unscoped.delete_all
    ProductVariantOptionValue.unscoped.delete_all
    OptionValue.unscoped.delete_all
    ProductOption.unscoped.delete_all
    ProductVariant.unscoped.delete_all
    Media.unscoped.delete_all
    CollectionProduct.unscoped.delete_all
    Collection.unscoped.delete_all
    Product.unscoped.delete_all
    Publication.unscoped.delete_all
    Translation.unscoped.delete_all
    TranslationStatus.unscoped.delete_all
    ShopLocale.unscoped.delete_all
    UserStoreAssignment.unscoped.delete_all
    StaffMember.unscoped.delete_all
    Shop.delete_all
  end

  before { purge! }
  after { purge! }

  let!(:shop) { create(:shop, subdomain: "eng-conc") }

  it "🔴 resync 與規則編輯交錯：resync 的鎖定讀必見**最新已提交**規則，不得用舊規則落庫" do
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ], product_type: "香水")
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    collection = ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "紅色", handle: "reds",
                             collection_type: "smart", sort_order: "manual", description_html: "")
      s = CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                                   target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: s.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      c
    end

    # 撐開窗：resync 執行緒先起跑、在「取得 collection 鎖之前」被閘住；
    # 主執行緒此刻把規則改成 blue 並 commit；然後放行 resync。
    # 正確行為＝resync 鎖下重讀規則 ⇒ 看到 blue ⇒ 商品不再命中 ⇒ 不加入。
    reached = Queue.new
    release = Queue.new
    gated = false
    allow(Collection).to receive(:lock).and_wrap_original do |orig, *args|
      if !gated && Thread.current[:resync_thread]
        gated = true
        reached << :ok
        release.pop
      end
      orig.call(*args)
    end

    resync = Thread.new do
      Thread.current[:resync_thread] = true
      ActiveRecord::Base.connection_pool.with_connection do
        Collections::ResyncProduct.call(shop:, product_id: product.id)
      end
    end
    reached.pop
    # 主執行緒：把規則改掉並 commit（模擬商家同時編輯規則）。
    ActsAsTenant.with_tenant(shop) do
      CollectionSourceRule.where(shop_id: shop.id).update_all(value_text: "blue")
    end
    release << :go
    result = resync.value

    expect(result.joined).to eq(0),
      "resync 用了閘住之前讀的舊規則（red）落庫——鎖定讀防線失效"
    members = ActsAsTenant.with_tenant(shop) do
      CollectionMembership.where(collection_id: collection.id).pluck(:product_id)
    end
    expect(members).to be_empty
  end
end
