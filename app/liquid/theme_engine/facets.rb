# frozen_string_literal: true

module ThemeEngine
  # Ella 修復 PR-20：storefront filtering（facets）v1——91 §3.61 收口。
  #
  # ①這是什麼：collection 頁的 `collection.filters` 生成器＋商品列表過濾器。
  #   官方契約（shopify.dev objects/filter・filter_value，取證 2026-09-02）：
  #   filter＝label/param_name/type(boolean|list|price_range)/values/
  #   active_values/min_value/max_value/range_max/operator/url_to_remove；
  #   filter_value＝label/value/param_name/count/active/url_to_add/url_to_remove。
  # ②v1 過濾器集合（ours：全開，管理面配置隨後續包）：
  #   availability(boolean)／price(price_range)／變體選項(list, per option)／
  #   vendor(list)／product_type(list)。
  #   param 形：`filter.v.option.{name}`＝官方逐字例；availability/price/vendor/
  #   product_type 的精確字串官方頁未逐字列出（V）——採本尊已知形
  #   `filter.v.availability`/`filter.v.price.gte|lte`/`filter.p.vendor`/
  #   `filter.p.product_type`；主題端由 param_name 自我一致（Ella 表單 name
  #   取自 drop）。
  # ③🔴 單位邊界（鐵律 3）：price 的 URL 參數值＝主單位十進位（Ella price-facet
  #   以 `money_without_currency` 填 input）；drop 的 `min_value.value`＝
  #   integer cents（Ella `| money` 直餵）——換算只在 parse 層一處。
  # ④多值語義：同名參數重複＝OR（官方 operator 預設 OR）；跨過濾器＝AND。
  #   🔴 多值必須從 query string 解析（Rack parse_query 保留重複鍵）；
  #   Rails params hash 對重複裸鍵 last-wins 會靜默丟值。
  # ⑤counts：各 list/boolean 值的 count＝「套用其他過濾器後」的結果數
  #   （標準 faceting；官方句「number of results related to the filter value」
  #   未細到口徑＝V）。range_max＝未過濾集合的最高「商品最低價」（官方
  #   "highest product price within the collection"；以 min variant price 代
  #   商品價＝ours，與列表卡價一致）。
  class Facets
    AVAILABLE_SQL = <<~SQL.squish
      EXISTS (
        SELECT 1 FROM product_variants fpv
        LEFT JOIN inventory_items fii ON fii.product_variant_id = fpv.id
        WHERE fpv.product_id = products.id AND (
          fii.id IS NULL OR fii.tracked = FALSE OR fpv.inventory_policy = 'continue'
          OR (SELECT COALESCE(SUM(fil.available), 0) FROM inventory_levels fil
              WHERE fil.inventory_item_id = fii.id) > 0
        )
      )
    SQL
    MIN_PRICE_SQL = "(SELECT MIN(fp.price_cents) FROM product_variants fp WHERE fp.product_id = products.id)"

    P_AVAIL = "filter.v.availability"
    P_PRICE_GTE = "filter.v.price.gte"
    P_PRICE_LTE = "filter.v.price.lte"
    P_VENDOR = "filter.p.vendor"
    P_TYPE = "filter.p.product_type"
    OPTION_PREFIX = "filter.v.option."

    # @param base_relation [ActiveRecord::Relation] 未過濾的系列商品集合
    # @param query_string [String] 原始 query（多值解析＋URL 重建的唯一來源）
    # @param path [String] 帶前綴的當前頁路徑（url_to_add/remove 的 base）
    # 平台篩選字串（本尊 `filter.label`／`value.label` 為平台翻譯，非主題字串）：hoko.vip zh-CN 實測 legend「供貨情況」、
    # 值「现货」「缺货」、Price「價格」（2026-09-03 快照）；Brand／Product type 的 zh 值未取得（V，91 §3.75b）。
    STRINGS = {
      "en" => { availability: "Availability", in_stock: "In stock", out_of_stock: "Out of stock", price: "Price", brand: "Brand", product_type: "Product type" },
      "zh" => { availability: "供貨情況", in_stock: "现货", out_of_stock: "缺货", price: "價格", brand: "Brand", product_type: "Product type" }
    }.freeze

    # E8b：預設只出 availability＋price（hoko.vip 新店 /collections/all 只有 `filter.v.availability`／`filter.v.price.*`；
    # 官方 help：Availability／Category／Price／Product type／Tags／Vendor 為 "available to all stores"，由 Search & Discovery
    # 「Add filter」啟用——我方尚無該設定面，先以 `enabled` 參數控制，預設集合登記 V（91 §3.75b）。
    DEFAULT_ENABLED = %w[availability price].freeze
    ALL_FILTERS = %w[availability price options vendor product_type].freeze

    # 啟用清單來源＝`shops.storefront_filters`（Search & Discovery「Add filter」的儲存位；設定面未做，91 §3.75b V）。
    # nil／空 ⇒ 新店預設 availability＋price（hoko.vip 實測）；未知鍵忽略。
    def self.enabled_for(shop)
      list = Array(shop&.storefront_filters).map(&:to_s) & ALL_FILTERS
      list.presence || DEFAULT_ENABLED
    end

    def initialize(base_relation:, query_string: "", path: "/", locale: nil, enabled: DEFAULT_ENABLED)
      @enabled = Array(enabled).map(&:to_s)
      @strings = STRINGS.fetch(locale.to_s.split(/[-_]/).first.to_s.downcase, STRINGS["en"])
      @base = base_relation
      @path = path
      @pairs = Rack::Utils.parse_query(query_string.to_s)
                          .flat_map { |k, v| Array(v).map { |one| [ k, one.to_s ] } }
    end

    def filters
      @filters ||= build_filters
    end

    # 套用全部啟用中的過濾條件（跨過濾器 AND、同過濾器 OR）
    def apply(relation) = apply_except(relation, nil)

    def active? = @pairs.any? { |k, _| k.start_with?("filter.") }

    private

    def values_for(key) = @pairs.filter_map { |k, v| v if k == key && !v.empty? }

    def option_selections
      @option_selections ||= @pairs.each_with_object({}) do |(k, v), acc|
        next unless k.start_with?(OPTION_PREFIX) && !v.empty?

        (acc[k.delete_prefix(OPTION_PREFIX)] ||= []) << v
      end
    end

    def price_cents(key)
      raw = values_for(key).first
      return nil if raw.nil?

      (BigDecimal(raw) * 100).to_i
    rescue ArgumentError
      nil
    end

    # skip：計 counts 時排除「自己」（標準 faceting——自家值互斥不自我歸零）
    def apply_except(relation, skip)
      rel = relation
      rel = rel.where(AVAILABLE_SQL) if skip != :availability && values_for(P_AVAIL).include?("1")
      unless skip == :price
        gte = price_cents(P_PRICE_GTE)
        lte = price_cents(P_PRICE_LTE)
        rel = rel.where("#{MIN_PRICE_SQL} >= ?", gte) if gte
        rel = rel.where("#{MIN_PRICE_SQL} <= ?", lte) if lte
      end
      vendors = values_for(P_VENDOR)
      rel = rel.where(vendor: vendors) if skip != :vendor && vendors.any?
      types = values_for(P_TYPE)
      rel = rel.where(product_type: types) if skip != :product_type && types.any?
      option_selections.each do |name, vals|
        next if skip == [ :option, name ]

        rel = rel.where(<<~SQL.squish, name, vals)
          EXISTS (SELECT 1 FROM product_options fo JOIN option_values fov
                  ON fov.product_option_id = fo.id
                  WHERE fo.product_id = products.id AND fo.name = ? AND fov.value IN (?))
        SQL
      end
      rel
    end

    def build_filters
      list = []
      list << availability_filter if @enabled.include?("availability")
      list << price_filter if @enabled.include?("price")
      option_names.each { |name| list << option_filter(name) } if @enabled.include?("options")
      list << list_filter(label: @strings[:brand], key: :vendor, param: P_VENDOR, column: :vendor) if @enabled.include?("vendor")
      list << list_filter(label: @strings[:product_type], key: :product_type, param: P_TYPE, column: :product_type) if @enabled.include?("product_type")
      list.compact
    end

    def availability_filter
      scoped = apply_except(@base, :availability)
      total = scoped.distinct.count(:id)
      in_stock = scoped.where(AVAILABLE_SQL).distinct.count(:id)
      active = values_for(P_AVAIL).include?("1")
      values = [
        FacetValueDrop.new(label: @strings[:in_stock], value: "1", param_name: P_AVAIL,
                           count: in_stock, active: active, facets: self),
        FacetValueDrop.new(label: @strings[:out_of_stock], value: "0", param_name: P_AVAIL,
                           count: total - in_stock, active: false, facets: self)
      ]
      FacetFilterDrop.new(
        label: @strings[:availability], param_name: P_AVAIL, type: "boolean", facets: self,
        values: zero_count_last(values))
    end

    # E8b：count 0 的值排最後——hoko.vip /collections/all 出「现货(1)、缺货(2)」、/collections/frontpage 出「缺货(1)、现货(0)」
    # （现货 0 個時退到後面，Ella 印成 disabled）；官方排序規則未取得（91 §3.75b V），只套 availability。
    def zero_count_last(values) = values.each_with_index.sort_by { |v, i| [ v.count.to_i.zero? ? 1 : 0, i ] }.map(&:first)

    def price_filter
      range_max = @base.maximum(Arel.sql(MIN_PRICE_SQL)) || 0
      FacetFilterDrop.new(
        label: @strings[:price], param_name: "filter.v.price", type: "price_range", facets: self,
        range_max: range_max,
        min_value: FacetValueDrop.new(label: "From", value: price_cents(P_PRICE_GTE),
                                      param_name: P_PRICE_GTE, facets: self),
        max_value: FacetValueDrop.new(label: "To", value: price_cents(P_PRICE_LTE),
                                      param_name: P_PRICE_LTE, facets: self))
    end

    def option_names
      @option_names ||= @base.joins("INNER JOIN product_options fon ON fon.product_id = products.id")
                             .distinct.pluck(Arel.sql("fon.name")).sort
    end

    def option_filter(name)
      param = "#{OPTION_PREFIX}#{name}"
      scoped = apply_except(@base, [ :option, name ])
      counts = scoped.joins("INNER JOIN product_options fo ON fo.product_id = products.id")
                     .joins("INNER JOIN option_values fov ON fov.product_option_id = fo.id")
                     .where("fo.name = ?", name)
                     .group(Arel.sql("fov.value")).distinct.count(:id)
      selected = option_selections[name] || []
      values = counts.keys.sort.map do |value|
        FacetValueDrop.new(label: value, value: value, param_name: param,
                           count: counts[value], active: selected.include?(value), facets: self)
      end
      FacetFilterDrop.new(label: name, param_name: param, type: "list", facets: self, values: values)
    end

    def list_filter(label:, key:, param:, column:)
      scoped = apply_except(@base, key)
      counts = scoped.where.not(column => [ nil, "" ]).group(column).distinct.count(:id)
      return nil if counts.empty?

      selected = values_for(param)
      values = counts.keys.sort_by(&:downcase).map do |value|
        FacetValueDrop.new(label: value, value: value, param_name: param,
                           count: counts[value], active: selected.include?(value), facets: self)
      end
      FacetFilterDrop.new(label: label, param_name: param, type: "list", facets: self, values: values)
    end

    # ---- URL 重建（官方：add/remove 皆去分頁參數；sort_by 保留）----------
    public

    def url_with(pairs)
      kept = pairs.reject { |k, _| k == "page" }
      kept.empty? ? @path : "#{@path}?#{Rack::Utils.build_query(kept)}"
    end

    def current_pairs = @pairs.reject { |k, _| k == "page" }

    def url_to_add(param, value)
      url_with(current_pairs + [ [ param, value.to_s ] ])
    end

    def url_to_remove_value(param, value)
      url_with(current_pairs.reject { |k, v| k == param && v == value.to_s })
    end

    def url_to_remove_filter(param)
      url_with(current_pairs.reject { |k, _| k == param || k.start_with?("#{param}.") })
    end
  end

  # 官方 filter 物件（objects/filter 逐字屬性面；operator v1 恆 OR）
  class FacetFilterDrop < Liquid::Drop
    def initialize(label:, param_name:, type:, facets:, values: [],
                   min_value: nil, max_value: nil, range_max: nil)
      super()
      @label, @param_name, @type, @facets = label, param_name, type, facets
      @values = values
      @min_value, @max_value, @range_max = min_value, max_value, range_max
    end

    attr_reader :label, :param_name, :type, :range_max, :min_value, :max_value, :values

    def operator = "OR"
    def active_values = @values.select(&:active)
    def inactive_values = @values.reject(&:active)
    def true_value = @type == "boolean" ? @values.first : nil
    def false_value = @type == "boolean" ? @values.last : nil
    def presentation = @type == "list" ? "text" : nil
    def url_to_remove = @facets.url_to_remove_filter(@param_name)

    def liquid_method_missing(name)
      ThemeEngine.count_miss("filter.#{name}")
      nil
    end
  end

  # 官方 filter_value 物件（objects/filter_value 逐字屬性面）
  class FacetValueDrop < Liquid::Drop
    def initialize(label:, value:, param_name:, facets:, count: nil, active: false)
      super()
      @label, @value, @param_name, @count, @active, @facets = label, value, param_name, count, active, facets
    end

    attr_reader :label, :value, :param_name, :count

    def active = @active
    def url_to_add = @facets.url_to_add(@param_name, @value)
    def url_to_remove = @facets.url_to_remove_value(@param_name, @value)
    def image = nil
    def swatch = nil

    def liquid_method_missing(name)
      ThemeEngine.count_miss("filter_value.#{name}")
      nil
    end
  end
end
