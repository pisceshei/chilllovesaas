# frozen_string_literal: true

module Storefront
  # 購物車 Ajax 端點（specs/15 F1；契約對照 83 §3.3／§12.5 真店逐格）。
  #
  # ①路由形：`.js` 與裸路徑同義（Ella 用 routes.cart_add_url＝裸 `/cart/add`，
  #   83 §4.4——兩形都收，皆回 JSON）。
  # ②錯誤形（真店 422 實測逐字結構）：`{"status":…,"message":…,"description":…}`；
  #   文案繁中（鐵律 10；不抄本尊英文文案——鐵律 9）。
  # ③🔴 A1 已收口（包 33 後半）：vehicle＝**host 解析的公開端點**——shop 恆由
  #   TenantResolver 依 host 寫入 `Current.shop`，匿名買家可用；不再要求 staff
  #   session（原掛 Admin::BaseController 的 staff 閘已摘除；staff 預覽在同一
  #   租戶 host，走同一組端點）。防濫用＝Rack::Attack `storefront-cart/ip`
  #   （本尊 cart 端點有 bot 牆 429——83 §12.5 量測，我方對位）。
  # ④cookie `_cl_buyer`：簽名、host-only（F1 ⚠️坑：跨店共享防線——**不設
  #   domain 屬性**）；值＝cart token。落在真店網域＝host-only 語義自此真實。
  # ⑤bundled section rendering（官方句：cart 變更建議帶 sections 參數）：
  #   POST 帶 `sections` ⇒ 回應加 `sections` map（複用 #203 fragment 機制，
  #   context＝`sections_url` 參數指定的頁，預設 "/"）。
  class CartController < BaseController
    # 主題 JS 的 Ajax POST 無 CSRF token（storefront 語義；本尊同形）。
    # 寫入面靠 host-only 簽名 cookie 綁車＋限流，不靠 CSRF。
    skip_forgery_protection

    rescue_from Storefront::CartError do |e|
      render json: e.as_json_body, status: e.status
    end

    # GET /cart.js
    def show
      render json: CartSerializer.cart_json(current_cart)
    end

    # POST /cart/add(.js)：回「被加入的行」陣列（官方形：非整車——83 官方句）
    def add
      lines = add_params.map do |item|
        CartWriter.add(cart: current_cart, variant_id: item[:id],
                       quantity: item.fetch(:quantity, 1),
                       properties: item[:properties].to_h)
      end
      payload = { "items" => lines.map { |l| CartSerializer.item_json(l) } }
      render json: payload.merge(sections_payload)
    end

    # POST /cart/change(.js)：id/line ＋ quantity（0＝移除）⇒ 整車
    def change
      key = params[:id].presence || line_key_from_line_param
      CartWriter.change(cart: current_cart, line_key: key, quantity: params.require(:quantity))
      render json: CartSerializer.cart_json(current_cart.reload).merge(sections_payload)
    end

    # POST /cart/update(.js)：note／attributes／updates ⇒ 整車
    def update
      CartWriter.update_meta(cart: current_cart, note: params[:note],
                             attributes: free_form_hash(params[:attributes]))
      apply_updates_param
      render json: CartSerializer.cart_json(current_cart.reload).merge(sections_payload)
    end

    # POST /cart/clear(.js)：清行、保留 note/attributes ⇒ 整車
    def clear
      CartWriter.clear(cart: current_cart)
      render json: CartSerializer.cart_json(current_cart.reload).merge(sections_payload)
    end

    # GET /cart/shipping_rates.json——運費試算（第三包；86 §6 官方三支的同步形）。
    # 回應形＝官方逐字結構：{"shipping_rates":[{"name","price","source"}]}；
    # 🔴 price＝**十進位主單位字串**（"62.73"）——序列化層邊界（鐵律 3），
    #   cents 在這裡經 divmod 轉字串、不得把 cents 裸值放進 JSON。
    # 費率集合＝46c 合併形（試算是單一清單，split 呈現屬 checkout 頁）；
    # 不可配送／不在 market ⇒ 空陣列（官方錯誤形未取得——ours，登記 86）。
    def shipping_rates
      render json: { "shipping_rates" => estimate_rates }
    end

    # POST /cart/prepare_shipping_rates.json——官方「發起計算」支。我方同步引擎
    # 一次算完（官方 prepare 的回應形未取得——ours：回與同步支相同結果）。
    def prepare_shipping_rates
      render json: { "shipping_rates" => estimate_rates }
    end

    # GET /cart/async_shipping_rates.json——官方「取結果」支（未完成回 null；
    # 我方同步引擎恆已完成）。
    def async_shipping_rates
      render json: { "shipping_rates" => estimate_rates }
    end

    private

    COOKIE = "_cl_buyer"

    # 試算輸入＝cart 行的即時快照（與 CreateFromCart 同源欄）；目的地取
    # `shipping_address[country]`（86 §6 官方參數形；zip/province 收下不用——
    # 我方 zone 為國級，州級登記 85 §4 V）。
    def estimate_rates
      # E14：Ella 運費試算表單 POST 的是 all_country_option_tags 的 value＝英文國名（本尊形）；國碼照收。字典外的二位碼
      # 仍交 RateResolver 判（不在 market 就是空陣列——R2）。
      raw = params.dig(:shipping_address, :country).to_s.strip
      country = ThemeEngine::CountryOptionTags.code_for(raw) || (raw.match?(/\A[A-Za-z]{2}\z/) ? raw.upcase : "")
      return [] if country.blank?

      cart = current_cart
      lines = ActsAsTenant.with_tenant(Current.shop) do
        cart.cart_line_items.includes(product_variant: :product).order(:id).map do |line|
          variant = line.product_variant
          { key: line.id.to_s, quantity: line.quantity, unit_price_cents: variant.price_cents,
            weight_grams: variant.weight_grams, requires_shipping: variant.requires_shipping,
            shipping_profile_id: variant.product.shipping_profile_id }
        end
      end
      return [] if lines.empty?

      result = ActsAsTenant.with_tenant(Current.shop) do
        Checkouts::RateResolver.call(shop: Current.shop, country_code: country, lines:)
      end
      return [] unless result.ok?

      result.merged_options.map do |option|
        { "name" => option.name, "price" => decimal_string(option.price_cents),
          "source" => "chilllove" }
      end
    end

    # cents → 十進位主單位字串（"6.00" 形；同 Seo::JsonLd 的 divmod 紀律——不走 float）。
    def decimal_string(cents)
      format("%d.%02d", cents / 100, cents % 100)
    end

    def current_cart
      @current_cart ||= ActsAsTenant.with_tenant(Current.shop) do
        token = cookies.signed[COOKIE]
        cart = token && Cart.includes(cart_line_items: { product_variant: :product })
                            .find_by(shop_id: Current.shop.id, token: token)
        cart || create_cart!
      end
    end

    def create_cart!
      cart = Cart.create!(shop_id: Current.shop.id, attributes_json: {})
      # 🔴 host-only：刻意不給 :domain（給了＝跨店共享，F1 ⚠️坑）。
      cookies.signed[COOKIE] = { value: cart.token, httponly: true, same_site: :lax }
      cart
    end

    # 兩種官方載體（83 §4：Ella=FormData `id=…&quantity=…`；JSON=items 陣列）。
    def add_params
      if params[:items].present?
        params.require(:items).map { |i| i.permit(:id, :quantity, properties: {}) }
      else
        [ params.permit(:id, :quantity, properties: {}) ]
      end
    end

    def line_key_from_line_param
      index = Integer(params[:line], exception: false)
      raise Storefront::CartError.new("缺少 id 或 line 參數。", status: 400) if index.nil? || index < 1

      line = current_cart.cart_line_items.order(:id)[index - 1]
      raise Storefront::CartError.new("找不到此購物車行。", status: 404) if line.nil?

      line.id.to_s
    end

    def apply_updates_param
      updates = params[:updates]
      return if updates.blank?

      if updates.is_a?(ActionController::Parameters)
        free_form_hash(updates).each do |key, qty|
          CartWriter.change(cart: current_cart, line_key: key, quantity: qty)
        end
      else
        Array(updates).each_with_index do |qty, i|
          line = current_cart.cart_line_items.order(:id)[i] or next
          CartWriter.change(cart: current_cart, line_key: line.id.to_s, quantity: qty)
        end
      end
    end

    # 契約性自由表（Ajax attributes／updates map）的顯式淨化：逐鍵讀出、
    # 值壓成字串——不用 permit!（Brakeman Mass Assignment；這些值只進 json
    # 欄與數量解析，不觸 AR 屬性指派）。
    def free_form_hash(raw)
      return {} if raw.nil?

      raw.keys.each_with_object({}) { |k, h| h[k.to_s] = raw[k].to_s }
    end

    # bundled section rendering（≤5 與缺失→null 的語義沿用 #203 fragment 端點）。
    def sections_payload
      raw = params[:sections]
      return {} if raw.blank?

      ids = raw.is_a?(Array) ? raw.map(&:to_s) : raw.to_s.split(",").map(&:strip)
      theme = ActsAsTenant.with_tenant(Current.shop) { Theme.published.first }
      return {} if theme.nil?

      sections_url = params[:sections_url].presence || "/"
      hit = locale_hit(sections_url.to_s.delete_prefix("/").split("/", 2)[0]) || default_hit # E12：段的語言跟 sections_url 前綴；E13：無前綴退回店預設
      renderer = ThemeEngine::PageRenderer.new(
        theme:, shop: Current.shop, publication: Publication.online_store!,
        host: request.host, cart_json: CartSerializer.cart_json(current_cart.reload),
        url_prefix: hit ? Markets::UrlPrefix.for(hit.web_presence, hit.locale_tag) : "",
        locale: hit&.locale_tag, web_presence: hit&.web_presence,
        market: hit&.market, country_code: hit&.effective_country_code
      )
      result = renderer.render(strip_locale_prefix(sections_url),
                               params: { "sections" => ids.join(",") })
      { "sections" => JSON.parse(result.html) }
    rescue JSON::ParserError
      {}
    end

    # sections_url 來自主題 JS 的 location.pathname ⇒ 可能帶前綴（/zh-hant/products/x；預設語言無前綴）；
    # PageRenderer 收前綴已剝的站內路徑（包 34）。D80：只剝**真的命中**的前綴（locale_hit），不剝「像前綴」的段。
    def strip_locale_prefix(path)
      segments = path.to_s.delete_prefix("/").split("/", 2)
      return path if segments[0].blank? || locale_hit(segments[0]).nil?

      rest = segments[1].to_s
      rest.empty? ? "/" : "/#{rest}"
    end
  end
end
