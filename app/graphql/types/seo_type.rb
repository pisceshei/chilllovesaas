# frozen_string_literal: true

module Types
  # 商品 SEO 覆寫的讀取面（欄位皆可 null＝未覆寫，前台自行 fallback）。
  class SeoType < BaseObject
    graphql_name "SEO"
    description "搜尋引擎資訊覆寫；null＝沿用商品標題／說明摘要。"

    field :title, String, null: true
    field :description, String, null: true

    # @return [String, nil] products.seo_title
    def title = object.seo_title

    # @return [String, nil] products.seo_description
    def description = object.seo_description
  end
end
