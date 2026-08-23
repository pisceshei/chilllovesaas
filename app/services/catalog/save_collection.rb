# frozen_string_literal: true

module Catalog
  # 商品系列的宣告式 upsert（ML-3；形態沿用 `SaveProduct`／63 §B.4：建立與更新同一支，
  # 差別只在有無 id；lockVersion 涵蓋整棵樹）。
  #
  # 🔴 **與商品共用的三件事，刻意不另寫一份**：
  #   ① 譯文寫入走同一個 `Translations::Upsert`（只換 resource_type）；
  #   ② handle 生成走同一個 `HandleGenerator`；
  #   ③ AR 例外在這裡轉譯成 userErrors，不外洩（28 §0.3）。
  # 各寫一份的代價不是重複碼，是**語義漂移**——兩邊對「空字串＝清除」的解讀遲早不同。
  class SaveCollection
    Result = Data.define(:collection, :user_errors)

    class TranslationRejected < StandardError
      attr_reader :user_errors

      def initialize(user_errors)
        @user_errors = user_errors
        super("translations rejected")
      end
    end

    GID_PATTERN = %r{\Agid://chilllove/Collection/(\d+)\z}

    class << self
      # @param shop [Shop]
      # @param input [Hash] title／descriptionHtml／handle／seo／translations／collectionType／sortOrder／productIds
      # @return [Result]
      def call(shop:, input:)
        errors = []
        attributes = normalize(shop, input, errors)
        return Result.new(collection: nil, user_errors: errors) if errors.any?

        input[:id].present? ? update(shop, input, attributes) : create(shop, attributes)
      end

      private

      def normalize(shop, input, errors)
        title = input[:title].to_s.strip
        errors << error([ "title" ], I18n.t("errors.collection.title_blank"), "BLANK") if title.empty?
        if title.length > Limits.fetch(:product, :title_max_chars)
          errors << error([ "title" ], I18n.t("errors.collection.title_too_long"), "TOO_LONG")
        end

        description = Catalog::SaveProduct.sanitize_description_for(input[:description_html].to_s)

        collection_type = (input[:collection_type] || "manual").to_s.downcase
        unless Collection::TYPES.include?(collection_type)
          errors << error([ "collectionType" ], I18n.t("errors.collection.type_invalid"), "INVALID")
        end

        sort_order = (input[:sort_order] || "manual").to_s.downcase
        unless Collection::SORT_ORDERS.include?(sort_order)
          errors << error([ "sortOrder" ], I18n.t("errors.collection.sort_order_invalid"), "INVALID")
        end

        manual_handle = input[:handle].presence
        if manual_handle && !manual_handle.match?(/\A[a-z0-9-]+\z/)
          errors << error([ "handle" ], I18n.t("errors.collection.handle_invalid"), "INVALID")
        end

        {
          title:,
          description_html: description,
          handle: manual_handle,
          collection_type:,
          sort_order:,
          seo: seo_attributes(input, errors),
          product_ids: input[:product_ids],
          translations: input[:translations]
        }
      end

      def seo_attributes(input, errors)
        seo = input[:seo]
        return {} if seo.nil?

        attributes = {}
        unless seo[:title].nil?
          value = seo[:title].to_s.strip
          if value.length > Limits.fetch(:content, :seo_title_max_chars)
            errors << error([ "seo", "title" ], I18n.t("errors.collection.seo_title_too_long"), "TOO_LONG")
          end
          attributes[:seo_title] = value.presence
        end
        unless seo[:description].nil?
          value = seo[:description].to_s.strip
          if value.length > Limits.fetch(:content, :seo_meta_description_max_chars)
            errors << error([ "seo", "description" ], I18n.t("errors.collection.seo_description_too_long"), "TOO_LONG")
          end
          attributes[:seo_description] = value.presence
        end
        attributes
      end

      def create(shop, attributes)
        collection = nil
        ActsAsTenant.with_tenant(shop) do
          ActiveRecord::Base.transaction do
            collection = Collection.create!(
              title: attributes[:title],
              description_html: attributes[:description_html],
              handle: attributes[:handle] || unique_handle(shop, attributes[:title]),
              collection_type: attributes[:collection_type],
              sort_order: attributes[:sort_order],
              **attributes.fetch(:seo)
            )
            sync_members!(shop, collection, attributes[:product_ids])
            reject_translations!(shop, collection, attributes)
          end
        end
        Result.new(collection: collection.reload, user_errors: [])
      rescue TranslationRejected => rejected
        Result.new(collection: nil, user_errors: rejected.user_errors)
      rescue ActiveRecord::RecordNotUnique
        Result.new(collection: nil, user_errors: [ error([ "handle" ], I18n.t("errors.collection.handle_taken"), "HANDLE_TAKEN") ])
      rescue ActiveRecord::RecordInvalid => invalid
        Result.new(collection: nil, user_errors: translate_record_invalid(invalid))
      end

      # model 驗證（uniqueness）與 DB 唯一索引是兩條路徑，**兩條都要轉成同一個碼**——
      # 只處理其中一條的症狀是「單機測試回 HANDLE_TAKEN、併發時回 INVALID」。
      def translate_record_invalid(invalid)
        invalid.record.errors.map do |model_error|
          if model_error.attribute == :handle && model_error.type == :taken
            error([ "handle" ], I18n.t("errors.collection.handle_taken"), "HANDLE_TAKEN")
          else
            error(nil, model_error.full_message, "INVALID")
          end
        end
      end

      def update(shop, input, attributes)
        match = GID_PATTERN.match(input[:id].to_s)
        return Result.new(collection: nil, user_errors: [ error([ "id" ], I18n.t("errors.collection.gid_invalid"), "INVALID") ]) unless match
        if input[:lock_version].nil?
          return Result.new(collection: nil,
                            user_errors: [ error([ "lockVersion" ], I18n.t("errors.collection.lock_version_required"), "BLANK") ])
        end

        collection = nil
        ActsAsTenant.with_tenant(shop) do
          ActiveRecord::Base.transaction do
            collection = Collection.lock.find_by(id: match[1])
            raise ActiveRecord::RecordNotFound if collection.nil?
            raise ActiveRecord::StaleObjectError.new(collection, "update") if collection.lock_version != input[:lock_version]

            collection.assign_attributes(
              title: attributes[:title],
              description_html: attributes[:description_html],
              collection_type: attributes[:collection_type],
              sort_order: attributes[:sort_order],
              **attributes.fetch(:seo)
            )
            collection.updated_at = Time.current
            collection.save!
            sync_members!(shop, collection, attributes[:product_ids])
            reject_translations!(shop, collection, attributes)
          end
        end
        Result.new(collection: collection.reload, user_errors: [])
      rescue TranslationRejected => rejected
        Result.new(collection: nil, user_errors: rejected.user_errors)
      rescue ActiveRecord::RecordNotFound
        Result.new(collection: nil, user_errors: [ error([ "id" ], I18n.t("errors.collection.not_found"), "NOT_FOUND") ])
      rescue ActiveRecord::StaleObjectError
        Result.new(collection: nil, user_errors: [ error(nil, I18n.t("errors.collection.stale"), "STALE_OBJECT") ])
      rescue ActiveRecord::RecordInvalid => invalid
        Result.new(collection: nil, user_errors: translate_record_invalid(invalid))
      end

      # 宣告式成員同步（只對手動系列）：未列出＝移除，順序＝陣列順序。
      # 🔴 智慧系列送 productIds 一律忽略——成員是規則的函數，接受它等於製造第二個真相。
      def sync_members!(shop, collection, product_ids)
        return if product_ids.nil?
        return unless collection.collection_type == "manual"

        ids = Array(product_ids).filter_map { |gid| gid.to_s[%r{/(\d+)\z}, 1]&.to_i }
        # 🔴 `pluck` 回的是 **DB 順序**不是送入順序——position 必須照商家給的陣列順序，
        #    否則「拖曳排序後儲存，順序又跳回去」。存在性用 Set 過濾，排序用原陣列。
        found = Product.where(shop_id: shop.id, id: ids).pluck(:id).to_set
        existing = ids.uniq.select { |id| found.include?(id) }
        collection.collection_products.where.not(product_id: existing).delete_all
        existing.each_with_index do |product_id, index|
          record = collection.collection_products.find_or_initialize_by(product_id:)
          record.shop_id = shop.id
          record.position = index
          record.save!
        end
      end

      # 譯文與商品共用同一個服務（只換 resource_type）；驗證失敗 ⇒ 整棵樹回滾。
      def reject_translations!(shop, collection, attributes)
        result = Translations::Upsert.call(
          shop:,
          resource_type: "COLLECTION",
          resource_id: collection.id,
          source_locale: Locales::Registry.source_tag(shop),
          source_values: {
            "title" => collection.title,
            "body_html" => collection.description_html,
            "meta_title" => collection.seo_title,
            "meta_description" => collection.seo_description
          },
          translations: Array(attributes[:translations]).map { |entry| entry.respond_to?(:to_h) ? entry.to_h.symbolize_keys : entry }
        )
        raise TranslationRejected, result.user_errors if result.user_errors.any?
      end

      def unique_handle(shop, title)
        3.times do
          candidate = Catalog::HandleGenerator.call(title, resource: "collection").handle
          return candidate unless Collection.where(shop_id: shop.id, handle: candidate).exists?
        end
        "collection-#{SecureRandom.alphanumeric(8).downcase}"
      end

      def error(field, message, code)
        { field:, message:, code: }
      end
    end
  end
end
