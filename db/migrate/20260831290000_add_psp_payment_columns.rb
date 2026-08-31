# frozen_string_literal: true

# G6-1c：checkout 的 PSP intent 引用欄（order_transactions 側用既有 provider_reference）。
class AddPspPaymentColumns < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:checkouts, :psp_intent_id)
      add_column :checkouts, :psp_intent_id, :string,
                 comment: "PSP payment intent id（輪詢／對帳引用；request_id 冪等使同 checkout 恆同 intent）"
    end
  end
end
