# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-6：filters——sort_by／within／link_to_tag／link_to_add_tag／link_to_remove_tag／
# default_pagination／color_to_hsl／color_to_rgb／md5（官方 shopify.dev filters/* 各頁，取證 2026-09-02；
# D78 triage 已驗證 link_to_add_tag／link_to_remove_tag／url_for_type／sort_by，未驗證 default_pagination／
# color_to_hsl／md5；`within` 原為 no-op stub、三套主題合計用量最高）。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤）：
#   T1 sort_by："/collections/sale-potions?sort_by=best-selling"（殺：no-op／用 `&` 開頭）
#   T2 within："/collections/sale-potions/products/draught-of-immortality"；nil 系列原樣（殺：no-op stub）
#   T3 link_to_tag：系列 href＝當前 URL＋"/"＋tag、title "Show products matching tag X"；
#      部落格 href＝/tagged/X、title "Show articles tagged X"（殺：href 只放 tag）
#   T4 link_to_add_tag：title "Narrow selection to products matching tag X"、href 帶既有 current_tags＋X；
#      已啟用的 tag 只出純文字（殺：無視 current_tags）
#   T5 link_to_remove_tag：href 去掉該 tag、最後一個時回系列根（殺：與 add 同形）
#   T6 default_pagination 官方逐字例（殺：格式漂移／next 文案）
#   T7 color_to_hsl '#EA5AB9' ⇒ 'hsl(320, 77%, 64%)'；alpha ⇒ hsla（殺：ColorDrop hue 恆 0 的假值）
#   T8 md5 '' ⇒ d41d8cd98f00b204e9800998ecf8427e
RSpec.describe "ThemeEngine filters gap (PR-6)" do
  def render(src, assigns = {}, registers = {})
    Liquid::Template.parse(src, environment: ThemeEngine::Runtime::ENVIRONMENT)
                    .render(assigns, registers: { request_path: "/collections/all" }.merge(registers))
  end

  let(:shop) { create(:shop, subdomain: "fg-shop") }
  let(:collection_drop) do
    ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "Sale potions", handle: "sale-potions", sort_order: "manual",
                             description_html: "")
      ThemeEngine::CollectionDrop.new(c)
    end
  end

  it "T1 sort_by（官方例）＋既有 query 用 &" do
    expect(render("{{ collection.url | sort_by: 'best-selling' }}", "collection" => collection_drop))
      .to eq("/collections/sale-potions?sort_by=best-selling")
    expect(render("{{ '/collections/sale-potions?page=2' | sort_by: 'manual' }}"))
      .to eq("/collections/sale-potions?page=2&sort_by=manual")
  end

  it "T2 🔴 within（官方例）；nil 系列原樣；帶 locale 前綴沿用系列 URL" do
    expect(render("{{ '/products/draught-of-immortality' | within: collection }}", "collection" => collection_drop))
      .to eq("/collections/sale-potions/products/draught-of-immortality")
    expect(render("{{ '/products/x' | within: nothing }}")).to eq("/products/x")
    prefixed = ActsAsTenant.with_tenant(shop) do
      ThemeEngine::CollectionDrop.new(Collection.find_by!(handle: "sale-potions"), url_prefix: "/en-hk")
    end
    collection_drop # 建立系列列
    expect(render("{{ '/en-hk/products/x' | within: collection }}", "collection" => prefixed))
      .to eq("/en-hk/collections/sale-potions/products/x")
  end

  it "T3 link_to_tag：系列與部落格兩形" do
    expect(render("{{ 'extra-potent' | link_to_tag: 'extra-potent' }}"))
      .to eq('<a href="/collections/all/extra-potent" title="Show products matching tag extra-potent">extra-potent</a>')
    expect(render("{{ 'news' | link_to_tag: 'news' }}", {}, { request_path: "/blogs/journal" }))
      .to eq('<a href="/blogs/journal/tagged/news" title="Show articles tagged news">news</a>')
  end

  it "T4 🔴 link_to_add_tag：帶既有 current_tags；已啟用者純文字" do
    out = render("{{ 'fresh' | link_to_add_tag: 'fresh' }}|{{ 'healing' | link_to_add_tag: 'healing' }}",
                 { "current_tags" => [ "healing" ] }, { request_path: "/collections/all/healing" })
    expect(out).to eq('<a href="/collections/all/healing+fresh" title="Narrow selection to products matching tag fresh">fresh</a>|healing')
    expect(render("{{ 'fresh' | link_to_add_tag: 'fresh' }}"))
      .to eq('<a href="/collections/all/fresh" title="Narrow selection to products matching tag fresh">fresh</a>')
  end

  it "T5 link_to_remove_tag：去掉該 tag；最後一個回系列根；部落格用 /tagged/" do
    out = render("{{ 'healing' | link_to_remove_tag: 'healing' }}|{{ 'fresh' | link_to_remove_tag: 'fresh' }}",
                 { "current_tags" => %w[healing fresh] }, { request_path: "/collections/all/healing+fresh" })
    expect(out).to eq('<a href="/collections/all/fresh" title="Remove tag healing">healing</a>|' \
                      '<a href="/collections/all/healing" title="Remove tag fresh">fresh</a>')
    expect(render("{{ 'fresh' | link_to_remove_tag: 'fresh' }}", { "current_tags" => [ "fresh" ] },
                  { request_path: "/collections/all/fresh" }))
      .to eq('<a href="/collections/all" title="Remove tag fresh">fresh</a>')
    expect(render("{{ 'news' | link_to_remove_tag: 'news' }}", { "current_tags" => %w[news tips] },
                  { request_path: "/blogs/journal/tagged/news+tips" }))
      .to eq('<a href="/blogs/journal/tagged/tips" title="Remove tag news">news</a>')
  end

  it "T6 🔴 default_pagination 官方逐字例＋next／previous 參數" do
    paginate = ThemeEngine::PaginateDrop.new(items: 3, page_size: 2, current_page: 1,
                                             url_builder: ->(n) { "/services/liquid_rendering/resource?page=#{n}" })
    expect(render("{{ paginate | default_pagination }}", "paginate" => paginate)).to eq(
      '<span class="page current">1</span> <span class="page"><a href="/services/liquid_rendering/resource?page=2" title="">2</a></span> ' \
      '<span class="next"><a href="/services/liquid_rendering/resource?page=2" title="">Next &raquo;</a></span>'
    )
    page2 = ThemeEngine::PaginateDrop.new(items: 3, page_size: 2, current_page: 2,
                                          url_builder: ->(n) { "/r?page=#{n}" })
    expect(render("{{ paginate | default_pagination: next: '下一頁', previous: '上一頁' }}", "paginate" => page2)).to eq(
      '<span class="prev"><a href="/r?page=1" title="">上一頁</a></span> ' \
      '<span class="page"><a href="/r?page=1" title="">1</a></span> <span class="page current">2</span>'
    )
  end

  it "T7 🔴 color_to_hsl／color_to_rgb 官方例；alpha ⇒ hsla／rgba" do
    expect(render("{{ '#EA5AB9' | color_to_hsl }}|{{ '#EA5AB9' | color_to_rgb }}|{{ 'rgba(234, 90, 185, 0.5)' | color_to_hsl }}"))
      .to eq("hsl(320, 77%, 64%)|rgb(234, 90, 185)|hsla(320, 77%, 64%, 0.5)")
  end

  it "T8 md5 官方例" do
    expect(render("{{ '' | md5 }}|{{ 'hello' | md5 }}"))
      .to eq("d41d8cd98f00b204e9800998ecf8427e|5d41402abc4b2a76b9719d911017c592")
  end
end
