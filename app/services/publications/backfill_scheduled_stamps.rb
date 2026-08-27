# frozen_string_literal: true

module Publications
  # 一次性 backfill：修復「PR-C 之前已被消化掉的排程事件」（D53／handoff §5）。
  #
  # ①這是什麼：S5（PR #151）起就在投排程事件，而 `Events::Consumers::REGISTRY`
  #   在 PR-C 之前沒有 `PRODUCT_PUBLICATION_CHANGED` ⇒ `deliver_to_consumers!` 開頭
  #   `return if consumers.empty?` ⇒ 這些事件到點被 relay 取走、派給零個消費者、
  #   直接標成 `published`——接上消費者也**重放不到**（delivery 帳從未建立、事件已終態）。
  #   `docs/dev/m2-publishable-write.md` §4.3 明文「PR-C 必須處理」的就是這件事。
  # ②具體功能：掃 `resource_publications` 中 `published_at` 已到（≤ now）、
  #   `publishable_type = "Product"`、且對應商品 `publications_updated_at` 落後於
  #   `published_at` 者，把 stamp 補到 `published_at`。資格閘與消費者同一條
  #   （`status ∈ Product::PURCHASABLE_STATUSES`）——現值不合格者不補，
  #   等它改回 ACTIVE 時由 `status_transition` 事件路徑 bump（D53 F2 catch-up 三層）。
  # ③怎麼做出來：🔴 **冪等靠 `at: row.published_at`**——補完 stamp ≥ published_at，
  #   重跑時 `stamp < published_at` 不再成立 ⇒ 不再前進（T22 的判準）。
  #   用 `Time.current` 當 at 就不冪等（每跑一次前進一次）。
  #   同商品多管道多列：逐列判定，最終收斂到 max(published_at)，重跑仍冪等。
  #   ProductVariant 列不掃（官方明文變體不可排程；立即發布的列在寫入當刻已同步 bump，
  #   `stamp < published_at` 不成立，天然不在掃描結果裡）。
  #   🔴 **跑完即結案，不是常駐 sweeper**（`m2-resource-publication-semantics.md` §6 禁令；
  #   不得掛到 `catalog:resync:publications`——該 task 零實作，`91` §3.23）。
  # ④跨功能影響：`products.publications_updated_at`（與消費者同一個唯一副作用）、
  #   `lib/tasks/publications.rake`（部署後手動執行的入口）。不動 `event_outbox`
  #   （那些事件已終態，帳不改——本服務修的是 stamp 這個**結果**，不是事件史）。
  class BackfillScheduledStamps
    class << self
      # @param now [Time] 掃描的「已到點」邊界（測試注入用；生產取當下）
      # @return [Hash] `{scanned:, bumped:}`——營運核對用的計數
      def call(now: Time.current)
        scanned = 0
        bumped = 0
        ActsAsTenant.without_tenant do
          ResourcePublication
            .where(publishable_type: "Product")
            .where(published_at: ..now)
            .find_each do |row|
              scanned += 1
              bumped += 1 if bump_if_stale(row)
            end
        end
        Rails.logger.info("event=backfill_scheduled_stamps scanned=#{scanned} bumped=#{bumped}")
        { scanned:, bumped: }
      end

      private

      # @return [Boolean] 是否實際前進了 stamp
      def bump_if_stale(row)
        stamp, status = Product.where(shop_id: row.shop_id, id: row.publishable_id)
                               .pick(:publications_updated_at, :status)
        return false if status.nil?                                  # 商品已刪：事件比資料活得久，不是錯誤
        return false unless Product::PURCHASABLE_STATUSES.include?(status)
        return false if stamp.present? && stamp >= row.published_at  # 已補過／已有更晚的真實變動

        Product.bump_publications_stamp!(shop_id: row.shop_id, id: row.publishable_id,
                                         at: row.published_at)
        true
      end
    end
  end
end
