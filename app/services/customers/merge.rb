# frozen_string_literal: true

module Customers
  # 顧客合併（G6 步 8b；官方 customerMerge 對位）。
  #
  # ①保留規則：官方不保證哪個留下（"don't guarantee which customer is kept"），
  #   唯一明文＝雙方都無 email 時留 customer_two（"This customer is kept when
  #   neither customer has an email address."）。我方定則（ours，PR 描述明載）：
  #   恰一方有 email ⇒ 留有 email 者；雙方都有 ⇒ 留 customer_one；都無 ⇒ 留 two。
  # ②hard blockers：官方 11 類（CustomerMergeErrorFieldType 逐字在
  #   docs/dev/g6-customer-mutations.md）。我方現制可判三類——
  #   REDACTED_AT（anonymized_at）／PENDING_DATA_REQUEST（redaction_scheduled_at）
  #   ／DELETED_AT（查無）；其餘八類（gift cards/store credit/subscriptions/
  #   company/payment methods/multipass/merge-in-progress/override）對應子系統
  #   尚不存在＝結構性不可能，落 91 §3.53。
  # ③搬移面（help 14 類的我方現制子集）：orders／checkouts／地址簿（保留方預設
  #   不動、被併方地址全轉非預設）／consent 事件（稽核軌跡跟人走）；
  #   note 串接（≤5000 官方上限）；tags 聯集（≤250）；空缺聯絡欄補值。
  # ④統計＝合併後**由訂單重算**（鐵律 7：不用兩邊快取相加——快取可能漂移）。
  # ⑤v1 同步交易制（官方非同步 job ⇒ ours 簡化，91 §3.53）；鎖序＝id 升冪防死鎖。
  class Merge
    Result = Data.define(:customer, :error)

    NOTE_LIMIT = 5000
    TAG_LIMIT = 250

    class << self
      def call(shop:, customer_one:, customer_two:)
        blocker = blocker_for(customer_one) || blocker_for(customer_two)
        return Result.new(customer: nil, error: blocker) if blocker
        if customer_one.id == customer_two.id
          return Result.new(customer: nil, error: [ "不能與自己合併。", "INVALID" ])
        end

        kept, discarded = pick_kept(customer_one, customer_two)

        ActiveRecord::Base.transaction do
          first, second = [ kept, discarded ].sort_by(&:id)
          first.lock!
          second.lock!

          Order.where(shop_id: shop.id, customer_id: discarded.id)
               .update_all(customer_id: kept.id)
          Checkout.where(shop_id: shop.id, customer_id: discarded.id)
                  .update_all(customer_id: kept.id)
          CustomerAddress.where(shop_id: shop.id, customer_id: discarded.id)
                         .update_all(customer_id: kept.id, default_address: false)
          # append-only 事件表跟人走（readonly? 擋 model 層 ⇒ 集合式 UPDATE）
          CustomerMarketingConsent.where(shop_id: shop.id, customer_id: discarded.id)
                                  .update_all(customer_id: kept.id)

          # 🔴 先算後刪再寫：merged_attrs 要讀被併方欄位，但 email/phone 有唯一索引
          # ——被併方還在時把它的 phone 寫進保留方會撞 uq（G4 測試實紅抓到的序）。
          attrs = merged_attrs(kept, discarded)
          discarded.destroy!
          kept.update!(attrs)
          recompute_stats!(shop, kept)
        end
        Result.new(customer: kept.reload, error: nil)
      end

      private

      def blocker_for(customer)
        return [ "個資已抹除的顧客不可合併（官方 REDACTED_AT）。", "INVALID_STATE" ] if customer.anonymized_at.present?
        return [ "有待執行抹除請求的顧客不可合併（官方 PENDING_DATA_REQUEST）。", "INVALID_STATE" ] if customer.redaction_scheduled_at.present?

        nil
      end

      def pick_kept(one, two)
        return [ one, two ] if one.email.present? && two.email.blank?
        return [ two, one ] if two.email.present? && one.email.blank?
        return [ two, one ] if one.email.blank? && two.email.blank? # 官方唯一明文

        [ one, two ] # 雙方都有 email ⇒ ours 定則
      end

      def merged_attrs(kept, discarded)
        note = [ kept.note, discarded.note ].compact_blank.join("\n").first(NOTE_LIMIT)
        tags = (Array(kept.tags) | Array(discarded.tags)).first(TAG_LIMIT)
        {
          note: note.presence, tags:,
          phone: kept.phone.presence || discarded.phone,
          first_name: kept.first_name.presence || discarded.first_name,
          last_name: kept.last_name.presence || discarded.last_name,
          email: kept.email.presence || discarded.email
        }
      end

      # 鐵律 7 同源：合併後統計由訂單重算，不信兩邊快取。
      def recompute_stats!(shop, kept)
        scope = Order.where(shop_id: shop.id, customer_id: kept.id)
        kept.update!(
          orders_count: scope.count,
          total_spent_cents: scope.sum(:total_cents),
          last_order_at: scope.maximum(:processed_at)
        )
      end
    end
  end
end
