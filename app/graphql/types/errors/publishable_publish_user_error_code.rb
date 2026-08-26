# frozen_string_literal: true

module Types
  module Errors
    # `publishablePublish` 的錯誤碼（S5）。
    #
    # ## 🔴 這是比 publication 線更大的一次偏離，逐項登記
    #
    # 本尊 `publishablePublish` 的 `userErrors` 型別是**裸 `UserError`**
    # （<https://shopify.dev/docs/api/admin-graphql/latest/mutations/publishablePublish>，
    # 取證 2026-08-27），而 `UserError` **恆兩欄**（`field`／`message`）——
    # 它實作的 `DisplayableError` 介面本身也只有那兩欄，**沒有 `code`**。
    # 官方自己的 Example 也只選 `field`／`message` 兩欄。
    # ⇒ 我方等於**憑空新增一個本尊 schema 中不存在的型別，外加一個不存在的欄位**。
    #
    # **對照 S1（publication 線）的量級差**：那次本尊**有** `PublicationUserErrorCode`
    # （22 值），我方只是精簡值域；本支是從零造。
    #
    # ## 授權鏈（為什麼不需要新的使用者裁定）
    #
    # 鐵律 4 已明文授權「我方全部 mutation 一開始就上 typed code enum」，
    # 其理由——**admin SPA 是唯一客戶端、錯誤分支必須機器可判別**——在本支同樣成立。
    # ⚠️ 鐵律 4 註記另有一句「本尊自己也在逐支遷往 typed error」，
    # 🔴 **本檔不引用那句**作為正當性來源：它目前只有 `bulkOperationRunMutation`
    # 一個具名錨，單點證據撐不起全稱句（鐵律 19.1）。
    #
    # ## 本輪真的會發出的碼（`from_pools` 之外不另加專屬碼）
    #
    # | code | 觸發 |
    # |---|---|
    # | `NOT_FOUND` | `id` 或 `input[].publicationId` 解析不到本店資源 |
    # | `INVALID` | GID 格式錯、`publicationId` 缺席、`publishDate` 明確傳 `null` |
    # | `TOO_BIG` | `input` 陣列超過 `api.array_input_max_items` |
    # | `FEATURE_NOT_ENABLED` | 該 publication 的 `supports_future_publishing` 為 false |
    # | `INVALID_STATE` | 為不支援排程的 publishable 型別（正典＝limits）指定未來時間 |
    #
    # 五個碼**全部在共用池內**，`from_pools` 即涵蓋 ⇒ 本檔無 `own_value`。
    # 🔴 **不自創 `LIMIT_EXCEEDED`**（`28 §2` 明文禁止，超限一律 `TOO_BIG`）。
    #
    # @see docs/dev/m2-publishable-write.md §5
    class PublishablePublishUserErrorCode < BaseCodeEnum
      graphql_name "PublishablePublishUserErrorCode"
      description "把資源發布到 publication 時可能回傳的錯誤碼。"

      from_pools
    end
  end
end
