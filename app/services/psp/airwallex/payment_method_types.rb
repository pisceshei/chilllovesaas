# frozen_string_literal: true

module Psp
  module Airwallex
    # capability 查詢（G6-1b；15-F4.2 條件 2 的來源）。
    #
    # 官方逐字 schema（取證 2026-08-31）：`GET /api/v1/pa/config/payment_method_types`
    # 回 `{has_more, items:[{active, flows, name, transaction_currencies,
    # transaction_mode}]}`；**同名方法可因 transaction_mode 重複** ⇒ 去重；
    # 結帳能力只取 `transaction_mode=oneoff`（官方：oneoff→Payment Intent API）＋
    # `active=true`（皆由 query 參數過濾，回應側仍複驗——寧可雙重）。
    module PaymentMethodTypes
      module_function

      # @param provider [ShopPaymentProvider] airwallex 列
      # @param transport [#call, nil] 注入給 Client（specs 用）
      # @return [Array<String>] active oneoff 方法名（原樣 name、去重、字母序）
      # @raise [Client::Unauthorized, Client::Error]
      def fetch(provider, transport: nil)
        client = Client.new(provider, transport:)
        path = Limits.fetch(:psp_integration, :airwallex, :payment_method_types_path)
        page_size = Limits.fetch(:psp_integration, :airwallex, :capability_page_size)
        mode = Limits.fetch(:psp_integration, :airwallex, :capability_transaction_mode)

        names = []
        page = 0
        loop do
          data = client.get_json("#{path}?active=true&transaction_mode=#{mode}&page_size=#{page_size}&page_num=#{page}")
          items = data.fetch("items", [])
          names.concat(
            items.select { |item| item["active"] == true && item["transaction_mode"].to_s == mode.to_s }
                 .map { |item| item.fetch("name").to_s }
          )
          break unless data["has_more"] == true

          page += 1
        end
        names.uniq.sort
      end
    end
  end
end
