# frozen_string_literal: true

module Markets
  # 前綴 → (market, locale) 路由查表（docs/specs/67 §F.1(c)；🔴 2026-09-04 D80 方案 1 使用者裁定）。
  #
  #   剝第一路徑段 → 查 (shop, domain, prefix) → 命中 ⇒ (market, presence, locale)，繼續
  #                                            → 未命中 ⇒ 整條路徑視為**無前綴**、以店預設 (market, locale) 服務
  #                                              （本尊 `/zh-hans/` 404 不是因為「前綴查無」，是因為沒有 `/zh-hans/…` 這個頁面）
  #
  # 🔴 市場的來源有兩層（limits `i18n.locale_prefix.market_determined_by: url_then_buyer_selection`）：
  #   ①URL 前綴命中的 presence 決定 (market, locale)；子資料夾／自有網域市場到此為止。
  #   ②共用主網域上、沒有自己 presence 的市場（hoko 的美國／香港／日本／欧盟）沒有 URL 身分——由買家在
  #     `{% form 'localization' %}` 選國家寫下的 `localization` cookie（國碼）覆寫市場（§G23：POST country_code=US ⇒
  #     `Set-Cookie: localization=US`，之後同 URL `Shopify.country = "US"`）。語言仍只由 URL 決定；GeoIP 仍不參與。
  # 🔴 只解析「開放且已發布」的組合（67 §F.1(d)）：open_to_buyers ∧ shop_locales.published。
  #
  # v1 為線性掃描：列數＝店內白名單列數（≤ max_shop_locales × presences，數十級），
  # 且步 2 的頁級快取在上游吸收重複解析；物化前綴表待流量證據再議（勿預先優化）。
  module PrefixIndex
    # market：生效市場（可能是 cookie 覆寫後的共用市場）；web_presence：URL 身分所屬的 presence（共用市場沿用 primary 的）；
    # country_code：買家選定的國家（cookie；nil ⇒ 市場第一個 region）。
    Hit = Data.define(:market, :web_presence, :locale_tag, :country_code) do
      def initialize(market:, web_presence:, locale_tag:, country_code: nil)
        super
      end

      # localization.country／`Shopify.country` 用的國碼：買家選定 > 市場第一個 region（可在租戶脈絡外呼叫）。
      def effective_country_code
        country_code || ActsAsTenant.with_tenant(market.shop) { market.region_country_codes.first }
      end
    end

    module_function

    # @param shop [Shop]
    # @param domain [Domain] 請求命中的網域（host→shop 解析後）
    # @param first_segment [String] 第一路徑段（不含斜線），例 "zh-hant"
    # @return [Hit, nil] nil ⇒ 不是前綴（呼叫端把整條路徑當無前綴路徑處理）
    def resolve(shop:, domain:, first_segment:)
      return nil if first_segment.blank?

      wanted = "/#{first_segment}"

      ActsAsTenant.with_tenant(shop) do
        published = ShopLocale.where(shop_id: shop.id, published: true).pluck(:locale_tag).to_set
        MarketWebPresenceLocale.open_to_buyers
                               .includes(market_web_presence: :market)
                               .find_each do |row|
          next unless published.include?(row.locale_tag)

          presence = row.market_web_presence
          next unless effective_domain_id(presence) == domain.id

          begin
            return Hit.new(market: presence.market, web_presence: presence, locale_tag: row.locale_tag) \
              if UrlPrefix.for(presence, row.locale_tag) == wanted
          rescue UrlPrefix::Error
            next # 髒值組合不可路由（fail-closed），不擋其他組合解析
          end
        end
      end
      nil
    end

    # 預設 (market, locale) 命中＝primary market 的第一個 presence × 其預設語言（67 §F.1(b) 根路徑與無前綴路徑的落點；
    # 取序同 Storefront::LocalizationController）。E13（2026-09-04）抽成單一真相：①PagesController 根路徑／無前綴路徑
    # 直接以它渲染（D80 起不再 302）；②主題編輯器預覽（/admin/store/preview）以它渲染——本尊編輯器市場選擇器預設
    # "Store default"（docs/research/100 §中 2）；③無前綴的 SRA 端點（recommendations／search suggest／cart sections）以它渲染。
    # 尚未 provision 市場／presence／語言 ⇒ nil（fail-closed：呼叫端 404）。
    # @param shop [Shop]
    # @return [Hit, nil]
    def default_hit(shop:)
      ActsAsTenant.with_tenant(shop) do
        market = Market.find_by(is_primary: true) or return nil
        presence = market.market_web_presences.order(:id).first or return nil
        locale_tag = presence.default_shop_locale.presence or return nil
        Hit.new(market:, web_presence: presence, locale_tag:)
      end
    end

    # 買家選國覆寫（D80）：命中的 presence 是共用網域形（無 suffix）且該國屬於同一網域上「沒有自己 presence」的 active
    # region 市場 ⇒ 換成該市場、記下國碼；否則原樣（子資料夾／自有網域 URL 的市場由 URL 固定；國碼不屬任何市場／屬
    # primary 市場本身 ⇒ 只記國碼）。語言與 presence 不變（語言只由 URL 決定）。
    # @param hit [Hit]
    # @param shop [Shop]
    # @param domain [Domain]
    # @param country_code [String, nil] 兩碼大寫國碼（cookie 值；髒值由呼叫端先擋）
    # @return [Hit]
    def with_buyer_country(hit, shop:, domain:, country_code:)
      return hit if hit.nil? || country_code.blank?
      return hit if hit.web_presence.subfolder_suffix.present?

      ActsAsTenant.with_tenant(shop) do
        return hit unless effective_domain_id(hit.web_presence) == domain.id

        market = shared_market_for_country(shop:, domain:, country_code:)
        if market.nil?
          own = hit.market.region_country_codes.include?(country_code) ? country_code : nil
          return own ? Hit.new(market: hit.market, web_presence: hit.web_presence, locale_tag: hit.locale_tag, country_code: own) : hit
        end

        Hit.new(market:, web_presence: hit.web_presence, locale_tag: hit.locale_tag, country_code:)
      end
    end

    # 同一網域上、以該國為 region 的 active region 市場，且該市場**沒有自己的 presence**（沿 lineage 用 primary 的）。
    # 有自己 presence 的市場（子資料夾／自有網域）由 URL 決定，不由 cookie。
    # @return [Market, nil]
    def shared_market_for_country(shop:, domain:, country_code:)
      primary_presence = Market.find_by(shop_id: shop.id, is_primary: true)&.market_web_presences&.order(:id)&.first
      return nil if primary_presence.nil? || effective_domain_id(primary_presence) != domain.id

      MarketRegion.where(shop_id: shop.id, country_code: country_code)
                  .joins(:market).merge(Market.where(status: "active", market_type: "region"))
                  .order("markets.is_primary DESC, markets.id ASC")
                  .map(&:market)
                  .find { |market| !market.is_primary && market.market_web_presences.none? }
    end

    # 店內全部 presence × 白名單列（不問開放／發布）的非空前綴段集合——URL 重導的路徑驗證用
    # （帶前綴的正規路徑要擋；但不能拿「像前綴」當判準，/faq 這種兩三字母段是合法無前綴路徑）。
    # @param shop [Shop]
    # @return [Set<String>] 例 #<Set: {"zh-hant", "en-ca"}>
    def prefix_segments(shop:)
      ActsAsTenant.with_tenant(shop) do
        MarketWebPresenceLocale.includes(:market_web_presence).filter_map do |row|
          prefix = begin
            UrlPrefix.for(row.market_web_presence, row.locale_tag)
          rescue UrlPrefix::Error
            nil
          end
          prefix.presence&.delete_prefix("/")
        end.to_set
      end
    end

    # subfolder presence（domain_id NULL）落在 primary domain 上（29 §1.2）。
    def effective_domain_id(presence)
      presence.domain_id || Domain.primary.where(shop_id: presence.shop_id).pick(:id)
    end
  end
end
