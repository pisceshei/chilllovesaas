# frozen_string_literal: true

# G6 步 8b：customers.locale——通知語言（Edit customer modal 實測欄
# 「This customer will receive notifications in this language.」；
# 對位官方 CustomerInput.locale）。NULL＝店預設語言。
class AddLocaleToCustomers < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:customers, :locale)
      add_column :customers, :locale, :string, limit: 16,
                 comment: "通知語言（BCP-47；NULL＝店預設。Edit customer modal 的 Language 欄）"
    end
  end
end
