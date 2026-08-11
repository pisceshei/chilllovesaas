# 由日期版本 Admin API endpoint 提供、版本獨立的 GraphQL schema。
#
# schema 以 tenant-aware GID resolver 保證 `node/nodes` 不跨店，並從
# `config/limits.yml` 取得 complexity 上限。見 docs/research/28 §0.1–0.4、
# docs/specs/12 F4。
class ChillloveSchema < GraphQL::Schema
  query Types::QueryType

  orphan_types Types::ProductType
  max_complexity GraphqlLimits.fetch(:max_request_cost)

  # 透過明確的 tenant-scoped query 解析 GID。
  #
  # 刻意不使用可能繞過預設 tenant scope 的 `GlobalID.find`。
  #
  # @param global_id [String] `gid://chilllove/{Type}/{id}`
  # @param context [GraphQL::Query::Context] 目前 request context
  # @return [Product, nil] 屬於目前 tenant 的 resource；找不到時為 nil
  # @note 副作用：執行 tenant-scoped Product SELECT，不修改資料。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F4
  def self.object_from_id(global_id, context)
    match = global_id.to_s.match(%r{\Agid://chilllove/Product/(\d+)\z})
    return unless match

    Product.where(shop_id: context.fetch(:current_shop).id).find_by(id: match[1])
  end

  # 將支援的 resource 序列化為 CHILL LOVE GID。
  #
  # @param object [Product] GraphQL result object
  # @param _type_definition [GraphQL::Schema::Object] 已解析的 GraphQL type
  # @param _context [GraphQL::Query::Context] query context
  # @return [String] resource global id
  # @note 副作用：無。
  # @see docs/research/28-api-contract.md §0.3
  def self.id_from_object(object, _type_definition, _context)
    "gid://chilllove/#{object.class.name}/#{object.id}"
  end

  # 把實作 interface 的 model object 解析成 GraphQL concrete type。
  #
  # @param _abstract_type [Module] GraphQL interface
  # @param object [Object] application object
  # @param _context [GraphQL::Query::Context] query context
  # @return [Class<Types::BaseObject>] concrete output type
  # @raise [GraphQL::RequiredImplementationMissingError] object type 未支援時拋出
  # @note 副作用：無。
  # @see docs/research/28-api-contract.md §0.3
  def self.resolve_type(_abstract_type, object, _context)
    return Types::ProductType if object.is_a?(Product)

    raise GraphQL::RequiredImplementationMissingError, "Unsupported GraphQL object: #{object.class.name}"
  end
end
