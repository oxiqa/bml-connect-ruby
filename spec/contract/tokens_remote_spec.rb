# frozen_string_literal: true

require "spec_helper"

# T010/T015/T020 — the remote HTTP contract for the three token operations.
# Every stub URL is derived from client.base_url (research R10): no host is
# hardcoded, so a drift in the client's endpoint constant can never be masked
# by a stale stub.
RSpec.describe BMLConnect::Tokens, "remote contract" do
  let(:client) { build_client }
  let(:tokens) { client.tokens }

  def json(body, status)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  describe "list request shape" do
    it "GETs the nested collection path with the raw Authorization header, no Bearer, no X-App-Id, no body, no query" do
      stub = stub_request(:get, tokens_url(client, "cus_1"))
             .with(headers: { "Authorization" => "test-key" }) do |req|
               expect(req.headers).not_to have_key("X-App-Id")
               expect(req.headers["Authorization"]).not_to include("Bearer")
               expect(req.body.to_s).to be_empty
               true
             end
             .to_return(json({ count: "1", items: [{ id: "tok_1" }] }, 200))

      tokens.list("cus_1")
      expect(stub).to have_been_requested
      expect(a_request(:get, /tokens\?/)).not_to have_been_made
    end
  end

  describe "retrieve request shape" do
    it "GETs /public-customers/{customerId}/tokens/{tokenId}" do
      stub = stub_request(:get, tokens_url(client, "cus_1", "/tok_1")).to_return(json({ id: "tok_1" }, 200))
      tokens.retrieve("cus_1", "tok_1")
      expect(stub).to have_been_requested
    end

    it "maps 404 to NotFoundError and does not retry it" do
      stub = stub_request(:get, tokens_url(client, "cus_1", "/missing")).to_return(json({ message: "no" }, 404))
      expect { tokens.retrieve("cus_1", "missing") }.to raise_error(BMLConnect::NotFoundError)
      expect(stub).to have_been_requested.once
    end
  end

  describe "delete request shape" do
    it "DELETEs /public-customers/{customerId}/tokens/{tokenId} and treats 204 as success" do
      stub = stub_request(:delete, tokens_url(client, "cus_1", "/tok_1")).to_return(status: 204, body: "")
      expect(tokens.delete("cus_1", "tok_1")).to be(true)
      expect(stub).to have_been_requested
    end

    it "maps 400 to ValidationError and does not retry it" do
      stub = stub_request(:delete, tokens_url(client, "cus_1", "/tok_1")).to_return(json({ message: "bad" }, 400))
      expect { tokens.delete("cus_1", "tok_1") }.to raise_error(BMLConnect::ValidationError)
      expect(stub).to have_been_requested.once
    end

    it "retries a transient 503 on delete and then succeeds on 204 (delete is idempotent, R9)" do
      stub = stub_request(:delete, tokens_url(client, "cus_1", "/tok_1"))
             .to_return(json({ message: "upstream" }, 503))
             .to_return(status: 204, body: "")
      expect(tokens.delete("cus_1", "tok_1")).to be(true)
      expect(stub).to have_been_requested.twice
    end
  end

  describe "error mapping" do
    {
      400 => BMLConnect::ValidationError,
      401 => BMLConnect::AuthenticationError,
      403 => BMLConnect::AuthenticationError,
      404 => BMLConnect::NotFoundError,
      409 => BMLConnect::ConflictError
    }.each do |status, error|
      it "maps #{status} to #{error}" do
        stub_request(:get, tokens_url(client, "cus_1", "/tok_1")).to_return(json({ message: "err" }, status))
        expect { tokens.retrieve("cus_1", "tok_1") }.to raise_error(error)
      end
    end

    it "raises AvailabilityError on a connection failure" do
      stub_request(:get, tokens_url(client, "cus_1")).to_raise(Faraday::ConnectionFailed.new("boom"))
      expect { tokens.list("cus_1") }.to raise_error(BMLConnect::AvailabilityError)
    end
  end
end
