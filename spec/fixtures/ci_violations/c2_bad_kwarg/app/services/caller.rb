# 故意違反 C2：對 Psp::* 的呼叫用了不帶正確後綴的金額 kwarg。
class Caller
  def run(order)
    Psp::Stripe.new(:stripe).charge(amount: order.total, currency: "HKD")
  end

  # 🔴 反向對照（2026-08-31 隨 `_psp_number` 白名單增補）：三個合法後綴**不得**被 C2 誤擋。
  # test-money-rules 對本 fixture 斷言「輸出不得點名 amount_psp_number」——
  # 若有人把白名單縮回兩值，這一行會被誤判成違規、該斷言轉紅。
  def run_number(order)
    Psp::Airwallex.new(:airwallex).charge(amount_psp_number: order.total_psp_number, currency: "HKD")
  end
end
