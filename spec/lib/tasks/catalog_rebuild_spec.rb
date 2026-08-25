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
end
