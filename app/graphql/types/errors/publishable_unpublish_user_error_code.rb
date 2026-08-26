# frozen_string_literal: true

module Types
  module Errors
    # `publishableUnpublish` 的錯誤碼（S5）。
    #
    # 🔴 **本尊在這裡同樣是裸 `UserError`**（兩支的 return fields 逐字相同，
    # 取證 2026-08-27）⇒ 偏離的性質與量級與 `PublishablePublishUserErrorCode` 完全相同，
    # 理由不重複，見該檔。
    #
    # 🔴 **為什麼是獨立的 enum 而不是與 publish 共用一個**：
    #   `28 §0.3.2②` 明文「一支 mutation 一個獨立 enum」，形狀照抄本尊
    #   （本尊 `PageCreateUserErrorCode`／`PageUpdateUserErrorCode`／`PageDeleteUserErrorCode`
    #   是三個不同 type、值數還不一樣）。
    #   ⚠️ 兩支目前的值域**恰好相同**（都只用共用池），但那是巧合不是設計——
    #   unpublish 永遠不會發 `FEATURE_NOT_ENABLED`／`INVALID_STATE`（它不看 `publishDate`），
    #   合併成一個 enum 會讓前端為 unpublish 寫兩條永遠死掉的分支。
    #
    # ## 本輪真的會發出的碼
    #
    # | code | 觸發 |
    # |---|---|
    # | `NOT_FOUND` | `id` 或 `input[].publicationId` 解析不到本店資源 |
    # | `INVALID` | GID 格式錯、`publicationId` 缺席 |
    # | `TOO_BIG` | `input` 陣列超過 `api.array_input_max_items` |
    #
    # 🔴 **不含** `FEATURE_NOT_ENABLED`／`INVALID_STATE`：官方逐字
    #   `This field has no effect if you include it in the publishableUnpublish mutation.`
    #   ⇒ unpublish 完全不看 `publishDate`，那兩道排程守衛在本支結構上不可達。
    #
    # @see docs/dev/m2-publishable-write.md §5
    class PublishableUnpublishUserErrorCode < BaseCodeEnum
      graphql_name "PublishableUnpublishUserErrorCode"
      description "把資源自 publication 取消發布時可能回傳的錯誤碼。"

      from_pools
    end
  end
end
