# frozen_string_literal: true
# PoC harness：用 CHILL LOVE 引擎渲染 Ella 7.2.0 的「真實檔案＋真實實例資料」
# 目標 A：announcement-bar（header-group.json 實例，4 層 blocks 樹）
# 目標 B：商品卡 card-product-flex（product.json recommendations 實例的 product-slide-item 子樹 ×4 商品）
# 目標 C：main-product 商品詳情頁（product.json main 實例：static blocks＋9 個巢狀卡片）

$LOAD_PATH.unshift "/tmp/liquid/lib"
require_relative "engine"
require "fileutils"

ELLA = ENV.fetch("ELLA_DIR", "/home/claude/ella")
OUT  = File.expand_path("out", __dir__)
FileUtils.mkdir_p(OUT)

rt = ChillLove::ThemeRuntime.new(ELLA, design_mode: false)

# ---- 樣本商品（integer cents）----------------------------------------------
def product(title, handle, cents, compare, color)
  ChillLove::ProductDrop.new(
    "id" => rand(10_000), "title" => title, "handle" => handle, "vendor" => "CHILL LOVE",
    "type" => "Skincare", "price" => cents, "price_min" => cents, "price_max" => cents,
    "compare_at_price" => compare, "description" => "<p>#{title} — PoC sample.</p>",
    "tags" => ["poc"], "has_only_default_variant" => false,
    "images" => [ChillLove::ImageDrop.new(label: title, color: color),
                 ChillLove::ImageDrop.new(label: "#{title} 2", color: color)],
    "options_with_values" => [{ "name" => "Size", "position" => 1, "values" => %w[30ml 50ml] }],
    "variants" => [
      { "id" => 111, "title" => "30ml", "price" => cents, "compare_at_price" => compare,
        "available" => true, "sku" => "#{handle}-30", "options" => ["30ml"], "option1" => "30ml",
        "inventory_management" => "shopify", "inventory_policy" => "deny", "inventory_quantity" => 8,
        "requires_shipping" => true, "taxable" => true },
      { "id" => 112, "title" => "50ml", "price" => cents + 1200, "compare_at_price" => nil,
        "available" => true, "sku" => "#{handle}-50", "options" => ["50ml"], "option1" => "50ml",
        "inventory_management" => "shopify", "inventory_policy" => "deny", "inventory_quantity" => 3,
        "requires_shipping" => true, "taxable" => true },
    ]
  )
end

PRODUCTS = [
  product("Rose Hydration Serum", "rose-serum", 45_150, 52_000, "#e8d5d0"),
  product("Clay Renewal Mask", "clay-mask", 28_900, nil, "#ddc9b4"),
  product("Cream Silk Cleanser", "silk-cleanser", 19_800, 24_500, "#efe7da"),
  product("Amber Night Oil", "amber-oil", 61_200, nil, "#d9c2a7"),
]

sections_html = []

# ---- 目標 A：announcement-bar（真實 group 實例）------------------------------
hg = rt.load_json("sections/header-group.json")
ann_key = hg["order"].find { |k| hg["sections"][k]["type"] == "announcement-bar" }
rt.closest = ChillLove::ClosestDrop.new(product: PRODUCTS.first)
sections_html << ["目標 A — announcement-bar（header-group 真實實例，_group-announcement-bar → _group-announcement → 子卡片）",
                  rt.render_section(ann_key, hg["sections"][ann_key])]

# ---- 目標 B：商品卡 ×4（product.json recommendations 實例的靜態卡片子樹）----
pj  = rt.load_json("templates/product.json")
rec = pj["sections"]["product_recommendations_ecaxGU"]
card_section_src = <<~LIQUID
  <div class="poc-card-grid" style="display:grid;grid-template-columns:repeat(4,1fr);gap:24px;padding:32px;">
    {% content_for 'block', type: 'card-product-flex', id: 'product-slide-item' %}
  </div>
