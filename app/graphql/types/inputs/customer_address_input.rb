# frozen_string_literal: true

module Types
  module Inputs
    # 顧客地址輸入（官方 MailingAddressInput 對位子集；country_code 兩碼）。
    class CustomerAddressInput < GraphQL::Schema::InputObject
      graphql_name "CustomerAddressInput"
      description "顧客地址欄位（省略＝不變／不設）"

      argument :first_name, String, required: false
      argument :last_name, String, required: false
      argument :company, String, required: false
      argument :address1, String, required: false
      argument :address2, String, required: false
      argument :city, String, required: false
      argument :province, String, required: false
      argument :postal_code, String, required: false
      argument :country_code, String, required: false
      argument :phone, String, required: false
    end
  end
end
