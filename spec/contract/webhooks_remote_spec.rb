# frozen_string_literal: true

require "spec_helper"

# T016 [US1] — the one outbound call this feature makes, and its conformance to
# the published document.
#
# Constitution II/III: every stub URL is interpolated from client.base_url, so a
# drift in an endpoint constant cannot be masked by a stale stub, and the path is
# asserted against reference/Connect-API.json rather than against our belief.
RSpec.describe "webhook verifying retrieve — remote contract" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  it "issues GET {base_url}transactions/{id} — the documented retrieve path" do
    stub = stub_request(:get, txn_url(client, "txn_1"))
           .to_return(json_response(transaction_body(state: "PAID"), 200))

    webhooks.handle(body: json_body, headers: json_headers)

    expect(stub).to have_been_requested.once
  end

  # FR-017: the raw Authorization API key. No Bearer, no X-App-Id — matching
  # every other resource in this library.
  it "authenticates with the raw Authorization API key, with no Bearer and no X-App-Id" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

    webhooks.handle(body: json_body, headers: json_headers)

    expect(
      a_request(:get, txn_url(client, "txn_1")).with do |req|
        req.headers["Authorization"] == "test-key" &&
          !req.headers["Authorization"].to_s.start_with?("Bearer") &&
          !req.headers.key?("X-App-Id")
      end
    ).to have_been_made.once
  end

  # FR-017: environment selection with no code change.
  it "targets whichever environment the client selects" do
    production = BMLConnect::Client.new(api_key: "k", app_id: "a", mode: "production",
                                        options: { retry_backoff: 0, webhook_recheck_delay: 0 })
    stub_request(:get, txn_url(production, "txn_1"))
      .to_return(json_response(transaction_body(state: "PAID"), 200))

    production.webhooks.handle(body: json_body, headers: json_headers)

    expect(a_request(:get, txn_url(production, "txn_1"))).to have_been_made.once
    expect(txn_url(production, "txn_1")).to include("api.merchants.bankofmaldives.com.mv")
  end

  it "sends no request body on the retrieve" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
    webhooks.handle(body: json_body, headers: json_headers)

    expect(a_request(:get, txn_url(client, "txn_1")).with { |req| req.body.to_s.empty? })
      .to have_been_made.once
  end

  # FR-018: traceable to the published document. The inbound side has no endpoint
  # to conform to — which is exactly why FR-019/SC-011 make a real UAT delivery a
  # release gate rather than a nice-to-have.
  describe "conformance to reference/Connect-API.json" do
    let(:document) { JSON.parse(File.read(File.expand_path("../../reference/Connect-API.json", __dir__))) }

    it "implements a documented path and method" do
      operation = document.dig("paths", "/public/transactions/{transactionId}", "get")
      expect(operation).not_to be_nil
      expect(operation["operationId"]).to eq("get-public-transactions-transactionId")
    end

    it "sends nothing to the undocumented callback — the library only receives" do
      expect(document["paths"].keys).to include("/public/webhooks")
      # Registration is documented and deliberately out of scope; this feature
      # must not call it.
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      webhooks.handle(body: json_body, headers: json_headers)

      expect(a_request(:post, URI.join(client.base_url, "/public/webhooks").to_s)).not_to have_been_made
      expect(a_request(:delete, URI.join(client.base_url, "/public/webhooks").to_s)).not_to have_been_made
    end
  end
end
