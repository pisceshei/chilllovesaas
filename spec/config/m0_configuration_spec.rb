# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe "M0 shared configuration" do
  def load_shared(name)
    path = File.expand_path("../../config/#{name}.yml", __dir__)
    YAML.safe_load_file(path, aliases: true)
  end

  it "keeps CHILL LOVE in one brand source for every environment" do
    config = load_shared("brand")

    expect(config.fetch("shared")).to eq("name" => "CHILL LOVE")
    %w[development test production].each do |environment|
      expect(config.fetch(environment)).to eq(config.fetch("shared"))
    end
  end

  it "copies every quota from docs/research/22 section 9.4 exactly" do
    limits = load_shared("limits").fetch("shared")

    expect(limits.fetch("discounts")).to include(
      "automatic_per_shop" => 25,
      "codes_per_shop" => 20_000_000,
      "automatic_customer_segments" => 5,
      "code_customer_segments" => 100,
      "applicable_resources" => 100
    )
    expect(limits.fetch("products")).to eq(
      "variants" => 2048,
      "options" => 3,
      "media" => 250,
      "description_bytes" => 65_536
    )
    expect(limits.fetch("smart_collections")).to eq("per_shop" => 5000, "conditions" => 60)
    expect(limits.fetch("themes")).to eq("library" => 20, "trials" => 19)
    expect(limits.fetch("locations")).to eq("basic_through_advanced" => 10, "plus" => 200)
    expect(limits.dig("fulfillment_orders", "manual_holds")).to eq(10)
    expect(limits.dig("timeline", "editable_minutes")).to eq(5)
    expect(limits.dig("abandoned_checkouts", "retention_months")).to eq(3)
    expect(limits.dig("exports", "synchronous_rows")).to eq(50)
    expect(limits.fetch("csv")).to eq("megabytes" => 15, "bytes" => 15_728_640)
    expect(limits.dig("text", "title_characters")).to eq(255)
    expect(limits.dig("orders", "starting_number")).to eq(1001)
  end

  it "copies consumed GraphQL boundaries from docs/research/28 sections 0.3 and 0.4" do
    graphql = load_shared("limits").dig("shared", "api", "graphql")

    expect(graphql).to eq(
      "connection_page_size" => 250,
      "input_array_items" => 250,
      "object_cost" => 1,
      "scalar_cost" => 0,
      "mutation_base_cost" => 10,
      "max_request_cost" => 1000,
      "bucket_capacity" => 2000,
      "restore_rate_per_second" => 100
    )
  end

  it "merges the same limits into every Rails environment" do
    config = load_shared("limits")

    %w[development test production].each do |environment|
      expect(config.fetch(environment)).to eq(config.fetch("shared"))
    end
  end

  it "routes Solid Cache to its dedicated development database" do
    config = load_shared("cache")

    expect(config.dig("development", "database")).to eq("cache")
    expect(config.dig("production", "database")).to eq("cache")
  end
end
