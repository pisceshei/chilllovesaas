class Psp::Bad
  def payload(order)
    total_decimal = order.to_decimal.string
    { amount: total_decimal }
  end
end
