# frozen_string_literal: true

# PR-10：storefront 密碼保護（本尊 private mode——chill.deals 對表軸）。
# digest 存 BCrypt（不存明文）；NULL＝未啟用（demo 店保持開放）。
class AddStorefrontPasswordToShops < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:shops, :storefront_password_digest)
      add_column :shops, :storefront_password_digest, :string, limit: 255,
                 comment: "storefront 密碼保護（NULL＝off；PR-10）"
    end
  end
end
