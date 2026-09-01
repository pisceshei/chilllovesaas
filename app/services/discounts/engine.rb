# frozen_string_literal: true

module Discounts
  # 折扣求值引擎（G6 步 9a；17-F2 的**解析半場**）。
  #
  # ①分工（鐵律 7）：Engine 讀 DB（候選/條件/組合裁決）→ 產**正規化純資料清單**；
  #   金額運算（F2.1 同基數/鉗制/分攤）在 Checkouts::Calculator——唯一金額計算點
  #   不變，Engine 不算錢。
  # ②候選：automatic 全撈（effective_status=active）＋輸入 code（單一 code 起步）。
  # ③條件（v1）：時間窗（effective_status）／min_subtotal_cents（🔴 判定基準＝
  #   **原始小計**——官方「order 級門檻看套用 product 折扣後的小計」的完整分層
  #   隨 entitlements 展開，v1 無 product 折扣疊加場景差異，91 §3.54 登記）／
  #   min_quantity／usage_limit 軟檢（硬保證在成單交易，17-F3）。
  # ④組合裁決（17-F2.4）：combines_* **雙向同意**；🔴 shipping 不可疊 shipping
  #   ＝引擎硬規則（不看旗標）；不可共存 ⇒ 買家利益最大（best wins，比折讓金額
  #   ——用近似值：percentage 以 bp×基數估、fixed 以面額）。
  # ⑤code 錯誤語義（17-F4.1）：不存在/過期/不符條件**一律同一句**
  #   「折扣碼無效或不適用」（枚舉防護優先於 UX 精確——刻意與本尊取捨不同）。
  class Engine
    Evaluation = Data.define(:discounts, :code_error)

    class << self
      # @param shop [Shop]
      # @param lines [Array<Hash>] {key:, quantity:, unit_price_cents:}
      # @param code [String, nil] 原始輸入（本函式內正規化）
      # @param customer_key [String, nil] once_per_customer 軟檢用
      # @return [Evaluation] discounts＝Calculator 的 discounts: 清單；code_error＝
      #   nil 或統一文案（碼無效時 discounts 仍含 automatic）
      def evaluate(shop:, lines:, code: nil, customer_key: nil)
        subtotal = lines.sum { |l| l[:quantity] * l[:unit_price_cents] }
        quantity = lines.sum { |l| l[:quantity] }

        candidates = automatic_candidates(shop)
        code_error = nil
        normalized = Discount.normalize_code(code)
        if normalized
          code_discount = code_candidate(shop, normalized)
          if code_discount && usable?(code_discount, subtotal, quantity, customer_key, shop)
            candidates << code_discount
          else
            code_error = "折扣碼無效或不適用"
          end
        end

        eligible = candidates.select { |d| meets_conditions?(d, subtotal, quantity) }
        chosen = resolve_combinations(eligible, subtotal)
        Evaluation.new(discounts: chosen.map { |d| normalize(d, lines) }, code_error:)
      end

      private

      def automatic_candidates(shop)
        Discount.where(shop_id: shop.id, method: "automatic", status: "active")
                .order(:id).limit(Limits.fetch(:discount, :max_active_automatic_per_shop))
                .select { |d| d.effective_status == "active" }
      end

      def code_candidate(shop, normalized)
        Discount.find_by(shop_id: shop.id, method: "code", code: normalized)
      end

      # code 的可用性（比一般條件多：生命週期/用量/每人一次——全歸一句錯誤）。
      def usable?(discount, subtotal, quantity, customer_key, shop)
        return false unless discount.effective_status == "active"
        return false unless meets_conditions?(discount, subtotal, quantity)
        if discount.usage_limit && discount.times_used >= discount.usage_limit
          return false
        end
        if discount.once_per_customer && customer_key.present?
          used = DiscountRedemption.where(shop_id: shop.id, discount_id: discount.id,
                                          customer_key:).exists?
          return false if used
        end

        true
      end

      def meets_conditions?(discount, subtotal, quantity)
        conditions = discount.conditions || {}
        min_subtotal = conditions["min_subtotal_cents"]
        return false if min_subtotal && subtotal < min_subtotal.to_i
        min_quantity = conditions["min_quantity"]
        return false if min_quantity && quantity < min_quantity.to_i

        true
      end

      # 17-F2.4：雙向同意共存；衝突取買家利益最大；shipping 疊 shipping 硬擋。
      def resolve_combinations(eligible, subtotal)
        by_value = eligible.sort_by { |d| -estimated_value(d, subtotal) }
        chosen = []
        by_value.each do |candidate|
          next if candidate.discount_class == "shipping" &&
                  chosen.any? { |d| d.discount_class == "shipping" } # 硬規則，不看旗標
          next unless chosen.all? { |kept| combinable?(kept, candidate) }

          chosen << candidate
        end
        chosen
      end

      # 雙向同意（17-F2.4）：兩張折扣都對「對方的 class」開旗標才共存。
      def combinable?(one, other)
        allows?(one, other.discount_class) && allows?(other, one.discount_class)
      end

      def allows?(discount, other_class)
        case other_class
        when "product" then discount.combines_product
        when "order" then discount.combines_order
        when "shipping" then discount.combines_shipping
        else false
        end
      end

      # best-wins 的估值（近似；同 class 衝突時的排序鍵）。
      def estimated_value(discount, subtotal)
        if discount.value_type == "percentage"
          subtotal * discount.percentage_basis_points / 10_000
        else
          discount.value_cents
        end
      end

      # Calculator 的 discounts: 清單元素（純資料；不含 AR 物件）。
      def normalize(discount, lines)
        entitled = Array(discount.conditions&.dig("entitled_variant_ids")).presence
        entitled_keys = entitled &&
                        lines.select { |l| entitled.include?(l[:variant_id]) }.map { |l| l[:key] }
        {
          id: discount.id, title: discount.title, discount_class: discount.discount_class,
          value_type: discount.value_type,
          basis_points: discount.percentage_basis_points,
          value_cents: discount.value_cents,
          entitled_line_keys: entitled_keys
        }
      end
    end
  end
end
