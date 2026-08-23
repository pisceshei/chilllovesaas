# frozen_string_literal: true

module Types
  # 平台語言字典條目（跨租戶共用；67 §C.1）。
  class PlatformLocaleType < BaseObject
    graphql_name "PlatformLocale"
    description "平台支援的語言。"

    field :tag, String, null: false, description: "BCP-47 標籤（zh-Hant／en／ja…）。"
    field :endonym, String, null: false, description: "語言自稱；切換器顯示這個（不用國旗、不用語言碼）。"
    field :direction, String, null: false, description: "ltr / rtl。"
  end
end
