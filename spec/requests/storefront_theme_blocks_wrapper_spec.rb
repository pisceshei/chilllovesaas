# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-2：theme block 包裝／`tag: null`／隱藏 block／section 本地 blocks。
# 官方：shopify.dev theme-blocks/schema（tag／class）、section-schema（blocks）、
# help.shopify.com sections-and-blocks（Hide）——取證 2026-09-02；真店 hoko.vip（Ella）逐字包裝形。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤；每格點名它要殺的反向實作）：
#   W1 預設包裝 `<div id="shopify-block-{id}" class="shopify-block">`（殺：無 tag 鍵就不包／包裝無 id）
#   W2 `"tag": null` ⇒ 不包（殺：null 也套 div）
#   W3 `tag`＋`class` ⇒ `<section … class="shopify-block boxed">`（殺：class 不接在 shopify-block 後）
#   W4 `disabled: true` 的 theme block 不渲染、不進 section.blocks（殺：只跳 section 級 disabled）
#   W5 section 本地 blocks（無 blocks/*.liquid）進 section.blocks 且吃本地 settings 預設；
#      隱藏者排除；與 @theme 塊混排（殺：只認 theme block 檔 ⇒ 本地塊靜默丟棄）
#   W6 包裝上沒有其他屬性（殺：把 editor 屬性硬塞進包裝）
RSpec.describe "Storefront theme block wrapper / disabled / section-local blocks", type: :request do
  let(:shop) { create(:shop, subdomain: "tbw-shop") }

  before do
    host! "tbw-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    get "/"
    expect(response).to have_http_status(:ok)
  end

  it "W1 🔴 預設 div 包裝帶 shopify-block-{id}；content_for 'blocks' 與 render child_block 兩路皆包" do
    # E8 渲染 1:1：id＝本尊實例形 `{A+17 碼}__{key}`（BlockIds）
    expect(response.body).to match(%r{<div id="shopify-block-A[A-Za-z0-9]{17}__p1" class="shopify-block"><i class="pblk" data-tone="warm">})
    expect(response.body).to match(%r{<div id="shopify-block-A[A-Za-z0-9]{17}__c1" class="shopify-block"><b class="leaf">子一</b>})
  end

  it "W2 🔴 tag: null ⇒ 直接輸出內容、無包裝" do
    expect(response.body).to include('<u class="bare">裸</u>')
    expect(response.body).not_to match(/id="shopify-block-[^"]*b1"/)
  end

  it "W3 tag＋class ⇒ 指定元素、class 接在 shopify-block 之後" do
    expect(response.body).to match(%r{<section id="shopify-block-A[A-Za-z0-9]{17}__b2" class="shopify-block boxed"><span class="boxed-in">盒</span>})
  end

  it "W4 🔴 disabled theme block 不渲染" do
    expect(response.body).not_to include("隱藏塊")
    expect(response.body).not_to match(/id="shopify-block-[^"]*b3"/)
  end

  it "W5 🔴 section 本地 blocks：渲染、吃本地預設、隱藏者排除、與 @theme 塊混排、size 同源" do
    expect(response.body).to include('<em class="lb" data-type="text" >一|3</em>')
    expect(response.body).to include('<em class="lb" data-type="text" >dflt|3</em>')
    expect(response.body).not_to include("藏|")
    expect(response.body).to include('<em class="lb" data-type="_leaf" >|</em>')
    expect(response.body).to include('<span id="blc">3</span>')
  end

  it "W6 包裝上只有 id 與 class（真店 hoko.vip 形）" do
    wrappers = response.body.scan(/<(?:div|section) id="shopify-block-[^"]*"[^>]*>/)
    expect(wrappers).not_to be_empty
    expect(wrappers).to all(match(/\A<(?:div|section) id="shopify-block-[^"]+" class="shopify-block[^"]*">\z/))
  end
end
