# frozen_string_literal: true

module Types
  module Errors
    # `productSet` 的 typed error code enum（鐵律 4：code 一律有值，ours 加嚴）。
    #
    # 值域＝共用池（COMMON＋CONCURRENCY）＋商品線專屬碼。`CONFLICT` 是
    # DISCOUNT_ONLY，禁入本 enum（code_pools.rb 的紀律）。
    #
    # @see docs/research/28-api-contract.md §6
    # @see docs/specs/63-product-data-flow.md §A.1 ③
    class ProductSetUserErrorCode < BaseCodeEnum
      graphql_name "ProductSetUserErrorCode"
      description "productSet 可能回傳的錯誤碼。"

      from_pools
      own_value :HANDLE_TAKEN, "handle 已被同店其他商品使用（手填衝突一律拒絕，不自動加尾碼）。"
      # ML-2：譯文的語言不在該店已啟用清單（67 §C.1；設定 › 語言啟用後才可寫）。
      own_value :LOCALE_NOT_ENABLED, "指定的語言未在本商店啟用。"
    end
  end
end
