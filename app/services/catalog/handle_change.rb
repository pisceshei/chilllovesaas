# frozen_string_literal: true

module Catalog
  # handle 變更的重導掛鉤（第 6 包；62 §F.3）。商品與系列共用。
  #
  # ①這是什麼：改 handle 時在**同一 transaction** 登記 301，並做鏈坍縮。
  # ②🔴 **舊 handle 永不回收**（62 §F.3 逐字「唯一性檢查因此要比對 url_redirects」）：
  #   `path_reserved?` 是唯一判準入口——handle 生成器與手填驗證都必須經過它，
  #   否則新商品可以佔走一個舊網址，讓既有 301 把它的頁面轉走。
  # ③🔴 **鏈坍縮在寫入時做**：B 改名 C 時，把所有指向 /…/B 的列改指 /…/C
  #   （A→B 變 A→C）。不坍縮的話鏈會隨改名次數線性成長，逼近
  #   `limits seo.redirect_max_chain`（Google ≤10 hops）才爆——爆的時候已經
  #   不知道是哪幾次改名疊出來的。坍縮＋「新路徑不得是既有 from_path」兩件事
  #   合起來保證**表裡永遠沒有鏈也沒有迴圈**（不變量，spec 釘住）。
  # ④跨功能影響：讀取者＝第 36 包的 301 引擎與後台重導管理；
  #   `SaveProduct`／`SaveCollection` 的 handle 流程都掛在這裡。
  module HandleChange
    class << self
      # 這條路徑是否已被重導佔用（＝某個舊 handle 的網址）。
      # @return [Boolean]
      def path_reserved?(shop, path)
        UrlRedirect.where(shop_id: shop.id, from_path: path).exists?
      end

      # 在呼叫端的 transaction 內登記改名重導＋鏈坍縮。
      #
      # 🔴 前置：呼叫端已用 `path_reserved?` 擋掉「新路徑是既有 from_path」
      #   ——那正是迴圈唯一可能的來源（新 from=舊、既有 from=新 ⇒ 環）。
      def register!(shop:, from_path:, to_path:)
        # 鏈坍縮：所有指向舊路徑的列改指新路徑（A→B ⇒ A→C）。
        UrlRedirect.where(shop_id: shop.id, to_path: from_path).update_all(to_path:)
        UrlRedirect.create!(shop_id: shop.id, from_path:, to_path:,
                            status_code: 301, source: "handle_change")
      end
    end
  end
end
