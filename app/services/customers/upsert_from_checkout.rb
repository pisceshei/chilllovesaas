# frozen_string_literal: true

module Customers
  # 訂單成立時的顧客建檔／回寫（16 §F6.1：email upsert；G6-7 接通
  # checkout→order→customer 資料鏈）。🔴 呼叫點在 `Orders::CreateFromCheckout`
  # 的 DB 交易內——純 DB 操作、無外部 IO（鐵律 5）。
  #
  # 語義（正典錨）：
  # - **email 為鍵 upsert**（16 §F6.1；`Customer.normalize_email` 收大小寫坑）；
  #   無 email ⇒ 不建檔、訂單不掛 customer（guest 無信箱形）。
  # - **併發安全**：撞 `uq_customers_email` ⇒ 重讀既有列（08 §F.3#1：恰一成功）。
  # - **統計欄增量**（orders_count／total_spent_cents／last_order_at）＝
  #   原子 SQL 增量（同交易；鐵律 7 同源三欄的唯一寫入者）。
  # - **行銷同意只升不降**（08 §C.4 consent 是 append-only 事實）：勾選 ⇒ 訂閱＋
  #   記 (updated_at, source="checkout")；未勾 ⇒ 不動既有訂閱——結帳頁沒有
  #   「取消訂閱」語義，退訂走顧客模組的 consent mutation。
  # - **識別欄只補空**：姓名／電話已有值不覆寫（訂單快照 ≠ 主檔編輯權）。
  # - **地址簿只在簿空時補**（06 §2：訂單面是快照；首單把快照補進地址簿設預設）。
  module UpsertFromCheckout
    module_function

    # @param checkout [Checkout] 已完成落庫的結帳（email／address／勾選已在）
    # @param order [Order] 剛建立的訂單（金額與 processed_at 已定）
    # @return [Customer, nil] 無 email 時回 nil（不建檔）
    def call(checkout:, order:)
      email = Customer.normalize_email(checkout.email)
      return nil if email.nil?

      customer = find_or_create(checkout, email)
      fill_identity!(customer, checkout.shipping_address)
      apply_consent!(customer, checkout)
      ensure_address!(customer, checkout.shipping_address)
      bump_stats!(customer, order)

      order.update_columns(customer_id: customer.id, updated_at: Time.current)
      checkout.update_columns(customer_id: customer.id, updated_at: Time.current)
      customer
    end

    def find_or_create(checkout, email)
      existing = Customer.find_by(shop_id: checkout.shop_id, email: email)
      return existing if existing

      Customer.create!(shop_id: checkout.shop_id, email: email,
                       currency: checkout.currency)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # 併發同 email 建檔：輸的一方改讀贏家（08 §F.3#1；DB unique 兜底）
      Customer.find_by!(shop_id: checkout.shop_id, email: email)
    end

    def fill_identity!(customer, address)
      updates = {}
      updates[:first_name] = address["first_name"] if customer.first_name.blank? && address["first_name"].present?
      updates[:last_name] = address["last_name"] if customer.last_name.blank? && address["last_name"].present?
      updates[:phone] = address["phone"].to_s.strip[0, 32] if customer.phone.blank? && address["phone"].present?
      customer.update!(**updates) if updates.any?
    end

    def apply_consent!(customer, checkout)
      return unless checkout.buyer_accepts_marketing
      return if customer.email_marketing_consent # 已訂閱：不重寫時間戳（最早同意時點保留）

      customer.update!(email_marketing_consent: true,
                       email_marketing_consent_updated_at: Time.current,
                       email_marketing_consent_source: "checkout")
    end

    def ensure_address!(customer, address)
      return if customer.customer_addresses.exists?
      return if address["address1"].blank? || address["city"].blank? || address["country_code"].blank?

      customer.customer_addresses.create!(
        shop_id: customer.shop_id,
        first_name: address["first_name"], last_name: address["last_name"],
        address1: address["address1"], address2: address["address2"].presence,
        city: address["city"], province: address["zone"].presence, # 87 §3 鍵名對映
        postal_code: address["postal_code"].presence.to_s[0, 32].presence,
        country_code: address["country_code"], phone: address["phone"].presence.to_s[0, 32].presence,
        default_address: true
      )
    end

    # 原子增量（鐵律 7 同源三欄唯一寫入端；併發下不丟計數——update_all 直發 SQL）。
    def bump_stats!(customer, order)
      Customer.where(id: customer.id).update_all(
        [ "orders_count = orders_count + 1, " \
          "total_spent_cents = total_spent_cents + ?, " \
          "last_order_at = ?, updated_at = ?",
          order.total_cents, order.processed_at || Time.current, Time.current ]
      )
    end
  end
end
