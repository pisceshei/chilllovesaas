class Psp::Bad
  def payload(order)
    value = Money::Decimal.from_string("14.80", "HKD")
    { amount: value.string }
  end
end
