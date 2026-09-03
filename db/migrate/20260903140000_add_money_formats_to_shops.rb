# frozen_string_literal: true

# D81（2026-09-03 使用者裁定「貨幣顯示格式跟隨 shopify 本尊」）：店級 `money_format`／`money_with_currency_format`。
#
# 本尊為店級設定（Settings › General › Store defaults › Change currency formatting；官方 help
# "currency-formatting" 頁列八個佔位符，`docs/dev/external-facts.md` §G15 逐字）。引擎的 money 過濾器族與
# `shop.money_format` 全部改讀這兩欄；`{ "HKD" => "HK$" }` 三處符號表退場（鐵律 10 的 `HK$1,480` 只是範例）。
#
# 回填規則＝`Shop::MoneyFormatDefaults`（同包）：HKD 依真店 hoko.vip 實測（`window.money_format = "${{amount}}"`、
# 購物車抽屜總額 `HK$0.00 HKD`）；其餘幣別為通用形並登記 V（本尊各幣別預設表官方未逐字公開）。
# 🔴 SQL 回填只列舉 HKD 與官方「預設 amount_no_decimals」清單，與 Ruby 表同源（spec 以雙向集合核對）。
class AddMoneyFormatsToShops < ActiveRecord::Migration[8.1]
  NO_DECIMALS = %w[BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX UYI VND VUV XAF XOF XPF].freeze

  def up
    # MySQL DDL 非交易：逐欄守衛，讓中途失敗後可重跑。
    unless column_exists?(:shops, :money_format)
      add_column :shops, :money_format, :string, limit: 255, null: false, default: "{{amount}}",
                 comment: "店級金額格式（HTML without currency；官方八佔位符；D81）"
    end
    unless column_exists?(:shops, :money_with_currency_format)
      add_column :shops, :money_with_currency_format, :string, limit: 255, null: false, default: "{{amount}}",
                 comment: "店級含幣別金額格式（HTML with currency；D81）"
    end

    codes = NO_DECIMALS.map { |c| "'#{c}'" }.join(", ")
    # 回填只寫本次新增的兩欄（strong_migrations 看不進 execute ⇒ safety_assured）。
    safety_assured { execute(<<~SQL) }
      UPDATE shops SET
        money_format = CASE
          WHEN store_currency = 'HKD' THEN '${{amount}}'
          WHEN store_currency IN (#{codes}) THEN CONCAT(store_currency, ' {{amount_no_decimals}}')
          ELSE CONCAT(store_currency, ' {{amount}}') END,
        money_with_currency_format = CASE
          WHEN store_currency = 'HKD' THEN 'HK${{amount}} HKD'
          WHEN store_currency IN (#{codes}) THEN CONCAT('{{amount_no_decimals}} ', store_currency)
          ELSE CONCAT('{{amount}} ', store_currency) END
    SQL
  end

  def down
    remove_column :shops, :money_with_currency_format
    remove_column :shops, :money_format
  end
end
