# frozen_string_literal: true

# G6-1b（capability 面）：provider 列快取「PSP 帳號實際開通的方式」。
#
# 15-F4.2：結帳顯示＝商家白名單 ∩ **PSP capability**——條件 2 的資料落點。
# 同步時點＝憑證儲存成功後自動＋詳情頁手動「重新讀取」（外部 IO 在交易外，鐵律 5）。
class AddCapabilitiesToShopPaymentProviders < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:shop_payment_providers, :available_methods)
      safety_assured do
        add_column :shop_payment_providers, :available_methods, :json, null: false,
                   default: -> { "(json_array())" },
                   comment: "PSP capability API 回報的 active oneoff 方法名快取（原樣 name；15-F4.2 條件 2）"
      end
    end
    unless column_exists?(:shop_payment_providers, :capabilities_synced_at)
      add_column :shop_payment_providers, :capabilities_synced_at, :datetime,
                 comment: "上次成功同步 capability 的時點；NULL＝從未成功（UI 顯示未同步態）"
    end
  end
end
