# frozen_string_literal: true

module Seo
  # 平台層商品 JSON-LD（62 §A；第 1 層責任、不可關）。
  #
  # 🔴 數字同源（§A.3；鐵律 7 的 SEO 面）：price 由 **integer cents** 直接序列化——
  #   `amount_cents / 100`、固定兩位小數十進位字串、無符號無千分位、**不看幣別**
  #   （§A.4 定案(1)；JPY 儲存 100000 ⇒ "1000.00"）。可見價的符號／千分位由 market
  #   locale 決定（鐵律 10）——兩者共用 cents，**不共用格式器**。
  # 🔴 禁止的實作（§A.3）：從 money filter 輸出逆向 parse 回數字＝第二個價格來源。
  # 🔴 UNLISTED 不輸出 Offer（limits `product.unlisted_excluded_from` 含 jsonld_offer）
  #   ——呼叫端（HeadTags）整段跳過，本模組不重複判。
  module JsonLd
    module_function

    # @param product [Product] 變體已 preload
    # @param url [String] canonical 絕對 URL
    # @param currency [String] presentment 幣別（v1＝shop.store_currency，單市場）
    # @return [String] <script type="application/ld+json"> 區塊
    def product_script(product:, url:, currency:)
      variants = product.product_variants.sort_by(&:position)
      offers = variants.map do |variant|
        {
          "@type" => "Offer",
          "url" => url,
          "price" => format_price(variant.price_cents),
          "priceCurrency" => currency,
          "availability" => availability(variant)
        }
      end
      payload = {
        "@context" => "https://schema.org",
        "@type" => "Product",
        "name" => product.title,
        "url" => url,
        "offers" => offers
      }
      # priceValidUntil：無真實檔期 ⇒ 整個屬性省略（§A.6；禁止 now+90 假宣告）。
      %(<script type="application/ld+json">#{JSON.generate(payload)}</script>)
    end

    # §A.4 定案(1)：cents/100、恆兩位小數、"." 小數點、無千分位。
    def format_price(cents)
      whole, frac = cents.to_i.divmod(100)
      format("%d.%02d", whole, frac)
    end

    # §A.5 對映（依序判定）：只看「可用」不看「現有」；未追蹤＝InStock。
    def availability(variant)
      item = variant.inventory_item
      return "https://schema.org/InStock" if item.nil? || !item.tracked

      available = item.inventory_levels.sum(&:available)
      return "https://schema.org/InStock" if available.positive?
      return "https://schema.org/BackOrder" if variant.inventory_policy == "continue"

      "https://schema.org/OutOfStock"
    end
  end
end
