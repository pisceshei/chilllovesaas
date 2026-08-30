# frozen_string_literal: true

module Storefront
  # 多語言 sitemap（包 35；62 §C；分片形態鏡射 83 §3.6 量測：sitemapindex＋products_N 子表）。
  #
  # 四條硬規則（62 §C）：①只列 canonical 且回 200 的 URL——products＝**discoverable**
  #   （UNLISTED 排除＝93 §C 判準直接複用，limits `product.unlisted_excluded_from` 含 sitemap）、
  #   collections＝published、pages＝visible；②lastmod＝內容更新時間（v1 用 updated_at，
  #   「庫存數不算內容更新」的細分待 stamp 細化——庫存量本就不動 products.updated_at）；
  #   ③不做 ping endpoint（Google 2024-01 移除）；④`xhtml:link` 與 `<head>` hreflang
  #   **同一個矩陣函式**（Seo::HreflangMatrix）——兩處各寫必然漂移。
  class SitemapsController < BaseController
    PER_PAGE = 10_000 # 單檔 URL ≤50,000（62 §C）；每資源 × (market,locale) 組合數 ⇒ 保守取 1 萬資源

    # GET /sitemap.xml
    def index
      publication = Publication.online_store!
      counts = ActsAsTenant.with_tenant(current_shop) do
        { "products" => Product.discoverable(publication:).count,
          "collections" => Collection.published_on(publication).count,
          "pages" => Page.visible.count }
      end
      children = counts.flat_map do |kind, count|
        (1..[ (count / PER_PAGE.to_f).ceil, 1 ].max).map { |n| "#{origin}/sitemap_#{kind}_#{n}.xml" }
      end
      xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
      xml << %(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
      children.each { |loc| xml << "  <sitemap><loc>#{ERB::Util.html_escape(loc)}</loc></sitemap>\n" }
      xml << "</sitemapindex>\n"
      render xml: xml
    end

    # GET /sitemap_:kind_:n.xml
    def show
      kind = params[:kind].to_s
      page = [ params[:n].to_i, 1 ].max
      rows = ActsAsTenant.with_tenant(current_shop) { rows_for(kind, page) }
      return head :not_found if rows.nil?

      xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
      xml << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ) <<
             %(xmlns:xhtml="http://www.w3.org/1999/xhtml">\n)
      rows.each do |canonical_path, lastmod|
        entries = Seo::HreflangMatrix.entries(shop: current_shop, canonical_path:)
        content = entries.reject { |e| e.code == "x-default" }
        next if content.empty?

        content.each do |entry|
          xml << "  <url>\n    <loc>#{ERB::Util.html_escape(entry.url)}</loc>\n"
          xml << "    <lastmod>#{lastmod.utc.iso8601}</lastmod>\n" if lastmod
          entries.each do |alt|
            xml << %(    <xhtml:link rel="alternate" hreflang="#{alt.code}" ) <<
                   %(href="#{ERB::Util.html_escape(alt.url)}"/>\n)
          end
          xml << "  </url>\n"
        end
      end
      xml << "</urlset>\n"
      render xml: xml
    end

    private

    # @return [Array<Array(String, Time)>, nil] [canonical_path, lastmod]；未知 kind ⇒ nil
    def rows_for(kind, page)
      publication = Publication.online_store!
      offset = (page - 1) * PER_PAGE
      case kind
      when "products"
        Product.discoverable(publication:).order(:id).offset(offset).limit(PER_PAGE)
               .pluck(:handle, :updated_at).map { |h, t| [ "/products/#{h}", t ] }
      when "collections"
        Collection.published_on(publication).order(:id).offset(offset).limit(PER_PAGE)
                  .pluck(:handle, :updated_at).map { |h, t| [ "/collections/#{h}", t ] }
      when "pages"
        Page.visible.order(:id).offset(offset).limit(PER_PAGE)
            .pluck(:handle, :updated_at).map { |h, t| [ "/pages/#{h}", t ] }
      end
    end

    def origin
      "https://#{request.host}"
    end
  end
end
