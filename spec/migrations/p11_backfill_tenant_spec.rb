# frozen_string_literal: true

require "rails_helper"

# 第 11 包 migration 20260826058000 的 `product_tags` 回填。
#
# 🔴 **這支 spec 存在的唯一理由**（2026-08-26 部署實測）：回填迴圈的本體只有在
#   「資料庫裡**已經存在帶標籤的商品**」時才會被執行到。
#   ①CI 的 `db:migrate` 跑在**空資料庫**上（零商品）；
#   ②開發庫剛好也沒有帶標籤的商品；
#   ⇒ 迴圈本體在兩處都從未執行，`db:migrate` 一路綠。
#   而正式環境有帶標籤的商品 ⇒ 一部署就 `ActsAsTenant::Errors::NoTenantSet`
#   （`require_tenant = true` ＋ `ProductTag` 的 `acts_as_tenant :shop`，
#   而 `.unscoped` 只拿掉 default scope、擋不住寫入的租戶要求）。
#
#   🔴 教訓：**「migration 在 CI 綠」不證明「migration 對既有資料安全」**。
#   凡是帶資料回填的 migration，都要有一支「先種既有資料、再在**無租戶**情境下
#   跑回填」的 spec——十一輪對抗審查與綠燈 CI 在結構上都證明不了這件事。
RSpec.describe "20260826058000 product_tags 回填" do
  let(:shop) { create(:shop, subdomain: "backfill-tenant") }

  # 回填邏輯的等價重現（與 migration 逐行對應；migration 本身不可在 spec 內重跑，
  # 因為它的 DDL 已經套用過——`if_not_exists` 讓它冪等，但 spec 要驗的是回填那一段）。
  def run_backfill
    limit = Limits.fetch(:product, :tag_max_chars)
    ActsAsTenant.without_tenant do
      Product.unscoped.where.not(tags: []).find_each do |product|
        seen = {}
        Array(product.tags).each do |raw|
          key = Tags::Normalize.key(raw)
          next if key.empty?
          next if seen.key?(key)
          next if key.length > limit || raw.to_s.length > limit

          seen[key] = raw
          ProductTag.unscoped.find_or_create_by!(
            shop_id: product.shop_id, product_id: product.id, tag_key: key
          ) { |row| row.tag_display = raw }
        end
      end
    end
  end

  before do
    ActsAsTenant.with_tenant(shop) do
      create(:product, shop:, title: "帶標籤的既有商品", tags: [ "Red_New", "夏季" ])
    end
    ActsAsTenant.with_tenant(shop) { ProductTag.unscoped.where(shop_id: shop.id).delete_all }
  end

  it "🔴 在**沒有 current_tenant** 的情境下回填既有標籤——不得 NoTenantSet" do
    # migration 跑在 `bin/rails db:migrate`，那裡沒有任何 current_tenant。
    expect(ActsAsTenant.current_tenant).to be_nil

    expect { run_backfill }.not_to raise_error

    keys = ActsAsTenant.with_tenant(shop) { ProductTag.where(shop_id: shop.id).pluck(:tag_key) }
    expect(keys).to contain_exactly("red-new", "夏季")
  end

  it "冪等：回填跑兩次不會重複建列" do
    run_backfill
    expect { run_backfill }.not_to raise_error

    count = ActsAsTenant.with_tenant(shop) { ProductTag.where(shop_id: shop.id).count }
    expect(count).to eq(2)
  end

  it "🔴 migration 原始碼必須把回填包在 without_tenant 內（守著這一行本身）" do
    # 上面兩格驗的是**邏輯**；這一格盯著 migration **檔案**——避免有人把
    # `without_tenant` 從 migration 拿掉而 spec 仍然綠（spec 用的是自己的副本）。
    source = File.read(
      Rails.root.join("db/migrate/20260826058000_create_smart_collection_foundation.rb"),
      encoding: "UTF-8"
    )
    backfill = source[/say_with_time "backfill product_tags.*?\n    end/m]

    expect(backfill).to be_present
    expect(backfill).to include("ActsAsTenant.without_tenant"),
      "回填未包在 without_tenant 內 ⇒ 正式環境只要有帶標籤的商品就 NoTenantSet"
  end
end
