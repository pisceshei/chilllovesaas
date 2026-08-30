# frozen_string_literal: true

module Types
  module Errors
    # themePublish 的錯誤碼（鐵律 4：code 一律有值——本尊 `ThemePublishUserError.code`
    # 是 nullable enum，我方加嚴，與 publication 線同款）。
    class ThemePublishUserErrorCode < BaseCodeEnum
      graphql_name "ThemePublishUserErrorCode"
      description "themePublish 可能回傳的錯誤碼。"

      from_pools

      # ours：本尊無對位（它的主題檔恆在其平台內）；我方主題檔案來源可缺席
      # （fixture 不隨平台散布、first-party 目錄未部署），發布無檔案來源的主題
      # 會讓前台整站不可渲染 ⇒ 擋在這裡。NOT_FOUND 已在共用池。
      own_value :SOURCE_MISSING, "主題沒有可解析的檔案來源（ours；發布會導致前台不可渲染）"
    end
  end
end
