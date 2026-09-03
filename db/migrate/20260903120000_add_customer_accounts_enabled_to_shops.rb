# frozen_string_literal: true

# 渲染 1:1（2026-09-03）：`shop.customer_accounts_enabled`（官方："Returns true if the store shows a login link."）
# 原為引擎硬編 false；本尊新店預設顯示登入連結（hoko.vip 未動設定即渲染 Drawer-Account）⇒ 店級布林、預設 true。
class AddCustomerAccountsEnabledToShops < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:shops, :customer_accounts_enabled)
      add_column :shops, :customer_accounts_enabled, :boolean, default: true, null: false,
                 comment: "storefront 是否顯示登入連結（官方 shop.customer_accounts_enabled；預設 true＝本尊新店形）"
    end
  end
end
