# frozen_string_literal: true

# 主題 conformance 共用 harness（D78：驗收單位＝平台契約；每套主題都是探針）。
#
# 用法：
#   include ThemeConformance
#   report = conformance_render_all(theme_dir:, theme_name:, theme_version:, shop:)
#   ⇒ { pages: [{template, path, status, bytes, liquid_errors, exception}], misses: {...}, skipped: [...] }
#
# 路徑對映：index／collection／list-collections／product／cart／search／404／page／
# blog／article，加上每個 {collection,product,page,article,blog,search}.*.{json,liquid}
# 視圖（?view= 尾碼）。customers/*、gift_card、password 為未路由面
# （帳戶線／禮品卡線／平台密碼頁）——列入 skipped 不計錯。
# 種子資料最小集（商品＋變體＋系列＋頁面＋部落格＋文章）在 with_tenant 內建，
# 呼叫端負責 shop 的清理（request/liquid spec 走 transaction 自清）。
module ThemeConformance
  def conformance_render_all(theme_dir:, theme_name:, theme_version:, shop:)
    source = ThemeEngine::FileSource.new(theme_dir)
    report = { pages: [], misses: {}, skipped: [] }
    ActsAsTenant.with_tenant(shop) do
      theme = Theme.create!(shop_id: shop.id, name: theme_name, version: theme_version, role: "published",
                            source: "licensed", license_attested: true)
      pub = Publication.online_store!
      product = Product.create!(shop_id: shop.id, status: "active", handle: "tc-tee", title: "TC Tee",
                                vendor: "TC", product_type: "Tee", description_html: "<p>tc</p>")
      ProductVariant.create!(shop_id: shop.id, product: product, price_cents: 18800, title: "Default", position: 1)
      collection = Collection.create!(shop_id: shop.id, title: "TC Col", handle: "tc-col",
                                      description_html: "", collection_type: "manual", sort_order: "manual")
      CollectionProduct.create!(shop_id: shop.id, collection: collection, product: product, position: 1)
      Page.create!(shop_id: shop.id, title: "About", handle: "about-us", body_html: "<p>x</p>",
                   published_at: 1.hour.ago)
      blog = Blog.create!(shop_id: shop.id, title: "News", handle: "news")
      Article.create!(shop_id: shop.id, blog: blog, title: "Hello", handle: "hello", body_html: "<p>y</p>",
                      published_at: 1.hour.ago, author_name: "TC")

      views = Dir.glob(File.join(theme_dir.to_s, "templates", "*")).map { |f| File.basename(f) }
      paths = [ [ "index", "/" ], [ "collection", "/collections/tc-col" ], [ "list-collections", "/collections" ],
                [ "product", "/products/tc-tee" ], [ "cart", "/cart" ], [ "search", "/search?q=tc" ],
                [ "404", "/nope-404" ], [ "page", "/pages/about-us" ], [ "blog", "/blogs/news" ],
                [ "article", "/blogs/news/hello" ] ]
      views.each do |v|
        base, suffix = v.match(/\A([a-z0-9_-]+)(?:\.([a-z0-9_-]+))?\.(?:json|liquid)\z/)&.captures
        next unless base && suffix
        case base
        when "collection" then paths << [ v, "/collections/tc-col?view=#{suffix}" ]
        when "product" then paths << [ v, "/products/tc-tee?view=#{suffix}" ]
        when "page" then paths << [ v, "/pages/about-us?view=#{suffix}" ]
        when "article" then paths << [ v, "/blogs/news/hello?view=#{suffix}" ]
        when "blog" then paths << [ v, "/blogs/news?view=#{suffix}" ]
        when "search" then paths << [ v, "/search?q=tc&view=#{suffix}" ]
        end
      end
      report[:skipped] = views.select { |v| v.start_with?("customers", "gift_card", "password") }

      paths.each do |label, full|
        path, qs = full.split("?", 2)
        params = qs ? Rack::Utils.parse_query(qs) : {}
        result = ThemeEngine::PageRenderer.new(theme:, shop:, publication: pub, source:).render(path, params:)
        report[:pages] << { template: label, path: full, status: result.status, bytes: result.html.to_s.bytesize,
                            liquid_errors: result.html.to_s.scan(/Liquid error[^<]{0,120}/).uniq }
      rescue StandardError => e
        report[:pages] << { template: label, path: full, exception: "#{e.class}: #{e.message[0, 200]}" }
      end
      report[:misses] = ThemeEngine.miss_report(top: 300)
    end
    report
  end
end

RSpec.configure { |c| c.include ThemeConformance }
