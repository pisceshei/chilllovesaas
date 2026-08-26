# frozen_string_literal: true

require "rails_helper"

# 第 12 包**重做輪**（2026-08-26）補的三件事：
#   ①`Publishable` 三個型別**各自**都要有可見性判定——計畫表第 12 列的包名逐字是
#     「**Publishable** × Publication 兩層 AND 過濾器」，而初版只交付了 Product 一個。
#   ②「已發布」謂詞收斂成唯一產生處（`ResourcePublication.published_exists_sql`
#     ＋ `PUBLISHED_SQL`），SQL 側與 Ruby 側不得分岔（鐵律 7）。
#   ③系列列表的「前台可見件數」——計畫表第 12 列「部署後看得到什麼」欄的逐字交付。
#
# 🔴 每一格的測資都刻意落在**兩種實作會分岔**的那一點。
RSpec.describe "發布可見性（Publishable 三型別）" do
  let(:shop) { create(:shop, subdomain: "pubvis") }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store } }

  def second_channel
    ActsAsTenant.with_tenant(shop) do
      Publication.create!(shop_id: shop.id, name: "門市 POS", channel_handle: "pos",
                          auto_publish: true, supports_future_publishing: false)
    end
  end

  def rows_for(record)
    ActsAsTenant.without_tenant do
      ResourcePublication.where(publishable_type: record.class.name, publishable_id: record.id)
                         .pluck(:publication_id)
    end
  end

  def new_collection(handle:, type: "manual")
    ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: handle, handle:, description_html: "",
                         collection_type: type, sort_order: "manual")
    end
  end

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # ── ⓪ 預設管道的查法（S0 修）─────────────────────────────────────────────
  describe "Publication.online_store / .online_store!" do
    it "取得建店時自動建立的那一個" do
      expect(Publication.online_store).to be_present
      expect(Publication.online_store.channel_handle).to eq(Shop::DEFAULT_CHANNEL_HANDLE)
    end

    # 🔴 分岔點：把 `Shop::DEFAULT_CHANNEL_HANDLE` 改回硬寫的字面量，這一格仍會綠，
    #    所以另外加下面那格**結構性斷言**盯著它。
    it "🔴 handle 來自 `Shop::DEFAULT_CHANNEL_HANDLE`，不是自己再寫一次字面量" do
      source = File.read(Rails.root.join("app/models/publication.rb"), encoding: "UTF-8")
      body = source[/def self\.online_store\b.*?\n  end/m]

      expect(body).to be_present
      expect(body).to include("Shop::DEFAULT_CHANNEL_HANDLE")
      expect(body).not_to include('"online_store"'),
        "同一個值有兩個產生處：改了常數而沒改這裡 ⇒ 本方法靜默回 nil ⇒ 整店商品前台不可見且不拋錯"
    end

    it "🔴 `.online_store!` 在缺管道時大聲失敗（不得回 nil 讓呼叫端炸在別處）" do
      ActsAsTenant.without_tenant do
        # 🔴 順序：先刪 channel 再刪 publication。反過來會被
        #   `fk_channels_publication_id` 擋住（S0 第二批起 channels 指向 publications）。
        Channel.where(shop_id: shop.id).delete_all
        Publication.where(shop_id: shop.id, channel_handle: Shop::DEFAULT_CHANNEL_HANDLE).delete_all
      end

      expect(Publication.online_store).to be_nil
      expect { Publication.online_store! }
        .to raise_error(ActiveRecord::RecordNotFound, /沒有 online_store publication/)
    end

    # 🔴 **S0 第二批的權威遷移**：handle 的權威是 `channels.handle`，
    #   `publications.channel_handle` 已降級為 legacy 快照。這一格證明遷移**真的發生了**
    #   ——只留快照、沒有 channel 的 publication，在 `.online_store` 眼中不存在。
    #   拿掉 `joins(:channel)` 改回讀 `channel_handle`，這一格會轉紅。
    it "🔴 只有 legacy 快照、沒有 channel 的 publication 不算管道" do
      ActsAsTenant.without_tenant { Channel.where(shop_id: shop.id).delete_all }

      # 快照欄還在，值也還對——但權威來源沒了。
      orphan = ActsAsTenant.without_tenant { Publication.find_by(shop_id: shop.id) }
      expect(orphan.channel_handle).to eq(Shop::DEFAULT_CHANNEL_HANDLE)

      expect(Publication.online_store).to be_nil
      expect { Publication.online_store! }.to raise_error(ActiveRecord::RecordNotFound)
    end

    # 🔴 兩處 handle 必須一致。本尊的 handle 帶每店後綴（`shop-72`，`82` §10.3），
    #   我方 v1 用固定值——但快照與權威分岔的形態現在就要擋住，
    #   否則 S1 刪 `channel_handle` 欄時會發現兩邊早就不一樣了。
    it "🔴 channels.handle 與 publications.channel_handle 一致（快照不得漂移）" do
      publication = Publication.online_store!
      expect(publication.channel.handle).to eq(publication.channel_handle)
    end
  end

  # ── ① 謂詞的唯一產生處 ──────────────────────────────────────────────────
  describe "ResourcePublication.published_exists_sql" do
    it "🔴 target 是封閉集合——未知鍵直接拋，不得靜默產生錯誤 SQL" do
      expect { ResourcePublication.published_exists_sql(:not_a_target) }.to raise_error(KeyError)
    end

    it "每個合法 target 都產生帶三個具名 bind 的 EXISTS" do
      ResourcePublication::VISIBILITY_TARGETS.each_key do |target|
        sql = ResourcePublication.published_exists_sql(target)
        expect(sql).to start_with("EXISTS (")
        expect(sql).to include(":shop_id", ":publication_id", ":at")
        # 🔴 **正向謂詞**：不得出現 `NOT EXISTS` 或 `NOT (`——對可空欄取反會讓
        #    NULL 變 UNKNOWN 而靜默漏掉整批列（第 11 包踩了三次）。
        #    `IS NOT NULL` 是**合法的**，它不是對謂詞取反，所以不能一律禁 NOT。
        expect(sql).not_to match(/NOT\s+EXISTS/i)
        expect(sql).not_to match(/NOT\s*\(/i)
      end
    end
  end

  # ── ② SQL 側與 Ruby 側同義 ─────────────────────────────────────────────
  describe "PUBLISHED_SQL 與 #published? 是同一條規則的兩種寫法" do
    # 🔴 這一格用**同一批時點**同時跑兩側再比對。只改一邊就會轉紅——那正是
    #    第 12 包初版留下的分叉（G29／P12-B13），本輪收斂後由這一格守住。
    it "四個代表性時點上，兩側逐一相等" do
      product = create(:product, shop:)
      create(:product_variant, product:)
      row = ActsAsTenant.without_tenant do
        ResourcePublication.find_by(publishable_type: "Product", publishable_id: product.id)
      end
      at = Time.current

      cases = { nil => false, 1.day.ago => true, at => true, 1.day.from_now => false }

      cases.each do |published_at, expected|
        ActsAsTenant.without_tenant { row.update_columns(published_at:) }
        row.reload

        ruby_side = row.published?(at:)
        sql_side = Product.where(id: product.id)
                          .where(ResourcePublication.published_exists_sql(:product),
                                 shop_id: shop.id, publication_id: online_store.id, at:)
                          .exists?

        expect(ruby_side).to eq(expected), "Ruby 側在 #{published_at.inspect} 上不符預期"
        expect(sql_side).to eq(ruby_side),
          "SQL 側與 Ruby 側在 #{published_at.inspect} 上分岔了（鐵律 7）"
      end
    end
  end

  # ── ③ Collection：只有一層 ─────────────────────────────────────────────
  describe "Collection.published_on" do
    it "已發布的系列進得來" do
      collection = new_collection(handle: "col-a")

      expect(Collection.published_on(online_store)).to contain_exactly(collection)
    end

    it "🔴 系列**沒有變體層也沒有 status 層**——刪掉它自己的發布列就不可見" do
      collection = new_collection(handle: "col-b")
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "Collection", publishable_id: collection.id).delete_all
      end

      expect(Collection.published_on(online_store)).to be_empty
    end

    it "🔴 只算目標管道：發布到別的管道不算數" do
      pos = second_channel
      collection = new_collection(handle: "col-c")
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "Collection", publishable_id: collection.id,
                                  publication_id: online_store.id).delete_all
      end
      expect(rows_for(collection)).to eq([ pos.id ])

      expect(Collection.published_on(online_store)).to be_empty
      expect(Collection.published_on(pos)).to contain_exactly(collection)
    end

    it "🔴 排程發布：`published_at` 在未來 ⇒ 到點前不可見" do
      collection = new_collection(handle: "col-d")
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "Collection", publishable_id: collection.id)
                           .update_all(published_at: 1.day.from_now)
      end

      expect(Collection.published_on(online_store)).to be_empty
      expect(Collection.published_on(online_store, at: 2.days.from_now)).to contain_exactly(collection)
    end

    it "跨租戶：別間店的系列不會進來" do
      new_collection(handle: "col-e")
      other = create(:shop, subdomain: "pubvis-other")
      ActsAsTenant.with_tenant(other) do
        Collection.create!(shop_id: other.id, title: "他家", handle: "col-e", description_html: "",
                           collection_type: "manual", sort_order: "manual")
      end

      expect(Collection.published_on(online_store).map(&:shop_id).uniq).to eq([ shop.id ])
    end
  end

  # ── ④ ProductVariant：本尊真值表的第三條 ───────────────────────────────
  describe "ProductVariant.purchasable_on" do
    let(:product) { create(:product, shop:, status: "active") }
    let!(:variant_a) { create(:product_variant, product:, title: "A") }

    it "商品可購買 ∧ 本變體已發布 ⇒ 可購買" do
      expect(ProductVariant.purchasable_on(publication: online_store)).to contain_exactly(variant_a)
    end

    # 分岔點：只看商品層的實作在這一格會回傳 variant_b。
    #
    # ⚠️ 同一商品的第二個變體**必須帶不同的選項座標**——無選項變體的
    #    `option_values_digest` 都是 NO_OPTIONS，第二個會撞
    #    `uq_product_variants_option_values_digest`（D12 的不變量，
    #    `spec/factories/product_variants.rb` 檔頭已寫明）。
    it "🔴 **這一個**變體未發布 ⇒ 它不可購買，但同商品的另一個仍可" do
      sized = create(:product, shop:, status: "active")
      option = create(:product_option, product: sized, values: %w[S M])
      s_value, m_value = option.option_values.order(:position).to_a

      kept = create(:product_variant, product: sized, title: "S", option_values: [ s_value ])
      dropped = create(:product_variant, product: sized, title: "M", option_values: [ m_value ])

      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "ProductVariant", publishable_id: dropped.id).delete_all
      end

      result = ProductVariant.purchasable_on(publication: online_store)
      expect(result).to include(kept)
      expect(result).not_to include(dropped)
    end

    # 分岔點：漏掉父商品那一半的實作在這一格會回傳 variant_a。
    it "🔴 父商品未發布 ⇒ 變體不可購買（本尊真值表第 3 列 Unpublished/Published=No）" do
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).delete_all
      end

      expect(ProductVariant.purchasable_on(publication: online_store)).to be_empty
    end

    # 分岔點：漏掉狀態層的實作在這一格會回傳 variant_a。
    it "🔴 父商品是 draft ⇒ 變體不可購買" do
      ActsAsTenant.with_tenant(shop) { product.update!(status: "draft") }

      expect(ProductVariant.purchasable_on(publication: online_store)).to be_empty
    end

    it "UNLISTED 的父商品：變體仍可購買（可購買但不可發現）" do
      ActsAsTenant.with_tenant(shop) { product.update!(status: "unlisted") }

      expect(ProductVariant.purchasable_on(publication: online_store)).to contain_exactly(variant_a)
    end
  end

  # ── ⑤ 系列列表的兩個數字 ───────────────────────────────────────────────
  describe "Collection.with_member_counts（計畫表第 12 列的可見交付）" do
    let(:collection) { new_collection(handle: "counted") }

    def add_member(product)
      ActsAsTenant.with_tenant(shop) do
        CollectionProduct.create!(shop_id: shop.id, collection_id: collection.id, product_id: product.id)
      end
    end

    def sellable(status:)
      product = create(:product, shop:, status:)
      create(:product_variant, product:)
      add_member(product)
      product
    end

    def counts
      row = Collection.with_member_counts(publication: online_store).find(collection.id)
      [ row.read_attribute("member_count").to_i, row.read_attribute("visible_member_count").to_i ]
    end

    it "全部可發現時，兩個數字相等" do
      sellable(status: "active")
      sellable(status: "active")

      expect(counts).to eq([ 2, 2 ])
    end

    # 🔴 這一格是本組的核心：本尊官方「An unlisted product doesn't display in
    #    Shopify-powered collection pages」⇒ 前台可見件數必須用 discoverable。
    #    分岔點：實作若用 purchasable，這一格會得到 [2, 2]。
    it "🔴 UNLISTED 成員計入後台但**不計入前台可見**（判準是 discoverable 不是 purchasable）" do
      sellable(status: "active")
      sellable(status: "unlisted")

      expect(counts).to eq([ 2, 1 ])
    end

    it "draft 與 archived 成員也不計入前台可見" do
      sellable(status: "active")
      sellable(status: "draft")
      sellable(status: "archived")

      expect(counts).to eq([ 3, 1 ])
    end

    # 分岔點：只看 status 不看發布層的實作在這一格會得到 [1, 1]。
    it "🔴 狀態 active 但**商品層未發布** ⇒ 不計入前台可見" do
      product = sellable(status: "active")
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).delete_all
      end

      expect(counts).to eq([ 1, 0 ])
    end

    # 分岔點：漏掉變體層 EXISTS 的實作在這一格會得到 [1, 1]。
    it "🔴 狀態 active、商品層已發布，但**所有變體都未發布** ⇒ 不計入前台可見" do
      product = sellable(status: "active")
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "ProductVariant").delete_all
      end
      expect(product.product_variants.count).to eq(1)

      expect(counts).to eq([ 1, 0 ])
    end

    it "🔴 publication 為 nil ⇒ 只帶後台數字（沒有管道就沒有前台可談）" do
      sellable(status: "active")
      row = Collection.with_member_counts(publication: nil).find(collection.id)

      expect(row.read_attribute("member_count").to_i).to eq(1)
      expect(row.has_attribute?("visible_member_count")).to be(false)
    end

    it "智慧系列走 collection_memberships（型別分流與 member_count 同源）" do
      smart = new_collection(handle: "smart-counted", type: "smart")
      product = create(:product, shop:, status: "active")
      create(:product_variant, product:)
      ActsAsTenant.with_tenant(shop) do
        CollectionMembership.create!(shop_id: shop.id, collection_id: smart.id, product_id: product.id)
      end

      row = Collection.with_member_counts(publication: online_store).find(smart.id)
      expect(row.read_attribute("member_count").to_i).to eq(1)
      expect(row.read_attribute("visible_member_count").to_i).to eq(1)
    end
  end

  # ── ⑥ cache stamp ──────────────────────────────────────────────────────
  describe "products.publications_updated_at（cache stamp）" do
    it "建立商品時被推上去（schema 註釋逐字指名「寫入者隨第 12 包」）" do
      product = create(:product, shop:)

      expect(product.reload.publications_updated_at).to be_present
    end

    it "🔴 建立**變體**時推的是**父商品**的戳（變體發布狀態會改變商品的有效可購買性）" do
      product = create(:product, shop:)
      ActsAsTenant.with_tenant(shop) do
        product.update_columns(publications_updated_at: 3.days.ago)
      end

      create(:product_variant, product:)

      expect(product.reload.publications_updated_at).to be > 1.hour.ago
    end

    # 🔴 這一格守的是一個實測踩到的坑：`update_all` 的 hash 形式會替啟用樂觀鎖的
    #    model 自動遞增 `lock_version` ⇒ 建立發布列會把商家手上開著的編輯表單直接作廢。
    #    分岔點：改回 hash 形式的 `update_all` 會讓這一格轉紅。
    it "🔴 推 cache stamp **不得**動 lock_version（否則商家開著的編輯表單會無故作廢）" do
      product = create(:product, shop:)
      before_lock = product.reload.lock_version

      Product.bump_publications_stamp!(shop_id: shop.id, id: product.id, at: Time.current)

      expect(product.reload.lock_version).to eq(before_lock)
      # 而且要能繼續存檔，不得 StaleObjectError
      expect { ActsAsTenant.with_tenant(shop) { product.update!(status: "draft") } }.not_to raise_error
    end

    it "系列不推商品戳（collections 表沒有這個欄位，不得挪用 products_updated_at）" do
      collection = new_collection(handle: "no-stamp")

      expect(collection).to be_persisted
      expect(Collection.column_names).not_to include("publications_updated_at")
    end
  end
end
