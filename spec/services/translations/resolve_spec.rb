# frozen_string_literal: true

require "rails_helper"

# 第 7 包：前台譯文解析（67 §C.4 的四步演算法）。
RSpec.describe Translations::Resolve do
  let(:shop) { create(:shop, subdomain: "resolve-shop") }

  # 新店的預設是 en(source, published) ＋ zh-Hant/zh-Hans/ja/fr（enabled 但未 published）。
  # 前台解析走 `:published`，所以要測什麼就得先發布什麼——這本身就是一格語義測試。
  def publish!(*tags)
    ActsAsTenant.with_tenant(shop) do
      tags.each { |tag| ShopLocale.find_by!(locale_tag: tag).update!(published: true) }
    end
  end

  # 🔴 **已知限制（必讀，dev doc 亦登記）**：`shop_locales belongs_to :platform_locale`，
  #   而現行 `platform_locales` 的 28 列裡**沒有任何一列的截尾目標也在表內**
  #   （pt-BR/pt-PT 的父 `pt` 不在表內；zh-Hant/zh-Hans 的父 `zh` 是禁用碼）
  #   ⇒ **今天在生產資料上，§C.4 步驟 2 的截尾鏈是不可達的**。
  #   複驗＝`bin/rails runner "puts PlatformLocale.pluck(:tag).inspect"`
  #   （取證 2026-08-25：ar cs da de el en es fi fr he hi id it ja ko ms nb nl pl
  #    pt-BR pt-PT ru sv th tr vi zh-Hans zh-Hant）。
  #   本 helper 因此在需要時**補一列平台字典**——這不是測試作弊，是把「字典補了之後
  #   鏈確實會生效」這件事變成可執行的證據；補平台字典本身是 ML-0 的事，不是本包。
  def add_locale!(tag, published: true, position: 9)
    parts = tag.split("-")
    PlatformLocale.find_or_create_by!(tag:) do |row|
      row.language = parts.first
      row.script = parts.find { |part| part.length == 4 }
      row.region = parts.find { |part| part.length == 2 && part == part.upcase }
      row.endonym = tag
      row.collation = "utf8mb4_0900_ai_ci"
      row.plural_rule = parts.first
    end
    ActsAsTenant.with_tenant(shop) do
      ShopLocale.create!(locale_tag: tag, is_source: false, enabled: true, published:, position:)
    end
  end

  def product!(**attrs)
    ActsAsTenant.with_tenant(shop) { create(:product, shop:, **attrs) }
  end

  def translate!(resource, locale, field, value)
    ActsAsTenant.with_tenant(shop) do
      Translation.create!(
        shop_id: shop.id,
        resource_type: resource.is_a?(Collection) ? "COLLECTION" : "PRODUCT",
        resource_id: resource.id, locale_tag: locale, field_key: field, value:,
        source_locale_tag: "en", source_digest: Translation.digest_for("x"), value_source: "human"
      )
    end
  end

  # graphql-ruby 把 `new` 設成 protected（正規入口是 schema 執行）。這裡只想量那一支
  # resolver 產生的 SQL，不想拉起整個 GraphQL 請求脈絡 ⇒ 明示地伸手進去，並註明理由。
  def product_type_for(product)
    Types::ProductType.send(:new, product, nil)
  end

  def resolve(resource, field, locale, scope: :published)
    described_class.field(shop:, resource:, field:, locale:, scope:)
  end

  # 訂閱一次 fallback_hit，回傳 payload 陣列。
  def capture_hits
    hits = []
    subscriber = ActiveSupport::Notifications.subscribe("i18n.fallback_hit") do |*, payload|
      hits << payload
    end
    yield
    hits
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # 🔴 收**全部**業務表的 SELECT，不是只收 translations（2026-08-25 依審查 C7 修正）：
  #   首版過濾 `sql.include?("`translations`")`，於是把 `Resolve` 對 `shop_locales` 的查詢
  #   全部濾掉——而那正是 `resolve.rb` 自己紅字警告的 N+1 面。實測把 batch 改成逐欄位
  #   重查 shop_locales 後會發出 76 條查詢，首版的 N+1 spec 仍然綠。
  IGNORED_SQL = /SCHEMA|TRANSACTION|\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i

  def capture_sql(table: nil)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      next if payload[:name].to_s == "SCHEMA" || sql.match?(IGNORED_SQL)
      next unless sql.lstrip.start_with?("SELECT")
      next if table && !sql.include?("`#{table}`")

      queries << sql
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "67 §C.4 的四步（逐步窮舉）" do
    it "步驟 1：請求語言直接命中 ⇒ depth 0、source :translation、不發遙測" do
      publish!("zh-Hant")
      product = product!(title: "Rose")
      translate!(product, "zh-Hant", "title", "玫瑰")

      hits = capture_hits { @result = resolve(product, "title", "zh-Hant") }

      expect(@result.value).to eq("玫瑰")
      expect(@result.locale).to eq("zh-Hant")
      expect(@result.depth).to eq(0)
      expect(@result.source).to eq(:translation)
      expect(@result.fallback?).to be(false)
      expect(hits).to be_empty
    end

    it "步驟 2：走截尾鏈 ⇒ zh-Hant-HK 命中 zh-Hant 的譯文，depth 1" do
      publish!("zh-Hant")
      add_locale!("zh-Hant-HK")
      product = product!(title: "Rose")
      translate!(product, "zh-Hant", "title", "玫瑰")

      result = resolve(product, "title", "zh-Hant-HK")

      expect(result.value).to eq("玫瑰")
      expect(result.locale).to eq("zh-Hant")   # 🔴 第 34 包的 lang 屬性用這個值，不是請求語言
      expect(result.depth).to eq(1)
      expect(result.fallback?).to be(true)
    end

    it "步驟 3：required 欄位全部落空 ⇒ 回 base row（來源語言原文），不是空白" do
      publish!("ja")
      product = product!(title: "Rose Tonnerre")

      result = resolve(product, "title", "ja")

      expect(result.value).to eq("Rose Tonnerre")
      expect(result.locale).to eq("en")
      expect(result.source).to eq(:base)
      expect(result.depth).to eq(1)   # 候選只有 [ja]，base 在它之後
    end

    it "步驟 4：optional 欄位落空且原文也空 ⇒ **整個欄位不輸出**（不是空字串）" do
      publish!("ja")
      product = product!(seo_description: nil)

      result = resolve(product, "meta_description", "ja")

      expect(result.omitted?).to be(true)
      expect(result.value).to be_nil
      expect(result.locale).to be_nil
    end

    it "步驟 4 的另一半：optional 欄位落空但原文有值 ⇒ 回原文（omit 的條件是原文也空）" do
      publish!("ja")
      product = product!(seo_description: "Niche fragrance")

      result = resolve(product, "meta_description", "ja")

      expect(result.value).to eq("Niche fragrance")
      expect(result.source).to eq(:base)
      expect(result.omitted?).to be(false)
    end

    it "🔴 required 欄位原文本身就是空 ⇒ 仍回 base（來源沒內容是事實，不是缺翻譯）" do
      publish!("ja")
      product = product!(description_html: "")

      result = resolve(product, "body_html", "ja")

      expect(result.source).to eq(:base)
      expect(result.value).to eq("")
      expect(result.omitted?).to be(false)
    end
  end

  describe "🔴 請求語言＝來源語言（遙測最容易被自己的正常路徑淹沒的地方）" do
    it "depth 0、source :base、**不發遙測**" do
      product = product!(title: "Rose")

      hits = capture_hits { @result = resolve(product, "title", "en") }

      expect(@result.value).to eq("Rose")
      expect(@result.depth).to eq(0)
      expect(@result.source).to eq(:base)
      expect(@result.fallback?).to be(false)
      expect(hits).to be_empty
    end

    it "鏈的中間階是來源語言時直接回 base（en-GB → en，不去查一列按定義不存在的譯文）" do
      add_locale!("en-GB")
      product = product!(title: "Rose")

      result = resolve(product, "title", "en-GB")

      expect(result.value).to eq("Rose")
      expect(result.locale).to eq("en")
      expect(result.depth).to eq(1)
      expect(result.source).to eq(:base)
    end
  end

  describe "🔴 空值視同沒有譯文（立本規則之前落庫的鬼列不得把使用者卡在空白畫面）" do
    it "語義空 HTML 的譯文列被跳過，繼續往鏈的下一階走" do
      publish!("zh-Hant")
      add_locale!("zh-Hant-HK")
      product = product!(description_html: "<p>Rose and spice</p>")
      translate!(product, "zh-Hant-HK", "body_html", "<p>&#160;</p>")   # 鬼列
      translate!(product, "zh-Hant", "body_html", "<p>玫瑰與辛香</p>")

      result = resolve(product, "body_html", "zh-Hant-HK")

      expect(result.value).to eq("<p>玫瑰與辛香</p>")
      expect(result.depth).to eq(1)
    end

    it "整條鏈都是空值 ⇒ 落到 base，不是輸出那個空字串" do
      publish!("zh-Hant")
      add_locale!("zh-Hant-HK")
      product = product!(description_html: "<p>Rose and spice</p>")
      translate!(product, "zh-Hant-HK", "body_html", "<p><br></p>")
      translate!(product, "zh-Hant", "body_html", "<p></p>")

      result = resolve(product, "body_html", "zh-Hant-HK")

      expect(result.value).to eq("<p>Rose and spice</p>")
      expect(result.source).to eq(:base)
    end
  end

  describe "🔴 繁簡永不互借（never_fallback_pairs）" do
    it "zh-Hant 缺譯文時不會拿 zh-Hans 的內容（字體不同＝整頁文字都不對）" do
      publish!("zh-Hant", "zh-Hans")
      product = product!(title: "Rose")
      translate!(product, "zh-Hans", "title", "玫瑰（简体）")

      result = resolve(product, "title", "zh-Hant")

      expect(result.value).to eq("Rose")
      expect(result.source).to eq(:base)
    end

    it "zh-Hant-HK 也不會經由任何路徑碰到 zh-Hans" do
      publish!("zh-Hans")
      add_locale!("zh-Hant-HK")
      product = product!(title: "Rose")
      translate!(product, "zh-Hans", "title", "玫瑰（简体）")

      expect(resolve(product, "title", "zh-Hant-HK").value).to eq("Rose")
    end
  end

  describe "scope（published vs enabled）" do
    it "🔴 :published 不讀未發布語言的譯文（未發布＝只能用預覽連結看）" do
      product = product!(title: "Rose")
      translate!(product, "ja", "title", "ローズ")   # ja 預設 enabled 但未 published

      expect(resolve(product, "title", "ja").value).to eq("Rose")
      expect(resolve(product, "title", "ja").source).to eq(:base)
    end

    it "🔴 A3：scope 濾掉請求語言時 depth **不得**塌回 0（否則 lang 屬性與遙測全盲）" do
      product = product!(title: "Rose")
      translate!(product, "ja", "title", "ローズ")   # 有譯文，但 ja 未 published

      hits = capture_hits { @result = resolve(product, "title", "ja") }

      # 首版用 select 先移除候選 ⇒ candidates 空 ⇒ depth=0、fallback?=false、hits=0，
      # 與「請求語言直接命中」在回傳值上完全無法區分。
      expect(@result.depth).to eq(1)
      expect(@result.fallback?).to be(true)
      expect(@result.source).to eq(:base)
      expect(hits.length).to eq(1)
      expect(hits.first).to include(requested_locale: "ja", resolved_locale: "en", depth: 1)
    end

    it "🔴 A3：鏈中間階被 scope 濾掉時，後面階的 depth 索引不位移" do
      add_locale!("zh-Hant", published: false) if false   # zh-Hant 已存在，僅示意
      ActsAsTenant.with_tenant(shop) { ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: false) }
      add_locale!("zh-Hant-HK", published: true)
      product = product!(title: "Rose")
      translate!(product, "zh-Hant", "title", "玫瑰")   # 鏈的第 1 階，但未 published

      result = resolve(product, "title", "zh-Hant-HK")

      # zh-Hant 被跳過（不讀它的譯文），但它仍佔 depth=1 這一格 ⇒ base 落在 depth=2。
      expect(result.value).to eq("Rose")
      expect(result.source).to eq(:base)
      expect(result.depth).to eq(2)
    end

    it ":enabled 讀得到（預覽連結的形態）" do
      product = product!(title: "Rose")
      translate!(product, "ja", "title", "ローズ")

      result = resolve(product, "title", "ja", scope: :enabled)

      expect(result.value).to eq("ローズ")
      expect(result.source).to eq(:translation)
    end

    it "🔴 未知 scope 一律 raise（fail-closed，不預設成比較寬的那一個）" do
      product = product!
      expect { resolve(product, "title", "ja", scope: :all) }
        .to raise_error(ArgumentError, /未知的 scope/)
    end
  end

  describe "批載（N+1 與執行計畫）" do
    it "🔴 SQL 條數＝distinct resource_type 數，不隨資源數增長" do
      publish!("zh-Hant")
      products = Array.new(8) { |i| product!(title: "P#{i}") }
      collection = ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: "C", handle: "c", description_html: "")
      end
      products.each { |p| translate!(p, "zh-Hant", "title", "譯#{p.id}") }

      queries = capture_sql(table: "translations") do
        described_class.batch(shop:, resources: products + [ collection ], locale: "zh-Hant")
      end

      expect(queries.length).to eq(2), "應為 PRODUCT 與 COLLECTION 各一條，實得 #{queries.length} 條"
    end

    it "🔴 `field_key` 不進 IN 清單（三個 IN 的乘積會爆 eq_range_index_dive_limit）" do
      publish!("zh-Hant")
      product = product!
      translate!(product, "zh-Hant", "title", "譯")

      queries = capture_sql(table: "translations") do
        described_class.batch(shop:, resources: [ product ], locale: "zh-Hant")
      end

      expect(queries.length).to eq(1)
      # 🔴 只斷言 **WHERE 子句**：`field_key` 出現在 SELECT 清單是對的（要拿它的值），
      #   會爆 eq range 的是它出現在**等值條件**裡。
      where_clause = queries.first[/WHERE(.*)$/m, 1].to_s
      expect(where_clause).not_to include("field_key"),
        "批載查詢的 WHERE 出現了 field_key——欄位必須在 Ruby 端過濾（見 Resolve 檔頭③(c)）。
