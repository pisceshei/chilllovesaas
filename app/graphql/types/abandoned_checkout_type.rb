# frozen_string_literal: true

module Types
  # 棄單（G6 步 7；89 §8 實測列表七欄的資料面）。
  #
  # 官方對位：AbandonedCheckout（abandonedCheckoutUrl 逐字＝"The URL for the
  # buyer to recover their checkout."）；Email status／Recovery status 是 admin
  # 列表徽章（89 §8）——recovery status v1＝「該 checkout 已成單」（不追連結歸因，
  # ours 簡化、91 §3 登記）。
  class AbandonedCheckoutType < BaseObject
    graphql_name "AbandonedCheckout"
    description "棄單（已提供 email 且逾時未完成的結帳）"

    field :id, GraphQL::Types::ID, null: false
    field :email, String, null: true
    field :customer_name, String, null: true, description: "地址簿姓名（billing→shipping 先到先得）"
    field :region, String, null: true, description: "國家/地區（列表 Region 欄）"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :abandoned_at, GraphQL::Types::ISO8601DateTime, null: false
    field :total_price_set, MoneyBagType, null: false
    field :line_items_count, Integer, null: false
    field :recovery_email_sent_at, GraphQL::Types::ISO8601DateTime, null: true,
          description: "挽回信寄出時間（null＝Not sent）"
    field :recovered, Boolean, null: false,
          description: "已成單（v1＝orders.checkout_id 存在；不追連結歸因）"
    field :abandoned_checkout_url, String, null: false,
          description: "挽回連結（官方同名欄；回結帳頁還原快照）"

    def id
      "gid://chilllove/AbandonedCheckout/#{object.id}"
    end

    def customer_name
      %w[billing_address shipping_address].each do |key|
        address = object.public_send(key)
        next if address.blank?

        name = [ address["first_name"], address["last_name"] ].compact_blank.join(" ")
        return name if name.present?
      end
      nil
    end

    def region
      (object.billing_address.presence || object.shipping_address.presence || {})["country"]
    end

    def total_price_set
      { cents: object.total_cents, currency: object.currency,
        presentment_cents: object.presentment_total_cents.nonzero? || object.total_cents,
        presentment_currency: object.presentment_currency }
    end

    def line_items_count
      Array(object.line_items_snapshot).sum { |line| line["quantity"].to_i }
    end

    def recovered
      Order.where(shop_id: object.shop_id, checkout_id: object.id).exists?
    end

    def abandoned_checkout_url
      Notifications::RecoveryUrl.for(object)
    end
  end
end
