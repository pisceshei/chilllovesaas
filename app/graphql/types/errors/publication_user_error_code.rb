# frozen_string_literal: true

module Types
  module Errors
    # publication* 三支 mutation 的錯誤碼（鐵律 4：code 一律有值）。
    #
    # 🔴 **本尊的對位型別是 `PublicationUserErrorCode`，共 22 個值**
    # （<https://shopify.dev/docs/api/admin-graphql/latest/enums/PublicationUserErrorCode>，
    # 取證 2026-08-26；兩路獨立抓取一致）。我方**只宣告本輪真的會發出的碼**，
    # 其餘登記延後——宣告一個永遠不會出現的錯誤碼，前端會為它寫一條永遠死掉的分支。
    #
    # ⚠️ 本尊的 `PublicationUserError.code` 是 **nullable**（`PublicationUserErrorCode` 不是 `!`）
    # ⇒ 「code 一律有值」在 publication 線上同樣是**我方加嚴**，不是照抄（鐵律 4 已明文登記）。
    #
    # 🔴 **本輪刻意不宣告、且各有理由的本尊碼**（取得對應能力時再加）：
    #   `CANNOT_COMBINE_PRODUCTS_AND_VARIANTS`（我方 `publishablesToAdd` 不區分型別混用）、
    #   `CANNOT_MODIFY_MARKET_CATALOG(_PUBLICATION)`（我方尚無 market catalog，S10）、
    #   `MARKET_NOT_FOUND`（同上）、`PRODUCT_LOCK_ERROR`（我方尚無商品鎖）。
    class PublicationUserErrorCode < BaseCodeEnum
      graphql_name "PublicationUserErrorCode"
      description "publication 生命週期可能回傳的錯誤碼。"

      from_pools

      # 逐字對位本尊：`Publishable ID not found.`
      own_value :INVALID_PUBLISHABLE_ID,
        "publishable GID 格式不合法、型別不在允許清單內，或該資源不屬於本店。"

      # 逐字對位本尊：`Catalog does not exist.`
      own_value :CATALOG_NOT_FOUND, "指定的 catalog 不存在（或不屬於本店）。"

      # 🔴 逐字對位本尊：`Can't modify a publication that belongs to an app catalog.`
      #   我方的判準是「這個 publication 綁著一個 channel」——在我方模型裡，
      #   綁 channel 就等於它屬於某個 app 的 catalog（channel → app_installation → platform_app）。
      #   移除它是**卸載管道**，不是刪 publication。
      own_value :CANNOT_MODIFY_APP_CATALOG_PUBLICATION,
        "這個 publication 屬於一個已安裝的管道，不能直接刪除或改名（要移除請卸載該管道）。"
    end
  end
end
