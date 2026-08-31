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
        @v.option_values.sort_by { |ov| ov.product_option_id }.map(&:value)
      rescue StandardError
        []
      end
    end

    def option1 = options[0]
    def option2 = options[1]
    def option3 = options[2]
    # A′2：變體專圖（media.product_variant_id）優先，無則回退商品首圖。
    def featured_image = own_image || @product.featured_image
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
    # @param selected_variant_id [Integer, nil] `?variant=` URL 參數（缺口分析 A2）；
    #   nil＝無選中（selected_variant 回 nil、selected_or_first… 走 first available）。
    # @param publication [Publication, nil] 渲染管道（A′5 collections 過濾與
    #   published_at 的上下文）；nil＝無管道語境（collections 回空、published_at nil）。
    attr_reader :selected_variant_id

    # @param translations [Hash] 內容翻譯 overlay（包 34；67 §F.3(c) 走 drops 不走 t）：
    #   field_key => 譯文，由 PageRenderer 以 Translations::Resolve **一次批載**。
    #   空 hash＝來源語言／無譯文 ⇒ 直讀 base row。handle 不在值域（不可翻，§D.3）。
    def initialize(product, url_prefix: "", selected_variant_id: nil, publication: nil,
                   translations: {})
      @selected_variant_id = selected_variant_id
      @publication = publication
      super()
      @p = product
      @url_prefix = url_prefix
      @tx = translations || {}
    end

    def id = @p.id
    def title = @tx["title"] || @p.title
    def handle = @p.handle
    def vendor = @p.vendor
    def type = @p.product_type
    def tags = @p.tags.to_a
    def description = @tx["body_html"] || @p.description_html
    def content = description
    def url = "#{@url_prefix}/products/#{@p.handle}"

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

    def media = images
    def media_count = images.size
    def featured_image = images.first || PlaceholderImageDrop.new(label: title)
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
        ids = CollectionMembership.where(shop_id: @p.shop_id, product_id: @p.id)
                                  .select(:collection_id)
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
    # translations：同 ProductDrop 的 overlay 契約（包 34）。
    def initialize(collection, url_prefix: "", published_at: nil, translations: {})
      super()
      @c = collection
      @url_prefix = url_prefix
      @published_at = published_at
      @tx = translations || {}
    end

    def id = @c.id
    def title = @tx["title"] || @c.title
    def handle = @c.handle
    def description = @tx["body_html"] || @c.description_html
    def url = "#{@url_prefix}/collections/#{@c.handle}"
    def published_at = @published_at

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

  # cart drop：無買家車 ⇒ 恆空形（包 30 原 stub）；有 ⇒ 直餵
  # `Storefront::CartSerializer.cart_json`（金額 cents 直通；items＝hash 陣列，
  # Liquid 點取即鍵取——契約同 `/cart.js`，83 §3.3）。
  class CartDrop < BaseDrop
    def initialize(currency:, cart_json: nil)
      # 🔴 `duties_included` 必須**顯式 false**（第三包；86 §7 差距 #1）：Ella 的
      # tax-note 四分支用 `== false` 顯式比較（cart-drawer:380 等），Liquid 的
      # `nil == false` 為假 ⇒ 缺鍵時四分支全不命中、整段稅注（含「未含稅」文案）
      # 靜默空白。taxes_included 同理保持顯式（真值接 tax_settings 隨法域包）。
      if cart_json
        super(cart_json.merge("currency" => { "iso_code" => cart_json["currency"] },
                              "taxes_included" => false, "duties_included" => false,
                              "discount_applications" => []))
      else
        super({ "item_count" => 0, "items" => [], "total_price" => 0,
                "items_subtotal_price" => 0, "original_total_price" => 0,
                "total_discount" => 0, "note" => nil, "attributes" => {},
                "currency" => { "iso_code" => currency },
                "cart_level_discount_applications" => [], "requires_shipping" => false,
                "taxes_included" => false, "duties_included" => false,
                "discount_applications" => [] })
      end
    end

    def empty? = @attrs["item_count"].to_i.zero?
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
