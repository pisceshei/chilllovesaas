# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product, type: :model do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # ── 四態值域（13 §F1.2 / limits.yml:804）─────────────────────────────────
  describe "狀態值域" do
    it "是四態，且逐字等於 limits.yml 的宣告（鐵律 6：不得硬編）" do
      expect(described_class::STATUSES)
        .to eq(Limits.enum(:product, :status_values).map(&:downcase))
      expect(described_class::STATUSES).to contain_exactly("active", "draft", "archived", "unlisted")
    end

    it "接受 unlisted" do
      product = build(:product, shop:, status: "unlisted")
      expect(product).to be_valid
    end

    it "拒絕值域外的狀態" do
      product = build(:product, shop:, status: "published")
      expect(product).not_to be_valid
      expect(product.errors[:status]).to be_present
    end

    # 🔴 這一條是**規格自己的恆等不變量**（limits.yml:809
    # `discoverable_subset_of_purchasable: true`），不是我發明的斷言。
    # 違反＝把買家從搜尋結果送進一個買不了的頁面（soft-404）。
    it "discoverable ⊆ purchasable（13 §F1.2 恆等不變量）" do
      expect(Limits.fetch(:product, :discoverable_subset_of_purchasable)).to be(true)
      expect(described_class::DISCOVERABLE_STATUSES - described_class::PURCHASABLE_STATUSES).to be_empty
    end

    it "UNLISTED 可購買但不可被發現——這正是它存在的理由" do
      expect(described_class::PURCHASABLE_STATUSES).to include("unlisted")
      expect(described_class::DISCOVERABLE_STATUSES).not_to include("unlisted")
    end
  end

  # ── 單一產生器（鐵律 7）──────────────────────────────────────────────────
  describe ".with_status_set" do
    let!(:active) { create(:product, shop:, status: "active") }
    let!(:unlisted) { create(:product, shop:, status: "unlisted") }
    let!(:draft) { create(:product, shop:, status: "draft") }
    let!(:archived) { create(:product, shop:, status: "archived") }

    it "purchasable 集合選出 active 與 unlisted" do
      result = described_class.with_status_set(described_class::PURCHASABLE_STATUSES, shop_id: shop.id)
      expect(result).to contain_exactly(active, unlisted)
    end

    it "discoverable 集合只選出 active" do
      result = described_class.with_status_set(described_class::DISCOVERABLE_STATUSES, shop_id: shop.id)
      expect(result).to contain_exactly(active)
    end

    it "帶明確 shop_id 作 defense in depth：別的租戶的商品不會進來" do
      other_shop = create(:shop)
      ActsAsTenant.with_tenant(other_shop) { create(:product, shop: other_shop, status: "active") }

      result = described_class.with_status_set(described_class::PURCHASABLE_STATUSES, shop_id: shop.id)
      expect(result.map(&:shop_id).uniq).to eq([ shop.id ])
    end

    it "不回傳 draft 與 archived（兩者 purchasable 與 discoverable 皆為 false）" do
      purchasable = described_class.with_status_set(described_class::PURCHASABLE_STATUSES, shop_id: shop.id)
      expect(purchasable).not_to include(draft, archived)
    end
  end

  # ── 發布層（第 12 包）────────────────────────────────────────────────────
  #
  # 🔴 這一組取代了原本的「刻意未實作」區塊（它斷言 `not_to respond_to(:purchasable)`）。
  # 當時不做的理由是**寫入端缺席**：沒有人建發布列，加上讀取面等於全站靜默下架。
  # 本包補上 `Publications::Materialize` ＋ 三個 `after_create` ＋ 回填 migration 後解除。
  #
  # 🔴 **每一格的測資都刻意落在「兩種實作會分岔」的那一點**——第 11 包連續踩了六種
  # 突變假綠，全部同一個根因：測資落在兩個實作**不會**分岔的那一格。
  describe "發布層" do
    let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store } }

    # 第二個管道。`Shop#after_create` 只建 online_store，多管道要自己建。
    def second_channel(auto_publish: true)
      ActsAsTenant.with_tenant(shop) do
        Publication.create!(shop_id: shop.id, name: "門市 POS", channel_handle: "pos",
                            auto_publish:, supports_future_publishing: false)
      end
    end

    def publications_of(record)
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: record.class.name, publishable_id: record.id)
                           .pluck(:publication_id).sort
      end
    end

    describe "生產者" do
      it "建立商品時即物化發布列（82 §8.4①）" do
        pos = second_channel
        product = create(:product, shop:)

        expect(publications_of(product)).to eq([ online_store.id, pos.id ].sort)
      end

      it "建立變體時即物化發布列（82 §8.2：未觸碰的變體回全部管道、不是 0 列）" do
        pos = second_channel
        variant = create(:product_variant, product: create(:product, shop:))

        expect(publications_of(variant)).to eq([ online_store.id, pos.id ].sort)
      end

      it "建立系列時即物化發布列（Collection 同為 Publishable）" do
        pos = second_channel
        collection = ActsAsTenant.with_tenant(shop) do
          Collection.create!(shop_id: shop.id, title: "測試系列", handle: "test-col",
                             description_html: "", collection_type: "manual", sort_order: "manual")
        end

        expect(publications_of(collection)).to eq([ online_store.id, pos.id ].sort)
      end

      # 🔴 **本組最重要的一格**——它釘住的是**我方裁定**（ours），不是照抄本尊。
      #
      # 本尊官方文檔說新變體「published to all channels where the parent product is
      # published」，但那句描述的是**生效狀態**；儲存狀態的實測與該句不一致，
      # 且該實測有排除不掉的替代假說。三方證據與選擇理由全文＝82 §8.4②。
      # 兩種選法對**可見性**的結果完全相同（閘控在讀取層的 AND，不在寫入層）。
      #
      # 分岔點：實作若改成「變體跟著父商品的 publication 集合」，在這一格會少一個管道。
      # 沒有這一格，那種實作**全部其他測試都會過**——因為平常父子本來就一致。
      it "🔴 變體拿到全部 auto_publish 管道，不跟隨父商品（ours，見 82 §8.4②）" do
        pos = second_channel
        product = create(:product, shop:)

        # 把父商品從 pos 上取消發布 ⇒ 父子刻意不一致。
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id,
                                    publication_id: pos.id).delete_all
        end
        expect(publications_of(product)).to eq([ online_store.id ])

        variant = create(:product_variant, product:)

        # 實測：新變體拿到 3 個管道，含父商品自己都沒有的那一個。
        expect(publications_of(variant)).to eq([ online_store.id, pos.id ].sort),
          "變體生產者不得讀父商品的 publication 集合（82 §8.4②）"
      end

      it "`auto_publish = false` 的管道不建列" do
        manual_channel = second_channel(auto_publish: false)
        product = create(:product, shop:)

        expect(publications_of(product)).to eq([ online_store.id ])
        expect(publications_of(product)).not_to include(manual_channel.id)
      end

      it "冪等：重跑不重複建列、也不改既有 published_at" do
        product = create(:product, shop:)
        before_at = ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).pick(:published_at)
        end
        # 🔴 沒有這一句，`published_at: nil` 的突變會讓下面變成 `nil == nil` 靜默通過。
        expect(before_at).to be_present

        expect(Publications::Materialize.for(product)).to eq(0)
        after_at = ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).pick(:published_at)
        end

        expect(publications_of(product)).to eq([ online_store.id ])
        expect(after_at).to eq(before_at)
      end

      # 🔴 生產者不得依賴 `ActsAsTenant.current_tenant`——它會在 seeds／factory／rake／
      #    資料 migration 底下被觸發，那些路徑沒有租戶。第 11 包的部署事故同一家族。
      #
      # ⚠️ 下面**三格缺一不可**，理由是 2026-08-26 突變測試的實測結果：
      #    原本只有第一格，而它把建立動作包在 `ActsAsTenant.without_tenant` 裡
      #    ⇒ **環境已經提供了實作要提供的東西**，兩種實作在那一格不分岔
      #    ⇒ 把 `Materialize` 裡的 `without_tenant` 整個拿掉，spec 照樣全綠。
      #    第二、三格才分別覆蓋註釋自陳的兩條真實危害路徑。
      it "🔴 沒有 current_tenant 時照樣建列（不得 NoTenantSet）" do
        target = online_store.id # 先在有租戶時取，避免測試自己踩到要驗的那個坑

        product = ActsAsTenant.without_tenant do
          expect(ActsAsTenant.current_tenant).to be_nil # 確認確實在無租戶情境
          create(:product, shop:)
        end

        expect(publications_of(product)).to eq([ target ])
      end

      # `with_tenant(nil)` 才是 seeds／rake 的真實形態：租戶是 nil，但**沒有** unscoped
      # ⇒ default scope 的 `NoTenantSet` raise 是活的。`without_tenant` 兩者都設，測不出來。
      it "🔴 `current_tenant` 為 nil 且**不在 without_tenant 內**時不得 NoTenantSet" do
        target = online_store.id
        product = create(:product, shop:)
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).delete_all
        end

        ActsAsTenant.with_tenant(nil) do
          expect(ActsAsTenant.current_tenant).to be_nil
          expect { Publications::Materialize.for(product) }.not_to raise_error
        end

        expect(publications_of(product)).to eq([ target ])
      end

      # 🔴 這一格守的是註釋裡自陳「比直接炸危險得多」的那一型：
      #    current_tenant 是別間店 ⇒ default scope 把管道過濾成 0 列
      #    ⇒ **一列都不建、而且不拋任何錯**。
      it "🔴 `current_tenant` 是**別間店**時仍照 publishable.shop_id 建列（不得靜默建 0 列）" do
        target = online_store.id
        product = create(:product, shop:)
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).delete_all
        end

        other = create(:shop)
        ActsAsTenant.with_tenant(other) do
          expect(Publications::Materialize.for(product)).to eq(1)
        end

        expect(publications_of(product)).to eq([ target ])
      end

      # 🔴 型別白名單：**raise 而非靜默回 0**。
      #    日後某包新增第四個 Publishable 卻忘了加進 `PUBLISHABLE_TYPES` 時，
      #    靜默回 0 會讓那個型別全部建不出發布列、前台看不到、且沒有任何 spec 會紅
      #    （三個 caller 都不看回傳值）。
      it "🔴 非 Publishable 型別一律 raise，不得靜默回 0" do
        expect { Publications::Materialize.for(online_store) }
          .to raise_error(ArgumentError, /不是 Publishable/)

        count = ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Publication").count
        end
        expect(count).to eq(0)
      end
    end

    describe ".purchasable / .discoverable" do
      # 一個「完整可賣」的商品：狀態 active ＋ 商品層已發布 ＋ 至少一個變體已發布。
      def sellable(status: "active")
        product = create(:product, shop:, status:)
        create(:product_variant, product:)
        product
      end

      it "狀態 active、商品層與變體層都已發布 ⇒ 可購買且可被發現" do
        product = sellable

        expect(described_class.purchasable(publication: online_store)).to contain_exactly(product)
        expect(described_class.discoverable(publication: online_store)).to contain_exactly(product)
      end

      it "🔴 UNLISTED：可購買但**不可被發現**（這正是這個狀態存在的理由）" do
        unlisted = sellable(status: "unlisted")

        expect(described_class.purchasable(publication: online_store)).to contain_exactly(unlisted)
        expect(described_class.discoverable(publication: online_store)).to be_empty
      end

      it "draft 與 archived 兩者皆否" do
        sellable(status: "draft")
        sellable(status: "archived")

        expect(described_class.purchasable(publication: online_store)).to be_empty
        expect(described_class.discoverable(publication: online_store)).to be_empty
      end

      # 分岔點：實作若少了變體層 EXISTS，這一格會回傳該商品。
      it "🔴 商品層已發布但**所有變體都未發布** ⇒ 不可購買" do
        product = sellable
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "ProductVariant").delete_all
        end

        expect(described_class.purchasable(publication: online_store)).to be_empty
      end

      # 分岔點：實作若少了商品層 EXISTS，這一格會回傳該商品。
      it "🔴 變體已發布但**商品層未發布** ⇒ 不可購買" do
        product = sellable
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).delete_all
        end

        expect(described_class.purchasable(publication: online_store)).to be_empty
      end

      # 分岔點：實作若忽略 published_at 的時間比較（只看列存不存在），這一格會回傳該商品。
      it "🔴 排程發布：`published_at` 在未來 ⇒ 判定時點之前不可購買" do
        product = sellable
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id)
                             .update_all(published_at: 1.day.from_now)
        end

        expect(described_class.purchasable(publication: online_store)).to be_empty
        expect(described_class.purchasable(publication: online_store, at: 2.days.from_now))
          .to contain_exactly(product)
      end

      # 分岔點：實作若把 `published_at IS NULL` 當成已發布，這一格會回傳該商品。
      it "🔴 `published_at` 為 NULL ⇒ 尚未發布，不可購買" do
        product = sellable
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id)
                             .update_all(published_at: nil)
        end

        expect(described_class.purchasable(publication: online_store)).to be_empty
      end

      it "只算目標管道：發布到別的管道不算數" do
        pos = second_channel
        product = sellable
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publication_id: online_store.id).delete_all
        end

        expect(described_class.purchasable(publication: online_store)).to be_empty
        expect(described_class.purchasable(publication: pos)).to contain_exactly(product)
      end

      # 🔴 **上面那一格只殺得掉「兩側同時漏掉 publication_id」的實作**——它把 online_store
      #    的列整批刪光，兩個 EXISTS 同時失去目標管道的列，於是只動一側的實作會被另一側的
      #    AND 擋下來、測不出分岔（2026-08-26 突變測試實測：只動商品層仍綠、只動變體層仍綠、
      #    兩側都動才紅）。而真實的漂移形態就是**只動一側**（改 SQL 時漏抄一個條件）。
      #    ⇒ 下面兩格各自只讓一側失去目標管道。
      it "🔴 商品層只發布到**別的管道** ⇒ 目標管道不可購買（守商品層 EXISTS 的 publication_id）" do
        pos = second_channel
        product = sellable
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id,
                                    publication_id: online_store.id).delete_all
        end
        expect(publications_of(product)).to eq([ pos.id ])

        expect(described_class.purchasable(publication: online_store)).to be_empty
      end

      it "🔴 變體層只發布到**別的管道** ⇒ 目標管道不可購買（守變體層 JOIN 的 publication_id）" do
        pos = second_channel
        product = sellable
        variant = product.product_variants.first
        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "ProductVariant", publishable_id: variant.id,
                                    publication_id: online_store.id).delete_all
        end
        expect(publications_of(variant)).to eq([ pos.id ])

        expect(described_class.purchasable(publication: online_store)).to be_empty
      end

      it "跨租戶：別間店的商品不會進來" do
        sellable
        other = create(:shop)
        ActsAsTenant.with_tenant(other) do
          op = create(:product, shop: other, status: "active")
          create(:product_variant, product: op)
        end

        result = described_class.purchasable(publication: online_store)
        expect(result.map(&:shop_id).uniq).to eq([ shop.id ])
      end

      # 🔴 **結構性斷言**：不變量必須由構造保證，不是靠兩份 SQL 各自寫對。
      #
      # ⚠️ 前一版是掃 `product.rb` 的原始碼看有沒有 `purchasable(` 字樣——
      #    2026-08-26 突變測試證明那**可以被一行註釋騙過**（把 `discoverable` 改寫成
      #    獨立 SQL，再在方法內加一行 `# equivalent to purchasable( ... )` ⇒ 守衛照樣過）。
      #    ⇒ 改成比對**產生出來的 SQL**，註釋騙不了。
      it "🔴 discoverable 由 purchasable 導出（不變量是定理不是測試項）" do
        # `at:` 必須釘死：兩次呼叫各自取 `Time.current` 會讓 SQL 的時間字面值差幾微秒。
        at = Time.utc(2026, 8, 26, 12, 0, 0)
        expected = described_class.purchasable(publication: online_store, at:)
                                  .where(status: described_class::DISCOVERABLE_STATUSES).to_sql

        expect(described_class.discoverable(publication: online_store, at:).to_sql).to eq(expected),
          "discoverable 必須由 purchasable 導出，否則 discoverable ⊆ purchasable 會退化成要靠測試盯的性質"
      end
    end

    describe "層與層不連動（82 §8.4③）" do
      # 分岔點：有人日後加上「商品層取消發布時連動取消變體層」的串聯時，這一格轉紅。
      # 🔴 兩格都必須先斷言 `before_rows` 非空——否則在「一列都沒有」的世界裡
      #    `[] == []` 會靜默通過（2026-08-26 突變測試實測：拿掉任一個 `after_create`
      #    之後這兩格照樣綠）。
      it "🔴 商品層取消發布後，變體層的列原封不動" do
        product = create(:product, shop:)
        variant = create(:product_variant, product:)
        before_rows = publications_of(variant)
        expect(before_rows).not_to be_empty

        ActsAsTenant.without_tenant do
          ResourcePublication.where(publishable_type: "Product", publishable_id: product.id).destroy_all
        end

        expect(publications_of(variant)).to eq(before_rows)
      end

      it "🔴 改變 status 不影響發布列（82 §8.4④：兩者正交）" do
        product = create(:product, shop:, status: "active")
        before_rows = publications_of(product)
        expect(before_rows).not_to be_empty

        ActsAsTenant.with_tenant(shop) { product.update!(status: "unlisted") }

        expect(publications_of(product)).to eq(before_rows)
      end
    end
  end
end

RSpec.describe Types::ProductStatusEnum do
  it "GraphQL 值域逐字等於 limits.yml（三份清單不得分岔）" do
    expect(described_class.values.keys).to eq(Limits.enum(:product, :status_values))
  end

  it "每個 token 對應到小寫的 DB 值" do
    expect(described_class.values.values.map(&:value)).to eq(Product::STATUSES)
  end

  it "每個值都有說明（14 §F1.2 的真值表要能從 schema 讀到）" do
    expect(described_class.values.values.map(&:description)).to all(be_present)
  end

  # 🔴 刻意偏離本尊並且必須留住：Shopify 對舊版 API 把 UNLISTED 回成 ACTIVE，
  # 那會讓舊版整合把它當 ACTIVE 處理再送進 feed／索引 ⇒ noindex 完全失效。
  it "不做舊 API 版本降級（limits.yml:817，刻意偏離，13 §F1.2(f)）" do
    expect(Limits.fetch(:product, :unlisted_downgrade_on_old_api_version)).to be(false)
    expect(described_class.values).to have_key("UNLISTED")
  end
end
