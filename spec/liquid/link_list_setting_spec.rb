# frozen_string_literal: true

require "rails_helper"

# E3c：`link_list` 型 setting 必須回 linklist 物件（Ella header：`{% for link in header_settings.menu.links %}`），
# 原本回 handle 字串 ⇒ `.links` 為 nil ⇒ demo 店主選單整條空白（2026-09-03 與本尊並排實錘）。
RSpec.describe "ThemeEngine link_list setting（E3c）" do
  let(:shop) { create(:shop) }

  before do
    ActsAsTenant.with_tenant(shop) do
      menu = Menu.create!(shop_id: shop.id, handle: "main-menu", title: "Main menu")
      [ [ "Home", "frontpage", nil ], [ "Catalog", "catalog", nil ], [ "Contact", "http", "/pages/contact" ] ]
        .each_with_index do |(title, item_type, url), index|
        MenuItem.create!(shop_id: shop.id, menu:, title:, item_type:, url:, position: index + 1)
      end
    end
  end

  def render(template, values)
    settings = ThemeEngine::SettingsDrop.new(values, { "menu" => "link_list" })
    context = Liquid::Context.new({ "linklists" => ThemeEngine::LinkListsDrop.new(shop) }, { "settings" => settings }, {})
    # 渲染在租戶語境內（PageRenderer 同樣在 with_tenant 裡跑；Menu 為 acts_as_tenant 表）
    ActsAsTenant.with_tenant(shop) { Liquid::Template.parse(template).render(context) }
  end

  it "LL1 🔴 handle ⇒ linklist 物件：`.links` 依 position 列出標題；`.handle`／`.title` 可讀" do
    out = render("{% for link in settings.menu.links %}{{ link.title }},{% endfor %}|{{ settings.menu.handle }}|{{ settings.menu.title }}",
                 { "menu" => "main-menu" })
    expect(out).to eq("Home,Catalog,Contact,|main-menu|Main menu")
  end

  it "LL2 空值與查無 handle ⇒ nil（for 迴圈為空、不炸）" do
    expect(render("[{% for link in settings.menu.links %}x{% endfor %}]", { "menu" => "" })).to eq("[]")
    expect(render("[{% for link in settings.menu.links %}x{% endfor %}]", { "menu" => "no-such-menu" })).to eq("[]")
  end

  it "LL3 無 linklists 語境（單元測試／無 context）⇒ nil，不回字串" do
    drop = ThemeEngine::SettingsDrop.new({ "menu" => "main-menu" }, { "menu" => "link_list" })
    expect(drop.liquid_method_missing("menu")).to be_nil
  end
end
