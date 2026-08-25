# frozen_string_literal: true

module Catalog
  # admin 商品頁 SaveBar 的服務端本體——`productSet` 的 normalize→validate→commit
  # （63 §A.1／§B.4：一次儲存 ＝ 一支宣告式 upsert，單一 transaction 原子寫入）。
  #
  # ## 射程（2026-08-23；更新態於同日第二包加入）
  #
  # 建立態（無 id）＋更新態（帶 id ＋ lockVersion）皆支援；仍限**隱含變體**
  # （無選項 ⇒ variants 恰一筆）。具名選項與多變體（B.5 變體身分保持）屬變體包。
  # 更新態的 handle **可改**（第 6 包；62 §F.3）：與現值相同＝no-op，
  # 不同＝改名並在**同一 transaction** 落 301（見 `Catalog::HandleChange`）。
  # 舊 handle 永不回收——新資源不得佔用任何既有 redirect 的 from_path。
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

    # 第 22 包：VariantSync 的 userErrors 載體（含 InitialQuantityRejected 轉包）。
    class VariantRejected < StandardError
      attr_reader :user_errors
      def initialize(user_errors) = (@user_errors = user_errors; super("variants rejected"))
    end

    # 譯文驗證失敗 ⇒ 整棵樹回滾（B.4 全樹語義：不得留下「base 存了、譯文沒存」的半套）。
    class TranslationRejected < StandardError
      # @return [Array<Hash>] userErrors
      attr_reader :user_errors

      def initialize(user_errors)
        @user_errors = user_errors
        super("translations rejected")
      end
    end

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

      # ML-3：系列的說明走同一套白名單 sanitize（公開；實作仍在 private 的 sanitize_description）。
      #
      # @param html [String]
      # @return [String]
      def sanitize_description_for(html)
        sanitize_description(html)
      end

      private

      # 射程外的輸入直接以 userErrors 拒絕（不靜默忽略欄位——那會讓呼叫端
      # 以為存進去了）。
      # 第 22 包解除單筆限制：input 帶 options 樹 ⇒ 走 VariantSync 多變體路；
      # 無 options ⇒ 維持「無選項商品恰一筆隱含變體」的原判準（B1-2 不變量）。
      def reject_unsupported!(input, errors)
        return if input[:options].present?

        variants = input[:variants] || []
        return if variants.length == 1

        errors << error(
          [ "variants" ],
          I18n.t("errors.product.variants_single_only"),
          "INVALID"
        )
      end

      def normalize(shop, input, errors)
        title = input[:title].to_s.strip
        errors << error([ "title" ], I18n.t("errors.product.title_blank"), "BLANK") if title.empty?
        if title.length > Limits.fetch(:product, :title_max_chars)
          errors << error([ "title" ], I18n.t("errors.product.title_too_long"), "TOO_LONG")
        end

        # 🔴 缺席／顯式 null＝**保持現值**（與 status／vendor／tags／seo 同語義）；
        #    空字串＝清除。第 29 包審查 V29-D1：變體子頁只送 title/options/variants，
        #    舊語義（`input[:description_html].to_s` → ""）讓它每存一次就把商品說明
        #    整段抹掉，userErrors 為空、toast 顯示「已儲存」，使用者完全看不到。
        #    連帶 `save_translations!` 會以清空後的 body_html 重算 digest ⇒ 全語言譯文被標過期。
        #    🔴 判準是 `.nil?` 不是 `.blank?`——後者會把「顯式清空」也吃掉。
        description = nil
        unless input[:description_html].nil?
          description = sanitize_description(input[:description_html].to_s)
          if description.bytesize > Limits.fetch(:product, :description_max_bytes)
            errors << error([ "descriptionHtml" ], I18n.t("errors.product.description_too_big"), "TOO_BIG")
          end
        end

        manual_handle = input[:handle].presence
        if manual_handle && !manual_handle.match?(/\A[a-z0-9-]+\z/)
          errors << error([ "handle" ], I18n.t("errors.product.handle_invalid"), "INVALID")
        elsif manual_handle && manual_handle.length > Limits.fetch(:handle, :max_chars)
          # 上限只在 HandleGenerator 截斷過，手填路徑原本無擋（審查 P6-5）。
          errors << error([ "handle" ], I18n.t("errors.product.handle_too_long"), "TOO_LONG")
        elsif manual_handle && Limits.fetch(:handle, :reserved).map(&:to_s).include?(manual_handle)
          # limits handle.reserved（all/new/index）：撞平台路由段（如 /admin/products/new）。
          errors << error([ "handle" ], I18n.t("errors.product.handle_reserved"), "INVALID")
        elsif manual_handle && Catalog::HandleChange.path_reserved?(
          shop, Catalog::HandleChange.path_for(:product, manual_handle))
          # 🔴 舊 handle 永不回收（62 §F.3）：這個網址已是某次改名的轉向來源，
          #    讓新商品佔走它＝既有 301 把新商品的頁面轉去別處。
          #    送**自己現有的 handle**（更新態回聲）不會命中——不變量保證自己的
          #    現任 handle 不可能是 from_path（指派當下就被本檢查擋掉了）。
          errors << error([ "handle" ], I18n.t("errors.product.handle_redirected"), "HANDLE_TAKEN")
        end

        if input[:options].present?
          options_input = input[:options].map { |o| { name: o[:name], values: o[:values] } }
          variants_input = (input[:variants] || []).each_with_index.map do |row, index|
            normalize_variant(shop, row, errors, index:).merge(
              id: parse_variant_gid(row[:id], index, errors),
              option_values: row[:option_values]&.map { |c| { option_name: c[:option_name], value: c[:value] } },
              initial_quantities: row[:initial_quantities]&.map { |q| { location_id: parse_location_gid(q[:location_id], index, errors), quantity: q[:quantity] } }
            )
          end
          variant = nil
        else
          options_input = nil
          variants_input = nil
          variant = normalize_variant(shop, (input[:variants] || []).first || {}, errors)
        end
        organization = normalize_organization(input, errors)
        # 譯文原樣帶下去（驗證在 Translations::Upsert，與 base 寫入同 tx）。
        translations = input[:translations]

        {
          title:,
          description_html: description,
          # 建立未帶 status ⇒ draft（90-blueprint/01 §B.1，61 實測；91 §3.7 登記）；
          # 更新未帶 ⇒ nil（update 分支解讀為「保持現值」——宣告式契約下前端會送，
          # 缺席只發生在 API 直呼叫，保持現值比靜默改 draft 安全）。
          status: input[:status] && input[:status].to_s.downcase,
          handle: manual_handle,
          organization:,
          translations:,
          variant:,
          options_input:,
          variants_input:,
          idempotency_key: input[:idempotency_key]
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
            errors << error([ "vendor" ], I18n.t("errors.product.vendor_too_long"), "TOO_LONG")
          end
          organization[:vendor] = vendor.presence
        end

        unless input[:product_type].nil?
          product_type = input[:product_type].to_s.strip
          if product_type.length > Limits.fetch(:product, :product_type_max_chars)
            errors << error([ "productType" ], I18n.t("errors.product.product_type_too_long"), "TOO_LONG")
          end
          organization[:product_type] = product_type.presence
        end

        unless input[:tags].nil?
          # 宣告式全量覆寫：strip → 去空 → 去重（保序）。單標籤與總數上限各自回錯。
          tags = input[:tags].map { |tag| tag.to_s.strip }.reject(&:empty?).uniq
          if tags.length > Limits.fetch(:product, :max_tags)
            errors << error([ "tags" ], I18n.t("errors.product.tags_too_many"), "TOO_LONG")
          end
          if tags.any? { |tag| tag.length > Limits.fetch(:product, :tag_max_chars) }
            errors << error([ "tags" ], I18n.t("errors.product.tag_too_long"), "TOO_LONG")
          end
          organization[:tags] = tags
        end

        unless input[:seo].nil?
          seo = input[:seo]
          unless seo[:title].nil?
            seo_title = seo[:title].to_s.strip
            if seo_title.length > Limits.fetch(:content, :seo_title_max_chars)
              errors << error([ "seo", "title" ], I18n.t("errors.product.seo_title_too_long"), "TOO_LONG")
            end
            organization[:seo_title] = seo_title.presence
          end
          unless seo[:description].nil?
            seo_description = seo[:description].to_s.strip
            if seo_description.length > Limits.fetch(:content, :seo_meta_description_max_chars)
              errors << error([ "seo", "description" ], I18n.t("errors.product.seo_description_too_long"), "TOO_LONG")
            end
            organization[:seo_description] = seo_description.presence
          end
        end

        organization
      end

      def normalize_variant(shop, variant_input, errors, index: 0)
        price_cents = parse_money(variant_input[:price], shop, "price", errors, required: true, index:)
        compare_cents = parse_money(variant_input[:compare_at_price], shop, "compareAtPrice", errors, required: false, index:)
        cost_cents = parse_money(variant_input[:cost], shop, "cost", errors, required: false, index:)

        {
          price_cents:,
          compare_at_price_cents: compare_cents,
          cost_cents:,
          sku: variant_input[:sku].presence,
          barcode: variant_input[:barcode].presence,
          # 🔴 `fetch(key, default)` 擋不住**顯式 null**：GraphQL 的 `Boolean` 可為 null，
          #    graphql-ruby 只要 key 存在就把 nil 寫進 `to_h` ⇒ `fetch` 的 default 不生效
          #    ⇒ nil 一路撞 `null: false` 欄位，噴 `ActiveRecord::NotNullViolation`。
          #    那是 `StatementInvalid` 的子類，本服務的 rescue 清單接不到，最後由
          #    graphql_controller 轉成 top-level `INTERNAL` ⇒ **違反鐵律 4①**
          #    （業務輸入不得漏成 500）。所以兩個布林都要顯式 nil 判斷。
          #    第 29 包審查 P29-BE-W1／R-2；`taxable` 是同一個 hash literal 的隔壁一行，
          #    同 producer 同狀態矩陣，依鐵律 17.2 一併封閉。
          taxable: boolean_or(variant_input, :taxable, true),
          # 第 29 包：運送兩欄。`weight_grams` 欄是 `null: false, default: 0`
          # ⇒ 沒送就給 0（不是 nil，否則 update! 撞 not-null）。
          weight_grams: normalize_weight(variant_input, errors, index:),
          requires_shipping: boolean_or(variant_input, :requires_shipping, true)
        }
      end

      # 缺席**與**顯式 null 都回落預設（見 normalize_variant 的紅字）。
      def boolean_or(variant_input, key, fallback)
        value = variant_input[key]
        value.nil? ? fallback : value
      end

      # 重量是非負整數公克。負數在 MySQL signed int 上完全合法 ⇒ DB 擋不住；
      # ProductVariant 另有 model validation 作第二道（insert_all 以外的路徑）。
      # 🔴 這裡就要回 userError，否則負重量靜默落庫、讀取面再原樣回出。
      # 上限不設：官方值未取得（鐵律 19），要設須先依鐵律 6 在 limits.yml 立鍵。
      def normalize_weight(variant_input, errors, index: 0)
        raw = variant_input[:weight_grams]
        return 0 if raw.nil?

        grams = raw.to_i
        if grams.negative?
          errors << error(
            [ "variants", index.to_s, "weightGrams" ],
            I18n.t("errors.product.weight_negative"), "INVALID"
          )
        end
        grams
      end

      # 65 §B X12：admin GraphQL 入向金額＝R4 十進位字串 → R1 integer cents。
      # 走 `Money::Decimal`（嚴格兩位小數 regex）→ `to_storage`；不合格式一律 userError，
      # **不得 round、不得默默補位**。負數在型別層合法（65 §A.7），價格域再擋。
      def parse_money(raw, shop, field, errors, required:, index: 0)
        if raw.blank?
          errors << error([ "variants", index.to_s, field ], I18n.t("errors.product.price_required"), "BLANK") if required
          return nil
        end

        decimal = Money::Decimal.from_string(raw.to_s, shop.store_currency)
        storage = decimal.to_storage
        if storage.cents.negative?
          errors << error([ "variants", index.to_s, field ], I18n.t("errors.product.amount_negative"), "GREATER_THAN_OR_EQUAL_TO")
          return nil
        end
        storage.cents
      rescue ArgumentError, Money::ExcessPrecision
        # ExcessPrecision 也要接：regex 錨點修正前「尾隨換行」的輸入曾能穿過
        # from_string 而在 to_storage 才炸（65 §B X12 的處置是 userErrors，不是 500）。
        # 錨點修好後理論上不可達，仍保留——兩道防線各自獨立成立。
        errors << error(
          [ "variants", index.to_s, field ],
          I18n.t("errors.product.amount_invalid"),
          "INVALID"
        )
        nil
      end

      VARIANT_GID = %r{\Agid://chilllove/ProductVariant/(\d+)\z}
      LOCATION_GID = %r{\Agid://chilllove/Location/(\d+)\z}

      def parse_variant_gid(raw, index, errors)
        return nil if raw.blank?

        match = VARIANT_GID.match(raw.to_s)
        errors << error([ "variants", index.to_s, "id" ], I18n.t("errors.product.gid_invalid"), "INVALID") unless match
        match && Integer(match[1])
      end

      def parse_location_gid(raw, index, errors)
        match = LOCATION_GID.match(raw.to_s)
        errors << error([ "variants", index.to_s, "initialQuantities" ], I18n.t("errors.product.gid_invalid"), "INVALID") unless match
        raw
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
              sync_variants!(shop, product, attributes)
              translation_errors = save_translations!(shop, product, attributes)
              raise TranslationRejected, translation_errors if translation_errors.any?

              enqueue_event!(shop, product, Events::Topics::PRODUCTS_CREATE)
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
                       user_errors: [ error([ "handle" ], I18n.t("errors.product.handle_taken"), "HANDLE_TAKEN") ])
          elsif (attempts += 1) < GENERATED_HANDLE_ATTEMPTS
            retry
          else
            Result.new(product: nil,
                       user_errors: [ error([ "handle" ], I18n.t("errors.product.handle_generation_failed"),
                                            "CREATION_FAILED") ])
          end
        rescue TranslationRejected => rejected
          Result.new(product: nil, user_errors: rejected.user_errors)
        rescue VariantRejected, Catalog::VariantSync::InitialQuantityRejected => rejected
          Result.new(product: nil, user_errors: rejected.user_errors)
        rescue ActiveRecord::RecordInvalid => invalid
          Result.new(product: nil, user_errors: translate_record_invalid(invalid))
        end
      end

      def create_product!(shop, attributes)
        handle = attributes[:handle] || unique_generated_handle(shop, attributes[:title])

        Product.create!(
          title: attributes[:title],
          # 建立態沒有「現值」可保持 ⇒ 缺席即空字串（欄位是 null: false）。
          description_html: attributes[:description_html].to_s,
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
                            user_errors: [ error([ "id" ], I18n.t("errors.product.gid_invalid"), "INVALID") ])
        end
        if input[:lock_version].nil?
          # 🔴 更新必帶 lockVersion：缺它「最後寫入者贏」會靜默蓋掉並發修改，
          #    正是 63 §A.4 樂觀鎖要擋的事故。
          return Result.new(product: nil,
                            user_errors: [ error([ "lockVersion" ], I18n.t("errors.product.lock_version_required"), "BLANK") ])
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

            # 第 6 包：handle 可改了。相同值＝no-op（前端送全樹不受影響）。
            # 佔用檢查不在這裡重複做：保留字／長度／redirect 佔用已在 normalize 擋；
            # 撞另一個商品由 model 的 `validates :handle, uniqueness` →
            # RecordInvalid → translate_record_invalid（HANDLE_TAKEN）承接，
            # 併發窗由下面的店級鎖＋`register!` 的複查關掉（審查 R6-3）。
            new_handle = attributes[:handle]
            handle_changed = new_handle.present? && new_handle != product.handle
            old_handle = product.handle
            # 🔴 改名是跨兩張表的不變量 ⇒ 店級序列化（HandleChange 檔頭③）。
            #    只在真的要改名時取，一般儲存不受影響。
            Catalog::HandleChange.serialize!(shop) if handle_changed

            product.assign_attributes(
              title: attributes[:title],
              handle: handle_changed ? new_handle : product.handle,
              # 🔴 `||` 而不是直接指派：normalize 在缺席時給 nil＝保持現值。
              #    Ruby 的 "" 是 truthy ⇒ 顯式清空（空字串）仍然寫得進去。
              description_html: attributes[:description_html] || product.description_html,
              status: attributes[:status] || product.status,
              # 只覆寫有提供的組織／SEO 鍵（缺席＝保持現值，normalize_organization 註釋）。
              **attributes.fetch(:organization)
            )
            # 全樹鎖：即使只有變體欄位變動也要 bump 版本 ⇒ 恆 touch updated_at。
            product.updated_at = Time.current
            product.save!
            # 🔴 改名 301 與改名**同一個 transaction**（62 §F.3）：redirect 沒寫成
            #    ＝舊網址 404；redirect 寫了、改名回滾＝好網址被轉走。兩者都不可接受。
            if handle_changed
              Catalog::HandleChange.register!(shop:, resource: :product,
                                              old_handle:, new_handle:)
            end
            # 第 3 包 cache stamp：宣告式全量下變體樹**每次更新都被重寫**
            # ⇒ 恆 bump（不精算「這次有沒有真的變」——精算漏一種形態就是舊快取）。
            # 🔴 走 CacheStamps 而不是直接賦值（審查 DOC-1）：stamp 的 runtime
            #    寫入面只有一個，「唯一寫入面」的宣稱與 `git grep CacheStamps`
            #    的複驗指令才都成立；混用直寫＝時鐘域與 lock 語義各走各的。
            Catalog::CacheStamps.bump_variants!(shop.id, product.id)

            sync_variants!(shop, product, attributes)
            translation_errors = save_translations!(shop, product, attributes)
            raise TranslationRejected, translation_errors if translation_errors.any?

            enqueue_event!(shop, product, Events::Topics::PRODUCTS_UPDATE)
          end
        end
        Result.new(product: product.reload, user_errors: [])
      rescue ActiveRecord::RecordNotFound
        Result.new(product: nil,
                   user_errors: [ error([ "id" ], I18n.t("errors.product.not_found"), "NOT_FOUND") ])
      rescue ActiveRecord::StaleObjectError
        Result.new(product: nil,
                   user_errors: [ error(nil, I18n.t("errors.product.stale"), "STALE_OBJECT") ])
      rescue TranslationRejected => rejected
        Result.new(product: nil, user_errors: rejected.user_errors)
      rescue VariantRejected, Catalog::VariantSync::InitialQuantityRejected => rejected
        Result.new(product: nil, user_errors: rejected.user_errors)
      rescue ActiveRecord::RecordNotUnique
        # 🔴 併發窗：兩個請求同時改成同一個 handle，輸家撞 `uq_products_handle`
        #    （審查 R6-1 實跑重現）。create 路徑早就接了，update 沒有——本包解鎖
        #    改名後這條路徑才首次可達。不接＝漏成 500（鐵律 4①），而
        #    graphql_controller 對 RecordNotUnique 是刻意 re-raise。
        Result.new(product: nil,
                   user_errors: [ error([ "handle" ], I18n.t("errors.product.handle_taken"), "HANDLE_TAKEN") ])
      rescue Catalog::HandleChange::Raced
        Result.new(product: nil,
                   user_errors: [ error([ "handle" ], I18n.t("errors.product.handle_raced"), "HANDLE_TAKEN") ])
      rescue ActiveRecord::RecordInvalid => invalid
        Result.new(product: nil, user_errors: translate_record_invalid(invalid))
      end

      # 寫譯文（ML-2）。**在商品的 transaction 內**呼叫：base 與譯文分兩次 commit 會出現
      # 「base 已改、digest 還是舊的」的窗口，那正是 67 §C.5 過期偵測要防的東西。
      # 缺席（nil）＝完全不動譯文；空陣列＝也不動（要刪某一條走「該條 value 空字串」）。
      #
      # @return [Array<Hash>] userErrors（空陣列＝成功）
      # 🔴 `entries` 缺席時**仍要跑**（只是不寫新譯文）：來源文字改了而譯文沒送，
      #    正是最常見的情境（商家改英文標題、沒動翻譯）——那時過期偵測必須照樣標記。
      #    早期版本在 nil 就 return，導致「改來源文字後譯文不標過期」（spec 抓到）。
      def save_translations!(shop, product, attributes)
        entries = attributes[:translations]

        source_locale = Locales::Registry.source_tag(shop)
        result = Translations::Upsert.call(
          shop:,
          resource_type: "PRODUCT",
          resource_id: product.id,
          source_locale:,
          source_values: {
            "title" => product.title,
            "body_html" => product.description_html,
            "meta_title" => product.seo_title,
            "meta_description" => product.seo_description
          },
          translations: Array(entries).map { |entry| entry.respond_to?(:to_h) ? entry.to_h.symbolize_keys : entry }
        )
        result.user_errors
      end

      # 第 22 包分流：有 options 樹 ⇒ VariantSync（兩階段 diff）；無 ⇒ 隱含變體路。
      # VariantSync 的 userErrors 以例外上拋（外層 rescue 轉 Result——與 Translation
      # 同型；🔴 不得用 ActiveRecord::Rollback，會被 transaction 靜默吞掉）。
      def sync_variants!(shop, product, attributes)
        if attributes[:options_input]
          result = Catalog::VariantSync.call(
            shop:, product:,
            options_input: attributes.fetch(:options_input),
            variants_input: attributes.fetch(:variants_input),
            idempotency_key: attributes[:idempotency_key])
          raise VariantRejected, result.user_errors if result.user_errors.any?
        elsif product.previously_new_record? || product.product_variants.none?
          create_implicit_variant!(shop, product, attributes.fetch(:variant))
        else
          update_implicit_variant!(product, attributes.fetch(:variant))
        end
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
          taxable: variant_attributes.fetch(:taxable),
          # 🔴 隱含變體與具名變體（VariantSync）**兩條路徑都要寫運送欄**——只補一條
          #    的症狀是「單變體商品改重量沒反應、多變體商品正常」，而單變體正是
          #    絕大多數商品（第 29 包 spec 的第四例就是抓這個）。
          weight_grams: variant_attributes.fetch(:weight_grams, 0),
          requires_shipping: variant_attributes.fetch(:requires_shipping, true)
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
          taxable: variant_attributes.fetch(:taxable),
          weight_grams: variant_attributes.fetch(:weight_grams, 0),
          requires_shipping: variant_attributes.fetch(:requires_shipping, true)
        )
      end

      # 63 §C.2 形（第 19 包 §4.5(a) 升級）：resource_version＝lock_version（§C.3 亂序防線①）、
      # changed_fields 只有欄位名沒有值（§C.2 紀律 1）、status 變更時經 StatusTransition
      # 一處實作補 status_transition 與 product.publication.changed 內部事件。
      # 🔴 內部 product.updated／product.variant.updated 本包不發（PR #115 §4.5 射程；
      #    留給接消費者的包，前置＝event_deliveries，63 §L-4 門檻）。
      NOISE_FIELDS = %w[id shop_id created_at updated_at lock_version].freeze

      def enqueue_event!(shop, product, topic)
        changed = product.saved_changes.keys - NOISE_FIELDS
        payload = {
          product_id: product.id,
          handle: product.handle,
          status: product.status,
          resource_version: product.lock_version,
          changed_fields: changed
        }
        payload[:status_transition] = Catalog::StatusTransition.call(shop: shop, product: product) if product.saved_changes.key?("status")
        EventOutbox.create!(
          event_id: SecureRandom.uuid,
          topic: topic,
          aggregate_type: "Product",
          aggregate_id: product.id,
          payload: payload,
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
        # 第 6 包：舊 handle 永不回收——重導的 from_path 也視同已占用，
        # 否則生成出的 handle 會被既有 301 把頁面轉走。
        return true if Catalog::HandleChange.path_reserved?(
          shop, Catalog::HandleChange.path_for(:product, handle))

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
