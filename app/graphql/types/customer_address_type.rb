# frozen_string_literal: true

module Types
  # 顧客地址（G6-7；來源＝customer_addresses 表——checkout 收貨地址在首單時
  # 補進地址簿的那份，06 §2：與訂單 JSON 快照是兩層）。
  class CustomerAddressType < BaseObject
    graphql_name "CustomerAddress"
    description "顧客地址簿的一列"

    field :id, GraphQL::Types::ID, null: false
    field :first_name, String, null: true
    field :last_name, String, null: true
    field :address1, String, null: false
    field :address2, String, null: true
    field :city, String, null: false
    field :province, String, null: true, description: "州/省（checkout zone 對映）"
    field :postal_code, String, null: true
    field :country_code, String, null: false, description: "ISO 3166-1 alpha-2"
    field :phone, String, null: true
    field :default, Boolean, null: false, method: :default_address

    def id
      "gid://chilllove/CustomerAddress/#{object.id}"
    end
  end
end
