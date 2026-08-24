# frozen_string_literal: true

require "rails_helper"

# 第 25 包（整合規格 §4-25 判準）：逐消費者投遞——一個消費者失敗不連累另一個重放。
RSpec.describe Events::Relay do
  let(:shop) { create(:shop, subdomain: "ev-deliv-shop") }

  def consumer(name, &block)
    built = Object.new
    built.instance_variable_set(:@consumer_name, name)
    built.instance_variable_set(:@handler, block)
    def built.name = @consumer_name
    def built.call(event) = @handler.call(event)
    built
  end

  def enqueue!(topic: Events::Topics::MEDIA_UPLOADED, **attributes)
    ActsAsTenant.with_tenant(shop) do
      EventOutbox.create!(event_id: SecureRandom.uuid, topic:,
                          aggregate_type: "StoredFile", aggregate_id: 1, payload: {},
                          available_at: Time.current, status: "pending", **attributes)
    end
  end

  def reload(event) = ActsAsTenant.without_tenant { EventOutbox.find(event.id) }

  def deliveries(event)
    ActsAsTenant.without_tenant { EventDelivery.where(event_id: event.event_id).order(:consumer).to_a }
  end

  it "🔴 部分失敗＝done 者不重放：A 成功 B 失敗 ⇒ 事件退避；重試只叫 B；全 done ⇒ published" do
    event = enqueue!
    a_calls = 0
    b_calls = 0
    b_fail = true
    a = consumer("test.a") { |_e| a_calls += 1 }
    b = consumer("test.b") { |_e| b_calls += 1; raise "b down" if b_fail }
    allow(described_class).to receive(:consumers_for).and_return([ a, b ])

    described_class.drain!
    after = reload(event)
    expect(after.status).to eq("pending")
    expect(after.attempts).to eq(1)
    expect(after.last_error).to include("test.b")
    rows = deliveries(event)
    expect(rows.map { |d| [ d.consumer, d.state, d.attempts ] })
      .to eq([ [ "test.a", "done", 0 ], [ "test.b", "pending", 1 ] ])

    # B 恢復後重試：A 不得被重叫（done 跳過＝重放隔離），事件 published、雙 done
    b_fail = false
    described_class.drain!(now: Time.current + 10.seconds)
    expect(a_calls).to eq(1)
    expect(b_calls).to eq(2)
    expect(reload(event).status).to eq("published")
    expect(deliveries(event).map(&:state)).to eq(%w[done done])
  end

  it "零消費者 topic：照舊直接 published、零 delivery 列（P19 語義不變）" do
    # 🔴 media.uploaded 自第 26 包起有真實消費者 ⇒ 本例改用仍無消費者的 topic
    # （複驗：`grep -n REGISTRY -A 3 app/services/events/consumers.rb`）
    event = enqueue!(topic: Events::Topics::PRODUCT_UPDATED)
    described_class.drain!
    expect(reload(event).status).to eq("published")
    expect(deliveries(event)).to be_empty
  end

  it "死信路徑：B 永久壞 ⇒ 事件 dead；A 的 done 帳保留（事後可稽核誰吃過）" do
    limit = Limits.fetch(:events, :outbox_dead_letter_attempts)
    event = enqueue!(attempts: limit - 1)
    a = consumer("test.a") { |_e| nil }
    b = consumer("test.b") { |_e| raise "b permanently down" }
    allow(described_class).to receive(:consumers_for).and_return([ a, b ])

    described_class.drain!
    after = reload(event)
    expect(after.status).to eq("dead")
    rows = deliveries(event)
    expect(rows.find { |d| d.consumer == "test.a" }.state).to eq("done")
    expect(rows.find { |d| d.consumer == "test.b" }.state).to eq("pending")
  end

  it "outbox purge 連動：事件被 purge 時投遞帳經 FK CASCADE 同批消失" do
    event = enqueue!
    a = consumer("test.a") { |_e| nil }
    allow(described_class).to receive(:consumers_for).and_return([ a ])
    described_class.drain!
    expect(deliveries(event)).not_to be_empty

    retention = Limits.fetch(:events, :outbox_retention_days)
    described_class.purge!(now: Time.current + (retention + 1).days)
    ActsAsTenant.without_tenant do
      expect(EventOutbox.where(id: event.id)).to be_empty
      expect(EventDelivery.where(event_id: event.event_id)).to be_empty
    end
  end
end
