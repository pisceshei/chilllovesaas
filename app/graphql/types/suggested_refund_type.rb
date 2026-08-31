# frozen_string_literal: true

module Types
  # 建議退款（G6-8；對位本尊 SuggestedRefund——官方句「A refund amount that Shopify
  # suggests based on the items, duties, and shipping costs that customers return.」，
  # 取證 2026-09-01）。
  #
  # 🔴 鐵律 7：本 type 的數字由 `Refunds::Calculator` 產生——與 refundCreate 實退
  # **同一份**計算程式碼（16 §F5.1「預覽的建議值與實際退款金額若能對不上就是 bug」）。
  # 解析輸入＝{ suggestion: Calculator::Suggestion, currency: String } Hash。
  class SuggestedRefundType < BaseObject
    graphql_name "SuggestedRefund"
    description "退款前的金額預覽（與實退共用同一份計算）"

    field :amount_set, MoneyBagType, null: false,
          description: "本次建議退款總額（行小計＋稅＋運費）"
    field :subtotal_set, MoneyBagType, null: false
    field :total_tax_set, MoneyBagType, null: false
    field :shipping_set, MoneyBagType, null: false
    field :maximum_refundable_set, MoneyBagType, null: false,
          description: "可退上限（= 已入帳 − 已退；16 §F5.1 軟上限）"

    def amount_set = money(object.fetch(:suggestion).total_cents)
    def subtotal_set = money(object.fetch(:suggestion).subtotal_cents)
    def total_tax_set = money(object.fetch(:suggestion).tax_cents)
    def shipping_set = money(object.fetch(:suggestion).shipping_cents)
    def maximum_refundable_set = money(object.fetch(:suggestion).maximum_refundable_cents)

    private

    def money(cents)
      { cents:, currency: object.fetch(:currency) }
    end
  end
end
