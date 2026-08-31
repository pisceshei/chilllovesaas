# frozen_string_literal: true

require "rails_helper"

# 65 §K.8–9（G6-1a 落地）：轉換事件與 P1 失敗事件。
RSpec.describe "Money 轉換可觀測（65 §K.8–9）" do
  around do |example|
    original = Psp.registry
    Psp.registry = Psp::Registry.new(YAML.safe_load_file(Rails.root.join("spec/fixtures/psp_packs/matrix.yml")))
    example.run
    Psp.registry = original
  end

  def capture(name)
    events = []
    subscription = ActiveSupport::Notifications.subscribe(name) { |event| events << event.payload }
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  it "K.8 出向：每次轉換一個事件，欄位含 psp/amount_format/currency/位數/storage_cents/wire_value" do
    events = capture("money.psp_conversion") do
      Money::Storage.from_cents(148_000, "JPY").to_psp_amount(psp: :number_two)
    end
    expect(events.length).to eq(1)
    expect(events.first).to include(
      direction: :outbound, psp: :number_two, amount_format: :decimal_number,
      currency: "JPY", storage_cents: 148_000, decimal_places: 2
    )
  end

  it "K.8 入向：from_psp_amount 也發事件" do
    events = capture("money.psp_conversion") do
      Money.from_psp_amount(1480, currency: "JPY", psp: :iso_minor)
    end
    expect(events.length).to eq(1)
    expect(events.first).to include(direction: :inbound, currency: "JPY", storage_cents: 148_000)
  end

  it "K.9 🔴 轉換失敗 ⇒ P1 失敗事件（severity=P1、error_class 可判）且原例外照樣拋出" do
    failures = capture("money.psp_conversion_failure") do
      expect { Money::Storage.from_cents(148_050, "JPY").to_psp_amount(psp: :iso_minor) }
        .to raise_error(Money::NonIntegralConversion)
    end
    expect(failures.length).to eq(1)
    expect(failures.first).to include(severity: "P1", error_class: "Money::NonIntegralConversion")
  end
end
