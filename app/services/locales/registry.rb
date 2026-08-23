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

    # @param shop [Shop]
    # @return [Array<String>] 已啟用且非來源語言（編輯頁要長出欄位的那些）
    def translatable_tags(shop)
      source = source_tag(shop)
      enabled_tags(shop) - [ source ]
    end
  end
end
