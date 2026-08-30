# frozen_string_literal: true

module Storefront
  # 購物車寫入（specs/15 F1；Ajax 慣例對齊 blueprint 03）。
  #
  # 錯誤契約（真店實測 83 §12.5：售罄 add ⇒ HTTP 422
  # `{"status":422,"message":…,"description":…}`）：本服務拋 CartError，
  # controller 轉同形 JSON。文案繁中（鐵律 10；本尊英文文案不抄——鐵律 9）。
  #
  # 🔴 併發（F1 #5）：add 走 upsert 撞 `(shop_id, cart_id, merge_key_hash)`
  #   唯一索引 ⇒ `quantity = quantity + ?` 收斂；兩分頁同時加購不丟量。
  # 🔴 不在 cart 階段扣庫存（F1 ⚠️坑：訂單成立時才扣）。
  module CartWriter
    module_function

    # @param cart [Cart]
    # @param variant_id [Integer]
    # @param quantity [Integer]
    # @param properties [Hash]
    # @return [CartLineItem] 被加入／合併後的行
    # @raise [CartError] 422：查無變體／售罄／超出行上限
    def add(cart:, variant_id:, quantity: 1, properties: {})
      quantity = Integer(quantity, exception: false) || 0
      raise CartError, "數量必須為正整數。" unless quantity.positive?

      variant = ProductVariant.find_by(shop_id: cart.shop_id, id: variant_id)
      raise CartError.new("找不到此商品變體。", status: 422) if variant.nil?
      raise CartError, "商品『#{line_name(variant)}』已售罄。" unless sellable?(variant)

      per_line_cap = Limits.fetch(:cart, :max_quantity_per_line)
      raise CartError, "單行數量不可超過 #{per_line_cap}。" if quantity > per_line_cap

      enforce_item_limit!(cart:, adding: quantity)
      upsert_line!(cart:, variant:, quantity:, properties: properties || {})
    end

    # @param line_key [String] Ajax `key`（"variant_id:hash"）或行 id 字串
    # @param quantity [Integer] 0＝移除
    def change(cart:, line_key:, quantity:)
      quantity = Integer(quantity, exception: false)
      raise CartError, "數量格式不正確。" if quantity.nil? || quantity.negative?

      line = find_line(cart, line_key)
      raise CartError.new("找不到此購物車行。", status: 404) if line.nil?

      if quantity.zero?
        line.destroy!
      else
        cap = Limits.fetch(:cart, :max_quantity_per_line)
        raise CartError, "單行數量不可超過 #{cap}。" if quantity > cap

        line.update!(quantity:)
      end
      line
    end

    def update_meta(cart:, note: nil, attributes: nil)
      cart.note = note unless note.nil?
      cart.attributes_json = cart.attributes_json.merge(attributes.to_h) unless attributes.nil?
      cart.save!
      cart
    end

    # 官方語義（Ajax 官方句＋83 §3.3 實測）：清行**不清** note／attributes。
    def clear(cart:)
      cart.cart_line_items.delete_all
      cart.touch
      cart
    end

    # ── 內部 ──────────────────────────────────────────────────────────────

    # A2（包 33 後半）：cart_item_limit＝**總件數**上限，商家設定欄（shops 兩欄）。
    # 與 max_quantity_per_line／max_lines（本專案防呆）是不同概念、並存（limits cart 註釋）。
    # 豁免值域（pos/draft_order/b2b/untracked）＝其他通路的事，本端點只有 online store。
    # 只擋 add 不擋 change 減量；change 加量走同一 cap 由 controller 契約自然涵蓋
    # （change 是「改行數」語義，本尊上限文案掛在加入購物車——44:378）。
    def enforce_item_limit!(cart:, adding:)
      shop = Shop.find(cart.shop_id)
      return unless shop.cart_item_limit_enabled

      total = cart.cart_line_items.sum(:quantity) + adding
      cap = shop.cart_item_limit
      raise CartError, "購物車總件數不可超過 #{cap} 件。" if total > cap
    end

    def upsert_line!(cart:, variant:, quantity:, properties:)
      max_lines = Limits.fetch(:cart, :max_lines)
      unit_price_cents = variant.price_cents
      merge_key = CartLineItem.merge_key_for(
        product_variant_id: variant.id, properties:, selling_plan_id: nil,
        unit_price_cents:, parent_id: nil
      )
      existing = cart.cart_line_items.find_by(merge_key_hash: merge_key)
      if existing.nil? && cart.cart_line_items.count >= max_lines
        raise CartError, "購物車行數已達上限 #{max_lines}。"
      end

      now = Time.current
      CartLineItem.upsert(
        {
          shop_id: cart.shop_id, cart_id: cart.id, product_variant_id: variant.id,
          quantity:, properties:, selling_plan_id: nil,
          unit_price_cents:, parent_id: nil, merge_key_hash: merge_key,
          created_at: now, updated_at: now
        },
        # MySQL 的 ON DUPLICATE KEY 作用於任一唯一索引（此表唯一可撞的是
        # uq_cart_line_items_merge_key）；adapter 不支援 :unique_by。
        on_duplicate: Arel.sql("quantity = quantity + VALUES(quantity), updated_at = VALUES(updated_at)")
      )
      cart.touch
      cart.cart_line_items.find_by!(merge_key_hash: merge_key)
    end

    def find_line(cart, line_key)
      key = line_key.to_s
      if key.include?(":")
        variant_id, hash = key.split(":", 2)
        cart.cart_line_items.find_by(product_variant_id: variant_id, merge_key_hash: hash) ||
          cart.cart_line_items.find_by(merge_key_hash: hash)
      else
        cart.cart_line_items.find_by(id: key) ||
          cart.cart_line_items.find_by(product_variant_id: key)
      end
    end

    # 售罄判準與 VariantDrop#available 同軸（未追蹤恆可售；追蹤＝合計>0 ∨ continue）。
    def sellable?(variant)
      item = variant.inventory_item
      return true if item.nil? || !item.tracked
      return true if variant.inventory_policy == "continue"

      item.inventory_levels.sum(:available).positive?
    end

    def line_name(variant)
      title = variant.product.title
      variant.title == "Default Title" ? title : "#{title} - #{variant.title}"
    end
  end
end
