# frozen_string_literal: true

module Publications
  # 排程到點 → 對外上架事件的轉譯器（S8；D74）。
  #
  # ①這是什麼：`product.publication.changed` 的**第二個**消費者（第一個＝PR-C 的
  #   `ScheduledPublicationConsumer`，只管 cache stamp）。本消費者只做一件事：
  #   到點時把「排程發布」轉成對外 `product_listings/add`（變體＝ours 的
  #   `variant_listings/add`）。官方錨（取證 2026-08-27，scheduled-product-publishing 頁）
  #   逐字：`At the scheduled datetime, Shopify sends a product_listing/add event.`
  # ②判準（🔴 刻意**不**比對 payload 的 `published_at`）：
  #   同一 topic 的兩個消費者處理順序不保證，而 PR-C 消費者在到點時會**改寫**
  #   `published_at`（合格⇒處理當刻；不合格⇒NULL）。若本消費者照 PR-C 的
  #   `same_second?` 比對，排在它之後跑（或重試晚到）時每一筆合法事件都會被
  #   誤判成 superseded ⇒ ADD 永遠不發。改用 **DB 現值的可發布性**判定：
  #   列存在 ∧ `published_at` 現在已生效 ∧ ADD 閘（PURCHASABLE）⇒ 發。
  #   兩種消費順序下這個判準都收斂到同一個答案：
  #   - 先跑（PR-C 未改寫）：published_at＝原排程時點（已到）⇒ 發；
  #   - 後跑（PR-C 已改寫）：合格列＝處理當刻（已到）⇒ 發；不合格列＝NULL ⇒ 不發。
  # ③冪等：at-least-once 下重叫用 `dedupe_key = "listing-add:<event_id>"` 收斂
  #   （`uq_event_outbox_dedupe_key` 唯一索引擋重複 INSERT ⇒ rescue 成 no-op）。
  # ④明確不做：
  #   - `status_transition` 形狀 ⇒ no-op（狀態翻轉該不該補發逐管道 ADD/REMOVE
  #     ＝需要逐管道 diff，本尊語義未取得；登記 `docs/specs/91` §3.45）。
  #   - Collection ⇒ no-op（本尊無 collection listing topic，2026-08-28 掃描）。
  #   - 不 bump stamp、不改任何 `resource_publications` 列（那是 PR-C 的射程）。
  #   - 不合格分支一律 return ＋ 結構化 log，禁 raise（D53「三條最容易做錯的」第 2 條）。
  module ListingEventTranslator
    module_function

    # 進 `event_deliveries.consumer` 的具名身分（改名＝全部事件重放）。
    def name = "publications.listing_translator"

    # @param event [EventOutbox]
    # @return [void]
    def call(event)
      payload = event.payload
      return log(event, decision: :status_transition_skipped) if payload.key?("status_transition")
      return log(event, decision: :unknown_payload) unless payload.key?("publication_id")

      row = ActsAsTenant.without_tenant do
        ResourcePublication.find_by(
          shop_id: event.shop_id,
          publication_id: payload["publication_id"],
          publishable_type: payload["publishable_type"],
          publishable_id: payload["publishable_id"]
        )
      end
      return log(event, decision: :row_gone) if row.nil?
      return log(event, decision: :collection_not_applicable) if row.publishable_type == "Collection"
      return log(event, decision: :not_published_yet) unless row.published_at.present? && row.published_at <= Time.current
      return log(event, decision: :not_purchasable) unless addable?(event, row)

      emit_add!(event, row)
    end

    # ADD 的 active 閘（官方逐字 "an active product"；判準＝PURCHASABLE，與 D53 同集合；
    # 變體看父商品——變體無 status 欄，鏡射 D53 F1-⑤(b)(c)）。
    def addable?(event, row)
      status = ActsAsTenant.without_tenant do
        case row.publishable_type
        when "Product"
          Product.where(shop_id: event.shop_id, id: row.publishable_id).pick(:status)
        when "ProductVariant"
          Product.joins(:product_variants)
                 .where(shop_id: event.shop_id, product_variants: { id: row.publishable_id })
                 .pick(:status)
        end
      end
      status.present? && Product::PURCHASABLE_STATUSES.include?(status.downcase)
    end

    # @note 副作用：INSERT 一筆對外 ADD 事件（dedupe_key 擋重放的重複 INSERT）。
    def emit_add!(event, row)
      topic = row.publishable_type == "ProductVariant" ? Events::Topics::VARIANT_LISTINGS_ADD : Events::Topics::PRODUCT_LISTINGS_ADD
      # 消費者可能在任意租戶脈絡下被叫（relay 批次跨店）⇒ 與本檔讀取端同紀律：
      # without_tenant ＋ 明確 shop_id。
      ActsAsTenant.without_tenant do
      EventOutbox.create!(
        shop_id: event.shop_id,
        event_id: SecureRandom.uuid,
        topic: topic,
        aggregate_type: row.publishable_type,
        aggregate_id: row.publishable_id,
        payload: {
          publication_id: row.publication_id,
          publishable_type: row.publishable_type,
          publishable_id: row.publishable_id,
          occurred_at: Time.current.utc.iso8601
        },
        available_at: Time.current,
        dedupe_key: "listing-add:#{event.event_id}",
        status: "pending"
      )
      end
      log(event, decision: :listed)
    rescue ActiveRecord::RecordNotUnique
      # at-least-once 重叫：同一筆到點事件已轉譯過 ⇒ no-op（冪等收斂）。
      log(event, decision: :already_listed)
    end

    def log(event, decision:)
      Rails.logger.info(
        {
          consumer: name, event_id: event.event_id, topic: event.topic,
          aggregate_type: event.aggregate_type, aggregate_id: event.aggregate_id,
          decision: decision
        }.to_json
      )
    end
  end
end
