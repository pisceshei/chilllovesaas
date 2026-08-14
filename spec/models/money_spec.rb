# frozen_string_literal: true

require "rails_helper"

RSpec.describe Money do
  # ── L1：值物件無隱式轉換（65 §C L1）─────────────────────────────────────────
  #
  # 🔴 這一組是**反射斷言**，不是行為斷言。理由：只要 `to_i` 存在，
  # `Integer()`、多數序列化器、字串插值都會**自動**呼叫它——
  # 那時 L2/L3/L4 三層全部失效，而且沒有任何一條行為測試會紅。
  describe "L1 無隱式轉換" do
    let(:storage) { described_class::Storage.from_cents(148_000, "JPY") }
    let(:decimal) { storage.to_decimal }

    it "Storage 不實作 to_i / to_int / coerce / to_str" do
      %i[to_i to_int coerce to_str].each do |method|
        expect(storage).not_to respond_to(method), "Money::Storage 不得實作 #{method}"
      end
    end

    it "Decimal 不實作 to_str（它內含字串，最容易被插值靜默展開）" do
      %i[to_i to_int coerce to_str].each do |method|
        expect(decimal).not_to respond_to(method), "Money::Decimal 不得實作 #{method}"
      end
    end

    it "to_s 不回傳裸金額（插值時看得出來是值物件）" do
      expect(storage.to_s).to include("Money::Storage")
      expect(storage.to_s).not_to eq("148000")
      expect("#{decimal}").not_to eq("1480.00")
    end
  end

  # ── L2：唯一建構路徑（65 §C L2）────────────────────────────────────────────
  #
  # 🔴 `Data.define` 有**三條**公開建構路徑，只關 `.new` 是擋不住的。
  # 三條都測，因為漏掉任何一條，L2 就是假的而測試仍然全綠。
  describe "L2 建構路徑" do
    it "關掉 .[]（與 .new 等價的建構器）" do
      expect { described_class::Storage[cents: 1, currency: "HKD"] }.to raise_error(NoMethodError)
      expect { described_class::Decimal[string: "1.00", currency: "HKD"] }.to raise_error(NoMethodError)
    end

    it "關掉 #with（它讓「換幣別、保留數字」變成一行）" do
      storage = described_class::Storage.from_cents(100, "HKD")
      expect(storage).not_to respond_to(:with)
    end

    # 🔴 allocate 產出的實例 `is_a?` 為真但欄位全 nil ——
    # L3 的 adapter 斷言只看 `is_a?`，所以這是一條真的能穿過型別防線的路徑。
    it "關掉 .allocate（它產出 is_a? 為真但欄位全 nil 的實例）" do
      expect { described_class::Storage.allocate }.to raise_error(NoMethodError)
      expect { described_class::Decimal.allocate }.to raise_error(NoMethodError)
    end
  end

  # ── R1 Storage ────────────────────────────────────────────────────────────
  describe described_class::Storage do
    it "from_cents 拒絕 Float（鐵律 3：出現 float 即 bug）" do
      expect { described_class.from_cents(1.5, "HKD") }.to raise_error(TypeError, /float/)
      expect { described_class.from_cents(BigDecimal("1.5"), "HKD") }.to raise_error(TypeError)
    end

    it "幣別正規化成大寫" do
      expect(described_class.from_cents(100, "hkd").currency).to eq("HKD")
    end

    # 🔴 65 §A.7：型別層不驗正負。在這裡驗非負會讓退款差額與撤銷整條卡死。
    it "接受負數（退款差額、撤銷；65 §A.7）" do
      expect(described_class.from_cents(-500, "HKD").cents).to eq(-500)
    end

    it "同幣別可比較" do
      a = described_class.from_cents(100, "HKD")
      b = described_class.from_cents(200, "HKD")
      expect(a).to be < b
      expect(a).to eq(described_class.from_cents(100, "HKD"))
    end

    # 跨幣別比較不得靜默回 false——「不同」與「不可比」是兩件事。
    it "跨幣別比較 raise，不是回 false" do
      a = described_class.from_cents(100, "HKD")
      b = described_class.from_cents(100, "JPY")
      expect { a < b }.to raise_error(Money::CurrencyMismatch)
    end
  end

  # ── R4 Decimal ────────────────────────────────────────────────────────────
  describe described_class::Decimal do
    it "T2：JPY 儲存 148000 ⇒ Offer.price 是 \"1480.00\"（62 §A.4）" do
      expect(Money::Storage.from_cents(148_000, "JPY").to_decimal.string).to eq("1480.00")
    end

    it "HKD 同樣是兩位（顯示位數不看幣別，2026-08-12 裁定二）" do
      expect(Money::Storage.from_cents(148_000, "HKD").to_decimal.string).to eq("1480.00")
    end

    it "拒絕不符 decimal_string_regex 的字串" do
      expect { described_class.from_string("1480", "HKD") }.to raise_error(ArgumentError)
      expect { described_class.from_string("HK$1480.00", "HKD") }.to raise_error(ArgumentError)
      expect { described_class.from_string("1,480.00", "HKD") }.to raise_error(ArgumentError)
    end

    it "允許負號（limits 的正則就是 ^-?\\d+\\.\\d{2}$）" do
      expect(described_class.from_string("-5.00", "HKD").string).to eq("-5.00")
    end

    it "to_storage 小數超過兩位 ⇒ raise，不 round（58 §G.3 規則 2）" do
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:money_boundary, :decimal_string_regex)
        .and_return('^-?\d+\.\d{1,4}$')
      expect { described_class.from_string("1.234", "HKD").to_storage }
        .to raise_error(Money::ExcessPrecision, /不得 round/)
    end

    it "往返一致（T12 的 R1↔R4 那一半）" do
      [ 0, 1, 148_000, -500, 9_223_372_036_854_775_807 ].each do |cents|
        storage = Money::Storage.from_cents(cents, "JPY")
        expect(storage.to_decimal.to_storage).to eq(storage), "cents=#{cents} 往返不一致"
      end
    end
  end

  # ── R3 Display ────────────────────────────────────────────────────────────
  describe described_class::Display do
    it "T1：JPY 儲存 148000 ⇒ 顯示兩位小數（裁定二）" do
      expect(described_class.call(Money::Storage.from_cents(148_000, "JPY"))).to eq("1480.00")
    end

    it "只收 Money::Storage" do
      expect { described_class.call(148_000) }.to raise_error(TypeError)
      expect { described_class.call("1480.00") }.to raise_error(TypeError)
    end

    it "🔴 尚未帶幣別符號——符號與千分位由市場的 locale 決定（M5）" do
      output = described_class.call(Money::Storage.from_cents(148_000, "HKD"))
      expect(output).not_to include("HK$")
      expect(output).not_to include(",")
    end
  end

  # ── 鐵律 6：不得硬編 ───────────────────────────────────────────────────────
  #
  # 🔴 這一條比 grep `100` 強：它證明**行為真的跟著設定走**。
  # grep 只能證明「原始碼裡沒有那個字面量」，stub 能證明「換了設定值，結果跟著換」。
  describe "上限值來自 limits.yml" do
    it "storage_scale 改變時，to_decimal 跟著變" do
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:money_boundary, :storage_scale_multiplier).and_return(1000)

      expect(Money::Storage.from_cents(148_000, "JPY").to_decimal.string).to eq("148.00")
    end

    it "app/models/money.rb 內沒有 to_f（鐵律 3）" do
      source = File.read(Rails.root.join("app/models/money.rb"), encoding: "UTF-8")
      expect(source).not_to include("to_f")
    end
  end
end
