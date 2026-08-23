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

    # 序列化 product 的穩定 global API identifier。
    #
    # @return [String] `gid://chilllove/Product/{id}`
    # @note 副作用：無。
    # @see docs/research/28-api-contract.md §0.3
    def id
      "gid://chilllove/Product/#{object.id}"
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
