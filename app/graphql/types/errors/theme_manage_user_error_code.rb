# frozen_string_literal: true

module Types
  module Errors
    # 主題管理 mutation（rename/duplicate/delete）的錯誤碼（鐵律 4）。
    class ThemeManageUserErrorCode < BaseCodeEnum
      graphql_name "ThemeManageUserErrorCode"
      description "主題管理可能回傳的錯誤碼。"

      from_pools
      own_value :PUBLISHED_THEME_PROTECTED,
                "已發布主題不可刪除（官方：delete an unpublished theme——先發布別的主題）。"
    end
  end
end
