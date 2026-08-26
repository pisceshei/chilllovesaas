# frozen_string_literal: true

module Mutations
  # 建立一個 publication（S1）。
  #
  # 本尊對位＝`publicationCreate(input: PublicationCreateInput!)`，描述逐字
  # `Creates a Publication that controls which Product and Collection customers can access
  # through a Catalog.`（取證 2026-08-26）。
  #
  # 🔴 **參數形態照抄本尊的 `input:`，不用具名參數**。
  #   `docs/research/28-api-contract.md` §0.3.4 說「新寫的 mutation 走具名參數」，
  #   但那條的依據是「本尊自 2024-10 起把 `input:` 拆成具名」——而 publication 線
  #   **至今仍是舊式**（`publicationCreate(input:)`、`publicationUpdate(id:, input:)`）。
  #   鐵律 12 的 1:1 對齊優先於我方的風格偏好，且 schema 形狀是客戶端寫死的東西。
  #   ⚠️ 連帶後果：`userErrors.field` 的 path 第一段是 **`input`**（28 §0.3.1）。
  #
  # 🔴 **不進 `idempotency.required_for`**（本輪裁定，登記於 dev doc）：
  #   該清單目前收的是**金流與庫存**寫入（refund／inventory*／orderEditCommit…），
  #   判準是「重放會不會憑空多出一筆錢或一批庫存」。重放本 mutation 只會多出一個
  #   **可刪、無金流、無庫存**的容器。⚠️ 這是**我方判斷不是本尊規則**；
  #   若日後 publication 開始牽動計費（管道訂閱），必須重新裁定。
  class PublicationCreate < BaseMutation
    graphql_name "PublicationCreate"
    description "建立一個 publication（銷售管道的發布容器）。"

    user_errors_type Types::Errors::PublicationUserErrorType

    argument :input, Types::Inputs::PublicationCreateInput, required: true

    field :publication, Types::PublicationType, null: true

    # @param input [Types::Inputs::PublicationCreateInput]
    # @return [Hash] payload
    # @note 副作用：見 `Publications::Write.create`。
    def resolve(input:)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)

      catalog, error = resolve_catalog(shop, input[:catalog_id])
      return error if error

      result = Publications::Write.create(
        shop:,
        title: input[:title],
        auto_publish: input[:auto_publish],
        default_state: input[:default_state],
        sales_catalog: catalog
      )

      { publication: result.publication, user_errors: result.user_errors }
    end

    private

    # @return [Array(SalesCatalog, nil), Array(nil, Hash), Array(nil, nil)]
    #   命中時回 `[catalog, nil]`；GID 給了但查不到時回 `[nil, payload]`；沒給時回 `[nil, nil]`。
    def resolve_catalog(shop, gid)
      return [ nil, nil ] if gid.blank?

      legacy_id = gid.to_s[%r{\Agid://chilllove/AppCatalog/(\d+)\z}, 1]
      catalog = legacy_id && ActsAsTenant.with_tenant(shop) { SalesCatalog.find_by(id: legacy_id.to_i) }
      return [ catalog, nil ] if catalog

      [ nil, {
        publication: nil,
        user_errors: [ {
          field: [ "input", "catalogId" ],
          message: I18n.t("errors.publication.catalog_not_found"),
          code: "CATALOG_NOT_FOUND"
        } ]
      } ]
    end
  end
end
