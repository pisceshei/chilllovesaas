# frozen_string_literal: true

module Notifications
  # 挽回連結產生器（G6 步 7；官方 abandonedCheckoutUrl 的我方對位）。
  #
  # 形＝<origin>/checkouts/recover/<recovery_token>——recover 端點 302 回
  # 活結帳頁（快照還原＝checkout 本來就落庫）。本尊 URL 形不同
  # （/checkouts/ac/<t>/recover?key=…，89 §8 實測）；我方走 token 單段＝ours。
  module RecoveryUrl
    def self.for(checkout)
      shop = ActsAsTenant.without_tenant { checkout.shop }
      host = ActsAsTenant.with_tenant(shop) { Domain.primary.pick(:host) } ||
             "#{shop.subdomain}.#{Chilllove::TenantResolver.base_host}"
      "https://#{host}/checkouts/recover/#{checkout.recovery_token}"
    end
  end
end
