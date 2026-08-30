# frozen_string_literal: true

require "rails_helper"

# 頁級快取單元格（63 §D.3／§D.5）。
#
# 🔴 假綠殺手：
#   C2 volatile ⇒ TTL 60s（殺：旗標沒接到 TTL——Ella 商品卡庫存數字最長陳舊一天）
#   C3 時間值防呆（殺：raw pick 回字串時 to_i＝2026——全部 stamp 同值、永遠舊快取）
#   C4 只快取 200（殺：404 也快取＝敵手以亂 handle 灌爆儲存）
RSpec.describe Storefront::PageCache do
  let(:shop) { create(:shop) }
  let(:market) { ActsAsTenant.with_tenant(shop) { Market.find_by!(is_primary: true) } }
  let(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "T", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let(:memory) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(memory) }

  def result(status: 200, volatile: false)
    ThemeEngine::PageRenderer::Result.new(status:, html: "<x>", page_type: "index", volatile:)
  end

  def fetch(path: "/", volatile: false, status: 200)
    described_class.fetch(shop:, theme:, market:, locale_tag: "en", path:, params: {}) do
      result(status:, volatile:)
    end
  end

  it "C1 命中不再執行渲染 block；寫入用 DEFAULT_TTL" do
    calls = 0
    2.times do
      described_class.fetch(shop:, theme:, market:, locale_tag: "en", path: "/", params: {}) do
        calls += 1
        result
      end
    end
    expect(calls).to eq(1)
  end

  it "C2 🔴 volatile 頁 ⇒ TTL 壓到 volatile_section_ttl_seconds（60）" do
    expect(memory).to receive(:write)
      .with(anything, anything, hash_including(expires_in: 60.seconds))
      .and_call_original
    fetch(volatile: true)
  end

  it "C3 🔴 time_stamp：Time 取毫秒；字串正確解析（不是 String#to_i 的 2026）；nil＝0" do
    t = Time.zone.parse("2026-08-31 10:00:00.123")
    expect(described_class.time_stamp(t)).to eq((t.to_f * 1000).to_i)
    expect(described_class.time_stamp("2026-08-31 10:00:00")).to be > 1_000_000_000_000
    expect(described_class.time_stamp("2026-08-31 10:00:00")).not_to eq(2026)
    expect(described_class.time_stamp(nil)).to eq(0)
  end

  it "C4 🔴 404 不落快取（block 每次都執行）" do
    calls = 0
    2.times do
      described_class.fetch(shop:, theme:, market:, locale_tag: "en", path: "/products/none", params: {}) do
        calls += 1
        result(status: 404)
      end
    end
    expect(calls).to eq(2)
  end

  it "C5 key 維度：locale／market stamp／params 任一變即不同 key" do
    base = described_class.key_for(shop:, theme:, market:, locale_tag: "en", path: "/", params: {})
    expect(described_class.key_for(shop:, theme:, market:, locale_tag: "zh-Hant", path: "/", params: {}))
      .not_to eq(base)
    expect(described_class.key_for(shop:, theme:, market:, locale_tag: "en", path: "/", params: { "variant" => "9" }))
      .not_to eq(base)
    travel(1.second) { market.touch }
    expect(described_class.key_for(shop:, theme:, market: market.reload, locale_tag: "en", path: "/", params: {}))
      .not_to eq(base)
  end
end
