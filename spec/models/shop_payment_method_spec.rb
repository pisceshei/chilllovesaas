# frozen_string_literal: true

require "rails_helper"

# 結帳線第三包：manual 付款方式 model（86 §3 實測正典）。
RSpec.describe ShopPaymentMethod do
  let(:shop) { create(:shop, subdomain: "pm-shop") }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  it "M1 內建型別建立即得正典名；四型值域外拒收" do
    m = described_class.create!(shop_id: shop.id, method_type: "bank_deposit")
    expect(m.name).to eq("Bank Deposit")
    expect { described_class.create!(shop_id: shop.id, method_type: "paypal") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "M2 🔴 內建型別每店至多一列（86 §3：已啟用者從 ⊕ 選單消失）——model 驗證擋在 DB guard 之前" do
    described_class.create!(shop_id: shop.id, method_type: "bank_deposit")
    expect { described_class.create!(shop_id: shop.id, method_type: "bank_deposit", name: "BD 2") }
      .to raise_error(ActiveRecord::RecordInvalid, /已存在/)
  end

  it "M3 custom 可多列；名稱擋官方保留名單（大小寫不敏感——86 §3 逐字九名）" do
    described_class.create!(shop_id: shop.id, method_type: "custom", name: "AlipayHK 轉帳")
    described_class.create!(shop_id: shop.id, method_type: "custom", name: "FPS 轉數快")
    expect { described_class.create!(shop_id: shop.id, method_type: "custom", name: "gift card") }
      .to raise_error(ActiveRecord::RecordInvalid, /保留字/)
  end

  it "M4 snapshot 五鍵齊（含 payment_instructions——下單確認頁要用，86 §3 helper②）" do
    m = described_class.create!(shop_id: shop.id, method_type: "cash_on_delivery",
                                additional_details: "詳情", payment_instructions: "指示")
    expect(m.snapshot).to eq(
      "id" => m.id, "method_type" => "cash_on_delivery", "name" => "Cash on Delivery (COD)",
      "additional_details" => "詳情", "payment_instructions" => "指示"
    )
  end

  it "M5 停用＝active=false 不刪列（86 §3 Deactivate 語義）；active scope 只回啟用列" do
    m = described_class.create!(shop_id: shop.id, method_type: "money_order")
    m.update!(active: false)
    expect(described_class.active).to be_empty
    expect(described_class.count).to eq(1)
  end
end
