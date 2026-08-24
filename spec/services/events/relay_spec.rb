# frozen_string_literal: true

require "rails_helper"

# 第 19 包（docs/plans/2026-08-24-第19包執行規格.md §6-1／§6-3）：relay 核心語義。
# 核心一律直呼 Events::Relay.drain!（不經 queue adapter，§4.7）。
RSpec.describe Events::Relay do
  let!(:shop) { create(:shop, subdomain: "ev-relay-shop") }

  def enqueue!(topic: "products/update", available_at: Time.current, attempts: 0,
               locked_at: nil, status: "pending", dedupe_key: nil)
    ActsAsTenant.with_tenant(shop) do
      EventOutbox.create!(
        event_id: SecureRandom.uuid, topic:, aggregate_type: "Product", aggregate_id: 1,
        payload: { product_id: 1 }, available_at:, attempts:, locked_at:, status:,
        dedupe_key:
      )
    end
  end

  # 具名消費者（第 25 包契約：#name 進 event_deliveries.consumer、#call 投遞）。
  # 🔴 不用 define_singleton_method(&block)——它重綁 self，block 裡的 let 方法
  #    （shop 等）會斷鏈（本包實踩：undefined local variable 'shop'）。
  def consumer(name, &block)
    built = Object.new
    built.instance_variable_set(:@consumer_name, name)
    built.instance_variable_set(:@handler, block)
    def built.name = @consumer_name
    def built.call(event) = @handler.call(event)
    built
  end

  def reload(event) = ActsAsTenant.without_tenant { EventOutbox.find(event.id) }

  describe ".drain!" do
    it "把 pending 標成 published 並記 published_at（零消費者＝投遞即成功，假設 A5）" do
      event = enqueue!
      expect(described_class.drain!).to eq(1)
      after = reload(event)
      expect(after.status).to eq("published")
      expect(after.published_at).to be_present
      expect(after.locked_at).to be_nil
    end

    it "published 時清 dedupe_key（release-on-terminal：窗只在 pending 內的機械保證）" do
      event = enqueue!(dedupe_key: "inv:1:2:3")
      described_class.drain!
      expect(reload(event).dedupe_key).to be_nil
    end

    it "available_at 未到的列不取" do
      event = enqueue!(available_at: 1.hour.from_now)
      expect(described_class.drain!).to eq(0)
      expect(reload(event).status).to eq("pending")
    end

    it "locked_at 在 lock_timeout 內的列不取（別的 worker 正在處理）" do
      event = enqueue!(locked_at: 10.seconds.ago)
      expect(described_class.drain!).to eq(0)
      expect(reload(event).status).to eq("pending")
    end

    it "locked_at 逾時的孤兒被回收重派（specs/18 F1 坑：worker 死掉）" do
      timeout = Limits.fetch(:events, :outbox_lock_timeout_s)
      event = enqueue!(locked_at: (timeout + 5).seconds.ago)
      expect(described_class.drain!).to eq(1)
      expect(reload(event).status).to eq("published")
    end

    it "消費者拋錯 ⇒ attempts+1、available_at 指數退避後移、不標 published" do
      event = enqueue!
      boom = consumer("test.boom") { |_e| raise "boom" }
      allow(described_class).to receive(:consumers_for).and_return([ boom ])
      now = Time.current
      described_class.drain!(now: now)
      after = reload(event)
      expect(after.status).to eq("pending")
      expect(after.attempts).to eq(1)
      expect(after.available_at).to be > now
      expect(after.last_error).to include("boom")
    end

    it "attempts 達 outbox_dead_letter_attempts ⇒ dead 並清 dedupe_key（specs/18 F1-5）" do
      limit = Limits.fetch(:events, :outbox_dead_letter_attempts)
      event = enqueue!(attempts: limit - 1, dedupe_key: "inv:9:9:9")
      allow(described_class).to receive(:consumers_for).and_return([ consumer("test.broken") { |_e| raise "still broken" } ])
      described_class.drain!
      after = reload(event)
      expect(after.status).to eq("dead")
      expect(after.attempts).to eq(limit)
      expect(after.dedupe_key).to be_nil
    end

    it "店 1 的事件拋錯不阻塞店 2，且處理完不殘留 tenant（A 案兩條殘留 spec）" do
      shop2 = create(:shop, subdomain: "ev-relay-shop2")
      event1 = enqueue!
      event2 = ActsAsTenant.with_tenant(shop2) do
        EventOutbox.create!(event_id: SecureRandom.uuid, topic: "products/update",
                            aggregate_type: "Product", aggregate_id: 2,
                            payload: {}, available_at: Time.current, status: "pending")
      end
      calls = []
      failing_once = consumer("test.failing-once") do |e|
        calls << e.shop_id
        raise "shop1 boom" if e.shop_id == shop.id
      end
      allow(described_class).to receive(:consumers_for).and_return([ failing_once ])
      described_class.drain!
      expect(calls).to contain_exactly(shop.id, shop2.id)
      expect(reload(event1).status).to eq("pending")
      expect(reload(event2).status).to eq("published")
      expect(ActsAsTenant.current_tenant).to be_nil
    end
  end

  describe ".purge!" do
    it "刪除保留期外的 published 與 dead（dead 同受 purge＝假設 A2）；期內與 pending 不動" do
      retention = Limits.fetch(:events, :outbox_retention_days)
      old_published = enqueue!(status: "published")
      old_dead = enqueue!(status: "dead")
      fresh = enqueue!(status: "published")
      pending = enqueue!
      ActsAsTenant.without_tenant do
        EventOutbox.where(id: [ old_published.id, old_dead.id ])
                   .update_all(updated_at: (retention + 1).days.ago)
      end
      expect(described_class.purge!).to eq(2)
      remaining = ActsAsTenant.without_tenant { EventOutbox.pluck(:id) }
      expect(remaining).to contain_exactly(fresh.id, pending.id)
    end
  end
end
