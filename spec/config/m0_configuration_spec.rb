# frozen_string_literal: true

require "spec_helper"
require "yaml"

# 2026-08-13 移植改寫：原骨架自帶 58 行環境分層 limits.yml，本 spec 曾逐值斷言
# 「§9.4 配額被精確複製」。以 main 的 limits.yml（41 個頂層區塊、扁平結構）為
# 正典之後，逐值斷言變成同一份資料的第二份副本（鐵律 7 要防的漂移形態）——
# 值的唯一來源就是檔案本身。本 spec 的職責縮為兩件事：
#   1. brand.yml 仍是單一品牌來源（結構未變，原斷言保留）。
#   2. limits.yml 滿足「代碼消費契約」：扁平結構＋M0 代碼實際讀取的鍵存在且型別正確
#      （GraphqlLimits／rack_attack 在 boot 或首次請求就會炸，本 spec 把炸點提前到測試）。
RSpec.describe "M0 shared configuration" do
  def load_config(name)
    path = File.expand_path("../../config/#{name}.yml", __dir__)
    YAML.safe_load_file(path, aliases: true, permitted_classes: [ Date ])
  end

  it "keeps CHILL LOVE in one brand source for every environment" do
    config = load_config("brand")

    expect(config.fetch("shared")).to eq("name" => "CHILL LOVE")
    %w[development test production].each do |environment|
      expect(config.fetch(environment)).to eq(config.fetch("shared"))
    end
  end

  it "keeps limits.yml flat (no per-environment nesting)" do
    limits = load_config("limits")

    # 上限值是產品限制不是環境設定；application.rb 以扁平方式載入
    # （ActiveSupport::ConfigurationFile，非 config_for）。若有人把它包回
    # shared/development 分層，api 區塊會從頂層消失、GraphqlLimits 全數 KeyError。
    expect(limits).to include("api")
    expect(limits.keys).not_to include("shared", "development", "test", "production")
  end

  it "declares every api limit key the M0 GraphQL layer consumes" do
    api = load_config("limits").fetch("api")

    # GraphqlLimits 的呼叫點清單（keyset_connection／query_type／schema／
    # controller／request_cost）；缺任一鍵＝首次請求 500。
    %w[
      pagination_max_page_size pagination_default_page_size
      array_input_max_items max_query_cost_points object_cost_points
      cost_bucket_capacity cost_restore_points_per_sec
    ].each do |key|
      expect(api[key]).to be_an(Integer), "api.#{key} 缺失或不是整數"
    end

    # 邊界關係本身（不是複製值）：預設頁量不得超過單頁上限。
    expect(api.fetch("pagination_default_page_size"))
      .to be <= api.fetch("pagination_max_page_size")
  end

  it "declares the login throttle keys rack_attack consumes" do
    auth = load_config("limits").fetch("auth")

    %w[admin_login_throttle_per_ip admin_login_throttle_per_account].each do |key|
      rule = auth.fetch(key)
      expect(rule.fetch("limit")).to be_an(Integer)
      expect(rule.fetch("period_seconds")).to be_an(Integer)
    end
  end

  it "declares the media enum keys the M1 media pipeline consumes (第 24 包 B6–B9)" do
    limits = load_config("limits")
    media = limits.fetch("media")
    # MediaStatus 四態（26 包狀態機起點；schema default "ready" 矛盾由 26 包 migration 修）
    expect(media.fetch("statuses")).to eq(%w[uploaded processing ready failed])
    # B8：官方三值照搬＋我方預設（官方未載明預設＝ours）
    expect(media.fetch("duplicate_resolution_modes")).to eq(%w[append_uuid raise_error replace])
    expect(media.fetch("duplicate_resolution_mode_default")).to eq("append_uuid")
    # B9：本批僅圖片可上傳（無轉碼器）
    expect(media.fetch("upload_media_types_enabled")).to eq(%w[image])
    # B7：尺寸正典鍵必須存在（引用斷鏈＝這裡紅，不是消費端上線後才 KeyError）
    media.fetch("size_limit_source_keys").each do |ref|
      section, key = ref.split(".")
      expect(limits.fetch(section).fetch(key)).to be_a(Numeric)
    end
  end

  it "routes Solid Cache to its dedicated development database" do
    config = load_config("cache")

    expect(config.dig("development", "database")).to eq("cache")
    expect(config.dig("production", "database")).to eq("cache")
  end
end
