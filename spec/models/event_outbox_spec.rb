# frozen_string_literal: true

require "rails_helper"

# 第 19 包 §6-2：dedupe 語義由 schema 保證的部分，必須有 spec 釘住。
RSpec.describe EventOutbox do
  let!(:shop) { create(:shop, subdomain: "ev-outbox-shop") }

  def build_row(dedupe_key:, **attrs)
    ActsAsTenant.with_tenant(shop) do
      EventOutbox.create!(
        event_id: SecureRandom.uuid, topic: "inventory.adjusted",
        aggregate_type: "InventoryLevel", aggregate_id: 1,
        payload: {}, available_at: Time.current, status: "pending",
        dedupe_key:, **attrs
      )
    end
  end

  it "STATUSES 含 dead（specs/18 F1-5 的 attempts≥8 終態；§4.3-1 裁定）" do
    expect(described_class::STATUSES).to contain_exactly("pending", "published", "failed", "dead")
    expect(described_class::TERMINAL_STATUSES).to contain_exactly("published", "failed", "dead")
  end

  # 🔴 本設計依賴 MySQL「唯一索引允許多列 NULL」（官方 8.4 Reference "This constraint does
  #    not apply to NULL values"）。換 DB 或把 dedupe_key 改 NOT NULL 時，這兩條會先紅。
  it "dedupe_key 為 NULL 的兩列並存（豁免筆與商品事件天生不碰撞）" do
    build_row(dedupe_key: nil)
    expect { build_row(dedupe_key: nil) }.not_to raise_error
  end

  it "dedupe_key 同值的兩列被唯一索引拒絕（合併窗 upsert 的撞鍵面）" do
    build_row(dedupe_key: "inv:1:2:3")
    expect { build_row(dedupe_key: "inv:1:2:3") }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "不同店同 dedupe_key 不互撞（索引第一欄是 shop_id）" do
    shop2 = create(:shop, subdomain: "ev-outbox-shop2")
    build_row(dedupe_key: "inv:1:2:3")
    expect {
      ActsAsTenant.with_tenant(shop2) do
        EventOutbox.create!(event_id: SecureRandom.uuid, topic: "inventory.adjusted",
                            aggregate_type: "InventoryLevel", aggregate_id: 1,
                            payload: {}, available_at: Time.current, status: "pending",
                            dedupe_key: "inv:1:2:3")
      end
    }.not_to raise_error
  end
end
