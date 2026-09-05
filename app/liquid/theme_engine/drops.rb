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

    # T14：佔位圖無焦點 ⇒ 官方預設 50／50
    def presentation = ImagePresentationDrop.new(nil)

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
  # 直接包 StoredFile 的 image drop（settings image_picker 命中檔案庫時用；
  # Ella 修復 PR-2）。與 ImageDrop 同介面（本尊 image 物件子集）。
  class FileImageDrop < Liquid::Drop
    def initialize(stored_file)
      super()
      @file = stored_file
    end

    def id = @file.id
    def alt = @file.alt_text

    # PR-14：官方 image 物件 width/height 恆 number；nil＝資料層不變量被繞過
    # （StoredFile 驗證＋BackfillDimensions 之後不應再現）——遙測不改契約。
    def width
      ThemeEngine.count_miss("image.width_nil") if @file.width.nil?
      @file.width
    end

    def height
      ThemeEngine.count_miss("image.height_nil") if @file.height.nil?
      @file.height
    end
    def aspect_ratio = width && height && height.positive? ? width.to_f / height : nil
    def media_type = "image"
    def src = url
    def url = MediaUrl.for(@file)
    def to_s = url.to_s
    def presentation = ImagePresentationDrop.new(@file&.focal_point) # T14
    def preview_image = self
  end

  # PR-22：external_video media 的 Liquid 面（官方 media 物件依 media_type
  # 分派；external_video 帶 host/external_id——PR-16 的 external_video_url/tag
  # duck-type 直接吃）。preview_image：資料面無縮圖 ⇒ nil（主題
  # `media.preview_image.aspect_ratio | default: 1.0` 形對 nil 寬容）。
  class ExternalVideoMediaDrop < Liquid::Drop
    def initialize(media)
      super()
      @m = media
    end

    def id = @m.id
    def media_type = "external_video"
    def host = @m.external_host
    def external_id = @m.external_id
    def alt = @m.alt_text
    def position = @m.position
    def aspect_ratio = nil

    # E12：官方 objects/media 逐字 "A preview image of the media."（preview image 無 id；取證 2026-09-04）；本尊外部影片在
    # 商家貼上 URL 時抓供應商縮圖存成 preview image。我方無下載線 ⇒ YouTube 以供應商公開縮圖 URL（hqdefault 480×360）
    # 代位；Vimeo 需 oEmbed（未做 ⇒ nil ⇒ `image_url` 回 Liquid 錯誤「invalid url input」，與本尊無縮圖時同形；V，91 §3.79）。
    # 沒有這層，Ella 商品圖庫對影片的 `media.preview_image | image_url` 會印錯誤文字（真主題回歸規格 EG1）。
    def preview_image
      return nil unless @m.external_host.to_s == "youtube" && @m.external_id.present?

      @preview_image ||= ExternalPreviewImageDrop.new(
        url: "https://i.ytimg.com/vi/#{@m.external_id}/hqdefault.jpg", width: 480, height: 360, alt: @m.alt_text)
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("ExternalVideoMediaDrop.#{name}")
      nil
    end
  end

  # 外部影片的供應商縮圖（無 id、無 StoredFile；`image_url` 直出 URL、不加尺寸參數）。
  class ExternalPreviewImageDrop < Liquid::Drop
    def initialize(url:, width:, height:, alt: nil)
      super()
      @url, @width, @height, @alt = url, width, height, alt
    end

    attr_reader :url, :width, :height, :alt
    def src = @url
    def aspect_ratio = @width.to_f / @height
    def media_type = "image"
    def preview_image = self
    def to_s = @url
  end

  # T14 官方 objects/address（取證 2026-09-05）：address1／address2／city／company／country／country_code／first_name／id／
  # last_name／name（"A combination of the first and last names of the address."）／phone／province／province_code／
  # street（"A combination of the first and second lines of the address."）／summary／url／zip。
  # 我方來源＝`locations.address` JSON（admin 地點設定面未做 ⇒ 多為空，91 §3.91 V）。
  # country 官方回 country 物件；我方回字串（country 物件＝Markets 線，登記）。
  class AddressDrop < Liquid::Drop
    def initialize(attrs = {})
      super()
      @a = (attrs || {}).transform_keys(&:to_s)
    end

    def id = @a["id"]
    def address1 = @a["address1"]
    def address2 = @a["address2"]
    def city = @a["city"]
    def company = @a["company"]
    def country = @a["country"]
    def country_code = @a["country_code"]
    def first_name = @a["first_name"]
    def last_name = @a["last_name"]
    def phone = @a["phone"]
    def province = @a["province"]
    def province_code = @a["province_code"]
    def zip = @a["zip"]
    def name = [ first_name, last_name ].compact_blank.join(" ").presence
    def street = [ address1, address2 ].compact_blank.join(", ").presence
    def summary = [ name, street, city, province, country ].compact_blank.join(", ").presence
    def url = @a["url"]
    def to_h = @a
    def to_s = summary.to_s
  end

  # T14 官方 objects/location（取證 2026-09-05）："A store location."；"This object is only available when one or more
  # locations have local pickup enabled."——address／id／latitude／longitude／metafields／name。
  # latitude／longitude 官方 "Returns `nil` if the address isn't verified"；我方無地址驗證 ⇒ 一律 nil（91 §3.91 V）。
  class LocationDrop < Liquid::Drop
    def initialize(location)
      super()
      @l = location
    end

    def id = @l.id
    def name = @l.name
    def address = AddressDrop.new(@l.address)
    def latitude = nil
    def longitude = nil
    def metafields = {}
    def to_s = @l.name.to_s
  end

  # T14 官方 objects/store_availability（取證 2026-09-05）："A variant's inventory information for a physical store location."
  # ——available（"Returns `true` if the variant has available inventory at the location."）／location／
  # pick_up_enabled（"Returns `true` if the location has pickup enabled."）／pick_up_time（"The amount of time that it takes
  # for pickup orders to be ready at the location."）。三套主題（Ella／Kalles／Minimog 的 pickup-availability）都讀這四個。
  class StoreAvailabilityDrop < Liquid::Drop
    def initialize(location:, available:)
      super()
      @l = location
      @available = available
    end

    def available = @available
    def location = LocationDrop.new(@l)
    def pick_up_enabled = @l.pick_up_enabled
    def pick_up_time = @l.pick_up_time
  end

  # T14 官方 objects/focal_point（取證 2026-09-05）："The focal point for an image. The focal point will remain visible when
  # the image is cropped by the theme."——x／y＝百分比（"as a percent of the image width"／height），
  # "Returns `50` if no focal point is set"；直接輸出形＝`X% Y%`（官方例 `1.9231% 9.7917%`）。
  class FocalPointDrop < Liquid::Drop
    def initialize(point = nil)
      super()
      @p = (point || {}).transform_keys(&:to_s)
    end

    def x = numeric("x")
    def y = numeric("y")
    def to_s = "#{x}% #{y}%"

    def numeric(key)
      v = @p[key]
      return 50 if v.nil? # 官方預設

      f = v.to_f
      f == f.round ? f.to_i : f
    end
    private :numeric
  end

  # T14 官方 objects/image_presentation："The presentation settings for an image."——屬性只有 focal_point。
  class ImagePresentationDrop < Liquid::Drop
    def initialize(point = nil)
      super()
      @p = point
    end

    def focal_point = FocalPointDrop.new(@p)
  end

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
    # Ella 修復 PR-2：接買家面媒體端點（先前恆 nil＝0 <img> 根因 A）。
    def url = MediaUrl.for(@file)
    def to_s = url.to_s
    def presentation = ImagePresentationDrop.new(@file&.focal_point) # T14
    def preview_image = self

    # 🔴 ours：live「帶圖商品」的 image-json 形未量測（測試品全無圖）——
    # 先出我方真欄位，探針補量後對表（資料出口包 worklog 登記）。
    def as_storefront_json
      { "id" => id, "position" => position, "alt" => alt, "width" => width,
        "height" => height, "aspect_ratio" => aspect_ratio, "src" => url }
    end
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
    def barcode = @v.barcode
    def price = @v.price_cents
    def compare_at_price = @v.compare_at_price_cents

    # T14 官方 objects/variant#store_availabilities（取證 2026-09-05）：array of store_availability；
    # 🔴 "The array is defined in only the following cases:" —— `variant.selected` 為 true，或該變體是商品的
    # first available variant ⇒ 其餘變體回 nil（本尊對其餘變體的實際回傳未觀測，91 §3.91 V）。
    # 集合＝本店 `pick_up_enabled` 的 active 地點（官方：location 物件只在有地點開啟取貨時可用），
    # 逐地點以該地點可售量判 available；未追蹤庫存 ⇒ 恆 true（同 `available` 的判準）。
    def store_availabilities
      # 🔴 整段在租戶語境內：first_available_variant（讀 available ⇒ inventory_item）、locations 與 inventory_levels
      # （只包 locations 那一段 ⇒ 後面讀 inventory_item 就 NoTenantSet；規格 PU2／PU3 是這個殺手格）。
      ActsAsTenant.with_tenant(@v.shop) do
        next nil unless selected || @product.first_available_variant&.id == id

        locations = Location.where(shop_id: @v.shop_id).pickup_enabled.order(:priority, :id).to_a
        next [] if locations.empty?

        item = @v.inventory_item
        untracked = item.nil? || !item.tracked
        levels = item ? item.inventory_levels.index_by(&:location_id) : {}
        locations.map do |loc|
          here = untracked || levels[loc.id]&.available.to_i.positive?
          StoreAvailabilityDrop.new(location: loc, available: here)
        end
      end
    end

    # 缺口分析 A1（docs/plans/2026-08-30-商品模塊-Liquid對接缺口分析.md）：
    # 售罄感知。判準（本尊語義，13 §F1 同軸）：未追蹤 ⇒ 恆可購；追蹤 ⇒
    # 可售量 > 0 ∨ inventory_policy=continue（缺貨續賣）。
    # inventory_item 由變體 after_create 保證存在；nil 防衛＝未追蹤同義。
    def available
      item = @v.inventory_item
      return true if item.nil? || !item.tracked

      inventory_quantity.positive? || @v.inventory_policy == "continue"
    end

    # A′1：跨地點合計可售量（inventory_levels 需已 preload——PageRenderer 負責；
    # 未載入時退化為單筆查詢的 sum 也正確，只是多一次 IO）。
    def inventory_quantity
      # 63 §D.5：volatile 欄位——讀到即註冊旗標，頁級快取把該頁 TTL 壓到
      # volatile_section_ttl_seconds 兜底（價格類走 key-based、數量類走 TTL）。
      # 在 drop 裡註冊而非人工標 section：主題是第三方的，這是唯一能自動偵測的位置。
      @context&.registers&.[](:render_flags)&.add(:volatile)
      item = @v.inventory_item
      return 0 if item.nil?

      item.inventory_levels.sum(&:available)
    end

    # 🔴 值刻意用字串 "shopify"：主題 JS 硬編碼比對這個字串（Ella
    # edit-cart.js:137 讀 currentVariant.inventory_management；83 §4 取證）——
    # 這是相容層契約，不是「照抄品牌名」。未追蹤 ⇒ nil（本尊同形）。
    def inventory_management
      item = @v.inventory_item
      item&.tracked ? "shopify" : nil
    end

    def inventory_policy = @v.inventory_policy

    # 選項值走 join（product_variant_option_values → option_values）；無 option1..3 欄。
    def options
      @options ||= begin
        vals = @v.option_values.sort_by { |ov| ov.product_option_id }.map(&:value)
        # E8b：無選項商品的預設變體 options＝["Default Title"]（hoko.vip 集合頁 `data-json-product` 變體 JSON
        # `&quot;options&quot;:[&quot;Default Title&quot;]`；先前 [] ⇒ `"options":[]`）。
        vals.empty? ? [ "Default Title" ] : vals
      rescue StandardError
        []
      end
    end

    # E8b：無選項商品的預設變體 option1＝"Default Title"（hoko.vip 商品頁 `data-subtotal-variants` JSON `"option1":"Default Title"`）——
    # 由 `options` 的 ["Default Title"] 形直接取得（突變 M129 證實原本的 empty? 分支在 #61 之後不可達，已移除）。
    def option1 = options[0]
    def option2 = options[1]
    def option3 = options[2]
    # A′2：變體專圖（media.product_variant_id）優先，無則回退商品首圖。
    # E8b：無專圖 ⇒ 退商品**真實**首圖，商品無圖 ⇒ nil（hoko.vip 商品頁 `data-product-variant-media=""`；先前退佔位 drop ⇒ 印 data: svg）。
    def featured_image = own_image || @product.images.first
    def featured_media = featured_image
    def image = featured_image
    def requires_shipping = @v.requires_shipping
    def taxable = @v.taxable
    # Liquid 契約：variant.weight 單位＝公克（我方儲存同尺度，免換算）。
    def weight = @v.weight_grams
    # 真引擎預設顯示單位＝"kg"（83 §12 探針）；我方不存單位 ⇒ 常數（ours）。
    def weight_unit = "kg"
    def url = "#{@product.url}?variant=#{@v.id}"
    def selected = @product.selected_variant_id == @v.id
    def unit_price = nil
    def unit_price_measurement = nil
    def selected_selling_plan_allocation = nil
    def requires_selling_plan = false
    def selling_plan_allocations = []
    def quantity_price_breaks = []
    def quantity_rule = { "min" => 1, "max" => nil, "increment" => 1 }
    def matched = true

    # 真引擎拼裝規則（83 §12：live payload）：預設變體 name＝商品名、
    # public_title＝nil；具名變體 name＝"商品名 - 變體名"、public_title＝變體名。
    def name
      default_variant? ? @product.title : "#{@product.title} - #{@v.title}"
    end

    def public_title
      default_variant? ? nil : @v.title
    end

    # 真引擎 variant json＝21 鍵（83 §12.2：🔴 **無 quantity_price_breaks**，
    # 與 drop 面回 [] 不同——序列化面刻意排除該鍵）。
    # E17 複驗（hoko.vip 2026-09-05 集合頁商品卡 `data-json-product='{{ … | json }}'`）：Liquid `variant | json` 仍是這 21 鍵、此序；
    # `/products/{handle}.js` 端點的變體是**另一形**（22 鍵、含 quantity_price_breaks、序不同）⇒ `Storefront::ProductAjaxJson`。
    def as_storefront_json
      {
        "id" => id, "title" => title, "option1" => option1, "option2" => option2,
        "option3" => option3, "sku" => sku, "requires_shipping" => requires_shipping,
        "taxable" => taxable, "featured_image" => own_image_json, "available" => available,
        "name" => name, "public_title" => public_title, "options" => options,
        "price" => price, "weight" => weight, "compare_at_price" => compare_at_price,
        "inventory_management" => inventory_management, "barcode" => barcode,
        "requires_selling_plan" => requires_selling_plan,
        "selling_plan_allocations" => selling_plan_allocations,
        "quantity_rule" => quantity_rule
      }
    end

    # @api private（A3 的分組鍵；不是 Liquid 面）
    def option_value_ids
      @option_value_ids ||= if @v.association(:product_variant_option_values).loaded?
        @v.product_variant_option_values.map(&:option_value_id)
      else
        @v.product_variant_option_values.pluck(:option_value_id)
      end
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("VariantDrop.#{name}")
      nil
    end

    private

    def default_variant? = @product.has_only_default_variant

    # json 面的變體圖：只認變體專圖（無 ⇒ null；不回退商品首圖——live .js 同形）。
    def own_image_json
      img = own_image
      img && JsonSerializer.coerce(img.as_storefront_json)
    end

    def own_image
      return @own_image if defined?(@own_image)

      @own_image = if @v.association(:media).loaded?
        m = @v.media.select(&:stored_file).min_by(&:position)
        m && ImageDrop.new(m)
      end
    end
  end

  # 商品分類 drop（A′7；docs 26 taxonomy_category T2）。
  # 真引擎（83 §12.4）：to_s＝名稱、`| json`＝名稱字串、.id＝路徑碼
  # （"aa-1-13-8"）、.gid＝完整 GID。我方只存 category_gid ⇒ id/gid 可導出；
  # 🔴 name＝nil（taxonomy 名稱字典未落庫——平台字典表候選，鐵律 2 ③ 程序）。
  class CategoryDrop < Liquid::Drop
    GID_PREFIX = "gid://shopify/TaxonomyCategory/"

    def initialize(gid)
      super()
      @gid = gid
    end

    def gid = @gid
    def id = @gid.to_s.delete_prefix(GID_PREFIX)
    def name = nil
    def to_s = name.to_s

    def as_storefront_json = name

    def liquid_method_missing(name)
      ThemeEngine.count_miss("CategoryDrop.#{name}")
      nil
    end
  end

  # 單一 metafield drop（A′6；docs 26 §1.8：`.metafields.namespace.key`）。
  # 真引擎（83 §12.4）：直接輸出＝值、.value＝值、.type＝definition 型別、
  # 🔴 `| json` 拒絕（json_refused）。
  class MetafieldDrop < Liquid::Drop
    def initialize(row)
      super()
      @row = row
    end

    def value = @row.value
    def type = @row.metafield_definition.value_type
    def to_s = @row.value.to_s
    def json_refused? = true

    def liquid_method_missing(name)
      ThemeEngine.count_miss("MetafieldDrop.#{name}")
      nil
    end
  end

  # namespace 層（真引擎：`| json`＝扁平 {key: value}；未知 key ⇒ nil 鏈安全）。
  class MetafieldNamespaceDrop < Liquid::Drop
    def initialize(owner, namespace)
      super()
      @owner = owner
      @namespace = namespace.to_s
    end

    def liquid_method_missing(key)
      rows[key.to_s]&.then { |row| MetafieldDrop.new(row) }
    end

    def as_storefront_json
      rows.transform_values(&:value)
    end

    private

    def rows
      @rows ||= Metafield
                .where(shop_id: @owner.shop_id, owner_type: @owner.class.name, owner_id: @owner.id)
                .joins(:metafield_definition)
                .where(metafield_definitions: { namespace: @namespace })
                .includes(:metafield_definition)
                .index_by { |m| m.metafield_definition.key }
    end
  end

  # metafields 根（真引擎：任意 namespace 存取恆回 namespace drop；
  # 🔴 root `| json` 拒絕、不可迭代——83 §12.4）。
  class MetafieldsRootDrop < Liquid::Drop
    def initialize(owner)
      super()
      @owner = owner
    end

    def json_refused? = true

    def liquid_method_missing(namespace)
      MetafieldNamespaceDrop.new(@owner, namespace)
    end
  end

  # 選項 drop（缺口分析 A3；docs 26 §1 product_option T0 面）。
  class ProductOptionDrop < Liquid::Drop
    def initialize(option, product_drop)
      super()
      @o = option
      @product = product_drop
    end

    def name = @o.name
    def position = @o.position
    def to_s = @o.name

    def values
      @values ||= @o.option_values.sort_by(&:position).map { |ov| OptionValueDrop.new(ov, @product) }
    end

    # 真引擎 json 形（83 §12.4）：{name, position, values:[字串]}——值壓平。
    def as_storefront_json
      { "name" => name, "position" => position, "values" => values.map(&:to_s) }
    end

    # 官方 T0：目前選中變體在本選項上的值（字串）；無可用變體 ⇒ nil。
    def selected_value
      current = @product.selected_or_first_available_variant
      return nil if current.nil?

      values.find { |v| current.option_value_ids.include?(v.id) }&.to_s
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("ProductOptionDrop.#{name}")
      nil
    end
  end

  # 選項值 drop（A3；docs 26 §1 product_option_value T0 面：id/name/available/
  # selected/swatch/variant/product_url）。
  # 🔴 Ella 消費形（fixture product-variant-options.liquid:25-66 實測）：
  #   `value.available`（售罄劃線）、`color == value`（跨陣列比較）、
  #   `{{ value | handle }}`（字串濾鏡）、`value.variant`／`value.id`／
  #   `value.product_url`（swatch 導航 dataset）。== 因此按值語義覆寫。
  class OptionValueDrop < Liquid::Drop
    def initialize(option_value, product_drop)
      super()
      @ov = option_value
      @product = product_drop
    end

    def id = @ov.id
    def name = @ov.value
    def to_s = @ov.value

    # 本值參與的變體中任一可購 ⇒ 可選（售罄劃線的判準）。
    def available = matching_variants.any?(&:available)

    def selected
      current = @product.selected_or_first_available_variant
      current ? current.option_value_ids.include?(@ov.id) : false
    end

    # 代表變體＝首個可購命中者，全售罄退首命中（swatch 點擊導航目標）。
    def variant = matching_variants.find(&:available) || matching_variants.first

    # ours：本尊 product_url 服務 combined listings（跨商品導航）；我方無該
    # 功能 ⇒ 回本商品＋代表變體參數（Ella 只把它塞進 data-product-url）。
    def product_url
      v = variant
      v ? v.url : @product.url
    end

    def swatch = nil # 無 swatch 存儲（缺口分析 §B 登記）

    def as_storefront_json = @ov.value

    # Liquid `==`：drop == drop（同值 id）與 drop == "字串"（值字串）都成立。
    def ==(other)
      case other
      when OptionValueDrop then id == other.id
      when String then @ov.value == other
      else super
      end
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("OptionValueDrop.#{name}")
      nil
    end

    private

    def matching_variants = @product.variants_by_value_id[@ov.id]
  end

  # DB-backed 商品 drop（白名單委派；輸入＝已 preload 關聯的 Product）。
  class ProductDrop < Liquid::Drop
    # 官方（input-settings）：資源型 setting 直接輸出時回物件的 handle（backwards compatibility）
    def to_s = handle.to_s

    # @param selected_variant_id [Integer, nil] `?variant=` URL 參數（缺口分析 A2）；
    #   nil＝無選中（selected_variant 回 nil、selected_or_first… 走 first available）。
    # @param publication [Publication, nil] 渲染管道（A′5 collections 過濾與
    #   published_at 的上下文）；nil＝無管道語境（collections 回空、published_at nil）。
    attr_reader :selected_variant_id

    # @param translations [Hash] 內容翻譯 overlay（包 34；67 §F.3(c) 走 drops 不走 t）：
    #   field_key => 譯文，由 PageRenderer 以 Translations::Resolve **一次批載**。
    #   空 hash＝來源語言／無譯文 ⇒ 直讀 base row。handle 不在值域（不可翻，§D.3）。
    # url_params：搜尋結果脈絡的歸因參數（E17；`?_pos=…&_sid=…&_ss=r`），只有 SearchResultsDrop 傳。
    def initialize(product, url_prefix: "", selected_variant_id: nil, publication: nil,
                   translations: {}, url_params: "")
      @selected_variant_id = selected_variant_id
      @publication = publication
      super()
      @p = product
      @url_prefix = url_prefix
      @tx = translations || {}
      @url_params = url_params.to_s
    end

    def id = @p.id
    def title = @tx["title"] || @p.title
    def handle = @p.handle
    # 96 §3.1 官方："Search results have an additional `object_type` property"
    def object_type = "product"
    def vendor = @p.vendor
    def type = @p.product_type
    def tags = @p.tags.to_a
    def description = @tx["body_html"] || @p.description_html
    def content = description
    def url = "#{@url_prefix}/products/#{@p.handle}#{@url_params}"

    # Liquid 契約：variants 依 position 排序（association 預設是 id 序——
    # E10 抓到的真缺口；GraphQL 面的 keyset 同樣以 position 為第一鍵）。
    def variants
      @variants ||= @p.product_variants.sort_by(&:position).map { |v| VariantDrop.new(v, self) }
    end

    # A2：官方語義＝選中變體 → 首個可購變體；全售罄 fallback 首變體
    # （🔴 全售罄格的本尊行為未逐字取證——ours，缺口分析 §D 登記，CLI 探針後對表）。
    def selected_or_first_available_variant
      selected_variant || first_available_variant || variants.first
    end

    def first_available_variant = variants.find(&:available)

    def selected_variant
      @selected_variant_id && variants.find { |v| v.id == @selected_variant_id }
    end
    def has_only_default_variant = variants.size <= 1

    def images
      @images ||= if @p.respond_to?(:media) && @p.association(:media).loaded?
        @p.media.filter_map { |m| ImageDrop.new(m) if m.stored_file }
      else
        []
      end
    end

    # PR-22 官方語義：media＝全部媒體依 position 排序（image＋external_video）；
    # images 照舊只出圖片（官方 images 屬性本就是圖片子集）。
    def media
      @media_all ||= begin
        vids = if @p.respond_to?(:media) && @p.association(:media).loaded?
          @p.media.filter_map { |m| ExternalVideoMediaDrop.new(m) if m.external_video? }
        else
          []
        end
        (images + vids).sort_by { |m| [ m.position || 0, m.id || 0 ] }
      end
    end

    def media_count = media.size
    # E8b：無圖 ⇒ nil（官方 featured_image＝"The first (featured) image attached to the product."；hoko.vip /collections/all 三張真商品卡
    # `{% if card_product.featured_media %} card--media{% else %} card--text{% endif %}` 皆 `card--text`、商品頁 `data-product-variant-media=""`）。
    # 先前退 PlaceholderImageDrop ⇒ 卡片 `card--media`＋data: svg（E8 §3.75 登記的缺口）。首頁 onboarding 佔位卡走 placeholder_svg_tag，不受影響。
    def featured_image = images.first
    def featured_media = featured_image

    def price = variants.filter_map(&:price).min || 0
    def price_min = price
    def price_max = variants.filter_map(&:price).max || 0
    def price_varies = price_min != price_max
    def compare_at_price = variants.filter_map(&:compare_at_price).min
    # 真引擎實測（83 §12 CLI 探針，2026-08-30）：全變體無 compare_at 時
    # min/max 輸出 0（不是空）——0 fallback 是量測值不是猜測。
    def compare_at_price_min = variants.filter_map(&:compare_at_price).min || 0
    def compare_at_price_max = variants.filter_map(&:compare_at_price).max || 0
    def compare_at_price_varies = compare_at_price_min != compare_at_price_max
    # A1：任一變體可購 ⇒ 商品可購（無變體＝資料層不變量違反，回 false 安全側）。
    def available = variants.any?(&:available)
    def gift_card? = false
    def requires_selling_plan = false
    def selling_plan_groups = []
    def quantity_price_breaks_configured? = false

    # A′5：物化成員（collection_memberships）∩ 渲染管道已發布系列。
    # 真引擎格（83 §12.4）：🔴 未發布到本管道的系列**不出現**（S9-Col-Hidden
    # 排除格，成員已存仍被濾掉）。無管道語境 ⇒ 空陣列（安全側）。
    def collections
      @collections ||= if @publication.nil?
        []
      else
        # E17：手動系列的成員只在 `collection_products`（模型檔頭：物化表只收智慧系列）⇒ 兩表聯集，否則手動系列的商品
        # `product.collections` 恆空（hoko.vip `?view=ajax_product_card_compare` 的系列欄出「首頁」，我方空）。
        ids = CollectionMembership.where(shop_id: @p.shop_id, product_id: @p.id).pluck(:collection_id) |
              CollectionProduct.where(shop_id: @p.shop_id, product_id: @p.id).pluck(:collection_id)
        rows = Collection.published_on(@publication).where(id: ids).order(:id).to_a
        published = collection_published_at_map(rows)
        rows.map do |c|
          CollectionDrop.new(c, url_prefix: @url_prefix, published_at: published[c.id])
        end
      end
    end

    # A′6：metafields 根（namespace → key 惰性鏈；契約見 MetafieldsRootDrop）。
    def metafields
      @metafields ||= MetafieldsRootDrop.new(@p)
    end

    # A′7：taxonomy 分類（category_gid 既有欄；無值 ⇒ nil）。
    def category
      @p.category_gid.present? ? CategoryDrop.new(@p.category_gid) : nil
    end

    # 本商品在渲染管道上的發布時點（json 面用；無管道語境 ⇒ nil）。
    def published_at
      return nil if @publication.nil?

      @published_at ||= ResourcePublication.where(
        shop_id: @p.shop_id, publication_id: @publication.id,
        publishable_type: "Product", publishable_id: @p.id
      ).pick(:published_at)
    end

    # 官方："A timestamp for when the product was created."（objects/product，取證 2026-09-02；
    # 引擎缺口 PR-4——Ella／Minimog 用 `product.created_at` 算「新品」標）。
    def created_at = @p.created_at&.iso8601

    def options_with_values
      @options_with_values ||= @p.product_options.sort_by(&:position).map do |o|
        ProductOptionDrop.new(o, self)
      end
    rescue StandardError
      []
    end

    # @api private（A3：value id → 命中該值的變體 drops；availability 投影用）
    def variants_by_value_id
      @variants_by_value_id ||= variants.each_with_object(Hash.new { |h, k| h[k] = [] }) do |vd, h|
        vd.option_value_ids.each { |ovid| h[ovid] << vd }
      end
    end

    def options = options_with_values.map { |o| o["name"] }
    def selected_or_first_available_selling_plan_allocation = nil

    # 真引擎 product json（83 §12.2 鍵序）：有 `content` 無 `url`；無 media 鍵；
    # featured_image 無圖 ⇒ null（不代入佔位圖）。
    def as_storefront_json
      image_jsons = images.map { |i| JsonSerializer.coerce(i.as_storefront_json) }
      # E17：這是 Liquid `product | json` 形（83 §12.2：含 content、無 url）；`/products/{handle}.js` 與 recommendations JSON 的
      # 端點形（url 在 options 後、無 content、時戳店時區、變體 22 鍵）由 `Storefront::ProductAjaxJson.js_form` 轉出，不改此處。
      {
        "id" => id, "title" => title, "handle" => handle, "description" => description,
        "published_at" => JsonSerializer.coerce(published_at),
        "created_at" => JsonSerializer.coerce(@p.created_at),
        "vendor" => vendor, "type" => type, "tags" => tags,
        "price" => price, "price_min" => price_min, "price_max" => price_max,
        "available" => available, "price_varies" => price_varies,
        "compare_at_price" => compare_at_price,
        "compare_at_price_min" => compare_at_price_min,
        "compare_at_price_max" => compare_at_price_max,
        "compare_at_price_varies" => compare_at_price_varies,
        "variants" => variants.map { |v| JsonSerializer.coerce(v.as_storefront_json) },
        "images" => image_jsons, "featured_image" => image_jsons.first,
        "options" => options_with_values.map { |o| JsonSerializer.coerce(o.as_storefront_json) },
        "requires_selling_plan" => requires_selling_plan,
        "selling_plan_groups" => selling_plan_groups,
        "content" => content
      }
    end

    # @api private（collections json 的 published_at 一次撈齊）
    def collection_published_at_map(rows)
      return {} if rows.empty?

      ResourcePublication.where(
        shop_id: @p.shop_id, publication_id: @publication.id,
        publishable_type: "Collection", publishable_id: rows.map(&:id)
      ).pluck(:publishable_id, :published_at).to_h
    end

    # 🔴 specs/93 §D 紅線：Liquid `product` **沒有 `status` 屬性**（官方 44 屬性清單）。
    #   本 drop 刻意不定義它 ⇒ 落入 miss 遙測回 nil；後台語義不外洩到前台。
    def liquid_method_missing(name)
      ThemeEngine.count_miss("ProductDrop.#{name}")
      nil
    end
  end

  class CollectionDrop < Liquid::Drop
    # 官方（input-settings）：資源型 setting 直接輸出時回物件的 handle（backwards compatibility）
    def to_s = handle.to_s

    # translations：同 ProductDrop 的 overlay 契約（包 34）。
    # publication/locale/sort_param：步 12 商品出口（96 §1/§2）的渲染語境；
    #   publication nil＝無管道語境（products 回 nil——舊呼叫面行為不變）。
    # current_tags：系列 tag 路徑 `/collections/{handle}/{tag1+tag2}` 的 tag handle 陣列（引擎缺口 PR-9；
    #   help.shopify.com url-redirect 逐字 "URLs that use collection tag filtering (such as
    #   yourstore.com/collections/collection-name/tag-name)… Even if no products exist with that tag, the URL
    #   path is still considered valid"；make-collections-findable 逐字 "display only the products that match
    #   all of the tags that you enter" ⇒ 多 tag AND）。URL 段是 handle 形，對系列內實際 tag 以 handleize 相等解析。
    def initialize(collection, url_prefix: "", published_at: nil, translations: {},
                   publication: nil, locale: nil, sort_param: nil,
                   filter_query: nil, request_path: nil, current_tags: [], current_product_id: nil)
      super()
      @c = collection
      @url_prefix = url_prefix
      @published_at = published_at
      @tx = translations || {}
      @publication = publication
      @locale = locale
      @sort_param = sort_param
      @current_product_id = current_product_id # T14：系列語境商品頁的上／下一個商品
      @filter_query = filter_query
      @request_path = request_path
      @current_tags = Array(current_tags).map(&:to_s).reject(&:blank?)
    end

    # 前台 sort_by 參數值 ↔ Collection.SORT_ORDERS 內部值（96 §2 真店 9 值 select）。
    # E8b：`most-relevant` 是真值——本尊自動系列 admin「Default sort: Most relevant」⇒ 前台 default_sort_by＝most-relevant
    # （hoko.vip 首頁系列，2026-09-04；先前註釋「只在 filter 語境有意義 ⇒ 對映到預設」已證偽）。
    STOREFRONT_SORT = {
      "manual" => "manual", "best-selling" => "best_selling", "most-relevant" => "most_relevant",
      "title-ascending" => "title_asc", "title-descending" => "title_desc",
      "price-ascending" => "price_asc", "price-descending" => "price_desc",
      "created-ascending" => "created_asc", "created-descending" => "created_desc"
    }.freeze
    INTERNAL_TO_STOREFRONT = STOREFRONT_SORT.invert.freeze

    # PR-20：storefront filtering（91 §3.61 收口）——facets 語境齊備時出官方
    # filter 物件陣列；片段/editor 舊呼叫面無語境 ⇒ 照舊 []（零迭代分支）。
    def filters
      facets ? facets.filters : []
    end

    def facets
      return nil if @publication.nil? || @filter_query.nil?

      @facets ||= ThemeEngine::Facets.new(
        base_relation: CollectionProductsDrop.base_relation(collection: @c, publication: @publication,
                                                            tags: resolved_tags),
        query_string: @filter_query, path: @request_path || url, locale: @locale,
        enabled: ThemeEngine::Facets.enabled_for(@publication.shop))
    end

    def id = @c.id
    def title = @tx["title"] || @c.title
    def handle = @c.handle
    def description = @tx["body_html"] || @c.description_html
    def url = "#{@url_prefix}/collections/#{@c.handle}"
    def published_at = @published_at

    # 官方（96 §3.1 同構）：default_sort_by＝系列自身排序設定的前台鍵；
    # sort_by＝URL `sort_by` 覆寫（非法值忽略＝回預設）。
    def default_sort_by = INTERNAL_TO_STOREFRONT.fetch(@c.sort_order, "manual")
    def sort_by = STOREFRONT_SORT.key?(@sort_param.to_s) ? @sort_param.to_s : default_sort_by

    # 系列商品出口（96 §2）：懶載；paginate tag 呼叫 paginate! 設頁窗，
    # 不在 paginate 內＝前 50（官方 "up to a limit of 50"）。
    def products
      return nil if @publication.nil?

      @products ||= CollectionProductsDrop.new(
        collection: @c, publication: @publication, url_prefix: @url_prefix,
        locale: @locale, sort_key: STOREFRONT_SORT[sort_by], facets: facets, tags: resolved_tags
      )
    end

    # 官方語義（96 §2）：products_count＝當前檢視（含 filter）；
    # all_products_count＝未過濾全集（PR-20 起兩值真分家）。
    def products_count = products&.total || 0
    def all_products_count = products&.unfiltered_total || 0

    # ---- 引擎缺口 PR-4（objects/collection 逐字，取證 2026-09-02）------------------
    # image："The image for the collection. This image is added on the collection's page in the
    #   Shopify admin."——我方 collections 表無圖欄 ⇒ nil（宣告、不計 miss；圖欄隨系列線補）。
    # featured_image："The default is the collection image. If this image isn't available, then
    #   Shopify falls back to the featured image of the first product in the collection. If the
    #   first product in the collection doesn't have a featured image, then `nil` is returned."
    def image = nil

    def featured_image
      first = products&.first
      first.respond_to?(:featured_image) ? first.featured_image : nil
    end

    # T14 官方 objects/collection#previous_product／next_product（取證 2026-09-05）：
    # "The previous product in the collection. Returns `nil` if there's no previous product."（next 同形）；
    # 官方註「可用於商品頁」⇒ 語境＝`/collections/{handle}/products/{p}`，由 PageRenderer 帶 `current_product_id`。
    # 無語境（一般系列頁）或商品不在該系列 ⇒ nil。序＝該系列的生效排序（同 `products`）。
    # T14：`collection.terms` **官方 collection 物件沒有**（terms 只在 search——objects/search 逐字清單＝
    # default_sort_by／filters／performed／results／results_count／sort_by／sort_options／terms／types）。
    # Kalles／Minimog 把搜尋頁與系列頁共用同一段模板才讀到它 ⇒ 本尊同樣回 nil。顯式宣告，不計為引擎缺口。
    def terms = nil

    def previous_product = neighbour(-1)
    def next_product = neighbour(1)

    def neighbour(step)
      return nil if @current_product_id.nil? || @publication.nil?

      ids = neighbour_ids
      i = ids.index(@current_product_id) or return nil
      j = i + step
      return nil if j.negative? || j >= ids.size

      product = ActsAsTenant.with_tenant(@c.shop) { Product.find_by(shop_id: @c.shop_id, id: ids[j]) }
      product && ProductDrop.new(product, url_prefix: @url_prefix, publication: @publication)
    end
    private :neighbour

    # 系列內商品 id（生效排序）；官方未載掃描上限 ⇒ 以 limits `collection.neighbour_scan_limit` 封頂（ours）。
    def neighbour_ids
      @neighbour_ids ||= ActsAsTenant.with_tenant(@c.shop) do
        CollectionProductsDrop.base_relation(collection: @c, publication: @publication, tags: resolved_tags)
                              .reorder(Arel.sql(CollectionProductsDrop::ORDER_SQL.fetch(sort_by, CollectionProductsDrop::ORDER_SQL["manual"])))
                              .limit(Limits.fetch(:collection, :neighbour_scan_limit))
                              .pluck(:id)
      end
    end
    private :neighbour_ids

    # all_tags："All of the tags applied to the products in the collection. This includes tags for
    #   products that have been filtered out of the current view. A maximum of 1,000 tags can be
    #   returned."；tags："The tags that are currently applied to the collection. This doesn't
    #   include tags for products that have been filtered out."；all_types／all_vendors："All of
    #   the product types／vendors in a collection."。無管道語境 ⇒ 空陣列。
    def all_tags = @all_tags ||= distinct_values(:tags, unfiltered_relation).first(1000)
    def tags = @tags ||= distinct_values(:tags, filtered_relation)
    def all_types = @all_types ||= distinct_values(:product_type, unfiltered_relation)
    def all_vendors = @all_vendors ||= distinct_values(:vendor, unfiltered_relation)

    # current_vendor："The vendor name on a vendor collection page. You can query for products from
    #   a certain vendor at the `/collections/vendors` URL with a query parameter in the format of
    #   `?q=[vendor]`"；current_type 同形（`/collections/types`）。只有 PageRenderer 建的虛擬
    #   vendor／type 系列有值，真系列與 /collections/all 為 nil。
    def current_vendor = @c.respond_to?(:vendor) ? @c.vendor : nil
    def current_type = @c.respond_to?(:product_type) ? @c.product_type : nil

    # sort_options："The available sorting options for the collection."——官方頁輸出例的九項
    #   （name 官方註明「可由語言編輯器改」；我方先用官方英文名，語言表隨多語言線）。
    SORT_OPTIONS = [
      [ "Featured", "manual" ], [ "Most relevant", "most-relevant" ], [ "Best selling", "best-selling" ],
      [ "Alphabetically, A-Z", "title-ascending" ], [ "Alphabetically, Z-A", "title-descending" ],
      [ "Price, low to high", "price-ascending" ], [ "Price, high to low", "price-descending" ],
      [ "Date, old to new", "created-ascending" ], [ "Date, new to old", "created-descending" ]
    ].freeze
    # E17：平台翻譯改讀 `config/storefront_locales/{locale}.yml` 的 `_platform.sort_options`（hoko.vip 五語言
    # `/collections/all?section_id=…product-grid` 逐字，2026-09-05；external-facts §G25）；字典缺鍵 ⇒ 官方英文名。
    # 先前只有 "zh" 一組簡體名且 zh-Hant 也命中它（繁體店面出簡體）。
    def sort_options
      names = Storefront::PlatformStrings.dict(@locale.to_s).dig("_platform", "sort_options") || {}
      SORT_OPTIONS.map { |name, value| BaseDrop.new({ "name" => names.fetch(value, name), "value" => value }) }
    end

    # metafields："The metafields applied to the collection."（虛擬系列無 DB 列 ⇒ 空根）
    def metafields
      @metafields ||= @c.respond_to?(:virtual_all?) ? {} : MetafieldsRootDrop.new(@c)
    end

    # 未過濾全集（all_tags／all_types／all_vendors／all_products_count 的資料面）：不含 tag 路徑過濾。
    def unfiltered_relation
      return Product.none if @publication.nil?

      CollectionProductsDrop.base_relation(collection: @c, publication: @publication)
    end

    # 當前檢視（tags）：tag 路徑＋storefront filter 都算「過濾」。
    def filtered_relation
      return Product.none if @publication.nil?

      base = CollectionProductsDrop.base_relation(collection: @c, publication: @publication, tags: resolved_tags)
      facets ? facets.apply(base) : base
    end

    # URL 的 tag handle → 系列內實際 tag 字串（handleize 相等）；查無者保留原字串（⇒ 空結果，
    # 官方：路徑仍有效、不 404）。
    def resolved_tags
      return [] if @current_tags.empty?

      @resolved_tags ||= begin
        pool = all_tags.index_by { |tag| CollectionDrop.tag_handle(tag) }
        @current_tags.map { |raw| pool[raw] || pool[CollectionDrop.tag_handle(raw)] || raw }
      end
    end

    # 與 filters#handleize 同一規則（tag 段是 handle 形）。
    def self.tag_handle(value)
      value.to_s.downcase.gsub(/[^a-z0-9\p{Han}]+/, "-").gsub(/\A-|-\z/, "")
    end

    def distinct_values(column, relation)
      relation.pluck(column).flatten.filter_map(&:presence).uniq.sort_by(&:downcase)
    end

    # 真引擎 collection json＝9 鍵（83 §12.4 逐字鍵序）。
    # 🔴 published_scope 恆 "global"、template_suffix nil＝我方常數
    #   （無對應欄；live 同值，語義對表隨後續包）；body_html 空 ⇒ null。
    def as_storefront_json
      {
        "id" => id, "handle" => handle,
        "updated_at" => JsonSerializer.coerce(@c.updated_at),
        "published_at" => JsonSerializer.coerce(@published_at),
        "sort_order" => @c.sort_order, "template_suffix" => nil,
        "published_scope" => "global", "title" => title,
        "body_html" => @c.description_html.presence
      }
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("CollectionDrop.#{name}")
      nil
    end
  end

  # 虛擬全商品系列（96 §2：/collections/all 真店實證——無 handle=all 手動系列時
  # 仍 200，title＝Products、預設字母序）。商家自建 handle=all 的系列優先
  # （PageRenderer resolve 先查真系列）。id=0：無 DB 列（不可被 GID 引用）。
  # vendor／product_type：`/collections/vendors?q=`／`/collections/types?q=` 的虛擬系列（官方
  # objects/collection current_vendor／current_type 句；引擎缺口 PR-4）——有值時
  # CollectionProductsDrop.base_relation 以該欄過濾；/collections/all 兩者皆 nil。
  VirtualAllCollection = Struct.new(:title, :handle, :sort_order, :description_html, :updated_at,
                                    :vendor, :product_type) do
    def id = 0
    def virtual_all? = true
  end

  # 內容翻譯批載（63 §D.1 N+1 防線：整頁商品一次 batch，不逐商品查）。
  # @return [Hash{Integer => Hash{String => String}}] product_id => overlay
  module DropTranslations
    module_function

    def overlay_by_id(records:, locale:)
      return {} if locale.blank? || records.empty?

      shop = records.first.shop
      resolved = Translations::Resolve.batch(shop:, resources: records, locale: locale.to_s)
      records.each_with_object({}) do |record, acc|
        type = Translations::Resolve::RESOURCE_TYPE_BY_CLASS.fetch(record.class.name, nil)
        fields = resolved[[ type, record.id ]] || {}
        acc[record.id] = fields.each_with_object({}) do |(key, entry), inner|
          inner[key] = entry.value unless entry.omitted?
        end
      end
    end
  end

  # 系列商品的懶載出口（96 §2；official `collection.products`）。
  #
  # ①射程＝discoverable（模型註釋正典：搜尋、系列、推薦、sitemap、feed 用
  #   discoverable；商品詳情頁才是 purchasable）。
  # ②預設（不在 paginate 內）＝前 50（官方 "fetch up to 50 products by default"）；
  #   {% paginate %} 呼叫 paginate!(page:, per:) 後同一 drop 改回該頁窗。
  # ③排序：manual＝collection_products.position；price 走 MIN(variant price) 相關
  #   子查詢；best_selling v1 降級 created_desc（無銷售排名資料——91 §3 登記）。
  class CollectionProductsDrop < Liquid::Drop
    include Enumerable

    DEFAULT_LIMIT = 50 # 官方：paginate 外預設上限
    MAX_DEPTH = 25_000 # 官方："paginate to the 25,000th item in the array and no further"

    MIN_PRICE_SQL = "(SELECT MIN(pv.price_cents) FROM product_variants pv " \
                    "WHERE pv.product_id = products.id)"
    ORDER_SQL = {
      "manual" => "collection_products.position ASC, collection_products.id ASC",
      "title_asc" => "products.title ASC, products.id ASC",
      "title_desc" => "products.title DESC, products.id DESC",
      "price_asc" => "#{MIN_PRICE_SQL} ASC, products.id ASC",
      "price_desc" => "#{MIN_PRICE_SQL} DESC, products.id DESC",
      "created_desc" => "products.created_at DESC, products.id DESC",
      "created_asc" => "products.created_at ASC, products.id ASC",
      # v1 降級：無銷售排名 rollup ⇒ 以上新代位（91 §3 登記；接分析線後改真排名）
      "best_selling" => "products.created_at DESC, products.id DESC",
      # E8b：most_relevant 的排序語義未取得（91 §3.75b V）⇒ 暫同上新代位
      "most_relevant" => "products.created_at DESC, products.id DESC"
    }.freeze

    def initialize(collection:, publication:, url_prefix: "", locale: nil, sort_key: nil,
                   facets: nil, tags: [])
      super()
      @collection = collection
      @publication = publication
      @url_prefix = url_prefix
      @locale = locale
      @sort_key = sort_key
      @facets = facets
      @tags = Array(tags)
      @page, @per = 1, nil
    end

    # PR-20：base 集合抽成類方法——Facets 與列表共用同一定義（雙處漂移即
    # 「篩選器數字對不上列表」型 bug）
    # tags：系列 tag 路徑（PR-9）——逐 tag AND（help："match all of the tags"），與 BlogArticlesDrop 同一
    #   JSON_SEARCH 形；空陣列＝不過濾。
    def self.base_relation(collection:, publication:, tags: [])
      base = Product.discoverable(publication: publication)
      if collection.respond_to?(:virtual_all?)
        base = base.where(vendor: collection.vendor) if collection.vendor.present?
        base = base.where(product_type: collection.product_type) if collection.product_type.present?
      else
        base = base.joins(:collection_products)
                   .where(collection_products: { collection_id: collection.id })
      end
      Array(tags).each do |tag|
        base = base.where("JSON_SEARCH(products.tags, 'one', ?) IS NOT NULL", tag)
      end
      base
    end

    # 官方 all_products_count 的資料面（未過濾全集）
    def unfiltered_total
      @unfiltered_total ||= self.class.base_relation(collection: @collection, publication: @publication).count
    end

    # paginate tag 的接線點：設頁窗並回總數（PaginateDrop 需要 items）。
    def paginate!(page:, per:)
      @page, @per = page, per
      @drops = nil
      total
    end

    def each(&) = drops.each(&)
    def size = drops.size
    def first = drops.first

    def total
      @total ||= relation.count
    end

    private

    def virtual_all? = @collection.respond_to?(:virtual_all?)

    def relation
      base = self.class.base_relation(collection: @collection, publication: @publication, tags: @tags)
      base = @facets.apply(base) if @facets # PR-20：storefront filter 過濾
      base
    end

    def sort_key
      key = @sort_key.presence || @collection.sort_order
      # manual 對虛擬 all 無意義（無 position 列）⇒ 字母序（96 §2 真店預設形）
      key = "title_asc" if virtual_all? && key == "manual"
      ORDER_SQL.key?(key) ? key : "title_asc"
    end

    def offset
      per = @per || DEFAULT_LIMIT
      [ (@page - 1) * per, MAX_DEPTH ].min
    end

    def drops
      @drops ||= begin
        per = @per || DEFAULT_LIMIT
        products = relation.order(Arel.sql(ORDER_SQL.fetch(sort_key)))
                           .offset(offset).limit(per)
                           .includes(
                             product_variants: [ :product_variant_option_values,
                                                 { inventory_item: :inventory_levels },
                                                 { media: :stored_file } ],
                             product_options: :option_values,
                             media: :stored_file
                           ).to_a
        overlay = DropTranslations.overlay_by_id(records: products, locale: @locale)
        products.map do |product|
          ProductDrop.new(product, url_prefix: @url_prefix, publication: @publication,
                          translations: overlay[product.id] || {})
        end
      end
    end
  end

  # `collections` 全域（96 §1：official "All of the collections on a store."）。
  # 射程＝該管道已發布集（真店實證：OS 未發布系列不出現在 /collections）；
  # 迭代＝字母序（官方 "outputs the collections in alphabetical order"）；
  # `collections['handle']` 取單個；`size`＝Ella 消費形（官方頁未記載，96 §8）。
  class CollectionsDrop < Liquid::Drop
    include Enumerable

    def initialize(shop:, publication:, url_prefix: "", locale: nil)
      super()
      @shop = shop
      @publication = publication
      @url_prefix = url_prefix
      @locale = locale
      @page, @per = 1, nil
    end

    # 🔴 handle 存取走 liquid_method_missing、**不覆寫 `[]`**：Liquid::Drop#key? 恆
    # true ⇒ VariableLookup 對 drop 一律走 `[]`（＝invoke_drop 屬性派發）；覆寫 []
    # 會把 `collections.size` 劫持成 handle 查詢（本輪紅測實錘）。代價＝與
    # Enumerable 方法重名的 handle（map/first…）被方法遮蔽——本尊同型限制。
    def liquid_method_missing(handle)
      h = handle.to_s
      return nil if h.blank?

      @by_handle ||= {}
      return @by_handle[h] if @by_handle.key?(h)

      collection = Storefront::Lookup.collection_by_handle(publication: @publication, handle: h)
      @by_handle[h] = collection && wrap(collection)
    end

    def each(&) = drops.each(&)
    def size = total
    def first = drops.first

    def paginate!(page:, per:)
      @page, @per = page, per
      @drops = nil
      total
    end

    def total
      @total ||= relation.count
    end

    private

    def relation
      Collection.published_on(@publication).order(:title, :id)
    end

    def drops
      @drops ||= begin
        scope = relation
        scope = scope.offset((@page - 1) * @per).limit(@per) if @per
        scope.map { |collection| wrap(collection) }
      end
    end

    def wrap(collection)
      CollectionDrop.new(collection, url_prefix: @url_prefix, publication: @publication,
                         locale: @locale)
    end
  end

  # `all_products` 全域（96 §7）：handle 取商品；官方上限＝"a limit of 20 unique
  # handles per page"——第 21 個唯一 handle 回 nil＋遙測（官方未記載超限行為，
  # fail-quiet 是 ours；96 §8）。未命中官方回 `empty` ⇒ 我方 nil（{% if %} 同 falsy）。
  class AllProductsDrop < Liquid::Drop
    UNIQUE_HANDLE_LIMIT = 20

    def initialize(publication:, url_prefix: "", locale: nil)
      super()
      @publication = publication
      @url_prefix = url_prefix
      @locale = locale
      @cache = {}
    end

    # handle 存取走 liquid_method_missing（不覆寫 `[]`——理由見 CollectionsDrop 同註）。
    def liquid_method_missing(handle)
      h = handle.to_s
      return nil if h.blank?
      return @cache[h] if @cache.key?(h)

      if @cache.size >= UNIQUE_HANDLE_LIMIT
        ThemeEngine.count_miss("all_products.unique_handle_limit")
        return nil
      end

      product = Storefront::Lookup.product_by_handle(publication: @publication, handle: h)
      @cache[h] = product && ProductDrop.new(
        product, url_prefix: @url_prefix, publication: @publication,
        translations: DropTranslations.overlay_by_id(records: [ product ], locale: @locale)[product.id] || {}
      )
    end
  end

  # 搜尋結果的混型懶載出口（步 12b；96 §3——official `search.results`，item 可為
  # product／page／article、多帶 object_type）。
  #
  # ①排序：relevance＝商品在前（建立序新在前）→ 頁面（ours——官方 relevance 算法
  #   未公開）；price-±＝商品按 MIN(variant price)、**非商品結果推到尾**（官方句）。
  # ②分頁窗跨型別連續切（商品段先、頁面段後）；paginate 上限同 collection.products。
  class SearchResultsDrop < Liquid::Drop
    include Enumerable

    DEFAULT_LIMIT = 50

    PRODUCT_ORDER_SQL = {
      "relevance" => "products.created_at DESC, products.id DESC",
      "price-ascending" => "#{CollectionProductsDrop::MIN_PRICE_SQL} ASC, products.id ASC",
      "price-descending" => "#{CollectionProductsDrop::MIN_PRICE_SQL} DESC, products.id DESC"
    }.freeze

    def initialize(shop:, publication:, query:, types:, sort_key:, url_prefix: "", locale: nil,
                   facets: nil)
      super()
      @shop, @publication = shop, publication
      @query = query
      # PR-21 官方：filter 啟用 ⇒ 非商品結果全濾除
      @types = facets&.active? ? (types & [ "product" ]) : types
      @sort_key = PRODUCT_ORDER_SQL.key?(sort_key) ? sort_key : "relevance"
      @url_prefix = url_prefix
      @locale = locale
      @facets = facets
      @page, @per = 1, nil
    end

    def paginate!(page:, per:)
      @page, @per = page, per
      @drops = nil
      total
    end

    def each(&) = drops.each(&)
    def size = drops.size
    def first = drops.first

    def total
      @total ||= products_total + pages_total + articles_total
    end

    private

    def products_total
      @products_total ||= @types.include?("product") ? product_relation.count : 0
    end

    # 每次回應一個 9 hex 搜尋 session id（本尊 `_sid=25ef0946b`；值隨機＝身分，Normalizer 抹 `_sid=SID`）
    def search_sid
      @search_sid ||= SecureRandom.hex(5)[0, 9]
    end

    def pages_total
      @pages_total ||= @types.include?("page") ? page_relation.count : 0
    end

    def articles_total
      @articles_total ||= @types.include?("article") ? article_relation.count : 0
    end

    def article_relation
      Storefront::SearchQuery.articles(shop: @shop, query: @query)
    end

    def product_relation
      base = Storefront::SearchQuery.products(shop: @shop, publication: @publication, query: @query)
      base = @facets.apply(base) if @facets # PR-21：storefront filter
      base
    end

    def page_relation
      Storefront::SearchQuery.pages(shop: @shop, query: @query)
    end

    def drops
      @drops ||= begin
        per = @per || DEFAULT_LIMIT
        offset = (@page - 1) * per
        items = []
        if @types.include?("product") && offset < products_total
          # E17：`id:{n} OR id:{n}` 查詢的結果序＝relevance（hoko.vip 2026-09-05 main-search 三組查詢皆 cosy(_pos=1)、bolt(2)、acme(3)
          # ＝created_at DESC，與 query 內順序無關；Ella recently-viewed 段自行反序顯示——**不是**引擎排序）。
          # `product.url` 帶搜尋歸因參數 `?_pos={結果序}&_sid={每次回應 9 hex}&_ss=r`（hoko `/search?q=tee&section_id=…main-search` 逐字
          # `href="/products/acme-tee?_pos=1&_sid=d601cf1ac&_ss=r"`；recently-viewed 段的 `data-product-url` 同形）。頁面／文章結果的參數形＝V。
          products = product_relation.order(Arel.sql(PRODUCT_ORDER_SQL.fetch(@sort_key)))
                                     .offset(offset).limit(per)
                                     .includes(product_variants: [ :product_variant_option_values,
                                                                   { inventory_item: :inventory_levels },
                                                                   { media: :stored_file } ],
                                               product_options: :option_values,
                                               media: :stored_file).to_a
          overlay = DropTranslations.overlay_by_id(records: products, locale: @locale)
          items.concat(products.each_with_index.map do |product, i|
            ProductDrop.new(product, url_prefix: @url_prefix, publication: @publication,
                            translations: overlay[product.id] || {},
                            url_params: "?_pos=#{offset + i + 1}&_sid=#{search_sid}&_ss=r")
          end)
        end
        if @types.include?("page") && items.size < per
          page_offset = [ offset - products_total, 0 ].max
          pages = page_relation.order(:title, :id).offset(page_offset).limit(per - items.size).to_a
          items.concat(pages.map { |page| PageDrop.new(page, url_prefix: @url_prefix) })
        end
        if @types.include?("article") && items.size < per
          article_offset = [ offset - products_total - pages_total, 0 ].max
          articles = article_relation.includes(:blog).order(:title, :id)
                                     .offset(article_offset).limit(per - items.size).to_a
          items.concat(articles.map { |article| ArticleDrop.new(article, url_prefix: @url_prefix) })
        end
        items
      end
    end
  end

  # `search` 全域（96 §3.1——official search object 九屬性；filters v1 恆空陣列，
  # storefront filter 隨 filter 包＝91 §3.61）。
  class SearchDrop < Liquid::Drop
    SORT_VALUES = %w[relevance price-ascending price-descending].freeze # 96 §3.2 真店恰 3 值
    TYPE_VALUES = %w[article page product].freeze

    def initialize(shop:, publication:, url_prefix: "", locale: nil, params: {})
      super()
      @shop, @publication = shop, publication
      @url_prefix = url_prefix
      @locale = locale
      @params = params || {}
    end

    # T14：官方 objects/search（取證 2026-09-05）逐字只有 default_sort_by／filters／performed／results／
    # results_count／sort_by／sort_options／terms／types。三套主題另讀 `url`／`id`／`current_vendor`／`current_type`
    # （搜尋頁與系列頁共用模板的殘留）——**本尊同樣回 nil**；顯式宣告以免計為引擎缺口。
    def url = nil
    def id = nil
    def current_vendor = nil
    def current_type = nil

    def terms = @params["q"].to_s
    def performed = terms.present?
    def default_sort_by = "relevance"

    def sort_by
      value = @params["sort_by"].to_s
      SORT_VALUES.include?(value) ? value : default_sort_by
    end

    # E17：name＝平台翻譯（hoko.vip 五語言 `/search?q=tee&section_id=…main-search` 逐字，2026-09-05；§G25）；先前 name＝value
    # ⇒ 搜尋頁排序下拉出 `relevance`／`price-ascending` 字面。字典缺鍵 ⇒ 官方英文（en 店面實測）。
    SEARCH_SORT_NAMES_EN = { "relevance" => "Relevance", "price-ascending" => "Price, low to high",
                             "price-descending" => "Price, high to low" }.freeze

    def sort_options
      names = Storefront::PlatformStrings.dict(@locale.to_s).dig("_platform", "search_sort_options") || {}
      SORT_VALUES.map do |value|
        BaseDrop.new({ "value" => value, "name" => names.fetch(value, SEARCH_SORT_NAMES_EN.fetch(value)) })
      end
    end

    # 官方："The types are determined by the `type` query parameter."（CSV；預設全部）
    def types
      requested = @params["type"].to_s.split(",").map(&:strip) & TYPE_VALUES
      requested.presence || TYPE_VALUES
    end

    # PR-21：search facets——同一 Facets 服務（base＝商品搜尋結果集合）。
    # 官方：filter 啟用時「all non-product results are filtered out」。
    def filters
      facets ? facets.filters : []
    end

    # E17：**零結果 ⇒ filters 為空**（hoko.vip 2026-09-05 `/search?q=zzzzqq&section_id=…main-search`：Ella
    # `{% if search.results_count == 0 and search.filters == empty %}` 命中 ⇒ 只出 `<p role="status">未找到与“zzzzqq”…</p>`、
    # 無 facets 區塊；我方先前對空結果仍建 availability／price 過濾器 ⇒ 多出整個 facets-block-wrapper、狀態句消失）。
    def facets
      return @facets if defined?(@facets)

      @facets = nil
      return nil unless performed && @publication && @params.key?("_facets_qs")

      base = Storefront::SearchQuery.products(shop: @shop, publication: @publication, query: terms)
      return nil unless base.exists?

      @facets = ThemeEngine::Facets.new(
        base_relation: base, query_string: @params["_facets_qs"].to_s,
        path: "#{@url_prefix}/search", locale: @locale, enabled: ThemeEngine::Facets.enabled_for(@shop))
    end

    # E8b：未執行搜尋 ⇒ 0（hoko.vip /search 無 q 時 Ella `search.results_count > 0` 不炸；先前 `results` 回 [] ⇒ `[].total` NoMethodError
    # ⇒ `Liquid error (blocks/_recently_viewed_products line 70): internal`）。官方對未執行時的值未逐字（V）。
    def results_count = performed ? results.total : 0

    def results
      return [] unless performed

      @results ||= SearchResultsDrop.new(
        shop: @shop, publication: @publication, query: terms, types:,
        sort_key: sort_by, url_prefix: @url_prefix, locale: @locale,
        facets: facets
      )
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("SearchDrop.#{name}")
      nil
    end
  end

  # `predictive_search` 物件（96 §4.3；official：performed／resources／terms／types，
  # resources＝四型陣列——**無 queries**，query suggestions 屬 Ajax 層）。
  class PredictiveSearchDrop < Liquid::Drop
    def initialize(terms:, resources:, types:)
      super()
      @terms = terms
      @resources = resources
      @types = types
    end

    def performed = true
    def terms = @terms
    def types = @types
    def resources = BaseDrop.new(@resources)
  end

  # 文章留言（98 §1 官方：Liquid 只見 published——status 恆 "published"）。
  class CommentDrop < Liquid::Drop
    def initialize(comment, article_url: "")
      super()
      @c = comment
      @article_url = article_url
    end

    def id = @c.id
    def author = @c.author_name
    def content = @c.body
    def status = "published"
    def created_at = @c.created_at&.iso8601
    def url = "#{@article_url}#comment-#{@c.id}"
  end

  # 部落格文章（98 §1 官方 21 屬性的 v1 對位）。
  #
  # 🔴 `handle`/`url`＝**複合形**（官方範例值 `{blog}/{article}`）；`id` 官方型別
  #   string、我方整數（登記）；image/metafields/user v1 nil（91 §3.64）。
  class ArticleDrop < Liquid::Drop
    def initialize(article, url_prefix: "", blog: nil)
      super()
      @a = article
      @url_prefix = url_prefix
      @blog = blog || article.blog
    end

    def id = @a.id
    def title = @a.title
    def author = @a.author_name
    def handle = "#{@blog.handle}/#{@a.handle}"
    def url = "#{@url_prefix}/blogs/#{@blog.handle}/#{@a.handle}"
    def content = @a.body_html
    def excerpt = @a.excerpt_html
    def excerpt_or_content = @a.excerpt_html.presence || @a.body_html
    def tags = @a.tags.to_a
    def template_suffix = @a.template_suffix
    def published_at = @a.published_at&.iso8601
    def created_at = @a.created_at&.iso8601
    def updated_at = @a.updated_at&.iso8601
    def comments_enabled? = @blog.comments_enabled?
    def moderated? = @blog.moderated?
    def comments_count = @a.published_comments.count
    def comment_post_url = "#{url}/comments"
    def object_type = "article" # 96 §3.1 搜尋結果混型判別

    # 引擎缺口 PR-4（objects/article，取證 2026-09-02）：image "The featured image for the article."
    #   ——我方 articles 表無圖欄 ⇒ nil（宣告、不計 miss；圖欄隨內容線補）；
    #   metafields "The metafields applied to the article."
    def image = nil

    def metafields
      @metafields ||= MetafieldsRootDrop.new(@a)
    end

    # 官方："The **published** comments for the article."（分頁上限 50 官方句——
    # paginate! 由 tag 接線；預設前 50）
    def comments
      @comments ||= CommentsDrop.new(article: @a, article_url: url)
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("ArticleDrop.#{name}")
      nil
    end
  end

  # 文章留言集合（paginate 支援；官方 50/頁上限）。
  class CommentsDrop < Liquid::Drop
    include Enumerable

    DEFAULT_LIMIT = 50

    def initialize(article:, article_url:)
      super()
      @article = article
      @article_url = article_url
      @page, @per = 1, nil
    end

    def paginate!(page:, per:)
      @page, @per = [ page, 1 ].max, [ per, DEFAULT_LIMIT ].min
      @rows = nil
      total
    end

    def each(&) = rows.each(&)
    def size = rows.size

    def total
      @total ||= @article.published_comments.count
    end

    private

    def rows
      @rows ||= begin
        per = @per || DEFAULT_LIMIT
        @article.published_comments.order(:created_at, :id)
                .offset((@page - 1) * per).limit(per)
                .map { |comment| CommentDrop.new(comment, article_url: @article_url) }
      end
    end
  end

  # 部落格（98 §1 官方 14 屬性的 v1 對位；articles 可分頁）。
  class BlogDrop < Liquid::Drop
    # 官方（input-settings）：資源型 setting 直接輸出時回物件的 handle（backwards compatibility）
    def to_s = handle.to_s

    # current_article：文章頁的錨（next_article／previous_article 相對於它）；非文章頁 nil。
    def initialize(blog, url_prefix: "", current_tags: nil, current_article: nil)
      super()
      @b = blog
      @url_prefix = url_prefix
      @current_tags = current_tags
      @current_article = current_article
    end

    # 官方（objects/blog，取證 2026-09-02；引擎缺口 PR-4）：
    #   next_article "The next (older) article in the blog. Returns `nil` if there is no next article."
    #   previous_article "The previous (newer) article in the blog. Returns `nil` if there is no
    #   previous article."——以 published_at（同刻以 id）為序，只看 visible 文章。
    def next_article
      return nil unless @current_article

      @next_article ||= neighbour_article(older: true)
    end

    def previous_article
      return nil unless @current_article

      @previous_article ||= neighbour_article(older: false)
    end

    # 官方："The metafields applied to the blog."
    def metafields
      @metafields ||= MetafieldsRootDrop.new(@b)
    end

    def id = @b.id
    def title = @b.title
    def handle = @b.handle
    def url = "#{@url_prefix}/blogs/#{@b.handle}"
    def comments_enabled? = @b.comments_enabled?
    def moderated? = @b.moderated?
    def template_suffix = @b.template_suffix

    # 官方："This total doesn't include hidden articles."
    def articles_count = articles.total

    def articles
      @articles ||= BlogArticlesDrop.new(blog: @b, url_prefix: @url_prefix,
                                         current_tags: @current_tags)
    end

    # 兩欄官方皆存在且描述近同（98 §5-5：語義差異明文未取得 ⇒ 同值）。
    def all_tags
      @all_tags ||= Article.visible.where(shop_id: @b.shop_id, blog_id: @b.id)
                           .pluck(:tags).flatten.uniq.sort
    end

    def tags = all_tags

    def liquid_method_missing(name)
      ThemeEngine.count_miss("BlogDrop.#{name}")
      nil
    end

    private

    def neighbour_article(older:)
      anchor = @current_article
      at = anchor.published_at
      scope = Article.visible.where(shop_id: @b.shop_id, blog_id: @b.id).where.not(id: anchor.id)
      row = if older
        scope.where("published_at < ? OR (published_at = ? AND id < ?)", at, at, anchor.id)
             .order(published_at: :desc, id: :desc).first
      else
        scope.where("published_at > ? OR (published_at = ? AND id > ?)", at, at, anchor.id)
             .order(published_at: :asc, id: :asc).first
      end
      row && ArticleDrop.new(row, url_prefix: @url_prefix, blog: @b)
    end
  end

  # 部落格文章集合（visible 閘＋tagged 過濾＋paginate；新到舊）。
  class BlogArticlesDrop < Liquid::Drop
    include Enumerable

    DEFAULT_LIMIT = 50

    def initialize(blog:, url_prefix: "", current_tags: nil)
      super()
      @blog = blog
      @url_prefix = url_prefix
      @current_tags = Array(current_tags).reject(&:blank?)
      @page, @per = 1, nil
    end

    def paginate!(page:, per:)
      @page, @per = [ page, 1 ].max, per
      @rows = nil
      total
    end

    def each(&) = rows.each(&)
    def size = rows.size
    def first = rows.first

    def total
      @total ||= relation.count
    end

    private

    # tagged 過濾（98 §2 官方：/tagged/{tag}＋`+` 多 tag——AND 語義照官方
    # "filter by multiple tags by combining"）。
    def relation
      scope = Article.visible.where(shop_id: @blog.shop_id, blog_id: @blog.id)
      @current_tags.each do |tag|
        scope = scope.where("JSON_SEARCH(articles.tags, 'one', ?) IS NOT NULL", tag)
      end
      scope
    end

    def rows
      @rows ||= begin
        per = @per || DEFAULT_LIMIT
        relation.order(published_at: :desc, id: :desc)
                .offset((@page - 1) * per).limit(per)
                .includes(:blog)
                .map { |article| ArticleDrop.new(article, url_prefix: @url_prefix, blog: @blog) }
      end
    end
  end

  # `blogs` 全域（98 §1 官方：by handle 存取）。handle 查詢走 liquid_method_missing
  # （12a 教訓：不覆寫 `[]`）。
  class BlogsDrop < Liquid::Drop
    def initialize(shop:, url_prefix: "")
      super()
      @shop = shop
      @url_prefix = url_prefix
    end

    def liquid_method_missing(name)
      blog = Blog.find_by(shop_id: @shop.id, handle: name.to_s)
      return BlogDrop.new(blog, url_prefix: @url_prefix) if blog

      ThemeEngine.count_miss("blogs.#{name}")
      nil
    end
  end

  # PR-13：pages 全域（官方 "All of the pages on a store."，by-handle 取用形
  # `pages['about-us'].title`，shopify.dev objects/pages 2026-09-02）。
  # Ella 消費點：header/toolbar 的 `pages['wish-list'].url`（toolbar-mobile:187、
  # header-functions:52、menu-drawer-utility:57）。
  class PagesDrop < Liquid::Drop
    def initialize(shop:, url_prefix: "")
      super()
      @shop = shop
      @url_prefix = url_prefix
    end

    def liquid_method_missing(name)
      page = Page.find_by(shop_id: @shop.id, handle: name.to_s)
      return PageDrop.new(page, url_prefix: @url_prefix) if page

      ThemeEngine.count_miss("pages.#{name}")
      nil
    end
  end

  # PR-13：images 全域（官方 "All of the images that have been uploaded to a
  # store."，by-filename 取用形 `images['potions-header.png']`，shopify.dev
  # objects/images 2026-09-02）。Ella 消費點：品牌/vendor 圖卡
  # `images[vendor_image_name_png]`（_card-product-vendor-flex:18 等 20 用/6 檔）。
  class ImagesDrop < Liquid::Drop
    def initialize(shop:)
      super()
      @shop = shop
    end

    def liquid_method_missing(name)
      # 🔴 without_tenant＋顯式 shop_id（鐵律 2 條款②）——同 resolve_settings_file
      file = ActsAsTenant.without_tenant do
        StoredFile.find_by(shop_id: @shop.id, filename: name.to_s)
      end
      return FileImageDrop.new(file) if file

      ThemeEngine.count_miss("images.#{name}")
      nil
    end
  end

  class PageDrop < Liquid::Drop
    # 官方（input-settings）：資源型 setting 直接輸出時回物件的 handle（backwards compatibility）
    def to_s = handle.to_s

    def initialize(page, url_prefix: "")
      super()
      @page = page
      @url_prefix = url_prefix
    end

    def id = @page.id
    def title = @page.title
    def handle = @page.handle
    def content = @page.body_html
    def object_type = "page" # 96 §3.1 搜尋結果混型判別
    def url = "#{@url_prefix}/pages/#{@page.handle}"
    def published_at = @page.published_at&.iso8601

    # 官方："The metafields applied to the page."（objects/page；引擎缺口 PR-4——原為 miss）
    def metafields
      @metafields ||= MetafieldsRootDrop.new(@page)
    end

    def liquid_method_missing(name)
      ThemeEngine.count_miss("PageDrop.#{name}")
      nil
    end
  end

  # PR-16：video_url setting 的值物件（官方：回「a string that contains the
  # entered URL」＋ `id`/`type` 屬性，type ∈ youtube/vimeo；空 ⇒ nil。
  # shopify.dev input-settings#video_url 取證 2026-09-02）。
  # 🔴 用 Drop 不用 String 子類：Liquid 對非 Drop 走 `[]`，而 String#[]("id")
  # 是子字串搜尋——`url['id']` 會回 "id" 假值。
  class VideoUrlDrop < Liquid::Drop
    YOUTUBE_RE = %r{(?:youtube\.com/watch\?v=|youtube\.com/embed/|youtu\.be/)([\w-]{6,})}
    VIMEO_RE = %r{vimeo\.com/(?:video/)?(\d+)}

    def self.parse(url)
      s = url.to_s
      if (m = s.match(YOUTUBE_RE)) then new(url: s, id: m[1], type: "youtube")
      elsif (m = s.match(VIMEO_RE)) then new(url: s, id: m[1], type: "vimeo")
      end
    end

    def initialize(url:, id:, type:)
      super()
      @url, @id, @type = url, id, type
    end

    attr_reader :id, :type

    def url = @url
    def to_s = @url
  end

  # T13 官方 objects/policy（取證 2026-09-05）："A store policy, such as a privacy or return policy."——body（string）／id（string）／
  # title（string）／url（string，相對 URL `/policies/{handle}`）。id 值形本尊未觀測（91 §3.90 V）＝我方列 id 字串。
  class PolicyDrop < Liquid::Drop
    def initialize(policy, url_prefix: "")
      super()
      @policy = policy
      @url_prefix = url_prefix.to_s
    end

    def id = @policy.id.to_s
    def title = @policy.title.to_s
    def body = @policy.body.to_s
    def url = "#{@url_prefix}/policies/#{@policy.kind}"
  end

  class ShopDrop < Liquid::Drop
    # @param url_prefix [String] 語言前綴（`policy.url` 帶前綴——hoko 政策頁 hreflang 六語言皆有前綴形）
    def initialize(shop, url_prefix: "")
      super()
      @shop = shop
      @url_prefix = url_prefix.to_s
    end

    def id = @shop.id
    def name = @shop.name

    # T14：`shop.taxes_included` **官方 shop 物件沒有**（含稅旗標在 `cart.taxes_included`——objects/cart）。
    # Minimog `snippets/main-product-blocks` 讀它 ⇒ 本尊回 nil、主題不顯示稅務說明。
    # 🔴 不得改成回 `@shop.taxes_included` 欄位——那會比本尊多出一段文案（輸出不同即違反逐字對齊）。
    def taxes_included = nil

    # T13：官方 objects/shop（取證 2026-09-05）——`policies`＝array of policy；五個具名政策各回 policy 或 nil。
    # 判準（hoko.vip 2026-09-05）：只有設了內容的政策存在（未設者 `/policies/x` 404；Kalles 以 `shop.shipping_policy.body != blank` 判空）
    # ⇒ 未設／空 body ⇒ nil、不進 policies。陣列序本尊未觀測（91 §3.90 V）＝ShopPolicy::KINDS 序。
    def policies = policy_rows.map { |row| PolicyDrop.new(row, url_prefix: @url_prefix) }
    def privacy_policy = policy_drop("privacy-policy")
    def refund_policy = policy_drop("refund-policy")
    def terms_of_service = policy_drop("terms-of-service")
    def shipping_policy = policy_drop("shipping-policy")
    def subscription_policy = policy_drop("subscription-policy")

    def policy_rows
      @policy_rows ||= ActsAsTenant.with_tenant(@shop) { ShopPolicy.where(shop_id: @shop.id).present_body.to_a }
                                   .sort_by { |row| ShopPolicy::KINDS.index(row.kind) || ShopPolicy::KINDS.size }
    end
    private :policy_rows

    def policy_drop(kind)
      row = policy_rows.find { |r| r.kind == kind }
      row && PolicyDrop.new(row, url_prefix: @url_prefix)
    end
    private :policy_drop
    def currency = @shop.store_currency
    # 官方逐字（objects/shop，2026-09-03）：domain＝"The primary domain of the store."；permanent_domain＝
    # "The `.myshopify.com` domain of the store."——我方永久網域＝`{subdomain}.{base_host}`（與 ShopifyGlobal
    # `Shopify.shop`、Notifications::Payloads 同一 host 鏈；先前硬編 `chilllove.example` 是 PoC 殘留，91 §3.75 登記）。
    def domain = @shop.custom_domain.presence || permanent_domain
    def permanent_domain = "#{@shop.subdomain}.#{Chilllove::TenantResolver.base_host}"
    def url = "https://#{domain}"
    def secure_url = url
    def email = nil
    # D81（2026-09-03）：店級設定直出。官方 objects/shop 逐字：money_format＝"The money format of the store."、
    # money_with_currency_format＝"The money format of the store with the currency included."。本尊 admin
    # Settings › General › Change currency formatting 四欄（真店 pnrjnw-sy 2026-09-03 實讀，external-facts §G15）：
    # HTML with currency `HK${{amount}} HKD`／HTML without currency `${{amount}}`／Email 兩欄同值。
    # Ella JS（snippets/global-script.liquid）把這個字串原樣塞進 `window.money_format` 自己做 formatMoney ⇒
    # 與 money 過濾器同一字串來源（鐵律 7：格式邏輯一份＝ThemeEngine::MoneyFormat）。
    def money_format = @shop.money_format
    def money_with_currency_format = @shop.money_with_currency_format

    # description："The description of the store."——shops 表無對應欄（`grep -n description db/schema.rb`
    #   於 shops 段零命中）⇒ 宣告 nil、不計 miss；欄位隨店家設定線補。
    def description = nil

    # features：官方 objects/shop 屬性表**無**此鍵（未文檔化）；Ella／Kalles 以
    #   `shop.features.login_with_shop_classic_customer_accounts?`／`follow_on_shop?` 守 Shop 登入／
    #   追蹤按鈕（filters/login_button）。我方無 Shop 登入 ⇒ 兩旗標 false（＝功能未啟用的本尊形），
    #   宣告以免計 miss；本尊 runtime 實際值形＝未取得（登記）。
    def features = ShopFeaturesDrop.new

    def enabled_currencies = [ @shop.store_currency ]
    def published_locales = []
    # 官方逐字（objects/shop，2026-09-03）："Returns true if the store shows a login link. Returns false if not."
    # 店級設定（shops.customer_accounts_enabled，預設 true＝本尊新店形：hoko.vip 未動設定即渲染 Drawer-Account，
    # 該區塊受 `enable_account and shop.customer_accounts_enabled` 守）。
    def customer_accounts_enabled = @shop.customer_accounts_enabled
    # 官方逐字："Returns true if customer accounts are optional to complete checkout. Returns false if not."
    # 我方無「必須登入才可結帳」設定 ⇒ 恆 true（登記）。
    def customer_accounts_optional = true
    def metafields = {}
    def brand = nil
    def products_count = Product.where(shop_id: @shop.id).count
    # PR-13（官方 shop.types＝"All of the product types in the store."／
    # shop.vendors＝"All of the product vendors for the store."，array of string，
    # shopify.dev objects/shop 2026-09-02）。空值剔除＋不分大小寫排序。
    def types
      Product.where(shop_id: @shop.id).distinct.pluck(:product_type)
             .filter_map(&:presence).sort_by(&:downcase)
    end

    def vendors
      Product.where(shop_id: @shop.id).distinct.pluck(:vendor)
             .filter_map(&:presence).sort_by(&:downcase)
    end

    # 付款圖示值域（第三包；86 §5 實錘）：本尊語義＝「enabled payment providers」
    # 導出的**卡別**清單；🔴 manual methods 不進圖示列（Bank Deposit 啟用期間
    # footer 圖示仍空——86 §5 實測），且我方 v1 無信用卡 provider ⇒ **顯式空集合**
    # （Ella payment-icons/footer-bottom 的 for 迴圈零次＝正確渲染；PSP pack 落地時
    # 由 provider 能力導出卡別，完整 enum 官方未載——86 §5 V）。
    def enabled_payment_types = []

    def liquid_method_missing(name)
      ThemeEngine.count_miss("ShopDrop.#{name}")
      nil
    end
  end

  # `shop.features`（未文檔化；見 ShopDrop#features 註）——兩旗標 false，未知鍵計 miss。
  class ShopFeaturesDrop < BaseDrop
    def initialize
      super({ "login_with_shop_classic_customer_accounts?" => false, "follow_on_shop?" => false })
    end
  end

  # 選單（linklists）——DB：menus／menu_items。
  class LinkDrop < Liquid::Drop
    # @param current_path [String] 帶前綴的當前路徑（link.current 比對用）
    def initialize(item, url_prefix: "", current_path: nil)
      super()
      @item = item
      @url_prefix = url_prefix
      @current_path = current_path
    end

    def title = @item.title
    # 官方 "The handle of the link."——由標題 handleize（hoko.vip：`id="HeaderMenu-首頁"` ⇒ CJK 保留）
    def handle = @item.title.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, "-").gsub(/\A-|-\z/, "")

    # 官方逐字（objects/link，2026-09-03）：current "Returns true if the current URL path matches the URL of the link."；
    # child_current "Returns true if current URL path matches a link's child link URL."；active／child_active 官方只說
    # "Returns true if the link is active"（判準未取得 ⇒ 以 current 對位，登記 V）。比對＝去尾斜線的路徑（首頁 `/` 形）。
    def current
      return false if @current_path.nil?

      # E8b：http 型連結存的是無前綴路徑（hoko 主選單「聯絡我們」＝`/pages/contact`），而 current_path 帶市場前綴
      # `/zh-hans-tw/pages/contact` ⇒ 兩邊都先去前綴再比（hoko.vip /pages/contact：該項 `aria-current="page"`＋
      # `header__active-menu-item`，我方先前 false）。資源型連結的 url 自帶前綴，去掉後同樣可比。
      normalize_path(strip_prefix(url)) == normalize_path(strip_prefix(@current_path))
    end

    def strip_prefix(path)
      p = path.to_s
      return p if @url_prefix.blank?

      p == @url_prefix || p.start_with?("#{@url_prefix}/") ? p.delete_prefix(@url_prefix) : p
    end
    def active = current
    def child_current = links.any?(&:current)
    def child_active = links.any?(&:active)

    # 官方 link.type 值形＝`{kind}_link`（98 §1 逐字 13 值；我方子集同名對映）。
    def type = "#{@item.item_type}_link"

    def url
      case @item.item_type
      when "http" then @item.url
      when "frontpage" then @url_prefix.presence || "/"
      when "search" then "#{@url_prefix}/search"
      when "catalog" then "#{@url_prefix}/collections/all"
      when "collections" then "#{@url_prefix}/collections"
      when "product" then "#{@url_prefix}/products/#{resource_handle(Product)}"
      when "collection" then "#{@url_prefix}/collections/#{resource_handle(Collection)}"
      when "page" then "#{@url_prefix}/pages/#{resource_handle(Page)}"
      when "blog" then "#{@url_prefix}/blogs/#{resource_handle(Blog)}"
      when "article" then article_url
      end
    end

    # 文章連結＝複合路徑（98 §1：/blogs/{blog}/{article}）。
    def article_url
      article = Article.includes(:blog).find_by(shop_id: @item.shop_id, id: @item.resource_id)
      article && "#{@url_prefix}/blogs/#{article.blog.handle}/#{article.handle}"
    end

    def links
      @links ||= @item.children.sort_by(&:position).map { |i| LinkDrop.new(i, url_prefix: @url_prefix, current_path: @current_path) }
    end

    private

    def normalize_path(path)
      p = path.to_s.split(/[?#]/).first.to_s
      p = p.chomp("/")
      p.empty? ? "/" : p
    end

    def resource_handle(klass)
      klass.where(shop_id: @item.shop_id, id: @item.resource_id).pick(:handle)
    end
  end

  class LinkListDrop < Liquid::Drop
    # 缺 handle 時的空選單（本尊 `{% if linklists[x] %}` 為真且 links 為空——hoko.vip footer 選單區塊輸出空 `<ul>`；
    # 本尊對不存在 handle 回什麼物件＝官方未取得，以此形對位，登記 V）
    EmptyMenu = Struct.new(:handle, :title) do
      def menu_items = []
    end

    def initialize(menu, url_prefix: "", current_path: nil)
      super()
      @menu = menu
      @url_prefix = url_prefix
      @current_path = current_path
    end

    def title = @menu.title
    def handle = @menu.handle
    # E8b：字串形＝handle（Ella `_blog-post-sidebar-category`：`block.settings.link_list | handleize` 再 `linklists[...]`；
    # hoko.vip /collections/all 側欄列出 main-menu 三項，我方先前 Drop#to_s 形 ⇒ 查無 ⇒ 空 `<ul>`）。本尊 linklist 的 to_s 是
    # handle 還是 title 未取得（預設選單兩者 handleize 同值），登記 V。
    def to_s = handle.to_s
    # E8b：`linklists[x] == empty`（Ella `_blog-post-sidebar-category`：`{%- if linklists[link.handle] == empty -%}` 決定有無子選單）——
    # hoko.vip /collections/all 側欄「首頁」無子選單 ⇒ 本尊對不存在 handle（`linklists['首頁']`）`== empty` 為真；Liquid 的 `== empty`
    # 走 `empty?`，Drop 未定義 ⇒ nil ⇒ 我方誤判有子選單（多出 has-subMenu／icon-dropdown）。無 links ⇒ empty。
    def empty? = links.empty?

    def links
      @links ||= @menu.menu_items.select { |i| i.parent_menu_item_id.nil? }
                      .sort_by(&:position)
                      .map { |i| LinkDrop.new(i, url_prefix: @url_prefix, current_path: @current_path) }
    end

    def levels = 3
  end

  class LinkListsDrop < Liquid::Drop
    def initialize(shop, url_prefix: "", current_path: nil)
      super()
      @shop = shop
      @url_prefix = url_prefix
      @current_path = current_path
    end

    def liquid_method_missing(name)
      menu = Menu.includes(:menu_items).find_by(shop_id: @shop.id, handle: name.to_s)
      return LinkListDrop.new(menu, url_prefix: @url_prefix, current_path: @current_path) if menu

      ThemeEngine.count_miss("linklists.#{name}")
      LinkListDrop.new(LinkListDrop::EmptyMenu.new(name.to_s, nil), url_prefix: @url_prefix, current_path: @current_path)
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
      # PR-8：locale 物件化（本尊 request.locale＝shop_locale 物件——
      # 裸字串令 `<html lang="{{ request.locale.iso_code }}">` 吐空）。
      # iso_code 輸出本尊碼（zh-Hans ⇒ zh-CN；hoko.vip `<html lang="zh-CN">`），內部 tag 不變（LocaleTags）
      locale_obj = locale.is_a?(Hash) ? locale : { "iso_code" => LocaleTags.shopify_code(locale), "primary" => true }
      super({ "design_mode" => design_mode, "visual_preview_mode" => false,
              "page_type" => page_type, "host" => host,
              "origin" => host ? "https://#{host}" : nil, "path" => path,
              "locale" => locale_obj })
    end
  end

  # cart drop：無買家車 ⇒ 恆空形（包 30 原 stub）；有 ⇒ 直餵
  # `Storefront::CartSerializer.cart_json`（金額 cents 直通；items＝hash 陣列，
  # Liquid 點取即鍵取——契約同 `/cart.js`，83 §3.3）。
  class CartDrop < BaseDrop
    # @param taxes_included [Boolean] 官方 cart.taxes_included "Returns true if taxes are included in the prices of
    #   products in the cart."——店級設定（shops.taxes_included；hoko.vip 稅注「已含税」⇒ true）
    # E8b：currency 物件帶 symbol／name（Ella price-facet `{{ cart.currency.symbol }}`：hoko.vip 輸出 `$`；先前只有 iso_code ⇒ 空）
    def initialize(currency:, cart_json: nil, taxes_included: false, money_format: nil)
      @money_format = money_format
      # 🔴 `duties_included` 必須**顯式 false**（第三包；86 §7 差距 #1）：Ella 的
      # tax-note 四分支用 `== false` 顯式比較（cart-drawer:380 等），Liquid 的
      # `nil == false` 為假 ⇒ 缺鍵時四分支全不命中、整段稅注（含「未含稅」文案）
      # 靜默空白。taxes_included 同理保持顯式（真值接 tax_settings 隨法域包）。
      if cart_json
        super(cart_json.merge("currency" => Currencies.drop_hash(cart_json["currency"], money_format: money_format),
                              "taxes_included" => taxes_included, "duties_included" => false,
                              "discount_applications" => []))
      else
        super({ "item_count" => 0, "items" => [], "total_price" => 0,
                "items_subtotal_price" => 0, "original_total_price" => 0,
                "total_discount" => 0, "note" => nil, "attributes" => {},
                "currency" => Currencies.drop_hash(currency, money_format: money_format),
                "cart_level_discount_applications" => [], "requires_shipping" => false,
                "taxes_included" => taxes_included, "duties_included" => false,
                "discount_applications" => [] })
      end
    end

    def empty? = @attrs["item_count"].to_i.zero?
  end

  # 🔴 反例①已修：語言資料由呼叫端供給（shop_locales；包 34 接真值鏈）。
  # 官方 objects/localization（external-facts §G22）。available_countries 由 `Storefront::LocalizationContext` 供給
  # （同網域 active 市場 regions 聯集，E15）；未給時退回「只有當前國」（Runtime 的無 presence 退路——預覽面／無市場店）。
  # E17：官方 `country` 物件的字串化＝國名（hoko.vip 2026-09-05 header_mobile 區段 fetch：Ella
  # `language-country-localization.liquid` `icon-flag--{{ localization.country }}` ⇒ `icon-flag--台湾`；我方先前是裸 Hash ⇒
  # 輸出 Hash#inspect）。其餘屬性同 LocalizationContext#country_hash（§G22）。
  class CountryDrop < BaseDrop
    def to_s = self["name"].to_s
  end

  class LocalizationDrop < BaseDrop
    def initialize(language:, available_languages:, country: nil, market: nil, available_countries: nil)
      super({ "language" => language, "country" => country, "market" => market,
              "available_countries" => available_countries || [ country ].compact,
              "available_languages" => available_languages })
    end
  end

  class TemplateDrop < BaseDrop
    # suffix：`?view=` 替代模板的 template-suffix（96 §6；官方 "identify which
    # template is currently being used with the `template` object"）。
    def initialize(name, suffix: nil)
      super({ "name" => name, "suffix" => suffix, "directory" => nil })
    end

    def to_s = @attrs["name"]
  end

  # 官方 `color` 物件（objects/color，取證 2026-09-03）：alpha＝0.0–1.0 小數；red／green／blue 0–255；hue 0–360；
  # saturation／lightness 0–100；`rgb`＝空白分隔；`rgba`＝空白分隔＋斜線後 alpha（官方例 "51 79 180 / 1.0"）；
  # 直接輸出＝設定原值（官方例為 hex）。
  # 渲染 1:1 對表（2026-09-03，hoko.vip 首頁 86 處 `rgb(0 0 0 / 0.0)`）：Ella settings_data 的透明色存成
  # `rgba(0,0,0,0)`（arrow_background 70／arrow_border 64／primary_button_background 49／background 33…），本尊照樣
  # 給 color 物件（alpha 0.0）；舊實作只認 hex ⇒ 這些值以字串進主題，`.rgba` 為 nil、`.alpha != 0.0` 判斷全錯。
  class ColorDrop < Liquid::Drop
    HEX_RE = /\A#?(\h\h)(\h\h)(\h\h)(\h\h)?\z/
    SHORT_HEX_RE = /\A#?(\h)(\h)(\h)\z/
    RGB_RE = /\Argba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)\z/i

    def self.color_like?(value)
      s = value.to_s.strip
      s.match?(HEX_RE) || s.match?(SHORT_HEX_RE) || s.match?(RGB_RE) || s.casecmp?("transparent")
    end

    # 色值物件與**原始字串**相等（本尊：Ella color-swatches `color_2 == 'rgba(0,0,0,0)'` 成立 ⇒ 輸出
    # `background: #1199bb`，hoko.vip 2026-09-03；我方原本走 gradient 分支）。`to_str` 讓 `'…' == drop`
    # （String#== 對 to_str 物件反向呼叫 ==）同樣成立。
    def ==(other)
      other.respond_to?(:to_str) ? to_s == other.to_str : (other.is_a?(ColorDrop) && to_s == other.to_s)
    end
    alias eql? ==
    def to_str = to_s
    def hash = to_s.hash

    def initialize(value)
      super()
      @raw = value.to_s
      s = @raw.strip
      @r, @g, @b, @a = 0, 0, 0, 1.0
      if (m = s.match(HEX_RE))
        @r, @g, @b = m.captures.first(3).map { |x| x.to_i(16) }
        @a = m[4] ? (m[4].to_i(16) / 255.0).round(2) : 1.0
      elsif (m = s.match(SHORT_HEX_RE))
        @r, @g, @b = m.captures.map { |x| (x * 2).to_i(16) }
      elsif (m = s.match(RGB_RE))
        @r, @g, @b = m.captures.first(3).map(&:to_i)
        @a = m[4] ? m[4].to_f : 1.0
      elsif s.casecmp?("transparent")
        @a = 0.0
      end
    end

    def red = @r
    def green = @g
    def blue = @b
    def alpha = @a
    def rgb = "#{@r} #{@g} #{@b}"
    def rgba = "#{@r} #{@g} #{@b} / #{@a.to_f}"
    def hex = format("#%02x%02x%02x", @r, @g, @b)
    def hue = hsl[0]
    def saturation = hsl[1]
    def lightness = hsl[2]
    def to_s = @raw

    private

    # HSL（0–360／0–100／0–100，四捨五入）——官方屬性語義；舊實作 hue／saturation 為 0 的佔位已換掉。
    def hsl
      @hsl ||= begin
        r, g, b = @r / 255.0, @g / 255.0, @b / 255.0
        max, min = [ r, g, b ].max, [ r, g, b ].min
        l = (max + min) / 2.0
        if max == min
          [ 0, 0, (l * 100).round ]
        else
          d = max - min
          sat = l > 0.5 ? d / (2.0 - max - min) : d / (max + min)
          h = if max == r then ((g - b) / d) % 6
          elsif max == g then (b - r) / d + 2
          else (r - g) / d + 4
          end
          [ ((h * 60) % 360).round, (sat * 100).round, (l * 100).round ]
        end
      end
    end
  end

  # 色階（步 13b；97 §3——official `color_scheme`：`id`＋`settings`；直接輸出＝id，
  # 官方範例 `{{ settings.card_color_scheme }}` → `background-2`）。
  class ColorSchemeDrop < Liquid::Drop
    def initialize(id:, settings:, types: {})
      super()
      @id = id
      @settings = SettingsDrop.new(settings, types, label: "color_scheme(#{id})")
    end

    def id = @id
    def settings = @settings
    def to_s = @id
  end

  # 色階群組（97 §3——official 迭代形 `{% for scheme in settings.color_schemes %}`）。
  # 取單個走 `scheme(id)`／liquid_method_missing（🔴 不覆寫 `[]`——12a 教訓：
  # Drop#key? 恆 true 會把屬性派發劫持掉）。
  class ColorSchemeGroupDrop < Liquid::Drop
    include Enumerable

    def initialize(value, definition: [])
      super()
      @value = value.is_a?(Hash) ? value : {}
      @types = definition.each_with_object({}) do |d, h|
        h[d["id"]] = d["type"] if d.is_a?(Hash) && d["id"]
      end
    end

    def each(&) = drops.each(&)
    def size = drops.size
    def first = drops.first

    # color_scheme 型 setting 的解引用點（SettingsDrop coerce 用）。
    def scheme(id)
      drops.find { |s| s.id == id.to_s }
    end

    def liquid_method_missing(name)
      scheme(name) || begin
        ThemeEngine.count_miss("color_scheme_group.#{name}")
        nil
      end
    end

    private

    def drops
      @drops ||= @value.map do |id, raw|
        settings = raw.is_a?(Hash) ? (raw["settings"] || raw) : {}
        ColorSchemeDrop.new(id: id.to_s, settings:, types: @types)
      end
    end
  end

  # `font` object（步 13a 真實作；97 §1.1 官方七屬性）。file＝自 host woff2 路徑
  # （system font nil ⇒ font_face 空輸出——97 §4-5）。baseline_ratio：官方無公開
  # 數值來源 ⇒ 常數 0.1 維持（ours；僅排版微調用）。
  class FontDrop < Liquid::Drop
    attr_reader :family_key, :file

    def initialize(family_key:, family:, fallback_families:, weight:, style:, file:, system:)
      super()
      @family_key = family_key
      @family = family
      @fallback = fallback_families
      @weight = weight
      @style = style
      @file = file
      @system = system
    end

    def family = @family
    def fallback_families = @fallback
    def weight = @weight
    def style = @style
    def system? = @system
    def baseline_ratio = 0.1
    def variants = FontLibrary.variants_for(@family_key)
    def to_s = @family
  end

  class ClosestDrop < Liquid::Drop
    def initialize(product: nil, collection: nil, article: nil, blog: nil, page: nil)
      super()
      @h = { "product" => product, "collection" => collection, "article" => article, "blog" => blog, "page" => page }
    end

    # 官方逐字（objects/closest，取證 2026-09-04，external-facts §G18）：closest 的來源之一＝"The currently rendered
    # template resource of the same type"，型別 "product, collection, article, blog, page, or metaobject"——由模板 assigns
    # 取同型資源（metaobject 模板我方未做，V）。先前只填 product ⇒ 集合頁 `<h1>{{ closest.collection.title }}</h1>` 解成空、
    # `{{ closest.collection.description }}` 留裸字串（e8 §2b #55／#56）。
    def self.from_template(assigns)
      new(**%w[product collection article blog page].to_h { |k| [ k.to_sym, assigns[k] ] })
    end

    # content_for "block" 的 `closest.*` 覆寫層（步 12a-fix）：base 的既有值保留、
    # overrides 非 nil 者蓋上；未知鍵照收（liquid_method_missing 直讀 @h）。
    # 經 send 取私有 @h——不開 public reader，Liquid 只派發 public 方法，
    # 主題代碼拿不到整個 hash。
    def self.merged(base, overrides)
      merged = base.is_a?(ClosestDrop) ? base.send(:attrs).dup : {}
      overrides.each { |key, value| merged[key.to_s] = value unless value.nil? }
      drop = new
      drop.send(:attrs=, merged)
      drop
    end

    def liquid_method_missing(name)
      @h.fetch(name.to_s) do
        ThemeEngine.count_miss("closest.#{name}")
        nil
      end
    end

    private

    def attrs = @h

    def attrs=(value)
      @h = value
    end
  end

  # paginate.parts 的單一分頁件（official part：title/url/is_link）。
  class PartDrop < BaseDrop
    def initialize(title:, url: nil, is_link: false)
      super({ "title" => title.to_s, "url" => url, "is_link" => is_link })
    end
  end

  # 真分頁 drop（步 12；96 §1 paginate 契約）。items＝總數、pages＝ceil、
  # parts＝窗式分頁列（頁數多時首尾＋當前±1＋省略號——窗形是 ours，官方演算法
  # 未逐字記載）。url_builder：page N → 帶 page 參數的當前路徑 URL。
  class PaginateDrop < BaseDrop
    def initialize(items: 0, page_size: 24, current_page: 1, url_builder: nil)
      pages = [ (items.to_f / page_size).ceil, 1 ].max
      build = url_builder || ->(_n) { nil }
      super({
        "current_page" => current_page,
        "current_offset" => (current_page - 1) * page_size,
        "items" => items,
        "parts" => build_parts(pages, current_page, build),
        "next" => current_page < pages ? PartDrop.new(title: "&raquo;", url: build.call(current_page + 1), is_link: true) : nil,
        "previous" => current_page > 1 ? PartDrop.new(title: "&laquo;", url: build.call(current_page - 1), is_link: true) : nil,
        "page_size" => page_size,
        "pages" => pages,
        "page_param" => "page"
      })
    end

    private

    def build_parts(pages, current, build)
      return [] if pages <= 1

      numbers = if pages <= 7
        (1..pages).to_a
      else
        ([ 1, pages, current - 1, current, current + 1 ].select { |n| n.between?(1, pages) }).uniq.sort
      end
      parts = []
      numbers.each_with_index do |n, i|
        parts << PartDrop.new(title: "&hellip;") if i.positive? && n > numbers[i - 1] + 1
        parts << (n == current ? PartDrop.new(title: n) : PartDrop.new(title: n, url: build.call(n), is_link: true))
      end
      parts
    end
  end

  # `form`（官方 objects/form，取證 2026-09-02）：**屬性依 `{% form %}` 型別宣告**，
  # 只有未宣告的鍵才計 miss（D78 conformance 的 `FormDrop.*` 假缺口由此消失）。
  # ①值＝上次提交失敗後的回填（v1 無提交回填 ⇒ 一律 nil；主題以 `{% if form.email %}` 守）。
  # ②`password_needed`：官方逐字 "Returns `true`."（customer_login 專屬）——
  #   原實作未宣告 ⇒ nil ⇒ Ella／Kalles 登入表單的 `{%- if form.password_needed -%}`
  #   整段密碼欄不渲染（triage 已驗證缺口）。
  # ③`posted_successfully?`：官方 "Returns `true` if the form was submitted successfully.
  #   Returns `false` if there were errors."；純 GET 渲染時為 false——真店 hoko.vip
  #   `/pages/contact`（2026-09-02）Ella `{%- if form.posted_successfully? -%}` 的成功訊息
  #   未輸出。官方另逐字 "`customer_address` form always returns `true`"。
  # ④`errors`：官方 "If there are no errors, then `nil` is returned."
  # ⑤`set_as_default_checkbox` 官方語義是「渲染一個 checkbox」，其 HTML 形＝未取得
  #   （customers/* 未路由、真店走新版帳戶不出主題表單）⇒ 先宣告為 nil，不猜 markup。
  class FormDrop < BaseDrop
    # 官方 objects/form 每個屬性的「Exclusive to … forms」逐字對映。
    FIELDS = {
      "contact" => %w[email body],
      "create_customer" => %w[email first_name last_name],
      "customer" => %w[email],
      "customer_address" => %w[address1 address2 city company country first_name last_name phone
                               province zip set_as_default_checkbox],
      "customer_login" => %w[email password_needed],
      "new_comment" => %w[author body email],
      "product" => %w[email message name],
      "recover_customer_password" => %w[email]
    }.freeze

    def initialize(type = "contact", id: nil)
      attrs = { "errors" => nil, "posted_successfully?" => type == "customer_address", "id" => id }
      FIELDS.fetch(type, []).each { |field| attrs[field] = nil }
      attrs["password_needed"] = true if type == "customer_login"
      super(attrs)
    end
  end

  # settings（schema 型別感知強轉；25 坑 #6——color 必須是 color 物件）。
  # E17：`url` 型 setting 的值物件。本尊（hoko.vip 2026-09-05 header_mobile 區段 fetch）：Ella `blocks/_menu-tab-item.liquid`
  # `assign link = bl_stts.link` ⇒ `{% if link != blank %}href="{{ link.url }}"` 對 `"#"` 出 `href="#"`、對
  # `https://1.envato.market/dokaB2` 出該 URL ⇒ 值同時是字串（`{{ link }}`）也回應 `.url`（官方 input-settings 只說
  # "data is returned as a string"；`.url` 可用＝實測）。空值 ⇒ nil（`!= blank` 為假 ⇒ 本尊同段輸出 `role="link" aria-disabled="true"`）。
  # 我方先前回裸字串 ⇒ `.url` 為 nil ⇒ `href=""`（外部連結整個失效）。
  class UrlSettingDrop < Liquid::Drop
    def initialize(value)
      super()
      @value = value.to_s
    end

    def url = @value
    def to_s = @value
    def to_str = @value
  end

  class SettingsDrop < Liquid::Drop
    # schemes：色階群組 drop（步 13b）——`color_scheme` 型 setting 解引用用；
    #   nil＝無群組語境（值原樣回 id 字串，to_s 語義相同）。
    def initialize(values, types = {}, label: "settings", schemes: nil)
      super()
      @v, @t, @label = values || {}, types, label
      @schemes = schemes
    end

    # 資源型 setting（官方 input-settings）："blank if no selection has been made"——值**根本不存在**（無 default、
    # JSON 未給，靜態 block 常態）時同樣回空字串，不是 nil（hoko.vip product-grid 靜態卡 `card_product.featured_media`
    # 為真 ⇒ `card--media`）。其他型別維持「缺鍵 ⇒ nil」。
    RESOURCE_TYPES = %w[product collection page blog product_list collection_list].freeze

    def liquid_method_missing(name)
      k = name.to_s
      unless @v.key?(k)
        return coerce(k, nil) if RESOURCE_TYPES.include?(type_name_of(k))

        ThemeEngine.count_miss("#{@label}.#{k}")
        return nil
      end
      coerce(k, @v[k])
    end

    def type_name_of(key)
      entry = @t[key]
      (entry.is_a?(Hash) ? entry["type"] : entry).to_s
    end

    private

    # @t 值通常是型別字串；`color_scheme_group` 存整個 def（definition 子 schema
    # 是 scheme.settings 的型別來源——runtime.extract_types 同批改）。
    # @context 由 Liquid 渲染期注入（drop.context=）；無 context（單元測試）
    # ⇒ 直接佔位。查找走 Runtime#resolve_settings_file（帶 shop 語境）。
    def resolve_settings_image(val)
      rt = @context&.registers&.[](:runtime)
      file = rt.respond_to?(:resolve_settings_file) ? rt&.resolve_settings_file(val) : nil
      return FileImageDrop.new(file) if file

      PlaceholderImageDrop.new(label: File.basename(val.to_s), w: 1200, h: 800)
    end

    def coerce(key, val)
      type_entry = @t[key]
      type_name = type_entry.is_a?(Hash) ? type_entry["type"] : type_entry
      case type_name
      when "color", "color_background"
        return nil if val.nil? || val == ""

        # hex／rgba()／transparent 都是 color 物件（Ella 透明色存 `rgba(0,0,0,0)`）；漸層字串（color_background）原樣
        ColorDrop.color_like?(val) ? ColorDrop.new(val) : val
      when "image_picker"
        # 空值＝nil（官方契約：blank image setting 回 nil——除零診斷實錘，勿改）。
        # 非空 ⇒ 先解析檔案庫（shopify://shopify/files/{name} 或裸檔名 →
        # StoredFile by filename），命中出真圖 drop；未命中退佔位（PR-2）。
        return nil if val.nil? || val == ""

        resolve_settings_image(val)
      when "font_picker" then FontLibrary.drop(val) # 步 13a：handle → 真 font drop（97 §1）
      # 資源型 setting：值是 handle 字串，主題以物件消費（`bl_stts.collection.products`、`card_product != empty`）。
      # 官方逐字（input-settings，2026-09-03）：product／collection／page／blog 回物件，"blank if no selection has been
      # made, the selection isn't visible, or the selection no longer exists"；product_list／collection_list 回陣列。
      # 「blank」有兩種實測形（hoko.vip 首頁）：**未選**（setting 無值）⇒ 空字串——無商品的 card-product-flex 靜態卡
      # `card_product.featured_media` 仍為真 ⇒ `card--media`、`{{ card_product.id }}` 空、`media | json` ⇒ `""`；
      # **已選但查無**（lookbook 點位 `product: 'draped-mock-neck-tee'`）⇒ nil——`card_product == empty` 走 else、
      # `media | json` ⇒ `null`。原本回裸 handle 字串。
      when "product" then resolve_resource("all_products", val)
      when "collection" then resolve_resource("collections", val)
      when "page" then resolve_resource("pages", val)
      when "blog" then resolve_resource("blogs", val)
      when "product_list" then resolve_resource_list("all_products", val)
      when "collection_list" then resolve_resource_list("collections", val)
      when "link_list"
        # E3c：`link_list` 型 setting 回 linklist 物件（Ella header：`header_settings.menu.links`），
        # 不是 handle 字串——原本回字串 ⇒ `.links` 為 nil ⇒ 整條主選單空白（demo 店 2026-09-03 實錘）。
        # 走 `linklists` 全域 drop 查（同一 shop 語境與 url 前綴）；空值或查無 ⇒ nil（for 迴圈自然為空）。
        return nil if val.nil? || val == ""

        @context&.[]("linklists")&.liquid_method_missing(val.to_s)
      when "url"
        val.nil? || val.to_s == "" ? nil : UrlSettingDrop.new(val) # E17
      when "video_url"
        # 官方：空 ⇒ nil；非空 ⇒ URL 字串＋id/type（PR-16；解析不出 host 的
        # 值一樣回 nil——不可播的 URL 對主題等同未填）
        val.to_s.empty? ? nil : VideoUrlDrop.parse(val)
      when "color_scheme_group"
        ColorSchemeGroupDrop.new(val, definition: type_entry.is_a?(Hash) ? (type_entry["definition"] || []) : [])
      when "color_scheme"
        # official："returns the selected color_scheme object from color_scheme_group"；
        # 三段退回（input-settings 逐字，取證 2026-09-02）："If no value was entered, or the value
        # was invalid, then the default value from `color_scheme` is returned. If the default value
        # is also invalid, then the first `color_scheme` from `color_scheme_group` is returned."
        # 無群組語境（@schemes nil）⇒ 值原樣（既有語義）。
        return val unless @schemes

        default = type_entry.is_a?(Hash) ? type_entry["default"] : nil
        @schemes.scheme(val.to_s) || (default && @schemes.scheme(default.to_s)) || @schemes.first || val
      else val
      end
    end
  end

  class BlockDrop < Liquid::Drop
    attr_reader :key, :type, :settings_hash, :data, :path, :section_id

    # children：巢狀子 block drops（步 13b；官方 ≤8 層）——Ella
    # `{% for child_block in block.blocks %}{% render child_block %}` 消費形。
    # instance_id：本尊形 `{A+17 碼}__{key}`（BlockIds；渲染 1:1）——`block.id` 與 `shopify-block-{id}` 同值；
    # key：JSON 裸鍵（編輯器橋 `data-shopify-editor-block` 與 `cl:*` 契約以 key 定址）。
    def initialize(id:, type:, settings:, types:, data:, design_mode: false,
                   children: [], schemes: nil, instance_id: nil, path: nil, section_id: nil)
      super()
      @key, @type, @data = id, type, data
      @instance_id = instance_id
      @path = path || [ id ]
      @section_id = section_id
      @settings_hash = settings
      @settings = SettingsDrop.new(settings, types, label: "block(#{type})", schemes:)
      @design_mode = design_mode
      @children = children
    end

    def settings = @settings
    def blocks = @children
    # 官方 block.id；本尊實例形（見 BlockIds）。無 instance_id（測試直建 drop）⇒ 裸 key。
    def id = @instance_id || @key

    def shopify_attributes
      return "" unless @design_mode

      %(data-shopify-editor-block='#{JSON.generate(id: @key, type: @type)}')
    end

    def to_s = ""
  end

  class SectionDrop < Liquid::Drop
    attr_reader :id

    # @param index [Integer, nil] 官方 section.index（1-based，within its location）；nil＝static／編輯器／SRA。
    # @param location [String] 官方 section.location：template／群組 type／static／content_for_index。
    def initialize(id:, data:, types:, blocks: [], schemes: nil, index: nil, location: "template")
      super()
      @id, @data = id, data
      @settings = SettingsDrop.new(data["settings"] || {}, types, label: "section(#{data['type']})", schemes:)
      @blocks = blocks
      @index = index
      @location = location
    end

    # E19：section 檔名（`sections/{type}.liquid`）——content_for_header 的 sections-script data-sections 記錄用
    def type = @data["type"]

    def settings = @settings
    def blocks = @blocks
    # 官方逐字（2026-09-03）："The 1-based index of the current section within its location." ／
    # index0："This is the same as the index property except that the index starts at 0 instead of 1."
    # Ella 以 `section.index == nil` 判定「非整頁渲染 ⇒ 改走 section fetch」（before-you-leave／header_mobile），
    # 故整頁必須給值、SRA／編輯器必須 nil（hoko.vip：slideshow `data-index="1"`、before-you-leave
    # `data-section-fetch="false"`）。
    def index = @index
    def index0 = @index && @index - 1
    def location = @location

    def liquid_method_missing(name)
      ThemeEngine.count_miss("section.#{name}")
      nil
    end
  end

  # SettingsDrop 資源解析（放在 SectionDrop 之後以維持檔內順序；方法屬 SettingsDrop）
  class SettingsDrop
    private

    BLANK_RESOURCE = ""

    # 動態來源（`"product": "{{ closest.product }}"`，Ella 靜態商品卡）已由 resolve_dynamic 換成物件——drop／陣列**原樣透傳**；
    # 解成非資源純量（本尊 product-grid 以整數當 closest.product）⇒ 官方 "blank"（空字串）：卡片 `card--media`、
    # `{{ card_product.id }}` 空、`media | json` ⇒ `""`（hoko.vip）。
    def resolve_resource(global, val)
      return val if val.is_a?(Liquid::Drop) || val.is_a?(Array)
      return BLANK_RESOURCE unless val.nil? || val.is_a?(String)

      handle = val.to_s.strip
      return BLANK_RESOURCE if handle.empty? # 未選

      drop = @context&.[](global)
      return nil unless drop.respond_to?(:liquid_method_missing)

      drop.liquid_method_missing(handle).presence # 已選但查無 ⇒ nil
    end

    def resolve_resource_list(global, val)
      Array(val).filter_map do |handle|
        resolved = resolve_resource(global, handle)
        resolved == BLANK_RESOURCE ? nil : resolved
      end
    end
  end
end
