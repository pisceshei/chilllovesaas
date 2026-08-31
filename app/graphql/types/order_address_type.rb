# frozen_string_literal: true

module Types
  # 訂單上的地址快照（G6-6a；shipping_address／billing_address JSON 欄的出口）。
  #
  # 🔴 這是**快照**不是地址簿列（06 §2：顧客地址簿變更不回寫歷史訂單）——
  # 因此無 id、無 default 概念，與 CustomerAddressType 是兩個型別。
  # JSON 鍵對映（87 §3 checkout 收集面）：zone→province、其餘同名。
  # 解析輸入＝JSON Hash；空快照（{}）在 resolver 端回 null，本型別不處理空形。
  class OrderAddressType < BaseObject
    graphql_name "OrderAddress"
    description "訂單收貨／帳單地址快照"

    field :first_name, String, null: true
    field :last_name, String, null: true
    field :address1, String, null: true
    field :address2, String, null: true
    field :city, String, null: true
    field :province, String, null: true, description: "州/省（checkout zone 鍵對映）"
    field :postal_code, String, null: true
    field :country_code, String, null: true, description: "ISO 3166-1 alpha-2"
    field :phone, String, null: true

    def first_name = object["first_name"]
    def last_name = object["last_name"]
    def address1 = object["address1"]
    def address2 = object["address2"]
    def city = object["city"]
    def province = object["zone"]
    def postal_code = object["postal_code"]
    def country_code = object["country_code"]
    def phone = object["phone"]
  end
end
