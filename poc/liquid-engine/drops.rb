# frozen_string_literal: true
# CHILL LOVE PoC — 平台層 drops（對照 docs/research/26 §1；全部走 nil-stub 兜底＋miss 遙測）

require "json"
require "cgi"

module ChillLove
  MISSES = Hash.new(0) # "drop.attr" => count（相容性遙測，25 號 §7）

  class BaseDrop < Liquid::Drop
    def initialize(attrs = {}) = @attrs = attrs
    def liquid_method_missing(name)
      k = name.to_s
      MISSES["#{self.class.name.split('::').last}.#{k}"] += 1 unless @attrs.key?(k) # 只記真缺
      @attrs[k]
    end
  end

  # ---- 資源 drops -----------------------------------------------------------
  class ImageDrop < BaseDrop
    attr_reader :width, :height, :alt
    def initialize(label:, w: 900, h: 1200, color: "#e8ded2", fg: "#a9502c")
      super()
      @label, @width, @height, @alt = label, w, h, label
      @color, @fg = color, fg
    end
    def aspect_ratio = @width.to_f / @height
    def src = url
    def id = 1
    def url
      svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}"><rect width="100%" height="100%" fill="#{@color}"/><circle cx="50%" cy="42%" r="18%" fill="#{@fg}" opacity=".25"/><text x="50%" y="88%" font-family="Georgia" font-size="#{@width / 18}" fill="#{@fg}" text-anchor="middle">#{CGI.escapeHTML(@label)}</text></svg>)
      "data:image/svg+xml;utf8,#{svg.gsub('#', '%23').gsub('"', "'")}"
    end
    def to_s = url
    def preview_image = self
    def media_type = "image"
    def position = 1
    def attached_to_variant? = false
  end

  class VariantDrop < BaseDrop
    def initialize(product, attrs)
      super(attrs)
      @product = product
    end
    def product = @product
    def featured_image = @product.featured_image
    def featured_media = @product.featured_image
    def image = @product.featured_image
    def unit_price = nil
    def unit_price_measurement = nil
    def selected_selling_plan_allocation = nil
    def quantity_price_breaks = []
    def quantity_rule = { "min" => 1, "max" => nil, "increment" => 1 }
    def matched = true
  end

  class ProductOptionDrop < BaseDrop; end

  class ProductDrop < BaseDrop
    def initialize(attrs)
      super
      imgs = attrs["images"] || []
      @images = imgs
      @variants = (attrs["variants"] || []).map { |v| VariantDrop.new(self, v) }
    end
    def images = @images
    def media = @images
    def featured_image = @images.first
    def featured_media = @images.first
    def variants = @variants
    def selected_or_first_available_variant = @variants.first
    def first_available_variant = @variants.first
    def selected_variant = nil
    def has_only_default_variant = @attrs.fetch("has_only_default_variant", false)
    def options_with_values
      (@attrs["options_with_values"] || []).map { |o| ProductOptionDrop.new(o) }
    end
    def options = options_with_values.map { |o| o["name"] }
    def options_by_name = {}
    def price_varies = price_min != price_max
    def price = @attrs["price"]
    def price_min = @attrs.fetch("price_min", price)
    def price_max = @attrs.fetch("price_max", price)
    def compare_at_price = @attrs["compare_at_price"]
    def compare_at_price_min = compare_at_price
    def compare_at_price_max = compare_at_price
    def compare_at_price_varies = false
    def available = true
    def gift_card? = false
    def requires_selling_plan = false
    def selling_plan_groups = []
    def quantity_price_breaks_configured? = false
    def tags = @attrs.fetch("tags", [])
    def collections = []
    def metafields = {}
    def category = nil
    def content = @attrs["description"]
    def description = @attrs["description"]
    def selected_or_first_available_selling_plan_allocation = nil
    def url = "/products/#{@attrs['handle']}"
    def media_count = @images.size
  end

  # ---- 全域 drops -----------------------------------------------------------
  class ShopDrop < BaseDrop
    def initialize = super({
      "name" => "CHILL LOVE", "email" => "hi@chill.deals", "url" => "",
      "secure_url" => "", "domain" => "chill.deals", "permanent_domain" => "chill-love.myshopify.com",
      "currency" => "USD", "money_format" => "${{amount}}",
      "money_with_currency_format" => "${{amount}} USD",
      "enabled_currencies" => [], "published_locales" => [],
      "customer_accounts_enabled" => false, "customer_accounts_optional" => true,
      "metafields" => {}, "brand" => nil, "id" => 1,
    })
    def products_count = 4
    def types = []
    def vendors = ["CHILL LOVE"]
  end

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
      "storefront_login_url" => "/account/login",
    }.freeze
    def liquid_method_missing(name) = ROUTES.fetch(name.to_s) { ChillLove::MISSES["routes.#{name}"] += 1; nil }
  end

  class RequestDrop < BaseDrop
    def initialize(page_type: "index", design_mode: false)
      super({ "design_mode" => design_mode, "visual_preview_mode" => false,
              "page_type" => page_type, "host" => "chill.deals",
              "origin" => "https://chill.deals", "path" => "/", "locale" => nil })
    end
  end

  class CartDrop < BaseDrop
    def initialize = super({ "item_count" => 0, "items" => [], "total_price" => 0,
                             "items_subtotal_price" => 0, "original_total_price" => 0,
                             "total_discount" => 0, "note" => nil, "attributes" => {},
                             "empty?" => true, "currency" => { "iso_code" => "USD" },
                             "cart_level_discount_applications" => [], "requires_shipping" => false,
                             "taxes_included" => false, "discount_applications" => [] })
    def empty? = true
  end

  class CountryDrop < BaseDrop
    def initialize = super({ "iso_code" => "US", "name" => "United States",
                             "currency" => { "iso_code" => "USD", "symbol" => "$" },
                             "unit_system" => "imperial", "market" => nil })
  end

  class LocalizationDrop < BaseDrop
    def initialize = super({
      "language" => { "iso_code" => "en", "endonym_name" => "English", "root_url" => "/" },
      "country" => CountryDrop.new,
      "market" => { "handle" => "us", "id" => 1 },
      "available_countries" => [CountryDrop.new],
      "available_languages" => [{ "iso_code" => "en", "endonym_name" => "English", "root_url" => "/" }],
    })
  end

  class TemplateDrop < BaseDrop
    def initialize(name) = super({ "name" => name, "suffix" => nil, "directory" => nil })
    def to_s = @attrs["name"]
  end

  class ColorDrop < Liquid::Drop
    def initialize(hex)
      @hex = hex.to_s
      m = @hex.match(/#?(\h\h)(\h\h)(\h\h)/)
      @r, @g, @b = m ? m.captures.map { |x| x.to_i(16) } : [0, 0, 0]
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
      @h = { "product" => product, "collection" => collection, "article" => article }
    end
    def liquid_method_missing(name)
      @h.fetch(name.to_s) { ChillLove::MISSES["closest.#{name}"] += 1; nil }
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
    def initialize = super({ "errors" => nil, "posted_successfully?" => true, "id" => "poc-form" })
  end

  # ---- settings（schema 型別感知）-------------------------------------------
  class SettingsDrop < Liquid::Drop
    # values: 實例值；types: setting_id => schema type（值型別強轉，25 號坑 #6）
    def initialize(values, types = {}, label: "settings")
      @v, @t, @label = values || {}, types, label
    end
    def liquid_method_missing(name)
      k = name.to_s
      unless @v.key?(k)
        ChillLove::MISSES["#{@label}.#{k}"] += 1
        return nil
      end
      coerce(k, @v[k])
    end
    private
    def coerce(key, val)
      case @t[key]
      when "color", "color_background"
        return nil if val.nil? || val == ""
        val.to_s.start_with?("#") ? ColorDrop.new(val) : val # 漸層字串保持原樣
      when "image_picker"
        val.nil? || val == "" ? nil : ImageDrop.new(label: File.basename(val.to_s), w: 1200, h: 800)
      when "font_picker" then FontDrop.new(family: val.to_s.split("_").first.to_s.capitalize)
      when "product" then val # 已由動態來源 resolver 換成 ProductDrop 或保持 handle 字串
      when "link_list", "collection", "collection_list", "product_list", "page", "blog", "article", "video"
        val
      else val
      end
    end
  end

  # ---- section / block ------------------------------------------------------
  class BlockDrop < Liquid::Drop
    attr_reader :id, :type, :settings_hash, :data
    def initialize(id:, type:, settings:, types:, data:, design_mode: false)
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
      @id, @data = id, data
      @settings = SettingsDrop.new(data["settings"] || {}, types, label: "section(#{data['type']})")
      @blocks = blocks
    end
    def settings = @settings
    def blocks = @blocks
    def index = nil        # 編輯器/SRA 語義（27 §6.4）
    def index0 = nil
    def location = "template"
    def liquid_method_missing(name)
      ChillLove::MISSES["section.#{name}"] += 1
      nil
    end
  end
end
