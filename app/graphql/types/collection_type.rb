# frozen_string_literal: true

module Types
  # 商品系列（列表唯讀面；建立式待 71-R8-V4 裁定——sources 模型 vs 手動/智慧二分）。
  class CollectionType < BaseObject
    graphql_name "Collection"
    description "商品系列。"

    # S2：本尊 Collection 實作 `Publishable` 介面。
    implements Types::Interfaces::Publishable

    field :id, ID, null: false, description: "gid://chilllove/Collection/{id}"
    field :legacy_resource_id, ID, null: false
    field :title, String, null: false
    field :handle, String, null: false
    # ⚠️ 13 §F4 已把 manual/smart 標為 **legacy 衍生標籤**（原型 colKind 註釋：
    # 任何求值都不得讀它）；本欄位只供列表檢視篩選，sources 模型落地後改為衍生。
    field :collection_type, String, null: false,
      description: "manual／smart（legacy 檢視標籤；sources 模型落地後為衍生值）。"
    # 手動＝collection_products 數；智慧＝物化 memberships 數（第 11 包引擎）。
    # 🔴 null 仍然存在：智慧系列**尚未成功 rebuild**（rebuild_status ≠ OK）時回 null
    #   ——「未求值」與「恰好沒有商品」是兩件事（同金額 null≠0 原則），前端照舊顯示「—」。
    field :products_count, Integer, null: true,
      description: "商品數；智慧系列在首次成功 rebuild 前為 null。"
    # 「前台可見件數」——計畫表第 12 列逐字的可見交付。
    #
    # 🔴 判準是 **discoverable** 不是 purchasable，依據本尊對 UNLISTED 的官方定義：
    #   「An unlisted product doesn't display in Shopify-powered collection pages…」
    #   ⇒ Unlisted 商品可購買，但**不出現在系列頁**。
    # 🔴 null 的語義是「**不知道**」，不是 0：①單筆讀取沒帶這個 select；
    #   ②店裡還沒有 online_store 管道（沒有前台可談）。與 `products_count` 的
    #   null≠0 原則一致。
    field :visible_products_count, Integer, null: true,
      description: "在線上商店前台可見的商品數（discoverable）；未帶列表 select 或無管道時為 null。"
    field :rebuild_status, String, null: true,
      description: "智慧系列物化狀態：OK／PENDING／ERROR；手動系列為 null。"
    field :description_html, String, null: false
    field :sort_order, String, null: false, description: "前台排序（13 §F4）。"
    field :lock_version, Integer, null: false, description: "全樹樂觀鎖（含譯文）。"
    field :seo, Types::SeoType, null: false, description: "SEO 覆寫；子欄位 null＝未覆寫。"
    field :product_ids, [ ID ], null: false, description: "手動系列成員（position 序）；智慧系列為空陣列。"
    field :translations, [ Types::TranslationType ], null: false do
      argument :locales, [ String ], required: false
    end
    field :translation_status, [ Types::TranslationStatusType ], null: false,
      description: "各語言翻譯進度（鐵律 7：唯一來源 translation_status）。"

    # @return [String] GID
    def id
      "gid://chilllove/Collection/#{object.id}"
    end

    # @return [String] 十進位主鍵字串
    def legacy_resource_id
      object.id.to_s
    end

    # SEO 子物件直接以 collection 為 object（欄位在同一列上，SeoType 讀 seo_title／seo_description）。
    def seo = object

    # @return [Array<String>] 手動系列成員的 GID（position 序）
    def product_ids
      return [] unless object.collection_type == "manual"

      CollectionProduct.where(shop_id: object.shop_id, collection_id: object.id)
                       .ordered.pluck(:product_id)
                       .map { |id| "gid://chilllove/Product/#{id}" }
    end

    # @param locales [Array<String>, nil]
    # @return [Array<Translation>]
    def translations(locales: nil)
      scope = Translation.where(shop_id: object.shop_id, resource_type: "COLLECTION", resource_id: object.id)
      scope = scope.where(locale_tag: locales.map { |tag| Locales::Tag.normalize(tag) }) if locales.present?
      scope.order(:locale_tag, :field_key)
    end

    # @return [Array<TranslationStatus>]
    def translation_status
      TranslationStatus.where(shop_id: object.shop_id, resource_type: "COLLECTION", resource_id: object.id)
                       .order(:locale_tag)
    end

    # @return [Integer, nil]
    # 智慧系列在**尚未成功重建**（rebuild_status ≠ OK）時回 nil——回 0 是在斷言一件
    # 我方不知道的事。（2026-08-26 第七輪 L7 更正：原文寫「規則引擎未落地」，
    # 而該引擎正是第 11 包交付的；判準已改成看 rebuild_status。）
    # 手動系列優先用列表 select 帶下來的 `member_count`（見 `Collection::MEMBER_COUNT_SELECT`），
    # 單筆讀取沒有該欄時才退回自己 COUNT。
    def products_count
      if object.collection_type == "smart"
        return nil unless object.rebuild_status == "OK"
        return object.read_attribute("member_count").to_i if object.has_attribute?("member_count")

        return CollectionMembership.where(shop_id: object.shop_id, collection_id: object.id).count
      end
      return object.read_attribute("member_count").to_i if object.has_attribute?("member_count")

      CollectionProduct.where(shop_id: object.shop_id, collection_id: object.id).count
    end

    # 「前台可見件數」。
    #
    # 🔴 **只從列表 select 讀，不做逐筆 fallback**——與 `products_count` 刻意不同。
    # 理由：這個數字的算式含三層 EXISTS，逐筆退回等於在單筆讀取上跑一個
    # 昂貴查詢，而單筆頁（系列編輯頁）根本不顯示它。
    # 沒有這個欄 ⇒ 回 nil＝「本次查詢沒問這個數字」，**不是 0**。
    #
    # @return [Integer, nil]
    def visible_products_count
      return nil unless object.has_attribute?("visible_member_count")
      # 智慧系列尚未成功 rebuild 時，成員本身就是「未求值」⇒ 與 products_count 同口徑回 nil。
      return nil if object.collection_type == "smart" && object.rebuild_status != "OK"

      object.read_attribute("visible_member_count").to_i
    end
  end
end
