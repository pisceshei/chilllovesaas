require "rails_helper"

RSpec.describe "Admin API routes", type: :routing do
  it "exposes exactly one dated Admin API route" do
    routes = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_prefix("/")
      next unless path.start_with?("admin/api/")

      {
        verb: route.verb,
        path:,
        controller: route.defaults[:controller],
        action: route.defaults[:action]
      }
    end

    expect(routes).to contain_exactly(
      verb: "POST",
      path: "admin/api/2026-08/graphql.json",
      controller: "admin/api/v202608/graphql",
      action: "execute"
    )
  end

  it "does not expose Active Storage or legacy Admin API REST routes" do
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

    expect(paths.grep(%r{rails/active_storage})).to be_empty
    expect(get: "/admin/api/2026-08/graphql.json").not_to be_routable
    expect(post: "/admin/api/2026-08/graphql.json.xml").not_to be_routable
    expect(post: "/admin/api/v1/graphql.json").not_to be_routable
    expect(get: "/admin/api/v1/graphql.json").not_to be_routable
    expect(get: "/admin/api/2026-08/products.json").not_to be_routable
    expect(get: "/admin/api").not_to be_routable
  end

  it "still routes ordinary client-side admin paths to the SPA shell" do
    expect(get: "/admin/products").to route_to(
      controller: "admin/spa",
      action: "show",
      path: "products"
    )
  end
end
