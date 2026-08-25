# frozen_string_literal: true

require "rails_helper"

# 第 11 包：系列引用圖（三條求值路徑共用的排序與反向傳播來源）。
RSpec.describe Collections::ReferenceGraph do
  let(:shop) { create(:shop, subdomain: "ref-graph") }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # 建 n 個智慧系列，回傳 id 陣列（建立序＝id 昇冪）。
  def collections!(count)
    Array.new(count) do |i|
      Collection.create!(shop_id: shop.id, title: "C#{i}", handle: "rg-#{i}",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
  end

  # owner 排除 referenced。
  def reference!(owner, referenced)
    source = CollectionSource.find_or_create_by!(shop_id: shop.id, collection_id: owner.id,
                                                 source_type: "conditions") do |src|
      src.target_type = "products"
      src.inclusion_match = "all"
      src.position = 0
    end
    CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: source.id,
                                 block: "exclusion", condition_type: "collection",
                                 relation: "includes", value_int: referenced.id,
                                 position: source.rules.count)
  end

  describe ".topological" do
    it "被引用者排在引用者之前" do
      a, b, c = collections!(3)
      reference!(a, b)
      reference!(b, c)
      ids = [ a.id, b.id, c.id ]

      order = described_class.topological(shop, ids)
      expect(order).to match_array(ids), "回傳必須是 ids 的排列（不多不少）"
      expect(order.index(c.id)).to be < order.index(b.id)
      expect(order.index(b.id)).to be < order.index(a.id)
    end

    it "沒有引用時原樣回傳" do
      ids = collections!(3).map(&:id)
      expect(described_class.topological(shop, ids)).to eq(ids)
    end

    it "🔴 環（A⇄B）不得無窮迴圈，且仍回傳完整排列" do
      a, b = collections!(2)
      reference!(a, b)
      reference!(b, a)
      ids = [ a.id, b.id ]

      order = nil
      expect { order = described_class.topological(shop, ids) }.not_to raise_error
      expect(order).to match_array(ids)
    end

    it "三元環也一樣" do
      a, b, c = collections!(3)
      reference!(a, b)
      reference!(b, c)
      reference!(c, a)
      ids = [ a.id, b.id, c.id ]

      expect(described_class.topological(shop, ids)).to match_array(ids)
    end

    it "引用到不在清單內的系列（已刪／manual）不影響排列完整性" do
      a, b = collections!(2)
      reference!(a, b)
      ids = [ a.id ]   # b 不在清單內

      expect(described_class.topological(shop, ids)).to eq([ a.id ])
    end

    it "🔴 K1（2026-08-26 第六輪）：深引用鏈不得 SystemStackError（迭代 DFS，非遞迴）" do
      # 初版是 lambda 遞迴，鏈長約 1100 就爆堆疊；而 SystemStackError **不是**
      # StandardError ⇒ Events::Relay 的 rescue 接不到 ⇒ 整批事件（含其他商店的）
      # 不投遞、該事件永遠進不了 dead-letter（永久毒丸）。
      depth = 1500
      cols = collections!(depth)
      cols.each_cons(2) { |owner, referenced| reference!(owner, referenced) }
      ids = cols.map(&:id)

      order = nil
      expect { order = described_class.topological(shop, ids) }.not_to raise_error
      expect(order).to match_array(ids)
      # 最深的被引用者排最前、鏈頭排最後。
      expect(order.first).to eq(ids.last)
      expect(order.last).to eq(ids.first)
    end
  end

  describe ".referrers" do
    it "回傳引用該系列的那些（＝它變動後要跟著重算的）" do
      a, b, c = collections!(3)
      reference!(a, c)
      reference!(b, c)

      expect(described_class.referrers(shop, c.id)).to match_array([ a.id, b.id ])
      expect(described_class.referrers(shop, a.id)).to be_empty
    end
  end
end
