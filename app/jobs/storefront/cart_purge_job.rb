# frozen_string_literal: true

module Storefront
  # 90 天未動購物車清理（A3；specs/15 F1 #4；掃描鍵＝carts.ix_carts_updated_at）。
  #
  # 跨租戶批次刪除（platform 維護 job）：行由 FK cascade 帶走；分批避免長鎖。
  class CartPurgeJob < ApplicationJob
    queue_as :background

    BATCH = 1000

    def perform
      cutoff = Limits.fetch(:cart, :purge_days).days.ago
      total = 0
      loop do
        ids = ActsAsTenant.without_tenant do
          Cart.unscoped.where(updated_at: ...cutoff).limit(BATCH).pluck(:id)
        end
        break if ids.empty?

        total += ActsAsTenant.without_tenant { Cart.unscoped.where(id: ids).delete_all }
        break if ids.size < BATCH
      end
      Rails.logger.info("storefront.cart_purge deleted=#{total} cutoff=#{cutoff.iso8601}")
    end
  end
end
