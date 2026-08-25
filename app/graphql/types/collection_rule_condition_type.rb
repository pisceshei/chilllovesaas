# frozen_string_literal: true

module Types
  # 條件型別 × 合法 relation（第 11 包；對齊本尊 `CollectionRuleConditions` 的
  # ruleType／allowedRelations／defaultRelation 三欄形狀）。
  # 資料源＝`Collections::RuleCompiler::RELATIONS`（與寫入層驗證、編譯器同一份）。
  class CollectionRuleConditionType < Types::BaseObject
    graphql_name "CollectionRuleCondition"
    description "智慧系列的一個條件型別與它的合法 relation 集合。"

    field :rule_type, String, null: false, description: "條件型別（snake_case）。"
    field :allowed_relations, [ String ], null: false, description: "合法 relation。"
    field :default_relation, String, null: true, description: "最常用 relation（UI 預選）。"
    field :allowed_in_exclusion, Boolean, null: false,
      description: "此型別是否也可用於 exclusion 區塊（6 值子集的 v1 支援面）。"
  end
end
