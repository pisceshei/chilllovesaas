# frozen_string_literal: true

# 平台層 drops（包 30；PoC drops 的生產移植——「drops 接 DB」的落點）。
#
# 🔴 安全邊界（25 §6 ③）：**只暴露白名單屬性**。DB-backed drops 一律顯式方法委派，
#   `liquid_method_missing` 只回 nil＋遙測，**絕不**反射轉發到 AR model
#   （反射轉發＝把整個 AR 介面暴露給主題代碼）。
# 🔴 金額：`price` 族回 **integer cents**（Liquid 契約與我方儲存同尺度，鐵律 3
#   在這一層免換算；顯示轉換在 money filter）。
module ThemeEngine
  # attrs-hash 兜底 drop（設定值、雜項物件）。
  class BaseDrop < Liquid::Drop
    def initialize(attrs = {})
      super()
      @attrs = attrs
    end

    def liquid_method_missing(name)
      k = name.to_s
      ThemeEngine.count_miss("#{self.class.name.split('::').last}.#{k}") unless @attrs.key?(k)
      @attrs[k]
    end
  end

  # 佔位圖（媒體檔缺席時的過渡形態；27 §7 相容策略）。
  class PlaceholderImageDrop < BaseDrop
    attr_reader :width, :height, :alt

    def initialize(label:, w: 900, h: 1200)
      super()
      @label, @width, @height, @alt = label, w, h, label
    end

    def aspect_ratio = @width.to_f / @height
    def src = url

    def url
      svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}"><rect width="100%" height="100%" fill="#e8ded2"/><text x="50%" y="50%" font-size="#{@width / 18}" fill="#a9502c" text-anchor="middle">#{CGI.escapeHTML(@label.to_s)}</text></svg>)
      "data:image/svg+xml;utf8,#{svg.gsub('#', '%23').gsub('"', "'")}"
    end

    def to_s = url
    def preview_image = self
    def media_type = "image"
    def position = 1
  end

  # 媒體 drop（DB：Media＋StoredFile）。
  class ImageDrop < Liquid::Drop
    def initialize(media)
      super()
      @media = media
      @file = media.stored_file
    end

    def id = @media.id
    def alt = @file&.alt_text
    def width = @file&.width
    def height = @file&.height
    def aspect_ratio = width && height && height.positive? ? width.to_f / height : nil
    def media_type = "image"
    def position = @media.position
    def src = url
    def url = @file && Storage::LocalDisk.respond_to?(:url_for) ? Storage::LocalDisk.url_for(@file.storage_key) : nil
    def to_s = url.to_s
    def preview_image = self
  end

  class VariantDrop < Liquid::Drop
    def initialize(variant, product_drop)
      super()
      @v = variant
      @product = product_drop
    end

    attr_reader :product

    def id = @v.id
    def title = @v.title
    def sku = @v.sku
    def price = @v.price_cents
    def compare_at_price = @v.compare_at_price_cents
    def available = true # v1：可購買性由 lookup 前置；庫存感知隨前台包

    # 選項值走 join（product_variant_option_values → option_values）；無 option1..3 欄。
    def options
      @options ||= begin
        @v.option_values.sort_by { |ov| ov.product_option_id }.map(&:value)
      rescue StandardError
        []
      end
    end

    def option1 = options[0]
    def option2 = options[1]
    def option3 = options[2]
    def featured_image = @product.featured_image
    def featured_media = @product.featured_image
    def image = @product.featured_image
    def requires_shipping = @v.requires_shipping
    def taxable = @v.taxable
    def unit_price = nil
    def unit_price_measurement = nil
    def selected_selling_plan_allocation = nil
    def quantity_price_breaks = []
    def quantity_rule = { "min" => 1, "max" => nil, "increment" => 1 }
    def matched = true

    def liquid_method_missing(name)
      ThemeEngine.count_miss("VariantDrop.#{name}")
      nil
    end
  end

  # DB-backed 商品 drop（白名單委派；輸入＝已 preload 關聯的 Product）。
  class ProductDrop < Liquid::Drop
    def initialize(product, url_prefix: "")
      super()
      @p = product
      @url_prefix = url_prefix
    end

    def id = @p.id
    def title = @p.title
    def handle = @p.handle
    def vendor = @p.vendor
    def type = @p.product_type
    def tags = @p.tags.to_a
    def description = @p.description_html
    def content = @p.description_html
    def url = "#{@url_prefix}/products/#{@p.handle}"

    def variants
      @variants ||= @p.product_variants.map { |v| VariantDrop.new(v, self) }
    end

    def selected_or_first_available_variant = variants.first
    def first_available_variant = variants.first
    def selected_variant = nil
    def has_only_default_variant = variants.size <= 1

    def images
      @images ||= if @p.respond_to?(:media) && @p.association(:media).loaded?
        @p.media.filter_map { |m| ImageDrop.new(m) if m.stored_file }
      else
        []
      end
    end

    def media = images
    def media_count = images.size
    def featured_image = images.first || PlaceholderImageDrop.new(label: title)
    def featured_media = featured_image

    def price = variants.filter_map(&:price).min || 0
    def price_min = price
    def price_max = variants.filter_map(&:price).max || 0
    def price_varies = price_min != price_max
    def compare_at_price = variants.filter_map(&:compare_at_price).min
    def compare_at_price_min = compare_at_price
    def compare_at_price_max = variants.filter_map(&:compare_at_price).max
    def compare_at_price_varies = false
    def available = true
    def gift_card? = false
    def requires_selling_plan = false
    def selling_plan_groups = []
    def quantity_price_breaks_configured? = false
    def collections = []
    def metafields = {}
    def category = nil

    def options_with_values
      @p.product_options.sort_by(&:position).map do |o|
        BaseDrop.new("name" => o.name, "position" => o.position,
                     "values" => o.option_values.sort_by(&:position).map(&:value))
      end
    rescue StandardError
      []
    end

    def options = options_with_values.map { |o| o["name"] }
    def selected_or_first_available_selling_plan_allocation = nil

    # 🔴 specs/93 §D 紅線：Liquid `product` **沒有 `status` 屬性**（官方 44 屬性清單）。
    #   本 drop 刻意不定義它 ⇒ 落入 miss 遙測回 nil；後台語義不外洩到前台。
    def liquid_method_missing(name)
      ThemeEngine.count_miss("ProductDrop.#{name}")
      nil
    end
  end

  class CollectionDrop < Liquid::Drop
    def initialize(collection, url_prefix: "")
      super()
      @c = collection
      @url_prefix = url_prefix
    end

    def id = @c.id
    def title = @c.title
    def handle = @c.handle
    def description = @c.description_html
    def url = "#{@url_prefix}/collections/#{@c.handle}"

    def liquid_method_missing(name)
      ThemeEngine.count_miss("CollectionDrop.#{name}")
      nil
    end
  end

  class PageDrop < Liquid::Drop
    def initialize(page, url_prefix: "")
      super()
      @page = page
      @url_prefix = url_prefix
    end

    def id = @page.id
    def title = @page.title
    def handle = @page.handle
    def content = @page.body_html
    def url = "#{@url_prefix}/pages/#{@page.handle}"
    def published_at = @page.published_at&.iso8601

    def liquid_method_missing(name)
      ThemeEngine.count_miss("PageDrop.#{name}")
      nil
    end
  end

  class ShopDrop < Liquid::Drop
    def initialize(shop)
      super()
      @shop = shop
    end

    def id = @shop.id
    def name = @shop.name
    def currency = @shop.store_currency
    def domain = @shop.custom_domain.presence || "#{@shop.subdomain}.chilllove.example"
    def permanent_domain = "#{@shop.subdomain}.chilllove.example"
    def url = "https://#{domain}"
    def secure_url = url
    def email = nil
    def money_format = nil # 顯示格式由 locale 決定（鐵律 10）；money filter 走 registers
    def enabled_currencies = [ @shop.store_currency ]
    def published_locales = []
    def customer_accounts_enabled = false
    def customer_accounts_optional = true
    def metafields = {}
    def brand = nil
    def products_count = Product.where(shop_id: @shop.id).count
    def types = []
    def vendors = []

    def liquid_method_missing(name)
      ThemeEngine.count_miss("ShopDrop.#{name}")
      nil
    end
  end

  # 選單（linklists）——DB：menus／menu_items。
  class LinkDrop < Liquid::Drop
    def initialize(item, url_prefix: "")
      super()
      @item = item
      @url_prefix = url_prefix
    end

    def title = @item.title
    def type = @item.item_type

    def url
      case @item.item_type
      when "http" then @item.url
      when "product" then "#{@url_prefix}/products/#{resource_handle(Product)}"
      when "collection" then "#{@url_prefix}/collections/#{resource_handle(Collection)}"
      when "page" then "#{@url_prefix}/pages/#{resource_handle(Page)}"
      end
    end

    def links
      @links ||= @item.children.sort_by(&:position).map { |i| LinkDrop.new(i, url_prefix: @url_prefix) }
    end

    def child_active = false
    def active = false

    private

    def resource_handle(klass)
      klass.where(shop_id: @item.shop_id, id: @item.resource_id).pick(:handle)
    end
  end

  class LinkListDrop < Liquid::Drop
    def initialize(menu, url_prefix: "")
      super()
      @menu = menu
      @url_prefix = url_prefix
    end

    def title = @menu.title
    def handle = @menu.handle

    def links
      @links ||= @menu.menu_items.select { |i| i.parent_menu_item_id.nil? }
                      .sort_by(&:position)
                      .map { |i| LinkDrop.new(i, url_prefix: @url_prefix) }
    end

    def levels = 3
  end

  class LinkListsDrop < Liquid::Drop
    def initialize(shop, url_prefix: "")
      super()
      @shop = shop
      @url_prefix = url_prefix
    end

    def liquid_method_missing(name)
      menu = Menu.includes(:menu_items).find_by(shop_id: @shop.id, handle: name.to_s)
      return LinkListDrop.new(menu, url_prefix: @url_prefix) if menu

      ThemeEngine.count_miss("linklists.#{name}")
      nil
    end
  end

  # 🔴 反例②已修：路由帶前綴（B11 一次到位——包 33 傳真前綴；空字串＝無前綴）。
  class RoutesDrop < Liquid::Drop
    ROUTES = {
      "root_url" => "/", "cart_url" => "/cart", "cart_add_url" => "/cart/add",
      "cart_change_url" => "/cart/change", "cart_clear_url" => "/cart/clear",
      "cart_update_url" => "/cart/update", "product_recommendations_url" => "/recommendations/products",
      "predictive_search_url" => "/search/suggest", "search_url" => "/search",
      "all_products_collection_url" => "/collections/all", "collections_url" => "/collections",
      "blogs_url" => "/blogs", "account_url" => "/account", "account_login_url" => "/account/login",
      "account_logout_url" => "/account/logout", "account_register_url" => "/account/register",
      "account_addresses_url" => "/account/addresses", "account_recover_url" => "/account/recover",
      "storefront_login_url" => "/account/login"
    }.freeze

    def initialize(prefix: "")
      super()
      @prefix = prefix.to_s
    end

    def liquid_method_missing(name)
      base = ROUTES[name.to_s]
      if base.nil?
        ThemeEngine.count_miss("routes.#{name}")
        return nil
      end
      base == "/" ? (@prefix.empty? ? "/" : @prefix) : "#{@prefix}#{base}"
    end
  end

  # 🔴 反例③已修：locale／host 是真值參數。
  class RequestDrop < BaseDrop
    def initialize(page_type: "index", design_mode: false, locale: nil, host: nil, path: "/")
      super({ "design_mode" => design_mode, "visual_preview_mode" => false,
              "page_type" => page_type, "host" => host,
              "origin" => host ? "https://#{host}" : nil, "path" => path,
              "locale" => locale })
    end
  end

  class CartDrop < BaseDrop
    def initialize(currency:)
      super({ "item_count" => 0, "items" => [], "total_price" => 0,
              "items_subtotal_price" => 0, "original_total_price" => 0,
              "total_discount" => 0, "note" => nil, "attributes" => {},
              "currency" => { "iso_code" => currency },
              "cart_level_discount_applications" => [], "requires_shipping" => false,
              "taxes_included" => false, "discount_applications" => [] })
    end

    def empty? = true
  end

  # 🔴 反例①已修：語言資料由呼叫端供給（shop_locales；包 34 接真值鏈）。
  class LocalizationDrop < BaseDrop
    def initialize(language:, available_languages:, country: nil, market: nil)
      super({ "language" => language, "country" => country, "market" => market,
              "available_countries" => [ country ].compact,
              "available_languages" => available_languages })
    end
  end

  class TemplateDrop < BaseDrop
    def initialize(name)
      super({ "name" => name, "suffix" => nil, "directory" => nil })
    end

    def to_s = @attrs["name"]
  end

  class ColorDrop < Liquid::Drop
    def initialize(hex)
      super()
      @hex = hex.to_s
      m = @hex.match(/#?(\h\h)(\h\h)(\h\h)/)
      @r, @g, @b = m ? m.captures.map { |x| x.to_i(16) } : [ 0, 0, 0 ]
    end

    def red = @r
    def green = @g
    def blue = @b
    def alpha = 1.0
    def rgb = "#{@r} #{@g} #{@b}"
    def rgba = "#{@r} #{@g} #{@b} / 1.0"
    def hue = 0
    def saturation = 0
    def lightness = ((@r * 0.299 + @g * 0.587 + @b * 0.114) / 2.55).round
    def to_s = @hex
  end

  class FontDrop < BaseDrop
    def initialize(family: "Assistant", weight: 400, style: "normal")
      super({ "family" => family, "weight" => weight, "style" => style,
              "fallback_families" => "sans-serif", "baseline_ratio" => 0.1, "system?" => true })
    end

    def to_s = @attrs["family"]
  end

  class ClosestDrop < Liquid::Drop
    def initialize(product: nil, collection: nil, article: nil)
      super()
      @h = { "product" => product, "collection" => collection, "article" => article }
    end

    def liquid_method_missing(name)
      @h.fetch(name.to_s) do
        ThemeEngine.count_miss("closest.#{name}")
        nil
      end
    end
  end

  class PaginateDrop < BaseDrop
    def initialize(items: 0, page_size: 24)
      super({ "current_page" => 1, "current_offset" => 0, "items" => items,
              "parts" => [], "next" => nil, "previous" => nil,
              "page_size" => page_size, "pages" => 1, "page_param" => "page" })
    end
  end

  class FormDrop < BaseDrop
    def initialize
      super({ "errors" => nil, "posted_successfully?" => true, "id" => "cl-form" })
    end
  end

  # settings（schema 型別感知強轉；25 坑 #6——color 必須是 color 物件）。
  class SettingsDrop < Liquid::Drop
    def initialize(values, types = {}, label: "settings")
      super()
      @v, @t, @label = values || {}, types, label
    end

    def liquid_method_missing(name)
      k = name.to_s
      unless @v.key?(k)
        ThemeEngine.count_miss("#{@label}.#{k}")
        return nil
      end
      coerce(k, @v[k])
    end

    private

    def coerce(key, val)
      case @t[key]
      when "color", "color_background"
        return nil if val.nil? || val == ""

        val.to_s.start_with?("#") ? ColorDrop.new(val) : val
      when "image_picker"
        val.nil? || val == "" ? nil : PlaceholderImageDrop.new(label: File.basename(val.to_s), w: 1200, h: 800)
      when "font_picker" then FontDrop.new(family: val.to_s.split("_").first.to_s.capitalize)
      else val
      end
    end
  end

  class BlockDrop < Liquid::Drop
    attr_reader :id, :type, :settings_hash, :data

    def initialize(id:, type:, settings:, types:, data:, design_mode: false)
      super()
      @id, @type, @data = id, type, data
      @settings_hash = settings
      @settings = SettingsDrop.new(settings, types, label: "block(#{type})")
      @design_mode = design_mode
    end

    def settings = @settings

    def shopify_attributes
      return "" unless @design_mode

      %(data-shopify-editor-block='#{JSON.generate(id: @id, type: @type)}')
    end

    def to_s = ""
  end

  class SectionDrop < Liquid::Drop
    attr_reader :id

    def initialize(id:, data:, types:, blocks: [])
      super()
      @id, @data = id, data
      @settings = SettingsDrop.new(data["settings"] || {}, types, label: "section(#{data['type']})")
      @blocks = blocks
    end

    def settings = @settings
    def blocks = @blocks
    def index = nil
    def index0 = nil
    def location = "template"

    def liquid_method_missing(name)
      ThemeEngine.count_miss("section.#{name}")
      nil
    end
  end
end
