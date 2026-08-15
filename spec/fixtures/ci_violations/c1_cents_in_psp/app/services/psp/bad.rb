# 故意違反 C1：PSP 目錄裡出現 storage 尺度的識別字。
class Psp::Bad
  def charge(order)
    amount_cents = order.total_cents
    post(amount: amount_cents)
  end
end
