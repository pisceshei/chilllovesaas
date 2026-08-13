require "rails_helper"

RSpec.describe Chilllove::TenantResolver do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:downstream) do
    lambda do |env|
      captured_contexts << [ Current.shop, ActsAsTenant.current_tenant, env["chilllove.shop_id"] ]
      [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ]
    end
  end
  let(:captured_contexts) { [] }
  let(:middleware) { described_class.new(downstream, cache:) }

  after do
    Current.reset
    ActsAsTenant.current_tenant = nil
  end

  it "resolves a valid lvh.me subdomain and clears both tenant contexts" do
    shop = create(:shop, subdomain: "chill-love")

    status, = middleware.call(Rack::MockRequest.env_for("https://chill-love.lvh.me/admin"))

    expect(status).to eq(200)
    expect(captured_contexts).to eq([ [ shop, shop, shop.id ] ])
    expect(Current.shop).to be_nil
    expect(ActsAsTenant.current_tenant).to be_nil
  end

  it "routes an active persisted custom domain and rejects an inactive one" do
    active = create(:shop, custom_domain: "merchant.example")
    create(:shop, custom_domain: "suspended.example", status: "suspended")

    active_status, = middleware.call(Rack::MockRequest.env_for("https://merchant.example/admin"))
    inactive_status, = middleware.call(Rack::MockRequest.env_for("https://suspended.example/admin"))

    expect(active_status).to eq(200)
    expect(captured_contexts.first).to eq([ active, active, active.id ])
    expect(inactive_status).to eq(404)
  end

  it "runs inside the Rails Executor and before host authorization and login throttling" do
    middleware_classes = Rails.application.middleware.map(&:klass)
    resolver_index = middleware_classes.index(described_class)

    expect(resolver_index).to be > middleware_classes.index(ActionDispatch::Executor)
    expect(resolver_index).to be < middleware_classes.index(ActionDispatch::HostAuthorization)
    expect(resolver_index).to be < middleware_classes.index(Rack::Attack)
  end

  it "passes the lvh.me base and reserved platform hosts without a tenant" do
    base_status, = middleware.call(Rack::MockRequest.env_for("https://lvh.me/"))
    reserved_status, = middleware.call(Rack::MockRequest.env_for("https://admin.lvh.me/"))

    expect([ base_status, reserved_status ]).to eq([ 200, 200 ])
    expect(captured_contexts).to eq([ [ nil, nil, nil ], [ nil, nil, nil ] ])
  end

  it "requires an explicit canonical base host in production" do
    original_base_host = ENV.delete("CHILLLOVE_BASE_HOST")
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

    expect { described_class.base_host }.to raise_error(KeyError, /CHILLLOVE_BASE_HOST/)
  ensure
    ENV["CHILLLOVE_BASE_HOST"] = original_base_host if original_base_host
  end

  it "prevents shops from claiming a reserved platform subdomain" do
    shop = build(:shop, subdomain: "admin")

    expect(shop).not_to be_valid
    expect(shop.errors[:subdomain]).to include("為平台保留字")
  end

  it "returns 404 for an unknown Host rather than accepting a caller identity" do
    status, headers, body = middleware.call(
      Rack::MockRequest.env_for(
        "https://unknown.lvh.me/admin?shop=1",
        "HTTP_X_SHOP_ID" => "1"
      )
    )

    expect(status).to eq(404)
    expect(headers["Cache-Control"]).to eq("no-store")
    expect(body.join).to eq("找不到這間商店。")
    expect(captured_contexts).to be_empty
  end

  it "uses a five-minute host cache" do
    shop = create(:shop, subdomain: "cached-shop")
    expect(cache).to receive(:fetch)
      .with(described_class.cache_key("cached-shop.lvh.me"), expires_in: 5.minutes)
      .and_call_original

    status, = middleware.call(Rack::MockRequest.env_for("https://cached-shop.lvh.me/"))

    expect(status).to eq(200)
    expect(captured_contexts.first.first).to eq(shop)
  end

  it "clears tenant state even when the downstream app raises" do
    shop = create(:shop, subdomain: "error-shop")
    raising_app = lambda do |_env|
      expect(Current.shop).to eq(shop)
      raise "boom"
    end
    resolver = described_class.new(raising_app, cache:)

    expect do
      resolver.call(Rack::MockRequest.env_for("https://error-shop.lvh.me/"))
    end.to raise_error("boom")
    expect(Current.shop).to be_nil
    expect(ActsAsTenant.current_tenant).to be_nil
  end
end
