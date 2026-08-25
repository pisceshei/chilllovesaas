# frozen_string_literal: true

module Locales
  # 某店的語言集合查詢（docs/specs/67 §C.1）。集合是**資料**不是列舉——
  # 新增語言不改程式碼、不 migration（§A.2；驗收 I18N-2）。
  module Registry
    module_function

    # @param shop [Shop]
    # @return [Array<String>] 已啟用語言（position 序），含來源語言
    def enabled_tags(shop)
      ActsAsTenant.with_tenant(shop) { ShopLocale.enabled.pluck(:locale_tag) }
    end

    # @param shop [Shop]
    # @return [String] 來源語言標籤（base row 的語言；每店恰一個）
    def source_tag(shop)
      ActsAsTenant.with_tenant(shop) { ShopLocale.source!.locale_tag }
    end

    # 前台可見的語言（`shop_locales.published`）。
    #
    # 🔴 **enabled 與 published 是兩件事，不得互相代用**：`enabled=false` 是「下架但譯文保留」
    #   （`shop_locales.enabled` 欄註釋），`published=false` 是「只能用預覽連結看」
    #   （`i18n.storefront.unpublished_locale_status: 404`）。
    #   ⇒ `Translations::Resolve` 的 `scope: :published` 用這一支、`scope: :enabled` 用上一支；
    #   把前台的解析範圍寫成 enabled，未發布語言的譯文就會經由 fallback 鏈漏到前台去。
    #
    # @param shop [Shop]
    # @return [Array<String>] 已發布語言（position 序）
    def published_tags(shop)
      # `ShopLocale.published` scope 本身沒有 order（`enabled` 有）⇒ 這裡補上，
      # 讓兩支的回傳順序一致；順序會流進切換器與 fallback 候選，不該由 DB 決定。
      ActsAsTenant.with_tenant(shop) do
        ShopLocale.published.order(:position, :locale_tag).pluck(:locale_tag)
      end
    end

    # @param shop [Shop]
    # @return [Array<String>] 已啟用且非來源語言（編輯頁要長出欄位的那些）
    def translatable_tags(shop)
      source = source_tag(shop)
      enabled_tags(shop) - [ source ]
    end
  end
end
