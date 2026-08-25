# frozen_string_literal: true

module Catalog
  # handle 變更的重導掛鉤（第 6 包；62 §F.3）。商品與系列共用。
  #
  # ①這是什麼：改 handle 時在**同一 transaction** 登記 301，並做鏈坍縮。
  #
  # ②🔴 **不變量＝「redirect 的 from_path 永遠不是一個還活著的資源網址」**。
  #   它同時擋掉兩件事：
  #     - **鏈**：`{a→b, x→a}` 之所以是鏈，正因為 `a` 同時是 from_path 與 P2 的
  #       活 handle；擋住這個就沒有鏈。純表內的鏈（`{a→b, b→c}`）由**鏈坍縮**
  #       在寫入時消掉。
  #     - **活頁被遮蔽**：某商品的現任網址被別人的舊網址 301 轉走。
  #
  # ③🔴 **這是跨兩張表的不變量，只靠 check-then-act 在併發下必然破**
  #   （對抗審查 R6-3／P6-3 以實跑重現：R2 的檢查在 R1 commit 前跑、R2 的落庫在
  #   R1 commit 後 ⇒ 表裡出現鏈）。「活 handle」在 products／collections，
  #   「from_path」在 url_redirects，**沒有任何 DB 約束能跨表擋**。
  #   實測也證實 InnoDB 的 gap lock **關不了這個窗**：gap lock 彼此相容，
  #   兩個 `SELECT … FOR UPDATE` 都會通過（只有 INSERT 會被擋，而那只涵蓋
  #   兩種到達順序中的一種）。
  #   ⇒ 唯一可靠的做法是**單一序列化點**：改名操作在店級鎖下序列化
  #   （`serialize!`）。代價＝同一家店的改名彼此排隊；改名是商家手動、低頻動作，
  #   這個代價買到的是可證明的正確性。**不得**把它降級成「txn 內重查一次」——
  #   那只縮窗不關窗（同一個實跑腳本仍可重現）。
  #
  # ④跨功能影響：讀取者＝第 36 包的 301 引擎（因本不變量成立，它**不需要**
  #   迴圈偵測與 hop 追蹤，查一次表就回）與後台重導管理；寫入者＝
  #   `SaveProduct`／`SaveCollection` 的改名流程。新增任何「指派 handle」的
  #   路徑都必須經 `path_reserved?`（複驗＝`git grep -n "path_reserved?\|serialize!" app/`）。
  module HandleChange
    # 併發改名撞上（序列化後才看得見的狀態）⇒ 呼叫端轉 userErrors，不外洩。
    class Raced < StandardError; end

    # 資源類型 → (URL 前綴, model)。新增可改名的資源類型時在這裡加一列，
    # 兩個服務就都吃得到（不要在呼叫端各寫一份前綴字串）。
    RESOURCES = {
      product: { prefix: "/products", model: "Product" },
      collection: { prefix: "/collections", model: "Collection" }
    }.freeze

    class << self
      # @return [String] 該資源的正規路徑（無 locale 前綴——62 §F.3）
      def path_for(resource, handle) = "#{RESOURCES.fetch(resource).fetch(:prefix)}/#{handle}"

      # 這條路徑是否已被重導佔用（＝某個舊 handle 的網址）。
      # 🔴 這是 pre-flight 檢查（transaction 外、無鎖）：擋掉絕大多數情形並給出
      #   好的錯誤訊息，但**它不是不變量的守衛**——守衛是 `serialize!` ＋
      #   `register!` 內的複查（見檔頭③）。
      def path_reserved?(shop, path)
        UrlRedirect.where(shop_id: shop.id, from_path: path).exists?
      end

      # 🔴 取得店級序列化鎖。**必須在呼叫端的 transaction 內、且在改名相關的
      #   任何檢查之前**呼叫（見檔頭③）。
      #   鎖序：呼叫端已持有自己資源列的 FOR UPDATE，之後才取店列 ⇒ 全倉一致
      #   （沒有任何路徑是「先店後資源」），因此不成環、不會死鎖。
      def serialize!(shop)
        Shop.lock.find_by(id: shop.id) || raise(ActiveRecord::RecordNotFound)
      end

      # 在呼叫端的 transaction 內登記改名重導＋鏈坍縮。
      #
      # 前置：①已呼叫 `serialize!` ②呼叫端已把資源改名並存檔。
      # @raise [Raced] 序列化後才看得見的衝突（新路徑被佔／舊 handle 已被別人拿走）
      def register!(shop:, resource:, old_handle:, new_handle:)
        from_path = path_for(resource, old_handle)
        to_path = path_for(resource, new_handle)
        model = RESOURCES.fetch(resource).fetch(:model).constantize

        # 🔴 兩道複查都用**鎖定讀**（`.lock`）不用普通讀：REPEATABLE READ 下普通讀
        #   吃的是本 txn 的快照，看不到我們在等店級鎖期間對方 commit 的資料——
        #   那正是要防的那個到達順序。鎖定讀一律讀最新已提交版本。
        #
        # 複查一：新路徑不得是既有 from_path（pre-flight 查過，但那在鎖外）。
        raise Raced if UrlRedirect.lock.where(shop_id: shop.id, from_path: to_path).exists?
        # 複查二：舊 handle 不得已被**別的**活資源拿走——否則我們正要建立的
        #   from_path 會遮蔽它的現任頁面（對方先 commit 取走 handle、我們才插 redirect）。
        # ⚠️ **在店級鎖下這條構造上不可達**（突變驗證：刪掉它測試不會紅）。
        #   留著的理由是 fail-closed：日後若有人新增一條改名路徑而忘了 `serialize!`，
        #   這條會把「活頁被遮蔽」擋成 userError 而不是靜默損壞。
        #   🔴 **不得**因此宣稱它是承重守衛——承重的是 `serialize!`（見檔頭③）。
        raise Raced if model.lock.where(shop_id: shop.id, handle: old_handle).exists?

        # 鏈坍縮：所有指向舊路徑的列改指新路徑（A→B ⇒ A→C）。
        UrlRedirect.where(shop_id: shop.id, to_path: from_path).update_all(to_path:)
        UrlRedirect.create!(shop_id: shop.id, from_path:, to_path:,
                            status_code: 301, source: "handle_change")
      end
    end
  end
end
