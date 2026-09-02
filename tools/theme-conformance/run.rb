# 主題 conformance 通用 runner（D78）：渲染全模板 → status／Liquid error／例外／count_miss 遙測
# 用法：RAILS_ENV=test bundle exec rails runner tools/theme-conformance/run.rb <theme_dir> <name> <version> [preset_dir|-] [out.json]
require "json"
require "fileutils"

theme_dir, name, version, preset_dir, out = ARGV
abort "usage: theme_dir name version [preset_dir|-] [out.json]" unless theme_dir && name && version
theme_dir = Pathname(theme_dir).expand_path(Rails.root)
preset_label = nil
if preset_dir && preset_dir != "-"
  preset_dir = Pathname(preset_dir).expand_path(Rails.root)
  preset_label = File.basename(preset_dir)
  merged = Rails.root.join("tmp/conf-#{name.parameterize}-#{preset_label.parameterize}")
  FileUtils.rm_rf(merged)
  FileUtils.cp_r(theme_dir, merged)
  Dir.glob(preset_dir.join("**/*")).each do |f|
    next if File.directory?(f)
    rel = Pathname(f).relative_path_from(preset_dir).to_s
    rel = "config/#{rel}" if rel == "settings_data.json"
    rel = "templates/#{rel}" if !rel.include?("/") && rel.end_with?(".json")
    next unless rel.match?(%r{\A(config|sections|templates|snippets|assets|locales|layout|blocks)/})
    dest = merged.join(rel)
    FileUtils.mkdir_p(dest.dirname)
    FileUtils.cp(f, dest)
  end
  theme_dir = merged
end
source = ThemeEngine::FileSource.new(theme_dir)

shop = Shop.create!(name: "#{name} Conformance", subdomain: "tc-#{SecureRandom.hex(3)}")
report = { theme: name, version: version, preset: preset_label, pages: [], misses: {} }
begin
  ActsAsTenant.with_tenant(shop) do
    theme = Theme.create!(shop_id: shop.id, name: name, version: version, role: "published",
                          source: "licensed", license_attested: true)
    pub = Publication.online_store!
    product = Product.create!(shop_id: shop.id, status: "active", handle: "tc-tee", title: "TC Tee",
                              vendor: "TC", product_type: "Tee", description_html: "<p>tc</p>")
    ProductVariant.create!(shop_id: shop.id, product: product, price_cents: 18800, title: "Default", position: 1)
    collection = Collection.create!(shop_id: shop.id, title: "TC Col", handle: "tc-col",
                                    description_html: "", collection_type: "manual", sort_order: "manual")
    CollectionProduct.create!(shop_id: shop.id, collection: collection, product: product, position: 1)
    Page.create!(shop_id: shop.id, title: "About", handle: "about-us", body_html: "<p>x</p>", published_at: 1.hour.ago)
    blog = Blog.create!(shop_id: shop.id, title: "News", handle: "news")
    Article.create!(shop_id: shop.id, blog: blog, title: "Hello", handle: "hello", body_html: "<p>y</p>",
                    published_at: 1.hour.ago, author_name: "TC")

    views = Dir.glob(theme_dir.join("templates/*")).map { |f| File.basename(f) }
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
    report[:skipped_templates] = views.select { |v| v.start_with?("customers", "gift_card", "password") }

    paths.each do |label, full|
      path, qs = full.split("?", 2)
      params = qs ? Rack::Utils.parse_query(qs) : {}
      before = ThemeEngine::MISSES.dup
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = ThemeEngine::PageRenderer.new(theme:, shop:, publication: pub, source:).render(path, params: params)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      html = result.html.to_s
      errors = html.scan(/Liquid error[^<]{0,160}/).uniq
      comments = html.scan(/<!-- theme-engine: ([^>]{0,160})-->/).flatten.uniq
      delta = ThemeEngine::MISSES.each_with_object({}) { |(k, c), h| d = c - before.fetch(k, 0); h[k] = d if d.positive? }
      report[:pages] << { template: label, path: full, status: result.status, bytes: html.bytesize, ms: ms,
                          sections: html.scan(/id="shopify-section-([^"]+)"/).flatten.size,
                          liquid_errors: errors, engine_comments: comments, misses: delta }
    rescue StandardError => e
      report[:pages] << { template: label, path: full, exception: "#{e.class}: #{e.message[0, 300]}",
                          backtrace: e.backtrace.first(3) }
    end
    report[:misses] = ThemeEngine.miss_report(top: 300)
  end
ensure
  ActsAsTenant.without_tenant { Shop.where(id: shop.id).destroy_all rescue nil }
end
out ||= Rails.root.join("tmp/conformance-#{name.parameterize}-#{version}#{preset_label ? "-#{preset_label.parameterize}" : ""}.json").to_s
File.write(out, JSON.pretty_generate(report))
puts "#{name} #{version} #{preset_label}: pages=#{report[:pages].size} errors=#{report[:pages].sum { |p| (p[:liquid_errors] || []).size }} exceptions=#{report[:pages].count { |p| p[:exception] }} misskeys=#{report[:misses].size} out=#{out}"
