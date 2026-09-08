# frozen_string_literal: true

require "spec_helper"
require "json"
require "uri"

# T004 — the enforcement mechanism for Constitution II's anti-stub gate.
#
# This spec reads BML's published contract (reference/Connect-API.json) and
# asserts that every path template the Customers resource can emit, the auth
# header it sends, and its mode->base-URL mapping all exist in that document.
# Because it reads BML's file rather than the library's own stubs, it cannot be
# satisfied by an invented endpoint — the exact failure that shipped 4
# non-existent endpoints in the retired bml_tokenization gem.
RSpec.describe "OpenAPI conformance" do
  let(:doc) do
    path = File.expand_path("../../reference/Connect-API.json", __dir__)
    JSON.parse(File.read(path))
  end

  describe "paths the Customers resource can emit" do
    it "declares the collection path" do
      expect(doc["paths"]).to have_key(BMLConnect::Customers::PATH)
    end

    it "declares the single-customer path template" do
      template = "#{BMLConnect::Customers::PATH}/{customerId}"
      expect(doc["paths"]).to have_key(template)
    end
  end

  describe "paths the Tokens resource can emit" do
    it "declares the token collection path template" do
      expect(doc["paths"]).to have_key("/public-customers/{customerId}/tokens")
    end

    it "declares the single-token path template" do
      expect(doc["paths"]).to have_key("/public-customers/{customerId}/tokens/{tokenId}")
    end

    it "ties the resource's PATH constant to the documented collection template" do
      emitted = format(BMLConnect::Tokens::PATH, customer_id: "{customerId}")
      expect(doc["paths"]).to have_key(emitted)
    end
  end

  describe "authentication scheme" do
    let(:scheme) { doc.dig("components", "securitySchemes", "Authorization") }
    let(:client) { build_client }

    it "is an apiKey header named Authorization" do
      expect(scheme["type"]).to eq("apiKey")
      expect(scheme["in"]).to eq("header")
      expect(scheme["name"]).to eq("Authorization")
    end

    it "sends the raw key under the documented header name, with no Bearer prefix" do
      header_name = scheme["name"]
      value = client.http_client.headers[header_name]
      expect(value).to eq("test-key")
      expect(value).not_to include("Bearer")
    end

    it "sends no X-App-Id header (absent from the document)" do
      expect(client.http_client.headers).not_to have_key("X-App-Id")
      expect(File.read(File.expand_path("../../reference/Connect-API.json", __dir__)))
        .not_to include("X-App-Id")
    end
  end

  describe "mode to base-URL mapping matches servers[]" do
    let(:servers) { doc["servers"] }

    def host_for(description)
      server = servers.find { |s| s["description"] == description }
      URI.parse(server["url"]).host
    end

    it "maps production to the PRODUCTION server host" do
      client = build_client(mode: "production")
      expect(URI.parse(client.base_url).host).to eq(host_for("PRODUCTION"))
    end

    it "maps sandbox to the DEVELOPMENT (UAT) server host" do
      client = build_client(mode: "sandbox")
      expect(URI.parse(client.base_url).host).to eq(host_for("DEVELOPMENT"))
    end
  end
end
