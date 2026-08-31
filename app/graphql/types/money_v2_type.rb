# frozen_string_literal: true

module Types
  # 金額的對外序列化形（鐵律 3／65 §A R3：儲存 integer cents，**序列化層才轉
  # MoneyV2**——本型別就是那一層的 GraphQL 落點；G6-7 隨顧客線首發，
  # 後續 Order/LineItem 金額欄（G6-6）一律共用本型別）。
  #
  # 欄位契約（對位 Admin API MoneyV2）：
  # - `amount`：十進位字串、恆兩位小數（`Money::Display` 同一來源——鐵律 7：
  #   與結帳頁/後台顯示的字串同源），🔴 不是 Float（65 §C：JSON number 會被
  #   客戶端 parse 成 double）。
  # - `currencyCode`：ISO 4217 三碼。
  #
  # 解析輸入＝`{ cents: Integer, currency: String }` Hash（resolver 端組裝）。
  class MoneyV2Type < BaseObject
    graphql_name "MoneyV2"
    description "金額（amount 十進位字串＋currencyCode）"

    field :amount, String, null: false, description: "十進位金額字串（兩位小數）"
    field :currency_code, String, null: false, description: "ISO 4217 幣別碼"

    def amount
      Money::Display.call(Money::Storage.from_cents(object.fetch(:cents), object.fetch(:currency)))
    end

    def currency_code
      object.fetch(:currency)
    end
  end
end
