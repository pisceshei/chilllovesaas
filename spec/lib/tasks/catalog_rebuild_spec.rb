# frozen_string_literal: true

require "rails_helper"
require "rake"

# `catalog:rebuild:collections`＝dev doc §4／P11-B9 明文倚賴的**兜底**。
#
# 🔴 這一支存在的理由（2026-08-26 delta 審查 F6）：F2 讓 `Rebuild.call` 多出一種
#   「鎖等逾時、這一輪沒重建」的回傳，而它與「這個系列沒有 conditions source」
#   共用 `status: :skipped`。任務原本只數 `:error` ⇒ 兜底跑完什麼都沒做卻印
#   `rebuild OK` 並以 0 退出——運維只看得到綠色。fail-open 在兜底上比在主路徑上更糟。
RSpec.describe "rake catalog:rebuild:collections" do
  before(:all) do
    Rake::Task.clear
    Chilllove::Application.load_tasks
  end

  after(:all) { Rake::Task.clear }

  let!(:shop) { create(:shop, subdomain: "rake-rebuild") }
  let!(:collection) do
    ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "規則系列", handle: "rule-c",
                             collection_type: "smart", sort_order: "manual", description_html: "")
      CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                               target_type: "products", inclusion_match: "all", position: 0)
      c
    end
  end

  def run_task
    Rake::Task["catalog:rebuild:collections"].reenable
    Rake::Task["catalog:rebuild:collections"].invoke
  end

  it "🔴 G1 兜底面：工作清單＝全部智慧系列，零 source 的系列也要被造訪" do
    orphan = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "零條件", handle: "zero-src",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    visited = []
    allow(Collections::Rebuild).to receive(:call) do |shop:, collection:|
      visited << collection.id
      Collections::Rebuild::Result.new(status: :ok, inserted: 0, swept: 0, error: nil)
    end

    run_task
    expect(visited).to include(orphan.id),
      "兜底用 collection_sources 導出清單 ⇒ 最需要兜底的那一格（條件被清空）反而掃不到"
    expect(visited).to include(collection.id)
  end

  it "全部成功 ⇒ 印 rebuild OK、不 abort" do
    allow(Collections::Rebuild).to receive(:call)
      .and_return(Collections::Rebuild::Result.new(status: :ok, inserted: 1, swept: 0, error: nil))

    expect { run_task }.to output(/rebuild OK/).to_stdout
  end

  it "🔴 鎖等逾時的系列必須讓任務非零結束——兜底不得靜默回報成功" do
    allow(Collections::Rebuild).to receive(:call).and_return(
      Collections::Rebuild::Result.new(status: :skipped, inserted: 0, swept: 0,
                                       error: Collections::Rebuild::LOCK_TIMEOUT_ERROR)
    )

    expect { run_task }.to raise_error(SystemExit, /鎖等逾時未重建/).and output(/SKIPPED/).to_stdout
  end

  it "ERROR 的系列照舊非零結束" do
    allow(Collections::Rebuild).to receive(:call).and_return(
      Collections::Rebuild::Result.new(status: :error, inserted: 0, swept: 0, error: "unknown condition type")
    )

    expect { run_task }.to raise_error(SystemExit, /個系列 ERROR/)
  end

  it "沒有 conditions source 的普通跳過**不算**失敗（`:skipped` 的另一個意思）" do
    allow(Collections::Rebuild).to receive(:call)
      .and_return(Collections::Rebuild::Result.new(status: :skipped, inserted: 0, swept: 0, error: nil))

    expect { run_task }.to output(/rebuild OK/).to_stdout
  end

  it "🔴 L4（2026-08-26 第七輪）：真的跑任務——兜底必須依拓樸序，不 stub 引擎" do
    # 🔴 這一格存在的理由：既有五個 example 全部 `allow(Collections::Rebuild).to receive(:call)`，
    #   於是 rake 的**排序**在該檔構造上不可觀測——把 `ReferenceGraph.topological`
    #   那一行刪掉，整套仍然綠。K2 原本被抓到的形態（「resync 改了、兜底沒改」）
    #   會在測試面原樣重演。本格因此**不 stub 引擎**，走真實 Rebuild 並斷言成員。
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ], status: "active")
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    # A 排除 B、B 排除 C、C＝tag blue（商品沒有）⇒ C 空、B 含商品、A 應為空。
    # 建立序＝id 昇冪，與需要的計算序相反（最壞情況）。
    a, b, c = %w[l4-a l4-b l4-c].map do |handle|
      ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: handle, handle:,
                           collection_type: "smart", sort_order: "manual", description_html: "")
      end
    end
    ActsAsTenant.with_tenant(shop) do
      [ [ a, b ], [ b, c ] ].each do |(owner, referenced)|
        src = CollectionSource.create!(shop_id: shop.id, collection_id: owner.id, source_type: "conditions",
                                       target_type: "products", inclusion_match: "all", position: 0)
        CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: src.id, block: "inclusion",
                                     condition_type: "product_tag", relation: "includes",
                                     value_text: "red", position: 0)
        CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: src.id, block: "exclusion",
                                     condition_type: "collection", relation: "includes",
                                     value_int: referenced.id, position: 1)
      end
      src_c = CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                                       target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: src_c.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "blue", position: 0)
    end

    expect { run_task }.to output(/rebuild OK/).to_stdout

    members = lambda do |col|
      ActsAsTenant.with_tenant(shop) { CollectionMembership.where(collection_id: col.id).pluck(:product_id) }
    end
    expect(members.call(c)).to be_empty
    expect(members.call(b)).to eq([ product.id ])
    expect(members.call(a)).to be_empty,
      "兜底照 id 序跑 ⇒ A 讀到還沒重建的 B ⇒ 與 resync 給出不同答案（K2 重開）"
  end
end
