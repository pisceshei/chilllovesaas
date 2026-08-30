# frozen_string_literal: true

module Markets
  # 建店預設市場鏈（包 32）：primary market（基準法域 HK，鐵律 11）＋ primary domain
  # ＋ 主網域 presence ＋ 已發布語言白名單。
  #
  # 🔴 **單一實作**：Shop#after_create（未來新店）與 migration 20260831151000（既有店回填）
  #   都呼叫這裡——邏輯不得在呼叫端長出第二份（20260826060000 檔頭教訓：三份實作、
  #   spec 守自己那一份，兩個殺傷性 mutation 全綠）。
  #
  # 為什麼建店就要有市場：url_prefix 恆帶 region（67 §F.1(b)），region 來自市場——
  # 沒有市場的店**一條前台 URL 都組不出來**；B11 裁定「/{lang}-{region}/ 一次到位、
  # 先單一 HK 市場」正是把這條鏈在 v1 就接通。
  module ProvisionDefaults
    # 基準法域＝香港（鐵律 11；2026-08-12 決議）。名稱給人看（本尊 primary market 以
    # 國名命名，實測 2026-08-31：United States）；資料預設英文＝2026-08-23 使用者指示。
    DEFAULT_COUNTRY = "HK"
    DEFAULT_NAME = "Hong Kong"
    DEFAULT_HANDLE = "hk"

    module_function

    # 冪等：已有 primary market 的店原樣返回。
    #
    # @param shop [Shop]
    # @return [Market, nil] primary market；店內無 shop_locales（來源語言缺失）時跳過回 nil
    def call(shop:)
      ActsAsTenant.with_tenant(shop) do
        existing = Market.find_by(is_primary: true)
        return existing if existing

        source = ShopLocale.find_by(is_source: true)
        return nil if source.nil? # 語言列缺失的殘店：市場鏈接不起來，跳過（backfill 印警示）

        market = Market.create!(
          name: DEFAULT_NAME, handle: DEFAULT_HANDLE,
          status: "active", market_type: "region", is_primary: true
        )
        market.market_regions.create!(country_code: DEFAULT_COUNTRY)

        domain = Domain.find_by(domain_type: "primary") || Domain.create!(
          host: default_host(shop), domain_type: "primary", status: "active"
        )

        presence = market.market_web_presences.create!(
          domain:, default_shop_locale: source.locale_tag
        )

        # 白名單＝已發布語言（67 §C.8(c) 可選值域）；預設＝來源語言。position 沿用 shop_locales 序。
        ShopLocale.where(published: true).order(:position, :locale_tag).each_with_index do |locale, position|
          presence.market_web_presence_locales.create!(
            locale_tag: locale.locale_tag,
            position:,
            is_market_default: locale.locale_tag == source.locale_tag
          )
        end

        market
      end
    end

    # 既有店回填（migration 薄呼叫端用；冪等可重跑）。
    # @return [Integer] 實際建立市場的店數
    def backfill_all!
      created = 0
      Shop.find_each do |shop|
        market = call(shop:)
        if market.nil?
          Rails.logger.warn("markets.provision_defaults.skipped shop_id=#{shop.id} 原因=無來源語言列")
        elsif market.previously_new_record?
          created += 1
        end
      end
      created
    end

    # 網域種子：有 custom_domain 用它；否則平台子網域 host（快照——base_host 換環境時
    # 舊列成死列，步 2 解析器以 shops.subdomain 兜底，不會斷路由）。
    def default_host(shop)
      shop.custom_domain.presence || "#{shop.subdomain}.#{Chilllove::TenantResolver.base_host}"
    end
  end
end
