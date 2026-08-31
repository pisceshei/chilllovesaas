# frozen_string_literal: true

require "rails_helper"

# S5：發布寫入的**併發**測試。
#
# 🔴 **這支 spec 的存在理由**：S5 是全倉第一條 `resource_publications.published_at`
#   的 UPDATE 路徑（S1／S2 全倉零 UPDATE）。而 `uq_res_pub_target` 是
#   `(shop_id, publication_id, publishable_type, publishable_id)` 的唯一索引
#   ——它**完全不涉及 `published_at` 的值** ⇒ 同一列的兩個並發讀改寫，
#   唯一索引一點忙都幫不上。這是本包**新引入**的風險，不是既有問題。
#
# 🔴 **publication 線在此之前零併發 spec** ⇒ 骨架跨表抄：
#   `use_transactional_tests = false` ＋ purge! 形態抄
#   `spec/models/idempotency_key_concurrency_spec.rb`；
#   人工 gate 形態抄 `spec/services/catalog/handle_change_concurrency_spec.rb`。
#
# 🔴 **競態窗必須人工撐開**（該檔逐字警告，且它是實跑踩出來的）：MRI 的 GIL
#   ＋ 這幾條查詢太快，單純開兩個執行緒幾乎必然自然序列化——那樣寫的話，
#   把列鎖與 rescue **全部刪掉仍然全綠**。
#
# @see docs/dev/m2-publishable-write.md §4
RSpec.describe Publications::Write, "concurrency" do
  self.use_transactional_tests = false

  # 🔴 刪除順序由外鍵決定。發布列必須排在 Publication 之前（第 12 包教訓）；
  #   S0 的四張表是建立順序的反序：channels → publications → sales_catalogs → app_installations。
  def purge!
    EventOutbox.unscoped.delete_all
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
    UrlRedirect.unscoped.delete_all
    Product.unscoped.delete_all
    ResourcePublication.unscoped.delete_all
    Channel.unscoped.delete_all
    Publication.unscoped.delete_all
    SalesCatalog.unscoped.delete_all
    AppInstallation.unscoped.delete_all
    Translation.unscoped.delete_all
    TranslationStatus.unscoped.delete_all
    # 包 32：markets 鏈先於 shop_locales（複合 FK fk_mwp_default_locale／fk_mwpl_shop_locale）；
    # 刪 markets 由 DB cascade 帶走 regions／presences／白名單列，domains 隨後才無 presence 引用。
    Market.unscoped.delete_all
    Domain.unscoped.delete_all
    ShopLocale.unscoped.delete_all
    # 結帳線第二包：Shop callback 另生運送鏈（FK → shops），反序清（rates→zones→profiles）。
    ShippingRate.unscoped.delete_all
    ShippingZone.unscoped.delete_all
    ShippingProfile.unscoped.delete_all
    UserStoreAssignment.unscoped.delete_all
    StaffMember.unscoped.delete_all
    Shop.delete_all
  end

  # 🔴 `purge! || create` 是陷阱：`delete_all` 回傳整數（truthy）⇒ 短路 ⇒ shop 變 Integer。
  before { purge! }
  after { purge! }

  let!(:shop) { create(:shop, subdomain: "pubw-conc") }
  let(:future) { 6.days.from_now.change(usec: 0) }

  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      record = create(:product, shop:)
      create(:product_variant, product: record)
      record
    end
  end

  def online_store = ActsAsTenant.with_tenant(shop) { Publication.online_store! }

  def second_publication
    ActsAsTenant.with_tenant(shop) do
      Publication.create!(shop_id: shop.id, name: "第二管道", channel_handle: "second-conc",
                          auto_publish: false, supports_future_publishing: true)
    end
  end

  def product_gid = "gid://chilllove/Product/#{product.id}"

  def entry(publication, date: :omitted)
    base = { publication_id: "gid://chilllove/Publication/#{publication.id}" }
    return base if date == :omitted

    base.merge(publish_date: date, publish_date_given: true)
  end

  def publish(publication, date: :omitted)
    ActiveRecord::Base.connection_pool.with_connection do
      described_class.publish(shop:, publishable_gid: product_gid, entries: [ entry(publication, date:) ])
    end
  end

  def unpublish(publication)
    ActiveRecord::Base.connection_pool.with_connection do
      described_class.unpublish(shop:, publishable_gid: product_gid, entries: [ entry(publication) ])
    end
  end

  def row_for(publication)
    ActsAsTenant.without_tenant do
      ResourcePublication.find_by(shop_id: shop.id, publication_id: publication.id,
                                  publishable_type: "Product", publishable_id: product.id)
    end
  end

  # ── ① 兩個並發的建列 ─────────────────────────────────────────────────────

  # 🔴 **gate 必須下在取鎖之前**。第一版下在 `locked_publication_row` 回傳之後，
  #   結果是 A 的 INSERT 卡 50 秒後 `LockWaitTimeout`——因為 InnoDB 在
  #   REPEATABLE READ 下，對**不存在的列**做 `SELECT ... FOR UPDATE` 會取
  #   **間隙鎖（gap lock）**，B 就握著那把鎖在 gate 上等。
  #   ⚠️ 那次失敗本身就是列鎖生效的證據，但它讓測試量不到東西 ⇒ 改下在取鎖前。
  #
  # ⚠️ **本格證明什麼、不證明什麼**（誠實登記，鐵律 19）：
  #   證明「兩個並發 publish 之後恰好一列、兩邊都成功」這個不變量。
  #   **不證明**列鎖是它成立的原因——拿掉列鎖，`create!` 的 rescue 也會讓它綠。
  #   列鎖的專屬證據在下面第 ③ 格。
  it "兩個並發的 publish 建同一列 ⇒ 兩邊都成功，且只有一列" do
    target = second_publication
    expect(row_for(target)).to be_nil

    reached = Queue.new
    release = Queue.new
    gated = false

    allow(described_class).to receive(:locked_publication_row).and_wrap_original do |orig, **kw|
      unless gated
        gated = true
        reached << :ok
        release.pop
      end
      orig.call(**kw)
    end

    thread = Thread.new { publish(target) }
    reached.pop            # B 已進入寫入區、**尚未取鎖**
    a = publish(target)    # A 完整跑完並 commit ⇒ 那一列現在存在了
    release << :go
    b = thread.value

    expect(a.user_errors).to eq([]), "先到的一方應該成功"
    expect(b.user_errors).to eq([]), "慢的一方什麼都沒做錯——必須收斂成 no-op success"
    expect(ActsAsTenant.without_tenant {
      ResourcePublication.where(shop_id: shop.id, publication_id: target.id).count
    }).to eq(1)
  end

  # ── ② 唯一鍵衝突的復原（故障注入，不是自然競態）────────────────────────────

  # 🔴 **這一格是故障注入，必須誠實這樣標**：在 REPEATABLE READ ＋ 列鎖之下，
  #   建列競態已經被 gap lock 序列化 ⇒ `create!` 的 `RecordNotUnique` 分支
  #   **自然情境下打不到**。它是縱深防禦，存在的理由是：
  #     ①隔離級別若改成 READ COMMITTED（許多生產設定的預設），gap lock 消失、
  #       這條路立刻成為常規路徑；
  #     ②`ResourcePublication` **同時**有 DB 唯一索引與 model uniqueness validation，
  #       Rails 官方對這個組合逐字警告 `#find_by will never be called`。
  #   ⇒ 用故障注入證明它的**復原邏輯**是對的，而不是假裝這是自然競態
  #     （鐵律 20.2 第 5 類：不得只證明 happy path）。
  #
  # 🔴 判準是**重走完整矩陣**而不是就地補一個 update：輸掉競態的一方帶著未來日期
  #   而來，若 rescue 只做 `update! if published_at.nil?`，那個排程日期會被**靜默丟掉**
  #   而呼叫端收到成功。
  it "🔴 撞唯一鍵之後重走完整矩陣：呼叫端的 publishDate 仍然生效（不得靜默丟掉）" do
    target = second_publication
    injected = false

    # 注入：第一次 create! 之前先由另一條連線把該列插進去，然後讓 create! 撞上唯一鍵。
    allow(ResourcePublication).to receive(:create!).and_wrap_original do |orig, attrs|
      if !injected && attrs[:publication_id] == target.id
        injected = true
        ActiveRecord::Base.connection_pool.with_connection do
          ActsAsTenant.without_tenant do
            # 🔴 注入的列刻意帶**現在**而不是 `attrs` 裡那個未來時間：
            #   若照抄 attrs，對手建出來的列本來就已經是呼叫端要的日期
            #   ⇒ 下面的斷言在「rescue 什麼都沒做」時也會綠（突變測試實跑抓到）。
            #   要分辨得出來，對手的列就必須與呼叫端的意圖**不同**。
            ResourcePublication.insert_all([ attrs.merge(published_at: Time.current,
                                                         created_at: Time.current,
                                                         updated_at: Time.current) ])
          end
        end
      end
      orig.call(attrs)
    end

    result = publish(target, date: future)

    expect(injected).to be(true), "故障沒被注入＝這一格什麼都沒測到"
    expect(result.user_errors).to eq([])
    expect(row_for(target).published_at).to eq(future),
      "呼叫端的排程日期被吞了——它收到成功，商家設的排程卻不存在"
    expect(ActsAsTenant.without_tenant {
      ResourcePublication.where(shop_id: shop.id, publication_id: target.id).count
    }).to eq(1)
  end

  # ── ③ 讀改寫 vs 刪除（🔴 列鎖的專屬證據）──────────────────────────────────

  # 🔴 **這一格才是 `SELECT ... FOR UPDATE` 的守衛**，而且它會因為拿掉列鎖而轉紅：
  #   - **有**列鎖：B 的讀是 locking read，讀的是**最新已提交版本** ⇒ 它會卡在
  #     A 的列鎖上，等 A commit 後讀到「沒有列」⇒ 建列。最終狀態＝已發布。✅
  #   - **沒有**列鎖（`find_by`）：在 REPEATABLE READ 下那是一致性快照讀，
  #     讀到的是 **B 交易開始時**的版本 ⇒ B 看到「已發布」⇒ 判定 R5 no-op ⇒
  #     什麼都不寫；而 A 隨後把列刪了。最終狀態＝**沒有列，但 B 回報發布成功**。
  #     商家看到成功訊息，商品卻不在管道上。❌
  it "🔴 publish 與 unpublish 並發 ⇒ 後到的 publish 必須看到刪除後的狀態並重新建列" do
    target = online_store
    expect(row_for(target)).to be_present

    deleted = Queue.new
    finish = Queue.new

    # 卡在 A 的 transaction **內**（列已刪、尚未 commit，鎖還握著）。
    allow(described_class).to receive(:remove_publication!).and_wrap_original do |orig, **kw|
      result = orig.call(**kw)
      deleted << :ok
      finish.pop
      result
    end

    a_thread = Thread.new { unpublish(target) }
    deleted.pop                       # A 已刪列，txn 仍開著、持列鎖
    b_thread = Thread.new { publish(target) }
    sleep 0.5                         # 讓 B 真的走到列鎖前並卡住
    finish << :go                     # A commit、釋鎖
    a_thread.value
    b = b_thread.value

    expect(b.user_errors).to eq([])
    expect(row_for(target)).to be_present,
      "B 讀到過期快照後判定 no-op ⇒ 回報發布成功，商品卻不在管道上"
    expect(row_for(target).published?).to be(true)
  end
end
