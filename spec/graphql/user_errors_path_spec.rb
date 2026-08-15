# frozen_string_literal: true

require "rails_helper"

# 每一條都對得上 `docs/research/28` §0.3.1 的一條官方依據。
RSpec.describe UserErrors::Path do
  describe "剝 input 外殼（官方 /mutations/productDelete 回 [\"id\"] 不是 [\"input\",\"id\"]）" do
    it "第一段是 input 時剝掉" do
      expect(described_class.build(:input, :id)).to eq([ "id" ])
      expect(described_class.build(:input, :lock_version)).to eq([ "lockVersion" ])
    end

    it "只剝第一段——巢狀的 input 欄位名不受影響" do
      expect(described_class.build(:product, :input)).to eq(%w[product input])
    end

    it "只剝逐字等於 input 的參數；其他具名參數會進 path" do
      # 官方 productVariantsBulkCreate(productId:, variants:) 回 ["productId"]。
      expect(described_class.build(:product_id)).to eq([ "productId" ])
      expect(described_class.build(:variants, 0, :option_values, 0)).to eq(%w[variants 0 optionValues 0])
    end
  end

  describe "陣列索引是十進位裸字串段" do
    it "Integer 轉成不補零的十進位字串" do
      expect(described_class.build(:titles, 0, :value)).to eq(%w[titles 0 value])
      expect(described_class.build(:titles, 12, :value)).to eq(%w[titles 12 value])
    end

    it "path 允許終止於索引段（官方 [\"variants\",\"0\",\"optionValues\",\"0\"]）" do
      expect(described_class.build(:variants, 0)).to eq(%w[variants 0])
    end
  end

  describe "camelCase" do
    it "底線命名轉成 camelCase" do
      expect(described_class.build(:change_from_quantity)).to eq([ "changeFromQuantity" ])
    end

    it "已經是 camelCase 或單字的原樣保留" do
      expect(described_class.build(:lockVersion)).to eq([ "lockVersion" ])
      expect(described_class.build(:title)).to eq([ "title" ])
    end
  end

  describe "無法歸屬時回 nil（不是空陣列）" do
    it "沒有任何段" do
      expect(described_class.build).to be_nil
    end

    it "只有一個被剝掉的 input" do
      expect(described_class.build(:input)).to be_nil
    end

    it "全部是 nil 段" do
      expect(described_class.build(nil, nil)).to be_nil
    end
  end

  # 🔴 Checkout Validation Function 用的是 `target: "$.cart.deliveryGroups[0]..."`，
  # 那是**另一個介面的另一套語法**，不得與 userErrors.field 混用。
  describe "拒絕 JSONPath 風格" do
    it "含 [ ] $ . 任一字元即 raise" do
      # 不用 %w[...]——裡面的 `]` 會把字面量提前結束（我第一版就是這樣寫壞的）。
      [ "cart[0]", "$.cart", "cart.items", "a]b" ].each do |bad|
        expect { described_class.build(bad) }.to raise_error(ArgumentError, /JSONPath/)
      end
    end

    it "空字串段 raise" do
      expect { described_class.build("") }.to raise_error(ArgumentError, /不得為空/)
    end
  end
end
