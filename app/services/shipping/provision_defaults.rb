# frozen_string_literal: true

module Shipping
  # 建店預設運送鏈（結帳線第二包）：General 設定檔＋primary market 國家的 zone＋
  # 免運預設費率——新店開箱即可走完結帳運送段（Rates(p)=∅ 會整車擋，15 §F2.1）。
  #
  # 🔴 單一實作：Shop#after_create（新店）與 migration 回填都呼叫這裡
  #   （Markets::ProvisionDefaults 同款紀律——邏輯不得在呼叫端長出第二份）。
  # 🔴 必須排在 provision_default_market 之後：zone 國家取自 primary market regions。
  # 預設費率＝flat 0（免運）：商家未設定前不因缺費率擋結帳、也不多收一分錢；
  #   名稱「標準運送」＝我方繁中文案（鐵律 10；本尊預設 rate 名不抄）。
  module ProvisionDefaults
    GENERAL_NAME = "General"
    DEFAULT_ZONE_NAME = "Domestic"
    DEFAULT_RATE_NAME = "標準運送"

    module_function

    # 冪等：已有 General 設定檔的店原樣返回。
    #
    # @param shop [Shop]
    # @return [ShippingProfile, nil] General 檔；店內無 primary market（殘店）時跳過回 nil
    def call(shop:)
      ActsAsTenant.with_tenant(shop) do
        existing = ShippingProfile.general.first
        return existing if existing

        market = Market.find_by(is_primary: true)
        return nil if market.nil? # 市場鏈缺失的殘店：zone 沒有國家來源，跳過（backfill 印警示）

        profile = ShippingProfile.create!(name: GENERAL_NAME, general: true)
        zone = profile.shipping_zones.create!(
          shop_id: shop.id, name: DEFAULT_ZONE_NAME, country_codes: market.region_country_codes
        )
        zone.shipping_rates.create!(
          shop_id: shop.id, name: DEFAULT_RATE_NAME, rate_type: "flat",
          price_cents: 0, currency: shop.store_currency
        )
        profile
      end
    end

    # 既有店回填（migration 薄呼叫端用；冪等可重跑）。
    # @return [Integer] 實際建立 General 檔的店數
    def backfill_all!
      created = 0
      Shop.find_each do |shop|
        profile = call(shop:)
        if profile.nil?
          Rails.logger.warn("shipping.provision_defaults.skipped shop_id=#{shop.id} 原因=無 primary market")
        elsif profile.previously_new_record?
          created += 1
        end
      end
      created
    end
  end
end
