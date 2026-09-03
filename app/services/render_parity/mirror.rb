# frozen_string_literal: true

module RenderParity
  # 鏡像店：把本尊店的**資料面**（店名、語言、市場國別、商品、集合、頁面、選單）對齊到我方一間店，讓兩邊渲染同一套主題時
  # 只剩引擎差異可比（使用者 2026-09-03 裁定：preview／買家前台必須與本尊同主題渲染完全一樣）。
  #
  # ①這是什麼：`spec/fixtures/render_parity/{name}.json` 描述本尊店快照（hoko.vip 2026-09-03：products.json／
  #   collections.json／首頁選單／`Shopify.locale`／`Shopify.country`），本服務**冪等**地把它建到 `subdomain` 那間店。
  # ②怎麼做：只建缺的、不刪商家資料（商品／集合／頁面／選單存在即跳過）；語言與市場是「對齊」而非新增——來源語言
  #   改成快照語言（本尊簡體店 ⇒ 我方 `zh-Hans`，輸出碼由 `ThemeEngine::LocaleTags` 轉 `zh-CN`）、主市場國別改成快照
  #   `Shopify.country`。主題：匯入主題給 `THEME_CHECKSUM`（storage/themes/{checksum}，內容定址可共用）；否則用名稱鍵
  #   `{fixture_name}-{version}`——`themes/` 第一方目錄（bt3 demo 的 Ella 即此形）或非 production 的 `test/fixtures/themes/`。
  # ③跨功能：`lib/tasks/render_parity.rake`（`render_parity:mirror[subdomain,spec]`）、`RenderParity::Report`（對表）、
  #   `docs/dev/e8-render-parity.md`。
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
        align_market(shop)
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

    # 來源語言 ⇒ 快照語言、其餘語言全部取消發布（本尊店只有一個已發布語言）。
    # 順序受 ShopLocale 驗證約束：先撤舊來源（single_source_per_shop），再立新來源（來源必 published＋enabled）。
    def align_locales(shop)
      locales = ShopLocale.where(shop_id: shop.id)
      target = locales.find_by(locale_tag: locale_tag) ||
               ShopLocale.create!(shop_id: shop.id, locale_tag: locale_tag, enabled: true, published: false,
                                  is_source: false, position: locales.count)
      old_source = locales.where(is_source: true).where.not(id: target.id).first
      old_source&.update!(is_source: false)
      target.update!(is_source: true, published: true, enabled: true)
      locales.where.not(id: target.id).find_each { |row| row.update!(published: false) }
      note("locale source=#{locale_tag} (was #{old_source&.locale_tag || locale_tag})")
    end

    # 主市場國別 ⇒ 快照 `Shopify.country`；presence 預設語言與開放語言 ⇒ 只剩快照語言。
    # 順序受 MarketWebPresenceLocale 驗證約束：先改 presence.default_shop_locale，再撤舊預設列，最後立新預設列。
    def align_market(shop)
      country = shop_spec.fetch("country")
      market = Market.find_by!(is_primary: true)
      region = market.market_regions.first
      if region && region.country_code != country
        region.update!(country_code: country)
        market.update!(name: shop_spec.fetch("market_name", country), handle: country.downcase)
      end
      presence = market.market_web_presences.first or raise "primary market 無 web presence（shop #{shop.id}）"
      presence.update!(default_shop_locale: locale_tag) if presence.default_shop_locale != locale_tag
      rows = presence.market_web_presence_locales
      rows.where.not(locale_tag: locale_tag).find_each { |row| row.update!(is_market_default: false) }
      row = rows.find_by(locale_tag: locale_tag) ||
            rows.create!(shop_id: shop.id, locale_tag: locale_tag, position: 0, is_market_default: true, open_to_buyers: true)
      row.update!(is_market_default: true, open_to_buyers: true, closed_at: nil, position: 0)
      rows.where.not(id: row.id).delete_all
      note("market #{market.handle} country=#{country} presence default=#{locale_tag} prefix=#{Markets::UrlPrefix.for(presence, locale_tag)}")
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
          next
        end
        result = Catalog::SaveProduct.call(shop:, input: {
          title: p.fetch("title"), handle: p.fetch("handle"), vendor: p["vendor"], product_type: p["product_type"],
          tags: p.fetch("tags", []), description_html: p.fetch("body_html", ""), status: "active",
          variants: [ { price: p.fetch("price"), taxable: true } ]
        })
        raise "product #{p['handle']}: #{result.user_errors.inspect}" if result.user_errors.any?

        note("product created: #{p['handle']} #{p['price']} #{shop.store_currency}")
      end
    end

    def ensure_collections(shop)
      @spec.fetch("collections", []).each do |c|
        if Collection.find_by(shop_id: shop.id, handle: c.fetch("handle"))
          note("collection exists: #{c['handle']}")
          next
        end
        gids = Product.where(shop_id: shop.id, handle: c.fetch("products", [])).pluck(:id).map { |id| "gid://chilllove/Product/#{id}" }
        result = Catalog::SaveCollection.call(shop:, input: {
          title: c.fetch("title"), handle: c.fetch("handle"), collection_type: "manual", product_ids: gids
        })
        raise "collection #{c['handle']}: #{result.user_errors.inspect}" if result.user_errors.any?

        note("collection created: #{c['handle']} (#{gids.size} products)")
      end
    end

    def ensure_pages(shop)
      @spec.fetch("pages", []).each do |pg|
        page = Page.find_by(shop_id: shop.id, handle: pg.fetch("handle"))
        if page
          note("page exists: #{pg['handle']}")
        else
          Page.create!(shop_id: shop.id, title: pg.fetch("title"), handle: pg.fetch("handle"), body_html: pg.fetch("body_html", ""))
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
