# frozen_string_literal: true

module Storefront
  # `{% form 'localization' %}` 的提交端（包 34；67 §F.2）。
  #
  # ①兩個欄位名都要收（`country_code`／`language_code`——25 號坑 #4；語言與地區是
  #   **兩個維度**，合成一個控件是被明文擋掉的形態）。
  # ②解析序：country ⇒ market（active region 市場；查無 ⇒ primary）⇒ presence ⇒
  #   語言＝請求值若在該 presence 開放∧已發布，否則落 presence 預設
  #   （F.2 最後一列「切國家導致語言不支援 ⇒ 落 defaultLocale」＋ §A.5 開放集限定詞）。
  # ③回應＝302 到目標前綴＋return_to 路徑（剝舊前綴）；🔴 切換器本體仍是真實
  #   `<a href>`（F.2）——本端點服務的是 country+language 表單提交這一形。
  # ④open redirect 防線：return_to 只收站內路徑（"/" 開頭且非 "//"）。
  class LocalizationController < BaseController
    skip_forgery_protection

    # POST /localization（裸與帶前綴兩形，同 cart 家族）
    def create
      ActsAsTenant.with_tenant(current_shop) do
        presence = target_presence
        return head :unprocessable_content if presence.nil?

        tag = resolve_language(presence)
        prefix = Markets::UrlPrefix.for(presence, tag)
        redirect_to "#{prefix}#{return_path}", status: :found, allow_other_host: false
      end
    rescue Markets::UrlPrefix::Error
      head :unprocessable_content
    end

    private

    def target_presence
      market = market_for_country || Market.find_by(is_primary: true)
      return nil if market.nil?

      # presence 沿 lineage 累加（market.inheritance_additive）：自身無 presence ⇒ primary 的。
      market.market_web_presences.first ||
        Market.find_by(is_primary: true)&.market_web_presences&.first
    end

    def market_for_country
      code = params[:country_code].to_s.strip.upcase
      return nil if code.blank?

      MarketRegion.where(country_code: code)
                  .joins(:market).merge(Market.active)
                  .first&.market
    end

    def resolve_language(presence)
      requested = params[:language_code].to_s.presence
      return presence.default_shop_locale if requested.nil?

      tag = Locales::Tag.normalize(requested)
      open = presence.market_web_presence_locales.open_to_buyers.exists?(locale_tag: tag)
      published = ShopLocale.where(shop_id: presence.shop_id, locale_tag: tag, published: true).exists?
      open && published ? tag : presence.default_shop_locale
    end

    # return_to 剝舊前綴（第一段長得像前綴即剝——與 PagesController 同一 SEGMENT 來源）。
    def return_path
      raw = params[:return_to].to_s
      return "/" unless raw.start_with?("/") && !raw.start_with?("//")

      segments = raw.delete_prefix("/").split("/", 2)
      if segments[0].to_s.match?(/\A#{Markets::UrlPrefix::SEGMENT.source}\z/)
        rest = segments[1].to_s
        rest.empty? ? "/" : "/#{rest}"
      else
        raw
      end
    end
  end
end
