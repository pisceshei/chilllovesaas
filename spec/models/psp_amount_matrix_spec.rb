# frozen_string_literal: true

require "rails_helper"

# `docs/specs/65` §H 的測試矩陣。
#
# 🔴 **沒有這一節，這個 bug 會在上線後才出現**——exponent=2 的幣別下所有轉換的
# divisor 都是 1，錯誤實作與正確實作的輸出**完全相同**。
# 每一條 example 的標題都帶 T 編號，對得上 65 §H.2 的表。
RSpec.describe "金額單位邊界測試矩陣（65 §H）" do
  def registry_from(fixture)
    Psp::Registry.new(YAML.safe_load_file(Rails.root.join("spec/fixtures/psp_packs/#{fixture}.yml")))
  end

  around do |example|
    original = Psp.registry
    Psp.registry = registry_from("matrix")
    example.run
    Psp.registry = original
  end

  def storage(cents, currency) = Money::Storage.from_cents(cents, currency)

  # ── minor_units（Stripe／Adyen／Datatrans 型）───────────────────────────────
  describe "amount_format: minor_units" do
    it "T3 🔴 JPY 儲存 148000 ⇒ 送出 1480（不是 148000＝收款 100 倍）" do
      expect(storage(148_000, "JPY").to_psp_amount(psp: :iso_minor).minor).to eq(1480)
    end

    it "T4 🔴 webhook 1480 ⇒ 落庫 148000（不是 1480＝少記 99%）" do
      minor = storage(148_000, "JPY").to_psp_amount(psp: :iso_minor)
      expect(minor.to_storage.cents).to eq(148_000)
    end

    it "T5 🔴 PI 金額與 checkout 金額比對前先化到同一表示法" do
      checkout = storage(148_000, "JPY")
      from_psp = checkout.to_psp_amount(psp: :iso_minor).to_storage
      # 🔴 若拿 PI 的 R5（1480）直接比 checkout 的 R1（148000），
      # **每一張 JPY 訂單都會被判成金額不一致而自動退款**（65 §E.1-2）。
      expect(from_psp).to eq(checkout)
    end

    it "T6 🔴 JPY 148050（¥1,480.50）⇒ raise，不四捨五入抹掉 50" do
      expect { storage(148_050, "JPY").to_psp_amount(psp: :iso_minor) }
        .to raise_error(Money::NonIntegralConversion, /不得四捨五入/)
    end

    it "T7 KRW 1200000（₩12,000）⇒ 12000（防「只對 JPY 特判」）" do
      expect(storage(1_200_000, "KRW").to_psp_amount(psp: :iso_minor).minor).to eq(12_000)
    end

    # 🔴 T8 斷言的是「未宣告時正確地拒絕」，不是某個具體 exponent 值。
    # 65 §H.3：「ISO 4217 對 TWD 的 minor unit，本專案至今沒有任何一手出處。」
    it "T8 🔴 TWD 未被 pack 宣告 ⇒ raise（不是猜一個 exponent 送出去）" do
      expect { storage(100, "TWD").to_psp_amount(psp: :iso_minor) }
        .to raise_error(Psp::MinorUnitUndeclared, /未宣告/)
    end

    it "T9 HKD 148000 ⇒ 148000（divisor=1；確保修正沒把 exponent=2 弄壞）" do
      expect(storage(148_000, "HKD").to_psp_amount(psp: :iso_minor).minor).to eq(148_000)
    end

    it "T10 USD 邊界值 0 / 1 / BIGINT max 往返一致" do
      [ 0, 1, 9_223_372_036_854_775_807 ].each do |cents|
        value = storage(cents, "USD")
        expect(value.to_psp_amount(psp: :iso_minor).to_storage).to eq(value), "cents=#{cents}"
      end
    end

    it "T11 KWD（exponent 3）⇒ raise（A2：我方儲存尺度表達不了）" do
      expect { storage(100, "KWD").to_psp_amount(psp: :iso_minor) }
        .to raise_error(Psp::UnsupportedCurrencyExponent, /表達不了/)
    end

    it "pack 的 minor_unit_overrides 覆蓋 ISO 底表（Adyen 明文覆蓋 ISO）" do
      # ISO 底表沒有 TWD；override_minor 宣告了 TWD: 2。
      expect(storage(100, "TWD").to_psp_amount(psp: :override_minor).minor).to eq(100)
    end
  end

  # ── decimal_string（Airwallex 型）──────────────────────────────────────────
  #
  # 🔴 **這一組是本專案唯一「基準法域測得到、卻沒人在測」的送款事故形態**：
  # `decimal_string` 的誤用（把儲存值 148000 輸出成 "148000.00"）**在 HKD 上也會錯**。
  describe "amount_format: decimal_string" do
    it "T15 🔴 JPY 儲存 148000 ⇒ \"1480.00\"（不是 \"148000.00\"＝收款 100 倍）" do
      result = storage(148_000, "JPY").to_psp_amount(psp: :decimal_two)
      expect(result.string).to eq("1480.00")
      expect(result).to be_a(Money::PspDecimal)
    end

    it "🔴 HKD 也會錯的那一條：儲存 148000 ⇒ \"1480.00\" 而不是 \"148000.00\"" do
      expect(storage(148_000, "HKD").to_psp_amount(psp: :decimal_two).string).to eq("1480.00")
    end

    it "入向：\"1480.00\" ⇒ 落庫 148000（不是 1480＝少記 99%，且所有幣別皆然）" do
      value = storage(148_000, "HKD")
      expect(value.to_psp_amount(psp: :decimal_two).to_storage).to eq(value)
    end

    it "字串符合 psp_decimal_string_regex（無幣別符號、無千分位）" do
      pattern = Regexp.new(Limits.fetch(:money_boundary, :psp_decimal_string_regex))
      expect(storage(148_000, "JPY").to_psp_amount(psp: :decimal_two).string).to match(pattern)
    end

    it "負數（退款差額）也能送出" do
      expect(storage(-50_000, "HKD").to_psp_amount(psp: :decimal_two).string).to eq("-500.00")
    end
  end

  # ── decimal_number（Airwallex 型；R7，2026-08-31）───────────────────────────
  #
  # 🔴 假綠殺手：T20 殺「把儲存值直接當主單位數送出」（148000＝收款 100 倍，HKD 也錯）；
  # T24 殺「webhook 用 `JSON.parse` 預設 Float」。
  describe "amount_format: decimal_number" do
    it "T20 🔴 JPY 儲存 148000 ⇒ 數值 1480（不是 148000＝收款 100 倍）" do
      result = storage(148_000, "JPY").to_psp_amount(psp: :number_two)
      expect(result).to be_a(Money::PspNumber)
      expect(result.number).to eq(BigDecimal("1480"))
    end

    it "🔴 HKD 也會錯的那一條：儲存 4912 ⇒ 49.12（Airwallex 官方 HKD 退款例）" do
      expect(storage(4_912, "HKD").to_psp_amount(psp: :number_two).number).to eq(BigDecimal("49.12"))
    end

    it "T22 入向：BigDecimal 16.66 ⇒ 落庫 1666（不是 16＝少記 99%）" do
      expect(Money.from_psp_amount(BigDecimal("16.66"), currency: "HKD", psp: :number_two).cents)
        .to eq(1_666)
    end

    it "T22 入向：JSON number 整數形（1480）也收（decimal_class 對整數仍回 Integer）" do
      expect(Money.from_psp_amount(1480, currency: "JPY", psp: :zero_override_number).cents)
        .to eq(148_000)
    end

    it "T24 🔴 Float ⇒ TypeError（JSON.parse 預設把 number 解成 Float——約定變機械限制）" do
      expect { Money.from_psp_amount(16.66, currency: "HKD", psp: :number_two) }
        .to raise_error(TypeError, /Float 即 bug/)
    end

    it "入向小數超過生效位數 ⇒ raise（不得 round）" do
      expect { Money.from_psp_amount(BigDecimal("16.666"), currency: "HKD", psp: :number_two) }
        .to raise_error(Money::ExcessPrecision)
      expect { Money.from_psp_amount(BigDecimal("1480.5"), currency: "JPY", psp: :zero_override_number) }
        .to raise_error(Money::ExcessPrecision)
    end

    it "L1 🔴 PspNumber 的 to_s 不回傳裸金額（與 R6 的 to_s 陷阱同一條）" do
      r7 = storage(148_000, "HKD").to_psp_amount(psp: :number_two)
      expect(r7.to_s).to include("PspNumber")
      expect(r7).not_to respond_to(:to_str)
    end
  end

  # ── A7 per-currency 位數覆蓋 ＋ A6c 不得湊整（PayPal／Airwallex 實證形）────────
  #
  # 🔴 兩家實證都覆蓋自己引用的底表：PayPal 官方逐字「This currency does not support
  # decimals. If you pass a decimal amount, an error occurs.」（HUF/JPY/TWD）；
  # Airwallex payments 側零小數 20 幣（HUF/TWD/IDR 皆與 ISO 不同）。取證 2026-08-31。
  describe "A7 decimal_places_overrides ＋ A6c" do
    it "T21 🔴 PayPal 形：JPY 覆蓋 0 位 ⇒ \"1480\" 無小數點（帶小數＝官方逐字 error）" do
      result = storage(148_000, "JPY").to_psp_amount(psp: :zero_override_string)
      expect(result.string).to eq("1480")
    end

    it "T21 未覆蓋幣別承接基準 2 位（HKD ⇒ \"1480.00\"）" do
      expect(storage(148_000, "HKD").to_psp_amount(psp: :zero_override_string).string).to eq("1480.00")
    end

    it "T23 🔴 A6c：JPY 148050（¥1,480.50）對 0 位幣別 ⇒ raise，不得湊成 1481" do
      # 湊整會讓送款與帳上差 0.50 而沒有任何一張表記得住——兩種 decimal 格式都要擋。
      expect { storage(148_050, "JPY").to_psp_amount(psp: :zero_override_string) }
        .to raise_error(Money::NonIntegralConversion, /不得四捨五入/)
      expect { storage(148_050, "JPY").to_psp_amount(psp: :zero_override_number) }
        .to raise_error(Money::NonIntegralConversion, /不得四捨五入/)
    end

    it "T21 入向：無小數點字串 \"1480\"（PayPal JPY 合法形）⇒ 148000" do
      # 🔴 殺「split('.').last 對無點字串回整串」：修前 "1480" 會被數成 4 位小數而誤拒。
      expect(Money.from_psp_amount("1480", currency: "JPY", psp: :zero_override_string).cents)
        .to eq(148_000)
    end

    it "入向：JPY 收到 \"1480.00\"（超過生效 0 位）⇒ raise 進死信，不得就地猜" do
      expect { Money.from_psp_amount("1480.00", currency: "JPY", psp: :zero_override_string) }
        .to raise_error(Money::ExcessPrecision)
    end
  end

  # ── X8 入向閘門（包不出來就不准進）──────────────────────────────────────────
  describe "from_psp_amount 形態閘門" do
    it "minor_units 只收 Integer；字串 ⇒ TypeError（宣告與形態不符＝死信）" do
      expect(Money.from_psp_amount(1480, currency: "JPY", psp: :iso_minor).cents).to eq(148_000)
      expect { Money.from_psp_amount("1480", currency: "JPY", psp: :iso_minor) }
        .to raise_error(TypeError, /只收 Integer/)
    end

    it "decimal_string 只收 String；整數 ⇒ TypeError" do
      expect { Money.from_psp_amount(1480, currency: "HKD", psp: :decimal_two) }
        .to raise_error(TypeError, /只收 String/)
    end
  end

  # ── A5 整除約束（來源＝Stripe 對 HUF／TWD payout 的明文要求）─────────────────
  describe "A5 divisibility（T16）" do
    it "T16 🔴 違反時 raise，且**沒有靜默湊整**" do
      # 只測「有 raise」的話，一個「先湊整再 raise」的實作也會綠 ⇒ 兩件事都要驗。
      expect { storage(148_050, "TWD").to_psp_amount(psp: :override_minor) }
        .to raise_error(Psp::DivisibilityViolation, /不得自動湊整/)

      # 反向：沒有任何被湊整後的值被回傳（沒有殘留、沒有部分成功）。
      expect { storage(148_050, "TWD").to_psp_amount(psp: :override_minor) }
        .to raise_error(Psp::DivisibilityViolation)
    end

    it "符合倍數時正常送出" do
      expect(storage(148_000, "TWD").to_psp_amount(psp: :override_minor).minor).to eq(148_000)
    end

    it "🔴 decimal_string 格式下基準是主單位的 BigDecimal，不是 minor" do
      # decimal_divisible 宣告 TWD 整除 100（主單位）。
      # 148000 cents ⇒ 主單位 1480.00 ⇒ 1480 % 100 != 0 ⇒ raise。
      expect { storage(148_000, "TWD").to_psp_amount(psp: :decimal_divisible) }
        .to raise_error(Psp::DivisibilityViolation)
      # 1000000 cents ⇒ 主單位 10000.00 ⇒ 整除 ⇒ 通過。
      expect(storage(1_000_000, "TWD").to_psp_amount(psp: :decimal_divisible).string).to eq("10000.00")
    end
  end

  # ── T12 往返自檢（三種格式各跑）────────────────────────────────────────────
  it "T12 from_psp_amount(to_psp_amount(x)) == x（三種 amount_format 各跑）" do
    matrix = { "JPY" => 148_000, "KRW" => 1_200_000, "HKD" => 148_000, "USD" => 1 }
    matrix.each do |currency, cents|
      value = storage(cents, currency)
      %i[iso_minor decimal_two number_two].each do |psp|
        expect(value.to_psp_amount(psp:).to_storage).to eq(value), "#{currency}/#{psp} 往返不一致"
      end
    end
  end

  # ── L3 型別閘門（T14／T17／T18）────────────────────────────────────────────
  describe "L3 adapter 型別閘門" do
    let(:adapter) { Psp::BaseAdapter.new(:iso_minor) }
    let(:decimal_adapter) { Psp::BaseAdapter.new(:decimal_two) }

    it "T14 傳裸 Integer ⇒ TypeError" do
      expect { adapter.to_payload(148_000) }.to raise_error(TypeError, /只收/)
    end

    it "T14 傳裸 String ⇒ TypeError" do
      expect { decimal_adapter.to_payload("1480.00") }.to raise_error(TypeError, /只收/)
    end

    # 🔴 這一條是唯一能證明「型別而非字串」真的在守門的測試：
    # R4 與 R6 的字串內容可以一模一樣。
    it "T17 🔴 傳 Money::Decimal（R4）⇒ TypeError，即使字串內容與 R6 完全相同" do
      r4 = storage(148_000, "JPY").to_decimal
      r6 = storage(148_000, "JPY").to_psp_amount(psp: :decimal_two)
      expect(r4.string).to eq(r6.string)          # 字串一模一樣
      expect { decimal_adapter.to_payload(r4) }.to raise_error(TypeError, /只收/)
      expect(decimal_adapter.to_payload(r6)).to eq("1480.00")
    end

    it "T18 格式對了但家別錯了 ⇒ TypeError" do
      other = storage(148_000, "JPY").to_psp_amount(psp: :override_minor)
      expect { adapter.to_payload(other) }.to raise_error(TypeError, /是為 override_minor 算的/)
    end

    # ── 正負號（65 §A.7，2026-08-15 補實作）────────────────────────────────
    #
    # 🔴 **這兩層的期望是相反的，必須分開寫清楚**：
    #   型別層（`to_psp_amount`）**放行**負值——§A.7 明文型別層不驗正負，
    #     因為退款差額與撤銷需要負的 `Money::Storage`；
    #   adapter 層（`to_payload`）**拒收**負值——§A.7 表格「送 PSP」列逐字
    #     「PSP adapter 驗正數，負值一律 raise」。
    # ⚠️ 2026-08-15 之前，第二層**完全沒有實作**（規格有、代碼零落點）
    # ⇒ 負值可以一路走到線上形態。
    describe "🔴 負值不得送出（§A.7）" do
      it "型別層放行負值（這是刻意的，不是漏擋）" do
        expect(storage(-50_000, "HKD").to_psp_amount(psp: :iso_minor).minor).to eq(-50_000)
        expect(storage(-50_000, "HKD").to_psp_amount(psp: :decimal_two).string).to eq("-500.00")
      end

      it "adapter 層拒收負值 ── minor_units" do
        neg = storage(-50_000, "HKD").to_psp_amount(psp: :iso_minor)
        expect { adapter.to_payload(neg) }.to raise_error(TypeError, /不得為負/)
      end

      it "adapter 層拒收負值 ── decimal_string" do
        neg = storage(-50_000, "HKD").to_psp_amount(psp: :decimal_two)
        expect { decimal_adapter.to_payload(neg) }.to raise_error(TypeError, /不得為負/)
      end

      # 🔴 零值**刻意放行**：§A.7 引到的官方證據只證明「負值不可送」，
      # 而 $0 auth（卡片驗證）是真實形態 ⇒ 不在這裡發明規則。
      it "零值放行（$0 auth 是真實形態，§A.7 未裁定 ⇒ 不發明規則）" do
        expect(adapter.to_payload(storage(0, "HKD").to_psp_amount(psp: :iso_minor))).to eq(0)
        expect(decimal_adapter.to_payload(storage(0, "HKD").to_psp_amount(psp: :decimal_two)))
          .to eq("0.00")
      end
    end

    it "T18 家別對了但格式錯了 ⇒ TypeError" do
      minor = storage(148_000, "JPY").to_psp_amount(psp: :iso_minor)
      expect { decimal_adapter.to_payload(minor) }.to raise_error(TypeError, /只收/)
    end

    it "正確的值物件 ⇒ 回線上形態" do
      expect(adapter.to_payload(storage(148_000, "JPY").to_psp_amount(psp: :iso_minor))).to eq(1480)
    end
  end

  # ── L2 唯一建構路徑 ────────────────────────────────────────────────────────
  describe "L2 R5／R6 的建構路徑" do
    it "🔴 .new 被關閉——唯一路徑是 Money::Storage#to_psp_amount" do
      expect { Money::PspMinor.new(minor: 1, currency: "JPY", psp: :iso_minor) }
        .to raise_error(NoMethodError)
      expect { Money::PspDecimal.new(string: "1.00", currency: "JPY", psp: :decimal_two) }
        .to raise_error(NoMethodError)
      expect { Money::PspNumber.new(number: BigDecimal("1"), currency: "HKD", psp: :number_two) }
        .to raise_error(NoMethodError)
    end

    it "🔴 .[] / .allocate / #with 三條後門也全部關閉" do
      expect { Money::PspMinor[minor: 1, currency: "JPY", psp: :x] }.to raise_error(NoMethodError)
      expect { Money::PspMinor.allocate }.to raise_error(NoMethodError)
      expect(storage(100, "JPY").to_psp_amount(psp: :iso_minor)).not_to respond_to(:with)
    end

    it "🔴 沒有「先做一個 R4 再改型」的路徑" do
      expect(storage(100, "JPY").to_decimal).not_to respond_to(:to_psp_decimal)
    end
  end

  # ── L1：R6 的等價陷阱是 to_s ───────────────────────────────────────────────
  it "L1 🔴 PspDecimal 的 to_s 不回傳裸金額字串（插值時看得出來是值物件）" do
    r6 = storage(148_000, "JPY").to_psp_amount(psp: :decimal_two)
    expect(r6.to_s).to include("PspDecimal")
    expect("#{r6}").not_to eq("1480.00")
    expect(r6).not_to respond_to(:to_str)
  end

  # ── 矩陣覆蓋度自檢（65 §H.1 的 CI 規則）────────────────────────────────────
  describe "矩陣覆蓋度" do
    it "🔴 zero-decimal 幣別全部在本檔出現（缺任一 ⇒ CI fail）" do
      source = File.read(__FILE__, encoding: "UTF-8")
      Limits.enum(:money_boundary, :test_matrix_zero_decimal_required).each do |currency|
        expect(source).to include(currency), "測試矩陣缺 zero-decimal 幣別 #{currency}"
      end
    end

    it "三種 amount_format 各有 fixture pack" do
      packs = Psp.registry.codes.map { |code| Psp.registry.fetch(code).amount_format }
      Limits.enum(:money_boundary, :test_matrix_amount_formats_required).each do |format|
        expect(packs.map(&:to_s)).to include(format.downcase), "缺 #{format} 型 fixture pack"
      end
    end

    it "divisibility 至少一個 fixture pack（以 TWD／100 為原型）" do
      required = Limits.fetch(:money_boundary, :test_matrix_divisibility_required)
      required.each do |currency, multiple|
        found = Psp.registry.codes.any? do |code|
          Psp.registry.fetch(code).divisibility_for(currency) == multiple
        end
        expect(found).to be(true), "缺宣告 #{currency} 整除 #{multiple} 的 fixture pack"
      end
    end
  end
end
