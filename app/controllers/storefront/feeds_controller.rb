# frozen_string_literal: true

module Storefront
  # 商品 oEmbed 與 Atom feed（E19；content_for_header 的 `<link rel="alternate">` 目標；取證 external-facts §G27，hoko.vip 2026-09-05）。
  #
  # ①`GET /products/{handle}.oembed` ⇒ 200 `application/json+oembed`：
  #   `{"product_id":"acme-tee","title":"Acme Tee","description":"","brand":"Acme","offers":[{"title":"Default Title","offer_id":44547877830759,"sku":null,"price":188.0,"currency_code":"HKD","in_stock":true}],"url":"https:\/\/hoko.vip\/products\/acme-tee","provider":"我的商店 3","version":"1.0","type":"link"}`
  #   （`price` 為 JSON 數值、一位以上小數——鐵律 3：儲存 cents，序列化層轉；`in_stock` 對售罄變體仍 true——本尊變體有 99 庫存，判準＝
  #   庫存量>0 或 policy continue 或不追蹤，91 V）。
  # ②`GET /collections/{handle}.atom`／`/blogs/{handle}.atom` ⇒ 200 `application/atom+xml`（`xmlns:s="http://jadedpixel.com/-/spec/shopify"`）：
  #   集合 feed 逐商品 entry（id `https://host/products/{id}`、published／updated、link、title、s:type、s:vendor、summary CDATA 表格
  #   （厂商／类型／价格 三行，五語言逐字 `_platform.atom.*`）、s:variant{id,title,s:price[currency],s:sku,s:grams}）；feed `updated`＝最新
  #   entry 的 published；空 feed（hoko 部落格無文章）無 `<updated>`。文章 entry 形未觀測（91 V）⇒ 通用 Atom entry。
  class FeedsController < BaseController
    # GET /products/:handle.oembed
    def product_oembed
      product = ActsAsTenant.with_tenant(current_shop) do
        Product.find_by(shop_id: current_shop.id, handle: params[:handle].to_s, status: "active")
      end
      return head :not_found if product.nil?

      variants = ActsAsTenant.with_tenant(current_shop) { product.product_variants.order(:position, :id).to_a }
      payload = {
        "product_id" => product.handle, "title" => product.title, "description" => plain_text(product.description_html),
        "brand" => product.vendor.to_s,
        "offers" => variants.map { |v|
          { "title" => v.title.to_s, "offer_id" => v.id, "sku" => v.sku.presence, "price" => (BigDecimal(v.price_cents.to_i) / 100).to_f,
            "currency_code" => current_shop.store_currency, "in_stock" => in_stock?(v) }
        },
        "url" => "#{request.protocol}#{request.host_with_port}#{prefix}/products/#{product.handle}",
        "provider" => current_shop.name.to_s, "version" => "1.0", "type" => "link"
      }
      render plain: JSON.generate(payload).gsub("/", "\\/"), content_type: "application/json+oembed; charset=utf-8"
    end

    # GET /collections/:handle.atom
    def collection_atom
      handle = params[:handle].to_s
      collection = ActsAsTenant.with_tenant(current_shop) { Collection.find_by(shop_id: current_shop.id, handle:) }
      return head :not_found if collection.nil? && handle.downcase != "all" # 虛擬 all（本尊 /collections/all.atom 200）

      products = ActsAsTenant.with_tenant(current_shop) do
        scope = collection ? collection.products : Product.where(shop_id: current_shop.id)
        scope.where(status: "active").includes(:product_variants).order(created_at: :desc, id: :desc).to_a
      end
      entries = products.map { |p| product_entry(p) }
      latest = products.map { |p| p.try(:published_at) || p.created_at }.compact.max
      render_atom(id: "#{origin}#{prefix}/collections/#{handle}.atom", html: "#{origin}#{prefix}/collections/#{handle}",
                  title: current_shop.name.to_s, updated: latest, entries:)
    end

    # GET /blogs/:handle.atom
    def blog_atom
      blog = ActsAsTenant.with_tenant(current_shop) { Blog.find_by(shop_id: current_shop.id, handle: params[:handle].to_s) }
      return head :not_found if blog.nil?

      articles = ActsAsTenant.with_tenant(current_shop) { blog.articles.visible.order(published_at: :desc).to_a }
      entries = articles.map { |a| article_entry(blog, a) }
      render_atom(id: "#{origin}#{prefix}/blogs/#{ERB::Util.url_encode(blog.handle)}.atom", html: "#{origin}#{prefix}/blogs/#{ERB::Util.url_encode(blog.handle)}",
                  title: "#{current_shop.name} - #{blog.title}", updated: articles.first&.published_at, entries:)
    end

    private

    def origin = "#{request.protocol}#{request.host_with_port}"
    def prefix = Markets::UrlPrefix.for(effective_hit&.web_presence, effective_hit&.locale_tag).to_s
    def lang = ThemeEngine::LocaleTags.shopify_code(effective_hit&.locale_tag.presence || "en")
    def labels = Storefront::PlatformStrings.dict(effective_hit&.locale_tag.to_s).dig("_platform", "atom") || {}
    def x(s) = ERB::Util.html_escape(s.to_s)
    def iso(t) = t&.in_time_zone(current_shop.timezone)&.iso8601
    def money(cents) = format("%.2f", BigDecimal(cents.to_i) / 100)

    def in_stock?(v)
      return true unless v.respond_to?(:inventory_policy)

      v.inventory_policy.to_s == "continue" || !v.respond_to?(:inventory_quantity) || v.inventory_quantity.to_i.positive?
    end

    def plain_text(html) = ActionController::Base.helpers.strip_tags(html.to_s).strip

    def product_entry(p)
      published = p.try(:published_at) || p.created_at
      variants = p.product_variants.sort_by { |v| [ v.position.to_i, v.id ] }
      first = variants.first
      <<~XML
        <entry>
          <id>#{origin}/products/#{p.id}</id>
          <published>#{iso(published)}</published>
          <updated>#{iso(p.updated_at)}</updated>
          <link rel="alternate" type="text/html" href="#{origin}#{prefix}/products/#{p.handle}"/>
          <title>#{x(p.title)}</title>
          <s:type>#{x(p.product_type)}</s:type>
          <s:vendor>#{x(p.vendor)}</s:vendor>
          <summary type="html">
            <![CDATA[<table border="0">
        <tr>
          <td width="200"><img width="200" src="#"></td>
          <td valign="bottom">
            <p>

              <strong>#{labels['vendor']}</strong>#{x(p.vendor)}<br>
              <strong>#{labels['type']}</strong>#{x(p.product_type)}<br>
              <strong>#{labels['price']}</strong>
                  #{first ? money(first.price_cents) : ''}
            </p>
          </td>
        </tr>
        <tr>
          <td colspan="2"></td>
        </tr>
      </table>
      ]]>
          </summary>
      #{variants.map { |v| variant_xml(p, v) }.join}
        </entry>
      XML
    end

    def variant_xml(p, v)
      sku = v.sku.present? ? "<s:sku>#{x(v.sku)}</s:sku>" : "<s:sku/>"
      <<~XML
          <s:variant>
            <id>#{origin}/products/#{p.id}</id>
            <title>#{x(v.title)}</title>
            <s:price currency="#{current_shop.store_currency}">#{money(v.price_cents)}</s:price>
            #{sku}
            <s:grams>#{v.weight_grams.to_i}</s:grams>
          </s:variant>
      XML
    end

    def article_entry(blog, a)
      <<~XML
        <entry>
          <id>#{origin}/blogs/#{ERB::Util.url_encode(blog.handle)}/#{a.id}</id>
          <published>#{iso(a.published_at)}</published>
          <updated>#{iso(a.updated_at)}</updated>
          <link rel="alternate" type="text/html" href="#{origin}#{prefix}/blogs/#{ERB::Util.url_encode(blog.handle)}/#{a.handle}"/>
          <title>#{x(a.title)}</title>
          <author>
            <name>#{x(a.author_name.presence || current_shop.name)}</name>
          </author>
          <summary type="html">
            <![CDATA[#{a.excerpt_html}]]>
          </summary>
        </entry>
      XML
    end

    def render_atom(id:, html:, title:, updated:, entries:)
      xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
      xml << %(<feed xml:lang="#{lang}" xmlns="http://www.w3.org/2005/Atom" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/" xmlns:s="http://jadedpixel.com/-/spec/shopify">\n)
      xml << "  <id>#{id}</id>\n"
      xml << %(  <link rel="alternate" type="text/html" href="#{html}"/>\n)
      xml << %(  <link rel="self" type="application/atom+xml" href="#{id}"/>\n)
      xml << "  <title>#{x(title)}</title>\n"
      xml << "  <updated>#{iso(updated)}</updated>\n" if updated
      xml << "  <author>\n    <name>#{x(current_shop.name)}</name>\n  </author>\n"
      entries.each { |e| xml << e.gsub(/^/, "  ") }
      xml << "</feed>\n"
      render plain: xml, content_type: "application/atom+xml; charset=utf-8"
    end
  end
end
