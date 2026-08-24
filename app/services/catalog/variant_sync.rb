# frozen_string_literal: true

module Catalog
  # 選項樹＋多變體的宣告式同步（第 22 包；63 §B.4/§B.5 的引擎本體）。
  #
  # ①這是什麼：SaveProduct 在「input 帶 options 樹」時的唯一變體寫入路徑。
  #   在**呼叫端的 transaction 內**執行（本檔不開 transaction）。
  # ②兩階段 diff（63 §B.5——本節唯一事故形態的正面防線）：
  #   - 階段 A（投影）：把**既有變體**投影到新選項集合——新增選項補該選項第一值、
  #     被刪選項的座標移除、「無變體 → 有變體」＝隱含變體升級成第一個具名變體
  #     （保留原 id）。
  #   - 階段 B（比對）：input 列有 `id` 以 id 對應（primary match key，
  #     limits `variant_identity_id_wins`）；無 `id` 的列以**投影後**的
  #     option_values_digest 對應；配不上＝新建。既有變體未被任何列 match
  #     ＝刪除（63 §B.4 硬規則 1「未列出的變體視為刪除」，走 Catalog::DeleteVariant）。
  #   🔴 跳過階段 A 直接比 digest ⇒ 舊變體對不上任何新 digest ⇒ 全部 id 被換掉
  #     ＝ledger 斷鏈＋購物車 variant_id 失效＋GMC 判商品消失（63:311-316）。
  # ③title 生成（B3）：具名變體＝座標值依選項 position join " / "，寫入時入庫；
  #   選項值改名同 transaction 連動重算（本 service 全量重寫 title，天然涵蓋）。
  # ④initialQuantities：create-only（帶 id 的列給它＝INVALID）；寫入走
  #   Inventory::Adjust（D43 唯一入口）＋衍生冪等鍵——requires_new 子交易在
  #   外層 rollback 時一併回滾。
  # ⑤跨功能影響：DeleteVariant（刪除分支）、OptionValuesDigest（比對鍵）、
  #   inventory_items（隨新變體 after_create 誕生）、第 23 包 UI（本契約的驗證面）、
  #   前台 drops（第 30 包讀本結構）。事件由 SaveProduct 統一發，本 service 不自發。
  class VariantSync
    Result = Data.define(:user_errors)

    # 初始庫存被 Adjust 拒絕時拋出（🔴 不用 ActiveRecord::Rollback——它會被外層
    # transaction **靜默**吞掉，SaveProduct 會回成功而資料已回滾）。
    class InitialQuantityRejected < StandardError
      attr_reader :user_errors
      def initialize(user_errors) = (@user_errors = user_errors; super("initial quantities rejected"))
    end

    class << self
      # @param shop [Shop]
      # @param product [Product] 已鎖定（FOR UPDATE）的商品
      # @param options_input [Array<Hash>] [{name:, values: [String]}]
      # @param variants_input [Array<Hash>] normalize 後的變體列（含 :id／:option_values／
      #   :initial_quantities／金額欄）
      # @param idempotency_key [String, nil] productSet 的鍵（衍生初始庫存鍵用）
      # @return [Result]
      def call(shop:, product:, options_input:, variants_input:, idempotency_key: nil)
        errors = validate_options!(options_input)
        return Result.new(user_errors: errors) if errors.any?

        errors = validate_variant_rows!(options_input, variants_input)
        return Result.new(user_errors: errors) if errors.any?

        options_by_name = sync_options!(shop, product, options_input)

        existing = product.product_variants
                          .includes(:product_variant_option_values)
                          .order(:position).to_a
        # 階段 A：既有變體投影到新選項集合（記憶體運算，不寫 DB）
        projections = project_existing(existing, options_by_name, options_input)

        # 階段 B：input 列配對
        matched, to_create, errors = match_rows(shop, product, variants_input, existing, projections, options_by_name)
        return Result.new(user_errors: errors) if errors.any?

        total = matched.size + to_create.size
        if total > Limits.fetch(:product, :max_variants)
          return Result.new(user_errors: [ error([ "variants" ],
            I18n.t("errors.product.variant_limit_exceeded"), "VARIANT_LIMIT_EXCEEDED") ])
        end

        # 刪除：未被 match 的既有變體（宣告式；DeleteVariant 自帶 LAST_VARIANT guard）
        (existing - matched.keys).each do |orphaned|
          result = Catalog::DeleteVariant.call(shop:, variant: orphaned)
          return Result.new(user_errors: result.user_errors) unless result.deleted
        end

        apply_matched!(shop, product, matched, projections, options_by_name)
        create_new!(shop, product, to_create, options_by_name, idempotency_key)
        Result.new(user_errors: [])
      rescue ActiveRecord::RecordNotUnique
        # ai_ci 索引的 accent 級撞法（"e"／"é"）穿過 casefold 驗證才會到這——
        # 轉 userErrors，SaveProduct 收到後 raise ⇒ 外層 transaction 回滾。
        Result.new(user_errors: [ error([ "options" ],
          I18n.t("errors.product.option_values_invalid"), "INVALID") ])
      end

      private

      def error(field, message, code) = { field:, message:, code: }

      def validate_options!(options_input)
        errors = []
        if options_input.length > Limits.fetch(:product, :max_options)
          errors << error([ "options" ], I18n.t("errors.product.options_over_limit"), "OPTIONS_OVER_LIMIT")
        end
        names = options_input.map { |o| o[:name].to_s.strip }
        # casefold 去重：DB 唯一索引是 ai_ci（大小寫不敏感），Ruby 純 uniq 擋不住
        # "Red"/"RED" 這種撞法（審查 C7）；accent 級差異由 call 的 RecordNotUnique
        # 安全網收尾。
        if names.any?(&:empty?) || names.map { |n| n.unicode_normalize(:nfkc).downcase }.uniq.length != names.length
          errors << error([ "options" ], I18n.t("errors.product.option_name_invalid"), "INVALID")
        end
        options_input.each_with_index do |option, index|
          values = Array(option[:values]).map { |v| v.to_s.strip }
          if values.empty? || values.any?(&:empty?) ||
             values.map { |v| v.unicode_normalize(:nfkc).downcase }.uniq.length != values.length
            errors << error([ "options", index.to_s, "values" ],
              I18n.t("errors.product.option_values_invalid"), "INVALID")
          end
        end
        errors
      end

      def validate_variant_rows!(options_input, variants_input)
        errors = []
        option_names = options_input.map { |o| o[:name].to_s.strip }
        seen_coords = {}
        variants_input.each_with_index do |row, index|
          coords = Array(row[:option_values])
          if row[:id].present? && row[:initial_quantities].present?
            # create-only（limits initial_quantity_allowed_on_create_only）
            errors << error([ "variants", index.to_s, "initialQuantities" ],
              I18n.t("errors.product.initial_quantity_create_only"), "INVALID")
          end
          given = coords.map { |c| c[:option_name].to_s.strip }
          unless given.sort == option_names.sort
            errors << error([ "variants", index.to_s, "optionValues" ],
              I18n.t("errors.product.variant_coordinates_incomplete"), "INVALID")
            next
          end
          coords.each do |coord|
            option = options_input.find { |o| o[:name].to_s.strip == coord[:option_name].to_s.strip }
            values = Array(option[:values]).map { |v| v.to_s.strip }
            unless values.include?(coord[:value].to_s.strip)
              errors << error([ "variants", index.to_s, "optionValues" ],
                I18n.t("errors.product.variant_value_unknown"), "INVALID")
            end
          end
          key = coords.sort_by { |c| c[:option_name].to_s }.map { |c| "#{c[:option_name]}=#{c[:value]}" }.join("|")
          if seen_coords.key?(key)
            errors << error([ "variants", index.to_s ],
              I18n.t("errors.product.variant_duplicate"), "INVALID")
          end
          seen_coords[key] = true
        end
        errors
      end

      # 選項樹宣告式同步：以 name 對應既有（改 values 走 in-place，值以「值字串」對應
      # ——值改名（Red→Crimson）在宣告式下無法與「刪 Red 加 Crimson」區分，
      # 一律視為刪＋加；引用被刪值的既有變體由階段 B 的刪除分支處置。
      # @return [Hash{String => ProductOption}] name → option（含 reload 後的 values）
      # 🔴 position 兩階段落位（uq(shop, product, position) unique，同 apply_matched!）：
      #    ①刪除先行——被刪選項若仍佔位，重排會撞 1062；②留存者整批挪負區間再落正
      #    ——交換順序（尺寸↔色）與「新建者要的位被留存者佔住」兩種撞法一起消掉；
      #    ③update_all 後必 reload（P19 dirty-tracking 坑：快取舊值會讓 update! 靜默不發）。
      def sync_options!(shop, product, options_input)
        existing = product.product_options.includes(:option_values).to_a
        wanted = options_input.map { |oi| oi[:name].to_s.strip }
        (existing.map(&:name) - wanted).each do |gone|
          option = existing.find { |o| o.name == gone }
          option.option_values.each { |v| ProductVariantOptionValue.where(shop_id: shop.id, option_value_id: v.id).delete_all }
          option.destroy!
        end
        kept = existing.select { |o| wanted.include?(o.name) }
        if kept.any?
          ProductOption.where(shop_id: shop.id, id: kept.map(&:id))
                       .update_all("position = -position - 100000")
          kept.each(&:reload)
        end
        keep = {}
        options_input.each_with_index do |option_input, index|
          name = option_input[:name].to_s.strip
          option = kept.find { |o| o.name == name } ||
                   ProductOption.create!(shop_id: shop.id, product_id: product.id,
                                         name:, position: index + 1)
          option.update!(position: index + 1) if option.position != index + 1
          sync_values!(shop, option, Array(option_input[:values]).map { |v| v.to_s.strip })
          keep[name] = option
        end
        keep
      end

      # 與 sync_options! 同款三步（值層的 unique＝uq(option, position)／uq(option, value)）。
      def sync_values!(shop, option, values)
        existing = option.option_values.to_a
        existing.reject { |v| values.include?(v.value) }.each do |gone|
          ProductVariantOptionValue.where(shop_id: shop.id, option_value_id: gone.id).delete_all
          gone.destroy!
        end
        kept = existing.select { |v| values.include?(v.value) }
        if kept.any?
          OptionValue.where(shop_id: shop.id, id: kept.map(&:id))
                     .update_all("position = -position - 100000")
          kept.each(&:reload)
        end
        values.each_with_index do |value, index|
          row = kept.find { |v| v.value == value } ||
                OptionValue.create!(shop_id: shop.id, product_option_id: option.id,
                                    value:, position: index + 1)
          row.update!(position: index + 1) if row.position != index + 1
        end
        option.association(:option_values).reload
      end

      # 階段 A：每個既有變體 → 投影後座標（option_id → option_value_id）。
      # 新增選項補第一值；被刪選項座標自然消失（座標列已由 sync_options! 清理）。
      def project_existing(existing, options_by_name, options_input)
        first_values = options_input.to_h do |oi|
          name = oi[:name].to_s.strip
          option = options_by_name.fetch(name)
          first = option.option_values.min_by(&:position)
          [ option.id, first ]
        end
        existing.to_h do |variant|
          coords = variant.product_variant_option_values.reject { |pvov| pvov.destroyed? }
                          .to_h { |pvov| [ pvov.product_option_id, pvov.option_value_id ] }
          projected = first_values.to_h do |option_id, first_value|
            [ option_id, coords[option_id] || first_value.id ]
          end
          [ variant, projected ]
        end
      end

      def digest_of(projection)
        # OptionValuesDigest 收 [[option_id, value_id], ...]（canonical 排序在其內部）
        Catalog::OptionValuesDigest.call(projection.to_a)
      end

      # 階段 B。@return [matched(Hash variant→row), to_create(Array), errors]
      def match_rows(shop, product, variants_input, existing, projections, options_by_name)
        matched = {}
        to_create = []
        errors = []
        by_id = existing.index_by(&:id)
        by_digest = projections.to_h { |variant, projection| [ digest_of(projection), variant ] }

        variants_input.each_with_index do |row, index|
          if row[:id].present?
            variant = by_id[row[:id]]
            if variant.nil?
              errors << error([ "variants", index.to_s, "id" ],
                I18n.t("errors.product.variant_not_found"), "NOT_FOUND")
              next
            end
            matched[variant] = row
          else
            digest = digest_of(row_projection(row, options_by_name))
            variant = by_digest[digest]
            if variant && !matched.key?(variant)
              matched[variant] = row
            else
              to_create << row
            end
          end
        end
        [ matched, to_create, errors ]
      end

      def row_projection(row, options_by_name)
        Array(row[:option_values]).to_h do |coord|
          option = options_by_name.fetch(coord[:option_name].to_s.strip)
          value = option.option_values.find { |v| v.value == coord[:value].to_s.strip }
          [ option.id, value.id ]
        end
      end

      def variant_title(projection, options_by_name)
        options_by_name.values.sort_by(&:position).map do |option|
          value_id = projection[option.id]
          option.option_values.find { |v| v.id == value_id }&.value
        end.compact.join(" / ")
      end

      # matched：更新金額欄＋重寫座標為 input 宣告（含投影補位）＋title 重算。
      # 🔴 position 兩階段落位：uq(shop, product, position) 是 unique，逐列 update
      #    交換位置會撞 1062（整合規格 §1.4 媒體同型坑）——先整批挪到負區間再落正。
      def apply_matched!(shop, product, matched, projections, options_by_name)
        if matched.any?
          ProductVariant.where(shop_id: shop.id, id: matched.keys.map(&:id))
                        .update_all("position = -position - 100000")
        end
        matched.each_with_index do |(variant, row), index|
          projection = row[:option_values].present? ? row_projection(row, options_by_name) : projections.fetch(variant)
          rewrite_coordinates!(shop, product, variant, projection)
          variant.reload
          variant.update!(
            position: index + 1,
            title: variant_title(projection, options_by_name),
            price_cents: row.fetch(:price_cents),
            compare_at_price_cents: row[:compare_at_price_cents],
            cost_cents: row[:cost_cents],
            sku: row[:sku],
            barcode: row[:barcode],
            taxable: row.fetch(:taxable, true)
          )
        end
      end

      def rewrite_coordinates!(shop, product, variant, projection)
        ProductVariantOptionValue.where(shop_id: shop.id, product_variant_id: variant.id).delete_all
        projection.each do |option_id, value_id|
          ProductVariantOptionValue.create!(
            shop_id: shop.id, product_id: product.id, product_variant_id: variant.id,
            product_option_id: option_id, option_value_id: value_id)
        end
      end

      def create_new!(shop, product, rows, options_by_name, idempotency_key)
        base_position = product.product_variants.reload.map(&:position).max || 0
        rows.each_with_index do |row, index|
          projection = row_projection(row, options_by_name)
          variant = ProductVariant.new(
            shop_id: shop.id, product_id: product.id,
            title: variant_title(projection, options_by_name),
            position: base_position + index + 1,
            currency: shop.store_currency,
            price_cents: row.fetch(:price_cents),
            compare_at_price_cents: row[:compare_at_price_cents],
            cost_cents: row[:cost_cents],
            sku: row[:sku], barcode: row[:barcode],
            taxable: row.fetch(:taxable, true))
          projection.each do |option_id, value_id|
            variant.product_variant_option_values.build(
              shop_id: shop.id, product_id: product.id,
              product_option_id: option_id, option_value_id: value_id)
          end
          variant.save!
          apply_initial_quantities!(shop, variant, row, idempotency_key)
        end
      end

      # D43：initial quantity 走唯一寫入口（衍生鍵＝productSet 鍵 + 變體 + 地點序）。
      def apply_initial_quantities!(shop, variant, row, idempotency_key)
        quantities = Array(row[:initial_quantities])
        return if quantities.empty?

        item = variant.inventory_item
        changes = quantities.map do |entry|
          { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
            location_id: entry[:location_id].to_s,
            delta: Integer(entry[:quantity]) }
        end
        result = Inventory::Adjust.call(shop:, mode: "adjust", input: {
          name: "available", reason: "received",
          idempotency_key: "#{idempotency_key || SecureRandom.uuid}:init:#{variant.id}",
          changes: })
        raise InitialQuantityRejected, result.user_errors if result.user_errors.any?
      end
    end
  end
end
