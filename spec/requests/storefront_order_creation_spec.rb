# frozen_string_literal: true

require "rails_helper"

# G6-0(a) 訂單成立（15-F5 manual 形）端到端。
#
# 🔴 假綠殺手（鐵律 20.2⑤）——每格點名要殺的實作：
#   O2 重複提交恰一單（殺：Guard 拔掉／checkout 條件轉移讀舊快照直寫）
#   O3 庫存不足整單回滾（殺：先建單後扣庫存的部分寫入；counter 半推進）
#   O4 policy=continue 允許負庫存（殺：把 deny 條件寫成無條件套用）
#   O7 outbox 與訂單同 transaction（殺：commit 後補發——崩潰窗掉事件，11 §8）
#   O8 每店連號（殺：全域自增洩漏平台總量——15-F5 ⚠️坑第 1 條）
RSpec.describe "Storefront order creation（G6-0a）", type: :request do
  let!(:shop) { create(:shop, subdomain: "oc-shop") }
  let!(:pay_method) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: "bank_deposit",
                                additional_details: "轉帳到 000-000",
                                payment_instructions: "回傳收據後 1 個工作天內確認。")
    end
  end
  let(:variant) { variant_for(title: "下單測品", price: 10_000, stock: 5) }

  def variant_for(title:, price:, stock:, policy: "deny", tracked: true, ship: true)
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: price, requires_shipping: ship,
                 inventory_policy: policy,
                 product: create(:product, shop:, status: "active", title:))
      v.inventory_item.update!(tracked: tracked)
      v.inventory_item.inventory_levels.order(:id).first.update!(available: stock)
      v
    end
  end

  before do
    host! "oc-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  # 建 checkout 並走完 delivery＋payment（成立前置）
  def ready_checkout!(variants_with_qty)
    items = variants_with_qty.map { |v, q| { id: v.id, quantity: q } }
    post "/cart/add.js", params: { items: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    post "/checkouts/#{token}/delivery", params: { country_code: "HK" }
    post "/checkouts/#{token}/payment", params: { payment_method_id: pay_method.id }
    ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
  end

  def order_of(checkout)
    ActsAsTenant.with_tenant(shop) { Order.find_by(shop_id: shop.id, checkout_id: checkout.id) }
  end

  it "O1 happy path：單號 #1001、行快照、manual sale/pending 交易、庫存 available−/committed+、" \
     "cart 刪除、thank-you 顯示付款指示" do
    checkout = ready_checkout!([ [ variant, 2 ] ])
    level = ActsAsTenant.with_tenant(shop) { variant.inventory_item.inventory_levels.order(:id).first }

    post "/checkouts/#{checkout.token}/complete"
    expect(response).to redirect_to("/checkouts/#{checkout.token}/complete")

    order = order_of(checkout)
    expect(order.name).to eq("#1001")
    expect(order.order_number).to eq(1001)
    expect(order.financial_status).to eq("pending")
    expect(order.total_cents).to eq(20_000) # 行 2×10000＋provision 免運 0（鐵律 7 同源）
    expect(order.shipping_cents).to eq(0)
    li = ActsAsTenant.with_tenant(shop) { order.line_items.sole }
    expect(li).to have_attributes(title: "下單測品", quantity: 2, unit_price_cents: 10_000,
                                  total_cents: 20_000, fulfillable_quantity: 2)
    tx = ActsAsTenant.with_tenant(shop) { order.order_transactions.sole }
    expect(tx).to have_attributes(kind: "sale", status: "pending", gateway: "bank_deposit",
                                  amount_cents: order.total_cents)
    expect(level.reload).to have_attributes(available: 3, committed: 2)
    expect(ActsAsTenant.with_tenant(shop) { Checkout.find(checkout.id).status }).to eq("completed")
    expect(ActsAsTenant.with_tenant(shop) { Cart.count }).to eq(0) # F5 步 5 同交易刪車

    get "/checkouts/#{checkout.token}/complete"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("#1001").and include("回傳收據後 1 個工作天內確認")
  end

  it "O2 🔴 重複提交恰一單：同路徑再 POST ⇒ replay 導回 thank-you，不建第二張" do
    checkout = ready_checkout!([ [ variant, 1 ] ])
    post "/checkouts/#{checkout.token}/complete"
    expect {
      post "/checkouts/#{checkout.token}/complete"
      expect(response).to have_http_status(:see_other)
    }.not_to change { ActsAsTenant.with_tenant(shop) { Order.count } }
    expect(ActsAsTenant.with_tenant(shop) { Order.sole.order_number }).to eq(1001)
  end

  it "O3 🔴 庫存不足（deny）⇒ 422＋整單回滾：無 order／無 outbox／checkout 仍 open／庫存不動／counter 不動" do
    low = variant_for(title: "只剩一件", price: 5_000, stock: 1)
    checkout = ready_checkout!([ [ low, 2 ] ])
    post "/checkouts/#{checkout.token}/complete"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("庫存不足")

    ActsAsTenant.with_tenant(shop) do
      expect(Order.count).to eq(0)
      expect(Checkout.find(checkout.id).status).to eq("open")
      expect(low.inventory_item.inventory_levels.order(:id).first)
        .to have_attributes(available: 1, committed: 0)
    end
    expect(ActsAsTenant.without_tenant { EventOutbox.where(topic: "orders/create").count }).to eq(0)
    expect(Shop.find(shop.id).order_counter).to eq(1000) # counter 同交易回滾（O8 前提）
  end

  it "O4 policy=continue ⇒ 允許負 available（商家明示允許超賣）" do
    cont = variant_for(title: "可超賣", price: 3_000, stock: 1, policy: "continue")
    checkout = ready_checkout!([ [ cont, 3 ] ])
    post "/checkouts/#{checkout.token}/complete"
    expect(response).to have_http_status(:see_other)
    level = ActsAsTenant.with_tenant(shop) { cont.inventory_item.inventory_levels.order(:id).first }
    expect(level).to have_attributes(available: -2, committed: 3)
  end

  it "O5 前置未齊 ⇒ 422：未選運送（需運送車）／未選付款各自擋下" do
    # 未選付款：只走 delivery
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    post "/checkouts/#{token}/delivery", params: { country_code: "HK" }
    post "/checkouts/#{token}/complete"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("請先選擇付款方式")

    # 未選運送：只走 payment
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token2 = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    post "/checkouts/#{token2}/payment", params: { payment_method_id: pay_method.id }
    post "/checkouts/#{token2}/complete"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("請先選擇運送方式")
  end

  it "O6 untracked 變體不扣庫存、照常成單" do
    untracked = variant_for(title: "不追蹤", price: 2_000, stock: 0, tracked: false)
    checkout = ready_checkout!([ [ untracked, 4 ] ])
    post "/checkouts/#{checkout.token}/complete"
    expect(response).to have_http_status(:see_other)
    expect(order_of(checkout)).to be_present
  end

  it "O7 🔴 outbox 與訂單同 transaction：成功恰一列 orders/create；🔴 manual 不發 orders/paid" do
    checkout = ready_checkout!([ [ variant, 1 ] ])
    post "/checkouts/#{checkout.token}/complete"
    rows = ActsAsTenant.without_tenant { EventOutbox.where("topic LIKE 'orders/%'").pluck(:topic) }
    expect(rows).to eq([ "orders/create" ])
  end

  it "O8 🔴 每店連號：同店第二單 1002；別店從自己的 1001 起（不洩漏平台總量）" do
    c1 = ready_checkout!([ [ variant, 1 ] ])
    post "/checkouts/#{c1.token}/complete"
    c2 = ready_checkout!([ [ variant, 1 ] ])
    post "/checkouts/#{c2.token}/complete"
    expect(ActsAsTenant.with_tenant(shop) { Order.order(:order_number).pluck(:order_number) })
      .to eq([ 1001, 1002 ])
  end

  it "O9 thank-you 閘：checkout 仍 open ⇒ GET complete 導回結帳頁（不洩單）" do
    checkout = ready_checkout!([ [ variant, 1 ] ])
    get "/checkouts/#{checkout.token}/complete"
    expect(response).to redirect_to("/checkouts/#{checkout.token}")
  end

  it "O10 完成鈕點亮邏輯：前置未齊＝disabled＋原因；齊備＝真 form" do
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    get "/checkouts/#{token}"
    expect(response.body).to include("請先選擇運送方式。")
    expect(response.body).not_to include("data-complete-form")

    post "/checkouts/#{token}/delivery", params: { country_code: "HK" }
    post "/checkouts/#{token}/payment", params: { payment_method_id: pay_method.id }
    get "/checkouts/#{token}"
    expect(response.body).to include("data-complete-form")
  end
end
