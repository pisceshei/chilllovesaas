# frozen_string_literal: true

module Events
  # outbox relay（第 19 包 §4.6；specs/18 F1-2 的 dispatcher）。
  #
  # ①這是什麼：把 event_outbox 的 pending 列取出「投遞」並標 published 的核心 service。
  #   可直呼（`Events::Relay.drain!`）——ActiveJob 只做薄包裝（Events::RelayJob），
  #   讓 rspec 不依賴 queue adapter（第 19 包 §4.7）。
  # ②取件語義：`FOR UPDATE SKIP LOCKED`（specs/18 F1-2；多實例不重複派發）＋
  #   locked_at 逾時回收（worker 死掉的孤兒，limits.events.outbox_lock_timeout_s）＋
  #   attempts 指數退避（available_at 後移 2^attempts 秒）＋
  #   attempts ≥ limits.events.outbox_dead_letter_attempts ⇒ status=dead（specs/18 F1-5）。
  # ③🔴 本包消費者路由表＝空（consumers_for 恆回 []）：「投遞」＝標 published。
  #   這讓 bt3 既有 pending 積壓被安全 drain（PR #115 假設 A5）。接真實消費者的包
  #   的開工前置＝先建 event_deliveries（63 §L-4 門檻，2026-08-24 寫死）。
  # ④租戶模式＝A 案（PR #115 假設 A4）：without_tenant 取件、按 shop_id 分組
  #   with_tenant 處理；租戶不得殘留到下一家店（spec 釘住）。
  # ⑤終態（published/failed/dead）一律清 dedupe_key（release-on-terminal）——
  #   「合併窗只在 pending 內」（63 §C.6）的機械保證。
  # ⑥觀測＝結構化 log 一行一事件（明文降級：specs/18 F1-5 的告警與 63 §C.3 的 metric
  #   不在本包，登記於第 19 包 worklog Pending——不是做完了）。
  # ⑦跨功能影響：event_outbox（唯一寫終態方）、config/recurring.yml（排程）、
  #   未來消費者包（consumers_for 是唯一掛載縫）。
  class Relay
    class << self
      # @param now [Time] 注入時鐘（測試逾時回收用）
      # @return [Integer] 本輪處理的事件數
      def drain!(now: Time.current)
        ids = ActsAsTenant.without_tenant { claim_batch(now) }
        return 0 if ids.empty?

        # 🔴 claim 用 update_all 寫 locked_at（繞過 dirty-tracking）⇒ 這裡重讀乾淨物件。
        #    沿用 claim 時的舊物件會讓 update!(locked_at: nil) 被 AR 判「回到載入值＝無變更」
        #    而漏出 UPDATE 語句（首輪 rspec 抓到的形態）。
        batch = ActsAsTenant.without_tenant { EventOutbox.where(id: ids).order(:id).to_a }

        # 按 shop 分組逐店處理：包內事件共享一次 with_tenant，
        # 任一店拋錯不得讓下一家店帶著錯的 tenant 跑（ensure 由 with_tenant 自身保證）。
        batch.group_by(&:shop_id).each_value do |events|
          shop = Shop.find(events.first.shop_id)
          ActsAsTenant.with_tenant(shop) do
            events.each { |event| deliver(event, now) }
          end
        end
        batch.size
      end

      # 保留期外的終態列 purge（specs/18 F1-5「保留 30 天」；dead 同受 purge＝假設 A2）。
      # @return [Integer] 刪除筆數
      def purge!(now: Time.current)
        cutoff = now - Limits.fetch(:events, :outbox_retention_days).days
        ActsAsTenant.without_tenant do
          EventOutbox.where(status: %w[published dead]).where(updated_at: ...cutoff).delete_all
        end
      end

      # 🔴 消費者路由的唯一掛載縫。本包恆空（§4.6③）；接消費者前先建 event_deliveries。
      # @return [Array<#call>]
      def consumers_for(_topic) = []

      private

      # 取件＝一個短 transaction：SKIP LOCKED 選定 → 標 locked_at → commit 釋放列鎖。
      # 之後的投遞在鎖外進行（慢消費者不得長押 InnoDB 列鎖）。
      def claim_batch(now)
        EventOutbox.transaction do
          timeout = Limits.fetch(:events, :outbox_lock_timeout_s)
          rows = EventOutbox
            .where(status: "pending")
            .where(available_at: ..now)
            .where("locked_at IS NULL OR locked_at < ?", now - timeout)
            .order(:id)
            .limit(Limits.fetch(:events, :outbox_batch_size))
            .lock("FOR UPDATE SKIP LOCKED")
            .to_a
          reclaimed = rows.count { |r| r.locked_at.present? }
          log(:outbox_reclaimed, count: reclaimed) if reclaimed.positive?
          EventOutbox.where(id: rows.map(&:id)).update_all(locked_at: now) if rows.any?
          rows.map(&:id)
        end
      end

      def deliver(event, now)
        consumers_for(event.topic).each { |consumer| consumer.call(event) }
        # 🔴 終態同時清 dedupe_key（release-on-terminal）：released 後同 key 的新事件
        #    開新列，不會 upsert 到已發布列上。
        event.update!(status: "published", published_at: now, locked_at: nil, dedupe_key: nil)
        log(:outbox_published, event)
      rescue StandardError => e
        attempts = event.attempts + 1
        if attempts >= Limits.fetch(:events, :outbox_dead_letter_attempts)
          event.update!(status: "dead", attempts: attempts, locked_at: nil,
                        dedupe_key: nil, last_error: e.message.to_s.first(1000))
          log(:outbox_dead, event)
        else
          event.update!(attempts: attempts, locked_at: nil,
                        available_at: now + (2**attempts).seconds,
                        last_error: e.message.to_s.first(1000))
          log(:outbox_retry, event)
        end
      end

      def log(kind, event = nil, **extra)
        fields = { event: kind }
        if event.is_a?(EventOutbox)
          fields.merge!(shop_id: event.shop_id, event_id: event.event_id,
                        topic: event.topic, attempts: event.attempts)
        end
        fields.merge!(extra)
        Rails.logger.info(fields.map { |k, v| "#{k}=#{v}" }.join(" "))
      end
    end
  end
end
