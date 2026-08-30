# frozen_string_literal: true

module Markets
  # 前綴 → (market, locale) 路由查表（docs/specs/67 §F.1(c)）。
  #
  #   剝第一路徑段 → 查 (shop, domain, prefix) → 命中 ⇒ (market, locale)，繼續
  #                                            → 未命中 ⇒ 🔴 404（§A.5(c) 情形 1／3／4 全走這裡）
  #
  # 🔴 市場**只**由 URL 決定（limits `i18n.locale_prefix.market_determined_by: url_only`）——
  #   不得從 GeoIP／cookie 推導；GeoIP 的唯一用途是 62 §K.2 的一次性重導建議。
  # 🔴 只解析「開放且已發布」的組合（67 §F.1(d)）：open_to_buyers ∧ shop_locales.published。
  #   未開放／已關閉／未發布 ⇒ nil ⇒ 呼叫端 404（unopened_prefix_status／unknown_prefix_status）。
  #
  # v1 為線性掃描：列數＝店內白名單列數（≤ max_shop_locales × presences，數十級），
  # 且步 2 的頁級快取在上游吸收重複解析；物化前綴表待流量證據再議（勿預先優化）。
  module PrefixIndex
    Hit = Data.define(:market, :web_presence, :locale_tag)

    module_function

    # @param shop [Shop]
    # @param domain [Domain] 請求命中的網域（host→shop 解析後）
    # @param first_segment [String] 第一路徑段（不含斜線），例 "zh-hant-hk"
    # @return [Hit, nil] nil ⇒ 呼叫端一律 404（不是重導、不是猜測）
    def resolve(shop:, domain:, first_segment:)
      wanted = "/#{first_segment}"
      published = ShopLocale.where(shop_id: shop.id, published: true).pluck(:locale_tag).to_set

      ActsAsTenant.with_tenant(shop) do
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
            next # region 來源缺失的組合不可路由（fail-closed），不擋其他組合解析
          end
        end
      end
      nil
    end

    # subfolder presence（domain_id NULL）落在 primary domain 上（29 §1.2）。
    def effective_domain_id(presence)
      presence.domain_id || Domain.primary.where(shop_id: presence.shop_id).pick(:id)
    end
  end
end
