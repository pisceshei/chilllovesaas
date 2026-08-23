# frozen_string_literal: true

module Types
  module Errors
    # shopLocale* 三支 mutation 的錯誤碼（鐵律 4：code 一律有值）。
    class ShopLocaleUserErrorCode < BaseCodeEnum
      graphql_name "ShopLocaleUserErrorCode"
      description "語言設定可能回傳的錯誤碼。"

      from_pools
      own_value :LOCALE_LIMIT_EXCEEDED, "已達每店語言數上限（limits i18n.max_shop_locales）。"
      own_value :SOURCE_LOCALE_IMMUTABLE, "來源語言不可停用、不可取消發布、不可刪除（67 §C.3(d)）。"
    end
  end
end
