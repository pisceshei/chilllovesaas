# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::OptionValuesDigest do
  describe ".call" do
    it "順序無關：同一組座標不論輸入順序都得到同一個 digest" do
      a = described_class.call([ [ 7, 12 ], [ 3, 99 ] ])
      b = described_class.call([ [ 3, 99 ], [ 7, 12 ] ])
      expect(a).to eq(b)
    end

    it "不同座標得到不同 digest" do
      expect(described_class.call([ [ 7, 12 ] ])).not_to eq(described_class.call([ [ 7, 13 ] ]))
      expect(described_class.call([ [ 7, 12 ] ])).not_to eq(described_class.call([ [ 8, 12 ] ]))
    end

    it "輸出恆為 40 字元小寫 hex（model 的 format 驗證依賴這件事）" do
      expect(described_class.call([ [ 1, 2 ], [ 3, 4 ] ])).to match(/\A[0-9a-f]{40}\z/)
    end

    it "🔴 同一個選項出現兩次 ⇒ ArgumentError（DB 的 uq_pvov_variant_option 的 model 層對應）" do
      expect { described_class.call([ [ 7, 12 ], [ 7, 13 ] ]) }
        .to raise_error(ArgumentError, /只能有一個值/)
    end

    it "非整數輸入 ⇒ TypeError（不接受字串 id；含「看起來像數字」的字串）" do
      expect { described_class.call([ [ "7", "abc" ] ]) }.to raise_error(TypeError)
      # 🔴 "7" 這種可轉換字串**也要擋**：舊實作 Integer("7") 會放行成 7，
      #    但這裡的契約是「id 就是 DB 來的 Integer」，任何轉換都是掩蓋呼叫端的型別錯。
      expect { described_class.call([ [ "7", 12 ] ]) }.to raise_error(TypeError)
      expect { described_class.call([ [ nil, 1 ] ]) }.to raise_error(TypeError)
    end

    it "🔴 Float ⇒ TypeError（不得靜默截斷）" do
      # 舊實作 Integer(1.9) 回 1 ⇒ [[1.9, 2.9]] 與 [[1, 2]] 算出**同一個 digest**，
      # 而檔頭 @raise 一直宣稱非整數會 raise——Float 是唯一溜過去的類別（2026-08-16 修）。
      expect { described_class.call([ [ 1.9, 2.9 ] ]) }.to raise_error(TypeError)
      expect { described_class.call([ [ 1.0, 2 ] ]) }.to raise_error(TypeError)
    end
  end

  describe "NO_OPTIONS" do
    it "＝空集合的 SHA1，代表本尊的 Default Title 變體" do
      expect(described_class::NO_OPTIONS).to eq(Digest::SHA1.hexdigest(""))
    end

    # 🔴 migration 把這個值寫死成字面量（它不能依賴 app 代碼當時的形狀）。
    # 兩處必須一致，否則回填出來的 digest 與 model 算出來的不同 ⇒
    # 既有列與新列會被唯一索引視為不同座標。
    it "與 migration 的 EMPTY_DIGEST 字面量一致" do
      source = Rails.root.join("db/migrate/20260816000000_create_product_variant_option_values.rb").read
      literal = source[/EMPTY_DIGEST\s*=\s*"([0-9a-f]{40})"/, 1]
      expect(literal).to eq(described_class::NO_OPTIONS)
    end
  end

  describe ".canonical" do
    it "依 product_option_id 升冪，格式為 選項id:值id 以逗號相接" do
      expect(described_class.canonical([ [ 7, 12 ], [ 3, 99 ] ])).to eq("3:99,7:12")
    end

    # 🔴 單射性：兩個 id 都是十進位整數（不含 `:` 與 `,`）⇒ 正規化字串可唯一解析回原集合。
    # 這一條釘住的是「日後有人把非數字塞進來時，必須改成長度前綴編碼」的前提。
    it "不同座標集合不會產生相同的正規化字串" do
      seen = {}
      [ [ [ 1, 23 ] ], [ [ 12, 3 ] ], [ [ 1, 2 ], [ 3, 4 ] ], [ [ 1, 234 ] ] ].each do |pairs|
        canonical = described_class.canonical(pairs)
        expect(seen).not_to have_key(canonical), "#{pairs.inspect} 與 #{seen[canonical].inspect} 撞了"
        seen[canonical] = pairs
      end
    end
  end
end
