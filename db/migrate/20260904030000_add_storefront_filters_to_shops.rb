# frozen_string_literal: true

# E8b：Search & Discovery「Add filter」啟用清單的儲存位（ThemeEngine::Facets.enabled_for）。
# nil ⇒ 新店預設 availability＋price（hoko.vip 實測）；值域 Facets::ALL_FILTERS。設定面未做（91 §3.75b V）。
class AddStorefrontFiltersToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :storefront_filters, :json, null: true
  end
end
