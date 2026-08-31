# frozen_string_literal: true

require "rails_helper"

# G6 步 6：事件 → 消費者 → job → 信（鐵律 5：寄送在交易外）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   D1 registry 佈線（殺：Consumers 表漏掛——事件永遠沒人消費）
#   D2 notify=false 不寄（殺：拿掉 notify 閘——商家勾掉仍寄）
#   D5 無 email 不寄（殺：job 對 blank email 照寄）
RSpec.describe "notifications delivery chain" do
  include ActiveJob::TestHelper

  let(:shop) { create(:shop, subdomain: "notifd") }

  let(:order) do
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#9101", order_number: 9101, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 5000, total_cents: 5000,
        presentment_total_cents: 5000, financial_status: "pending",
        fulfillment_status: "unfulfilled", status: "open", email: "buyer@example.com",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
      LineItem.create!(shop_id: shop.id, order_id: o.id, title: "品",
                       quantity: 1, fulfillable_quantity: 1,
                       unit_price_cents: 5000, total_cents: 5000, currency: "HKD")
      o
    end
  end

  fab_event = Struct.new(:shop_id, :payload)

  after { clear_enqueued_jobs }

  it "🔴 D1 registry：orders/create 掛訂單確認、order.fulfilled 掛出貨通知" do
    expect(Events::Consumers.for(Events::Topics::ORDERS_CREATE))
      .to include(Notifications::OrderConfirmationConsumer)
    expect(Events::Consumers.for(Events::Topics::ORDER_FULFILLED))
      .to include(Notifications::ShippingConfirmationConsumer)
  end

  it "orders/create 消費者 ⇒ 入列 DeliverJob（帶 order_id）" do
    event = fab_event.new(shop.id, { "order_id" => order.id })
    expect { Notifications::OrderConfirmationConsumer.call(event) }
      .to have_enqueued_job(Notifications::DeliverJob)
      .with(shop_id: shop.id, kind: "order_confirmation", order_id: order.id)
  end

  it "🔴 D2 notify=false ⇒ 出貨通知不入列（商家勾掉「通知顧客」）" do
    event = fab_event.new(shop.id, { "order_id" => order.id, "fulfillment_id" => 1, "notify" => false })
    expect { Notifications::ShippingConfirmationConsumer.call(event) }
      .not_to have_enqueued_job(Notifications::DeliverJob)
  end

  it "notify=true ⇒ 入列" do
    event = fab_event.new(shop.id, { "order_id" => order.id, "fulfillment_id" => 1, "notify" => true })
    expect { Notifications::ShippingConfirmationConsumer.call(event) }
      .to have_enqueued_job(Notifications::DeliverJob)
  end

  it "D4 DeliverJob 端到端：寄出一封、to＝order.email、subject 已渲染" do
    expect do
      Notifications::DeliverJob.perform_now(shop_id: shop.id, kind: "order_confirmation",
                                            order_id: order.id)
    end.to change { ActionMailer::Base.deliveries.size }.by(1)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "buyer@example.com" ])
    expect(mail.subject).to eq("Order #9101 confirmed")
    expect(mail.html_part&.body&.to_s || mail.body.to_s).to include("HK$50.00")
  end

  it "🔴 D5 order.email 空 ⇒ 不寄（靜默跳過，不炸 job）" do
    ActsAsTenant.without_tenant { Order.where(id: order.id).update_all(email: nil) }
    expect do
      Notifications::DeliverJob.perform_now(shop_id: shop.id, kind: "order_confirmation",
                                            order_id: order.id)
    end.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "From＝shop.sender_email；未設定 ⇒ no-reply@<base_host>" do
    ActsAsTenant.without_tenant { Shop.where(id: shop.id).update_all(sender_email: "eshop@notif.example") }
    Notifications::DeliverJob.perform_now(shop_id: shop.id, kind: "order_confirmation", order_id: order.id)
    expect(ActionMailer::Base.deliveries.last.from).to eq([ "eshop@notif.example" ])
  end
end
