# frozen_string_literal: true

module Types
  # 金額雙幣包（G6-6a；對位 Admin API MoneyBag：shopMoney＋presentmentMoney）。
  #
  # v1 單幣別階段兩者恆同值（checkout 線 presentment_currency == currency，
  # markets 幣別包接手後才分岔）——型別面先照契約形出齊，消費端不用改（ours，
  # 88 §7）。解析輸入＝{ cents:, currency:, presentment_cents:, presentment_currency: }
  # Hash（後兩鍵缺省時回落前兩鍵）。鐵律 3：cents 不裸出，經 MoneyV2 序列化。
  class MoneyBagType < BaseObject
    graphql_name "MoneyBag"
    description "店幣與展示幣的金額對（v1 兩者同值）"

    field :shop_money, MoneyV2Type, null: false
    field :presentment_money, MoneyV2Type, null: false

    def shop_money
      { cents: object.fetch(:cents), currency: object.fetch(:currency) }
    end

    def presentment_money
      { cents: object.fetch(:presentment_cents, object.fetch(:cents)),
        currency: object.fetch(:presentment_currency, object.fetch(:currency)) }
    end
  end
end
