# frozen_string_literal: true

require "rails_helper"

# 🔴 這支只驗一件 request spec **驗不到**的事：巢狀交易下的回滾。
#
# RSpec 的 transactional fixtures 用 `joinable: false` 開測試交易，所以
# request spec 裡 `SaveCollection` 的交易永遠會自己開 SAVEPOINT——
# 不論有沒有 `requires_new:` 都會回滾，兩種寫法在那裡**都是綠的**。
# 生產的巢狀（例如日後套上冪等包裝）是 joinable 的，行為相反。
# 因此這裡顯式包一層 joinable 交易，把生產形態搬進測試。
RSpec.describe Catalog::SaveCollection do
  let(:shop) { create(:shop, subdomain: "nested-tx-shop") }

  it "業務失敗時不留半成品——即使被包在一層 joinable 交易裡" do
    ActsAsTenant.with_tenant(shop) do
      # 這一層是 joinable 的（Rails 預設）；SaveCollection 的交易會併入它，
      # 於是「block 內 raise、block 外 rescue」不再自動回滾——除非 requires_new。
      ActiveRecord::Base.transaction do
        result = described_class.call(shop:, input: {
          title: "Nested Rollback", description_html: "<p>x</p>",
          collection_type: "manual", sort_order: "manual",
          product_ids: [ "not-a-gid" ]
        })

        expect(result.collection).to be_nil
        expect(result.user_errors.map { |row| row[:code] }).to eq([ "INVALID" ])
        expect(Collection.where(shop_id: shop.id, title: "Nested Rollback").count).to eq(0)

        raise ActiveRecord::Rollback
      end
    end
  end
end
