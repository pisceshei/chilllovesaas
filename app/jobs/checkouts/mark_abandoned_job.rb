# frozen_string_literal: true

module Checkouts
  # 棄單標記 job（G6 步 7；recurring.yml 每 5 分鐘）。
  #
  # ①判定＝官方逐字（89 §6）："A checkout is considered abandoned if it remains
  #   incomplete for more than ten minutes after the customer has provided their
  #   email information."——status=open ∧ email 非空 ∧ 最後活動超過
  #   limits checkout.abandoned_after_minutes ∧ 尚未標記。
  # ②「最後活動」以 updated_at 近似（結帳每步 PATCH 都 touch；ours 簡化——
  #   官方未公開內部判定欄）。
  # ③跨租戶平台 job（Events::Relay 同款 without_tenant + 集合式 UPDATE；
  #   冪等：abandoned_at IS NULL 條件天然防重複標記）。
  class MarkAbandonedJob < ApplicationJob
    queue_as :background

    def perform
      threshold = Limits.fetch(:checkout, :abandoned_after_minutes).to_i.minutes.ago
      ActsAsTenant.without_tenant do
        Checkout.where(status: "open", abandoned_at: nil)
                .where.not(email: [ nil, "" ])
                .where(updated_at: ..threshold)
                .update_all([ "abandoned_at = ?", Time.current ])
      end
    end
  end
end
