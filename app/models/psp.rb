# PSP（支付服務商）的宣告與 registry。
#
# 🔴 **本專案不自建支付系統**（open-decisions §F）。這一層存在的唯一理由是
# `docs/specs/65` 的鐵律 3：**每一家 PSP 的金額格式與單位都必須逐家明文宣告**，
# 因為 69 號查到的是**四家四種算法**：
#
# | PSP | `amount_format` | 三位小數幣別 | 自認可覆蓋 ISO 4217 |
# |---|---|---|---|
# | Adyen | `minor_units` | exponent 3 | 🔴 **是**（官方明文列出與 ISO 不同的幣別） |
# | Datatrans | `minor_units` | exponent 3 | 自稱遵循 ISO |
# | Stripe | `minor_units` | ⚠ V-204 | 🔴 實質是（`Special cases` 表涵蓋 ISK／HUF／TWD／UGX） |
# | Airwallex | 🔴 **`decimal_string`** | ⚠ V-132 | 引用 ISO 定義主單位 |
#
# ⇒「業界有共識、跟著 ISO 走就對了」這個假設**已被外部證據正面否定**。
#
# 🔴 **`Psp::Registry` / `Psp::Pack` / `Psp::BaseAdapter` 三個類別，規格只有呼叫端、
# 沒有定義端**——65 §D.1 寫的是 `Psp.registry.fetch(psp)` 怎麼被用，
# 沒寫這幾個類別長什麼樣。⇒ 它們是本 PR 裡**唯一有真實設計自由度**的部分，
# 因此刻意做得**極薄**：只做鍵驗證 ＋ 三個查詢方法，不做任何抽象。
# **第一家真 PSP 進來時，預期本檔會被改寫。**
#
# @see docs/specs/65-money-unit-boundary.md §D.3、§D.4
module Psp
  # 本模組所有例外的共同祖先。
  Error = Class.new(StandardError)

  # A0：pack 未宣告 `amount_format`。🔴 **不得預設 `minor_units`**。
  AmountFormatUndeclared = Class.new(Error)

  # A1：該幣別的 minor unit 未由 pack 宣告（也不在 ISO 底表裡）。
  MinorUnitUndeclared = Class.new(Error)

  # A2：exponent > 我方儲存尺度能表達的上限。
  UnsupportedCurrencyExponent = Class.new(Error)

  # A5：違反 pack 宣告的整除約束。🔴 **不得自動湊整**。
  DivisibilityViolation = Class.new(Error)

  # pack 宣告不完整（缺必填鍵、位數超限、閘門未結案…）⇒ 不得 enable。
  PackInvalid = Class.new(Error)

  # 找不到該 pack。
  PackNotFound = Class.new(Error)

  class << self
    # 生產環境的 registry（讀 `config/limits.yml` 的 `psp_packs`）。
    #
    # @return [Psp::Registry]
    # @note 副作用：無；只讀已載入的 limits 設定（memoized）。
    def registry
      @registry ||= Registry.new(Limits.fetch(:psp_packs))
    end

    # 測試用：換掉 registry。
    #
    # @param registry [Psp::Registry, nil] 傳 nil 還原成生產 registry
    # @return [void]
    # @note 副作用：改寫本模組的 memo。
    def registry=(registry)
      @registry = registry
    end

    # ISO 4217 底表（只在 pack 宣告 `minor_unit_source: iso4217` 時用）。
    #
    # @return [Hash{Symbol=>Integer}] 幣別 → exponent
    # @note 副作用：第一次呼叫時讀檔（memoized）。
    # @see config/iso4217_minor_units.yml
    def iso4217_exponents
      @iso4217_exponents ||= begin
        path = Rails.root.join(Limits.fetch(:money_boundary, :iso4217_table_source))
        YAML.safe_load_file(path).fetch("exponents").transform_keys { |k| k.to_s.upcase.to_sym }.freeze
      end
    end
  end
end
