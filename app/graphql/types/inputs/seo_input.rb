# frozen_string_literal: true

module Types
  module Inputs
    # 商品 SEO 覆寫輸入（91 §11：頁面標題／Meta 描述；留空＝前台 fallback 商品標題與說明摘要）。
    #
    # 上限引 `content.seo_title_max_chars`(70)／`content.seo_meta_description_max_chars`(320)
    # ——鐵律 6，不硬編。**160 不是上限**：本尊 Meta 描述計數器 203/160 照樣可存
    # （91 §11 實測），160 只是 SERP 顯示建議值（`seo.serp` 段），驗證只擋 320。
    class SeoInput < GraphQL::Schema::InputObject
      graphql_name "SEOInput"
      description "商品搜尋引擎資訊覆寫。"

      argument :title, String, required: false,
        description: "頁面標題（SERP title）；空字串＝清除覆寫。"
      argument :description, String, required: false,
        description: "Meta 描述；空字串＝清除覆寫。"
    end
  end
end
