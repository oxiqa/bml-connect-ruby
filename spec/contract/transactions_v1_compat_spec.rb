# frozen_string_literal: true

require "spec_helper"

# T001/T002 — the backward-compatibility PIN.
#
# This feature modifies released, in-production code. Six call sites in
# msgowl/website depend on the v1 transactions surface. These examples freeze
# that surface's request shape and return type so any regression is impossible
# to miss (FR-010, SC-005). If one of these fails, a released method changed and
# the website is about to break — stop.
RSpec.describe "Transactions v1 backward-compatibility pin" do
  let(:client) { build_client }
  let(:transactions) { client.transactions }

  let(:valid_params) do
    {
      amount: 1000,
      currency: "MVR",
      redirectUrl: "https://merchant.example.mv/return",
      localId: "0000",
      customerReference: "C0000"
    }
  end

  describe "#create (legacy v1, signed) request shape" do
    it "POSTs to the v1 /public/transactions endpoint (derived from base_url)" do
      stub = stub_request(:post, v1_url(client))
             .to_return(json_response({ id: "t1", status: 1 }, 200))
      transactions.create(valid_params)
      expect(stub).to have_been_requested
    end

    it "sends signature, apiVersion, appVersion and signMethod in the body" do
      stub = stub_request(:post, v1_url(client)).with do |req|
        body = JSON.parse(req.body)
        expect(body).to include("signature", "apiVersion", "appVersion", "signMethod")
        expect(body["amount"]).to eq(1000)
        expect(body["currency"]).to eq("MVR")
        true
      end.to_return(json_response({ id: "t1" }, 200))

      transactions.create(valid_params)
      expect(stub).to have_been_requested
    end

    it "returns a Faraday::Response, not a value object" do
      stub_request(:post, v1_url(client)).to_return(json_response({ id: "t1" }, 200))
      resp = transactions.create(valid_params)
      expect(resp).to be_a(Faraday::Response)
      expect(resp.status).to eq(200)
    end

    it "parses the response body with symbol keys" do
      stub_request(:post, v1_url(client)).to_return(json_response({ id: "t1", state: "PENDING" }, 200))
      resp = transactions.create(valid_params)
      expect(resp.body[:id]).to eq("t1")
      expect(resp.body[:state]).to eq("PENDING")
    end
  end

  describe "#get and #list keep their raw-response contract" do
    it "#get returns a Faraday::Response" do
      stub_request(:get, v1_url(client, "/t1")).to_return(json_response({ id: "t1" }, 200))
      expect(transactions.get("t1")).to be_a(Faraday::Response)
    end

    it "#list returns a Faraday::Response" do
      stub_request(:get, v1_url(client)).to_return(json_response([], 200))
      expect(transactions.list).to be_a(Faraday::Response)
    end
  end

  # T002 — the six response fields msgowl/website reads off a v1 response.
  describe "the six fields the website depends on remain reachable" do
    let(:website_body) do
      {
        id: "t_123",
        url: "https://api.uat.merchants.bankofmaldives.com.mv/pay/t_123",
        state: "CONFIRMED",
        expires: "2026-09-10T00:00:00Z",
        merchantId: "m_1",
        paddedCardNumber: "411111******1111"
      }
    end

    it "exposes id, url, state, expires, merchantId, paddedCardNumber via resp.body" do
      stub_request(:post, v1_url(client)).to_return(json_response(website_body, 200))
      body = transactions.create(valid_params).body
      expect(body[:id]).to eq("t_123")
      expect(body[:url]).to include("/pay/t_123")
      expect(body[:state]).to eq("CONFIRMED")
      expect(body[:expires]).to eq("2026-09-10T00:00:00Z")
      expect(body[:merchantId]).to eq("m_1")
      expect(body[:paddedCardNumber]).to eq("411111******1111")
    end
  end
end
