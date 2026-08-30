# frozen_string_literal: true

module Types
  module Errors
    # urlRedirect* 三支 mutation 的錯誤碼（鐵律 4：code 一律有值）。
    class UrlRedirectUserErrorCode < BaseCodeEnum
      graphql_name "UrlRedirectUserErrorCode"
      description "重導管理可能回傳的錯誤碼。"

      from_pools
      own_value :PREFIXED_PATH_FORBIDDEN,
                "路徑不得帶 locale 前綴——重導存無前綴正規形，各語言由路由層自動保留前綴（62 §F.3；包 36 裁定）。"
      own_value :SELF_REDIRECT, "來源與目標不得相同（自我迴圈）。"
    end
  end
end
