# frozen_string_literal: true

namespace :inventory do
  desc "逐店對帳 ledger ↔ 現值（有差異則列出並以非零碼結束；給 nightly cron）"
  task reconcile: :environment do
    total = 0
    Shop.find_each do |shop|
      discrepancies = ActsAsTenant.with_tenant(shop) { Inventory::Reconcile.call(shop:) }
      next if discrepancies.empty?

      total += discrepancies.length
      puts "shop=#{shop.subdomain}:"
      discrepancies.each { |d| puts "  [#{d.kind}] #{d.detail}" }
    end
    if total.zero?
      puts "reconcile OK：0 差異"
    else
      abort "reconcile FAILED：#{total} 筆差異"
    end
  end
end
