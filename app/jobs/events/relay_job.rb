# frozen_string_literal: true

module Events
  # Events::Relay.drain! 的 ActiveJob 薄包裝（第 19 包 §4.6/§4.7）。
  # 🔴 不是租戶 job（relay 是跨租戶掃描者，A 案；ApplicationJob 檔頭的
  #    「shop_id 第一參數」約定不適用）。排程＝config/recurring.yml events_relay。
  class RelayJob < ApplicationJob
    queue_as :default

    def perform = Events::Relay.drain!
  end
end
