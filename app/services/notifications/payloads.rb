# frozen_string_literal: true

module Notifications
  # 通知 payload 建構器（G6 步 6；89 §5 官方變數名的唯一產地）。
  #
  # ①這是什麼：per-kind 的攤平 assigns。變數名逐一對位官方參考表：
  #   order 屬性攤平（name／order_name／order_number／subtotal_price／total_price／
  #   line_items／order_status_url…）、fulfillment 帶前綴（tracking_company／
  #   tracking_numbers／tracking_urls）、棄單恢復連結＝裸 url。
  # ②金額值一律 **integer cents**（鐵律 3；模板端經 money filter 顯示）。
  # ③order_status_url＝thank-you 頁（GET /checkouts/:token/complete）——我方尚無
  #   獨立 order status 頁，ours 簡化（89 §7 登記）。
  # ④host 鏈與 Seo::HreflangMatrix 同款：primary domain → subdomain.base_host。
  module Payloads
    class << self
      # @return [Hash] 訂單確認（orders/create）
      def order_confirmation(order:)
        shop = ActsAsTenant.without_tenant { order.shop }
        ActsAsTenant.with_tenant(shop) { base_order(order, shop) }
      end

      # @return [Hash] 出貨通知（order.fulfilled；notify=true）
      def shipping_confirmation(order:, fulfillment:)
        shop = ActsAsTenant.without_tenant { order.shop }
        numbers = Array(fulfillment.tracking_numbers)
        ActsAsTenant.with_tenant(shop) { base_order(order, shop) }.merge(
          fulfillment: {
            tracking_company: fulfillment.tracking_company,
            tracking_numbers: numbers.map { |row| row.is_a?(Hash) ? row["number"] : row },
            tracking_urls: numbers.filter_map { |row| row.is_a?(Hash) ? row["url"].presence : nil },
            item_count: Array(fulfillment.line_items_snapshot).sum { |li| li["quantity"].to_i }
          }
        )
      end

      # @return [Hash] 棄單挽回（步 7 觸發；url＝recovery 連結，官方裸名）
      def abandoned_checkout(checkout:, url:)
        shop = ActsAsTenant.without_tenant { checkout.shop }
        {
          shop: shop_hash(shop),
          url:,
          customer: { first_name: checkout.email.to_s.split("@").first },
          line_items: Array(checkout.line_items_snapshot).map do |line|
            qty = line["quantity"].to_i
            { title: line["title"], quantity: qty,
              price: line["unit_price_cents"].to_i,
              final_line_price: line["unit_price_cents"].to_i * qty }
          end
        }
      end

      private

      def base_order(order, shop)
        checkout_token = order.checkout_id &&
                         Checkout.where(shop_id: shop.id, id: order.checkout_id).pick(:token)
        {
          shop: shop_hash(shop),
          name: order.name,
          order_name: order.name,
          order_number: order.order_number,
          email: order.email,
          subtotal_price: order.subtotal_cents,
          shipping_price: order.shipping_cents,
          tax_price: order.tax_cents,
          total_price: order.total_cents,
          financial_status: order.financial_status,
          fulfillment_status: order.fulfillment_status,
          order_status_url: checkout_token && "#{origin(shop)}/checkouts/#{checkout_token}/complete",
          line_items: order.line_items.order(:id).map do |line|
            { title: line.title, quantity: line.quantity,
              final_line_price: line.total_cents, price: line.unit_price_cents }
          end
        }
      end

      def shop_hash(shop)
        { name: shop.name, url: origin(shop), email: shop.sender_email }
      end

      # host 解析鏈＝Seo::HreflangMatrix#absolute_url 同款（67 §F.1(d)）。
      # with_tenant 自帶：呼叫端不一定在 tenant block 內（Domain require_tenant）。
      def origin(shop)
        host = ActsAsTenant.with_tenant(shop) { Domain.primary.pick(:host) } ||
               "#{shop.subdomain}.#{Chilllove::TenantResolver.base_host}"
        "https://#{host}"
      end
    end
  end
end
