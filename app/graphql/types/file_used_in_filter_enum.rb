# frozen_string_literal: true

module Types
  # `files(usedIn:)` 的值域（第 28 包）。
  #
  # 對齊本尊 Files 頁的 **Used in** 篩選（changelog「Unified media library pools」
  # 2023-05-08 新增 Used-In 欄與 `used_in` 篩選；API 面 `files` query 支援
  # `used_in:product`／`used_in:none`，取證 2026-08-25）。
  # 🔴 本尊的 used_in 還涵蓋 Metaobjects 與 Brand Settings——我方那兩者尚未實作，
  #    因此 `PRODUCT` 目前恆等於「有任何引用」。等主題／頁面引用進來（第 30+ 包）
  #    要回頭把這個 enum 拆細，不得讓 PRODUCT 悄悄變成「其實是 any」。
  class FileUsedInFilterEnum < GraphQL::Schema::Enum
    graphql_name "FileUsedInFilter"
    description "依引用狀態篩選檔案。"

    value "PRODUCT", "被至少一個商品引用。"
    value "NONE", "沒有任何引用（可安全刪除）。"
  end
end
