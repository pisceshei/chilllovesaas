# frozen_string_literal: true

module Catalog
  # 變體刪除的唯一路徑（第 20 包／整合規格 §1.1＋裁定 B1 方案②）。
  #
  # ①這是什麼：硬刪一個變體，同 transaction 處理三條外鍵與稽核帳保留。
  #   13 §F1-36：「商品與變體一律允許硬刪，不論是否被 line_items 引用」——
  #   訂單靠快照欄（title/variant_title/sku/unit_price_cents）獨立成立。
  # ②三條 FK 的處置（B1）：
  #   - line_items.product_variant_id → 單欄置 NULL（欄本來可空＝弱引用；
  #     🔴 不用 MySQL ON DELETE SET NULL——複合 FK 含 NOT NULL 的 shop_id，
  #     SET NULL 會全欄置空 ⇒ ERROR 1830，排程 §2.1② 實測）。
  #   - media.product_variant_id → 置 NULL（變體圖退回商品媒體池）。
  #   - inventory_items → **保留列**：product_variant_id 置 NULL＋variant_deleted_at
  #     蓋章；levels 與 ledger（inventory_adjustments）原樣不動——ledger 是
  #     append-only 稽核帳，刪了對帳重放（13 §F5-3）就永遠對不上。
  # ③guard：商品恆有 ≥1 變體（limits catalog_flow.product_min_variants）——
  #   刪到最後一筆回 LAST_VARIANT_REQUIRED userError，不是例外。
  # ④跨功能影響：第 22 包宣告式 diff 的「未列出視為刪除」分支呼叫本路徑；
  #   product_variant_option_values 同 transaction 刪除；事件由呼叫端
  #   （SaveProduct 的 products/update）統一發，本 service 不自發。
  class DeleteVariant
    Result = Data.define(:deleted, :user_errors)

    class << self
      # @param shop [Shop]
      # @param variant [ProductVariant] 已鎖定歸屬本店的變體
      # @return [Result]
      def call(shop:, variant:, now: Time.current)
        remaining = ProductVariant.where(shop_id: shop.id, product_id: variant.product_id).count
        if remaining <= Limits.fetch(:catalog_flow, :product_min_variants)
          return Result.new(deleted: false, user_errors: [ {
            field: [ "variants" ],
            message: I18n.t("errors.product.last_variant_required"),
            code: "LAST_VARIANT_REQUIRED"
          } ])
        end

        ActiveRecord::Base.transaction do
          # line_items／media 目前是零 model 的骨架表（建 model 屬 M3／包 25 射程）
          # ⇒ 用 sanitized SQL 置 NULL，不越界建薄 model（17.2）。
          nullify!("line_items", shop, variant)
          nullify!("media", shop, variant)
          ProductVariantOptionValue.where(shop_id: shop.id, product_variant_id: variant.id)
                                   .delete_all
          # 🔴 順序是契約：先把 item 斷開（置 NULL），之後 variant.destroy! 的
          #    `has_one :inventory_item, dependent: :destroy` 查無關聯 ⇒ 不觸發連鎖刪
          #    ——item／levels／ledger 因此保留（B1）。順序反了＝item 被連鎖 destroy、
          #    levels 的 RESTRICT FK 直接炸。spec 以「ledger 列數不減」釘住。
          InventoryItem.where(shop_id: shop.id, product_variant_id: variant.id)
                       .update_all(product_variant_id: nil, variant_deleted_at: now)
          variant.destroy!
          # 第 3 包 cache stamp：變體集合變了。
          Catalog::CacheStamps.bump_variants!(shop.id, variant.product_id)
        end
        Result.new(deleted: true, user_errors: [])
      end

      private

      def nullify!(table, shop, variant)
        ActiveRecord::Base.connection.exec_update(
          ActiveRecord::Base.sanitize_sql(
            [ "UPDATE #{table} SET product_variant_id = NULL WHERE shop_id = ? AND product_variant_id = ?",
              shop.id, variant.id ]
          )
        )
      end
    end
  end
end