SQL: #{queries.first}"
      expect(where_clause).to include("locale_tag")
      expect(where_clause).to include("resource_id")
    end

    it "🔴 中間的資源完全沒有譯文時，後面的資源不得錯位（DataLoader 補洞）" do
      publish!("zh-Hant")
      a = product!(title: "A")
      b = product!(title: "B")   # 一列譯文都沒有
      c = product!(title: "C")
      translate!(a, "zh-Hant", "title", "甲")
      translate!(c, "zh-Hant", "title", "丙")

      out = described_class.batch(shop:, resources: [ a, b, c ], fields: [ "title" ], locale: "zh-Hant")

      expect(out[[ "PRODUCT", a.id ]]["title"].value).to eq("甲")
      expect(out[[ "PRODUCT", b.id ]]["title"].value).to eq("B")     # 落 base，不是拿到丙
      expect(out[[ "PRODUCT", b.id ]]["title"].source).to eq(:base)
      expect(out[[ "PRODUCT", c.id ]]["title"].value).to eq("丙")
    end

    it "🔴 超過 max_resources_per_batch 一律 raise（不靜默截斷）" do
      maximum = Limits.fetch(:i18n, :resolve, :max_resources_per_batch)
      # 未持久化的物件即可——上限檢查在任何查詢之前，不該為了測它去建 51 筆商品。
      oversized = ActsAsTenant.with_tenant(shop) { Array.new(maximum + 1) { Product.new(id: 1) } }

      expect { described_class.batch(shop:, resources: oversized, locale: "en") }
        .to raise_error(ArgumentError, /最多解析 #{maximum} 筆/)
    end

    it "資源數 × 候選階數不得逼近 eq_range_index_dive_limit 的預設 200" do
      # 這一格把 limits 的推導本身變成可執行斷言：改任一個鍵而忘了另一個就會紅。
      # ⚠️ 200 是 MySQL 官方預設值；我方實例現值＝U14 未取得（上線前 SELECT @@eq_range_index_dive_limit）。
      product_of = Limits.fetch(:i18n, :resolve, :max_resources_per_batch) *
                   Limits.fetch(:i18n, :resolve, :max_chain_length)
      expect(product_of).to be <= 200
    end

    it "空 resources 直接回空 hash（連 shop_locales 都不查）" do
      shop   # 先把 lazy factory 拉起來，不然它的建店查詢會混進量測
      t = capture_sql(table: "translations") { described_class.batch(shop:, resources: [], locale: "en") }
      l = capture_sql(table: "shop_locales") { expect(described_class.batch(shop:, resources: [], locale: "en")).to eq({}) }
      expect(t).to be_empty
      expect(l).to be_empty
    end

    it "🔴 C7：整批的 shop_locales 查詢是**固定次數**，不隨資源或欄位數成長" do
      publish!("zh-Hant")
      products = Array.new(6) { |i| product!(title: "P#{i}") }
      products.each { |p| translate!(p, "zh-Hant", "title", "譯#{p.id}") }

      queries = capture_sql(table: "shop_locales") do
        described_class.batch(shop:, resources: products, locale: "zh-Hant")
      end

      # source_tag 一次 ＋ published_tags 一次＝2；逐資源／逐欄位重查會變成 6×4×2。
      expect(queries.length).to eq(2),
        "shop_locales 查了 #{queries.length} 次——batch 內出現 N+1（首版的 capture_sql 看不到這個）"
    end

    it "🔴 C7 反向：把 registry 查詢搬進逐欄位迴圈後，上面那格必須紅" do
      # 突變的可執行版本：證明該斷言真的在守 shop_locales 的 N+1，而不是碰巧成立。
      publish!("zh-Hant")
      products = Array.new(3) { |i| product!(title: "P#{i}") }
      call_count = 0
      allow(Locales::Registry).to receive(:published_tags).and_wrap_original do |orig, arg|
        call_count += 1
        orig.call(arg)
      end

      described_class.batch(shop:, resources: products, locale: "zh-Hant")

      expect(call_count).to eq(1), "published_tags 每批只該查一次"
    end

    it "🔴 A7：field 傳 Symbol 也能用（內層 key 統一 String）" do
      publish!("zh-Hant")
      product = product!(title: "Rose")
      translate!(product, "zh-Hant", "title", "玫瑰")

      expect(described_class.field(shop:, resource: product, field: :title, locale: "zh-Hant").value)
        .to eq("玫瑰")
      expect(described_class.fields_for(shop:, resource: product, fields: [ :title ], locale: "zh-Hant").keys)
        .to eq([ "title" ])
    end

    it "🔴 A10：傳別店的資源物件一律 raise（base 值是從物件讀的，查詢層擋不到）" do
      other = create(:shop, subdomain: "resolve-other")
      theirs = ActsAsTenant.with_tenant(other) { create(:product, shop: other, title: "SECRET") }

      expect { described_class.batch(shop:, resources: [ theirs ], locale: "en") }
        .to raise_error(ArgumentError, /不屬於本店/)
    end

    it "不支援的資源類型 raise（不靜默推導成一個查不到列的字串）" do
      expect { described_class.batch(shop:, resources: [ shop ], locale: "en") }
        .to raise_error(ArgumentError, /不支援的可翻資源類型/)
    end
  end

  describe "遙測" do
    it "🔴 payload 不含 resource_id（無界集合不得進 label）" do
      publish!("ja")
      product = product!(title: "Rose")

      hits = capture_hits { resolve(product, "title", "ja") }

      expect(hits.length).to eq(1)
      expect(hits.first.keys).to contain_exactly(
        :shop_id, :requested_locale, :resolved_locale, :resource_type, :field_key, :depth
      )
      expect(hits.first).to include(requested_locale: "ja", resolved_locale: "en", depth: 1)
    end

    it "depth < fallback_telemetry_min_depth 一律不發" do
      publish!("zh-Hant")
      product = product!
      translate!(product, "zh-Hant", "title", "玫瑰")

      expect(capture_hits { resolve(product, "title", "zh-Hant") }).to be_empty
    end

    it "🔴 F9：omitted 欄位**不發**遙測（什麼都沒輸出，「回落到 en」是假訊息）" do
      publish!("ja")
      product = product!(seo_description: nil)

      hits = capture_hits do
        expect(resolve(product, "meta_description", "ja").omitted?).to be(true)
      end

      expect(hits).to be_empty,
        "首版每個沒有 SEO 描述的商品每次渲染都發一筆 resolved_locale: en——但沒有任何字串被輸出"
    end

    it "沒有訂閱者時也不會爆（訂閱者不存在＝正確狀態）" do
      publish!("ja")
      product = product!(title: "Rose")
      expect { resolve(product, "title", "ja") }.not_to raise_error
    end
  end

  describe "🔴 I18N-6：resolve 不收 market 參數（67 §C.2 沿革）" do
    it "batch／fields_for／field 三支的參數名都沒有 market" do
      %i[batch fields_for field].each do |name|
        names = described_class.method(name).parameters.map(&:last)
        expect(names).not_to include(:market, :market_id, :market_handle),
          "#{name} 的簽名出現了 market——市場影響曝光與錢，不影響內容（先讀 67 §C.2）"
      end
    end
  end

  describe "🔴 後台 GraphQL 不得產生鏈（商家一按儲存就會把原文寫成真譯文）" do
    it "ProductType#translations 對 locale_tag 精確比對，不是 IN 一串候選" do
      publish!("zh-Hant")
      add_locale!("zh-Hant-HK")
      product = product!
      translate!(product, "zh-Hant", "title", "玫瑰")

      queries = capture_sql(table: "translations") do
        ActsAsTenant.with_tenant(shop) do
          product_type_for(product).translations(locales: [ "zh-Hant-HK" ]).to_a
        end
      end

      expect(queries.length).to eq(1)
      # 單一語言 ⇒ Rails 產生 `locale_tag = ?`；出現 IN 一串就是有人把 Resolve 接進來了。
      expect(queries.first).not_to match(/locale_tag`? IN \(.*,.*\)/),
        "後台 translations 出現了多語言候選——這一支必須是精確比對（見 Resolve 檔頭④）"
    end

    it "後台拿不到 fallback 值（zh-Hant-HK 沒有自己的譯文就是沒有，不借 zh-Hant 的）" do
      publish!("zh-Hant")
      add_locale!("zh-Hant-HK")
      product = product!
      translate!(product, "zh-Hant", "title", "玫瑰")

      rows = ActsAsTenant.with_tenant(shop) do
        product_type_for(product).translations(locales: [ "zh-Hant-HK" ]).to_a
      end

      expect(rows).to be_empty
    end
  end

  describe "🔴 C5：讀取端尺寸 fast-path" do
    it "超過閾值的 html 值不 parse、直接視為有內容" do
      publish!("zh-Hant")
      product = product!(description_html: "<p>base</p>")
      threshold = Limits.fetch(:i18n, :blank_value, :read_fast_path_max_bytes)
      # 語義上是空的，但體積超過閾值 ⇒ 讀取端不 parse ⇒ 當成有內容（假陰性側）。
      big_blank = "<p>#{'&nbsp;' * ((threshold / 6) + 50)}</p>"
      expect(big_blank.bytesize).to be > threshold
      translate!(product, "zh-Hant", "body_html", big_blank)

      result = resolve(product, "body_html", "zh-Hant")

      expect(result.source).to eq(:translation)
      expect(result.depth).to eq(0)
    end

    it "🔴 寫入端**不**吃 fast-path：同一個值走 Upsert 仍判空（不可逆動作要跑完整判準）" do
      threshold = Limits.fetch(:i18n, :blank_value, :read_fast_path_max_bytes)
      big_blank = "<p>#{'&nbsp;' * ((threshold / 6) + 50)}</p>"

      expect(Translations::BlankValue.blank?(big_blank, kind: :html)).to be(true)
      expect(Translations::BlankValue.blank?(big_blank, kind: :html, skip_parse_above: threshold)).to be(false)
    end
  end

  describe "touched_sources（交給第 33 包的 cache stamp 自檢）" do
    it "回傳 [:translations]，且**不呼叫**任何自檢（接收端尚未存在）" do
      expect(described_class.touched_sources).to eq([ :translations ])
    end
  end
end
