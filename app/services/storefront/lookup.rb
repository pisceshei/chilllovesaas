# frozen_string_literal: true

module Storefront
  # 前台消費介面的**直連讀取入口**（S9；docs/specs/93 的可執行落點）。
  #
  # ①這是什麼：W6（包 30+）的 Liquid 渲染管線與未來 Storefront API 解析 handle／id
  #   時的**唯一**入口。本尊語義（兩條 A 級錨，取證 2026-08-30）：
  #   - Storefront API：未發布資源逐字 "Unpublished products will behave just like
  #     they were archived or deleted: they will be omitted from connections and
  #     not found when queried by handle or ID"（shopify.dev product query 頁）
  #     ——查單筆回 **null**（不是錯誤），connection 裡**整筆消失**。
  #   - Liquid 前台：查無 handle ⇒ 主題化 **404** 頁（實測 2026-08-30，82 §20）。
  #   ⇒ 本模組統一回 **record 或 nil**；「nil → 404 頁」是 W6 controller 的事，
  #   「nil → JSON null」是 API serializer 的事——**分層在消費端，不在這裡**。
  # ②判準（🔴 直連面用 `purchasable`，不是 `discoverable`）：
  #   UNLISTED 官方逐字 "The product is active but you need a direct link to view
  #   it… It will be returned in Storefront API and Liquid only when referenced
  #   individually by handle, id, or metafield reference."（ProductStatus enum）
  #   ⇒ 直連（handle／id／metafield 引用）落在 purchasable 集合；
  #   搜尋、系列、推薦、sitemap、feed 等**發現面**必須改用 `Product.discoverable`
  #   ——那一側不經過本模組（W6 紅線見 93 §D）。
  #   實測對照（82 §20 矩陣）：draft／archived 直連 404、unlisted 直連 200
  #   且 suggest／全文搜尋皆排除。
  # ③明確不做：
  #   - 店級閘門（密碼保護／development、B2B-only）＝**包 30/33 的請求層**射程
  #     （閘在 controller before_action，先於任何 lookup；93 §E）。
  #   - 第三層 catalog 過濾（88 §3.2 延後 M5）——補上時是在這裡的 relation 再加條件。
  #   - Collection 無 status 欄 ⇒ 只有發布層一個閘（88 §1；本檔 collection_by_handle）。
  module Lookup
    module_function

    # 直連查商品（Liquid `/products/{handle}`、API `product(handle:)`）。
    #
    # @param publication [Publication] 正在逛的管道（🔴 必填，同 `Product.purchasable`
    #   檔頭的理由：沒有「任一管道」的版本）
    # @param handle [String] 大小寫不敏感（handle 欄位 uniqueness 即 case_insensitive）
    # @param at [Time] 判定時點（排程發布未到點＝未發布）
    # @return [Product, nil]
    # @note 副作用：一次 SELECT。
    def product_by_handle(publication:, handle:, at: Time.current)
      Product.purchasable(publication:, at:).find_by(handle: handle.to_s)
    end

    # 直連查商品（id 形態；metafield product_reference 解引用也走這裡）。
    # @return [Product, nil]
    def product_by_id(publication:, id:, at: Time.current)
      Product.purchasable(publication:, at:).find_by(id:)
    end

    # 直連查系列（Liquid `/collections/{handle}`）。
    #
    # 🔴 系列**沒有狀態層**（Collection 無 status 欄），可見性＝發布層單閘；
    #   「系列頁裡列哪些商品」是另一個問題（`discoverable` ∧ 成員關係），
    #   屬 W6 系列頁射程，**不在**本模組。
    # @return [Collection, nil]
    def collection_by_handle(publication:, handle:, at: Time.current)
      Collection.published_on(publication, at:).find_by(handle: handle.to_s)
    end
  end
end
