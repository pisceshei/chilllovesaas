# frozen_string_literal: true

module Types
  # 通知模板（G6 步 6；89 §7.3 overlay 語義的讀面）。
  class NotificationTemplateType < BaseObject
    graphql_name "NotificationTemplate"
    description "通知信模板（合併視圖：覆寫列或平台預設）"

    field :key, String, null: false, description: "模板 key（Catalog::KINDS；對位本尊 email_templates URL key）"
    field :subject, String, null: false
    field :body_liquid, String, null: false
    field :is_default, Boolean, null: false,
          description: "true＝目前用平台預設（無覆寫列；Revert 後回到 true）"
  end
end
