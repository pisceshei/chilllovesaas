# 由日期版本 Admin API endpoint 提供、版本獨立的 GraphQL schema。
#
# schema 以 tenant-aware GID resolver 保證 `node/nodes` 不跨店，並從
# `config/limits.yml` 取得 complexity 上限。見 docs/research/28 §0.1–0.4、
# docs/specs/12 F4。
class ChillloveSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType

  # ProductType 已由 productSet payload 引用，不再是 orphan；此行在 mutation root
  # 掛載（2026-08-23）時移除。
  max_complexity GraphqlLimits.fetch(:max_query_cost_points)

  # 透過明確的 tenant-scoped query 解析 GID。
  #
  # 刻意不使用可能繞過預設 tenant scope 的 `GlobalID.find`。
  #
  # @param global_id [String] `gid://chilllove/{Type}/{id}`
  # @param context [GraphQL::Query::Context] 目前 request context
  # @return [Product, nil] 屬於目前 tenant 的 resource；找不到時為 nil
  # @note 副作用：執行 tenant-scoped Product SELECT，不修改資料。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F4
  # GID → 物件（一律 tenant-scoped：跨店 GID 回 nil 而不是別店資料）。
  # 🔴 新增資源型別時**這裡與 resolve_type 要一起改**——只改一邊的症狀是
  #    「query 回 null 但 mutation 寫得進去」或反過來，兩者都很難從錯誤訊息看出原因。
  RESOLVABLE_TYPES = {
    "Product" => -> { Product },
    "Collection" => -> { Collection },
    # 第 28 包補齊（原本 C6 排除的理由已消解）：`FileType` 現在 implements Node、
    # 下面 resolve_type 也有 StoredFile 分支，三處齊了才入表。
    # 🔴 鍵是對外的 `File`、值是 model `StoredFile`（類名避開 Ruby core）。
    "File" => -> { StoredFile }
  }.freeze

  def self.object_from_id(global_id, context)
    match = global_id.to_s.match(%r{\Agid://chilllove/(\w+)/(\d+)\z})
    return unless match

    model = RESOLVABLE_TYPES[match[1]]&.call
    return unless model

    model.where(shop_id: context.fetch(:current_shop).id).find_by(id: match[2])
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
    return Types::CollectionType if object.is_a?(Collection)
    return Types::FileType if object.is_a?(StoredFile)

    raise GraphQL::RequiredImplementationMissingError, "Unsupported GraphQL object: #{object.class.name}"
  end
end
