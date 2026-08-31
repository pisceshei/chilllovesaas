# frozen_string_literal: true

require "rails_helper"

RSpec.describe Psp::Registry do
  def load_fixture(name)
    YAML.safe_load_file(Rails.root.join("spec/fixtures/psp_packs/#{name}.yml"))
  end

  # ── 🔴 本檔最重要的一條 ─────────────────────────────────────────────────────
  #
  # registry 有**兩個來源，鍵型別不同**：
  #   生產 = config/limits.yml 經 deep_symbolize_keys ⇒ **Symbol**
  #   測試 = YAML.safe_load_file ⇒ **String**
  # 而 65 §D.3 的「空表 ≠ 缺鍵」又逼實作必須用 `Hash#key?`——它對兩者不通用。
  #
  # 不收斂的後果：整份 §H 測試矩陣**證明不了生產路徑**。
  # 第一個真 pack 進 limits.yml 時，`pack.key?("amount_format")` 回 false ⇒
  # 每一個生產 pack 都被判成缺必填鍵、永遠不得 enable，
  # 而錯誤訊息會說「缺 amount_format」——**YAML 裡明明逐字寫著**。
  describe "🔴 兩種來源的鍵型別必須在入口收斂" do
    let(:string_keyed) { load_fixture("matrix") }
    let(:symbol_keyed) { string_keyed.deep_symbolize_keys }

    it "String 鍵與 Symbol 鍵餵同一份 pack，行為完全一致" do
      from_string = described_class.new(string_keyed)
      from_symbol = described_class.new(symbol_keyed)

      expect(from_string.codes).to eq(from_symbol.codes)

      from_string.codes.each do |code|
        a = from_string.fetch(code)
        b = from_symbol.fetch(code)
        expect(a.amount_format).to eq(b.amount_format), "#{code} 的 amount_format 不一致"
        expect(a.amount_value_class).to eq(b.amount_value_class)
        %w[JPY KRW HKD USD TWD KWD].each do |currency|
          # minor unit 只對 minor_units 型 pack 有意義（decimal_string 型會明確 raise）。
          if a.amount_format == :minor_units
            expect(a.minor_unit_exponent(currency)).to eq(b.minor_unit_exponent(currency)),
              "#{code}/#{currency} 的 exponent 不一致"
          end
          expect(a.divisibility_for(currency)).to eq(b.divisibility_for(currency)),
            "#{code}/#{currency} 的 divisibility 不一致"
        end
      end
    end

    it "幣別鍵大小寫也收斂（pack 是人手寫的 YAML）" do
      registry = described_class.new(load_fixture("matrix"))
      # fixture 的 lowercase_keys 逐字寫的是 `twd: 2` 與 `twd: 100`。
      pack = registry.fetch(:lowercase_keys)
      expect(pack.minor_unit_exponent("TWD")).to eq(2)
      expect(pack.divisibility_for("TWD")).to eq(100)
    end
  end

  describe "生產 registry" do
    it "讀 limits.yml 的 psp_packs，且目前沒有任何 enabled 的 pack" do
      # 65 §D.3 逐字：「本區塊目前沒有任何 enabled 的 pack，也不得有。」
      expect(Psp.registry.enabled).to be_empty
    end

    it "🔴 enable_gates_registered 不是 pack（把它當 pack 會在啟動時就炸）" do
      expect(Psp.registry.codes).not_to include(:enable_gates_registered)
    end
  end

  describe "查詢" do
    subject(:registry) { described_class.new(load_fixture("matrix")) }

    it "fetch 不分大小寫" do
      expect(registry.fetch("ISO_MINOR").amount_format).to eq(:minor_units)
    end

    it "找不到時 raise 並列出已宣告的 pack" do
      expect { registry.fetch(:nope) }.to raise_error(Psp::PackNotFound, /已宣告/)
    end

    # 🔴 對 decimal_string 型 pack 問 minor unit 是呼叫端的錯。
    # 不明確 raise 的話會拋 `KeyError: key not found: :minor_unit_overrides`，
    # 而那個訊息會讓人以為 pack 漏了鍵，於是去補一個**不該存在**的鍵。
    it "對 decimal_string 型 pack 問 minor unit ⇒ 明確 raise（不是 KeyError）" do
      expect { registry.fetch(:decimal_two).minor_unit_exponent("JPY") }
        .to raise_error(Psp::PackInvalid, /不用 minor unit/)
    end
  end
end

RSpec.describe Psp::Pack do
  def invalid_declaration(name)
    YAML.safe_load_file(Rails.root.join("spec/fixtures/psp_packs/invalid.yml")).fetch(name)
  end

  def build(name)
    Psp::Registry.new(name => invalid_declaration(name))
  end

  # 65 §K 第 7 條：檢查綠不算交付，要證明**每一個違反 fixture 各自被擋下**。
  describe "🔴 不合法的宣告必須在建構期就 raise" do
    it "T19 未宣告 amount_format ⇒ raise（不得預設 minor_units）" do
      expect { build("no_format") }.to raise_error(Psp::PackInvalid, /amount_format/)
    end

    it "A6 decimal_places > 2 ⇒ raise（靜默的精度謊報）" do
      expect { build("too_many_places") }.to raise_error(Psp::PackInvalid, /decimal_places=3/)
    end

    # 🔴 A6b（2026-08-15，PR #29 驗收指出）。本輪之前這兩個宣告是**合法**的，
    # 而它們會讓 `to_psp_decimal` 靜默四捨五入 ⇒ 送款金額 ≠ 帳上金額。
    it "A6b decimal_places = 1 ⇒ raise（會靜默湊整：14.85 送成 14.9）" do
      expect { build("too_few_places") }.to raise_error(Psp::PackInvalid, /decimal_places=1 < 2/)
    end

    it "A6b decimal_places = 0 ⇒ raise" do
      expect { build("zero_places") }.to raise_error(Psp::PackInvalid, /decimal_places=0 < 2/)
    end

    it "🔴 空表 ≠ 缺鍵：divisibility 整個鍵不見 ⇒ raise" do
      expect { build("missing_divisibility") }.to raise_error(Psp::PackInvalid, /divisibility/)
    end

    it "缺 divisibility_scope ⇒ raise（V-206 未結案）" do
      expect { build("missing_scope") }.to raise_error(Psp::PackInvalid, /divisibility_scope/)
    end

    it "enable_gate 非空卻 enabled: true ⇒ raise" do
      expect { build("gated_but_enabled") }.to raise_error(Psp::PackInvalid, /V-999/)
    end

    # ── A7（2026-08-31 隨 decimal_places_overrides 新增）─────────────────────
    it "A7 🔴 空表 ≠ 缺鍵：decimal_places_overrides 整個鍵不見 ⇒ raise" do
      expect { build("missing_places_overrides") }
        .to raise_error(Psp::PackInvalid, /decimal_places_overrides/)
    end

    it "A7 覆蓋 > 2 ⇒ 載入即 raise（不能等到轉換時 ZeroDivision）" do
      expect { build("override_too_many_places") }
        .to raise_error(Psp::PackInvalid, /BHD.*不在 0\.\.2/)
    end
  end

  describe "🔴 空表是合法的（已查證、無例外）" do
    it "divisibility: {} 與 enable_gate: [] 可以通過" do
      registry = Psp::Registry.new(YAML.safe_load_file(Rails.root.join("spec/fixtures/psp_packs/matrix.yml")))
      pack = registry.fetch(:iso_minor)
      expect(pack.divisibility_for("JPY")).to be_nil
      expect(pack.enabled?).to be(false)
    end
  end
end