LIQUID
File.write("#{ELLA}/sections/poc-card-harness.liquid", card_section_src)
cards = PRODUCTS.map do |p|
  rt.closest = ChillLove::ClosestDrop.new(product: p)
  rt.render_section("poc-cards-#{p['handle']}",
                    { "type" => "poc-card-harness", "settings" => rec["settings"],
                      "blocks" => rec["blocks"], "block_order" => [] })
end
sections_html << ["目標 B — 商品卡 card-product-flex ×4（recommendations 真實實例子樹：media/info/title/price/button 巢狀卡片；closest.product 動態來源）",
                  %(<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:24px;padding:32px;">#{cards.join}</div>)]

# ---- 目標 C：main-product 商品詳情頁（真實 main 實例）------------------------
rt.closest = ChillLove::ClosestDrop.new(product: PRODUCTS.first)
rt.global_assigns["product"] = PRODUCTS.first
rt.global_assigns["template"] = ChillLove::TemplateDrop.new("product")
sections_html << ["目標 C — main-product 商品詳情頁（product.json main 真實實例：⚓media-gallery＋⚓product-details（9 個巢狀卡片）＋⚓sticky-atc）",
                  rt.render_section("main", pj["sections"]["main"], page_type: "product")]

# ---- 組頁 -------------------------------------------------------------------
FileUtils.rm_rf("#{OUT}/assets")
FileUtils.cp_r("#{ELLA}/assets", "#{OUT}/assets")
File.delete("#{ELLA}/sections/poc-card-harness.liquid")

# 真實管線：渲染 Ella 的 head 兩支 snippets（global-style＝:root 變數 1048 行；global-css＝元件樣式表）
head_src = "{% render 'global-style' %}\n{% render 'global-css' %}"
File.write("#{ELLA}/sections/poc-head-harness.liquid", head_src)
globals = rt.render_section("poc-head", { "type" => "poc-head-harness", "settings" => {} })
File.delete("#{ELLA}/sections/poc-head-harness.liquid")

html = <<~HTML
  <!doctype html>
  <html lang="zh-Hant">
  <head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>CHILL LOVE Liquid 引擎 PoC — 渲染 Ella 7.2.0 真實檔案</title>
  #{globals}
  <style>
    body{margin:0;font-family:Assistant,system-ui,sans-serif}
    .poc-banner{background:#1a1c1e;color:#fff;padding:14px 24px;font-size:14px;line-height:1.5}
    .poc-banner b{color:#7ee2b8}
    .poc-label{background:#f3efff;color:#6d28d9;font-size:13px;padding:8px 24px;border-top:1px solid #e3e3e6;border-bottom:1px solid #e3e3e6}
  </style>
  </head>
  <body>
  <div class="poc-banner"><b>CHILL LOVE Liquid 相容引擎 PoC</b> — 以 Shopify/liquid gem（MIT）＋自實作平台層（content_for/blocks 機制、drops、filters）渲染 <b>Ella 7.2.0 未經修改的原始檔案與真實模板實例資料</b>。樣式為 Ella 自帶 CSS；圖片為佔位 SVG；未實作屬性回 nil（詳 compat-report.json）。</div>
  #{sections_html.map { |(label, h)| %(<div class="poc-label">#{label}</div>\n#{h}) }.join("\n")}
  </body></html>
HTML
File.write("#{OUT}/index.html", html)

report = rt.compat_report
File.write("#{OUT}/compat-report.json", JSON.pretty_generate(report))

puts "HTML bytes: #{html.bytesize}"
puts "errors: #{report[:errors].size}"
report[:errors].first(15).each { |e| puts "  E: #{e}" }
puts "warnings: #{report[:warnings].size}"
report[:warnings].first(8).each { |w| puts "  W: #{w}" }
puts "top misses:"
report[:top_misses].first(18).each { |k, v| puts "  #{k} ×#{v}" }
