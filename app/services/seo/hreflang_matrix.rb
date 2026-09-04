# frozen_string_literal: true

module Seo
  # hreflang 完整矩陣（62 §I.1 唯一實作——`<head>` 與 sitemap 的 `xhtml:link`
  # **共用本函式**，兩處各寫一遍必然漂移，§C 規則 4）。
  #
  # 四條硬性不變量（62 §I.1；REG-6）：自指／雙向（同一函式產同一集合＝天然雙向，
  # 🔴 禁止任何按頁客製）／絕對 URL／每個 URL 回 200 且 self-canonical。
  # 🔴 語言集合＝**開放 ∧ 已發布**（open_locales——與 PrefixIndex／LocalizationContext
  #   同一開放集，67 §F.1(d) 三處同軸）。碼＝Markets::HreflangCodes.for_presence（D80 2026-09-04：共用網域 presence
  #   一語言一碼 zh-Hant／en，子資料夾 presence 逐國展開）；沒有自己 presence 的共用市場不進矩陣（同一組 URL）。
  module HreflangMatrix
    Entry = Data.define(:code, :url)

    module_function

    # @param shop [Shop]
    # @param canonical_path [String] 前綴已剝的正規路徑（"/"＝首頁、"/products/x"…）
    # @return [Array<Entry>] 含 x-default（62 §I.2；D80：指主網域 primary market 預設語言的 URL＝無前綴根形）
    def entries(shop:, canonical_path:)
      list = []
      seen = Set.new
      # primary market 先行 ⇒ 碼衝突時 primary 勝（62 §I.3(c) nearest_own 的單店退化形；
      # 多 presence／lineage 的完整解析待 derived_parent 重算器落地——單市場 v1 無衝突面）。
      markets = Market.where(shop_id: shop.id, status: "active").order(is_primary: :desc, id: :asc)
      markets.each do |market|
        market.market_web_presences.order(:id).each do |presence|
          open_published_locales(presence).each do |tag|
            begin
              url = absolute_url(shop, presence, tag, canonical_path)
            rescue Markets::UrlPrefix::Error
              next # region 來源缺失的組合不可路由（fail-closed），不進矩陣（不變量 4）
            end
            Markets::HreflangCodes.for_presence(presence, tag).each do |code|
              next if seen.include?(code) # dedupe：先到者勝（primary 序）

              seen << code
              list << Entry.new(code:, url:)
            end
          end
        end
      end
      xd = x_default_url(shop, canonical_path)
      list << Entry.new(code: "x-default", url: xd) if xd
      list
    end

    # 開放 ∧ 已發布（67 §C.8／§F.1(d)——與路由解析同一判準）。
    def open_published_locales(presence)
      published = ShopLocale.where(shop_id: presence.shop_id, published: true).pluck(:locale_tag)
      presence.market_web_presence_locales.open_to_buyers
              .where(locale_tag: published).pluck(:locale_tag)
    end

    # absolute_url（67 §F.1(d)）：origin(wp) ＋ url_prefix ＋ canonical_path（純拼接，
    # handle 不含語言 ⇒ 無逐語言查表）。首頁 path "/" ⇒ 前綴＋斜線。
    def absolute_url(shop, presence, locale_tag, canonical_path)
      prefix = Markets::UrlPrefix.for(presence, locale_tag)
      path = canonical_path == "/" ? "#{prefix}/" : "#{prefix}#{canonical_path}"
      "#{origin(shop, presence)}#{path}"
    end

    def origin(shop, presence)
      host = presence.domain&.host ||
             Domain.primary.where(shop_id: shop.id).pick(:host) ||
             "#{shop.subdomain}.#{Chilllove::TenantResolver.base_host}"
      "https://#{host}"
    end

    # x-default＝主網域 primary market 預設語言的 URL（D80：預設語言無前綴 ⇒ 就是無前綴路徑；本尊 hoko 每頁
    # x-default 指無前綴同路徑，§G23）。primary 鏈缺失 ⇒ nil（entries 端 compact 掉）。
    def x_default_url(shop, canonical_path)
      market = Market.find_by(shop_id: shop.id, is_primary: true) or return nil
      presence = market.market_web_presences.order(:id).first or return nil
      absolute_url(shop, presence, presence.default_shop_locale, canonical_path)
    rescue Markets::UrlPrefix::Error
      nil
    end
  end
end
