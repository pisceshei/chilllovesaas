# frozen_string_literal: true

module Types
  # 部落格留言政策（官方 CommentPolicy 三值逐字——98 §3）。
  class CommentPolicyType < GraphQL::Schema::Enum
    graphql_name "CommentPolicy"
    description "部落格留言政策。"

    value "AUTO_PUBLISHED", "留言免審核直接發布。", value: "auto_published"
    value "CLOSED", "不開放留言（admin 預設 Disabled）。", value: "closed"
    value "MODERATED", "留言須審核後才發布。", value: "moderated"
  end
end
