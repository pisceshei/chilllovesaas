# frozen_string_literal: true

module Types
  # `files(sortKey:)` 的值域（D48「所有的都跟 Shopify」）。
  #
  # 本尊 Files 頁的排序值域＝**Date added／File name／Size**，各可升降
  # （help.shopify.com/en/manual/shopify-admin/productivity-tools/file-uploads，
  # 取證 2026-08-25，逐字："By default, files are listed from newest to oldest
  # based on the date that they were uploaded."）。
  #
  # 🔴 **enum 的成員名是我方取的（ours）**：官方 `FileSortKeys` 的完整值域
  #    **未取得**（query reference 只回了預設值 `ID`）。⇒ 三個名字都取自官方
  #    `files` query **篩選識別字**（`created_at`／`filename`／`original_upload_size`，
  #    同一份文檔明列），這樣至少不是憑空造字；查到官方值域後回頭對齊。
  #    不得把這段寫成「照抄本尊」。
  class FileSortKeysEnum < GraphQL::Schema::Enum
    graphql_name "FileSortKeys"
    description "檔案庫排序鍵。"

    value "CREATED_AT", "上傳日期（預設；未指定時為新到舊）。"
    value "FILENAME", "檔名。"
    value "ORIGINAL_UPLOAD_SIZE", "檔案大小。"
  end
end
