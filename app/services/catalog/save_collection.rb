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

    # 整棵樹的拒絕載體（譯文、成員 ID⋯⋯）：任一子部分被拒 ⇒ 整筆存檔回滾。
    class TreeRejected < StandardError
      attr_reader :user_errors

      def initialize(user_errors)
        @user_errors = user_errors
        super("collection tree rejected")
      end
    end

    GID_PATTERN = %r{\Agid://chilllove/Collection/(\d+)\z}
    PRODUCT_GID_PATTERN = %r{\Agid://chilllove/Product/(\d+)\z}

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
        elsif manual_handle && manual_handle.length > Limits.fetch(:handle, :max_chars)
          errors << error([ "handle" ], I18n.t("errors.collection.handle_too_long"), "TOO_LONG")
        elsif manual_handle && Limits.fetch(:handle, :reserved).map(&:to_s).include?(manual_handle)
          # 🔴 保留字檢查商品側早就有、系列側沒有（審查 R6-4）：本包解鎖系列改名後
          #    系列可被改成 "all"／"new"／"index"，撞平台路由段。
          errors << error([ "handle" ], I18n.t("errors.collection.handle_reserved"), "INVALID")
        elsif manual_handle && Catalog::HandleChange.path_reserved?(
          shop, Catalog::HandleChange.path_for(:collection, manual_handle))
          # 舊 handle 永不回收（62 §F.3；與 SaveProduct 同判準入口）。
          errors << error([ "handle" ], I18n.t("errors.collection.handle_redirected"), "HANDLE_TAKEN")
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
          # 🔴 `requires_new:` 不是可選的謹慎，是**正確性**：Rails 的 joined 巢狀交易
          #    下，這個 block 內 raise 再於 block 外 rescue，**什麼都不會回滾**——
          #    部分寫入照樣被外層 commit（`Idempotency::Guard` 註釋記錄過同一個陷阱）。
          #    v1 的 collectionSet 沒有外層交易，所以現在「剛好」是對的；
          #    但這種正確性取決於呼叫者，日後有人加上冪等包裝就靜默失效，
          #    而症狀是「回了 userErrors，資料庫卻多了一筆半成品系列」。
          #    🔴 這不是推論，是實測（2026-08-23，MySQL 8.4 / Rails 8.1）：
          #    joined 巢狀 ⇒ 殘留列數 1；requires_new ⇒ 0。
          #    **request spec 驗不到這件事**（RSpec 測試交易是 joinable: false，
          #    兩種寫法都綠），守衛在 spec/services/catalog/save_collection_spec.rb。
          ActiveRecord::Base.transaction(requires_new: true) do
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
      rescue TreeRejected => rejected
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
          # 見 create 的 `requires_new:` 說明——兩條路徑必須一致。
          ActiveRecord::Base.transaction(requires_new: true) do
            collection = Collection.lock.find_by(id: match[1])
            raise ActiveRecord::RecordNotFound if collection.nil?
            raise ActiveRecord::StaleObjectError.new(collection, "update") if collection.lock_version != input[:lock_version]

            # 第 6 包：系列 handle 可改（先前是靜默忽略——那比硬拒更糟，
            # 商家以為改了、其實沒改）。相同值＝no-op。
            new_handle = attributes[:handle]
            handle_changed = new_handle.present? && new_handle != collection.handle
            old_handle = collection.handle
            # 🔴 跨兩張表的不變量 ⇒ 店級序列化（HandleChange 檔頭③；與商品同一套）。
            Catalog::HandleChange.serialize!(shop) if handle_changed

            collection.assign_attributes(
              title: attributes[:title],
              handle: handle_changed ? new_handle : collection.handle,
              description_html: attributes[:description_html],
              collection_type: attributes[:collection_type],
              sort_order: attributes[:sort_order],
              **attributes.fetch(:seo)
            )
            collection.updated_at = Time.current
            collection.save!
            # 改名 301 同 txn（62 §F.3；與 SaveProduct 同一套語義）。
            if handle_changed
              Catalog::HandleChange.register!(shop:, resource: :collection,
                                              old_handle:, new_handle:)
            end
            sync_members!(shop, collection, attributes[:product_ids])
            reject_translations!(shop, collection, attributes)
          end
        end
        Result.new(collection: collection.reload, user_errors: [])
      rescue TreeRejected => rejected
        Result.new(collection: nil, user_errors: rejected.user_errors)
      rescue ActiveRecord::RecordNotFound
        Result.new(collection: nil, user_errors: [ error([ "id" ], I18n.t("errors.collection.not_found"), "NOT_FOUND") ])
      rescue ActiveRecord::StaleObjectError
        Result.new(collection: nil, user_errors: [ error(nil, I18n.t("errors.collection.stale"), "STALE_OBJECT") ])
      rescue ActiveRecord::RecordNotUnique
        # 併發窗：輸家撞 `uq_collections_handle`（審查 R6-2，與商品同型）。
        Result.new(collection: nil,
                   user_errors: [ error([ "handle" ], I18n.t("errors.collection.handle_taken"), "HANDLE_TAKEN") ])
      rescue Catalog::HandleChange::Raced
        Result.new(collection: nil,
                   user_errors: [ error([ "handle" ], I18n.t("errors.collection.handle_raced"), "HANDLE_TAKEN") ])
      rescue ActiveRecord::RecordInvalid => invalid
        Result.new(collection: nil, user_errors: translate_record_invalid(invalid))
      end

      # 宣告式成員同步（只對手動系列）：未列出＝移除，順序＝陣列順序。
      # 🔴 智慧系列送 productIds 一律忽略——成員是規則的函數，接受它等於製造第二個真相。
      # 成員 GID → id。🔴 **解析不出來或不屬於本店的一律報錯，不得靜默丟掉**：
      # 這是宣告式 API（未列出＝移除），靜默丟掉的症狀是「存檔成功，但成員少了一個」——
      # 沒有錯誤訊息、沒有紅字，商家要到前台才發現，而那時已經不知道是哪一步弄丟的。
      # 併發刪除（商品剛被同事刪掉）也走這條：回 NOT_FOUND 讓商家重載後看見商品真的沒了，
      # 比替他決定「那就不要那個成員」誠實。
      def resolve_member_ids(shop, product_ids, errors)
        parsed = Array(product_ids).map do |gid|
          id = gid.to_s[PRODUCT_GID_PATTERN, 1]
          errors << error([ "productIds" ], I18n.t("errors.collection.product_gid_invalid", gid: gid.to_s), "INVALID") if id.nil?
          id&.to_i
        end
        return [] if errors.any?

        ids = parsed.uniq
        found = Product.where(shop_id: shop.id, id: ids).pluck(:id).to_set
        missing = ids.reject { |id| found.include?(id) }
        missing.each do |id|
          errors << error([ "productIds" ], I18n.t("errors.collection.product_not_found", id:), "NOT_FOUND")
        end
        # 🔴 `pluck` 回的是 **DB 順序**不是送入順序——position 必須照商家給的陣列順序，
        #    否則「拖曳排序後儲存，順序又跳回去」。排序一律用原陣列。
        ids
      end

      def sync_members!(shop, collection, product_ids)
        return if product_ids.nil?
        return unless collection.collection_type == "manual"

        errors = []
        ids = resolve_member_ids(shop, product_ids, errors)
        raise TreeRejected, errors if errors.any?

        collection.collection_products.where.not(product_id: ids).delete_all
        ids.each_with_index do |product_id, index|
          record = collection.collection_products.find_or_initialize_by(product_id:)
          record.shop_id = shop.id
          record.position = index
          record.save!
        end
        # 第 3 包 cache stamp：成員集合變了（14 §F1 的 collections.products_updated_at）。
        Catalog::CacheStamps.bump_collection_members!(shop.id, collection.id)
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
        raise TreeRejected, result.user_errors if result.user_errors.any?
      end

      # 生成衝突＝數字尾碼（limits `collision_strategy_generated: numeric_suffix_from_1`，
      # 與 SaveProduct 同語義）。
      # 🔴 舊版是 `3.times` 重跑同一個確定性生成器——三輪必得同一個 candidate，
      #   任何衝突都直接掉進隨機 fallback（`collection-<8碼>`），而商品側是
      #   `veteran → veteran-1`。同倉兩套語義，且隨機 fallback 不經任何檢查
      #   （審查 P6-6）。隨機碼現在只留給「品質閘門不過」那一種情形。
      def unique_handle(shop, title)
        base = Catalog::HandleGenerator.call(title, resource: "collection").handle
        return base unless collection_handle_taken?(shop, base)

        (1..).each do |suffix|
          candidate = "#{base}-#{suffix}"
          return candidate unless collection_handle_taken?(shop, candidate)
        end
      end

      def collection_handle_taken?(shop, handle)
        return true if Limits.fetch(:handle, :reserved).map(&:to_s).include?(handle)
        return true if Catalog::HandleChange.path_reserved?(
          shop, Catalog::HandleChange.path_for(:collection, handle))

        Collection.where(shop_id: shop.id, handle:).exists?
      end

      def error(field, message, code)
        { field:, message:, code: }
      end
    end
  end
end
