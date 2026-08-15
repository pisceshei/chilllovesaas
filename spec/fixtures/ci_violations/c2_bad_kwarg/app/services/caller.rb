# 故意違反 C2：對 Psp::* 的呼叫用了不帶正確後綴的金額 kwarg。
class Caller
  def run(order)
    Psp::Stripe.new(:stripe).charge(amount: order.total, currency: "HKD")
  end
end
