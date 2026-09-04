# frozen_string_literal: true

module Storefront
  # `{% form 'localization' %}` 的提交端（包 34；67 §F.2；🔴 2026-09-04 D80 方案 1 使用者裁定改本尊形）。
  #
  # 官方 tags/form 逐字（external-facts §G23）："Generates a form for customers to select their preferred country so that
  # they're shown the appropriate language and currency."——欄位 `country_code`／`language_code`／`return_to`。
  # 本尊實測（hoko.vip 2026-09-04 curl）：
  #   country_code=US&return_to=/collections/all            ⇒ 302 /collections/all ＋ Set-Cookie: localization=US; path=/
  #   language_code=en&return_to=/collections/all           ⇒ 302 /en/collections/all ＋ Set-Cookie: localization=TW; path=/en
  #   country_code=JP&language_code=ja&return_to=/zh-hant/… ⇒ 302 /ja/collections/all ＋ Set-Cookie: localization=JP; path=/ja
  #   （cookie 一年效期、SameSite=Lax、path＝目標語言的根路徑；值＝所選國碼）
  #
  # ①兩個欄位名都要收（語言與地區是**兩個維度**，合成一個控件是被明文擋掉的形態）。
  # ②語言：請求值若在目標 presence 開放∧已發布 ⇒ 取之；未給 ⇒ 維持當前語言（請求前綴／return_to 前綴）；
  #   都不成立 ⇒ 落 presence 預設（F.2 最後一列）。
  # ③國家：該國的 active 市場**有自己的 presence**（子資料夾／自有網域）⇒ 302 到該 presence 的前綴（URL 身分）；
  #   **沒有自己的 presence**（共用主網域）⇒ 寫 `localization` cookie（值＝國碼，path＝目標語言根路徑）、留在同一語言的 URL
  #   （市場由 BaseController 讀 cookie 覆寫）；不屬任何市場 ⇒ 只切語言。
  # ④回應＝302 到目標前綴＋return_to 路徑（剝舊前綴，只剝**真的是前綴**的段）；open redirect 防線：return_to 只收站內路徑。
  class LocalizationController < BaseController
    skip_forgery_protection

    # POST /localization（裸與帶前綴兩形，同 cart 家族）
    def create
      ActsAsTenant.with_tenant(current_shop) do
        base = effective_hit
        base_presence = base&.web_presence
        return head :unprocessable_content if base_presence.nil?

        market = market_for_country
        own_presence = market&.market_web_presences&.order(:id)&.first
        if own_presence && own_presence != base_presence
          tag = resolve_language(own_presence, current: nil)
          return redirect_to "#{Markets::UrlPrefix.for(own_presence, tag)}#{return_path}",
                             status: :found, allow_other_host: false
        end

        tag = resolve_language(base_presence, current: current_language_tag(base))
        prefix = Markets::UrlPrefix.for(base_presence, tag)
        # 本尊每次提交都寫 cookie（含 primary 自己的國：language_code=en 時 `localization=TW; path=/en`）；
        # 只有「該國屬於別的 presence」才走上面的 302，不寫 cookie。
        if market && (own_presence.nil? || own_presence == base_presence)
          cookies[LOCALIZATION_COOKIE] = { value: country_code, path: prefix.presence || "/",
                                           expires: 1.year.from_now, same_site: :lax }
        end
        redirect_to "#{prefix}#{return_path}", status: :found, allow_other_host: false
      end
    rescue Markets::UrlPrefix::Error
      head :unprocessable_content
    end

    private

    def country_code
      code = params[:country_code].to_s.strip.upcase
      code.match?(MarketRegion::COUNTRY_CODE_FORMAT) ? code : nil
    end

    def market_for_country
      return nil if country_code.nil?

      MarketRegion.where(country_code:)
                  .joins(:market).merge(Market.active.where(market_type: "region"))
                  .order("markets.is_primary DESC, markets.id ASC")
                  .first&.market
    end

    # 當前語言＝POST 路徑前綴命中的語言；裸 /localization ⇒ return_to 的前綴命中；都無 ⇒ nil（落 presence 預設）。
    def current_language_tag(base)
      return base.locale_tag if params[:locale_prefix].present? && locale_hit

      return_prefix_hit&.locale_tag
    end

    def resolve_language(presence, current:)
      requested = params[:language_code].to_s.presence
      candidates = []
      # 表單送回的是主題輸出的本尊碼（zh-CN／zh-TW；ThemeEngine::LocaleTags）⇒ 先反查回我方 tag 再正規化
      candidates << Locales::Tag.normalize(ThemeEngine::LocaleTags.platform_tag(requested)) if requested
      candidates << current if current
      candidates.find { |tag| open_and_published?(presence, tag) } || presence.default_shop_locale
    end

    def open_and_published?(presence, tag)
      presence.market_web_presence_locales.open_to_buyers.exists?(locale_tag: tag) &&
        ShopLocale.where(shop_id: presence.shop_id, locale_tag: tag, published: true).exists?
    end

    # return_to 的第一段若是本店本網域**真的存在**的前綴 ⇒ 命中（用來剝前綴與取當前語言）；不用「像前綴」判斷
    # （/faq 這種兩三字母段是合法無前綴路徑）。
    def return_prefix_hit
      return @return_prefix_hit if defined?(@return_prefix_hit)

      raw = safe_return_to
      seg = raw.delete_prefix("/").split("/", 2)[0].to_s.downcase
      @return_prefix_hit = seg.match?(/\A#{Markets::UrlPrefix::SEGMENT.source}\z/) ? locale_hit(seg) : nil
    end

    def safe_return_to
      raw = params[:return_to].to_s
      raw.start_with?("/") && !raw.start_with?("//") ? raw : "/"
    end

    # return_to 剝舊前綴（只剝命中的前綴；無前綴路徑原樣）。
    def return_path
      raw = safe_return_to
      return raw if return_prefix_hit.nil?

      rest = raw.delete_prefix("/").split("/", 2)[1].to_s
      rest.empty? ? "/" : "/#{rest}"
    end
  end
end
