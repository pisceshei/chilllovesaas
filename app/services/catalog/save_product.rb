# frozen_string_literal: true

module Catalog
  # admin 商品頁 SaveBar 的服務端本體——`productSet` 的 normalize→validate→commit
  # （63 §A.1／§B.4：一次儲存 ＝ 一支宣告式 upsert，單一 transaction 原子寫入）。
  #
  # ## 射程（2026-08-23；更新態於同日第二包加入）
  #
  # 建立態（無 id）＋更新態（帶 id ＋ lockVersion）皆支援；仍限**隱含變體**
  # （無選項 ⇒ variants 恰一筆）。具名選項與多變體（B.5 變體身分保持）屬變體包。
  # 更新態的 handle 變更暫拒（301 基建屬 URL 包）：input.handle 與現值相同＝no-op，
  # 不同＝INVALID——宣告式全樹契約下前端照常送整棵樹，不受影響。
  #
  # ## 錯誤模型
  #
  # 回傳 `Result`（product + user_errors）；**AR 例外在這裡轉譯**，不外洩——
  # graphql_controller 對 `RecordNotUnique` 刻意 re-raise（63 §A.1 ④「不得漏成 500」
  # 的責任在 mutation/service 層）。
  #
  # @see docs/specs/63-product-data-flow.md §A.1／§B.4
  # @see docs/specs/13-spec-products-inventory-media.md §F1／§F2
  class SaveProduct
    Result = Data.define(:product, :user_errors)

    # 更新態 handle 變更的控制流例外（轉譯成 userErrors，不外洩）。
    class HandleChangePending < StandardError; end

    # 富文本白名單（13 §F1:126）：存前 sanitize，前台輸出處再 sanitize 一次（雙保險）。
    # ⚠️ img[src 限自家 CDN] 的 CDN 白名單待媒體包（現階段限 https）；登記於 dev doc Pending。
    ALLOWED_TAGS = %w[p br strong em ul ol li a img].freeze
    ALLOWED_ATTRIBUTES = %w[href src alt].freeze

    class << self
      # 執行一次商品儲存（目前＝建立）。
      #
      # @param shop [Shop] 當前租戶
      # @param input [Hash] GraphQL ProductSetInput 的 to_h（鍵為 snake_case Symbol）
      # @return [Result] product 與 userErrors（互斥：有錯誤時 product 為 nil）
      # @note 副作用：成功時在單一 transaction 內寫入 products／product_variants／
      #   event_outbox 三表。
      def call(shop:, input:)
        errors = []
        reject_unsupported!(input, errors)
        return Result.new(product: nil, user_errors: errors) if errors.any?

        attributes = normalize(shop, input, errors)
        return Result.new(product: nil, user_errors: errors) if errors.any?

        if input[:id].present?
          update(shop, input, attributes)
        else
          commit(shop, attributes)
        end
      end

      private

      # 射程外的輸入直接以 userErrors 拒絕（不靜默忽略欄位——那會讓呼叫端
      # 以為存進去了）。
      def reject_unsupported!(input, errors)
        variants = input[:variants] || []
        return if variants.length == 1

        errors << error(
          [ "variants" ],
          "無選項商品的變體必須恰為一筆（隱含變體）；具名選項與多變體屬後續里程碑。",
          "INVALID"
        )
      end

      def normalize(shop, input, errors)
        title = input[:title].to_s.strip
        errors << error([ "title" ], "標題不能為空白。", "BLANK") if title.empty?
        if title.length > Limits.fetch(:product, :title_max_chars)
          errors << error([ "title" ], "標題長度超過上限。", "TOO_LONG")
        end

        description = sanitize_description(input[:description_html].to_s)
        if description.bytesize > Limits.fetch(:product, :description_max_bytes)
          errors << error([ "descriptionHtml" ], "說明超過大小上限。", "TOO_BIG")
        end

        manual_handle = input[:handle].presence
        if manual_handle && !manual_handle.match?(/\A[a-z0-9-]+\z/)
          errors << error([ "handle" ], "handle 只能包含小寫字母、數字與連字號。", "INVALID")
        elsif manual_handle && Limits.fetch(:handle, :reserved).map(&:to_s).include?(manual_handle)
          # limits handle.reserved（all/new/index）：撞平台路由段（如 /admin/products/new）。
          errors << error([ "handle" ], "此 handle 為系統保留字，請改用其他值。", "INVALID")
        end

        variant = normalize_variant(shop, (input[:variants] || []).first || {}, errors)
        organization = normalize_organization(input, errors)

        {
          title:,
          description_html: description,
          # 建立未帶 status ⇒ draft（90-blueprint/01 §B.1，61 實測；91 §3.7 登記）；
          # 更新未帶 ⇒ nil（update 分支解讀為「保持現值」——宣告式契約下前端會送，
          # 缺席只發生在 API 直呼叫，保持現值比靜默改 draft 安全）。
          status: input[:status] && input[:status].to_s.downcase,
          handle: manual_handle,
          organization:,
          variant:
        }
      end

      # 組織分類＋SEO（91 §11–12）。回傳 hash **只含有提供的鍵**：
      # 缺席（nil）＝更新態保持現值（與 status 同語義）；空字串／空陣列＝清除。
      # 上限全部引 limits（鐵律 6）；SEO 的 160 是 SERP 建議值不是上限，只擋 320。
      def normalize_organization(input, errors)
        organization = {}

        unless input[:vendor].nil?
          vendor = input[:vendor].to_s.strip
          if vendor.length > Limits.fetch(:product, :vendor_max_chars)
            errors << error([ "vendor" ], "廠商長度超過上限。", "TOO_LONG")
          end
          organization[:vendor] = vendor.presence
        end

        unless input[:product_type].nil?
          product_type = input[:product_type].to_s.strip
          if product_type.length > Limits.fetch(:product, :product_type_max_chars)
            errors << error([ "productType" ], "產品類型長度超過上限。", "TOO_LONG")
          end
          organization[:product_type] = product_type.presence
        end

        unless input[:tags].nil?
          # 宣告式全量覆寫：strip → 去空 → 去重（保序）。單標籤與總數上限各自回錯。
          tags = input[:tags].map { |tag| tag.to_s.strip }.reject(&:empty?).uniq
          if tags.length > Limits.fetch(:product, :max_tags)
            errors << error([ "tags" ], "標籤數量超過上限。", "TOO_LONG")
          end
          if tags.any? { |tag| tag.length > Limits.fetch(:product, :tag_max_chars) }
            errors << error([ "tags" ], "單一標籤長度超過上限。", "TOO_LONG")
          end
          organization[:tags] = tags
        end

        unless input[:seo].nil?
          seo = input[:seo]
          unless seo[:title].nil?
            seo_title = seo[:title].to_s.strip
            if seo_title.length > Limits.fetch(:content, :seo_title_max_chars)
              errors << error([ "seo", "title" ], "SEO 標題長度超過上限。", "TOO_LONG")
            end
            organization[:seo_title] = seo_title.presence
          end
          unless seo[:description].nil?
            seo_description = seo[:description].to_s.strip
            if seo_description.length > Limits.fetch(:content, :seo_meta_description_max_chars)
              errors << error([ "seo", "description" ], "Meta 描述長度超過上限。", "TOO_LONG")
            end
            organization[:seo_description] = seo_description.presence
          end
        end

        organization
      end

      def normalize_variant(shop, variant_input, errors)
        price_cents = parse_money(variant_input[:price], shop, "price", errors, required: true)
        compare_cents = parse_money(variant_input[:compare_at_price], shop, "compareAtPrice", errors, required: false)
        cost_cents = parse_money(variant_input[:cost], shop, "cost", errors, required: false)

        {
          price_cents:,
          compare_at_price_cents: compare_cents,
          cost_cents:,
          sku: variant_input[:sku].presence,
          barcode: variant_input[:barcode].presence,
          taxable: variant_input.fetch(:taxable, true)
        }
      end

      # 65 §B X12：admin GraphQL 入向金額＝R4 十進位字串 → R1 integer cents。
      # 走 `Money::Decimal`（嚴格兩位小數 regex）→ `to_storage`；不合格式一律 userError，
      # **不得 round、不得默默補位**。負數在型別層合法（65 §A.7），價格域再擋。
      def parse_money(raw, shop, field, errors, required:)
        if raw.blank?
          errors << error([ "variants", "0", field ], "價格欄位必填。", "BLANK") if required
          return nil
        end

        decimal = Money::Decimal.from_string(raw.to_s, shop.store_currency)
        storage = decimal.to_storage
        if storage.cents.negative?
          errors << error([ "variants", "0", field ], "金額不得為負。", "GREATER_THAN_OR_EQUAL_TO")
          return nil
        end
        storage.cents
      rescue ArgumentError, Money::ExcessPrecision
        # ExcessPrecision 也要接：regex 錨點修正前「尾隨換行」的輸入曾能穿過
        # from_string 而在 to_storage 才炸（65 §B X12 的處置是 userErrors，不是 500）。
        # 錨點修好後理論上不可達，仍保留——兩道防線各自獨立成立。
        errors << error(
          [ "variants", "0", field ],
          "請輸入有效金額字串（主單位、恆兩位小數、不含符號與千分位）。",
          "INVALID"
        )
        nil
      end

      def sanitize_description(html)
        return "" if html.blank?

        scrubber = Rails::HTML::PermitScrubber.new
        scrubber.tags = ALLOWED_TAGS
        scrubber.attributes = ALLOWED_ATTRIBUTES
        fragment = Loofah.fragment(html)
        fragment.scrub!(scrubber)
        strip_disallowed_urls(fragment)
        fragment.to_s
      end

      # a[href] 與 img[src] 只留 http(s)（13 §F1:126）；javascript: 等一律拔屬性。
      def strip_disallowed_urls(fragment)
        fragment.css("a[href]").each do |node|
          node.remove_attribute("href") unless node["href"].to_s.match?(%r{\Ahttps?://}i)
        end
        fragment.css("img[src]").each do |node|
          node.remove_attribute("src") unless node["src"].to_s.match?(%r{\Ahttps://}i)
        end
      end

      # 生成 handle 的併發衝突重試上限：check-then-insert 的窗口內兩請求可同名，
      # 輸家重生成（拿到下一個尾碼）再試；連輸表示異常熱點，放棄並回報。
      GENERATED_HANDLE_ATTEMPTS = 3

      def commit(shop, attributes)
        manual = attributes[:handle].present?
        attempts = 0
        begin
          product = nil
          ActsAsTenant.with_tenant(shop) do
            ActiveRecord::Base.transaction do
              product = create_product!(shop, attributes)
              create_implicit_variant!(shop, product, attributes.fetch(:variant))
              enqueue_event!(shop, product, "products/create")
            end
          end
          Result.new(product:, user_errors: [])
        rescue ActiveRecord::RecordNotUnique
          # handle 唯一索引兜底（63 §A.1 ④：轉譯成 userErrors，不得漏成 500）。
          # 🔴 手填與生成分流（對抗審查 confirmed #9）：手填衝突＝reject
          # （collision_strategy_explicit）；**生成**衝突＝自動改尾碼
          # （collision_strategy_generated）——併發撞索引的輸家重生成再試，
          # 不得把 reject 誤用在生成路徑上。
          if manual
            Result.new(product: nil,
                       user_errors: [ error([ "handle" ], "handle 已被使用。", "HANDLE_TAKEN") ])
          elsif (attempts += 1) < GENERATED_HANDLE_ATTEMPTS
            retry
          else
            Result.new(product: nil,
                       user_errors: [ error([ "handle" ], "handle 產生時持續發生衝突，請重試。",
                                            "CREATION_FAILED") ])
          end
        rescue ActiveRecord::RecordInvalid => invalid
          Result.new(product: nil, user_errors: translate_record_invalid(invalid))
        end
      end

      def create_product!(shop, attributes)
        handle = attributes[:handle] || unique_generated_handle(shop, attributes[:title])

        Product.create!(
          title: attributes[:title],
          description_html: attributes[:description_html],
          status: attributes[:status] || "draft",
          handle: handle,
          **attributes.fetch(:organization)
        )
      end

      # ── 更新態（63 §B.4：同一支 mutation，差別只在有無 id；lockVersion 涵蓋全樹）──

      GID_PATTERN = %r{\Agid://chilllove/Product/(\d+)\z}

      def update(shop, input, attributes)
        match = GID_PATTERN.match(input[:id].to_s)
        unless match
          return Result.new(product: nil,
                            user_errors: [ error([ "id" ], "無效的商品 GID。", "INVALID") ])
        end
        if input[:lock_version].nil?
          # 🔴 更新必帶 lockVersion：缺它「最後寫入者贏」會靜默蓋掉並發修改，
          #    正是 63 §A.4 樂觀鎖要擋的事故。
          return Result.new(product: nil,
                            user_errors: [ error([ "lockVersion" ], "更新商品必須提供 lockVersion。", "BLANK") ])
        end

        product = nil
        ActsAsTenant.with_tenant(shop) do
          ActiveRecord::Base.transaction do
            # FOR UPDATE 序列化並發儲存；鎖住後比對版本，輸家吃 STALE_OBJECT。
            product = Product.lock.find_by(id: match[1])
            raise ActiveRecord::RecordNotFound if product.nil?

            if product.lock_version != input[:lock_version]
              raise ActiveRecord::StaleObjectError.new(product, "update")
            end

            if attributes[:handle] && attributes[:handle] != product.handle
              # handle 變更需 301（62 §F.3）；url_redirects 基建屬 URL 包 ⇒ 暫拒，
              # 相同值視為 no-op（前端送全樹不受影響）。登記於 dev doc §6。
              raise HandleChangePending
            end

            product.assign_attributes(
              title: attributes[:title],
              description_html: attributes[:description_html],
              status: attributes[:status] || product.status,
              # 只覆寫有提供的組織／SEO 鍵（缺席＝保持現值，normalize_organization 註釋）。
              **attributes.fetch(:organization)
            )
            # 全樹鎖：即使只有變體欄位變動也要 bump 版本 ⇒ 恆 touch updated_at。
            product.updated_at = Time.current
            product.save!

            update_implicit_variant!(product, attributes.fetch(:variant))
            enqueue_event!(shop, product, "products/update")
          end
        end
        Result.new(product: product.reload, user_errors: [])
      rescue ActiveRecord::RecordNotFound
        Result.new(product: nil,
                   user_errors: [ error([ "id" ], "找不到商品。", "NOT_FOUND") ])
      rescue ActiveRecord::StaleObjectError
        Result.new(product: nil,
                   user_errors: [ error(nil, "商品已被其他人修改，請重新載入後再儲存。", "STALE_OBJECT") ])
      rescue HandleChangePending
        Result.new(product: nil,
                   user_errors: [ error([ "handle" ], "handle 變更需要 301 轉址基建（URL 里程碑），暫不開放。", "INVALID") ])
      rescue ActiveRecord::RecordInvalid => invalid
        Result.new(product: nil, user_errors: translate_record_invalid(invalid))
      end

      # 宣告式覆寫那筆隱含變體（無選項 ⇒ 恰一筆，B1-2 不變量）。
      def update_implicit_variant!(product, variant_attributes)
        variant = product.product_variants.order(:position).first
        variant.update!(
          price_cents: variant_attributes.fetch(:price_cents),
          compare_at_price_cents: variant_attributes[:compare_at_price_cents],
          cost_cents: variant_attributes[:cost_cents],
          sku: variant_attributes[:sku],
          barcode: variant_attributes[:barcode],
          taxable: variant_attributes.fetch(:taxable)
        )
      end

      # 隱含變體（61 §1.1：商品恆有 ≥1 變體；無選項＝Default Title 那一筆）。
      # DB title 直接存 `catalog_flow.default_variant_liquid_title` 的值——Liquid 硬相容
      # 契約與 DB 存值同源（2026-08-23 裁定，缺口「隱含變體 DB title 存值未明文」以此結案）。
      def create_implicit_variant!(shop, product, variant_attributes)
        product.product_variants.create!(
          title: Limits.fetch(:catalog_flow, :default_variant_liquid_title),
          position: 1,
          currency: shop.store_currency,
          price_cents: variant_attributes.fetch(:price_cents),
          compare_at_price_cents: variant_attributes[:compare_at_price_cents],
          cost_cents: variant_attributes[:cost_cents],
          sku: variant_attributes[:sku],
          barcode: variant_attributes[:barcode],
          taxable: variant_attributes.fetch(:taxable)
        )
      end

      def enqueue_event!(shop, product, topic)
        EventOutbox.create!(
          event_id: SecureRandom.uuid,
          topic: topic,
          aggregate_type: "Product",
          aggregate_id: product.id,
          payload: { product_id: product.id, handle: product.handle, status: product.status },
          available_at: Time.current,
          status: "pending"
        )
      end

      # 生成衝突 ⇒ 自 -1 起算尾碼（`collision_strategy_generated: numeric_suffix_from_1`；
      # 本尊實測 potion → potion-1）。手填衝突**不走這裡**——那是 reject（HANDLE_TAKEN）。
      def unique_generated_handle(shop, title)
        result = HandleGenerator.call(title, resource: "product")
        if result.flagged?
          # `flag_when_letters_dropped`：有字母被丟棄一律標記、不得靜默。
          # ⚠️ 落庫欄位待 SEO health 包（surface_auto_token_ratio_in_seo_health 的
          #    消費端），先以結構化日誌承載，登記於 dev doc §5。
          Rails.logger.info(
            "[handle] letters_dropped shop_id=#{shop.id} handle=#{result.handle.inspect} title=#{title.inspect}"
          )
        end

        base = result.handle
        return base unless handle_taken?(shop, base)

        (1..).each do |suffix|
          candidate = "#{base}-#{suffix}"
          return candidate unless handle_taken?(shop, candidate)
        end
      end

      def handle_taken?(shop, handle)
        # 保留字視同已占用：生成出 "new" 這類值時自動走尾碼（new-1），
        # 不讓商品 handle 撞平台路由段。
        return true if Limits.fetch(:handle, :reserved).map(&:to_s).include?(handle)

        Product.where(shop_id: shop.id, handle:).exists?
      end

      def translate_record_invalid(invalid)
        invalid.record.errors.map do |model_error|
          code = case model_error.type
          when :blank then "BLANK"
          when :taken
                   # 手填 handle 衝突走專屬碼（`collision_strategy_explicit: reject`）。
                   model_error.attribute == :handle ? "HANDLE_TAKEN" : "TAKEN"
          when :too_long then "TOO_LONG"
          when :inclusion then "INCLUSION"
          else "INVALID"
          end
          error([ model_error.attribute.to_s ], model_error.full_message, code)
        end
      end

      def error(path_segments, message, code)
        { field: UserErrors::Path.build(*path_segments), message:, code: }
      end
    end
  end
end
