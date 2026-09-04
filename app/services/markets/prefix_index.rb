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

    # 預設 (market, locale) 命中＝primary market 的第一個 presence × 其預設語言（67 §F.1(b) 根路徑處置的同一落點；
    # 取序同 Storefront::LocalizationController#target_presence）。E13（2026-09-04）抽成單一真相：
    # ①PagesController 根路徑／無前綴 302 的目標前綴；②主題編輯器預覽（/admin/store/preview）以它渲染——本尊編輯器
    # 市場選擇器預設 "Store default"（docs/research/100 §中 2）；③無前綴的 SRA 端點（recommendations／search suggest／
    # cart sections）以它渲染——編輯器預覽內主題 JS 打的是 `Shopify.routes.root + "recommendations/products"` 這種
    # 無前綴 URL（Ella data-url="/recommendations/products?limit=5"），本尊主市場預設語言無前綴故同語言；我方原本
    # locale nil ⇒ 英文回退（E13 computed 對表：預覽內 recommendations 卡片按鈕 74／99px vs 店面 32／80px）。
    # 🔴 這不是 GeoIP／cookie 推市場（BaseController ③ 仍成立）：它是店自己設定的預設，與根路徑 302 的目標同一個。
    # 尚未 provision 市場／presence／語言 ⇒ nil（fail-closed：呼叫端維持舊行為）。
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

    # subfolder presence（domain_id NULL）落在 primary domain 上（29 §1.2）。
    def effective_domain_id(presence)
      presence.domain_id || Domain.primary.where(shop_id: presence.shop_id).pick(:id)
    end
  end
end
