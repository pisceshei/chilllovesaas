# frozen_string_literal: true

module Types
  module Errors
    # 內容線（pages/blogs/articles/menus）mutation 的錯誤碼（鐵律 4）。
    class ContentUserErrorCode < BaseCodeEnum
      graphql_name "ContentUserErrorCode"
      description "內容線 mutation 可能回傳的錯誤碼。"

      from_pools
      own_value :DEFAULT_MENU_PROTECTED,
                "預設選單不可刪除、handle 不可改（官方：default menus can't be deleted——98 §3）。"
      own_value :NESTING_TOO_DEEP,
                "選單巢狀超過 3 層上限（官方 linklist.levels：maximum of 3 levels）。"
    end
  end
end
