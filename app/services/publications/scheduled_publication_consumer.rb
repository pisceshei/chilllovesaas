# frozen_string_literal: true

module Publications
  # 排程發布到點的消費者（PR-C；D53 五格的執行面）。
  #
  # ①這是什麼：`product.publication.changed` 的 outbox 消費者。同一 topic 有兩個
  #   真實生產者、兩種 payload 形狀（🔴 D53「三條最容易做錯的」第 3 條）：
  #   - `Publications::Write#enqueue_scheduled_event!`（S5）：
  #     `{publication_id, publishable_type, publishable_id, published_at, scheduled: true}`，
  #     `available_at` ＝ 未來的 `published_at`（到點才被 relay 取件）。
  #   - `Catalog::StatusTransition`：`{product_id, resource_version, status_transition: {from, to}}`，
  #     **沒有 `publication_id`**，`available_at = Time.current`。
  # ②具體功能：到點那一刻只做 D53 §3.1 的五項——重讀 DB 現值（payload 只作定位）、
  #   列不存在／已改期 ⇒ no-op、依 publishable_type 分流取 status、
  #   `status ∈ Product::PURCHASABLE_STATUSES`（＝{active, unlisted}）⇒ bump cache stamp。
  #   `status_transition` 形狀 ⇒ 商品級 bump（狀態轉移兩個方向都改變可見性，無資格閘）。
  #   🔴 判準是**可見性軸**不是 `== ACTIVE`：UNLISTED 官方逐字
  #   `The product is active but you need a direct link to view it.`（ProductStatus enum，
  #   取證 2026-08-27）——寫 `!= ACTIVE` 的事故形態＝UNLISTED 商品到點後前台已可購買
  #   但快取永不失效（D53 F1）。
  # ③怎麼做出來：唯一副作用＝`Product.bump_publications_stamp!`（at: 到點處理當刻，
  #   不是 payload 的 publishDate——與 S5「stamp 寫現在不寫未來」同一條紀律）。
  #   🔴 **不合格分支一律 return、禁止 raise**（D53「三條最容易做錯的」第 2 條）：
  #   `Events::Relay#deliver` 只有兩條出口，raise 表達「條件不合」會讓每筆不合格排程
  #   燒掉 2/4/8/16/32/64/128 秒的退避重試、在 `event_outbox.last_error` 留假錯誤、
  #   最終進 dead 表被營運當真事故。每個分支寫一行結構化 log（F1-⑤(d)：
  #   `event_id / topic / publishable_type / publishable_id / status / decision`），
  #   否則「條件不合 no-op」與「消費者沒被觸發」在測試上不可分辨（裁定書 §4.2）。
  #   明確不做（D53 §3.2）：不 UPDATE `published_at`、不翻 `products.status`、
  #   不建/刪發布列、不掃 due 列、不加 max-age、不改 `relay.rb`。
  # ④跨功能影響：`Events::Consumers::REGISTRY`（本消費者的唯一掛載點）、
  #   `Publications::Write`／`Catalog::StatusTransition`（兩個生產者，契約不動）、
  #   `products.publications_updated_at`（前台快取 stamp 的唯一消費面）、
  #   `Publications::BackfillScheduledStamps`（補 PR-C 之前被零消費者消化掉的事件）。
  #   catch-up（D53 F2）：不自動補發布——DRAFT 錯過時點後改回 ACTIVE 的那一刻，
  #   可見性由查詢層自然成立（`published_at <= now` 已真），本消費者只在收到
  #   `status_transition` 事件時 bump stamp 讓快取失效。
  module ScheduledPublicationConsumer
    module_function

    # 進 `event_deliveries.consumer` 的具名身分（改名＝全部事件重放，Consumers 檔頭契約）。
    def name = "publications.scheduled_stamp"

    # @param event [EventOutbox]
    # @return [void]（冪等：at-least-once 下重叫收斂——stamp bump 是單調前進的賦值）
    def call(event)
      payload = event.payload
      if payload.key?("status_transition")
        handle_status_transition(event, payload)
      elsif payload.key?("publication_id")
        handle_scheduled(event, payload)
      else
        # 未知形狀 ⇒ fail-closed：no-op ＋ log，不 raise（D53 §3.1 末段）。
        log(event, decision: :unknown_payload)
      end
    end

    # S5 排程 payload：到點副作用的主路徑。
    def handle_scheduled(event, payload)
      row = ActsAsTenant.without_tenant do
        ResourcePublication.find_by(
          shop_id: event.shop_id,
          publication_id: payload["publication_id"],
          publishable_type: payload["publishable_type"],
          publishable_id: payload["publishable_id"]
        )
      end
      return log(event, decision: :row_gone) if row.nil?
      # 改期＝同一列已有更晚（或更早）的新 `published_at`，舊時點那筆事件作廢。
      # 🔴 比對到**秒**：payload 走 `utc.iso8601`（秒級），DB 欄位是 datetime(6)——
      #   直接 `==` 會因微秒差把每一筆合法事件都誤判成 superseded。
      return log(event, decision: :superseded) unless same_second?(row.published_at, payload["published_at"])

      case row.publishable_type
      when "Collection"
        # Collection 無 status 軸、無 stamp 落點——本規則不適用（D53 F1）。
        log(event, decision: :no_stamp_target)
      when "Product", "ProductVariant"
        product_id = resolve_product_id(event.shop_id, row)
        return log(event, decision: :row_gone) if product_id.nil?

        status = ActsAsTenant.without_tenant do
          Product.where(shop_id: event.shop_id, id: product_id).pick(:status)
        end
        return log(event, decision: :row_gone, product_id:) if status.nil?

        if Product::PURCHASABLE_STATUSES.include?(status)
          Product.bump_publications_stamp!(shop_id: event.shop_id, id: product_id, at: Time.current)
          log(event, decision: :bumped, status:, product_id:)
        else
          log(event, decision: :not_purchasable, status:, product_id:)
        end
      else
        log(event, decision: :unknown_payload)
      end
    end

    # `Catalog::StatusTransition` payload：商品級 bump（不帶 publication_id，
    # 不得重放任何 per-channel 副作用，D53 §3.1「另一種 payload」段）。
    # 無資格閘——status 轉移**兩個方向**都改變可見性（active→draft 也要讓快取失效）。
    def handle_status_transition(event, payload)
      product_id = payload["product_id"]
      return log(event, decision: :unknown_payload) if product_id.nil?

      exists = ActsAsTenant.without_tenant do
        Product.where(shop_id: event.shop_id, id: product_id).exists?
      end
      return log(event, decision: :row_gone, product_id:) unless exists

      Product.bump_publications_stamp!(shop_id: event.shop_id, id: product_id, at: Time.current)
      log(event, decision: :bumped, product_id:)
    end

    # 秒級等值（見 handle_scheduled 內註）。任一邊缺值＝不可比 ⇒ 視為已改期。
    def same_second?(db_value, payload_value)
      return false if db_value.nil? || payload_value.blank?

      db_value.to_i == Time.iso8601(payload_value).to_i
    rescue ArgumentError
      false
    end

    # ProductVariant 列讀**父商品**（變體無 status 欄；官方明文變體不可排程 ⇒
    # 實務上不會出現，但分支必須存在且不得炸——D53 §3.1 第 4 項）。
    def resolve_product_id(shop_id, row)
      return row.publishable_id if row.publishable_type == "Product"

      ActsAsTenant.without_tenant do
        ProductVariant.where(shop_id:, id: row.publishable_id).pick(:product_id)
      end
    end

    # 與 `Events::Relay#log` 同形（k=v 單行），欄位集依 D53 F1-⑤(d)。
    def log(event, decision:, **extra)
      fields = {
        event: "scheduled_publication", event_id: event.event_id, topic: event.topic,
        publishable_type: event.aggregate_type, publishable_id: event.aggregate_id,
        decision: decision
      }.merge(extra)
      Rails.logger.info(fields.map { |k, v| "#{k}=#{v}" }.join(" "))
      nil
    end
  end
end
