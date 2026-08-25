# frozen_string_literal: true

module Types
  module Inputs
    # 智慧系列的條件規則（第 11 包 rules 契約；typed value——金額欄是十進位字串，
    # **序列化邊界**折 cents 後落 `value_cents`，鐵律 3）。
    class CollectionRuleInput < GraphQL::Schema::InputObject
      graphql_name "CollectionRuleInput"
      description "單一條件。conditionType 值域＝limits collection.*_condition_types（snake_case）。"

      argument :block, String, required: true, description: "inclusion／exclusion（區塊，不是 source 極性）。"
      argument :condition_type, String, required: true,
        description: "product_title／product_tag／variant_price…（見 docs/dev/m2-smart-collections.md 值域表）。"
      argument :relation, String, required: true,
        description: "eq／not_eq／contains／includes／gt／lt／is_set…（依 conditionType，執行期 query 可查）。"
      argument :value_text, String, required: false, description: "字串/標籤/狀態條件的值。"
      argument :value_money, String, required: false,
        description: "金額條件的值（十進位字串如 \"128.00\"；服務端折 cents 儲存——鐵律 3）。"
      argument :value_int, Integer, required: false, description: "重量（克）/庫存數量條件的值。"
      argument :referenced_collection_id, ID, required: false,
        description: "exclusion 的 collection 型：被減去的系列 GID。"
    end

    # 一個來源（sources 模型；conditions×products——v1 唯一可用組合）。
    class CollectionSourceInput < GraphQL::Schema::InputObject
      graphql_name "CollectionSourceInput"
      description "系列來源。v1 只收 conditions×products；sub_collections／variants 屬後續包。"

      argument :target_type, String, required: false,
        description: "products（預設；variants 屬後續包）。"
      argument :inclusion_match, String, required: false, description: "all（預設）／any。"
      argument :exclusion_match, String, required: false, description: "all／any；省略＝all。"
      argument :rules, [ Types::Inputs::CollectionRuleInput ], required: true,
        description: "條件清單（宣告式：整份取代）。"
    end
  end
end
