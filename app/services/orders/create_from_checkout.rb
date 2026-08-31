# frozen_string_literal: true

module Orders
  # 訂單成立（15-F5——整條結帳線最關鍵的一個 transaction；G6-0(a) 落 manual 形，
  # PSP capture／authorize 形隨 G6-1/G6-2 接上）。
  #
  # ①🔴 commit 掛「訂單成立」事件、不掛付款 SUCCESS 回呼（F5 標題 2026-08-17 更正）：
  #   manual（bank deposit／COD）單成立時付款是 PENDING，但庫存**此刻就要佔**——
  #   掛付款回呼＝COD 單完全不占庫存＝超賣。
  # ②冪等兩層（F5 步 1）：Idempotency::Guard（key＋參數指紋；claim/replay 狀態機）
  #   ＋ orders.checkout_id 唯一索引 DB 兜底（漏帶 key 的併發雙擊）。
  # ③單一 transaction、🔴 鎖序全專案固定：鎖 checkout（FOR UPDATE，open→completed
  #   條件轉移）→ **shop counter**（UPDATE +1 讀回，鎖序首位）→ **inventory**
  #   （逐行條件式 available−/committed+，level 按 id 升冪）→ 建 order＋line_items
  #   （快照）＋transaction 列（manual：kind=sale/status=pending/金額＝checkout 應收）
  #   → timeline event → outbox orders/create（同 transaction，11 §8）→ cart 刪除
  #   （同 transaction——commit 後清理前崩潰＝買家帶已購件二次下單，F5 步 5）。
  #   寄信在 transaction 外（v1 不對外發信 ⇒ 僅留掛載點註記）。
  # ④庫存不足（tracked ∧ policy=deny ∧ available<qty）⇒ 整單 raise → rollback
  #   （F5 步 3；此刻無已收款 ⇒ 無退款分支）；policy=continue ⇒ 允許負 available。
  # ⑤🔴 manual 形不發 orders/paid（付清由 markAsPaid／capture 路徑補發——F5 步 2）。
  module CreateFromCheckout
    Error = Class.new(StandardError)
    # 帶機器碼的業務失敗（controller 轉 422 文案；code 進 userErrors 對位）。
    class Failure < Error
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    MUTATION_NAME = "OrdersCreateFromCheckout"

    module_function

    # @param shop [Shop]
    # @param checkout_token [String]
    # @param idempotency_key [String] 顯式冪等鍵（鐵律 5「訂單成立必帶」）
    # @param cart [Cart, nil] 買家當前 cart（同 transaction 刪除；F5 步 5）
    # @return [Hash] Guard outcome：{ replayed:, resource: Order, user_errors: [] }
    # @raise [Idempotency::Guard::Conflict] 併發撞 key／參數不符
    # @raise [Failure] 庫存不足等業務失敗（transaction 已回滾）
    def call(shop:, checkout_token:, idempotency_key:, cart: nil)
      Idempotency::Guard.with(
        shop:, key: idempotency_key, mutation_name: MUTATION_NAME,
        input: { checkout_token: checkout_token }
      ) do
        create!(shop:, checkout_token:, cart:)
      end
    end

    # @return [Array(Order, Array)] Guard block 契約 [resource, user_errors]
    def create!(shop:, checkout_token:, cart:)
      ActsAsTenant.with_tenant(shop) do
        ActiveRecord::Base.transaction do
          checkout = Checkout.lock("FOR UPDATE")
                             .find_by(shop_id: shop.id, token: checkout_token)
          raise Failure.new("CHECKOUT_NOT_FOUND", "找不到這筆結帳。") if checkout.nil?

          if checkout.status == "completed"
            # DB 兜底層命中（另一把 key 或漏帶 key 的重複提交）：回既有訂單。
            existing = Order.find_by(shop_id: shop.id, checkout_id: checkout.id)
            raise Failure.new("CHECKOUT_NOT_OPEN", "這筆結帳已結束。") if existing.nil?

            next [ existing, [] ]
          end
          raise Failure.new("CHECKOUT_NOT_OPEN", "這筆結帳已結束。") unless checkout.status == "open"

          ensure_ready!(checkout)

          # open→completed 條件轉移（FOR UPDATE 已互斥；條件式 UPDATE 是第二道，
          # 殺「讀舊快照直接改」的回歸——affected 0 ⇒ 競態輸家）。
          moved = Checkout.where(id: checkout.id, status: "open")
                          .update_all(status: "completed", completed_at: Time.current)
          raise Failure.new("CHECKOUT_NOT_OPEN", "這筆結帳已結束。") if moved.zero?

          number = next_order_number!(shop) # 🔴 鎖序首位（先 counter 後 inventory）
          variants = load_variants(shop, checkout)
          deduct_inventory!(shop, checkout, variants)

          order = build_order!(shop, checkout, number)
          build_line_items!(shop, order, checkout, variants)
          build_manual_transaction!(shop, order, checkout)
          # G6-7（16 §F6.1）：email upsert 建檔＋統計增量＋consent／地址回寫；
          # 同交易純 DB（鐵律 5）；無 email ⇒ 回 nil、訂單不掛 customer。
          Customers::UpsertFromCheckout.call(checkout:, order:)

          Event.create!(shop_id: shop.id, order_id: order.id, kind: "order.placed",
                        happened_at: Time.current,
                        metadata: { "checkout_token" => checkout.token,
                                    "payment_method" => checkout.payment_method_snapshot["method_type"] })
          enqueue_orders_create!(order)

          cart&.destroy! # F5 步 5：同 transaction；abandoned_at 保留不清

          [ order, [] ]
        end
      end
    end

    # 成立前置（F3-4 同一道 gate 的 v1 面）：需運送的車必須已選費率；
    # 有可用付款方式時必須已選（零方式＝結帳頁本來就顯示無法付款）。
    def ensure_ready!(checkout)
      requires_shipping = checkout.line_items_snapshot.any? { |l| l.fetch("requires_shipping", true) }
      if requires_shipping && checkout.shipping_lines.blank?
        raise Failure.new("SHIPPING_NOT_SELECTED", "請先選擇運送方式。")
      end
      return if checkout.payment_method_snapshot.present? && checkout.payment_method_snapshot["method_type"].present?

      raise Failure.new("PAYMENT_METHOD_NOT_SELECTED", "請先選擇付款方式。")
    end

    # 每店連號（F5 步 4）：交易內原子 +1 後讀回；此 UPDATE 同時取得 shops 列鎖＝
    # 全專案鎖序首位。
    def next_order_number!(shop)
      Shop.where(id: shop.id).update_all("order_counter = order_counter + 1")
      Shop.where(id: shop.id).pick(:order_counter)
    end

    def load_variants(shop, checkout)
      ids = checkout.line_items_snapshot.map { |l| l["variant_id"] }.compact
      ProductVariant.where(shop_id: shop.id, id: ids)
                    .includes(:product, inventory_item: :inventory_levels)
                    .index_by(&:id)
    end

    # 逐行條件式扣庫存（13-F5：available−／committed+）。
    # 🔴 全部走**條件式 UPDATE**、不先 SELECT 再算（F4.1(d) 同紀律）：
    #   deny ⇒ `available >= qty` 進 WHERE，affected 0＝庫存不足 ⇒ 整單 raise；
    #   continue ⇒ 無下限條件（允許負 available——商家明示允許超賣）。
    # level 選擇 v1＝地點 priority 最高的一列；多行按 level id 升冪執行（鎖序穩定）。
    def deduct_inventory!(shop, checkout, variants)
      priorities = Location.where(shop_id: shop.id).pluck(:id, :priority).to_h
      plan = checkout.line_items_snapshot.filter_map do |line|
        variant = variants[line["variant_id"]]
        next if variant.nil? # 變體已刪：快照照建單，不佔庫存（庫存主體已不存在）
        next unless variant.inventory_item&.tracked

        level = variant.inventory_item.inventory_levels
                       .min_by { |l| [ priorities[l.location_id] || 0, l.id ] }
        next if level.nil?

        { level_id: level.id, quantity: line["quantity"], policy: variant.inventory_policy,
          title: line["title"] }
      end

      plan.sort_by { |p| p[:level_id] }.each do |p|
        scope = InventoryLevel.where(shop_id: shop.id, id: p[:level_id])
        scope = scope.where("available >= ?", p[:quantity]) if p[:policy] == "deny"
        affected = scope.update_all([ "available = available - ?, committed = committed + ?",
                                      p[:quantity], p[:quantity] ])
        next unless affected.zero?

        raise Failure.new("INSUFFICIENT_INVENTORY", "「#{p[:title]}」庫存不足，訂單未成立。")
      end
    end

    def build_order!(shop, order_checkout, number)
      country = order_checkout.shipping_address["country_code"].to_s
      Order.create!(
        shop_id: shop.id,
        checkout_id: order_checkout.id,
        name: "##{number}",
        order_number: number,
        email: order_checkout.email,
        buyer_accepts_marketing: order_checkout.buyer_accepts_marketing, # G6-7：勾選快照傳導
        currency: order_checkout.currency,
        presentment_currency: order_checkout.presentment_currency,
        subtotal_cents: order_checkout.subtotal_cents,
        discount_cents: order_checkout.discount_cents,
        shipping_cents: order_checkout.shipping_cents,
        tax_cents: order_checkout.tax_cents,
        total_cents: order_checkout.total_cents,
        presentment_total_cents: order_checkout.presentment_total_cents,
        shipping_address: order_checkout.shipping_address,
        billing_address: order_checkout.billing_address,
        financial_status: "pending", # manual 形（86 §3 官方句：marked as Pending）
        fulfillment_status: "unfulfilled",
        status: "open",
        # 法域快照（鐵律 11）：seller＝基準法域 HK；buyer 依收貨國（pack 碼小寫），
        # 無法對映的國家先落國碼小寫（法域 pack 擴充時對映表接手——登記 ours）。
        seller_jurisdiction: "hk",
        buyer_jurisdiction: country.present? ? country.downcase : "hk",
        processed_at: Time.current
      )
    end

    # G6-8（步 5）：建單即物化 FO——本尊訂單一成立就有 FulfillmentOrder
    #（官方句「Fulfillment orders represent the work which is intended to be done
    # in relation to an order.」，取證 2026-09-01）。v1＝每單一張、單地點
    #（location 選擇同 deduct_inventory! 的 priority 規則）。既有訂單由
    # migration 20260901010000 回填。
    def materialize_fulfillment_order!(shop, order)
      location = Location.where(shop_id: shop.id).order(priority: :desc, id: :asc).first
      return if location.nil? # 無地點的店不建 FO（出貨線需要地點；登記於 dev doc）

      FulfillmentOrder.create!(shop_id: shop.id, order_id: order.id,
                               location_id: location.id, status: "open",
                               request_status: "unsubmitted")
    end

    def build_line_items!(shop, order, order_checkout, variants)
 materialize_fulfillment_order!(shop, order)
      order_checkout.line_items_snapshot.each do |line|
        variant = variants[line["variant_id"]]
        quantity = line.fetch("quantity")
        unit = line.fetch("unit_price_cents")
        LineItem.create!(
          shop_id: shop.id,
          order_id: order.id,
          product_variant_id: variant&.id,
          title: line.fetch("title"),
          variant_title: line["variant_title"],
          sku: variant&.sku,
          vendor: variant&.product&.vendor,
          product_type: variant&.product&.product_type,
          quantity: quantity,
          fulfillable_quantity: quantity,
          unit_price_cents: unit,
          total_cents: unit * quantity, # v1 無行級折扣（F2.1(f) 捨入位置：純整數乘加）
          total_discount_cents: 0,
          tax_cents: 0,
          currency: order_checkout.currency,
          requires_shipping: line.fetch("requires_shipping", true),
          taxable: true,
          properties: line["properties"] || {}
        )
      end
    end

    # manual 形 transaction（F5 步 2 三形之三）：kind=sale／status=pending／
    # 金額＝checkout 應收（R1 cents 直通——manual 無 PSP 表示法轉換）。
    def build_manual_transaction!(shop, order, order_checkout)
      OrderTransaction.create!(
        shop_id: shop.id,
        order_id: order.id,
        kind: "sale",
        status: "pending",
        # G6-1c：PSP 快照 gateway＝實際承作方（provider）；manual 沿用 method_type。
        gateway: order_checkout.payment_method_snapshot["provider"] ||
                 order_checkout.payment_method_snapshot.fetch("method_type"),
        amount_cents: order_checkout.total_cents,
        currency: order_checkout.currency,
        idempotency_key: "sale-#{order_checkout.token}"
      )
    end

    def enqueue_orders_create!(order)
      EventOutbox.create!(
        event_id: SecureRandom.uuid,
        topic: Events::Topics::ORDERS_CREATE,
        aggregate_type: "Order",
        aggregate_id: order.id,
        payload: { order_id: order.id, order_number: order.order_number,
                   total_cents: order.total_cents, currency: order.currency,
                   financial_status: order.financial_status },
        available_at: Time.current,
        status: "pending"
      )
      # 🔴 不發 orders/paid：manual 形付清走 markAsPaid 路徑再補發（F5 步 2）。
    end
  end
end
