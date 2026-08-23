# GraphQL schema type 的 namespace。
module Types
  # Admin GraphQL API 的 tenant-scoped product representation。
  #
  # 主要物件實作 Node，同時提供 legacyResourceId 供遷移相容。見
  # docs/research/28 §0.3。
  class ProductType < BaseObject
    implements Interfaces::Node

    field :legacy_resource_id, ID, null: false
    field :title, String, null: false
    field :handle, String, null: false
    field :status, Types::ProductStatusEnum, null: false
    field :description_html, String, null: false,
      description: "富文本說明（已 sanitize 的儲存值）。"
    field :variants, [ Types::ProductVariantType ], null: false,
      description: "變體（position 序）；無選項商品恆為一筆隱含變體。"
    # SaveBar 樂觀鎖（63 §A.4：lockVersion 涵蓋整棵樹）；payload 帶回讓前端
    # 下一次儲存能偵測併發覆蓋（STALE_OBJECT）。
    field :lock_version, Integer, null: false
    # ── 組織分類＋SEO（91 §11–12，P1）──
    field :vendor, String, null: true
    field :product_type, String, null: true
    field :tags, [ String ], null: false,
      description: "標籤全量（宣告式契約的讀取面；恆為陣列，無標籤＝[]）。"
    field :seo, Types::SeoType, null: false,
      description: "SEO 覆寫（物件恆在，子欄位 null＝未覆寫）。"
    field :translations, [ Types::TranslationType ], null: false,
      description: "非來源語言的譯文（ML-2）；locales 省略＝該店已啟用的全部語言。" do
      argument :locales, [ String ], required: false
    end
    field :translation_status, [ Types::TranslationStatusType ], null: false,
      description: "各語言翻譯進度（鐵律 7：唯一來源 translation_status）。"

    # 序列化 product 的穩定 global API identifier。
    #
    # @return [String] `gid://chilllove/Product/{id}`
    # @note 副作用：無。
    # @see docs/research/28-api-contract.md §0.3
    def id
      "gid://chilllove/Product/#{object.id}"
    end

    # SEO 子物件直接以 product 本身為 object（欄位在同一列上，SeoType 讀
    # seo_title／seo_description）——不做額外查詢。
    def seo = object

    # @return [Array<String>] products.tags（json 欄，DB default []）
    def tags = object.tags || []

    # @param locales [Array<String>, nil] 篩選語言；省略＝全部已啟用語言
    # @return [Array<Translation>] 本商品的譯文列
    # @note 副作用：tenant-scoped SELECT。
    def translations(locales: nil)
      scope = Translation.where(shop_id: object.shop_id, resource_type: "PRODUCT", resource_id: object.id)
      scope = scope.where(locale_tag: locales.map { |tag| Locales::Tag.normalize(tag) }) if locales.present?
      scope.order(:locale_tag, :field_key)
    end

    # @return [Array<TranslationStatus>] 各語言進度（無列＝尚未有任何譯文，前端顯示 0/N）
    def translation_status
      TranslationStatus.where(shop_id: object.shop_id, resource_type: "PRODUCT", resource_id: object.id)
                       .order(:locale_tag)
    end

    # @return [Array<ProductVariant>] position 序（B1-2：恆 ≥1 筆）
    def variants
      object.product_variants.order(:position)
    end

    # 為 migration compatibility 序列化底層 database id。
    #
    # @return [String] 十進位 primary key
    # @note 副作用：無。
    # @see docs/research/28-api-contract.md §0.3
    def legacy_resource_id
      object.id.to_s
    end
  end
end
