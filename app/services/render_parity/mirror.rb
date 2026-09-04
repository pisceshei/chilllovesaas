# frozen_string_literal: true

module RenderParity
  # 鏡像店：把本尊店的**資料面**（店名、語言、市場國別、商品、集合、頁面、選單）對齊到我方一間店，讓兩邊渲染同一套主題時
  # 只剩引擎差異可比（使用者 2026-09-03 裁定：preview／買家前台必須與本尊同主題渲染完全一樣）。
  #
  # ①這是什麼：`spec/fixtures/render_parity/{name}.json` 描述本尊店快照（hoko.vip 2026-09-03：products.json／
  #   collections.json／首頁選單／`Shopify.locale`／`Shopify.country`），本服務**冪等**地把它建到 `subdomain` 那間店。
  # ②怎麼做：只建缺的、不刪商家資料（商品／集合／頁面／選單存在即跳過）；語言與市場是「對齊」而非新增——來源語言
  #   改成快照語言（本尊簡體店 ⇒ 我方 `zh-Hans`，輸出碼由 `ThemeEngine::LocaleTags` 轉 `zh-CN`）、已發布語言集＝快照
  #   `shop.languages`（順序＝position；集合外的語言取消發布）、主市場國別改成快照 `Shopify.country`；E15（2026-09-04）：
  #   快照 `markets[]` 的非主市場逐一建立／對齊（region 型、active、regions 加缺刪多、一個 subfolder presence、語言白名單
  #   ＝同一語言集、預設同店預設）——本尊五市場共用 hoko.vip 與五語言（external-facts §G21），我方 67 §F.1(b) 恆帶地區
  #   ⇒ 每個市場一組 `/{lang}-{region}` 前綴（多國市場的 region＝`suffix`，V-225 暫案 C）。主題：匯入主題給
  #   `THEME_CHECKSUM`（storage/themes/{checksum}，內容定址可共用）；否則用名稱鍵 `{fixture_name}-{version}`——`themes/`
  #   第一方目錄（bt3 demo 的 Ella 即此形）或非 production 的 `test/fixtures/themes/`。
  # ③跨功能：`lib/tasks/render_parity.rake`（`render_parity:mirror[subdomain,spec]`）、`RenderParity::Report`（對表）、
  #   `docs/dev/e8-render-parity.md`；語言集直接決定 `Storefront::LocalizationContext` 的 `available_languages`（Ella 頁首
  #   語言鈕只在 size > 1 時渲染）與 `Seo::HreflangMatrix` 的展開集（多市場逐國展開＝D80 裁定前的登記差異）。
  class Mirror
    Result = Struct.new(:shop, :log, keyword_init: true)

    def self.call(**) = new(**).call

    # @param subdomain [String] 目標店 subdomain（不存在則建立）
    # @param spec [Hash] 快照描述（見 spec/fixtures/render_parity/hoko.json）
    # @param theme_checksum [String, nil] production 用：已匯入主題的 content_checksum
    def initialize(subdomain:, spec:, theme_checksum: nil)
      @subdomain = subdomain.to_s
      @spec = spec
      @theme_checksum = theme_checksum.presence
      @log = []
    end

    def call
      shop = ensure_shop
      ActsAsTenant.with_tenant(shop) do
        align_locales(shop)
        align_markets(shop)
        ensure_theme(shop)
        ensure_products(shop)
        ensure_collections(shop)
        ensure_pages(shop)
        ensure_menus(shop)
      end
      Result.new(shop:, log: @log)
    end

    private

    def note(message) = @log << message

    def shop_spec = @spec.fetch("shop")
    def locale_tag = shop_spec.fetch("locale")

    # 已發布語言集（有序）；缺鍵＝只有來源語言（E8 舊快照形）。來源語言必在集合內（它不可取消發布）。
    def languages
      @languages ||= begin
        list = Array(shop_spec["languages"]).map { |t| Locales::Tag.normalize(t.to_s) }.presence || [ locale_tag ]
        raise ArgumentError, "shop.languages 必須含來源語言 #{locale_tag}（SOURCE_LOCALE_IMMUTABLE）" unless list.include?(locale_tag)

        list
      end
    end

    def ensure_shop
      created = false
      shop = ActsAsTenant.without_tenant do
        Shop.find_or_create_by!(subdomain: @subdomain) do |record|
          created = true
          record.assign_attributes(
            name: shop_spec.fetch("name"), status: "active",
            store_currency: shop_spec.fetch("currency"),
            timezone: shop_spec.fetch("timezone", "Asia/Hong_Kong"), plan: "basic"
          )
        end
      end
      # D81：格式兩欄跟隨快照（缺鍵 ⇒ 該幣別種子）。
      defaults = Shop::MoneyFormatDefaults.for(shop_spec.fetch("currency"))
      shop.update!(name: shop_spec.fetch("name"), store_currency: shop_spec.fetch("currency"),
                   customer_accounts_enabled: shop_spec.fetch("customer_accounts_enabled", true),
                   taxes_included: shop_spec.fetch("taxes_included", false),
                   money_format: shop_spec.fetch("money_format", defaults[0]),
                   money_with_currency_format: shop_spec.fetch("money_with_currency_format", defaults[1]))
      note("shop #{created ? 'created' : 'aligned'}: #{shop.subdomain} (#{shop.name})")
      shop
    end

    # 來源語言 ⇒ 快照語言；已發布集 ⇒ 快照 `languages`（順序＝position）；集合外的語言取消發布（不刪列、譯文保留）。
    # 順序受 ShopLocale 驗證約束：先建缺列（未發布），撤舊來源（single_source_per_shop），立新來源（來源必 published＋enabled），
    # 再逐列對齊 published／enabled／position。
    def align_locales(shop)
      locales = ShopLocale.where(shop_id: shop.id)
      languages.each_with_index do |tag, index|
        next if locales.exists?(locale_tag: tag)

        ShopLocale.create!(shop_id: shop.id, locale_tag: tag, enabled: true, published: false, is_source: false, position: index)
      end
      target = locales.find_by!(locale_tag: locale_tag)
      old_source = locales.where(is_source: true).where.not(id: target.id).first
      old_source&.update!(is_source: false)
      target.update!(is_source: true, published: true, enabled: true)
      languages.each_with_index do |tag, index|
        row = locales.find_by!(locale_tag: tag)
        wanted = { published: true, enabled: true, position: index }
        row.update!(wanted) if wanted.any? { |attribute, value| row.public_send(attribute) != value }
      end
      locales.where.not(locale_tag: languages).where(published: true).find_each { |row| row.update!(published: false) }
      note("locales published=#{languages.join(',')} source=#{locale_tag} (was #{old_source&.locale_tag || locale_tag})")
    end

    # 主市場：國別 ⇒ 快照 `Shopify.country`、名稱／handle 跟隨；presence 語言白名單 ⇒ `languages`。
    # 非主市場（快照 `markets[]`）：find-or-create（region 型、active）、regions 加缺刪多、恰一個 subfolder presence
    # （`suffix`；本尊市場共用主網域、無自身前綴，我方 67 §F.1(b) 需要 region 識別字才能組前綴）、白名單同主市場。
    # 🔴 不刪快照外的既有市場（不刪商家資料原則；鏡像店由本服務獨占，實務上不會出現）。
    def align_markets(shop)
      country = shop_spec.fetch("country")
      market = Market.find_by!(is_primary: true)
      region = market.market_regions.first
      region.update!(country_code: country) if region && region.country_code != country
      name = shop_spec.fetch("market_name", country)
      market.update!(name:, handle: country.downcase) if market.name != name || market.handle != country.downcase
      presence = market.market_web_presences.order(:id).first or raise "primary market 無 web presence（shop #{shop.id}）"
      align_presence_locales(shop, presence)
      note("market #{market.handle} country=#{country} presence default=#{locale_tag} " \
           "prefixes=#{languages.map { |tag| Markets::UrlPrefix.for(presence, tag) }.join(',')}")

      Array(@spec["markets"]).each do |m|
        handle = m.fetch("handle")
        extra = Market.find_by(handle:)
        if extra
          extra.update!(name: m.fetch("name")) if extra.name != m.fetch("name")
        else
          extra = Market.create!(name: m.fetch("name"), handle:, status: "active", market_type: "region", is_primary: false)
        end
        wanted = m.fetch("countries").map { |code| code.to_s.strip.upcase }
        existing = extra.market_regions.pluck(:country_code)
        (wanted - existing).each { |code| extra.market_regions.create!(shop_id: shop.id, country_code: code) }
        extra.market_regions.where.not(country_code: wanted).delete_all if (existing - wanted).any?
        suffix = m["suffix"].presence
        if suffix.nil?
          # D80（2026-09-04）：本尊的非主市場共用主網域、沒有自己的 presence（/en-us 404；市場由買家選國 cookie 決定）
          # ⇒ 我方同形：不建 presence；E15 期建過的 subfolder presence 一併拆掉（冪等）。
          removed = extra.market_web_presences.count
          extra.market_web_presences.destroy_all if removed.positive?
          note("market #{extra.handle} regions=#{wanted.size} presence=none（共用主網域）#{" removed=#{removed}" if removed.positive?}")
          next
        end
        extra_presence = extra.market_web_presences.order(:id).first ||
                         extra.market_web_presences.create!(shop_id: shop.id, subfolder_suffix: suffix,
                                                            default_shop_locale: locale_tag)
        if extra_presence.domain_id.nil? && extra_presence.subfolder_suffix != suffix
          extra_presence.update!(subfolder_suffix: suffix)
        end
        align_presence_locales(shop, extra_presence)
        note("market #{extra.handle} regions=#{wanted.size} suffix=#{extra_presence.subfolder_suffix} " \
             "prefixes=#{languages.map { |tag| Markets::UrlPrefix.for(extra_presence, tag) }.join(',')}")
      end
    end

    # presence 白名單 ⇒ `languages`（position＝集合序、全部開放、預設＝來源語言）；集合外的列刪除（該 presence 未曾對買家
    # 開放過那些語言，不涉 67 §C.8 的關閉語義）。順序受 MarketWebPresenceLocale 驗證約束：先撤舊預設旗、改 presence
    # default_shop_locale，再建／對齊各列（uq_mwpl_single_default 只容一列 default）。
    def align_presence_locales(shop, presence)
      rows = presence.market_web_presence_locales
      if presence.default_shop_locale != locale_tag
        rows.where(is_market_default: true).find_each { |row| row.update!(is_market_default: false) }
        presence.update!(default_shop_locale: locale_tag)
      end
      rows.where(is_market_default: true).where.not(locale_tag: locale_tag).find_each { |row| row.update!(is_market_default: false) }
      languages.each_with_index do |tag, index|
        wanted = { position: index, open_to_buyers: true, closed_at: nil, is_market_default: tag == locale_tag }
        row = rows.find_by(locale_tag: tag) || rows.create!(shop_id: shop.id, locale_tag: tag, **wanted)
        row.update!(wanted) if wanted.any? { |attribute, value| row.public_send(attribute) != value }
      end
      rows.where.not(locale_tag: languages).delete_all
    end

    def ensure_theme(shop)
      if Theme.where(shop_id: shop.id, role: "published").exists?
        note("theme: published theme exists, kept")
        return
      end
      t = @spec.fetch("theme")
      theme =
        if @theme_checksum
          Theme.create!(shop_id: shop.id, name: t.fetch("name"), version: t.fetch("version"), role: "published",
                        published_at: Time.current, source: "import", license_attested: true,
                        content_checksum: @theme_checksum)
        else
          # 名稱鍵主題（Sources.key_for＝`{name.parameterize}-{version}`）：先確認來源目錄存在——`themes/{key}`（第一方，
          # production 可用；bt3 demo 的 Ella 即此形）或非 production 的 `test/fixtures/themes/{key}`——否則 fail-closed。
          key = "#{t.fetch('fixture_name').to_s.parameterize}-#{t.fetch('version')}"
          available = Rails.root.join("themes", key).directory? ||
                      (!Rails.env.production? && Rails.root.join("test", "fixtures", "themes", key).directory?)
          raise ArgumentError, "無主題來源：themes/#{key} 不存在且未給 THEME_CHECKSUM" unless available

          Theme.create!(shop_id: shop.id, name: t.fetch("fixture_name"), version: t.fetch("version"), role: "published",
                        published_at: Time.current, source: "licensed", license_attested: true)
        end
      note("theme created: #{theme.name} #{theme.version} key=#{ThemeEngine::Sources.key_for(theme)}")
    end

    def ensure_products(shop)
      @spec.fetch("products", []).each do |p|
        if Product.find_by(shop_id: shop.id, handle: p.fetch("handle"))
          note("product exists: #{p['handle']}")
          align_stock(shop, p)
          next
        end
        result = Catalog::SaveProduct.call(shop:, input: {
          title: p.fetch("title"), handle: p.fetch("handle"), vendor: p["vendor"], product_type: p["product_type"],
          tags: p.fetch("tags", []), description_html: p.fetch("body_html", ""), status: "active",
          variants: [ { price: p.fetch("price"), taxable: true } ]
        })
        raise "product #{p['handle']}: #{result.user_errors.inspect}" if result.user_errors.any?

        note("product created: #{p['handle']} #{p['price']} #{shop.store_currency}")
        align_stock(shop, p)
      end
    end

    # E8b：快照 `inventory_quantity`（本尊 /products.json `available`：cosy-lamp true、其餘 false；實際數量未取得 ⇒ 快照給值，V）
    # ⇒ 店預設地點的 inventory_level.available；缺鍵不動（沿用 SaveProduct 預設＝tracked、0）。
    def align_stock(shop, p)
      return unless p.key?("inventory_quantity")

      variant = Product.find_by!(shop_id: shop.id, handle: p.fetch("handle")).product_variants.order(:id).first
      item = InventoryItem.find_by(shop_id: shop.id, product_variant_id: variant.id) or return note("no inventory item: #{p['handle']}")
      location = Location.where(shop_id: shop.id).order(:id).first or raise "shop #{shop.subdomain} 無地點"
      target = p["inventory_quantity"].to_i
      current = InventoryLevel.where(shop_id: shop.id, inventory_item_id: item.id, location_id: location.id).sum(:available)
      return if current == target

      # 庫存唯一寫入入口（13 §F5；rubocop Chilllove/InventoryDirectWrite）：set 模式、忽略 compare，每次對齊一把新 key
      result = Inventory::Adjust.call(shop:, mode: "set", input: {
        name: "available", reason: "correction", idempotency_key: "render-parity-mirror:#{SecureRandom.uuid}",
        changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                     location_id: "gid://chilllove/Location/#{location.id}",
                     quantity: target, ignore_compare_quantity: true } ] })
      raise "stock align #{p['handle']}: #{result.user_errors.inspect}" if result.user_errors.any?

      note("stock aligned: #{p['handle']} = #{target}")
    end

    def ensure_collections(shop)
      @spec.fetch("collections", []).each do |c|
        if (existing = Collection.find_by(shop_id: shop.id, handle: c.fetch("handle")))
          # E8b：既有系列只對齊 sort_order（本尊首頁系列 admin「Default sort: Most relevant」）
          if c["sort_order"].present? && existing.sort_order != c["sort_order"]
            existing.update!(sort_order: c["sort_order"])
            note("collection sort aligned: #{c['handle']} = #{c['sort_order']}")
          else
            note("collection exists: #{c['handle']}")
          end
          next
        end
        gids = Product.where(shop_id: shop.id, handle: c.fetch("products", [])).pluck(:id).map { |id| "gid://chilllove/Product/#{id}" }
        result = Catalog::SaveCollection.call(shop:, input: {
          title: c.fetch("title"), handle: c.fetch("handle"), collection_type: "manual", product_ids: gids,
          sort_order: c["sort_order"]
        }.compact)
        raise "collection #{c['handle']}: #{result.user_errors.inspect}" if result.user_errors.any?

        note("collection created: #{c['handle']} (#{gids.size} products)")
      end
    end

    def ensure_pages(shop)
      @spec.fetch("pages", []).each do |pg|
        page = Page.find_by(shop_id: shop.id, handle: pg.fetch("handle"))
        if page
          # E8b：既有草稿頁補發布（本尊頁面為已發布；先前 create 未帶 published_at ⇒ 前台 404）
          page.update!(published_at: Time.current) if page.published_at.nil?
          page.update!(template_suffix: pg["template_suffix"]) if pg.key?("template_suffix") && page.template_suffix != pg["template_suffix"]
          note("page exists: #{pg['handle']}")
        else
          Page.create!(shop_id: shop.id, title: pg.fetch("title"), handle: pg.fetch("handle"), body_html: pg.fetch("body_html", ""),
                       published_at: Time.current, template_suffix: pg["template_suffix"])
          note("page created: #{pg['handle']}")
        end
      end
    end

    def ensure_menus(shop)
      @spec.fetch("menus", []).each do |m|
        created = false
        menu = Menu.find_or_create_by!(handle: m.fetch("handle")) do |record|
          created = true
          record.title = m.fetch("title")
        end
        if created
          m.fetch("items").each_with_index do |(title, item_type, url), index|
            MenuItem.create!(shop_id: shop.id, menu:, title:, item_type:, url:, position: index + 1)
          end
        end
        note("menu #{created ? 'created' : 'exists'}: #{m['handle']}")
      end
    end
  end
end
