# frozen_string_literal: true

# 包 33 後半（A2）：cart_item_limit 商家設定欄（缺口分析 A2；limits `cart.item_limit_*`）。
# 本尊形態（44:378 live 實測）：modal stepper 預設 50＋「您商店的建議上限為 50」＋開關。
# 商家後台設定頁隨結帳偏好包；本欄先落資料層讓 CartWriter 有真值可讀。
class AddCartSettingsToShops < ActiveRecord::Migration[8.1]
  def change
    # 預設值＝limits `cart.item_limit_suggested`（50）。migration 不讀 Limits（鐵律 6 的
    # 引用義務落在執行程式碼——CartWriter；schema default 是資料快照，兩處由 spec 釘住同值）。
    add_column :shops, :cart_item_limit, :integer, null: false, default: 50,
               comment: "cart 總件數上限（A2；建議值 50＝limits cart.item_limit_suggested）"
    add_column :shops, :cart_item_limit_enabled, :boolean, null: false, default: true,
               comment: "上限開關（limits cart.item_limit_enabled_default）"
  end
end
