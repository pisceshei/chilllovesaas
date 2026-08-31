# frozen_string_literal: true

# G6-3（步 2）：付款請款模式落庫（86 §2 modal 實測——radio 恰三值；
# limits capture.modes 四值中 automatic_per_fulfillment 為 Plus-only，
# UI 照本尊 modal 三值出、enum 保留四值）。
class AddPaymentCaptureMethodToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :payment_capture_method, :string, limit: 40,
      null: false, default: "automatic_at_checkout",
      comment: "請款模式（limits capture.modes；86 §2 modal 三值 UI＋enum 四值保留）"
  end
end
