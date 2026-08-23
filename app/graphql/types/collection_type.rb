# frozen_string_literal: true

module Types
  # 商品系列（列表唯讀面；建立式待 71-R8-V4 裁定——sources 模型 vs 手動/智慧二分）。
  class CollectionType < BaseObject
    graphql_name "Collection"
    description "商品系列。"

    field :id, ID, null: false, description: "gid://chilllove/Collection/{id}"
    field :legacy_resource_id, ID, null: false
    field :title, String, null: false
    field :handle, String, null: false
    # ⚠️ 13 §F4 已把 manual/smart 標為 **legacy 衍生標籤**（原型 colKind 註釋：
    # 任何求值都不得讀它）；本欄位只供列表檢視篩選，sources 模型落地後改為衍生。
    field :collection_type, String, null: false,
      description: "manual／smart（legacy 檢視標籤；sources 模型落地後為衍生值）。"
    # 手動系列＝成員數；智慧系列的求值屬規則引擎包 ⇒ null（不是 0——「未求值」
    # 與「恰好沒有商品」是兩件事，同金額 null≠0 的原則）。
    field :products_count, Integer, null: true,
      description: "商品數；智慧系列在規則引擎落地前為 null。"
    field :description_html, String, null: false
    field :sort_order, String, null: false, description: "前台排序（13 §F4）。"
    field :lock_version, Integer, null: false, description: "全樹樂觀鎖（含譯文）。"
    field :seo, Types::SeoType, null: false, description: "SEO 覆寫；子欄位 null＝未覆寫。"
    field :product_ids, [ ID ], null: false, description: "手動系列成員（position 序）；智慧系列為空陣列。"
    field :translations, [ Types::TranslationType ], null: false do
      argument :locales, [ String ], required: false
    end
    field :translation_status, [ Types::TranslationStatusType ], null: false,
      description: "各語言翻譯進度（鐵律 7：唯一來源 translation_status）。"

    # @return [String] GID
    def id
      "gid://chilllove/Collection/#{object.id}"
    end

    # @return [String] 十進位主鍵字串
    def legacy_resource_id
      object.id.to_s
    end

    # SEO 子物件直接以 collection 為 object（欄位在同一列上，SeoType 讀 seo_title／seo_description）。
    def seo = object

    # @return [Array<String>] 手動系列成員的 GID（position 序）
    def product_ids
      return [] unless object.collection_type == "manual"

      CollectionProduct.where(shop_id: object.shop_id, collection_id: object.id)
                       .ordered.pluck(:product_id)
                       .map { |id| "gid://chilllove/Product/#{id}" }
    end

    # @param locales [Array<String>, nil]
    # @return [Array<Translation>]
    def translations(locales: nil)
      scope = Translation.where(shop_id: object.shop_id, resource_type: "COLLECTION", resource_id: object.id)
      scope = scope.where(locale_tag: locales.map { |tag| Locales::Tag.normalize(tag) }) if locales.present?
      scope.order(:locale_tag, :field_key)
    end

    # @return [Array<TranslationStatus>]
    def translation_status
      TranslationStatus.where(shop_id: object.shop_id, resource_type: "COLLECTION", resource_id: object.id)
                       .order(:locale_tag)
    end

    # @return [Integer, nil]
    def products_count
      return nil unless object.collection_type == "manual"

      CollectionProduct.where(shop_id: object.shop_id, collection_id: object.id).count
    end
  end
end
