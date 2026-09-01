# frozen_string_literal: true

module Content
  # 選單樹寫入（步 14a；98 §3——官方 menuUpdate＝**整棵替換不是合併**）。
  #
  # ①交易內：清舊項 → 依輸入樹重建（position＝陣列序；巢狀 ≤3 層官方上限）。
  # ②項型驗證：http 需 url；資源型（product/collection/page/blog/article）需
  #   resource_id；靜態型（frontpage/search/catalog/collections）兩者皆免。
  # ③resource GID 解析帶 shop_id 條件（鐵律 2③）。
  class SaveMenu
    MAX_DEPTH = 3 # 官方 "There's a maximum of 3 levels."

    RESOURCE_MODELS = {
      "product" => -> { Product }, "collection" => -> { Collection },
      "page" => -> { Page }, "blog" => -> { Blog }, "article" => -> { Article }
    }.freeze
    STATIC_TYPES = %w[frontpage search catalog collections].freeze

    Result = Struct.new(:menu, :error, keyword_init: true)

    def self.call(shop:, menu:, title:, handle:, items:)
      new(shop:, menu:, title:, handle:, items:).call
    end

    def initialize(shop:, menu:, title:, handle:, items:)
      @shop, @menu = shop, menu
      @title, @handle, @items = title, handle, items
    end

    def call
      error = validate_tree(@items, depth: 1)
      return Result.new(error:) if error

      ActiveRecord::Base.transaction do
        @menu ||= Menu.new(shop_id: @shop.id)
        @menu.assign_attributes(title: @title, handle: @handle)
        @menu.save!
        @menu.menu_items.destroy_all
        build_items(@items, parent: nil)
      end
      Result.new(menu: @menu.reload)
    rescue ActiveRecord::RecordNotUnique
      Result.new(error: [ "handle", "此 handle 已被使用。", "TAKEN" ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(error: [ nil, e.record.errors.full_messages.first.to_s, "INVALID" ])
    end

    private

    def validate_tree(items, depth:)
      return [ "items", "選單巢狀超過 #{MAX_DEPTH} 層上限。", "NESTING_TOO_DEEP" ] if depth > MAX_DEPTH

      items.each do |item|
        type = item[:type].to_s
        if type == "http" && item[:url].blank?
          return [ "items", "http 型項目必須帶 url（#{item[:title]}）。", "BLANK" ]
        end
        if RESOURCE_MODELS.key?(type) && resolve_resource(type, item[:resource_id]).nil?
          return [ "items", "找不到資源（#{item[:title]}）。", "NOT_FOUND" ]
        end
        error = validate_tree(Array(item[:items]), depth: depth + 1)
        return error if error
      end
      nil
    end

    def build_items(items, parent:)
      items.each_with_index do |item, index|
        type = item[:type].to_s
        resource = RESOURCE_MODELS.key?(type) ? resolve_resource(type, item[:resource_id]) : nil
        row = MenuItem.create!(
          shop_id: @shop.id, menu: @menu, parent_menu_item: parent,
          position: index + 1, title: item[:title].to_s, item_type: type,
          url: type == "http" ? item[:url].to_s : nil,
          resource_type: resource&.class&.name, resource_id: resource&.id
        )
        build_items(Array(item[:items]), parent: row)
      end
    end

    def resolve_resource(type, gid)
      model = RESOURCE_MODELS.fetch(type).call
      numeric = gid.to_s[%r{\Agid://chilllove/#{model.name}/(\d+)\z}, 1]
      numeric && model.find_by(shop_id: @shop.id, id: numeric)
    end
  end
end
