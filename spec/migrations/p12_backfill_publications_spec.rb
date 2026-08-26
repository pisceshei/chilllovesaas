# frozen_string_literal: true

require "rails_helper"

# 第 12 包 migration 20260826060000 的 `resource_publications` 回填。
#
# 🔴 **這支 spec 存在的唯一理由**（與 `p11_backfill_tenant_spec.rb` 同一條教訓）：
#   回填迴圈的本體只有在「資料庫裡**已經存在**待回填的資源」時才會被執行到。
#   ①CI 的 `db:migrate` 跑在**空資料庫**上；
#   ②開發庫也常剛好沒有；
#   ⇒ 迴圈本體在兩處都未執行，`db:migrate` 一路綠，只有正式環境會炸。
#
#   🔴 本次是**當場複驗到的**，不是引述教訓：同一支 migration 在本機
#   開發庫回填 **3 列**（有既有資料），在測試庫回填 **0 列**（空庫）——
#   兩次都 exit 0。若回填有 bug，測試庫那次不會發現。
RSpec.describe "20260826060000 resource_publications 回填" do
  let!(:shop) { create(:shop, subdomain: "backfill-pub") }

  # 回填邏輯的等價重現（與 migration 逐行對應）。
  def run_backfill
    created = 0
    ActsAsTenant.without_tenant do
      Publication.unscoped.where(auto_publish: true).group_by(&:shop_id).each do |shop_id, publications|
        publication_ids = publications.map(&:id)

        { "Product" => Product, "ProductVariant" => ProductVariant, "Collection" => Collection }.each do |type, klass|
          klass.unscoped.where(shop_id:).select(:id).find_in_batches(batch_size: 1_000) do |batch|
            ids = batch.map(&:id)
            existing = ResourcePublication.unscoped.where(
              shop_id:, publishable_type: type, publishable_id: ids, publication_id: publication_ids
            ).pluck(:publishable_id, :publication_id).to_set

            rows = ids.flat_map do |publishable_id|
              publication_ids.filter_map do |publication_id|
                next if existing.include?([ publishable_id, publication_id ])

                { shop_id:, publication_id:, publishable_type: type, publishable_id:,
                  published_at: Time.current, created_at: Time.current, updated_at: Time.current }
              end
            end
            next if rows.empty?

            ResourcePublication.unscoped.insert_all(rows)
            created += rows.size
          end
        end
      end
    end
    created
  end

  # 「回填前既有、且沒有發布列」的資源——正是正式環境的形態。
  # 🔴 用 `delete_all` 清掉 callback 剛建好的列，才回到 migration 要面對的起始狀態；
  #    不清就等於在測「已經有列時回填不重複建」，那是另一格。
  let!(:product) { ActsAsTenant.with_tenant(shop) { create(:product, shop:) } }
  let!(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, product:) } }

  before do
    ActsAsTenant.without_tenant { ResourcePublication.unscoped.where(shop_id: shop.id).delete_all }
  end

  it "🔴 在**沒有 current_tenant** 的情境下回填既有資源——不得 NoTenantSet" do
    expect(ActsAsTenant.current_tenant).to be_nil

    expect { run_backfill }.not_to raise_error

    rows = ActsAsTenant.without_tenant do
      ResourcePublication.unscoped.where(shop_id: shop.id).pluck(:publishable_type, :publishable_id)
    end
    expect(rows).to contain_exactly([ "Product", product.id ], [ "ProductVariant", variant.id ])
  end

  it "回填的列是**已發布**狀態（published_at 不為 NULL 且不在未來）" do
    run_backfill

    stamps = ActsAsTenant.without_tenant do
      ResourcePublication.unscoped.where(shop_id: shop.id).pluck(:published_at)
    end
    expect(stamps).to all(be_present)
    expect(stamps).to all(be <= Time.current)
  end

  it "冪等：回填跑兩次不會重複建列" do
    first = run_backfill
    expect(first).to be_positive

    expect(run_backfill).to eq(0)

    count = ActsAsTenant.without_tenant { ResourcePublication.unscoped.where(shop_id: shop.id).count }
    expect(count).to eq(first)
  end

  it "🔴 `auto_publish = false` 的管道不被回填" do
    manual = ActsAsTenant.with_tenant(shop) do
      Publication.create!(shop_id: shop.id, name: "手動管道", channel_handle: "manual-ch",
                          auto_publish: false, supports_future_publishing: false)
    end

    run_backfill

    ids = ActsAsTenant.without_tenant do
      ResourcePublication.unscoped.where(shop_id: shop.id).pluck(:publication_id).uniq
    end
    expect(ids).not_to include(manual.id)
  end

  it "🔴 跨租戶：只回填該店自己管道的列" do
    other = create(:shop, subdomain: "backfill-pub-other")
    ActsAsTenant.with_tenant(other) { create(:product, shop: other) }

    run_backfill

    mismatched = ActsAsTenant.without_tenant do
      ResourcePublication.unscoped
                         .joins("JOIN publications p ON p.id = resource_publications.publication_id")
                         .where("p.shop_id <> resource_publications.shop_id").count
    end
    expect(mismatched).to eq(0)
  end

  it "🔴 migration 原始碼必須把回填包在 without_tenant 內（守著這一行本身）" do
    # 上面幾格驗的是**邏輯**；這一格盯著 migration **檔案**——spec 用的是自己的
    # 邏輯副本，把 `without_tenant` 從 migration 拿掉，上面全部仍會綠。
    source = File.read(
      Rails.root.join("db/migrate/20260826060000_backfill_resource_publications.rb"),
      encoding: "UTF-8"
    )
    backfill = source[/say_with_time "backfill resource_publications.*?\n    end/m]

    expect(backfill).to be_present
    expect(backfill).to include("ActsAsTenant.without_tenant"),
      "回填未包在 without_tenant 內 ⇒ 正式環境只要有既有商品就 NoTenantSet"
  end
end
