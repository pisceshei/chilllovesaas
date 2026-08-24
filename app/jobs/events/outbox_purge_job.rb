# frozen_string_literal: true

module Events
  # 終態列保留期 purge 的薄包裝（specs/18 F1-5；排程＝recurring.yml events_outbox_purge）。
  class OutboxPurgeJob < ApplicationJob
    queue_as :background

    def perform = Events::Relay.purge!
  end
end
