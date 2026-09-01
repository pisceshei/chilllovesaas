# frozen_string_literal: true

module Analytics
  # 指標辭典（G6 步 10；19-F1 三要素之定義＋單位；80 §3 紅線逐條落點）。
  #
  # 🔴 三條官方紅線（80 §3；違者＝鐵律 7 誤用）：
  #   ①**AOV＝((gross sales − discounts) / orders)**（官方公式逐字，95 §4）——
  #     分子＝subtotal_cents（不含運費/稅/duties），excluding post-order
  #     adjustments（退款/編輯/換貨），落成立日、退款**不回頭改它**；
  #     ⇒ `AOV × Orders ≠ Total sales` 是**官方語義**，一致性測試不得斷言相等
  #     （19-F1 必測⑤／G25 具名例外）。
  #   ②**total_sales 可以是負數**（撤銷 > 銷售的日子）——不設非負約束。
  #   ③ANY_CLICK 歸因小計>總計白名單（隨歸因線；本包未實作歸因）。
  # 單位：*_cents 語義的存 cents；count 語義的存原值。
  module Metrics
    MONEY = %w[gross_sales discounts returns net_sales shipping_charges taxes
               total_sales aov_numerator].freeze
    COUNT = %w[orders_count units_sold aov_denominator].freeze
    ALL = (MONEY + COUNT).freeze
  end
end
