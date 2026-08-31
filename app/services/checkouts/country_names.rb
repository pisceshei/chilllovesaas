# frozen_string_literal: true

module Checkouts
  # 結帳頁國家下拉的顯示名（87 §3：值域＝商店 Markets 啟用國集合；option text＝
  # 英文全名，實測 `US:United States`）。ISO 3166-1 alpha-2 → 英文短名的事實字典
  # （非上限值，不進 limits.yml）；覆蓋常見市場，缺項回落 code——加國家時同步補列。
  module CountryNames
    NAMES = {
      "AU" => "Australia", "AT" => "Austria", "BE" => "Belgium", "BR" => "Brazil",
      "CA" => "Canada", "CH" => "Switzerland", "CN" => "China", "CZ" => "Czechia",
      "DE" => "Germany", "DK" => "Denmark", "ES" => "Spain", "FI" => "Finland",
      "FR" => "France", "GB" => "United Kingdom", "HK" => "Hong Kong SAR",
      "ID" => "Indonesia", "IE" => "Ireland", "IL" => "Israel", "IN" => "India",
      "IT" => "Italy", "JP" => "Japan", "KH" => "Cambodia", "KR" => "South Korea",
      "LU" => "Luxembourg", "MO" => "Macao SAR", "MX" => "Mexico", "MY" => "Malaysia",
      "NL" => "Netherlands", "NO" => "Norway", "NZ" => "New Zealand",
      "PH" => "Philippines", "PL" => "Poland", "PT" => "Portugal", "SE" => "Sweden",
      "SG" => "Singapore", "TH" => "Thailand", "TW" => "Taiwan", "US" => "United States",
      "VN" => "Vietnam", "ZA" => "South Africa"
    }.freeze

    module_function

    # @param code [String] ISO 3166-1 alpha-2
    # @return [String] 英文短名；未收錄回落 code（可見即可修，不擲錯）
    def label(code)
      NAMES.fetch(code.to_s.upcase, code.to_s.upcase)
    end
  end
end
