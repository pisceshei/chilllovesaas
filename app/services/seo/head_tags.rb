# frozen_string_literal: true

module Seo
  # `content_for_header` 的平台注入段（包 35；62 §A.1 第 1 層——只新增節點，
  # 不動主題的 class 與 DOM 層級，naming_contract.platform_injection_additive_only）。
  #
  # 組成：canonical ＋ hreflang link 群（HreflangMatrix 唯一實作）＋ 商品 JSON-LD；
  # UNLISTED ⇒ 只出 canonical ＋ robots noindex meta（limits `product.unlisted_meta_robots`；
  # `unlisted_excluded_from` 含 hreflang／jsonld_offer——两者整段不出）。
  module HeadTags
    module_function

    # @param shop [Shop]
    # @param presence [MarketWebPresence]
    # @param locale_tag [String]
    # @param canonical_path [String] 前綴已剝路徑
    # @param params [Hash] query（canonical 白名單只認 page——62 §B.1 行 2/4/6：
    #   variant 去參數、分頁 self-canonical、追蹤參數剝除）
    # @param record [Product, Collection, Page, nil] 本頁資源（404 頁 nil）
    # @param status [Integer] 渲染狀態（非 200 ⇒ 只出 canonical 也不出——不是內容頁）
    # @return [String] HTML 片段（塞進 content_for_header）
    def build(shop:, presence:, locale_tag:, canonical_path:, params:, record:, status:)
      return "" unless status == 200

      canonical = canonical_url(shop, presence, locale_tag, canonical_path, params)
      tags = [ %(<link rel="canonical" href="#{ERB::Util.html_escape(canonical)}">) ]

      if unlisted?(record)
        tags << %(<meta name="robots" content="#{Limits.fetch(:product, :unlisted_meta_robots)}">)
      else
        HreflangMatrix.entries(shop:, canonical_path:).each do |entry|
          tags << %(<link rel="alternate" hreflang="#{entry.code}" href="#{ERB::Util.html_escape(entry.url)}">)
        end
        if record.is_a?(Product)
          tags << JsonLd.product_script(product: record, url: canonical, currency: shop.store_currency)
        end
      end
      tags.join("\n")
    end

    # canonical＝絕對、自引、去非白名單參數（62 §B.1 共通規則）。
    def canonical_url(shop, presence, locale_tag, canonical_path, params)
      base = HreflangMatrix.absolute_url(shop, presence, locale_tag, canonical_path)
      page = params["page"].to_s
      page.match?(/\A[0-9]+\z/) && page.to_i > 1 ? "#{base}?page=#{page}" : base
    end

    def unlisted?(record)
      record.is_a?(Product) && record.status == "unlisted"
    end
  end
end
