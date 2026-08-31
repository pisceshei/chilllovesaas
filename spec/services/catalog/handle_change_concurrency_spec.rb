# frozen_string_literal: true

require "rails_helper"

# 第 6 包：改名不變量的**併發**測試。
#
# 🔴 這支 spec 的存在理由：本包第一版把「表裡永遠無鏈無迴圈」寫成保證，而對抗審查
#   （R6-3／P6-3）**實跑重現**了鏈——check-then-act 跨兩張表，序列情境的 spec 全綠
#   也證明不了併發下成立。序列 spec（`spec/requests/url_redirects_spec.rb`）守語義，
#   這一支守不變量。
#
# 🔴 `use_transactional_tests = false`：要驗的是跨連線的鎖，transactional fixtures
#   下其他執行緒看不到未 commit 的資料（骨架同 `inventory/adjust_concurrency_spec`）。
RSpec.describe Catalog::HandleChange, "concurrency" do
  self.use_transactional_tests = false

  def purge!
    EventOutbox.unscoped.delete_all
    UrlRedirect.unscoped.delete_all
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
    # 🔴 發布列必須排在 Publication 之前刪（第 12 包）：Product／ProductVariant／
    #    Collection 的 after_create 會建 resource_publications，而本幫手用的是
    #    `delete_all`（繞過 dependent: :destroy）⇒ 殘列讓 fk_res_pub_publication_id 擋住刪除。
    ResourcePublication.unscoped.delete_all
    # 2026-08-26 S0：四張新表的刪除順序由外鍵決定，等於建立順序的**反序**：
    #   channels → publications → sales_catalogs → app_installations
    #   （同 `app/models/shop.rb` 的關聯宣告順序，完整理由見該處）。
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

  let!(:shop) { create(:shop, subdomain: "hc-conc") }

  after { purge! }

  def make_product!(handle)
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:)
      v.product.update!(handle:)
      v.product
    end
  end

  def rename(product, new_handle)
    ActiveRecord::Base.connection_pool.with_connection do
      ActsAsTenant.with_tenant(shop) do
        Current.shop = shop
        Catalog::SaveProduct.call(shop:, input: {
          id: "gid://chilllove/Product/#{product.id}",
          title: product.reload.title,
          lock_version: product.lock_version,
          handle: new_handle,
          variants: [ { id: "gid://chilllove/ProductVariant/#{product.product_variants.sole.id}",
                        price: "128.00" } ]
        })
      end
    end
  end

  # 表裡沒有任何一列的 to_path 同時是別列的 from_path，
  # 且沒有任何 from_path 是還活著的商品網址。
  def invariant_violations
    ActsAsTenant.with_tenant(shop) do
      froms = UrlRedirect.pluck(:from_path)
      chains = UrlRedirect.where(to_path: froms).pluck(:from_path, :to_path)
      live = Product.pluck(:handle).map { |h| "/products/#{h}" }
      shadowed = UrlRedirect.where(from_path: live).pluck(:from_path)
      { chains:, shadowed: }
    end
  end

  # 🔴 **競態窗必須人工撐開**：MRI 的 GIL ＋ 這幾條查詢太快，單純開兩個執行緒
  #   幾乎必然自然序列化——第一版就是這樣寫的，四道守衛裡有三道刪掉仍然全綠
  #   （假綠）。對抗審查方當初也是用人工 gate 才重現的。下面兩格各自把窗撐在
  #   **不同的位置**，對應兩種到達順序。

  it "🔴 順序 A：R2 通過 pre-flight 後 R1 才 commit ⇒ R2 必須被 register! 的複查擋下" do
    p1 = make_product!("aaa")
    p2 = make_product!("xxx")

    reached = Queue.new
    release = Queue.new
    gated = false
    # 在 R2 的 pre-flight（normalize 內、transaction 外）之後卡住它，
    # 讓 R1 整個跑完並 commit。這正是審查 R6-3 重現的時序。
    allow(Catalog::HandleChange).to receive(:path_reserved?).and_wrap_original do |orig, shop_arg, path|
      result = orig.call(shop_arg, path)
      if path == "/products/aaa" && !gated
        gated = true
        reached << :ok
        release.pop
      end
      result
    end

    t2 = Thread.new { rename(p2, "aaa") }
    reached.pop                       # R2 已過 pre-flight（此刻 aaa 還沒被釋出）
    r1 = rename(p1, "bbb")            # R1 完整跑完並 commit：aaa 變成 from_path
    release << :go
    r2 = t2.value

    expect(r1.user_errors).to eq([])
    expect(r2.user_errors.map { |e| e[:code] }).to eq([ "HANDLE_TAKEN" ])
    expect(invariant_violations).to eq({ chains: [], shadowed: [] })
  end

  it "🔴 順序 B：R1 在 txn 內尚未 commit 時 R2 全程跑完 ⇒ 店級鎖必須把 R2 擋在門外" do
    p1 = make_product!("ccc")
    p2 = make_product!("yyy")

    inserted = Queue.new
    finish = Queue.new
    # 卡在 R1 的 txn **內**（redirect 已插入、尚未 commit）。
    # 沒有店級鎖的話，R2 會在此期間完整跑完並用過期快照通過複查 ⇒ 造出鏈。
    allow(Catalog::HandleChange).to receive(:register!).and_wrap_original do |orig, **kw|
      result = orig.call(**kw)
      if kw[:old_handle] == "ccc"
        inserted << :ok
        finish.pop
      end
      result
    end

    t1 = Thread.new { rename(p1, "ddd") }
    inserted.pop                      # R1 已插入 ccc→ddd，txn 仍開著、持店級鎖
    t2 = Thread.new { rename(p2, "ccc") }
    sleep 0.5                         # 讓 R2 真的走到店級鎖前並卡住
    finish << :go                     # R1 commit、釋鎖
    r1 = t1.value
    r2 = t2.value

    expect(r1.user_errors).to eq([])
    expect(r2.user_errors.map { |e| e[:code] }).to eq([ "HANDLE_TAKEN" ])
    expect(invariant_violations).to eq({ chains: [], shadowed: [] })
  end

  it "🔴 店級序列化：兩個改名的臨界區不得重疊（這是不變量的**可證明**來源）" do
    # 🔴 為什麼要獨立測「不重疊」而不是只測結果：兩道 register! 複查各自只接住
    #   一種到達順序，而 `複查一` 的鎖定讀在 unique index 上取 gap lock，**恰好**
    #   也擋住了順序 B 的 INSERT——於是逐一刪除守衛時，順序 A/B 的結果測都還是綠。
    #   真正讓「無鏈無迴圈」可證明的是**臨界區不重疊**：任何兩個改名都序列化，
    #   後到者必然看得見先到者已提交的狀態，兩道複查因此必定命中其一。
    #   沒有這條，正確性就退回「靠 InnoDB 的鎖粒度碰巧覆蓋」——那是不能寫進
    #   保證的東西（本包第一版正是這樣把「永遠無鏈」寫成保證而被審查實跑推翻）。
    p1 = make_product!("m1")
    p2 = make_product!("m2")

    spans = Queue.new
    allow(Catalog::HandleChange).to receive(:register!).and_wrap_original do |orig, **kw|
      entered = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = orig.call(**kw)
      sleep 0.4                       # 把臨界區撐開，讓重疊（若可能）必然發生
      spans << [ entered, Process.clock_gettime(Process::CLOCK_MONOTONIC) ]
      result
    end

    [ Thread.new { rename(p1, "m1x") }, Thread.new { rename(p2, "m2x") } ].each(&:join)

    a, b = Array.new(2) { spans.pop }.sort_by(&:first)
    expect(a.last).to be <= b.first,
      "臨界區重疊：#{a.inspect} 與 #{b.inspect}——店級序列化沒有生效"
    expect(invariant_violations).to eq({ chains: [], shadowed: [] })
  end

  it "序列改名的鏈坍縮在併發後仍成立（A→B→C 只留兩列、都指向 C）" do
    product = make_product!("s1")
    rename(product, "s2")
    rename(product, "s3")
    ActsAsTenant.with_tenant(shop) do
      expect(UrlRedirect.pluck(:to_path).uniq).to eq([ "/products/s3" ])
    end
    expect(invariant_violations).to eq({ chains: [], shadowed: [] })
  end
end
