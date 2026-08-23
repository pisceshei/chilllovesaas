# frozen_string_literal: true

module Types
  # 某店啟用的一個內容語言（docs/specs/67 §C.1；ML-2）。
  class ShopLocaleType < BaseObject
    graphql_name "ShopLocale"
    description "商店啟用的內容語言。"

    field :locale, Types::PlatformLocaleType, null: false, description: "平台語言字典條目。"
    field :is_source, Boolean, null: false, description: "來源語言（base 資料表的文字語言）；每店恰一個。"
    field :published, Boolean, null: false, description: "已對前台發布（未發布＝只有預覽連結看得到）。"
    field :position, Integer, null: false, description: "切換器與堆疊欄位的排序。"
    field :enabled, Boolean, null: false, description: "false＝停用（譯文保留，重新啟用即復原）。"

    # @return [PlatformLocale]
    def locale = object.platform_locale
  end
end
