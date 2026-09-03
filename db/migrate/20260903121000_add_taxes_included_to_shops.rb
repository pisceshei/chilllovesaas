# frozen_string_literal: true

# 渲染 1:1（2026-09-03）：`cart.taxes_included`（官方 "Returns true if taxes are included in the prices of products in the cart."）
# 原為引擎硬編 false；hoko.vip 購物車抽屜稅注「已含税」⇒ 店級布林（預設 false；真值日後接法域包 tax_settings）。
class AddTaxesIncludedToShops < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:shops, :taxes_included)
      add_column :shops, :taxes_included, :boolean, default: false, null: false,
                 comment: "售價是否含稅（官方 cart.taxes_included；預設 false）"
    end
  end
end
